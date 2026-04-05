# $PROFILE - Omar's dev environment for Windows
#
# Copy to $PROFILE path (run: echo $PROFILE) and run Install-DevEnv to bootstrap.
#
# Sections:
#   1. Prompt (Oh My Posh / Starship)
#   2. PATH & environment
#   3. Aliases & functions
#   4. Utility functions
#   5. fzf integration
#   6. Update-DevEnv  - upgrade all package managers in one shot
#   7. Install-DevEnv - bootstrap a fresh Windows machine from scratch
#   8. Test-DevEnv    - verify & auto-fix the dev environment (doctor)

# Ensure TLS 1.2 for all web requests (Windows PowerShell 5.1 defaults to old TLS)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Track how this script was loaded so elevated relaunches can source the same file.
$script:DevEnvScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $PROFILE }
$script:DevEnvInteractiveConsole = $false
try {
    $script:DevEnvInteractiveConsole = $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
} catch {
    $script:DevEnvInteractiveConsole = $false
}

function Add-PathEntry {
    param(
        [string]$Path,
        [ValidateSet('Prepend', 'Append')]
        [string]$Position = 'Prepend'
    )

    if (-not $Path -or -not (Test-Path $Path)) {
        return
    }

    $normalized = $Path.TrimEnd('\')
    $entries = @($env:PATH -split ';' | Where-Object { $_ })
    $existing = @($entries | ForEach-Object { $_.TrimEnd('\') })
    if ($existing -contains $normalized) {
        return
    }

    if ($Position -eq 'Append') {
        $env:PATH = if ($env:PATH) { "$env:PATH;$normalized" } else { $normalized }
    } else {
        $env:PATH = if ($env:PATH) { "$normalized;$env:PATH" } else { $normalized }
    }
}

# --- 1. Prompt ----------------------------------------------------------------

# Starship prompt (if installed)
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# --- 2. PATH & environment ---------------------------------------------------

# Android SDK
$env:ANDROID_SDK_ROOT = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_HOME     = $env:ANDROID_SDK_ROOT
Add-PathEntry "$env:ANDROID_SDK_ROOT\platform-tools"
Add-PathEntry "$env:ANDROID_SDK_ROOT\cmdline-tools\latest\bin"

# Maestro
Add-PathEntry "$env:USERPROFILE\.maestro\bin"

# NVM for Windows
$env:NVM_DIR = "$env:APPDATA\nvm"

# pnpm
$env:PNPM_HOME = "$env:LOCALAPPDATA\pnpm"
Add-PathEntry $env:PNPM_HOME

# --- 3. Unix polyfills & aliases ---------------------------------------------

# Remove PowerShell aliases that shadow real Unix tools with incompatible behavior
Remove-Item Alias:curl  -Force -ErrorAction SilentlyContinue  # PS aliases curl -> Invoke-WebRequest
Remove-Item Alias:wget  -Force -ErrorAction SilentlyContinue  # PS aliases wget -> Invoke-WebRequest

# Add Git for Windows Unix tools to PATH (grep, sed, awk, find, xargs, etc.)
$gitUsrBin = "${env:ProgramFiles}\Git\usr\bin"
Add-PathEntry $gitUsrBin -Position Append

# Common Unix commands missing from Windows
function touch { param([string[]]$Paths) foreach ($p in $Paths) { if (Test-Path $p) { (Get-Item $p).LastWriteTime = Get-Date } else { New-Item -ItemType File -Path $p -Force | Out-Null } } }
function which { param([string]$Name) (Get-Command $Name -ErrorAction SilentlyContinue).Source }
function head  { param([int]$n = 10) $input | Select-Object -First $n }
function tail  { param([int]$n = 10) $input | Select-Object -Last $n }
function wc    { $input | Measure-Object -Line -Word -Character }
function grep  { param([string]$Pattern) $input | Select-String -Pattern $Pattern }
function df    { Get-PSDrive -PSProvider FileSystem | Format-Table Name, @{N='Used(GB)';E={[math]::Round($_.Used/1GB,1)}}, @{N='Free(GB)';E={[math]::Round($_.Free/1GB,1)}} }
function ln    { param([string]$Target, [string]$Link) New-Item -ItemType SymbolicLink -Path $Link -Target $Target }
function export { param([string]$Assignment) $parts = $Assignment -split '=',2; [Environment]::SetEnvironmentVariable($parts[0], $parts[1], 'Process') }
function unset  { param([string]$Name) Remove-Item "env:$Name" -ErrorAction SilentlyContinue }

# Navigation
function .. { Set-Location .. }
function ... { Set-Location ..\.. }

# Better ls - eza > default
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza --group-directories-first --icons -F @args }
}

# Git
Set-Alias -Name g   -Value git
Set-Alias -Name lg  -Value lazygit

# Containers - Podman with Docker fallback
if (Get-Command podman -ErrorAction SilentlyContinue) {
    Set-Alias -Name d -Value podman
    function dc { podman compose @args }
} elseif (Get-Command docker -ErrorAction SilentlyContinue) {
    Set-Alias -Name d -Value docker
    function dc { docker compose @args }
}

# Infrastructure
Set-Alias -Name k  -Value kubectl
function kctx { kubectl config current-context }
function kns { kubectl config set-context --current --namespace @args }
Set-Alias -Name tf -Value terraform

# Misc
function hget { http --print=HBhb --download @args }
function claudef { claude --dangerously-skip-permissions @args }

# WSL
function wsl-update { wsl --update }
function wsl-shutdown { wsl --shutdown }
function wsl-status { wsl --list --verbose }

# Docker lifecycle shortcuts
function docker-start { Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue; Write-Host "Docker Desktop starting..." }
function docker-stop  { Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue; Write-Host "Docker Desktop stopped" }
function docker-nuke  {
    Write-Host "This will remove ALL containers, images, volumes, and networks." -ForegroundColor Red
    $confirm = Read-Host "Are you sure? [y/N]"
    if ($confirm -ne 'y') { Write-Host "Aborted."; return }
    $running = docker ps -aq 2>$null
    if ($running) { docker stop $running }
    docker system prune -af --volumes
    Write-Host "Docker nuked." -ForegroundColor Green
}

# --- 4. Utility functions ----------------------------------------------------

# Print the latest GitHub release download URL matching a pattern.
function Get-GHLatest {
    param([string]$Repo, [string]$Pattern)
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    $release.assets | Where-Object { $_.name -like "*$Pattern*" } | Select-Object -ExpandProperty browser_download_url
}

function Get-DevEnvEntryScript {
    if ($script:DevEnvScriptPath -and (Test-Path $script:DevEnvScriptPath)) {
        return $script:DevEnvScriptPath
    }
    return $PROFILE
}

function Write-Skip {
    param([string]$Message)
    Write-Host "       [skip] $Message" -ForegroundColor DarkGray
}

# Add a Scoop bucket only if it doesn't already exist (idempotent).
function Add-ScoopBucket {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { return }
    $bucketDir = Join-Path $env:USERPROFILE "scoop\buckets\$Name"
    if (Test-Path $bucketDir) { return }
    scoop bucket add $Name | Out-Null
}

# Install Liberica JDK via Scoop, skipping if the current binary already
# satisfies the minimum major version ($MinMajor). Handles PATH precedence
# by nudging the Scoop shim to the front.
function Install-LibericaJdk {
    param([int]$MinMajor = 25)
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        choco install -y --no-progress liberica-jdk
        return
    }
    Add-ScoopBucket java
    $installed = scoop list liberica-jdk 2>$null | Out-String
    if ($installed -match '(?m)liberica-jdk\s+(\d+)') {
        $have = [int]$matches[1]
        if ($have -ge $MinMajor) {
            Write-Host "       liberica-jdk $have already installed (>= $MinMajor)" -ForegroundColor DarkGray
            return
        }
        scoop update liberica-jdk | Out-Null
    } else {
        scoop install java/liberica-jdk | Out-Null
    }
}

function Show-DevEnvUsage {
    param(
        [ValidateSet('all', 'doctor', 'install', 'update')]
        [string]$Topic = 'all'
    )

    switch ($Topic) {
        'doctor' {
            @'
Usage: doctor [fix|--fix]
Check tools, PATH, security, and configuration.

Examples:
  doctor
  doctor --fix
'@.Trim() | Write-Host
        }
        'install' {
            @'
Usage: install
Bootstrap this machine with the tools and settings defined in this profile.
'@.Trim() | Write-Host
        }
        'update' {
            @'
Usage: update
Update installed package managers and developer toolchains.
Missing package managers are skipped automatically.
'@.Trim() | Write-Host
        }
        default {
            @'
Available commands:
  doctor [fix|--fix]  Check tools, PATH, security, and configuration
  install             Bootstrap this machine with the configured toolchain
  update              Update installed package managers and CLIs

Examples:
  doctor
  doctor --fix
  install
  update
'@.Trim() | Write-Host
        }
    }
}

function devenv-help {
    if ($args.Count -eq 0) { Show-DevEnvUsage; return }
    if ($args.Count -gt 1) {
        Write-Host "devenv-help: expected at most one topic" -ForegroundColor Red
        $global:LASTEXITCODE = 1
        return
    }
    $topic = $args[0]
    if ($topic -in @('-h', '--help', 'help', 'all')) { Show-DevEnvUsage; return }
    if ($topic -in @('doctor', 'install', 'update')) { Show-DevEnvUsage $topic; return }
    Write-Host "devenv-help: unknown topic '$topic' (try: doctor, install, update)" -ForegroundColor Red
    $global:LASTEXITCODE = 1
}

# Show directory sizes
function dsize {
    if (Get-Command dust -ErrorAction SilentlyContinue) {
        dust -d 1 @args
    } else {
        Get-ChildItem -Directory @args | ForEach-Object {
            $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            [PSCustomObject]@{ Name = $_.Name; Size = "{0:N2} MB" -f ($size / 1MB) }
        }
    }
}

# Deduplicate PATH and remove non-existent directories.
function Clean-Path {
    $clean = $env:PATH -split ';' |
        Where-Object { $_ -ne '' } |
        ForEach-Object { $_.TrimEnd('\') } |
        Select-Object -Unique |
        Where-Object { Test-Path $_ }
    $env:PATH = $clean -join ';'
    Write-Host "PATH cleaned: $($clean.Count) entries"
}

# --- 5. Autocomplete & PSReadLine --------------------------------------------

# Tab completion: show menu, cycle with Tab/Shift-Tab
if ($script:DevEnvInteractiveConsole -and (Get-Module -ListAvailable PSReadLine)) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -EditMode Windows
        if ((Get-Module PSReadLine).Version -ge [version]'2.1.0') {
            Set-PSReadLineOption -PredictionSource History
            Set-PSReadLineOption -PredictionViewStyle ListView
        }
        Set-PSReadLineOption -ShowToolTips
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
        Set-PSReadLineKeyHandler -Key Shift+Tab -Function MenuComplete
    } catch {
        Write-Verbose "Skipping PSReadLine configuration in this host."
    }
}

# kubectl completion
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    kubectl completion powershell 2>$null | Out-String | Invoke-Expression
}

