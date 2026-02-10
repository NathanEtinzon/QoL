#!/usr/bin/env bash

# ---------------------------------------------------------
# init.sh - Debian init script for my usual configuration |
# ---------------------------------------------------------

# > Rename machine if needed
# > Install the following packages :
#   - git
#   - curl
#   - net-tools
#   - ca-certificates
#   - zsh
#   - gpg
#   - sudo
#   - docker
#   - sudo
#   - openssh-server
# > Configure the shell :
#   - zsh
#   - oh-my-zsh
#   - plugins
#       - git
#       - sudo
#       - zsh-autosuggestions
#       - zsh-syntax-highlighting
#   - p10k
# > Configure ssh
#
# Usage:
#   sudo ./init.sh
#   sudo ./init.sh --rename myhost

set -Eeuo pipefail
IFS=$'\n\t'
umask 027

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "This script must be run as root (use sudo)."
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

is_debian_like() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *"debian"* ]]
}

confirm_or_exit() {
  local answer=""
  echo "You are about to initialise this machine."
  echo "This will install packages, configure Docker repo, configure SSH, grant NOPASSWD sudo to current user,"
  echo "add current user to docker group, and configure Zsh for root and current user."
  read -r -p "Continue? [y/N] " answer
  answer="${answer,,}"
  [[ "$answer" == "y" || "$answer" == "yes" ]] || die "Aborted by user."
}

