# Agents

## lint

Validate all three dotfiles for syntax, consistency, and common pitfalls.

### Steps
1. Run `bash -n .bashrc` and report errors
2. Run `bash -n macos.zshrc` — note that zsh-specific syntax (like `${(P)var}`) will fail in bash; only flag actual logic errors
3. Lint `windows.ps1` via `PSParser.Tokenize()` using the Windows PowerShell binary at `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe`
4. Check for double error counting: any `((errors++))` or `$script:errors++` on the line immediately after a `_fail` call is a bug — `_fail` already increments
5. Check for `_ok`, `_fail`, `_fix`, `_section` called outside `doctor()` — they are only defined inside it
6. Check for `readlink -f` in `macos.zshrc` — must be `realpath` on macOS
7. Check that `unset -f` at the end of doctor cleans up ALL helper functions
8. Verify no non-ASCII characters in `windows.ps1` (em dashes, box drawing, smart quotes break PS 5.1)

## add-tool

Add a new tool to all three dotfiles consistently.

### Inputs
- `tool_name`: the command name (e.g., `k9s`)
- `install_cmd_linux`: how to install on Linux (e.g., `brew install k9s`)
- `install_cmd_mac`: how to install on macOS (e.g., `brew install k9s`)
- `install_cmd_win`: how to install on Windows (e.g., `choco install -y k9s`)
- `ver_cmd`: optional version extraction command (e.g., `k9s version --short`)

### Steps
1. Add `_doctor_check` line to the CLI tools section in `.bashrc` with the install and version commands
2. Add matching `_doctor_check` line to `macos.zshrc`
3. Add matching `Check-Command` line to `windows.ps1`
4. If the tool needs a brew/choco install in `install()`, add it there too
5. Run the lint agent to validate

## add-security-check

Add a new security check to all three doctor commands.

### Inputs
- `check_name`: what we're checking (e.g., "Disk encryption")
- `check_cmd_linux`: bash command that returns truthy if OK
- `check_cmd_mac`: zsh command that returns truthy if OK
- `check_cmd_win`: PowerShell expression that returns truthy if OK
- `fix_cmd`: optional fix command per platform

### Steps
1. Add the check to the Security section in `.bashrc` using `_ok`/`_fail` helpers
2. Add matching check to `macos.zshrc` using `_ok`/`_fail` helpers
3. Add matching check to `windows.ps1` using `_ok`/`_fail` helpers
4. Ensure `_fail` is used (not manual `((errors++))`)
5. Run the lint agent to validate

## review

Comprehensive cross-platform consistency review.

### Steps
1. Read all three files completely
2. Compare: every tool in one file's `doctor()` should exist in the others (or be marked platform-specific)
3. Compare: every alias/function in one file should have a counterpart in the others
4. Compare: security checks should cover equivalent concerns per platform
5. Check that `install()` installs everything that `doctor()` checks for
6. Check that `update()` covers all relevant package managers per platform
7. Report a table of inconsistencies with file, line number, and what to fix
