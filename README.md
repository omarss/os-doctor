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

## Optimize-Windows.ps1

Standalone Windows 11 hardening script. Separate from the shell profiles.

```powershell
# Full hardening (Strict profile)
.\Optimize-Windows.ps1

# Recommended for most users
.\Optimize-Windows.ps1 -HardeningProfile Moderate

# Preview without changes
.\Optimize-Windows.ps1 -DryRun

# Interactive mode
.\Optimize-Windows.ps1 -Interactive

# Disk cleanup only
.\Optimize-Windows.ps1 -Clean
```

Creates a system restore point before changes. See the script header for full documentation.

Covers: Defender hardening, firewall, Credential Guard, HVCI, SMB signing, NTLM restrictions, ASR rules, telemetry, bloatware removal, DNS over HTTPS, exploit protection, audit policies, and more. Based on CIS Windows 11 Enterprise Benchmark.

## License

MIT
