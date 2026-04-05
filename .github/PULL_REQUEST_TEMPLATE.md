## Summary
<!-- What changed and why? -->

## Platforms touched
- [ ] Linux / WSL (`shells/bashrc`, `optimize/ubuntu.sh`)
- [ ] macOS (`shells/zshrc`, `optimize/macos.sh`)
- [ ] Windows (`shells/windows.ps1`, `optimize/windows.ps1`)
- [ ] Android (`optimize/android.sh`)
- [ ] Install entry points (`install.sh`, `install.bat`)
- [ ] Docs / meta

## Cross-platform parity
<!-- If you added a tool, alias, or check, confirm it exists in all relevant shells,
     or explain why it's platform-specific. -->

## Testing
<!-- How did you verify this? Which platforms did you actually run `doctor` on? -->

- [ ] `bash -n` clean on touched shell scripts
- [ ] PowerShell parse-check clean on touched `.ps1` files
- [ ] Ran `doctor` on a real target machine

## Checklist
- [ ] No manual `((errors++))` after `_fail` calls
- [ ] No `_ok` / `_fail` / `_fix` used outside `doctor()`
- [ ] README / CLAUDE.md updated if user-visible behavior changed
- [ ] CHANGELOG.md updated under `[Unreleased]`
