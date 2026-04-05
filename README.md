# os-doctor

Cross-platform dev environment bootstrap, health checker, and security hardening toolkit. One set of commands — `doctor`, `install`, `update` — works the same on Linux, macOS, and Windows.

## Quick Start

```bash
# Linux / macOS — copy the right file to your shell profile
cp .bashrc ~/.bashrc        # WSL / Ubuntu
cp macos.zshrc ~/.zshrc     # macOS

# Windows — copy to your PowerShell profile
Copy-Item windows.ps1 $PROFILE

# Then in any shell:
doctor          # check everything
doctor fix      # auto-fix what's possible
install         # bootstrap a fresh machine
update          # upgrade all package managers
```

## What's Included

### Shell Profiles

| File | Platform | Shell |
|------|----------|-------|
| `.bashrc` | WSL / Ubuntu | bash + Oh My Bash |
| `macos.zshrc` | macOS | zsh + Oh My Zsh |
| `windows.ps1` | Windows | PowerShell 5.1+ / 7+ |

### Standalone Optimizers

| File | Platform | What it does |
|------|----------|--------------|
| `optimize_ubuntu.sh` | Ubuntu / WSL | Performance tuning, privacy cleanup, security hardening, cache cleanup |
| `optimize_macos.sh` | macOS | Finder/Dock tuning, privacy defaults, firewall/update hardening, cache cleanup |
| `optimize_android.sh` | Android via adb | Device-side tuning, privacy/security settings, cache trim |
| `optimize_windows.ps1` | Windows 11 | Performance, privacy, security hardening, disk cleanup |

### Commands (all platforms)

| Command | What it does |
|---------|-------------|
| `doctor` | Run 50+ health checks with colored `✔`/`✘` output |
| `doctor fix` | Auto-fix issues (requests sudo/admin upfront) |
| `install` | Bootstrap from scratch — installs all tools, runtimes, SDKs |
| `update` | Upgrade all package managers in one shot |
| `docker-start` | Start Docker daemon / Desktop |
| `docker-stop` | Stop all Docker engines |
| `docker-nuke` | Remove ALL containers, images, volumes (with confirmation) |

### Aliases (all platforms)

| Alias | Command |
|-------|---------|
| `g` | `git` |
| `lg` | `lazygit` |
| `d` | `docker` or `podman` (auto-detected) |
| `dc` | `docker compose` or `podman compose` |
| `k` | `kubectl` |
| `kctx` | `kubectl config current-context` |
| `kns` | `kubectl config set-context --current --namespace` |
| `tf` | `terraform` |
| `ls` | `eza` with icons (falls back to default) |
| `..` / `...` | Navigate up directories |

### Safety Guards

`rm`, `mv`, `cp` are aliased with confirmation flags (`-I`/`-i`) to prevent accidental destructive operations.

### Autocomplete

- **Bash**: TAB cycles through completions, colored file type hints, case-insensitive
- **Zsh**: Arrow-key menu selection, grouped by category, case-insensitive
- **PowerShell**: Predictive IntelliSense from history, ListView suggestions
- **Tool completions**: kubectl, gh, docker loaded automatically

### Unix Polyfills (Windows only)

Git for Windows Unix tools added to PATH (`grep`, `sed`, `awk`, `find`, `xargs`, etc.) plus PowerShell functions: `touch`, `which`, `head`, `tail`, `wc`, `grep`, `df`, `ln`, `export`, `unset`.

## Doctor Checks

The `doctor` command validates your entire dev environment:

```
System tools      apt, curl, git, jq, python3, wget, telnet, htop, tree
Package managers   Homebrew, npm, pnpm, cargo, rustup
Runtimes           Node >= 24 (LTS), Java >= 25 (LTS), NVM, SDKMAN
Containers         Docker, Podman, Socktainer (macOS), kubectl, kubectx, k9s
Cloud & infra      Terraform, gcloud, GitHub CLI
CLI tools          fzf, eza, dust, httpie, lazygit, starship, Claude Code
Android SDK        ANDROID_HOME, cmdline-tools, platform-tools, sdkmanager
Security           Firewall, SSH keys (Ed25519), git credentials, disk encryption
PATH               Duplicates, stale entries, JAVA_HOME consistency
Configuration      Git settings (pull.rebase, autocrlf, eol, signing, editor)
                   gh auth, gcloud auth, Docker daemon, NVM default, JAVA_HOME
```

