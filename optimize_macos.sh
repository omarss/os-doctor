#!/usr/bin/env bash
#
# Opinionated macOS optimization and hardening script for developer workstations.
#
# Usage:
#   ./optimize_macos.sh
#   ./optimize_macos.sh --profile strict
#   ./optimize_macos.sh --interactive
#   ./optimize_macos.sh --clean
#   ./optimize_macos.sh --dry-run

set -u
set -o pipefail

PROFILE="moderate"
INTERACTIVE=false
CLEAN_ONLY=false
DRY_RUN=false
SKIP_BACKUP=false

SCRIPT_LABEL="optimize_macos"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ORIGINAL_USER="${SUDO_USER:-$USER}"
ORIGINAL_HOME="$(dscl . -read "/Users/$ORIGINAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
if [[ -z "$ORIGINAL_HOME" ]]; then
  ORIGINAL_HOME="$HOME"
fi
LOG_FILE="$ORIGINAL_HOME/${SCRIPT_LABEL}_${TIMESTAMP}.log"
BACKUP_DIR="$ORIGINAL_HOME/${SCRIPT_LABEL}_backup_${TIMESTAMP}"
CHANGE_COUNT=0

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
Usage: ./optimize_macos.sh [options]

Options:
  --profile {moderate|strict}  Hardening level. Default: moderate
  --interactive                Choose categories interactively
  --clean                      Run cleanup only
  --dry-run                    Preview changes without applying them
  --skip-backup                Do not snapshot touched preference files
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

