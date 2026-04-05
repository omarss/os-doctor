<div align="center">

# os-doctor

### One toolkit. Three shells. Every platform.

**Bootstrap**, **diagnose**, **update**, and **harden** your dev environment with the same commands on Linux, macOS, Windows, WSL, and Android.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/omarss/os-doctor/lint.yml?branch=main&label=ci&logo=github)](https://github.com/omarss/os-doctor/actions/workflows/lint.yml)
[![Platforms](https://img.shields.io/badge/platforms-linux%20%7C%20macos%20%7C%20windows%20%7C%20wsl%20%7C%20android-brightgreen)](#-whats-included)
[![Shells](https://img.shields.io/badge/shells-bash%20%7C%20zsh%20%7C%20powershell-purple)](#-whats-included)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](.pre-commit-config.yaml)

```text
$ doctor
  ✔ git 2.47.0
  ✔ node v24.8.0
  ✔ docker 27.3.1
  ✘ java — not installed
    → sdk install java 25.0.2-librca
  ⚠ SSH key uses rsa (prefer ed25519)

8 checks failed — run `doctor --fix` to repair
```

</div>

---

## ✨ Why os-doctor?

Setting up a dev machine means remembering dozens of install steps, debugging PATH conflicts, and hoping your Windows box matches your teammate's Mac. **os-doctor replaces that entire ritual with three commands that behave identically everywhere:**

| | What it does |
|---|---|
| 🩺 **`doctor`** | Audits 50+ tools, PATH entries, git config, and security posture. Reports `✔` / `✘` / `⚠` with color, and tells you exactly how to fix each failure. |
| 🔧 **`doctor --fix`** | Actually runs those fixes. Requests sudo/admin upfront so you can walk away. |
| 📦 **`install`** | Bootstraps a fresh machine from scratch — package managers, runtimes, SDKs, CLI tools. |
| ⬆️ **`update`** | Upgrades every package manager in one shot. Skips anything you haven't installed. |

Plus `optimize/*` scripts for OS-level **hardening** (CIS-style benchmarks for Windows, Ubuntu, macOS, and Android).

---

## 🚀 Quick Start

### Linux / macOS / WSL

```bash
git clone https://github.com/omarss/os-doctor.git && cd os-doctor
./install.sh          # auto-detects OS, installs the right profile
```

### Windows

```powershell
git clone https://github.com/omarss/os-doctor.git; cd os-doctor
.\install.bat          # or double-click in Explorer
```

### Manual install

<details>
<summary>Copy the profile yourself</summary>

```bash
# Linux / WSL
cp shells/bashrc ~/.bashrc && source ~/.bashrc

# macOS
cp shells/zshrc ~/.zshrc && source ~/.zshrc
```

```powershell
# Windows PowerShell
Copy-Item shells/windows.ps1 $PROFILE
. $PROFILE
```
</details>

After installing, restart your shell and run `doctor` to see where you stand.

---

## 📖 Table of Contents

- [The Three Commands](#-the-three-commands)
- [What's Included](#-whats-included)
- [Doctor Checks](#-doctor-checks)
- [Optimizers (OS Hardening)](#-optimizers-os-hardening)
- [Architecture](#-architecture)
- [Pinned Versions](#-pinned-versions)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🎯 The Three Commands

Every command works the same on every platform. Every command supports `--help`.

```bash
doctor                   # run all health checks
doctor --fix             # fix what can be fixed automatically
doctor --help            # usage

install                  # bootstrap a fresh machine
update                   # upgrade every installed package manager

devenv-help              # show the full command reference
devenv-help doctor       # per-command detail
```

**Extra commands** bundled with the profile:

| Command | Description |
|---|---|
| 🐳 `docker-start` / `docker-stop` | Start or stop Docker (daemon on Linux, Desktop on macOS/Windows) |
| 💣 `docker-nuke` | Remove **all** containers, images, volumes — with confirmation |
| 📂 `dsize [path]` | Show directory sizes (uses `dust` if available, else `du`) |
| 🔗 `gh_latest owner/repo <pattern>` | Get the latest GitHub release download URL |

---

## 📦 What's Included

### Shell profiles

| File | Platform | Shell framework |
|---|---|---|
| [`shells/bashrc`](shells/bashrc) | Linux · WSL · Ubuntu | bash + Oh My Bash |
| [`shells/zshrc`](shells/zshrc) | macOS | zsh + Oh My Zsh |
| [`shells/windows.ps1`](shells/windows.ps1) | Windows | PowerShell 5.1+ / 7+ |

### Aliases (all platforms)

| Alias | Expands to | | Alias | Expands to |
|---|---|---|---|---|
| `g` | `git` | | `k` | `kubectl` |
| `lg` | `lazygit` | | `kctx` | `kubectl config current-context` |
| `d` | `docker` or `podman` | | `kns` | `kubectl config set-context --current --namespace` |
| `dc` | `docker compose` | | `tf` | `terraform` |
| `ls` | `eza` with icons | | `..` · `...` | navigate up |

🛡️ **Safety guards.** `rm`, `mv`, `cp` are aliased with `-i`/`-I` to require confirmation before destructive writes.

### Autocomplete

- **Bash** — TAB cycles completions, colored file-type hints, case-insensitive
- **Zsh** — arrow-key menu select, grouped by category, colored
- **PowerShell** — predictive IntelliSense from history, ListView suggestions
- **Auto-loaded completions** — `kubectl`, `gh`, `docker`

### Unix polyfills *(Windows only)*

Git-for-Windows `usr\bin` goes on PATH (`grep`, `sed`, `awk`, `find`, `xargs`, …) plus PowerShell functions for `touch`, `which`, `head`, `tail`, `wc`, `grep`, `df`, `ln`, `export`, `unset`.

---

## 🩺 Doctor Checks

`doctor` validates your entire dev environment across **ten categories**:

| Category | What's verified |
|---|---|
| 🛠️ **System tools** | `apt`, `curl`, `git`, `jq`, `python3`, `wget`, `telnet`, `htop`, `tree` |
| 📦 **Package managers** | Homebrew · `npm` · `pnpm` · `cargo` · `rustup` · `winget` · `choco` · `scoop` |
| ⚙️ **Runtimes** | Node ≥ 24 (LTS) · Java ≥ 25 (LTS) · NVM · SDKMAN |
| 🐳 **Containers** | Docker · Podman · Socktainer *(macOS)* · `kubectl` · `kubectx` · `k9s` |
| ☁️ **Cloud & infra** | Terraform · gcloud · GitHub CLI |
| 🔧 **CLI tools** | `fzf` · `eza` · `dust` · `httpie` · `lazygit` · `starship` · Claude Code |
| 📱 **Android SDK** | `ANDROID_HOME` · `cmdline-tools` · `platform-tools` · `sdkmanager` |
| 🔒 **Security** | Firewall · SSH keys (Ed25519) · git credentials · disk encryption |
| 🧭 **PATH** | Duplicates · stale entries · `JAVA_HOME` consistency |
| ⚙️ **Configuration** | Git settings · auth status · editor · `pull.rebase` · line endings |

**Platform extras:**

<table>
<tr>
<td align="center">🐧 <b>Linux / WSL</b></td>
<td align="center">🪟 <b>Windows</b></td>
<td align="center">🍎 <b>macOS</b></td>
</tr>
<tr>
<td valign="top">

- WSL `appendWindowsPath`
- `systemd` enabled
- VS Code Server

</td>
<td valign="top">

- Defender status
- Secure Boot
- BitLocker
- Scoop, Windows features

</td>
<td valign="top">

- FileVault
- Gatekeeper
- SIP
- Xcode license
- Socktainer socket

</td>
</tr>
</table>

---

## 🛡️ Optimizers (OS Hardening)

Standalone scripts in `optimize/` that go beyond the shell profile and harden the underlying OS. Each follows the same workflow: **default** profile ships safe settings, **strict** profile turns on aggressive hardening, **`--dry-run`** shows you everything first.

| Script | Platform | Based on |
|---|---|---|
| [`optimize/windows.ps1`](optimize/windows.ps1) | Windows 11 | CIS Windows 11 Enterprise Benchmark |
| [`optimize/ubuntu.sh`](optimize/ubuntu.sh) | Ubuntu · WSL | CIS Ubuntu Benchmark |
| [`optimize/macos.sh`](optimize/macos.sh) | macOS | Apple Platform Security guidance |
| [`optimize/android.sh`](optimize/android.sh) | Android *(via adb)* | AOSP best practices |

### Common flags

Every optimizer understands the same surface area:

```bash
<script>                  # default safe profile
<script> --profile strict # stronger hardening
<script> --dry-run        # preview without changes
<script> --clean          # cleanup only
<script> --interactive    # pick categories to run
```

<details>
<summary>🪟 <b>Windows 11 hardening</b> — Defender, Credential Guard, HVCI, SMB signing, DNS over HTTPS, telemetry, bloatware removal, ASR rules…</summary>

```powershell
.\optimize\windows.ps1                              # recommended default
.\optimize\windows.ps1 -HardeningProfile Strict -BlockNTLM
.\optimize\windows.ps1 -DisableRemoteDesktop
.\optimize\windows.ps1 -DryRun
.\optimize\windows.ps1 -Interactive
.\optimize\windows.ps1 -Clean
```

Creates a system restore point before changes. Strict NTLM blocking requires explicit `-BlockNTLM`; Remote Desktop stays available unless `-DisableRemoteDesktop` is passed.
</details>

<details>
<summary>🐧 <b>Ubuntu / WSL</b> — sysctl tuning, journald limits, unattended-upgrades, UFW, SSH hardening, privacy cleanup…</summary>

```bash
sudo ./optimize/ubuntu.sh                  # default safe profile
sudo ./optimize/ubuntu.sh --profile strict
sudo ./optimize/ubuntu.sh --dry-run
sudo ./optimize/ubuntu.sh --clean
sudo ./optimize/ubuntu.sh --interactive
```

Detects WSL and skips Linux-native actions that don't apply there.
</details>

<details>
<summary>🍎 <b>macOS</b> — Dock/Finder tuning, firewall, Gatekeeper, FileVault nudging, cache cleanup…</summary>

```bash
sudo ./optimize/macos.sh
sudo ./optimize/macos.sh --profile strict
sudo ./optimize/macos.sh --dry-run
sudo ./optimize/macos.sh --clean
sudo ./optimize/macos.sh --interactive
```

Cleans Xcode DerivedData, Homebrew leftovers, and common developer caches.
</details>

<details>
<summary>📱 <b>Android</b> — animation scales, scan shutdown, package verification, dex optimization (via adb, no on-device script)…</summary>

```bash
./optimize/android.sh                          # auto-target single device
./optimize/android.sh --serial emulator-5554
./optimize/android.sh --profile strict
./optimize/android.sh --dry-run
./optimize/android.sh --clean
```

OEM support varies — unsupported keys are logged as warnings instead of aborting.
</details>

---

## 🏗️ Architecture

Every shell profile follows the same nine-section layout, so jumping between `bashrc` / `zshrc` / `windows.ps1` feels the same:

```
1. Shell framework        → Oh My Bash · Oh My Zsh · Starship
2. PATH & environment     → idempotent, guarded, deduped
3. Shell settings         → autocomplete, completions (kubectl, gh, docker)
4. Aliases                → navigation · containers · infra · safety
5. Utility functions      → gh_latest · dsize · docker-{start,stop,nuke}
6. fzf integration        → Ctrl-R history search
7. update()               → per-platform package manager upgrades
8. install()              → full bootstrap with auto-elevation (Windows)
9. doctor()               → health checks with colored output
```

### Repo layout

```
os-doctor/
├── shells/               # profiles deployed to user ($HOME, $PROFILE)
│   ├── bashrc            # Linux · WSL
│   ├── zshrc             # macOS
│   └── windows.ps1       # Windows PowerShell 5.1+ / 7+
├── optimize/             # standalone OS-hardening scripts
│   ├── ubuntu.sh · macos.sh · android.sh · windows.ps1
├── install.sh            # POSIX entry point (Linux · macOS · WSL)
├── install.bat           # Windows entry point
├── .github/              # CI workflows + issue/PR templates
├── .pre-commit-config.yaml
└── CLAUDE.md · AGENTS.md # contributor & agent guidance
```

---

## 📌 Pinned Versions

| Tool | Version |
|---|---|
| NVM | [v0.40.4](https://github.com/nvm-sh/nvm/releases/tag/v0.40.4) |
| Java | [25.0.2-librca](https://bell-sw.com/pages/downloads/) *(Liberica LTS)* |
| Kubernetes apt repo | v1.35 |
| Android build-tools | 36.1.0 |
| Android platforms | android-36 |

Upgrade policy: **latest stable** for actions/workflows, **latest LTS** for runtimes.

---

## 🤝 Contributing

PRs welcome! Please read [**CONTRIBUTING.md**](CONTRIBUTING.md) — it covers the cross-platform parity checklist, lint workflow (`pre-commit install && pre-commit run --all-files`), and common pitfalls.

- 🐛 [Report a bug](https://github.com/omarss/os-doctor/issues/new?template=bug_report.md)
- ✨ [Request a feature](https://github.com/omarss/os-doctor/issues/new?template=feature_request.md)
- 🔒 Security issue? See [**SECURITY.md**](SECURITY.md) — please **don't** open a public issue
- 📜 [Code of Conduct](CODE_OF_CONDUCT.md)

---

## 📜 License

Licensed under the [**Apache License 2.0**](LICENSE). See [NOTICE](NOTICE) for attribution.

<div align="center">

---

Made with care for developers who hop between machines.

**[⬆ Back to top](#os-doctor)**

</div>
