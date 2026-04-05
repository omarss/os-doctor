# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Apache 2.0 `LICENSE` and `NOTICE` files
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `CHANGELOG.md`
- `.editorconfig` and `.gitattributes` for consistent formatting and line endings
- GitHub issue and pull request templates
- GitHub Actions workflow for shell and PowerShell linting
- Shared `devenv-help` command across Bash, Zsh, and PowerShell profiles

### Changed
- Reorganized repository layout: shell profiles moved to `shells/`, standalone optimizers moved to `optimize/`
- Shell files renamed without leading dots (`shells/bashrc`, `shells/zshrc`)
- Line-ending git config on Windows now matches Linux/macOS (`core.autocrlf=input`, `core.eol=lf`)
- Switched project license from MIT to Apache 2.0
- Bumped `actions/checkout` from `@v4` to `@v6` (latest stable, v6.0.2)
- Pinned `editorconfig-checker/action-editorconfig-checker` from `@main` to `@v2` (latest stable tag)
- Made PATH setup idempotent across all three shell profiles to avoid duplicate entries on repeated sourcing
- Added `--help` support to the shared `doctor`, `install`, and `update` commands, plus `--fix` support for `doctor`
- Made `update` skip missing package managers instead of failing noisily
- Switched install entry points to timestamped profile backups before overwriting existing files

### Removed
- Stray artifact files (`Backing`, `Detected`, `Running`, `Installing`, `dotfiles.zip`, `Documents/`)
