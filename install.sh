#!/usr/bin/env bash
# install.sh — Detect OS and deploy the appropriate shell profile(s), then bootstrap.
#
# Usage:
#   curl -fsSL <url>/install.sh | bash
#   # or
#   ./install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { printf "\033[1;34m==> %s\033[0m\n" "$*"; }
ok()    { printf "\033[32m  ✔ %s\033[0m\n" "$*"; }
warn()  { printf "\033[33m  ⚠ %s\033[0m\n" "$*"; }
fail()  { printf "\033[31m  ✘ %s\033[0m\n" "$*"; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./install.sh

Detect the current OS, install the matching shell profile, and run the
platform bootstrap command.
EOF
}

backup_file() {
  local target="$1"
  [[ -f "$target" ]] || return 0

  local stamp backup
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="${target}.bak.${stamp}"
  info "Backing up existing $(basename "$target") to $backup"
  cp "$target" "$backup"
}

if [[ $# -gt 0 ]]; then
  case "${1-}" in
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
fi

deploy_bashrc() {
  local src="$REPO_DIR/shells/bashrc"
  local dest="$HOME/.bashrc"

  [[ -f "$src" ]] || fail "shells/bashrc not found in $REPO_DIR"

  backup_file "$dest"

  info "Installing .bashrc to $dest"
  cp "$src" "$dest"
  ok "Installed .bashrc"
}

deploy_windows_profile() {
  # Deploy windows.ps1 to the Windows host's PowerShell $PROFILE from WSL
  local src="$REPO_DIR/shells/windows.ps1"
  local opt_src="$REPO_DIR/optimize/windows.ps1"

  [[ -f "$src" ]] || { warn "shells/windows.ps1 not found — skipping Windows profile"; return; }

  # Resolve the Windows user profile path via WSL interop
  local win_home
  win_home=$(wslpath "$(cmd.exe /C 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')" 2>/dev/null) || true

  if [[ -z "$win_home" || ! -d "$win_home" ]]; then
    warn "Could not resolve Windows home — skipping Windows profile deploy"
    return
  fi

  # PowerShell profile location
  local ps_profile_dir="$win_home/Documents/WindowsPowerShell"
  local ps_profile="$ps_profile_dir/Microsoft.PowerShell_profile.ps1"

  mkdir -p "$ps_profile_dir"

  backup_file "$ps_profile"

  info "Installing shells/windows.ps1 to $ps_profile"
  cp "$src" "$ps_profile"
  ok "Installed Windows PowerShell profile"

  # Also deploy optimize/windows.ps1 to the Windows desktop for easy access
  if [[ -f "$opt_src" ]]; then
    local win_desktop="$win_home/Desktop"
    if [[ -d "$win_desktop" ]]; then
      backup_file "$win_desktop/Optimize-Windows.ps1"
      cp "$opt_src" "$win_desktop/Optimize-Windows.ps1"
      ok "Copied optimize/windows.ps1 to Windows Desktop"
    else
      backup_file "$win_home/Optimize-Windows.ps1"
      cp "$opt_src" "$win_home/Optimize-Windows.ps1"
      ok "Copied optimize/windows.ps1 to Windows home"
    fi
  fi
}

OS="$(uname -s)"
case "$OS" in
  Linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      info "Detected WSL (Windows Subsystem for Linux)"
      info ""
      info "Deploying BOTH Ubuntu (.bashrc) and Windows (windows.ps1) profiles"
      info ""

      # Deploy Linux profile
      deploy_bashrc

      # Deploy Windows profile from WSL
      deploy_windows_profile

      # Bootstrap Linux environment
      info "Sourcing new profile and running install..."
      # shellcheck disable=SC1090
      source "$HOME/.bashrc"
      install
    else
      info "Detected Linux"

      deploy_bashrc

      info "Sourcing new profile and running install..."
      # shellcheck disable=SC1090
      source "$HOME/.bashrc"
      install
    fi
    ;;

  Darwin*)
    info "Detected macOS"

    SRC="$REPO_DIR/shells/zshrc"
    DEST="$HOME/.zshrc"

    [[ -f "$SRC" ]] || fail "shells/zshrc not found in $REPO_DIR"

    backup_file "$DEST"

    info "Installing shells/zshrc to $DEST"
    cp "$SRC" "$DEST"
    ok "Installed .zshrc"

    info "Sourcing new profile and running install..."
    zsh -c "source '$DEST' && install"
    ;;

  *)
    fail "Unsupported OS: $OS — use install.bat on Windows"
    ;;
esac

ok "Bootstrap complete! Restart your shell."
