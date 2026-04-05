# Contributing to os-doctor

Thanks for your interest in improving os-doctor. This guide covers how to propose changes.

## Ground rules

- **Cross-platform consistency is the headline feature.** Any tool, alias, doctor check, or fix added to one shell should have a counterpart in the others (or be explicitly marked platform-specific).
- **Doctor output stays uniform.** Use `_ok` / `_fail` / `_warn` / `_fix` on bash/zsh and `_ok` / `_fail` / `_warn` / `_fixmsg` on PowerShell. Never manually increment the error counter — `_fail` does that for you.
- **No silent side effects.** Install/fix code paths should tell the user what they're doing and request elevation up front, not midway through.

## Project layout

```
shells/        bashrc, zshrc, windows.ps1 — deployed to user profile
optimize/      standalone hardening scripts (ubuntu, macos, android, windows)
install.sh     POSIX entry point (Linux, macOS, WSL)
install.bat    Windows entry point
```

## Development workflow

1. Fork and create a feature branch off `main`.
2. Make your changes. Keep each PR focused on one concern.
3. Run the lint checks for the files you touched:
   - `bash -n shells/bashrc`
   - `bash -n optimize/ubuntu.sh` (and any other shell script)
   - For PowerShell files, open in PS 5.1+ and verify they parse: `[System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw shells/windows.ps1), [ref]$null)`
4. Verify your change by sourcing the profile and running `doctor` on a real machine of the target platform.
5. Update `README.md` and `CLAUDE.md` if you added user-visible commands or changed conventions.
6. Open a PR describing the motivation and the platforms you tested on.

## Cross-platform checklist for new tools

When adding a tool (e.g., a new CLI), confirm:

- [ ] `_doctor_check` (or `Check-Command`) added to all three shell files
- [ ] `install()` installs it on all three platforms
- [ ] `update()` upgrades it if it has a separate updater
- [ ] README "What's Included" table updated if it's user-visible

## Cross-platform checklist for security checks

- [ ] Check added to the Security section in all three shells
- [ ] Uses `_ok` / `_fail` — no manual counter increments
- [ ] Fix command is idempotent and safe to re-run
- [ ] Platform-specific nuances documented in a comment

## Common pitfalls

These are repeat offenders — please scan for them before submitting:

- `awk '{print $2}'` inside an eval'd string must escape as `'{print \$2}'`
- `readlink -f` does not exist on macOS — use `realpath`
- PowerShell 5.1 breaks on non-ASCII characters (em dash, smart quotes, box-drawing) in string literals
- `2>$null` inside single-quoted strings passed to `Invoke-Expression` double-redirects — remove it
- `_ok` / `_fail` / `_fix` are defined inside `doctor()` only — don't call them from other functions

## Reporting bugs

Open an issue with:
- Platform and version (`uname -a` or `[System.Environment]::OSVersion`)
- Shell and version
- The exact command you ran
- Expected vs actual output

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