# --- 6. fzf integration ------------------------------------------------------

if ($script:DevEnvInteractiveConsole -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border'

    # Ctrl-R history search via fzf
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
        $line = (Get-History | Select-Object -ExpandProperty CommandLine | Sort-Object -Unique |
            fzf --tac --no-sort)
        if ($line) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($line)
        }
    }
}

# --- 6. Update-DevEnv - upgrade all package managers in one shot -------------

# Alias to match Linux/macOS
function update {
    if ($args.Count -eq 0) {
        Update-DevEnv
        return
    }
    if ($args.Count -eq 1 -and $args[0] -in @('--help', '-h', 'help')) {
        Show-DevEnvUsage update
        return
    }
    Write-Host "update: unknown argument '$($args[0])'" -ForegroundColor Red
    Show-DevEnvUsage update
    $global:LASTEXITCODE = 1
}

function Update-DevEnv {
    Write-Host "==> winget" -ForegroundColor Cyan
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget upgrade --all --accept-source-agreements --accept-package-agreements
    } else {
        Write-Skip "winget not installed"
    }

    Write-Host "==> choco" -ForegroundColor Cyan
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        choco upgrade all -y
    } else {
        Write-Skip "choco not installed"
    }

    Write-Host "==> scoop" -ForegroundColor Cyan
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop update *
    } else {
        Write-Skip "scoop not installed"
    }

    Write-Host "==> rustup & cargo" -ForegroundColor Cyan
    if (Get-Command rustup -ErrorAction SilentlyContinue) {
        rustup update
        if (Get-Command cargo -ErrorAction SilentlyContinue) {
            cargo install-update -a 2>$null
        }
    } else {
        Write-Skip "rustup not installed"
    }

    Write-Host "==> nvm (node LTS)" -ForegroundColor Cyan
    if (Get-Command nvm -ErrorAction SilentlyContinue) {
        nvm install lts
        nvm use lts
    } else {
        Write-Skip "nvm not installed"
    }

    Write-Host "==> npm" -ForegroundColor Cyan
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        npm install -g npm
        npm update -g
    } else {
        Write-Skip "npm not installed"
    }

    Write-Host "==> pnpm" -ForegroundColor Cyan
    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        pnpm self-update
        pnpm update -g
    } else {
        Write-Skip "pnpm not installed"
    }

    Write-Host "==> gcloud" -ForegroundColor Cyan
    if (Get-Command gcloud -ErrorAction SilentlyContinue) {
        gcloud components update --quiet
    } else {
        Write-Skip "gcloud not installed"
    }

    Write-Host "==> WSL" -ForegroundColor Cyan
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        wsl --update
    } else {
        Write-Skip "wsl not installed"
    }

    Write-Host "==> Done!" -ForegroundColor Green
}

