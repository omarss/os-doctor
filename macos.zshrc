#!/usr/bin/env zsh
# ~/.zshrc — Omar's dev environment for macOS
#
# Copy to ~/.zshrc on a Mac and run `install` to bootstrap from scratch.
#
# Sections:
#   1. Oh My Zsh
#   2. PATH & environment
#   3. Shell settings
#   4. Aliases
#   5. Utility functions
#   6. fzf integration
#   7. update()   — upgrade all package managers in one shot
#   8. install()  — bootstrap a fresh Mac from scratch
#   9. doctor()   — verify & auto-fix the dev environment

# ─── 1. Oh My Zsh ────────────────────────────────────────────────────────────

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

plugins=(git)

[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# ─── 2. PATH & environment ───────────────────────────────────────────────────

export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# Homebrew — Apple Silicon (/opt/homebrew) with Intel (/usr/local) fallback
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Rust / Cargo
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# NVM / Node
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]]          && . "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"

# SDKMAN / Java
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && . "$HOME/.sdkman/bin/sdkman-init.sh"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Android SDK — default Android Studio location on macOS
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
[[ -d "$ANDROID_SDK_ROOT/platform-tools" ]]           && export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
[[ -d "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" ]] && export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

# Maestro (mobile UI testing)
[[ -d "$HOME/.maestro/bin" ]] && export PATH="$PATH:$HOME/.maestro/bin"

# ─── 3. Shell settings ───────────────────────────────────────────────────────

setopt AUTO_CD              # cd into directories by name alone
setopt CORRECT              # offer spelling correction
setopt SHARE_HISTORY        # share history across sessions
setopt HIST_IGNORE_ALL_DUPS # no duplicate history entries
setopt COMPLETE_IN_WORD     # complete from cursor position
setopt ALWAYS_TO_END        # move cursor to end after completion
setopt AUTO_MENU            # show menu on second TAB
setopt LIST_PACKED          # compact completion list
stty -ixon 2>/dev/null      # prevent Ctrl-S from freezing the terminal

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # case-insensitive
zstyle ':completion:*' menu select                          # arrow-key menu
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"     # colored completions
zstyle ':completion:*' group-name ''                        # group by category
zstyle ':completion:*:descriptions' format '%F{cyan}-- %d --%f'

# Tool-specific completions
command -v kubectl >/dev/null && source <(kubectl completion zsh 2>/dev/null)
command -v gh      >/dev/null && eval "$(gh completion -s zsh 2>/dev/null)"
command -v docker  >/dev/null && source <(docker completion zsh 2>/dev/null)

# ─── 4. Aliases ──────────────────────────────────────────────────────────────

# Navigation
alias ..='cd ..'
alias ...='cd ../..'

# Better ls — eza > lsd > default
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first --icons -F'
elif command -v lsd >/dev/null; then
  alias ls='lsd'
fi

# Git
alias g='git'
alias lg='lazygit'

# Containers — Socktainer (native, no VM) > Podman > Docker Desktop
if [[ -S "$HOME/.socktainer/container.sock" ]] && command -v docker >/dev/null; then
  export DOCKER_HOST="unix://$HOME/.socktainer/container.sock"
  alias d='docker'
  alias dc='docker compose'
elif command -v podman >/dev/null; then
  alias d='podman'
  alias dc='podman compose'
elif command -v docker >/dev/null; then
  alias d='docker'
  alias dc='docker compose'
fi

# Infrastructure
alias k='kubectl'
alias kctx='kubectl config current-context'
alias kns='kubectl config set-context --current --namespace'
alias tf='terraform'

# Misc
alias please='sudo $(fc -ln -1)'
alias hget='http --print=HBhb --download'
alias claudef='claude --dangerously-skip-permissions'

# Safety guards
alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

# ─── 5. Utility functions ────────────────────────────────────────────────────

# Print the latest GitHub release download URL matching a pattern.
#   Usage: gh_latest owner/repo <file-pattern>
gh_latest() {
  curl -s "https://api.github.com/repos/$1/releases/latest" \
    | grep "browser_download_url" \
    | grep "$2" | cut -d '"' -f 4
}

