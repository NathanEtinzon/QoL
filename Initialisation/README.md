# Script d'initialisation Debian

Script d'initialisation non interactif pour deployer rapidement un environnement Debian pret a l'usage avec des configurations standards : shell, outils, Docker et SSH.

## Objectif

Ce script permet de :

* automatiser la configuration post-installation d'un systeme Debian
* standardiser un environnement de travail
* gagner du temps lors du provisioning (VM, serveur, lab)
* eviter les prompts bloquants pendant l'installation

## Fonctionnalites

### Installation des paquets essentiels

Le script installe automatiquement les outils necessaires selon les options activees :

* git
* curl
* wget
* net-tools
* ca-certificates
* zsh
* gpg
* sudo
* openssh-server
* docker (via depot officiel)

Les commandes apt sont executees en mode non interactif avec :

* `DEBIAN_FRONTEND=noninteractive`
* `APT_LISTCHANGES_FRONTEND=none`
* `NEEDRESTART_MODE=a`
* conservation automatique des fichiers de configuration existants via options `dpkg`

### Configuration du shell

* Installation de **Oh My Zsh**
* Plugins :
  * git
  * sudo
  * zsh-autosuggestions
  * zsh-syntax-highlighting
* Theme **Powerlevel10k**
* Recuperation automatique de `.p10k.zsh` via `wget`

La configuration Powerlevel10k par defaut est telechargee depuis :

```bash
https://raw.githubusercontent.com/NathanEtinzon/QoL/main/Initialisation/.p10k.zsh
```

L'URL peut etre surchargee :

```bash
sudo env P10K_CONFIG_URL="https://example.org/.p10k.zsh" ./init.sh --user nathan
```

### Configuration SSH

* Installation et activation du service SSH
* `PermitRootLogin no`
* `PermitEmptyPasswords no`
* `PasswordAuthentication no` par defaut

Les actions sensibles sont explicites :

* `--ssh-password-auth yes` active l'authentification SSH par mot de passe
* `--restrict-ssh-user` ajoute `AllowUsers <user>`

### Actions sensibles opt-in

Par defaut, le script ne modifie pas les points suivants :

* pas de `NOPASSWD: ALL`
* pas de changement de shell par defaut avec `chsh`
* pas de restriction `AllowUsers`
* pas d'activation SSH password auth

Options disponibles :

```bash
--enable-nopasswd-sudo
--set-default-shell
--ssh-password-auth yes
--restrict-ssh-user
```

## Utilisation

### Execution standard

```bash
sudo ./init.sh --user nathan
```

### Renommer la machine

```bash
sudo ./init.sh --user nathan --rename debian-lab01
```

### Installation complete avec actions sensibles explicites

```bash
sudo ./init.sh \
  --user nathan \
  --rename debian-lab01 \
  --enable-nopasswd-sudo \
  --set-default-shell \
  --ssh-password-auth no \
  --restrict-ssh-user
```

### Desactiver certains blocs

```bash
sudo ./init.sh --user nathan --skip-docker
sudo ./init.sh --user nathan --skip-ssh
sudo ./init.sh --user nathan --skip-zsh
```

### Aide

```bash
sudo ./init.sh --help
```

## Options

* `--user <name>` : utilisateur cible. Par defaut : `SUDO_USER`, puis `user`
* `--rename <hostname>` : renomme la machine
* `--skip-zsh` : ignore Zsh, Oh My Zsh et Powerlevel10k
* `--skip-docker` : ignore Docker
* `--skip-ssh` : ignore SSH
* `--skip-chsh` : ne change pas le shell par defaut, comportement par defaut
* `--set-default-shell` : passe le shell par defaut a zsh
* `--enable-nopasswd-sudo` : accorde `NOPASSWD: ALL` a l'utilisateur cible
* `--ssh-password-auth <yes|no>` : configure `PasswordAuthentication`, par defaut `no`
* `--restrict-ssh-user` : ajoute `AllowUsers <user>` dans `sshd_config`

## Prerequis

* Debian ou derive Debian (teste sur Debian 11/12)
* Acces root ou sudo
* Connexion Internet

## Cas d'usage

* Deploiement rapide VM (lab, ecole, tests)
* Bootstrap serveur personnel
* Environnement de developpement standardise
* Formation / TP

## Licence

**GNU General Public License v3.0**