backup_user_defaults() {
  local domain="$1"
  local safe_name dest
  if $SKIP_BACKUP || $DRY_RUN; then
    return 0
  fi
  safe_name="$(printf '%s' "$domain" | tr './ ' '___')"
  dest="$BACKUP_DIR/user-defaults-${safe_name}.plist"
  if [[ -e "$dest" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  sudo -H -u "$ORIGINAL_USER" defaults export "$domain" "$dest" >/dev/null 2>&1 || true
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

performance_settings() {
  local dock_speed
  log_msg SECTION "Performance"
  backup_user_defaults "NSGlobalDomain"
  backup_user_defaults "com.apple.dock"
  backup_user_defaults "com.apple.finder"

  if [[ "$PROFILE" == "strict" ]]; then
    dock_speed="0.08"
  else
    dock_speed="0.15"
  fi

  run_user_shell "Disable automatic window animations" "defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false"
  run_user_shell "Speed up window resize animations" "defaults write NSGlobalDomain NSWindowResizeTime -float 0.001"
  run_user_shell "Enable dock auto-hide" "defaults write com.apple.dock autohide -bool true"
  run_user_shell "Remove dock auto-hide delay" "defaults write com.apple.dock autohide-delay -float 0"
  run_user_shell "Reduce dock animation time" "defaults write com.apple.dock autohide-time-modifier -float $dock_speed"
  run_user_shell "Disable dock launch animations" "defaults write com.apple.dock launchanim -bool false"
  run_user_shell "Speed up Mission Control animation" "defaults write com.apple.dock expose-animation-duration -float 0.1"
  run_user_shell "Disable Finder animations" "defaults write com.apple.finder DisableAllAnimations -bool true"
  run_user_shell "Restart Dock and Finder" "killall Dock >/dev/null 2>&1 || true; killall Finder >/dev/null 2>&1 || true"
}

privacy_settings() {
  log_msg SECTION "Privacy"
  backup_user_defaults "com.apple.AdLib"
  backup_user_defaults "com.apple.SubmitDiagInfo"
  backup_user_defaults "com.apple.CrashReporter"

  run_user_shell "Disable personalized advertising" "defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false"
  run_user_shell "Disable automatic diagnostic submission" "defaults write com.apple.SubmitDiagInfo AutoSubmit -bool false"
  run_user_shell "Suppress CrashReporter dialogs" "defaults write com.apple.CrashReporter DialogType -string none"
}

security_settings() {
  local firewall_path
  log_msg SECTION "Security"

  backup_file "/Library/Preferences/com.apple.SoftwareUpdate.plist"
  backup_file "/Library/Preferences/com.apple.commerce.plist"
  backup_file "/Library/Preferences/com.apple.loginwindow.plist"
  backup_user_defaults "com.apple.screensaver"

  firewall_path="/usr/libexec/ApplicationFirewall/socketfilterfw"
  if [[ -x "$firewall_path" ]]; then
    run_shell "Enable macOS firewall" "$firewall_path --setglobalstate on"
    run_shell "Enable firewall stealth mode" "$firewall_path --setstealthmode on"
    run_shell "Enable firewall logging" "$firewall_path --setloggingmode on"
  fi

  if command_exists spctl; then
    run_shell "Enable Gatekeeper assessments" "spctl --master-enable"
  fi

  run_shell "Enable automatic update checks" "defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true"
  run_shell "Enable automatic update downloads" "defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true"
  run_shell "Enable automatic security data updates" "defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true"
  run_shell "Enable automatic critical updates" "defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true"
  run_shell "Enable App Store auto-updates" "defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true"
  run_shell "Disable guest login" "defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false"

  if command_exists systemsetup; then
    run_shell "Disable remote login" "systemsetup -setremotelogin off"
    run_shell "Disable remote Apple events" "systemsetup -setremoteappleevents off"
  else
    log_msg WARN "systemsetup not found; skipping remote access toggles"
  fi

  run_user_shell "Require password immediately after sleep or screen saver" "defaults write com.apple.screensaver askForPassword -int 1 && defaults write com.apple.screensaver askForPasswordDelay -int 0"

  if command_exists fdesetup; then
    if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then
      log_msg INFO "FileVault is already enabled"
    else
      log_msg WARN "FileVault is not enabled; turn it on manually if this Mac stores sensitive data"
    fi
  fi
}

cleanup_system() {
  log_msg SECTION "Cleanup"
  run_shell "Run periodic maintenance scripts" "periodic daily weekly monthly >/dev/null 2>&1 || true"
  run_user_shell "Clear user caches" "find \"$HOME/Library/Caches\" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true"
  run_user_shell "Clear diagnostic reports" "rm -rf \"$HOME/Library/Logs/DiagnosticReports\"/* 2>/dev/null || true"
  run_user_shell "Clear Xcode DerivedData" "rm -rf \"$HOME/Library/Developer/Xcode/DerivedData\"/* 2>/dev/null || true"
  run_user_shell "Clear CoreSimulator caches" "rm -rf \"$HOME/Library/Developer/CoreSimulator/Caches\"/* 2>/dev/null || true"
  run_user_shell "Clear pip cache" "pip cache purge >/dev/null 2>&1 || true"
  run_user_shell "Clear npm cache" "npm cache clean --force >/dev/null 2>&1 || true"

  if command_exists brew; then
    run_user_shell "Run Homebrew cleanup" "brew autoremove >/dev/null 2>&1 || true; brew cleanup -s >/dev/null 2>&1 || true"
  fi

  run_shell "Flush DNS caches" "dscacheutil -flushcache >/dev/null 2>&1 || true; killall -HUP mDNSResponder >/dev/null 2>&1 || true"
}

show_interactive_menu() {
  printf '\n%s\n' "============================================"
  printf '%s\n' "  macOS Optimizer - Interactive Mode"
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
  log_msg INFO "Changes applied: $CHANGE_COUNT"
  log_msg INFO "Log file: $LOG_FILE"
  if $SKIP_BACKUP; then
    log_msg WARN "Backups were skipped"
  else
    log_msg INFO "Backup directory: $BACKUP_DIR"
  fi
}

ensure_root "$@"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log_msg SECTION "macOS Optimizer"
log_msg INFO "User: $ORIGINAL_USER"
log_msg INFO "Profile: $PROFILE"
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