apt_install() {
  local pkgs=("$@")
  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if ((${#missing[@]})); then
    info "Installing packages: ${missing[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
  else
    info "Packages already installed: ${pkgs[*]}"
  fi
}

valid_hostname() {
  local hn="$1"
  [[ ${#hn} -le 253 ]] || return 1
  [[ "$hn" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

set_hostname_safe() {
  local new_hn="$1"
  valid_hostname "$new_hn" || die "Invalid hostname: '$new_hn'"

  local old_hn
  old_hn="$(hostname)"

  if [[ "$old_hn" == "$new_hn" ]]; then
    info "Hostname already set to '$new_hn'"
    return 0
  fi

  info "Renaming host: '$old_hn' -> '$new_hn'"
  cp -a /etc/hosts "/etc/hosts.bak.$(date +%F_%H%M%S)"

  hostnamectl set-hostname "$new_hn"
  echo "$new_hn" > /etc/hostname

  if grep -qE '^\s*127\.0\.1\.1\s+' /etc/hosts; then
    sed -i -E "s/^\s*127\.0\.1\.1\s+.*/127.0.1.1\t${new_hn}/" /etc/hosts
  else
    printf "\n127.0.1.1\t%s\n" "$new_hn" >> /etc/hosts
  fi

  info "Hostname renamed to '$new_hn'"
}

install_docker_debian() {
  have_cmd curl || die "curl is required for Docker install step."
  have_cmd gpg  || die "gpg is required for Docker key handling."

  # shellcheck disable=SC1091
  . /etc/os-release
  local codename="${VERSION_CODENAME:-}"
  [[ -n "$codename" ]] || die "VERSION_CODENAME is empty; cannot configure Docker repo."

  if dpkg -s docker-ce >/dev/null 2>&1; then
    info "Docker already installed (docker-ce present). Skipping."
    return 0
  fi

  info "Configuring Docker apt repository (Debian: $codename)"
  install -m 0755 -d /etc/apt/keyrings

  local tmpdir
  tmpdir="$(mktemp -d)"
  local key_tmp="${tmpdir}/docker.asc"
  local keyring="/etc/apt/keyrings/docker.gpg"
  local source_list="/etc/apt/sources.list.d/docker.sources"

  curl -fsSL "https://download.docker.com/linux/debian/gpg" -o "$key_tmp"
  gpg --batch --quiet --show-keys "$key_tmp" >/dev/null 2>&1 || die "Downloaded Docker GPG key is not a valid public key."

  gpg --batch --yes --dearmor -o "$keyring" "$key_tmp"
  chmod 0644 "$keyring"

  cat > "$source_list" <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${codename}
Components: stable
Signed-By: ${keyring}
EOF

  apt-get update -y
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  if have_cmd systemctl; then
    systemctl enable --now docker >/dev/null 2>&1 || info "systemctl enable/start docker failed (maybe not systemd environment)."
  fi

  rm -rf "$tmpdir"
  info "Docker installation complete."
}

ensure_user_nopasswd_sudo() {
  local user="$1"
  [[ -n "$user" ]] || die "ensure_user_nopasswd_sudo: missing user"
  [[ "$user" != "root" ]] || { info "User is root; skipping sudoers grant."; return 0; }

  if ! dpkg -s sudo >/dev/null 2>&1; then
    info "Installing sudo package..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo
  fi

  local sudoers_file="/etc/sudoers.d/90-${user}-nopasswd"
  local line="${user} ALL=(ALL) NOPASSWD: ALL"

  info "Granting passwordless sudo to user '$user' via $sudoers_file"
  printf "%s\n" "$line" > "$sudoers_file"
  chmod 0440 "$sudoers_file"

  visudo -cf "$sudoers_file" >/dev/null 2>&1 || die "visudo validation failed for $sudoers_file"
  info "sudoers entry validated."
}

ensure_user_in_docker_group() {
  local user="$1"
  [[ -n "$user" ]] || die "ensure_user_in_docker_group: missing user"
  [[ "$user" != "root" ]] || { info "User is root; skipping docker group membership."; return 0; }

  if ! getent group docker >/dev/null 2>&1; then
    info "Creating 'docker' group"
    groupadd docker
  fi

  if id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
    info "User '$user' is already in group 'docker'"
  else
    info "Adding user '$user' to group 'docker'"
    usermod -aG docker "$user"
    info "User '$user' added to group 'docker' (new session required to take effect)"
  fi
}

set_sshd_directive() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+" "$file"; then
    sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "$file"
  else
    printf "\n%s %s\n" "$key" "$value" >> "$file"
  fi
}

set_sshd_allowusers() {
  local file="$1"
  local user="$2"
  [[ -n "$user" ]] || die "set_sshd_allowusers: missing user"

  if grep -qE "^[[:space:]]*AllowUsers[[:space:]]+" "$file"; then
    sed -i -E "s|^[[:space:]]*AllowUsers[[:space:]]+.*|AllowUsers ${user}|" "$file"
  else
    printf "\nAllowUsers %s\n" "$user" >> "$file"
  fi
}

configure_ssh() {
  local current_user="$1"
  [[ -n "$current_user" ]] || die "configure_ssh: missing current user (SUDO_USER)."

  apt_install openssh-server

  local cfg="/etc/ssh/sshd_config"
  [[ -f "$cfg" ]] || die "sshd_config not found at $cfg"

  info "Backing up sshd_config"
  cp -a "$cfg" "${cfg}.bak.$(date +%F_%H%M%S)"

  set_sshd_directive "$cfg" "PermitRootLogin" "no"
  set_sshd_directive "$cfg" "PasswordAuthentication" "yes"
  set_sshd_directive "$cfg" "PermitEmptyPasswords" "no"
  set_sshd_allowusers "$cfg" "$current_user"

  if have_cmd systemctl; then
    info "Enabling and restarting ssh service"
    systemctl enable ssh
    systemctl restart ssh
  else
    info "systemctl not available; skipping ssh service enable/restart."
  fi
}

configure_zsh_for_account() {
  local user="$1"
  local home="$2"

  [[ -n "$user" && -n "$home" ]] || die "configure_zsh_for_account: missing user/home."
  [[ -d "$home" ]] || die "Home directory not found: $home"

  local omz_dir="${home}/.oh-my-zsh"
  local zshrc="${home}/.zshrc"
  local zsh_custom="${omz_dir}/custom"

  info "Configuring Zsh/oh-my-zsh for '$user' (home: $home)"

  if [[ "$user" == "root" ]]; then
    mkdir -p "${zsh_custom}/plugins" "${zsh_custom}/themes"
  else
    sudo -u "$user" mkdir -p "${zsh_custom}/plugins" "${zsh_custom}/themes"
  fi

  if [[ ! -d "$omz_dir" ]]; then
    if [[ "$user" == "root" ]]; then
      git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$omz_dir"
    else
      sudo -u "$user" git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$omz_dir"
    fi
  else
    info "oh-my-zsh already present for '$user'."
  fi

  if [[ ! -f "$zshrc" ]]; then
    if [[ "$user" == "root" ]]; then
      cp "${omz_dir}/templates/zshrc.zsh-template" "$zshrc"
    else
      sudo -u "$user" cp "${omz_dir}/templates/zshrc.zsh-template" "$zshrc"
    fi
  fi

  local p1="${zsh_custom}/plugins/zsh-syntax-highlighting"
  local p2="${zsh_custom}/plugins/zsh-autosuggestions"
  local th="${zsh_custom}/themes/powerlevel10k"

  if [[ ! -d "$p1" ]]; then
    if [[ "$user" == "root" ]]; then
      git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$p1"
    else
      sudo -u "$user" git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$p1"
    fi
  fi

  if [[ ! -d "$p2" ]]; then
    if [[ "$user" == "root" ]]; then
      git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$p2"
    else
      sudo -u "$user" git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$p2"
    fi
  fi

  if [[ ! -d "$th" ]]; then
    if [[ "$user" == "root" ]]; then
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$th"
    else
      sudo -u "$user" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$th"
    fi
  fi

  if [[ "$user" == "root" ]]; then
    bash -c "
      set -euo pipefail
      zshrc='$zshrc'
      omz='$omz_dir'

      if grep -qE '^ZSH=' \"\$zshrc\"; then
        sed -i -E \"s|^ZSH=.*|ZSH=\\\"$omz\\\"|\" \"\$zshrc\"
      else
        printf '\\nZSH=\"%s\"\\n' \"$omz\" >> \"\$zshrc\"
      fi

      if grep -qE '^ZSH_THEME=' \"\$zshrc\"; then
        sed -i -E 's|^ZSH_THEME=.*|ZSH_THEME=\"powerlevel10k/powerlevel10k\"|' \"\$zshrc\"
      else
        printf '\\nZSH_THEME=\"powerlevel10k/powerlevel10k\"\\n' >> \"\$zshrc\"
      fi

      if ! grep -qE '^plugins=\\(' \"\$zshrc\"; then
        printf '\\nplugins=(git)\\n' >> \"\$zshrc\"
      fi

      required='git sudo zsh-autosuggestions zsh-syntax-highlighting'
      current=\$(grep -E '^plugins=\\(' \"\$zshrc\" | head -n1 | sed -E 's/^plugins=\\((.*)\\)/\\1/')
      merged=\"\$current \$required\"
      merged=\$(echo \"\$merged\" | tr ' ' '\\n' | awk 'NF{a[\$0]=1} END{for(k in a) print k}' | tr '\\n' ' ')
      merged=\$(echo \"\$merged\" | xargs)
      sed -i -E \"s/^plugins=\\(.*\\)/plugins=(\$merged)/\" \"\$zshrc\"
    "
  else
    sudo -u "$user" bash -c "
      set -euo pipefail
      zshrc='$zshrc'
      omz='$omz_dir'

      if grep -qE '^ZSH=' \"\$zshrc\"; then
        sed -i -E \"s|^ZSH=.*|ZSH=\\\"$omz\\\"|\" \"\$zshrc\"
      else
        printf '\\nZSH=\"%s\"\\n' \"$omz\" >> \"\$zshrc\"
      fi

      if grep -qE '^ZSH_THEME=' \"\$zshrc\"; then
        sed -i -E 's|^ZSH_THEME=.*|ZSH_THEME=\"powerlevel10k/powerlevel10k\"|' \"\$zshrc\"
      else
        printf '\\nZSH_THEME=\"powerlevel10k/powerlevel10k\"\\n' >> \"\$zshrc\"
      fi

      if ! grep -qE '^plugins=\\(' \"\$zshrc\"; then
        printf '\\nplugins=(git)\\n' >> \"\$zshrc\"
      fi

      required='git sudo zsh-autosuggestions zsh-syntax-highlighting'
      current=\$(grep -E '^plugins=\\(' \"\$zshrc\" | head -n1 | sed -E 's/^plugins=\\((.*)\\)/\\1/')
      merged=\"\$current \$required\"
      merged=\$(echo \"\$merged\" | tr ' ' '\\n' | awk 'NF{a[\$0]=1} END{for(k in a) print k}' | tr '\\n' ' ')
      merged=\$(echo \"\$merged\" | xargs)
      sed -i -E \"s/^plugins=\\(.*\\)/plugins=(\$merged)/\" \"\$zshrc\"
    "
  fi

  local zsh_path
  zsh_path="$(command -v zsh || true)"
  if [[ -n "$zsh_path" ]]; then
    local current_shell
    current_shell="$(getent passwd "$user" | cut -d: -f7)"
    if [[ "$current_shell" != "$zsh_path" ]]; then
      chsh -s "$zsh_path" "$user" || info "Could not change default shell for $user (maybe restricted)."
    fi
  fi

  info "Zsh/oh-my-zsh configured for '$user'."
}

main() {
  require_root
  is_debian_like || die "This script currently supports Debian-like systems only."

  local rename_host=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rename) rename_host="${2:-}"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  local current_user="${SUDO_USER:-}"
  if [[ -z "$current_user" || "$current_user" == "root" ]]; then
    die "This script expects to be run via sudo from a non-root user (SUDO_USER missing or root)."
  fi

  confirm_or_exit

  if [[ -n "$rename_host" ]]; then
    set_hostname_safe "$rename_host"
  else
    info "Hostname rename not requested. (Use --rename <name>)"
  fi

  info "Updating apt index"
  apt-get update -y

  apt_install git curl net-tools ca-certificates zsh gpg sudo

  install_docker_debian

  configure_ssh "$current_user"

  configure_zsh_for_account "root" "/root"

  local current_home
  current_home="$(getent passwd "$current_user" | cut -d: -f6)"
  [[ -n "$current_home" ]] || die "Could not determine home for user: $current_user"

  ensure_user_nopasswd_sudo "$current_user"
  ensure_user_in_docker_group "$current_user"
  configure_zsh_for_account "$current_user" "$current_home"

  info "Initialisation complete."
  info "Note: docker group change requires a new login/session for '$current_user'."
  info "For each configured account, you can run: exec zsh ; p10k configure"
}

main "$@"