# --- 7. Install-DevEnv - bootstrap a fresh Windows machine from scratch ------

function install {
    if ($args.Count -eq 0) {
        Install-DevEnv
        return
    }
    if ($args.Count -eq 1 -and $args[0] -in @('--help', '-h', 'help')) {
        Show-DevEnvUsage install
        return
    }
    Write-Host "install: unknown argument '$($args[0])'" -ForegroundColor Red
    Show-DevEnvUsage install
    $global:LASTEXITCODE = 1
}

function Install-DevEnv {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        if (-not $script:DevEnvInteractiveConsole) {
            Write-Host "Install-DevEnv requires an elevated interactive PowerShell session." -ForegroundColor Yellow
            return
        }
        Write-Host "Elevating to Administrator (UAC prompt)..." -ForegroundColor Yellow
        $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        $entryScript = (Get-DevEnvEntryScript).Replace("'", "''")
        $argString = "-NoProfile -ExecutionPolicy RemoteSigned -Command ""& { . '$entryScript'; Install-DevEnv }"""
        Start-Process $psExe -Verb RunAs -ArgumentList $argString -Wait
        Write-Host "Admin install complete. Restart your terminal." -ForegroundColor Green
        return
    }

    # Chocolatey
    Write-Host "==> Chocolatey" -ForegroundColor Cyan
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }

    # Scoop (user-level package manager)
    Write-Host "==> Scoop" -ForegroundColor Cyan
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        curl.exe -fsSL --ssl-no-revoke https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1 -o "$env:TEMP\scoop-install.ps1"
        if (Test-Path "$env:TEMP\scoop-install.ps1") {
            & "$env:TEMP\scoop-install.ps1" -RunAsAdmin
        } else {
            Write-Host "       download failed - install manually in pwsh: irm get.scoop.sh | iex" -ForegroundColor Yellow
        }
    }
    Add-ScoopBucket extras
    Add-ScoopBucket java

    # Core tools via Chocolatey (pip ships with python3 - don't install separately)
    Write-Host "==> Choco packages" -ForegroundColor Cyan
    choco install -y --no-progress `
        git curl jq unzip `
        python3 `
        docker-desktop podman-cli `
        kubernetes-cli terraform `
        gh fzf eza dust lazygit starship `
        vscode android-studio

    # httpie via pip (choco package is broken)
    Write-Host "==> httpie (pip)" -ForegroundColor Cyan
    if (Get-Command pip -ErrorAction SilentlyContinue) {
        pip install --quiet --upgrade httpie
    } else {
        Write-Skip "pip not found (python3 install may need a shell restart)"
    }

    # Rust
    Write-Host "==> Rust (rustup)" -ForegroundColor Cyan
    if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
        Invoke-WebRequest -Uri https://win.rustup.rs/x86_64 -OutFile "$env:TEMP\rustup-init.exe"
        & "$env:TEMP\rustup-init.exe" -y
        $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
    }

    # NVM for Windows + Node
    Write-Host "==> NVM for Windows + Node" -ForegroundColor Cyan
    if (-not (Get-Command nvm -ErrorAction SilentlyContinue)) {
        choco install -y --no-progress nvm
        if (Get-Command refreshenv -ErrorAction SilentlyContinue) { refreshenv }
    }
    if (Get-Command nvm -ErrorAction SilentlyContinue) {
        try {
            nvm install lts
            nvm use lts
        } catch {
            Write-Skip "nvm install failed (transient network error?) - re-run 'nvm install lts' later"
        }
    } else {
        Write-Skip "nvm not on PATH yet - open a new terminal and run 'nvm install lts'"
    }

    # Java via Scoop (Liberica LTS)
    Write-Host "==> Java (Liberica LTS via Scoop)" -ForegroundColor Cyan
    Install-LibericaJdk

    # pnpm
    Write-Host "==> pnpm" -ForegroundColor Cyan
    if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
        npm install -g pnpm
    }

    # gcloud CLI
    Write-Host "==> gcloud CLI" -ForegroundColor Cyan
    if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
        choco install -y gcloudsdk
    }

    # Claude Code
    Write-Host "==> Claude Code" -ForegroundColor Cyan
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        npm install -g @anthropic-ai/claude-code
    }

    # Maestro
    Write-Host "==> Maestro" -ForegroundColor Cyan
    if (-not (Get-Command maestro -ErrorAction SilentlyContinue)) {
        Write-Host "       Install from https://maestro.mobile.dev - Windows support is manual"
    }

    # WSL
    Write-Host "==> WSL" -ForegroundColor Cyan
    $wslInstalled = wsl --list --quiet 2>$null
    if (-not $wslInstalled) {
        wsl --install --distribution Ubuntu --no-launch
        Write-Host "       WSL installed - run 'wsl' to finish Ubuntu setup"
    } else {
        wsl --update
    }

    # Windows optional features
    Write-Host "==> Windows optional features (Telnet, SSH, Hyper-V)" -ForegroundColor Cyan
    $features = @(
        "TelnetClient",
        "Microsoft-Hyper-V-All",
        "VirtualMachinePlatform",
        "Microsoft-Windows-Subsystem-Linux"
    )
    foreach ($feat in $features) {
        $info = Get-WindowsOptionalFeature -Online -FeatureName $feat -ErrorAction SilentlyContinue
        if (-not $info) {
            Write-Skip "$feat not available on this Windows SKU"
            continue
        }
        if ($info.State -ne "Enabled") {
            Write-Host "       enabling $feat..."
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName $feat -NoRestart -ErrorAction Stop | Out-Null
            } catch {
                Write-Skip "$feat could not be enabled: $($_.Exception.Message)"
            }
        }
    }

    # OpenSSH client
    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
    }

    Write-Host "==> All done! Restart your terminal." -ForegroundColor Green
}

