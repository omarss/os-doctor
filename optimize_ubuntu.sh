#!/usr/bin/env bash
#
# Opinionated Ubuntu optimization and hardening script for native installs and WSL.
#
# Usage:
#   ./optimize_ubuntu.sh
#   ./optimize_ubuntu.sh --profile strict
#   ./optimize_ubuntu.sh --interactive
#   ./optimize_ubuntu.sh --clean
#   ./optimize_ubuntu.sh --dry-run

set -u
set -o pipefail

PROFILE="moderate"
INTERACTIVE=false
CLEAN_ONLY=false
DRY_RUN=false
SKIP_BACKUP=false

SCRIPT_LABEL="optimize_ubuntu"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ORIGINAL_USER="${SUDO_USER:-$USER}"
ORIGINAL_HOME="$(getent passwd "$ORIGINAL_USER" 2>/dev/null | cut -d: -f6)"
if [[ -z "$ORIGINAL_HOME" ]]; then
  ORIGINAL_HOME="$HOME"
fi
LOG_FILE="$ORIGINAL_HOME/${SCRIPT_LABEL}_${TIMESTAMP}.log"
BACKUP_DIR="$ORIGINAL_HOME/${SCRIPT_LABEL}_backup_${TIMESTAMP}"
CHANGE_COUNT=0

if grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null || grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=true
else
  IS_WSL=false
fi

color_for_level() {
  case "$1" in
    INFO) printf '\033[32m' ;;
    WARN) printf '\033[33m' ;;
    ERROR) printf '\033[31m' ;;
    SKIP) printf '\033[90m' ;;
    SECTION) printf '\033[36m' ;;
    *) printf '\033[0m' ;;
  esac
}

log_msg() {
  local level="$1"
  shift
  local message="$*"
  local color reset
  color="$(color_for_level "$level")"
  reset='\033[0m'
  printf '[%s] [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$level" "$message" >>"$LOG_FILE"
  if [[ "$level" == "SECTION" ]]; then
    printf '\n%b== %s ==%b\n' "$color" "$message" "$reset"
  else
    printf '  %b[%s]%b %s\n' "$color" "$level" "$reset" "$message"
  fi
}

usage() {
  cat <<'EOF'
Usage: ./optimize_ubuntu.sh [options]

Options:
  --profile {moderate|strict}  Hardening level. Default: moderate
  --interactive                Choose categories interactively
  --clean                      Run cleanup only
  --dry-run                    Preview changes without applying them
  --skip-backup                Do not copy managed files before editing
  -h, --help                   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --profile\n' >&2
        exit 1
      fi
      PROFILE="$2"
      shift 2
      ;;
    --interactive)
      INTERACTIVE=true
      shift
      ;;
    --clean)
      CLEAN_ONLY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-backup)
      SKIP_BACKUP=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$PROFILE" in
  moderate|strict) ;;
  *)
    printf 'Invalid profile: %s\n' "$PROFILE" >&2
    exit 1
    ;;
esac

ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    exec sudo bash "$0" "$@"
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

systemd_available() {
  command_exists systemctl && [[ -d /run/systemd/system ]]
}

