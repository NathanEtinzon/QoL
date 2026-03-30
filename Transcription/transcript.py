import argparse
import sys
import time
from pathlib import Path
from datetime import datetime

from faster_whisper import WhisperModel
from colorama import Fore, Style, init

# Initialisation colorama (Windows)
init(autoreset=True)


# =========================
# LOGGING
# =========================
def now():
    return datetime.now().strftime("%H:%M:%S")


def log_info(msg):
    print(f"{Fore.CYAN}[{now()}][INFO]{Style.RESET_ALL} {msg}")


def log_warn(msg):
    print(f"{Fore.YELLOW}[{now()}][WARN]{Style.RESET_ALL} {msg}")


def log_error(msg):
    print(f"{Fore.RED}[{now()}][ERROR]{Style.RESET_ALL} {msg}")


def log_success(msg):
    print(f"{Fore.GREEN}[{now()}][SUCCESS]{Style.RESET_ALL} {msg}")


def log_section(msg):
    print(f"\n{Fore.MAGENTA}{'='*70}")
    print(f"{msg}")
    print(f"{'='*70}{Style.RESET_ALL}")


# =========================
# UTILS
# =========================
def ask_yes_no(prompt: str) -> bool:
    while True:
        answer = input(prompt).strip().lower()
        if answer in ("y", "yes", "o", "oui"):
            return True
        if answer in ("n", "no", "non"):
            return False
        log_warn("Réponse invalide. Merci de répondre par Y/N.")


def format_seconds(seconds: float) -> str:
    seconds = int(seconds)
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


# =========================
# MAIN
# =========================
def main():
    parser = argparse.ArgumentParser(
        description="Outil de transcription audio basé sur Faster-Whisper (GPU prioritaire, fallback CPU possible)"
    )

    parser.add_argument(
        "-i", "--input",
        required=True,
        help="Chemin vers le fichier audio à transcrire (ex: .mp3, .wav)"
    )

    parser.add_argument(
        "-o", "--output",
        default="transcription.txt",
        help="Fichier de sortie (défaut : transcription.txt)"
    )

    parser.add_argument(
        "-m", "--model",
        default="small",
        help="Modèle Whisper (tiny, base, small, medium, large-v3)"
    )

    parser.add_argument(
        "-l", "--language",
        default="fr",
        help="Langue de l'audio (fr par défaut, mettre 'auto' pour détection)"
    )

    # Affichage aide si aucun argument
    if len(sys.argv) == 1:
        parser.print_help()
        print("\nExemple :")
        print("python transcript.py -i \"C:\\audio.mp3\" -o resultat.txt -m medium")
        sys.exit(1)

    args = parser.parse_args()

    audio_path = Path(args.input)
    output_path = Path(args.output)

    if not audio_path.exists():
        log_error(f"Fichier introuvable : {audio_path}")
        sys.exit(1)

    language = None if args.language == "auto" else args.language

    log_section("Démarrage du script")

    log_info(f"Fichier source      : {audio_path}")
    log_info(f"Fichier de sortie  : {output_path}")
    log_info(f"Modèle             : {args.model}")
    log_info(f"Langue             : {args.language}")

    # =========================
    # INIT GPU
    # =========================
    try:
        log_info("Initialisation du modèle sur GPU (CUDA)...")
        model = WhisperModel(args.model, device="cuda", compute_type="float16")
        execution_device = "GPU"
        log_success("Modèle chargé sur GPU.")
    except Exception as gpu_error:
        log_error("Échec de l'initialisation GPU.")
        log_warn(f"Détail : {gpu_error}")

        fallback = ask_yes_no(
            f"{Fore.YELLOW}[QUESTION]{Style.RESET_ALL} Basculer sur CPU ? (Y/N) : "
        )

        if not fallback:
            log_error("Arrêt demandé par l'utilisateur.")
            sys.exit(1)

        try:
            log_info("Initialisation du modèle sur CPU...")
            model = WhisperModel(args.model, device="cpu", compute_type="int8")
            execution_device = "CPU"
            log_success("Modèle chargé sur CPU.")
        except Exception as cpu_error:
            log_error("Échec de l'initialisation CPU.")
            log_error(cpu_error)
            sys.exit(1)

    # =========================
    # TRANSCRIPTION
    # =========================
    log_section(f"Transcription en cours ({execution_device})")

    start_time = time.time()

    try:
        segments_generator, info = model.transcribe(
            str(audio_path),
            beam_size=5,
            language=language
        )

        log_info(f"Langue détectée : {info.language}")
        log_info(f"Probabilité     : {info.language_probability:.2f}")

        if getattr(info, "duration", None):
            log_info(f"Durée audio     : {format_seconds(info.duration)}")

        log_info("Décodage des segments...")
        segments = list(segments_generator)

    except Exception as e:
        log_error("Erreur lors de la transcription.")
        log_error(e)
        sys.exit(1)

    transcription_time = time.time() - start_time

    log_info(f"Segments détectés : {len(segments)}")
    log_info(f"Temps traitement  : {transcription_time:.2f}s")

    # =========================
    # ÉCRITURE
    # =========================
    log_info("Écriture du fichier...")

    try:
        with open(output_path, "w", encoding="utf-8") as f:
            for segment in segments:
                f.write(
                    f"[{segment.start:.2f}s -> {segment.end:.2f}s] {segment.text.strip()}\n"
                )
    except Exception as e:
        log_error("Erreur écriture fichier.")
        log_error(e)
        sys.exit(1)

    total_time = time.time() - start_time

    log_section("Fin du traitement")

    log_success(f"Transcription générée : {output_path.resolve()}")
    log_info(f"Durée totale : {total_time:.2f}s")
    log_info(f"Mode utilisé : {execution_device}")


if __name__ == "__main__":
    main()