#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
umask 027

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export NEEDRESTART_MODE=a

DEFAULT_P10K_CONFIG_URL="https://raw.githubusercontent.com/NathanEtinzon/QoL/main/Initialisation/.p10k.zsh"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "This script must be run as root."
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: ./init.sh [options]

Options:
  --user <name>                 Target user to configure. Defaults to SUDO_USER, then 'user'.
  --rename <hostname>           Rename the machine.
  --skip-zsh                    Skip Zsh, Oh My Zsh and Powerlevel10k configuration.
  --skip-docker                 Skip Docker repository and package installation.
  --skip-ssh                    Skip SSH server configuration.
  --skip-chsh                   Do not change the default shell. This is the default behavior.
  --set-default-shell           Change the default shell to zsh for configured accounts.
  --enable-nopasswd-sudo        Grant NOPASSWD sudo to the target user.
  --ssh-password-auth <yes|no>  Set SSH PasswordAuthentication. Defaults to 'no'.
  --restrict-ssh-user           Restrict SSH login to the target user with AllowUsers.
  -h, --help                    Show this help.

Environment:
  P10K_CONFIG_URL               Override the default Powerlevel10k config URL.
EOF
}

valid_yes_no() {
  [[ "$1" == "yes" || "$1" == "no" ]]
}

is_debian_like() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *"debian"* ]]
}

apt_update() {
  apt-get -o Dpkg::Use-Pty=0 update -y
}

apt_install_noninteractive() {
  apt-get \
    -o Dpkg::Use-Pty=0 \
    install -y \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    --no-install-recommends \
    "$@"
}