backup_file() {
  local path="$1"
  local dest
  if $SKIP_BACKUP || $DRY_RUN || [[ ! -e "$path" ]]; then
    return 0
  fi
  dest="$BACKUP_DIR$path"
  if [[ -e "$dest" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp -a "$path" "$dest"
}

run_shell() {
  local description="$1"
  local command="$2"
  if $DRY_RUN; then
    log_msg SKIP "[DRY RUN] $description"
    log_msg SKIP "          $command"
    return 0
  fi
  if bash -lc "$command" >>"$LOG_FILE" 2>&1; then
    CHANGE_COUNT=$((CHANGE_COUNT + 1))
    log_msg INFO "$description"
    return 0
  fi
  log_msg ERROR "$description failed"
  return 1
}

run_user_shell() {
  local description="$1"
  local command="$2"
  if [[ "$ORIGINAL_USER" == "root" ]]; then
    run_shell "$description" "$command"
    return
  fi
  if $DRY_RUN; then
    log_msg SKIP "[DRY RUN] $description"
    log_msg SKIP "          sudo -H -u $ORIGINAL_USER bash -lc '$command'"
    return 0
  fi
  if sudo -H -u "$ORIGINAL_USER" bash -lc "$command" >>"$LOG_FILE" 2>&1; then
    CHANGE_COUNT=$((CHANGE_COUNT + 1))
    log_msg INFO "$description"
    return 0
  fi
  log_msg ERROR "$description failed"
  return 1
}

write_managed_file() {
  local path="$1"
  local content="$2"
  if ! $DRY_RUN; then
    backup_file "$path"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" >"$path"
  fi
  CHANGE_COUNT=$((CHANGE_COUNT + 1))
  if $DRY_RUN; then
    log_msg SKIP "[DRY RUN] Would write $path"
  else
    log_msg INFO "Wrote $path"
  fi
}

set_key_value_file() {
  local path="$1"
  local key="$2"
  local value="$3"
  if ! $DRY_RUN; then
    backup_file "$path"
    mkdir -p "$(dirname "$path")"
    touch "$path"
    if grep -Eq "^[[:space:]]*${key}=" "$path"; then
      sed -i -E "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$path"
    else
      printf '%s=%s\n' "$key" "$value" >>"$path"
    fi
  fi
  CHANGE_COUNT=$((CHANGE_COUNT + 1))
  if $DRY_RUN; then
    log_msg SKIP "[DRY RUN] Would set $key=$value in $path"
  else
    log_msg INFO "Set $key=$value in $path"
  fi
}

performance_settings() {
  local swappiness cache_pressure journald_limit perf_conf journald_conf
  log_msg SECTION "Performance"
  if [[ "$PROFILE" == "strict" ]]; then
    swappiness=5
    cache_pressure=50
    journald_limit=150M
  else
    swappiness=10
    cache_pressure=75
    journald_limit=250M
  fi

  perf_conf="$(cat <<EOF
# Managed by os-doctor
vm.swappiness = $swappiness
vm.vfs_cache_pressure = $cache_pressure
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
EOF
)"
  write_managed_file "/etc/sysctl.d/99-os-doctor-performance.conf" "$perf_conf"
  run_shell "Reload sysctl settings" "sysctl --system >/dev/null"

  if systemd_available; then
    journald_conf="$(cat <<EOF
[Journal]
SystemMaxUse=$journald_limit
RuntimeMaxUse=128M
EOF
)"
    write_managed_file "/etc/systemd/journald.conf.d/99-os-doctor.conf" "$journald_conf"
    run_shell "Restart systemd-journald" "systemctl restart systemd-journald"
  else
    log_msg WARN "systemd not detected; skipping journald tuning"
  fi

  if $IS_WSL; then
    log_msg WARN "WSL detected; skipping native disk trim configuration"
  elif systemd_available; then
    run_shell "Enable periodic SSD trim" "systemctl enable --now fstrim.timer"
  fi
}

privacy_settings() {
  log_msg SECTION "Privacy"
  set_key_value_file "/etc/default/apport" "enabled" "0"

  if systemd_available; then
    run_shell "Disable apport services" "systemctl disable --now apport.service apport-autoreport.service 2>/dev/null || true"
    run_shell "Disable whoopsie service" "systemctl disable --now whoopsie.service 2>/dev/null || true"
  fi

  set_key_value_file "/etc/default/motd-news" "ENABLED" "0"
  run_shell "Remove popularity-contest" "apt-get purge -y popularity-contest >/dev/null 2>&1 || true"
}

security_settings() {
  local auto_updates network_conf ssh_conf security_packages
  log_msg SECTION "Security"

  if $IS_WSL; then
    security_packages="unattended-upgrades"
  elif [[ "$PROFILE" == "strict" ]]; then
    security_packages="unattended-upgrades ufw fail2ban"
  else
    security_packages="unattended-upgrades ufw"
  fi

  run_shell "Install security packages" "apt-get update >/dev/null && apt-get install -y $security_packages >/dev/null"

  auto_updates="$(cat <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
)"
  write_managed_file "/etc/apt/apt.conf.d/20auto-upgrades" "$auto_updates"

  if systemd_available; then
    run_shell "Enable unattended-upgrades" "systemctl enable --now unattended-upgrades.service 2>/dev/null || true"
  fi

  network_conf="$(cat <<'EOF'
# Managed by os-doctor
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
EOF
)"
  write_managed_file "/etc/sysctl.d/99-os-doctor-network-hardening.conf" "$network_conf"
  run_shell "Reload network hardening sysctls" "sysctl --system >/dev/null"

  if $IS_WSL; then
    log_msg WARN "WSL detected; skipping UFW because Windows networking is authoritative"
  else
    run_shell "Set UFW defaults" "ufw default deny incoming && ufw default allow outgoing"
    if dpkg -s openssh-server >/dev/null 2>&1; then
      run_shell "Allow OpenSSH in UFW" "ufw allow OpenSSH"
    fi
    run_shell "Enable UFW" "ufw --force enable"
    if command_exists docker; then
      log_msg WARN "Docker can bypass UFW for published ports; review DOCKER-USER rules separately"
    fi
  fi

  if dpkg -s openssh-server >/dev/null 2>&1; then
    if [[ "$PROFILE" == "strict" || -f "$ORIGINAL_HOME/.ssh/authorized_keys" ]]; then
      ssh_conf="$(cat <<'EOF'
