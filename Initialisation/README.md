# Script d'initialisation Debian

Script d’initialisation pour déployer rapidement un environnement Debian prêt à l’usage avec mes configurations standards (shell, outils, Docker, SSH).

## Objectif

Ce script permet de :

* automatiser la configuration post-installation d’un système Debian
* standardiser un environnement de travail
* gagner du temps lors du provisioning (VM, serveur, lab)

## Fonctionnalités

### Installation des paquets essentiels

Le script installe automatiquement :

* git
* curl
* net-tools
* ca-certificates
* zsh
* gpg
* sudo
* openssh-server
* docker (via dépôt officiel)

### Configuration du shell

* Passage en **zsh**
* Installation de **Oh My Zsh**
* Plugins :

  * git
  * sudo
  * zsh-autosuggestions
  * zsh-syntax-highlighting
* Thème **Powerlevel10k (p10k)**

### Configuration SSH

* Activation du service SSH
* Configuration de base pour accès distant

### Renommage de la machine

Possibilité de renommer le hostname via option CLI.

## Utilisation

### Exécution standard (recommandé)

```bash
sudo ./init.sh
```

### Exécution en root

```bash
./init.sh
```

### Renommer la machine

```bash
./init.sh --rename mon-hostname
```

## Prérequis

* Debian (testé sur Debian 11/12)
* Accès root ou sudo
* Connexion Internet

## Cas d’usage

* Déploiement rapide VM (lab, école, tests)
* Bootstrap serveur perso
* Environnement de dev standardisé
* Formation / TP

## Licence

**GNU General Public License v3.0**