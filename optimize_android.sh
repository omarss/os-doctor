#!/usr/bin/env bash
#
# Opinionated Android optimization script that runs from your host via adb.
#
# Usage:
#   ./optimize_android.sh
#   ./optimize_android.sh --serial emulator-5554
#   ./optimize_android.sh --profile strict
#   ./optimize_android.sh --interactive
#   ./optimize_android.sh --clean
#   ./optimize_android.sh --dry-run

set -u
set -o pipefail

PROFILE="moderate"
INTERACTIVE=false
CLEAN_ONLY=false
DRY_RUN=false
SERIAL=""

SCRIPT_LABEL="optimize_android"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$HOME/${SCRIPT_LABEL}_${TIMESTAMP}.log"
BACKUP_FILE="$HOME/${SCRIPT_LABEL}_settings_backup_${TIMESTAMP}.tsv"
CHANGE_COUNT=0
DEVICE_ID=""
ADB_CMD=(adb)

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
Usage: ./optimize_android.sh [options]

Options:
  --serial SERIAL               Target a specific adb device or emulator
  --profile {moderate|strict}  Optimization level. Default: moderate
  --interactive                Choose categories interactively
  --clean                      Run cleanup only
  --dry-run                    Preview changes without applying them
  -h, --help                   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --serial\n' >&2
        exit 1
      fi
      SERIAL="$2"
      shift 2
      ;;
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

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_device() {
  local devices count first
  if ! command_exists adb; then
    printf 'adb is required to run optimize_android.sh\n' >&2
    exit 1
  fi

  adb start-server >/dev/null 2>&1 || true

  if [[ -n "$SERIAL" ]]; then
    DEVICE_ID="$SERIAL"
  else
    devices="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
    count="$(printf '%s\n' "$devices" | awk 'NF { c++ } END { print c + 0 }')"
    if [[ "$count" -eq 0 ]]; then
      printf 'No adb devices are connected and authorized.\n' >&2
      exit 1
    fi
    if [[ "$count" -gt 1 ]]; then
      printf 'Multiple adb devices detected. Re-run with --serial SERIAL.\n' >&2
      printf '%s\n' "$devices" >&2
      exit 1
    fi
    first="$(printf '%s\n' "$devices" | awk 'NF { print; exit }')"
    DEVICE_ID="$first"
  fi

  ADB_CMD=(adb -s "$DEVICE_ID")
  if ! "${ADB_CMD[@]}" get-state >/dev/null 2>&1; then
    printf 'Unable to talk to device %s\n' "$DEVICE_ID" >&2
    exit 1
  fi
}

adb_capture() {
  local command="$1"
  "${ADB_CMD[@]}" shell "$command" 2>>"$LOG_FILE" | tr -d '\r'
}

run_adb_shell() {
  local description="$1"
  local command="$2"
  if $DRY_RUN; then
    log_msg SKIP "[DRY RUN] $description"
    log_msg SKIP "          ${ADB_CMD[*]} shell $command"
    return 0
  fi
  if "${ADB_CMD[@]}" shell "$command" >>"$LOG_FILE" 2>&1; then
    CHANGE_COUNT=$((CHANGE_COUNT + 1))
    log_msg INFO "$description"
    return 0
  fi
  log_msg ERROR "$description failed"
  return 1
}

run_adb_shell_optional() {
  local description="$1"
  local command="$2"
  if $DRY_RUN; then
    log_msg SKIP "[DRY RUN] $description"
    log_msg SKIP "          ${ADB_CMD[*]} shell $command"
    return 0
  fi
  if "${ADB_CMD[@]}" shell "$command" >>"$LOG_FILE" 2>&1; then
    CHANGE_COUNT=$((CHANGE_COUNT + 1))
    log_msg INFO "$description"
  else
    log_msg WARN "$description not supported on this device"
  fi
}

backup_setting() {
  local namespace="$1"
  local key="$2"
  local current pattern
  pattern="$(printf '%s\t%s\t' "$namespace" "$key")"
  if [[ -f "$BACKUP_FILE" ]] && grep -Fq "$pattern" "$BACKUP_FILE"; then
    return 0
  fi
  current="$(adb_capture "settings get $namespace $key" | tail -n 1)"
  printf '%s\t%s\t%s\n' "$namespace" "$key" "$current" >>"$BACKUP_FILE"
}

put_setting() {
  local namespace="$1"
  local key="$2"
  local value="$3"
  local description="$4"
  backup_setting "$namespace" "$key"
  run_adb_shell "$description" "settings put $namespace $key $value"
}

put_setting_optional() {
  local namespace="$1"
  local key="$2"
  local value="$3"
  local description="$4"
  backup_setting "$namespace" "$key"
  run_adb_shell_optional "$description" "settings put $namespace $key $value"
}

performance_settings() {
  local animation_scale
  log_msg SECTION "Performance"
  if [[ "$PROFILE" == "strict" ]]; then
    animation_scale="0.0"
  else
    animation_scale="0.5"
  fi

  put_setting global window_animation_scale "$animation_scale" "Set window animation scale to $animation_scale"
  put_setting global transition_animation_scale "$animation_scale" "Set transition animation scale to $animation_scale"
  put_setting global animator_duration_scale "$animation_scale" "Set animator duration scale to $animation_scale"
}

privacy_settings() {
  log_msg SECTION "Privacy"
  put_setting_optional global wifi_scan_always_enabled "0" "Disable always-available Wi-Fi scanning"
  put_setting_optional global ble_scan_always_enabled "0" "Disable always-available Bluetooth scanning"
  put_setting_optional global send_action_app_error "0" "Disable app crash intent broadcasts"
  put_setting_optional global network_recommendations_enabled "0" "Disable network recommendation prompts"
}

security_settings() {
  log_msg SECTION "Security"
  put_setting_optional global verifier_verify_adb_installs "1" "Require package verification for adb installs"
  put_setting_optional global package_verifier_enable "1" "Enable package verifier"
  put_setting_optional global auto_time "1" "Enable automatic network-provided time"
  put_setting_optional global auto_time_zone "1" "Enable automatic time zone"
  put_setting_optional secure install_non_market_apps "0" "Disable installs from unknown sources where supported"
}

cleanup_system() {
  log_msg SECTION "Cleanup"
  run_adb_shell_optional "Trim application caches" "pm trim-caches 128G"
  run_adb_shell_optional "Run background dex optimization job" "cmd package bg-dexopt-job"
  run_adb_shell_optional "Clear logcat buffers" "logcat -c"
}

show_interactive_menu() {
  printf '\n%s\n' "============================================"
  printf '%s\n' "  Android Optimizer - Interactive Mode"
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

  read -r -p "Apply selected categories to $DEVICE_ID? [Y/n] " confirm
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
  log_msg INFO "Device: $DEVICE_ID"
  log_msg INFO "Changes applied: $CHANGE_COUNT"
  log_msg INFO "Log file: $LOG_FILE"
  log_msg INFO "Backup file: $BACKUP_FILE"
  log_msg WARN "Android settings support varies by OEM and OS version; review warnings above for skipped keys"
}

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
touch "$BACKUP_FILE"

ensure_device

DEVICE_MODEL="$(adb_capture "getprop ro.product.model" | tail -n 1)"
ANDROID_RELEASE="$(adb_capture "getprop ro.build.version.release" | tail -n 1)"

log_msg SECTION "Android Optimizer"
log_msg INFO "Device: $DEVICE_ID"
log_msg INFO "Model: ${DEVICE_MODEL:-unknown}"
log_msg INFO "Android: ${ANDROID_RELEASE:-unknown}"
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
