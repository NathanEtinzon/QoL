# Script de transcription audio (Faster-Whisper)

Petit Script Python permettant de transcrire des fichiers audio (MP3, WAV, etc.) en texte à l’aide de **Faster-Whisper**, avec support **GPU (CUDA)** et fallback automatique vers **CPU**.

---

## Fonctionnalités

- Transcription audio via Whisper (OpenAI)
- Priorité GPU (CUDA) avec fallback CPU interactif
- Interface CLI simple et en français
- Logs colorés et lisibles
- Détection automatique ou forcée de la langue
- Gestion robuste des erreurs
- Compatible Windows / Linux

---

## Prérequis

- Python 3.9+
- pip

### Dépendances Python

```bash
pip install faster-whisper colorama
```

---

## Option GPU (facultatif mais recommandé)

Pour utiliser le GPU :
- Carte NVIDIA compatible
- CUDA Toolkit 12 installé
- Drivers NVIDIA à jour

Vérification :

```bash
nvidia-smi
```

⚠️ Si CUDA n’est pas disponible, le script proposera automatiquement de basculer en CPU.

---

## Utilisation

### Commande de base

```bash
python transcript.py -i "chemin/vers/audio.mp3"
```

### Exemple complet

```bash
python transcript.py -i "C:\audio\podcast.mp3" -o resultat.txt -m medium -l fr
```

---

## Options disponibles

|Option|Description|
|---|---|
|`-i`, `--input`|Chemin du fichier audio (obligatoire)|
|`-o`, `--output`|Fichier de sortie (défaut : transcription.txt)|
|`-m`, `--model`|Modèle Whisper (tiny, base, small, medium, large-v3)|
|`-l`, `--language`|Langue (ex: fr) ou `auto`|

---

## Modèles disponibles

|Modèle|Qualité|Performance|
|---|---|---|
|tiny|faible|très rapide|
|base|moyenne|rapide|
|small|bonne|équilibré|
|medium|très bonne|plus lent|
|large-v3|excellente|lent|

---

## Exemple de sortie

```text
[12.34s -> 15.67s] Bonjour et bienvenue sur ce podcast...
[15.67s -> 18.90s] Aujourd’hui nous allons parler de cybersécurité...
```

---

## Logs

Le script affiche des logs colorés :

- INFO → bleu
- WARN → jaune
- ERROR → rouge
- SUCCESS → vert

Exemple :

```text
[INFO] Initialisation du modèle sur GPU...
[ERROR] CUDA non disponible
[QUESTION] Basculer sur CPU ? (Y/N)
```

---

## Bonnes pratiques

- Privilégier le traitement local pour données sensibles
- Ne pas exécuter en administrateur sauf nécessité
- Vérifier les dépendances CUDA si utilisation GPU
- Stocker les résultats dans un environnement sécurisé

---

## Limitations

- Performance dépendante du matériel
- GPU nécessite configuration CUDA correcte
- Pas de diarisation (séparation des speakers)
- Pas de nettoyage automatique du texte

## Licence

**GNU General Public License v3.0**