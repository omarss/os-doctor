# os-doctor

Cross-platform dev environment bootstrap, health checker, and hardening toolkit.

## Files

| File | Platform | Shell | Deployed to |
|------|----------|-------|-------------|
| `.bashrc` | WSL / Ubuntu | bash | `~/.bashrc` |
| `macos.zshrc` | macOS | zsh | `~/.zshrc` |
| `windows.ps1` | Windows | PowerShell 5.1+ / 7+ | `$PROFILE` |
| `Optimize-Windows.ps1` | Windows | PowerShell | Standalone script |

## Key commands (all platforms)

- `doctor` — run health checks (colored output with `✔`/`✘` symbols)
- `doctor fix` — auto-fix what's possible (requests sudo/admin upfront)
- `install` — bootstrap a fresh machine from scratch
- `update` — upgrade all package managers in one shot

## Architecture

Each file follows the same section layout:

1. Shell framework (Oh My Bash / Oh My Zsh / Starship)
2. PATH & environment (guarded with existence checks, no duplicates)
3. Shell settings & aliases
4. Utility functions (gh_latest, dsize, docker-start/stop/nuke)
5. fzf integration
6. `update()` — per-platform package manager upgrades
7. `install()` — full bootstrap with auto-elevation on Windows
8. `doctor()` — comprehensive health checks

## Doctor sections

Every `doctor()` checks these in order:
System tools, Package managers, Runtimes (with version validation: Node >= 24, Java >= 25),
Containers, Cloud & infra, CLI tools, Android SDK, Shell, WSL (Linux only),
Security (firewall, SSH keys, credentials, disk encryption),
PATH (duplicates, stale entries, JAVA_HOME consistency),
Configuration (git settings, auth status, editor, pull.rebase=false, line endings)

## Conventions

- **Colored output helpers**: `_ok`, `_fail`, `_warn`, `_fix`, `_section` (bash/zsh) and `_ok`, `_fail`, `_warn`, `_fixmsg`, `_header` (PowerShell)
- **Error counting**: `_fail` increments the counter — never add `((errors++))` or `$script:errors++` after a `_fail` call
- **Fix commands**: Passed as strings to `eval` (bash/zsh) or `Invoke-Expression` (PS). Must be self-contained.
- **Version checks**: `_doctor_check_ver` validates major version >= minimum
- **Git config checks**: `_doctor_check_git` / `Check-GitConfig` validates and auto-fixes
- **PATH guards**: All PATH additions use `[[ -d ... ]]` or `Test-Path` guards
- **No `readlink -f` on macOS**: Use `realpath` instead
- **Line endings**: Linux/macOS use `core.autocrlf=input, core.eol=lf`. Windows uses `core.autocrlf=true, core.eol=native`.
- **Container priority**: Linux: Docker > Podman. macOS: Socktainer > Podman > Docker. Windows: Podman > Docker.
- **Auto-elevation**: Windows `install` and `doctor fix` auto-elevate via UAC. Detects PS version (pwsh vs powershell).
- **TLS fix**: Windows profile sets `[Net.ServicePointManager]::SecurityProtocol = Tls12` at the top for PS 5.1 compatibility.
- **Unix polyfills on Windows**: Git usr/bin added to PATH, PS aliases for curl/wget removed, functions for touch/which/head/tail/grep/wc/df/ln/export/unset.

## Tool versions (pinned)

- NVM: v0.40.4
- Java: 25.0.2-librca (Liberica LTS)
- Kubernetes apt repo: v1.35
- Android: build-tools 36.1.0, platforms android-36

## Testing changes

1. Edit the file
2. For bash: `source ~/.bashrc && doctor`
3. For Windows: restart PowerShell, run `doctor`
4. Verify no syntax errors: `bash -n .bashrc` or PS `PSParser.Tokenize()`
5. Check for double error counting after `_fail` calls
6. Check that `_ok`/`_fail`/`_fix` are not used outside `doctor()` (they're local)

## Common pitfalls

- `awk '{print $2}'` in eval'd strings: escape as `'{print \$2}'`
- `awk` in `$()` command substitution: do NOT escape `$` inside single quotes — use `cut`/`sed`/`tr` instead
- PowerShell: no `try {}` inside `if ()` — assign to variable first
- PowerShell: `2>$null` inside single-quoted strings passed to `Invoke-Expression` causes "error stream already redirected" — remove it (try/catch handles errors)
- PowerShell: no Unicode in comments/strings for PS 5.1 profiles (em dash, box drawing chars)