# --- 8. Test-DevEnv - verify & auto-fix the dev environment (doctor) --------

# Alias to match Linux/macOS: doctor / doctor fix
function doctor {
    if ($args.Count -eq 0) {
        Test-DevEnv
        return
    }
    if ($args.Count -eq 1 -and $args[0] -in @('fix', '--fix', '-f')) {
        Test-DevEnv -Fix
        return
    }
    if ($args.Count -eq 1 -and $args[0] -in @('--help', '-h', 'help')) {
        Show-DevEnvUsage doctor
        return
    }
    Write-Host "doctor: unknown argument '$($args[0])'" -ForegroundColor Red
    Show-DevEnvUsage doctor
    $global:LASTEXITCODE = 1
}

function Test-DevEnv {
    param([switch]$Fix)

    # Auto-elevate for fix mode (Windows features, choco need admin)
    if ($Fix) {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            if (-not $script:DevEnvInteractiveConsole) {
                Write-Host "doctor fix requires an elevated interactive PowerShell session." -ForegroundColor Yellow
                return
            }
            Write-Host "Elevating to Administrator (UAC prompt)..." -ForegroundColor Yellow
            $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
            $entryScript = (Get-DevEnvEntryScript).Replace("'", "''")
            $argString = "-NoProfile -ExecutionPolicy RemoteSigned -Command ""& { . '$entryScript'; Test-DevEnv -Fix }"""
            Start-Process $psExe -Verb RunAs -ArgumentList $argString -Wait
            return
        }
    }

    $script:errors = 0

    # --- output helpers ---
    function _ok      { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host ([char]0x2714) -ForegroundColor Green -NoNewline; Write-Host " $Msg" }
    function _fail    { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host ([char]0x2718) -ForegroundColor Red -NoNewline; Write-Host " $Msg"; $script:errors++ }
    function _warn    { param([string]$Msg) Write-Host "  " -NoNewline; Write-Host ([char]0x26A0) -ForegroundColor Yellow -NoNewline; Write-Host " $Msg" }
    function _fixmsg  { param([string]$Msg) Write-Host "    " -NoNewline; Write-Host ([char]0x2192) -ForegroundColor Yellow -NoNewline; Write-Host " $Msg" }
    function _header  { param([string]$Msg) Write-Host ""; Write-Host $Msg -ForegroundColor Cyan }

    # --- check helpers ---

    function Check-Command {
        param([string]$Name, [string]$Cmd, [string]$FixCmd, [string]$VerCmd)
        if (Get-Command $Cmd -ErrorAction SilentlyContinue) {
            $ver = ""
            if ($VerCmd) { $ver = try { Invoke-Expression $VerCmd } catch { "" } }
            if ($ver) { _ok "$Name ($ver)" } else { _ok "$Name" }
        } else {
            _fail "$Name - missing"
            if ($Fix -and $FixCmd) {
                _fixmsg "fixing: $FixCmd"
                Invoke-Expression $FixCmd
            }
        }
    }

    function Check-Dir {
        param([string]$Name, [string]$Dir, [string]$FixCmd)
        if (Test-Path $Dir) {
            _ok "$Name"
        } else {
            _fail "$Name - $Dir not found"
            if ($Fix -and $FixCmd) {
                _fixmsg "fixing: $FixCmd"
                Invoke-Expression $FixCmd
            }
        }
    }

    function Check-EnvVar {
        param([string]$Name, [string]$Var)
        $val = [Environment]::GetEnvironmentVariable($Var)
        if (-not $val) { $val = (Get-Item "env:$Var" -ErrorAction SilentlyContinue).Value }
        if ($val) { _ok "$Name (`$$Var = $val)" } else { _fail "$Name - `$$Var not set" }
    }

    function Check-Version {
        param([string]$Name, [string]$Version, [int]$MinMajor, [string]$FixCmd)
        if (-not $Version) {
            _fail "$Name - not installed"
            if ($Fix -and $FixCmd) { _fixmsg "fixing: $FixCmd"; Invoke-Expression $FixCmd }
            return
        }
        $major = [int](($Version -replace '^v','') -replace '\..*','')
        if ($major -ge $MinMajor) {
            _ok "$Name ($Version)"
        } else {
            _fail "$Name ($Version) - want >= $MinMajor"
            if ($Fix -and $FixCmd) { _fixmsg "fixing: $FixCmd"; Invoke-Expression $FixCmd }
        }
    }

    function Check-GitConfig {
        param([string]$Key, [string]$Expected)
        $actual = git config --global $Key 2>$null
        if ($actual -eq $Expected) {
            _ok "$Key = $actual"
        } else {
            if ($actual) { _fail "$Key = $actual (want: $Expected)" } else { _fail "$Key - not set (want: $Expected)" }
            if ($Fix) {
                git config --global $Key $Expected
                _fixmsg "fixed: $Key = $Expected"
            }
        }
    }

    # --- checks ---

    _header "System tools"
    Check-Command "winget"          winget  ""
    Check-Command "Chocolatey"      choco   'Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))'
    Check-Command "Scoop"           scoop   'Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; $f = "$env:TEMP\scoop-install.ps1"; curl.exe -fsSL --ssl-no-revoke https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1 -o $f; if (Test-Path $f) { & $f -RunAsAdmin } else { Write-Host "       download failed - install manually in pwsh: irm get.scoop.sh | iex" -ForegroundColor Yellow }'
    Check-Command "curl"            curl    "choco install -y curl"
    Check-Command "git"             git     "choco install -y git"         'git --version'

    # Git for Windows Unix tools (grep, sed, awk, find, xargs, etc.)
    if (Test-Path "${env:ProgramFiles}\Git\usr\bin") {
                _ok "Git Unix tools (grep, sed, awk, find)"
    } else {
                _fail "Git Unix tools - Git usr/bin not found (install Git for Windows)"
    }
    Check-Command "jq"              jq      "choco install -y jq"
    # On Windows, "python3" is often a Microsoft Store stub. Check "python" first.
    $pyCmd = $null
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $pyOut = python --version 2>&1 | Out-String
        if ($pyOut -match 'Python (\d+\.\d+\.\d+)') { $pyCmd = "python"; $pyVer = $matches[1] }
    }
    if (-not $pyCmd -and (Get-Command python3 -ErrorAction SilentlyContinue)) {
        $pyOut = python3 --version 2>&1 | Out-String
        if ($pyOut -match 'Python (\d+\.\d+\.\d+)') { $pyCmd = "python3"; $pyVer = $matches[1] }
    }
    if ($pyCmd) {
                _ok "Python ($pyVer)"
    } else {
                _fail "Python - missing"
        if ($Fix) {
                    _fixmsg "fixing: choco install -y python3"
            choco install -y python3
        }
    }
    # pip ships with python3 - no separate install path
    Check-Command "pip"             pip     "choco install -y python3"

    Write-Host ""
    _header "Package managers"
    Check-Command "npm"    npm    ""              'npm --version'
    Check-Command "pnpm"   pnpm   "npm install -g pnpm"  'pnpm --version'
    Check-Command "cargo"  cargo  ""              'cargo --version 2>$null'
    Check-Command "rustup" rustup ""

    Write-Host ""
    _header "Runtimes"
    $nodeVer = try { (node -v) } catch { "" }
    Check-Version "Node" $nodeVer 24 "nvm install lts"

    # Prefer JAVA_HOME\bin\java.exe so the version check reflects the
    # intended JDK even when PATH still points at an older install.
    $javaVer = ""
    $javaExe = ""
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
        $javaExe = "$env:JAVA_HOME\bin\java.exe"
    } elseif (Get-Command java -ErrorAction SilentlyContinue) {
        $javaExe = (Get-Command java).Source
    }
    if ($javaExe) {
        $javaOut = (& $javaExe -version 2>&1) | Out-String
        if ($javaOut -match '"(\d+[\d.]*)') { $javaVer = $matches[1] }
    }
    Check-Version "Java" $javaVer 25 "Install-LibericaJdk -MinMajor 25"

    Write-Host ""
    _header "Containers"
    Check-Command "Docker"  docker  "choco install -y docker-desktop"  'docker --version'
    Check-Command "Podman"  podman  "choco install -y podman-cli"      'podman --version'
    Check-Command "kubectl" kubectl "choco install -y kubernetes-cli"   'kubectl version --client'

    Write-Host ""
    _header "Cloud & infra"
    Check-Command "Terraform"  terraform "choco install -y terraform"   'terraform version | Select-Object -First 1'
    Check-Command "gcloud"     gcloud    "choco install -y gcloudsdk"   'gcloud version 2>$null | Select-Object -First 1'
    Check-Command "GitHub CLI" gh        "choco install -y gh"          'gh --version | Select-Object -First 1'

    Write-Host ""
    _header "CLI tools"
    Check-Command "fzf"         fzf       "choco install -y fzf"          'fzf --version'
    Check-Command "eza"         eza       "choco install -y eza"          'eza --version | Select-String "^v" | Select-Object -First 1'
    Check-Command "dust"        dust      "choco install -y dust"         'dust --version'
    Check-Command "httpie"      http      "pip install httpie"            'http --version'
    Check-Command "lazygit"     lazygit   "choco install -y lazygit"      'lazygit --version | Select-Object -First 1'
    Check-Command "starship"    starship  "choco install -y starship"     'starship --version | Select-Object -First 1'
    Check-Command "Claude Code" claude    "npm install -g @anthropic-ai/claude-code"  'claude --version'

    Write-Host ""
    _header "Android SDK"
    Check-EnvVar "ANDROID_HOME" "ANDROID_HOME"
    Check-Dir    "cmdline-tools"  "$env:ANDROID_SDK_ROOT\cmdline-tools\latest"
    Check-Dir    "platform-tools" "$env:ANDROID_SDK_ROOT\platform-tools"
    Check-Command "sdkmanager" sdkmanager ""

    Write-Host ""
    _header "PATH"

    # Duplicates
    $pathEntries = $env:PATH -split ';' | Where-Object { $_ -ne '' }
    $uniqueEntries = $pathEntries | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique
    $dupCount = $pathEntries.Count - $uniqueEntries.Count
    $staleEntries = $pathEntries | Where-Object { -not (Test-Path $_) }
    $needsClean = $false
    if ($dupCount -gt 0) {
                _fail "$dupCount duplicate PATH entries"
        $needsClean = $true
    } else {
                _ok "No duplicate PATH entries ($($pathEntries.Count) total)"
    }

    if ($staleEntries.Count -gt 0) {
                _fail "$($staleEntries.Count) stale PATH entries"
        foreach ($s in $staleEntries) { Write-Host "       $s" -ForegroundColor DarkGray }
        $needsClean = $true
    } else {
                _ok "All PATH entries exist"
    }

    if ($Fix -and $needsClean) {
        Clean-Path
                _fixmsg "fixed: duplicates and stale entries removed"
    }

    # Java PATH vs JAVA_HOME consistency
    if ($env:JAVA_HOME -and (Get-Command java -ErrorAction SilentlyContinue)) {
        $javaPath = (Get-Command java).Source
        $javaHomeNorm = $env:JAVA_HOME.TrimEnd('\')
        if ($javaPath -like "${javaHomeNorm}\*") {
                    _ok "java in PATH matches JAVA_HOME"
        } else {
                    _fail "java in PATH ($javaPath) does not match JAVA_HOME ($env:JAVA_HOME)"
            if ($Fix) {
                $javaHomeBin = "$javaHomeNorm\bin"
                if (Test-Path $javaHomeBin) {
                    Add-PathEntry $javaHomeBin -Position Prepend
                            _fixmsg "prepended $javaHomeBin to PATH for this session"
                            _fixmsg "persist: setx PATH `"$javaHomeBin;`$env:PATH`" (or edit via System Properties)"
                }
            }
        }
    }

    # Python Store stub check
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $pythonPath = (Get-Command python).Source
        if ($pythonPath -like "*\WindowsApps\*") {
                    _fail "python resolves to Windows Store stub ($pythonPath)"
            Write-Host "       Disable: Settings > Apps > Advanced app settings > App execution aliases" -ForegroundColor DarkGray
        } else {
                    _ok "python is not a Store stub"
        }
    }

    Write-Host ""
    _header "WSL"
    $wslList = wsl --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ }
    if ($wslList) {
        $distros = $wslList -join ", "
                _ok "WSL installed ($distros)"
    } else {
                _fail "WSL - no distributions installed"
        if ($Fix) {
                    _fixmsg "fixing: wsl --install"
            wsl --install --distribution Ubuntu --no-launch
        }
    }

    Write-Host ""
    _header "Windows features"
    foreach ($feat in @("TelnetClient", "Microsoft-Hyper-V-All", "VirtualMachinePlatform", "Microsoft-Windows-Subsystem-Linux")) {
        $info = try { Get-WindowsOptionalFeature -Online -FeatureName $feat -ErrorAction SilentlyContinue } catch { $null }
        if (-not $info) {
                    _warn "$feat - not available on this Windows SKU"
            continue
        }
        if ($info.State -eq "Enabled") {
                    _ok "$feat"
        } else {
                    _fail "$feat - not enabled"
            if ($Fix) {
                        _fixmsg "fixing: Enable-WindowsOptionalFeature $feat"
                try {
                    Enable-WindowsOptionalFeature -Online -FeatureName $feat -NoRestart -ErrorAction Stop | Out-Null
                } catch {
                            _fixmsg "could not enable: $($_.Exception.Message)"
                }
            }
        }
    }
    Check-Command "ssh"    ssh    ""
    Check-Command "telnet" telnet ""

    Write-Host ""
    _header "Security"

    # Windows Defender
    $defender = try { Get-MpComputerStatus -ErrorAction SilentlyContinue } catch { $null }
    if ($defender) {
        if ($defender.RealTimeProtectionEnabled) {
                    _ok "Windows Defender real-time protection"
        } else {
                    _fail "Windows Defender real-time protection - disabled"
        }
        # 65535 is the sentinel Defender returns when it's disabled/inactive.
        if ($defender.AntivirusSignatureAge -ge 65535 -or -not $defender.RealTimeProtectionEnabled) {
                    _warn "Defender signatures - not reported (Defender disabled or inactive)"
        } elseif ($defender.AntivirusSignatureAge -le 7) {
                    _ok "Defender signatures ($($defender.AntivirusSignatureAge) days old)"
        } else {
                    _fail "Defender signatures - $($defender.AntivirusSignatureAge) days old (update recommended)"
        }
    }

    # Firewall
    $fwProfiles = try { Get-NetFirewallProfile -ErrorAction SilentlyContinue } catch { $null }
    if ($fwProfiles) {
        $allEnabled = ($fwProfiles | Where-Object { -not $_.Enabled }).Count -eq 0
        if ($allEnabled) {
                    _ok "Firewall enabled (all profiles)"
        } else {
            $disabled = ($fwProfiles | Where-Object { -not $_.Enabled }).Name -join ", "
                    _fail "Firewall disabled on: $disabled"
        }
    }

    # Secure Boot
    $secureBoot = try { Confirm-SecureBootUEFI -ErrorAction SilentlyContinue } catch { $null }
    if ($secureBoot -eq $true) {
                _ok "Secure Boot enabled"
    } elseif ($secureBoot -eq $false) {
                _fail "Secure Boot - disabled"
    }

    # BitLocker
    $bl = try { Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue } catch { $null }
    if ($bl) {
        if ($bl.ProtectionStatus -eq "On") {
                    _ok "BitLocker enabled on C:"
        } else {
                    _fail "BitLocker - not enabled on C:"
        }
    }

    # SSH key
    $sshKey = "$env:USERPROFILE\.ssh\id_ed25519"
    if (Test-Path $sshKey) {
                _ok "SSH key (Ed25519)"
    } elseif (Test-Path "$env:USERPROFILE\.ssh\id_rsa") {
                _ok "SSH key (RSA - consider upgrading to Ed25519)"
    } else {
                _fail "SSH key - none found"
        if ($Fix) {
                    _fixmsg "fixing: ssh-keygen -t ed25519"
            ssh-keygen -t ed25519 -C "$env:USERNAME@$env:COMPUTERNAME"
        }
    }

    # Git credential helper
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $credHelper = git config --global credential.helper 2>$null
        if ($credHelper -eq "store") {
                    _fail "git credential.helper = store (plaintext passwords!)"
            if ($Fix) {
                git config --global credential.helper manager
                        _fixmsg "fixed: credential.helper = manager"
            }
        } elseif ($credHelper) {
                    _ok "git credential.helper = $credHelper"
        } else {
                    _fail "git credential.helper - not set"
            if ($Fix) {
                git config --global credential.helper manager
                        _fixmsg "fixed: credential.helper = manager"
            }
        }
    }

    Write-Host ""
    _header "Configuration"

    # Windows version
    $winVer = [System.Environment]::OSVersion.Version
            _ok "Windows $($winVer.Major).$($winVer.Minor) (Build $($winVer.Build))"

    # Git settings
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitName  = git config --global user.name  2>$null
        $gitEmail = git config --global user.email 2>$null
        if ($gitName -and $gitEmail) {
                    _ok "git identity ($gitName <$gitEmail>)"
        } else {
                    _fail "git identity - user.name or user.email not set"
            if ($Fix) { Write-Host "       run: git config --global user.name 'Your Name'; git config --global user.email 'you@email.com'" -ForegroundColor Yellow }
        }

        # Pull strategy
        Check-GitConfig "pull.rebase"          "false"

        # Line endings - match Linux/macOS: commit LF, checkout LF
        Check-GitConfig "core.autocrlf"        "input"
        Check-GitConfig "core.eol"             "lf"

        # Modern defaults
        Check-GitConfig "init.defaultBranch"   "main"
        Check-GitConfig "push.autoSetupRemote" "true"
        Check-GitConfig "push.default"         "current"
        Check-GitConfig "fetch.prune"          "true"

        # Better diffs and merge conflicts
        Check-GitConfig "diff.colorMoved"      "default"
        Check-GitConfig "merge.conflictstyle"  "zdiff3"

        # Editor
        $gitEditor = git config --global core.editor 2>$null
        if ($gitEditor) {
                    _ok "core.editor = $gitEditor"
        } else {
                    _fail "core.editor - not set"
            if ($Fix) {
                git config --global core.editor "code --wait"
                        _fixmsg "fixed: core.editor = code --wait"
            }
        }
    }

    # GitHub CLI auth
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghAuth = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
                    _ok "gh authenticated"
        } else {
                    _fail "gh - not authenticated"
            if ($Fix) { Write-Host "       run: gh auth login" -ForegroundColor Yellow }
        }
    }

    # Docker daemon
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $dockerInfo = docker info 2>$null
        if ($LASTEXITCODE -eq 0) {
                    _ok "Docker daemon reachable"
        } else {
                    _fail "Docker daemon - not running"
        }
    }

    # gcloud auth
    if (Get-Command gcloud -ErrorAction SilentlyContinue) {
        $gcloudAcct = gcloud auth list 2>$null | Select-String '^\*' | ForEach-Object { ($_ -split '\s+')[1] }
        if ($gcloudAcct) {
                    _ok "gcloud auth ($gcloudAcct)"
        } else {
                    _fail "gcloud - no active account"
            if ($Fix) { Write-Host "       run: gcloud auth login" -ForegroundColor Yellow }
        }
    }

    # JAVA_HOME
    if (Get-Command java -ErrorAction SilentlyContinue) {
        if ($env:JAVA_HOME -and (Test-Path $env:JAVA_HOME)) {
                    _ok "JAVA_HOME set"
        } else {
                    _fail "JAVA_HOME - not set or invalid"
        }
    }

    # --- summary ---

    Write-Host ""
    if ($script:errors -eq 0) {
        Write-Host ([char]0x2714) -ForegroundColor Green -NoNewline; Write-Host " All checks passed!" -ForegroundColor Green
    } else {
        Write-Host ([char]0x2718) -ForegroundColor Red -NoNewline; Write-Host " $($script:errors) issue(s) found." -ForegroundColor Red
        if (-not $Fix) { Write-Host "  Run " -NoNewline; Write-Host "doctor fix" -ForegroundColor White -NoNewline; Write-Host " to auto-fix what's possible." }
    }
}
