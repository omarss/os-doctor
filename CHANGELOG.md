# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Windows `install`: removed non-existent `pip` choco package (pip ships with `python3`)
- Windows `install`: idempotent `Add-ScoopBucket` helper — no more "bucket already exists" warnings
- Windows `install`: replaced the brittle one-liner Java install with `Install-LibericaJdk` — checks if the current install already satisfies the minimum major version and stops re-adding the scoop bucket
- Windows `install` + `doctor`: Windows optional features now skip gracefully when the feature isn't available on the current SKU (e.g., `Microsoft-Hyper-V-All` on Home editions) instead of throwing a DISM error
- Windows `doctor`: Defender signature age `65535` sentinel is now reported as a warning ("Defender disabled or inactive") instead of "65535 days old"
- Windows `doctor`: PATH cleanup now runs once when both duplicates and stale entries are present, not twice
- Windows `doctor`: Java version check now prefers `$env:JAVA_HOME\bin\java.exe` over the PATH-resolved `java`, so the version reflects the intended JDK even when an older install still sits ahead on PATH
- Windows `doctor --fix`: JAVA_HOME mismatch now offers to prepend `$env:JAVA_HOME\bin` to the session PATH (with a `setx` command for persistence)
- Windows `install`: `nvm install lts` is wrapped in try/catch so transient nodejs.org outages don't abort the whole bootstrap

### Added
- Apache 2.0 `LICENSE` and `NOTICE` files
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `CHANGELOG.md`
- `.editorconfig` and `.gitattributes` for consistent formatting and line endings
- GitHub issue and pull request templates
- GitHub Actions workflow for shell and PowerShell linting
- Shared `devenv-help` command across Bash, Zsh, and PowerShell profiles
- `.pre-commit-config.yaml` with strict shellcheck, editorconfig, actionlint, bash/zsh parse-checks, PSScriptAnalyzer, and non-ASCII guardrails
- `pre-commit` CI job that runs every hook (plus manual-stage zsh parse-check) on every push and PR

### Changed
- Reorganized repository layout: shell profiles moved to `shells/`, standalone optimizers moved to `optimize/`
- Shell files renamed without leading dots (`shells/bashrc`, `shells/zshrc`)
- Line-ending git config on Windows now matches Linux/macOS (`core.autocrlf=input`, `core.eol=lf`)
- Switched project license from MIT to Apache 2.0
- Bumped `actions/checkout` from `@v4` to `@v6` (latest stable, v6.0.2)
- Pinned `editorconfig-checker/action-editorconfig-checker` from `@main` to `@v2` (latest stable tag)
- Made PATH setup idempotent across all three shell profiles to avoid duplicate entries on repeated sourcing
- PATH additions that previously ran unconditionally (e.g., Android `platform-tools` on Bash) are now gated on directory existence — `doctor` still flags missing SDKs
- Added `--help` support to the shared `doctor`, `install`, and `update` commands, plus `--fix` support for `doctor`
- `devenv-help` accepts a topic (`doctor`, `install`, `update`) consistently across Bash, Zsh, and PowerShell
- All three shells now signal an error (exit 1 / `$LASTEXITCODE=1`) when called with an unknown argument
- Internal shell helpers prefixed with `_devenv_` to avoid polluting the user namespace
- Made `update` skip missing package managers instead of failing noisily
- Switched install entry points to timestamped profile backups before overwriting existing files

### Removed
- Stray artifact files (`Backing`, `Detected`, `Running`, `Installing`, `dotfiles.zip`, `Documents/`)