# Docker lifecycle shortcuts.
docker-start() { open -a Docker && echo "Docker Desktop starting..."; }
docker-stop()  { osascript -e 'quit app "Docker"' && echo "Docker Desktop stopped"; }
docker-nuke()  {
  echo "This will remove ALL containers, images, volumes, and networks."
  read -rq "confirm?Are you sure? [y/N] " || { echo "\nAborted."; return 1; }
  echo
  docker stop $(docker ps -aq) 2>/dev/null
  docker system prune -af --volumes
  echo "Docker nuked."
}

# Show directory sizes — dust with du fallback.
dsize() { dust -d 1 "$@" 2>/dev/null || du -h -d 1 "$@"; }

# ─── 6. fzf integration ──────────────────────────────────────────────────────

if command -v fzf >/dev/null; then
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
  source <(fzf --zsh 2>/dev/null) || true
fi

# ─── 7. update() — upgrade all package managers in one shot ──────────────────

update() {
  echo "==> brew"
  brew update && brew upgrade && brew cleanup

  echo "==> brew casks"
  brew upgrade --cask

  echo "==> rustup & cargo"
  rustup update
  cargo install-update -a 2>/dev/null || true

  echo "==> nvm (node)"
  nvm install node --reinstall-packages-from=node && nvm cache clear

  echo "==> npm"
  npm install -g npm && npm update -g

  echo "==> pnpm"
  pnpm self-update && pnpm update -g

  echo "==> pip"
  pip3 install --upgrade pip 2>/dev/null || true

  echo "==> gcloud"
  gcloud components update --quiet

  echo "==> Done!"
}

# ─── 8. install() — bootstrap a fresh Mac from scratch ───────────────────────

install() {
  echo "==> Xcode Command Line Tools"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install
    echo "       "Press Enter once the Xcode CLT installer finishes..."
    read -r
  fi

  echo "==> Homebrew"
  if ! command -v brew >/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  echo "==> Brew formulae"
  brew install git curl jq fzf eza dust httpie lazygit starship gh kubectl podman

  echo "==> Brew casks"
  brew install --cask docker android-studio visual-studio-code google-cloud-sdk

  echo "==> Rust (rustup)"
  if ! command -v rustup >/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"
  fi

  echo "==> NVM + Node"
  if [[ ! -d "$HOME/.nvm" ]]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
  fi
  nvm install node
  nvm install --lts

  echo "==> SDKMAN + Java (Liberica 25 LTS)"
  if [[ ! -d "$HOME/.sdkman" ]]; then
    curl -s "https://get.sdkman.io?rcupdate=false" | bash
  fi
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  sdk install java 25.0.2-librca <<< "Y"

  echo "==> pnpm"
  if ! command -v pnpm >/dev/null; then
    curl -fsSL https://get.pnpm.io/install.sh | sh -
  fi

  echo "==> Terraform"
  if ! command -v terraform >/dev/null; then
    brew install hashicorp/tap/terraform
  fi

  echo "==> Android SDK components"
  if command -v sdkmanager >/dev/null 2>&1; then
    yes | sdkmanager --licenses >/dev/null 2>&1
    sdkmanager "platform-tools" "build-tools;36.1.0" "platforms;android-36"
  else
    echo "       "[skip] open Android Studio first to set up the SDK, then re-run"
  fi

  echo "==> Maestro"
  if ! command -v maestro >/dev/null; then
    curl -Ls "https://get.maestro.mobile.dev" | bash
  fi

  echo "==> Socktainer (native macOS containers — requires macOS 26+ Apple Silicon)"
  if ! command -v socktainer >/dev/null; then
    brew tap socktainer/tap
    brew install socktainer
  fi

  echo "==> Oh My Zsh"
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi

  echo "==> Claude Code"
  if ! command -v claude >/dev/null; then
    npm install -g @anthropic-ai/claude-code
  fi

  echo "==> All done! Restart your shell."
}

# ─── 9. doctor() — verify & auto-fix the dev environment ────────────────────