apt_install() {
  local pkgs=("$@")
  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if ((${#missing[@]})); then
    info "Installing packages: ${missing[*]}"
    apt_install_noninteractive "${missing[@]}"
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

  apt_update
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

  if ! id -u "$user" >/dev/null 2>&1; then
    die "Target user '$user' does not exist."
  fi

  if ! dpkg -s sudo >/dev/null 2>&1; then
    info "Installing sudo package..."
    apt_install_noninteractive sudo
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

  if ! id -u "$user" >/dev/null 2>&1; then
    die "Target user '$user' does not exist."
  fi

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
  local target_user="$1"
  local password_auth="$2"
  local restrict_user="$3"
  [[ -n "$target_user" ]] || die "configure_ssh: missing target user."
  valid_yes_no "$password_auth" || die "configure_ssh: invalid PasswordAuthentication value: $password_auth"

  apt_install openssh-server

  local cfg="/etc/ssh/sshd_config"
  [[ -f "$cfg" ]] || die "sshd_config not found at $cfg"

  info "Backing up sshd_config"
  cp -a "$cfg" "${cfg}.bak.$(date +%F_%H%M%S)"

  set_sshd_directive "$cfg" "PermitRootLogin" "no"
  set_sshd_directive "$cfg" "PasswordAuthentication" "$password_auth"
  set_sshd_directive "$cfg" "PermitEmptyPasswords" "no"
  if [[ "$restrict_user" == "true" ]]; then
    set_sshd_allowusers "$cfg" "$target_user"
  else
    info "SSH AllowUsers restriction not requested. Leaving existing policy unchanged."
  fi

  if have_cmd systemctl; then
    info "Enabling and restarting ssh service"
    systemctl enable ssh
    systemctl restart ssh
  else
    info "systemctl not available; skipping ssh service enable/restart."
  fi
}

run_as_account() {
  local user="$1"
  shift

  if [[ "$user" == "root" ]]; then
    "$@"
  else
    sudo -u "$user" "$@"
  fi
}

install_p10k_config() {
  local user="$1"
  local home="$2"
  local url="${P10K_CONFIG_URL:-$DEFAULT_P10K_CONFIG_URL}"
  local target="${home}/.p10k.zsh"
  local tmp

  have_cmd wget || die "wget is required to download Powerlevel10k config."
  tmp="$(mktemp)"

  info "Downloading Powerlevel10k config for '$user' from $url"
  if ! wget --quiet --timeout=30 --tries=3 -O "$tmp" "$url"; then
    rm -f "$tmp"
    die "Failed to download Powerlevel10k config from $url"
  fi
  install -m 0644 "$tmp" "$target"
  rm -f "$tmp"

  if [[ "$user" != "root" ]]; then
    chown "$user:" "$target"
  fi
}

configure_zsh_for_account() {
  local user="$1"
  local home="$2"
  local set_default_shell="$3"

  [[ -n "$user" && -n "$home" ]] || die "configure_zsh_for_account: missing user/home."
  [[ -d "$home" ]] || die "Home directory not found: $home"

  local omz_dir="${home}/.oh-my-zsh"
  local zshrc="${home}/.zshrc"
  local zsh_custom="${omz_dir}/custom"

  info "Configuring Zsh/oh-my-zsh for '$user' (home: $home)"

  run_as_account "$user" mkdir -p "${zsh_custom}/plugins" "${zsh_custom}/themes"

  if [[ ! -d "$omz_dir" ]]; then
    run_as_account "$user" git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$omz_dir"
  else
    info "oh-my-zsh already present for '$user'."
  fi

  if [[ ! -f "$zshrc" ]]; then
    run_as_account "$user" cp "${omz_dir}/templates/zshrc.zsh-template" "$zshrc"
  fi

  local p1="${zsh_custom}/plugins/zsh-syntax-highlighting"
  local p2="${zsh_custom}/plugins/zsh-autosuggestions"
  local th="${zsh_custom}/themes/powerlevel10k"

  if [[ ! -d "$p1" ]]; then
    run_as_account "$user" git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$p1"
  fi

  if [[ ! -d "$p2" ]]; then
    run_as_account "$user" git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$p2"
  fi

  if [[ ! -d "$th" ]]; then
    run_as_account "$user" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$th"
  fi

  run_as_account "$user" env ZSHRC="$zshrc" OMZ_DIR="$omz_dir" HOME="$home" bash -c '
    set -euo pipefail

    if grep -qE "^ZSH=" "$ZSHRC"; then
      sed -i -E "s|^ZSH=.*|ZSH=\"$OMZ_DIR\"|" "$ZSHRC"
    else
      printf "\nZSH=\"%s\"\n" "$OMZ_DIR" >> "$ZSHRC"
    fi

    if grep -qE "^ZSH_THEME=" "$ZSHRC"; then
      sed -i -E "s|^ZSH_THEME=.*|ZSH_THEME=\"powerlevel10k/powerlevel10k\"|" "$ZSHRC"
    else
      printf "\nZSH_THEME=\"powerlevel10k/powerlevel10k\"\n" >> "$ZSHRC"
    fi

    if ! grep -qE "^plugins=\(" "$ZSHRC"; then
      printf "\nplugins=(git)\n" >> "$ZSHRC"
    fi

    required="git sudo zsh-autosuggestions zsh-syntax-highlighting"
    current="$(grep -E "^plugins=\(" "$ZSHRC" | head -n1 | sed -E "s/^plugins=\((.*)\)/\1/")"
    merged="$(printf "%s\n" $current $required | awk "NF && !seen[\$0]++" | tr "\n" " " | xargs)"
    sed -i -E "s/^plugins=\(.*\)/plugins=($merged)/" "$ZSHRC"

    if ! grep -qF "[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" "$ZSHRC"; then
      printf "\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh\n" >> "$ZSHRC"
    fi
  '

  install_p10k_config "$user" "$home"

  if [[ "$set_default_shell" == "true" ]]; then
    local zsh_path
    zsh_path="$(command -v zsh || true)"
    if [[ -n "$zsh_path" ]]; then
      local current_shell
      current_shell="$(getent passwd "$user" | cut -d: -f7)"
      if [[ "$current_shell" != "$zsh_path" ]]; then
        chsh -s "$zsh_path" "$user" || info "Could not change default shell for $user (maybe restricted)."
      fi
    fi
  else
    info "Default shell change not requested for '$user'."
  fi

  info "Zsh/oh-my-zsh configured for '$user'."
}

main() {
  require_root
  is_debian_like || die "This script currently supports Debian-like systems only."

  local rename_host=""
  local target_user="${SUDO_USER:-user}"
  local configure_zsh="true"
  local install_docker="true"
  local configure_ssh_service="true"
  local grant_nopasswd_sudo="false"
  local set_default_shell="false"
  local ssh_password_auth="no"
  local restrict_ssh_user="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        [[ -n "${2:-}" ]] || die "--user requires a value."
        target_user="$2"
        shift 2
        ;;
      --rename)
        [[ -n "${2:-}" ]] || die "--rename requires a value."
        rename_host="$2"
        shift 2
        ;;
      --skip-zsh)
        configure_zsh="false"
        shift
        ;;
      --skip-docker)
        install_docker="false"
        shift
        ;;
      --skip-ssh)
        configure_ssh_service="false"
        shift
        ;;
      --skip-chsh)
        set_default_shell="false"
        shift
        ;;
      --set-default-shell)
        set_default_shell="true"
        shift
        ;;
      --enable-nopasswd-sudo)
        grant_nopasswd_sudo="true"
        shift
        ;;
      --ssh-password-auth)
        [[ -n "${2:-}" ]] || die "--ssh-password-auth requires a value: yes or no."
        valid_yes_no "$2" || die "--ssh-password-auth must be 'yes' or 'no'."
        ssh_password_auth="$2"
        shift 2
        ;;
      --restrict-ssh-user)
        restrict_ssh_user="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  if ! id -u "$target_user" >/dev/null 2>&1; then
    die "Target user '$target_user' does not exist. Create it or run the script with --user <name>."
  fi

  if [[ "$configure_zsh" != "true" && "$set_default_shell" == "true" ]]; then
    die "--set-default-shell cannot be used with --skip-zsh."
  fi

  info "Running in non-interactive mode."
  info "Target user: $target_user"

  if [[ -n "$rename_host" ]]; then
    set_hostname_safe "$rename_host"
  else
    info "Hostname rename not requested. (Use --rename <name>)"
  fi

  info "Updating apt index"
  apt_update

  local base_packages=(git curl net-tools ca-certificates gpg sudo)
  if [[ "$configure_zsh" == "true" ]]; then
    base_packages+=(zsh wget)
  fi
  if [[ "$configure_ssh_service" == "true" ]]; then
    base_packages+=(openssh-server)
  fi
  apt_install "${base_packages[@]}"

  if [[ "$install_docker" == "true" ]]; then
    install_docker_debian
  else
    info "Docker installation skipped."
  fi

  if [[ "$configure_ssh_service" == "true" ]]; then
    configure_ssh "$target_user" "$ssh_password_auth" "$restrict_ssh_user"
  else
    info "SSH configuration skipped."
  fi

  if [[ "$configure_zsh" == "true" ]]; then
    configure_zsh_for_account "root" "/root" "$set_default_shell"
  else
    info "Zsh configuration skipped for root."
  fi

  local target_home
  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  [[ -n "$target_home" ]] || die "Could not determine home for user: $target_user"

  if [[ "$grant_nopasswd_sudo" == "true" ]]; then
    ensure_user_nopasswd_sudo "$target_user"
  else
    info "NOPASSWD sudo grant not requested for '$target_user'."
  fi

  if [[ "$install_docker" == "true" ]]; then
    ensure_user_in_docker_group "$target_user"
  fi

  if [[ "$configure_zsh" == "true" ]]; then
    configure_zsh_for_account "$target_user" "$target_home" "$set_default_shell"
  else
    info "Zsh configuration skipped for '$target_user'."
  fi

  info "Initialisation complete."
  if [[ "$install_docker" == "true" ]]; then
    info "Note: docker group membership requires a new login/session for '$target_user' to take effect."
  fi
}

main "$@"