# Managed by os-doctor
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF
)"
      write_managed_file "/etc/ssh/sshd_config.d/99-os-doctor.conf" "$ssh_conf"
      if systemd_available; then
        run_shell "Restart SSH service" "systemctl restart ssh.service 2>/dev/null || systemctl restart sshd.service 2>/dev/null || true"
      fi
    else
      log_msg WARN "OpenSSH server detected but no authorized_keys for $ORIGINAL_USER; leaving password auth unchanged"
    fi
  fi

  if [[ "$PROFILE" == "strict" ]] && ! $IS_WSL && systemd_available && dpkg -s fail2ban >/dev/null 2>&1; then
    run_shell "Enable fail2ban" "systemctl enable --now fail2ban.service"
  fi
}

cleanup_system() {
  log_msg SECTION "Cleanup"
  run_shell "Autoremove unused packages" "apt-get autoremove -y >/dev/null"
  run_shell "Clean apt caches" "apt-get autoclean -y >/dev/null && apt-get clean"

  if systemd_available; then
    run_shell "Vacuum old journal entries" "journalctl --vacuum-time=7d >/dev/null"
  fi

  run_user_shell "Clear thumbnail cache" "rm -rf \"$HOME/.cache/thumbnails\"/* 2>/dev/null || true"
  run_user_shell "Clear pip cache" "pip cache purge >/dev/null 2>&1 || true"
  run_user_shell "Clear npm cache" "npm cache clean --force >/dev/null 2>&1 || true"
  run_user_shell "Clear user trash" "rm -rf \"$HOME/.local/share/Trash/files\"/* 2>/dev/null || true"
}

show_interactive_menu() {
  printf '\n%s\n' "============================================"
  printf '%s\n' "  Ubuntu Optimizer - Interactive Mode"
  printf '%s\n' "  Profile: $PROFILE"
  printf '%s\n' "============================================"
  printf '\n'
  printf '%s\n' "  [1] Performance"
  printf '%s\n' "  [2] Privacy"
  printf '%s\n' "  [3] Security"
  printf '%s\n' "  [4] Clean"
  printf '%s\n' "  [A] All"
  printf '%s\n' "  [Q] Quit"
  printf '\n'
  read -r -p "Select categories (comma-separated, e.g. 1,3): " choices
  printf '%s' "$choices"
}

interactive_mode() {
  local choices run_perf=false run_priv=false run_sec=false run_clean=false
  choices="$(show_interactive_menu)"
  case "$choices" in
    *[Qq]*)
      log_msg WARN "Aborted"
      return
      ;;
  esac
  case "$choices" in
    *[Aa]*)
      run_perf=true
      run_priv=true
      run_sec=true
      run_clean=true
      ;;
    *)
      case "$choices" in *1*) run_perf=true ;; esac
      case "$choices" in *2*) run_priv=true ;; esac
      case "$choices" in *3*) run_sec=true ;; esac
      case "$choices" in *4*) run_clean=true ;; esac
      ;;
  esac

  if ! $run_perf && ! $run_priv && ! $run_sec && ! $run_clean; then
    log_msg WARN "No valid selection"
    return
  fi

  read -r -p "Apply selected categories? [Y/n] " confirm
  case "$confirm" in
    [Nn]*) log_msg WARN "Aborted"; return ;;
  esac

  $run_perf && performance_settings
  $run_priv && privacy_settings
  $run_sec && security_settings
  $run_clean && cleanup_system
}

show_summary() {
  log_msg SECTION "Summary"
  log_msg INFO "Profile: $PROFILE"
  log_msg INFO "WSL detected: $IS_WSL"
  log_msg INFO "Changes applied: $CHANGE_COUNT"
  log_msg INFO "Log file: $LOG_FILE"
  if $SKIP_BACKUP; then
    log_msg WARN "Backups were skipped"
  else
    log_msg INFO "Backup directory: $BACKUP_DIR"
  fi
  if $IS_WSL; then
    log_msg WARN "WSL keeps Windows in charge of firewalling and host-level disk scheduling"
  fi
}

ensure_root "$@"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log_msg SECTION "Ubuntu Optimizer"
log_msg INFO "User: $ORIGINAL_USER"
log_msg INFO "Profile: $PROFILE"
log_msg INFO "WSL detected: $IS_WSL"
if $DRY_RUN; then
  log_msg WARN "Dry-run mode; no changes will be written"
fi

if $INTERACTIVE; then
  interactive_mode
elif $CLEAN_ONLY; then
  cleanup_system
else
  performance_settings
  privacy_settings
  security_settings
fi

show_summary