doctor() {
  local fix=false errors=0
  [[ "$1" == "fix" ]] && fix=true

  # --- output helpers ---
  _ok()      { printf "  \033[32m✔\033[0m %s\n" "$*"; }
  _fail()    { printf "  \033[31m✘\033[0m %s\n" "$*"; ((errors++)); }
  _warn()    { printf "  \033[33m⚠\033[0m %s\n" "$*"; }
  _fix()     { printf "    \033[33m→\033[0m %s\n" "$*"; }
  _section() { printf "\n\033[1;36m%s\033[0m\n" "$*"; }

  # --- check helpers ---

  _doctor_check() {
    local name="$1" cmd="$2" fix_cmd="$3" ver_cmd="$4"
    if command -v "$cmd" >/dev/null 2>&1; then
      local ver=""
      [[ -n "$ver_cmd" ]] && ver=$(eval "$ver_cmd" 2>/dev/null)
      _ok "$name${ver:+ ($ver)}"
    else
      _fail "$name — missing"
      if $fix && [[ -n "$fix_cmd" ]]; then
        _fix "fixing: $fix_cmd"
        eval "$fix_cmd"
      fi
    fi
  }

  _doctor_check_dir() {
    local name="$1" dir="$2" fix_cmd="$3"
    if [[ -d "$dir" ]]; then
      _ok "$name"
    else
      _fail "$name — $dir not found"
      if $fix && [[ -n "$fix_cmd" ]]; then
        _fix "fixing: $fix_cmd"
        eval "$fix_cmd"
      fi
    fi
  }

  _doctor_check_env() {
    local name="$1" var="$2"
    if [[ -n "${(P)var}" ]]; then
      _ok "$name (\$$var = ${(P)var})"
    else
      _fail "$name — \$$var not set"
    fi
  }

  _doctor_check_ver() {
    local name="$1" ver="$2" min="$3" fix_cmd="$4"
    if [[ -z "$ver" ]]; then
      _fail "$name — not installed"
      if $fix && [[ -n "$fix_cmd" ]]; then
        _fix "fixing: $fix_cmd"
        eval "$fix_cmd"
      fi
      return
    fi
    local major
    major=$(echo "$ver" | sed 's/^v//' | cut -d. -f1)
    if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= min )); then
      _ok "$name ($ver)"
    else
      _fail "$name ($ver) — want >= $min"
      if $fix && [[ -n "$fix_cmd" ]]; then
        _fix "fixing: $fix_cmd"
        eval "$fix_cmd"
      fi
    fi
  }

  _doctor_check_git() {
    local key="$1" expected="$2"
    local actual
    actual=$(git config --global "$key" 2>/dev/null)
    if [[ "$actual" == "$expected" ]]; then
      _ok "$key = $actual"
    else
      if [[ -n "$actual" ]]; then
        _fail "$key = $actual (want: $expected)"
      else
        _fail "$key — not set (want: $expected)"
      fi
      $fix && git config --global "$key" "$expected" && _fix "fixed: $key = $expected"
    fi
  }

  # --- early sudo cache ---
  if ! sudo -n true 2>/dev/null; then
    _warn "Some checks need sudo — enter password now to avoid interruptions"
    sudo -v
  fi

  # --- checks ---

  _section "System tools"
  if xcode-select -p >/dev/null 2>&1; then
    _ok "Xcode CLI Tools"
  else
    _fail "Xcode CLI Tools — not installed"
    $fix && xcode-select --install
  fi
  _doctor_check "curl"    curl    ""                "curl --version | head -1 | awk '{print \$2}'"
  _doctor_check "git"     git     "brew install git" "git --version | awk '{print \$3}'"
  _doctor_check "jq"      jq      "brew install jq"
  _doctor_check "python3" python3 ""                 "python3 --version | awk '{print \$2}'"
  _doctor_check "pip3"    pip3    ""


  _section "Package managers"
  _doctor_check "Homebrew"      brew   '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"'
  _doctor_check "npm"           npm    ""                                                         "npm --version"
  _doctor_check "pnpm"          pnpm   "curl -fsSL https://get.pnpm.io/install.sh | sh -"        "pnpm --version"
  _doctor_check "Rust (cargo)"  cargo  "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . \"\$HOME/.cargo/env\""  "cargo --version | awk '{print \$2}'"
  _doctor_check "rustup"        rustup ""


  _section "Runtimes"
  _doctor_check_dir "NVM"    "$HOME/.nvm"    'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash'
  _doctor_check_ver "Node"   "$(node -v 2>/dev/null)"                                            24  "nvm install --lts"
  _doctor_check_dir "SDKMAN" "$HOME/.sdkman" 'curl -s "https://get.sdkman.io?rcupdate=false" | bash'
  _doctor_check_ver "Java"   "$(java -version 2>&1 | head -1 | tr -d '"' | cut -d' ' -f3)"       25  'source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null; sdk install java 25.0.2-librca <<< "Y"'


  _section "Containers"
  _doctor_check "Docker"      docker      "brew install --cask docker"                 "docker --version | awk '{print \$3}' | tr -d ','"
  _doctor_check "Podman"      podman      "brew install podman"                        "podman --version | awk '{print \$3}'"
  _doctor_check "Socktainer"  socktainer  "brew tap socktainer/tap && brew install socktainer"  "socktainer --version 2>/dev/null"
  _doctor_check "kubectl"     kubectl     "brew install kubectl"                       "kubectl version --client 2>/dev/null | awk '/Client Version:/{print \$3}'"


  _section "Cloud & infra"
  _doctor_check "Terraform"  terraform "brew install hashicorp/tap/terraform"  "terraform version 2>/dev/null | head -1 | awk '{print \$2}'"
  _doctor_check "gcloud"     gcloud    "brew install --cask google-cloud-sdk"  "gcloud version 2>/dev/null | head -1 | awk '{print \$4}'"
  _doctor_check "GitHub CLI" gh        "brew install gh"                       "gh --version | head -1 | awk '{print \$3}'"


  _section "CLI tools"
  _doctor_check "fzf"         fzf      "brew install fzf"       "fzf --version | awk '{print \$1}'"
  _doctor_check "eza"         eza      "brew install eza"       "eza --version 2>/dev/null | grep -m1 '^v' | awk '{print \$1}'"
  _doctor_check "dust"        dust     "brew install dust"      "dust --version | awk '{print \$2}'"
  _doctor_check "httpie"      http     "brew install httpie"    "http --version 2>/dev/null"
  _doctor_check "lazygit"     lazygit  "brew install lazygit"   "lazygit --version 2>/dev/null | grep -o 'version=[^,]*' | head -1 | cut -d= -f2"
  _doctor_check "starship"    starship "brew install starship"  "starship --version 2>/dev/null | head -1 | awk '{print \$2}'"
  _doctor_check "Claude Code" claude   "npm install -g @anthropic-ai/claude-code"  "claude --version 2>/dev/null"


  _section "Android SDK"
  _doctor_check_env "ANDROID_HOME" ANDROID_HOME
  _doctor_check_dir "cmdline-tools"  "$ANDROID_SDK_ROOT/cmdline-tools/latest" "open Android Studio to install SDK components"
  _doctor_check_dir "platform-tools" "$ANDROID_SDK_ROOT/platform-tools"       ""
  _doctor_check "sdkmanager" sdkmanager ""


  _section "Shell"
  _doctor_check_dir "Oh My Zsh" "$HOME/.oh-my-zsh" \
    'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'

  # --- security checks ---


  _section "Security"

  # FileVault
  local fv_status
  fv_status=$(fdesetup status 2>/dev/null)
  if [[ "$fv_status" == *"On"* ]]; then
    _ok "FileVault enabled"
  else
    _fail "FileVault - not enabled"
  fi

  # Gatekeeper
  local gk_status
  gk_status=$(spctl --status 2>/dev/null)
  if [[ "$gk_status" == *"enabled"* ]]; then
    _ok "Gatekeeper enabled"
  else
    _fail "Gatekeeper - disabled"
  fi

  # SIP (System Integrity Protection)
  local sip_status
  sip_status=$(csrutil status 2>/dev/null)
  if [[ "$sip_status" == *"enabled"* ]]; then
    _ok "SIP enabled"
  else
    _fail "SIP - disabled (security risk)"
  fi

  # Firewall
  local fw_status
  fw_status=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
  if [[ "$fw_status" == *"enabled"* ]]; then
    _ok "macOS firewall enabled"
  else
    _fail "macOS firewall - disabled"
    $fix && sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on && _fix "fixed"
  fi

  # SSH key
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    _ok "SSH key (Ed25519)"
  elif [[ -f "$HOME/.ssh/id_rsa" ]]; then
    _ok "SSH key (RSA - consider upgrading to Ed25519)"
  else
    _fail "SSH key - none found"
    if $fix; then
      ssh-keygen -t ed25519 -C "$USER@$(hostname)"
    fi
  fi

  # SSH directory permissions
  if [[ -d "$HOME/.ssh" ]]; then
    local ssh_perms
    ssh_perms=$(stat -f '%A' "$HOME/.ssh" 2>/dev/null)
    if [[ "$ssh_perms" == "700" ]]; then
      _ok "~/.ssh permissions ($ssh_perms)"
    else
      _fail "~/.ssh permissions ($ssh_perms) - want 700"
      $fix && chmod 700 "$HOME/.ssh" && _fix "fixed"
    fi
  fi

  # Git credential helper
  if command -v git >/dev/null 2>&1; then
    local cred_helper
    cred_helper=$(git config --global credential.helper 2>/dev/null)
    if [[ "$cred_helper" == "store" ]]; then
      _fail "git credential.helper = store (plaintext passwords!)"
      $fix && git config --global credential.helper osxkeychain && _fix "fixed: credential.helper = osxkeychain"
    elif [[ -n "$cred_helper" ]]; then
      _ok "git credential.helper = $cred_helper"
    else
      _fail "git credential.helper - not set"
      $fix && git config --global credential.helper osxkeychain && _fix "fixed: credential.helper = osxkeychain"
    fi
  fi

  # Auto-updates
  local auto_update
  auto_update=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)
  if [[ "$auto_update" == "1" ]]; then
    _ok "Automatic updates enabled"
  else
    _fail "Automatic updates - disabled"
  fi

  # --- PATH checks ---


  _section "PATH"

  # Duplicates
  local dup_count
  dup_count=$(echo "$PATH" | tr ':' '\n' | sort | uniq -d | wc -l)
  if (( dup_count > 0 )); then
    _fail "$dup_count duplicate PATH entries"
    if $fix; then
      export PATH="$(echo "$PATH" | tr ':' '\n' | awk '!seen[$0]++' | paste -sd:)"
      _fix "fixed: duplicates removed"
    fi
  else
    local total_count
    total_count=$(echo "$PATH" | tr ':' '\n' | wc -l)
    _ok "No duplicate PATH entries ($total_count total)"
  fi

  # Stale entries
  local stale_list stale_count
  stale_list=$(echo "$PATH" | tr ':' '\n' | while read -r p; do [[ -n "$p" && ! -d "$p" ]] && echo "$p"; done)
  if [[ -n "$stale_list" ]]; then
    stale_count=$(echo "$stale_list" | wc -l)
    _fail "$stale_count stale PATH entries"
    echo "$stale_list" | while read -r p; do _fix "$p"; done
    if $fix; then
      export PATH="$(echo "$PATH" | tr ':' '\n' | while read -r p; do [[ -d "$p" ]] && echo "$p"; done | paste -sd:)"
      _fix "fixed: stale entries removed"
    fi
  else
    _ok "All PATH entries exist"
  fi

  # Java PATH vs JAVA_HOME consistency
  if [[ -n "$JAVA_HOME" ]] && command -v java >/dev/null 2>&1; then
    local java_path java_home_resolved
    java_path=$(realpath "$(command -v java)" 2>/dev/null || command -v java)
    java_home_resolved=$(realpath "$JAVA_HOME" 2>/dev/null || echo "$JAVA_HOME")
    if [[ "$java_path" == "$java_home_resolved"* ]]; then
      _ok "java in PATH matches JAVA_HOME"
    else
      _fail "java in PATH ($java_path) does not match JAVA_HOME ($java_home_resolved)"
    fi
  fi

  # --- configuration checks ---


  _section "Configuration"

  # macOS version
  local macos_ver
  macos_ver=$(sw_vers -productVersion 2>/dev/null)
  local macos_major="${macos_ver%%.*}"
  if [[ -n "$macos_ver" ]]; then
    if (( macos_major >= 26 )); then
      _ok "macOS $macos_ver (Socktainer compatible)"
    else
      _ok "macOS $macos_ver (Socktainer requires macOS 26+)"
    fi
  fi

  # Git settings
  if command -v git >/dev/null 2>&1; then
    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null)
    git_email=$(git config --global user.email 2>/dev/null)
    if [[ -n "$git_name" && -n "$git_email" ]]; then
      _ok "git identity ($git_name <$git_email>)"
    else
      _fail "git identity — user.name or user.email not set"
      $fix && _fix "run: git config --global user.name 'Your Name' && git config --global user.email 'you@email.com'"
    fi

    _doctor_check_git "pull.rebase"          "false"
    _doctor_check_git "core.autocrlf"        "input"
    _doctor_check_git "core.eol"             "lf"
    _doctor_check_git "init.defaultBranch"   "main"
    _doctor_check_git "push.autoSetupRemote" "true"
    _doctor_check_git "push.default"         "current"
    _doctor_check_git "fetch.prune"          "true"
    _doctor_check_git "diff.colorMoved"      "default"
    _doctor_check_git "merge.conflictstyle"  "zdiff3"

    local git_editor
    git_editor=$(git config --global core.editor 2>/dev/null)
    if [[ -n "$git_editor" ]]; then
      _ok "core.editor = $git_editor"
    else
      _fail "core.editor — not set"
      $fix && git config --global core.editor "code --wait" && _fix "fixed: core.editor = code --wait"
    fi
  fi

  # GitHub CLI auth
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      _ok "gh authenticated"
    else
      _fail "gh — not authenticated"
      $fix && _fix "run: gh auth login"
    fi
  fi

  # Docker daemon
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      _ok "Docker daemon reachable"
    else
      _fail "Docker daemon — not running"
    fi
  fi

  # Socktainer socket
  if command -v socktainer >/dev/null 2>&1; then
    if [[ -S "$HOME/.socktainer/container.sock" ]]; then
      _ok "Socktainer socket active"
    else
      _fail "Socktainer — socket not found (run 'socktainer' to start)"
    fi
  fi

  # gcloud auth
  if command -v gcloud >/dev/null 2>&1; then
    local gcloud_acct
    gcloud_acct=$(gcloud auth list 2>/dev/null | awk '/^\*/{print $2}')
    if [[ -n "$gcloud_acct" ]]; then
      _ok "gcloud auth ($gcloud_acct)"
    else
      _fail "gcloud — no active account"
      $fix && _fix "run: gcloud auth login"
    fi
  fi

  # NVM default
  if command -v nvm >/dev/null 2>&1; then
    local nvm_default
    nvm_default=$(nvm alias default 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$nvm_default" ]]; then
      _ok "nvm default ($nvm_default)"
    else
      _fail "nvm — no default version set"
      $fix && nvm alias default node
    fi
  fi

  # JAVA_HOME
  if command -v java >/dev/null 2>&1; then
    if [[ -n "$JAVA_HOME" && -d "$JAVA_HOME" ]]; then
      _ok "JAVA_HOME set"
    else
      _fail "JAVA_HOME — not set or invalid"
    fi
  fi

  # Xcode license
  if xcode-select -p >/dev/null 2>&1; then
    if /usr/bin/xcrun clang --version >/dev/null 2>&1; then
      _ok "Xcode license accepted"
    else
      _fail "Xcode license — not accepted"
      $fix && sudo xcodebuild -license accept
    fi
  fi

  # --- cleanup helpers & summary ---

  unset -f _ok _fail _warn _fix _section _doctor_check _doctor_check_dir _doctor_check_env _doctor_check_ver _doctor_check_git

  printf "\n"
  if (( errors == 0 )); then
    printf "\033[1;32m✔ All checks passed!\033[0m\n"
  else
    printf "\033[1;31m✘ %d issue(s) found.\033[0m\n" "$errors"
    $fix || printf "  Run \033[1mdoctor fix\033[0m to auto-fix what's possible.\n"
  fi
}