Platform-specific checks: WSL config (appendWindowsPath, systemd, VS Code Server), Windows (Defender, Secure Boot, BitLocker, Scoop, Windows features), macOS (FileVault, Gatekeeper, SIP, Xcode license, Socktainer socket).

## Pinned Versions

| Tool | Version |
|------|---------|
| NVM | v0.40.4 |
| Java | 25.0.2-librca (Liberica LTS) |
| Kubernetes apt repo | v1.35 |
| Android build-tools | 36.1.0 |
| Android platforms | android-36 |

## optimize_windows.ps1

Standalone Windows 11 hardening script. Separate from the shell profiles.

```powershell
# Recommended for most users
.\optimize_windows.ps1

# Full hardening after compatibility review
.\optimize_windows.ps1 -HardeningProfile Strict -BlockNTLM

# Disable RDP explicitly
.\optimize_windows.ps1 -DisableRemoteDesktop

# Preview without changes
.\optimize_windows.ps1 -DryRun

# Interactive mode
.\optimize_windows.ps1 -Interactive

# Disk cleanup only
.\optimize_windows.ps1 -Clean
```

Creates a system restore point before changes. See the script header for full documentation.

Covers: Defender hardening, firewall, Credential Guard, HVCI, SMB signing, NTLM auditing, ASR rules, telemetry, bloatware removal, DNS over HTTPS, exploit protection, audit policies, and more. Strict NTLM blocking now requires explicit `-BlockNTLM`, and Remote Desktop remains available unless `-DisableRemoteDesktop` is passed. Based on CIS Windows 11 Enterprise Benchmark.

## optimize_ubuntu.sh

Standalone Ubuntu and WSL optimization script with the same high-level workflow as the Windows version.

```bash
# Full optimization with the safer default profile
sudo ./optimize_ubuntu.sh

# Stronger hardening
sudo ./optimize_ubuntu.sh --profile strict

# Preview only
sudo ./optimize_ubuntu.sh --dry-run

# Cleanup only
sudo ./optimize_ubuntu.sh --clean

# Choose categories interactively
sudo ./optimize_ubuntu.sh --interactive
```

Covers: sysctl tuning, journald limits, unattended-upgrades, UFW on native Ubuntu, SSH hardening when safe, privacy cleanup (apport, motd-news, popularity-contest), and developer cache cleanup. Detects WSL and skips Linux-native actions that do not make sense there.

## optimize_macos.sh

Standalone macOS optimization script for developer workstations.

```bash
# Full optimization with the safer default profile
sudo ./optimize_macos.sh

# Stronger hardening
sudo ./optimize_macos.sh --profile strict

# Preview only
sudo ./optimize_macos.sh --dry-run

# Cleanup only
sudo ./optimize_macos.sh --clean

# Choose categories interactively
sudo ./optimize_macos.sh --interactive
```

Covers: Dock and Finder animation tuning, privacy defaults, firewall and Gatekeeper enablement, automatic update settings, remote access shutdown, password-after-sleep enforcement, and cleanup of common developer caches such as Xcode DerivedData and Homebrew leftovers.

## optimize_android.sh

Standalone Android optimizer that runs from your workstation through adb, with no on-device script deployment required.

```bash
# Target the only connected device
./optimize_android.sh

# Target a specific device or emulator
./optimize_android.sh --serial emulator-5554

# Stronger settings
./optimize_android.sh --profile strict

# Preview only
./optimize_android.sh --dry-run

# Cleanup only
./optimize_android.sh --clean
```

Covers: animation scale tuning, always-available scan shutdown where supported, package verification for adb installs, automatic time/time zone, and maintenance commands such as cache trimming and dex optimization. OEM support varies, so unsupported keys are logged as warnings instead of aborting the run.

## License

MIT
