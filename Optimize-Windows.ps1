<#
.SYNOPSIS
    Opinionated Windows 11 optimization script for performance, privacy, and security.

.DESCRIPTION
    Applies curated settings in one shot. Creates a system restore point first.
    Default: applies ALL categories non-interactively with the Strict profile.
    Use --interactive (or -Interactive) to pick categories and toggle individual tweaks.

.PARAMETER HardeningProfile
    Hardening profile to apply:
      Strict   - Maximum hardening. Blocks NTLM, denies camera/mic by default,
                 removes bloatware, disables WSH, restricts WSL interop. Best for
                 security-focused workstations. (Default)
      Moderate - Sensible defaults that follow Microsoft/CIS recommended practices
                 without breaking common workflows. Keeps camera/mic accessible,
                 uses audit mode for ASR/controlled folders, preserves background
                 apps and visual effects. Good starting point for most users.

.PARAMETER Interactive
    Launch interactive mode where you choose which categories/tweaks to apply.

.PARAMETER Clean
    Run disk cleanup: purge temp files, Windows Update cache, thumbnail cache,
    Recycle Bin, error reports, delivery optimization cache, and font cache.
    Can be combined with other flags or used standalone.

.PARAMETER DryRun
    Show what would be changed without applying anything.

.PARAMETER SkipRestorePoint
    Skip creating a system restore point before making changes.

.EXAMPLE
    .\Optimize-Windows.ps1
    .\Optimize-Windows.ps1 -HardeningProfile Moderate
    .\Optimize-Windows.ps1 -HardeningProfile Strict -Interactive
    .\Optimize-Windows.ps1 -DryRun
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Strict", "Moderate")]
    [string]$HardeningProfile = "Strict",
    [switch]$Interactive,
    [switch]$Clean,
    [switch]$DryRun,
    [switch]$SkipRestorePoint
)

# PSScriptAnalyzer suppressions for intentional Write-Host usage (CLI tool with colored output)
# [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'SilentlyContinue'
$script:LogFile = Join-Path $env:USERPROFILE "Optimize-Windows_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:ChangeCount = 0
$script:SkipRestore = $SkipRestorePoint.IsPresent
$script:IsStrict = ($HardeningProfile -eq "Strict")

function Write-Log {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $line
    switch ($Level) {
        "INFO"    { Write-Host "  [+] $Message" -ForegroundColor Green }
        "WARN"    { Write-Host "  [!] $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "  [x] $Message" -ForegroundColor Red }
        "SKIP"    { Write-Host "  [-] $Message" -ForegroundColor DarkGray }
        "SECTION" { Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
        default   { Write-Host "  $Message" }
    }
}

function Initialize-RegPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = "DWord",
        [string]$Description = ""
    )
    if ($DryRun) {
        Write-Log -Message "[DRY RUN] Would set $Path\$Name = $Value" -Level "SKIP"
        return
    }
    if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set registry value to $Value")) {
        try {
            Initialize-RegPath -Path $Path
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
            $script:ChangeCount++
            if ($Description) { Write-Log -Message $Description }
        } catch {
            Write-Log -Message "Failed: $Path\$Name - $_" -Level "ERROR"
        }
    }
}

function Disable-ServiceByName {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Description = ""
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    if ($DryRun) {
        Write-Log -Message "[DRY RUN] Would disable service: $Name" -Level "SKIP"
        return
    }
    if ($PSCmdlet.ShouldProcess($Name, "Disable service")) {
        try {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
            $script:ChangeCount++
            $label = if ($Description) { "$Description ($Name)" } else { $Name }
            Write-Log -Message "Disabled service: $label"
        } catch {
            Write-Log -Message "Failed to disable service $Name - $_" -Level "ERROR"
        }
    }
}

function Remove-BloatwareApp {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)
    if ($DryRun) {
        Write-Log -Message "[DRY RUN] Would remove: $Name" -Level "SKIP"
        return
    }
    $pkg = Get-AppxPackage -Name $Name -AllUsers -ErrorAction SilentlyContinue
    if ($pkg) {
        if ($PSCmdlet.ShouldProcess($Name, "Remove AppX package")) {
            $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like $Name } |
                Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            $script:ChangeCount++
            Write-Log -Message "Removed: $Name"
        }
    }
}

# ---------------------------------------------------------------------------
# CATEGORY: PERFORMANCE
# ---------------------------------------------------------------------------
function Invoke-PerformanceOptimization {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    Write-Log -Message "PERFORMANCE OPTIMIZATIONS ($HardeningProfile profile)" -Level "SECTION"

    # --- Visual Effects (Strict: all off, Moderate: keep visuals, just reduce delays) ---
    if ($script:IsStrict) {
        Write-Log -Message "Disabling visual effects & animations..."
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -Type "DWord" -Description "Set visual effects to best performance"
        Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Type "String" -Description "Remove menu show delay"
        Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type "Binary" -Description "Disable UI animations"
        Set-RegistryValue -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -Type "String" -Description "Disable minimize/maximize animation"
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 0 -Type "DWord" -Description "Disable taskbar animations"
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewAlphaSelect" -Value 0 -Type "DWord" -Description "Disable translucent selection rectangle"
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewShadow" -Value 0 -Type "DWord" -Description "Disable icon shadow"
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Value 0 -Type "DWord" -Description "Disable Aero Peek"
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0 -Type "DWord" -Description "Disable Snap Assist flyout"
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -Type "DWord" -Description "Disable transparency effects"
    } else {
        Write-Log -Message "Keeping visual effects (Moderate profile) - reducing menu delay only..."
        Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "50" -Type "String" -Description "Reduce menu show delay to 50ms"
    }

    # --- Power Plan (Strict: Ultimate Performance, Moderate: High Performance) ---
    if (-not $DryRun) {
        if ($script:IsStrict) {
            Write-Log -Message "Setting Ultimate Performance power plan..."
            $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
            powercfg -duplicatescheme $ultimateGuid 2>$null
            powercfg /setactive $ultimateGuid 2>$null
            if ($LASTEXITCODE -ne 0) {
                powercfg /setactive "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
                Write-Log -Message "Activated High Performance plan (Ultimate not available)" -Level "WARN"
            } else {
                Write-Log -Message "Activated Ultimate Performance plan"
            }
            powercfg /hibernate off
            Write-Log -Message "Disabled hibernation"
        } else {
            Write-Log -Message "Setting High Performance power plan..."
            powercfg /setactive "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
            Write-Log -Message "Activated High Performance plan"
        }
    }

    # --- Disable SysMain / Superfetch (Strict only - SSD optimization) ---
    if ($script:IsStrict) {
        Write-Log -Message "Disabling SysMain & Prefetch (SSD optimized)..."
        Disable-ServiceByName -Name "SysMain" -Description "SysMain (Superfetch)"
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnablePrefetcher" -Value 0 -Type "DWord" -Description "Disable Prefetcher"
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnableSuperfetch" -Value 0 -Type "DWord" -Description "Disable Superfetch"
    } else {
        Write-Log -Message "Keeping SysMain enabled (Moderate profile)"
    }

    # --- Background Apps (Strict: disable all, Moderate: leave user-controlled) ---
    if ($script:IsStrict) {
        Write-Log -Message "Disabling background apps..."
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1 -Type "DWord" -Description "Disable background apps globally"
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BackgroundAppGlobalToggle" -Value 0 -Type "DWord" -Description "Disable background search"
        Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -Value 2 -Type "DWord" -Description "Policy: deny background apps"
    } else {
        Write-Log -Message "Keeping background apps user-controlled (Moderate profile)"
    }

    # --- Search Indexing ---
    Write-Log -Message "Limiting search indexing & disabling web search..."
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type "DWord" -Description "Disable Bing search integration"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0 -Type "DWord" -Description "Disable Cortana consent"
    Initialize-RegPath -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1 -Type "DWord" -Description "Disable search box suggestions"
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1 -Type "DWord" -Description "Disable web search"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "ConnectedSearchUseWeb" -Value 0 -Type "DWord" -Description "Disable connected search"

    # --- Disable tips, ads, suggestions ---
    Write-Log -Message "Disabling tips, ads, and suggestions..."
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @{
        "SubscribedContent-338389Enabled" = 0
        "SubscribedContent-310093Enabled" = 0
        "SubscribedContent-338388Enabled" = 0
        "SubscribedContent-338393Enabled" = 0
        "SubscribedContent-353694Enabled" = 0
        "SubscribedContent-353696Enabled" = 0
        "SubscribedContent-338396Enabled" = 0
        "SubscribedContent-353698Enabled" = 0
        "SoftLandingEnabled"              = 0
        "SystemPaneSuggestionsEnabled"    = 0
        "SilentInstalledAppsEnabled"      = 0
        "OemPreInstalledAppsEnabled"      = 0
        "PreInstalledAppsEnabled"         = 0
        "PreInstalledAppsEverEnabled"     = 0
        "ContentDeliveryAllowed"          = 0
        "FeatureManagementEnabled"        = 0
        "RotatingLockScreenEnabled"       = 0
        "RotatingLockScreenOverlayEnabled" = 0
    }
    foreach ($kv in $cdmKeys.GetEnumerator()) {
        Set-RegistryValue -Path $cdm -Name $kv.Key -Value $kv.Value -Type "DWord"
    }
    Write-Log -Message "Disabled all ContentDeliveryManager suggestions"

    # Hide Start Menu recommendations
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedSection" -Value 1 -Type "DWord" -Description "Hide Start Menu recommendations"

    # --- Game Bar (disable overlay, keep Game Mode) ---
    Write-Log -Message "Disabling Game Bar overlay (Game Mode stays on)..."
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 1 -Type "DWord" -Description "Enable Game Mode"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 -Type "DWord" -Description "Enable Auto Game Mode"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type "DWord" -Description "Disable Game DVR capture"
    Set-RegistryValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type "DWord" -Description "Disable GameDVR"
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type "DWord" -Description "Policy: disable Game DVR"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "ShowStartupPanel" -Value 0 -Type "DWord" -Description "Disable Game Bar tips"

    # --- Hardware-Accelerated GPU Scheduling ---
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type "DWord" -Description "Enable HW-accelerated GPU scheduling"

    # --- Disable unnecessary services ---
    Write-Log -Message "Disabling unnecessary services..."
    # Services safe to disable in both profiles
    $services = @{
        "RetailDemo"      = "Retail Demo Service"
        "Fax"             = "Fax"
        "wisvc"           = "Windows Insider Service"
        "WpcMonSvc"       = "Parental Controls"
    }
    # Additional services disabled only in Strict
    if ($script:IsStrict) {
        $services["MapsBroker"]     = "Downloaded Maps Manager"
        $services["WMPNetworkSvc"]  = "Windows Media Player Network Sharing"
        $services["XblAuthManager"] = "Xbox Live Auth Manager"
        $services["XblGameSave"]    = "Xbox Live Game Save"
        $services["XboxNetApiSvc"]  = "Xbox Live Networking"
        $services["XboxGipSvc"]     = "Xbox Accessory Management"
        $services["PhoneSvc"]       = "Phone Service"
        $services["SCardSvr"]       = "Smart Card"
        $services["ScDeviceEnum"]   = "Smart Card Device Enumeration"
        $services["SCPolicySvc"]    = "Smart Card Removal Policy"
    }
    foreach ($kv in $services.GetEnumerator()) {
        Disable-ServiceByName -Name $kv.Key -Description $kv.Value
    }

    # --- Remove Bloatware ---
    # Moderate: only third-party junk and obvious adware
    # Strict:   all bloatware including Microsoft first-party apps
    Write-Log -Message "Removing bloatware..."
    $bloat = @(
        # Third-party junk (both profiles)
        "SpotifyAB.SpotifyMusic"
        "Disney.37853FC22B2CE"
        "BytedancePte.Ltd.TikTok"
        "king.com.CandyCrushSaga"
        "king.com.CandyCrushSodaSaga"
        "Facebook.Facebook"
        "AmazonVideo.PrimeVideo"
        "5A894077.McAfeeSecurity"
        "4DF9E0F8.Netflix"
        "Clipchamp.Clipchamp"
        "MicrosoftCorporationII.MicrosoftFamily"
        "Microsoft.549981C3F5F10"
    )
    if ($script:IsStrict) {
        # Microsoft first-party bloat (Strict only)
        $bloat += @(
        "Microsoft.3DBuilder"
        "Microsoft.BingFinance"
        "Microsoft.BingNews"
        "Microsoft.BingSports"
        "Microsoft.BingWeather"
        "Microsoft.BingTranslator"
        "Microsoft.GamingApp"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.Messaging"
        "Microsoft.Microsoft3DViewer"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.MixedReality.Portal"
        "Microsoft.Office.OneNote"
        "Microsoft.OneConnect"
        "Microsoft.People"
        "Microsoft.PowerAutomateDesktop"
        "Microsoft.SkypeApp"
        "Microsoft.Todos"
        "Microsoft.WindowsAlarms"
        "microsoft.windowscommunicationsapps"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.WindowsSoundRecorder"
        "Microsoft.Xbox.TCUI"
        "Microsoft.XboxApp"
        "Microsoft.XboxGameOverlay"
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxIdentityProvider"
        "Microsoft.XboxSpeechToTextOverlay"
        "Microsoft.YourPhone"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
        "MicrosoftCorporationII.QuickAssist"
        "MicrosoftTeams"
        "MSTeams"
        "Microsoft.OutlookForWindows"
        "Microsoft.WindowsCopilot"
        )
    }
    foreach ($app in $bloat) {
        Remove-BloatwareApp -Name $app
    }
}

# ---------------------------------------------------------------------------
# CATEGORY: PRIVACY
# ---------------------------------------------------------------------------
function Invoke-PrivacyHardening {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    Write-Log -Message "PRIVACY HARDENING ($HardeningProfile profile)" -Level "SECTION"

    # --- Telemetry (Strict: disable services + level 0, Moderate: limit to required + level 1) ---
    Write-Log -Message "Disabling telemetry & diagnostics..."
    if ($script:IsStrict) {
        Disable-ServiceByName -Name "DiagTrack" -Description "Connected User Experiences and Telemetry"
        Disable-ServiceByName -Name "dmwappushservice" -Description "WAP Push Message Routing"
    }
    # Telemetry level: 0 = Security (Enterprise only), 1 = Required/Basic
    $telemetryLevel = if ($script:IsStrict) { 0 } else { 1 }
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value $telemetryLevel -Type "DWord" -Description "Set telemetry to level $telemetryLevel"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "LimitDiagnosticLogCollection" -Value 1 -Type "DWord" -Description "Limit diagnostic log collection"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "LimitDumpCollection" -Value 1 -Type "DWord" -Description "Limit dump collection"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type "DWord" -Description "Disable telemetry (user policy)"

    # --- Advertising ID ---
    Write-Log -Message "Disabling advertising ID..."
    Initialize-RegPath -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type "DWord" -Description "Disable advertising ID"
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Value 1 -Type "DWord" -Description "Policy: disable advertising ID"

    # --- Activity History ---
    Write-Log -Message "Disabling activity history..."
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0 -Type "DWord" -Description "Disable activity feed"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0 -Type "DWord" -Description "Disable publish user activities"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -Value 0 -Type "DWord" -Description "Disable upload user activities"

    # --- Location (Strict: deny + disable service, Moderate: just disable service) ---
    Write-Log -Message "Disabling location tracking..."
    Disable-ServiceByName -Name "lfsvc" -Description "Geolocation Service"
    if ($script:IsStrict) {
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Value "Deny" -Type "String" -Description "Deny location access"
    }

    # --- Speech & Inking ---
    Write-Log -Message "Disabling speech recognition & inking personalization..."
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1 -Type "DWord" -Description "Restrict ink collection"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1 -Type "DWord" -Description "Restrict text collection"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Value 0 -Type "DWord" -Description "Disable contact harvesting"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Value 0 -Type "DWord" -Description "Disable personalization privacy policy"
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization" -Name "AllowInputPersonalization" -Value 0 -Type "DWord" -Description "Policy: disable input personalization"

    # --- Feedback ---
    Write-Log -Message "Disabling feedback & tailored experiences..."
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Value 0 -Type "DWord" -Description "Disable feedback frequency"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "PeriodInNanoSeconds" -Value 0 -Type "DWord" -Description "Disable feedback period"

    # --- Tailored Experiences ---
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -Type "DWord" -Description "Disable tailored experiences"
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Type "DWord" -Description "Policy: disable tailored experiences"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type "DWord" -Description "Disable consumer features"

    # --- Copilot & Recall ---
    Write-Log -Message "Disabling Copilot & Recall..."
    Initialize-RegPath -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
    Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type "DWord" -Description "Disable Copilot (user)"
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type "DWord" -Description "Disable Copilot (machine)"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -Type "DWord" -Description "Remove Copilot from taskbar"

    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1 -Type "DWord" -Description "Disable Recall AI analysis"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "TurnOffSavingSnapshots" -Value 1 -Type "DWord" -Description "Disable Recall snapshots"

    Remove-BloatwareApp -Name "Microsoft.Copilot"
    Remove-BloatwareApp -Name "Microsoft.Windows.Ai.Copilot.Provider"

    # --- App Launch Tracking ---
    Write-Log -Message "Disabling app launch tracking..."
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0 -Type "DWord" -Description "Disable app launch tracking"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackDocs" -Value 0 -Type "DWord" -Description "Disable document tracking"

    # --- Camera & Microphone defaults ---
    if ($script:IsStrict) {
        # Strict: deny by default, user grants per-app manually
        Write-Log -Message "Setting camera & microphone to deny-by-default..."
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam" -Name "Value" -Value "Deny" -Type "String" -Description "Deny camera by default"
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone" -Name "Value" -Value "Deny" -Type "String" -Description "Deny microphone by default"

        # Deny additional capability categories
        $denyCapabilities = @(
            "activity", "appDiagnostics", "appointments", "bluetoothSync",
            "chat", "contacts", "email", "gazeInput",
            "phoneCall", "phoneCallHistory", "radios",
            "userAccountInformation", "userDataTasks", "userNotificationListener"
        )
        foreach ($cap in $denyCapabilities) {
            $capPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$cap"
            if (Test-Path $capPath) {
                Set-RegistryValue -Path $capPath -Name "Value" -Value "Deny" -Type "String"
            }
        }
        Write-Log -Message "Denied access to $($denyCapabilities.Count) capability categories"
    } else {
        # Moderate: leave camera/mic accessible (apps can request)
        Write-Log -Message "Camera & microphone left user-controlled (Moderate profile)"
    }

    # --- Error Reporting (Strict only) ---
    if ($script:IsStrict) {
        Disable-ServiceByName -Name "WerSvc" -Description "Windows Error Reporting"
    }
}

# ---------------------------------------------------------------------------
# CATEGORY: SECURITY
# ---------------------------------------------------------------------------
function Invoke-SecurityHardening {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    Write-Log -Message "SECURITY HARDENING ($HardeningProfile profile)" -Level "SECTION"

    # --- Windows Defender ---
    Write-Log -Message "Hardening Windows Defender..."
    if (-not $DryRun) {
        # Check if Defender service is available and running
        $defenderSvc = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
        $defenderAvailable = $false

        if (-not $defenderSvc) {
            Write-Log -Message "Windows Defender service not found - a third-party antivirus may be installed. Skipping Defender configuration." -Level "WARN"
        } elseif ($defenderSvc.Status -ne 'Running') {
            Write-Log -Message "Windows Defender service is stopped. Attempting to start..."
            try {
                Start-Service -Name "WinDefend" -ErrorAction Stop
                Start-Sleep -Seconds 2
                $defenderAvailable = $true
                Write-Log -Message "Defender service started successfully"
            } catch {
                Write-Log -Message "Could not start Defender service (a third-party antivirus may have disabled it). Skipping Defender configuration." -Level "WARN"
                Write-Log -Message "To use Defender: uninstall third-party AV, then reboot and re-run this script." -Level "WARN"
            }
        } else {
            $defenderAvailable = $true
        }

        if ($defenderAvailable) {
            try {
                Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
                Set-MpPreference -MAPSReporting 2
                Set-MpPreference -SubmitSamplesConsent 1
                Set-MpPreference -DisableBlockAtFirstSeen $false
                Set-MpPreference -PUAProtection 1
                Set-MpPreference -EnableNetworkProtection 1
                # Strict: block mode, Moderate: audit mode (logs but doesn't block)
                if ($script:IsStrict) {
                    Set-MpPreference -EnableControlledFolderAccess 1
                } else {
                    Set-MpPreference -EnableControlledFolderAccess 2
                }
                $cfaMode = if ($script:IsStrict) { "enabled (block)" } else { "audit mode" }
                Write-Log -Message "Defender: real-time, cloud, PUA, network protection on; controlled folder access $cfaMode"
            } catch {
                Write-Log -Message "Some Defender settings may require manual configuration: $_" -Level "WARN"
            }

            # Attack Surface Reduction rules (Strict=1/Block, Moderate=2/Audit)
            $asrAction = if ($script:IsStrict) { 1 } else { 2 }
            $asrMode = if ($script:IsStrict) { "Block" } else { "Audit" }
            $asrRules = @{
                "56a863a9-875e-4185-98a7-b882c64b5ce5" = $asrAction  # Exploited vulnerable drivers
                "7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c" = $asrAction  # Adobe Reader child processes
                "d4f940ab-401b-4efc-aadc-ad5f3c50688a" = $asrAction  # Office child processes
                "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2" = $asrAction  # Credential stealing from LSASS
                "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550" = $asrAction  # Executable content from email
                "5beb7efe-fd9a-4556-801d-275e5ffc04cc" = $asrAction  # Obfuscated scripts
                "d3e037e1-3eb8-44c8-a917-57927947596d" = $asrAction  # JS/VBS launching downloads
                "3b576869-a4ec-4529-8536-b80a7769e899" = $asrAction  # Office creating executables
                "75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84" = $asrAction  # Office code injection
                "e6db77e5-3df2-4cf1-b95a-636979351e5b" = $asrAction  # WMI persistence
                "d1e49aac-8f56-4280-b9ba-993a6d77406c" = $asrAction  # PSExec/WMI process creation
                "b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4" = $asrAction  # Untrusted USB processes
                "92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b" = $asrAction  # Win32 API from Office macros
                "c1db55ab-c21a-4637-bb3f-a12568109d35" = $asrAction  # Advanced ransomware protection
                "01443614-cd74-433a-b99e-2ecdc07bfc25" = $asrAction  # Low-prevalence executables
            }
            $asrFailed = 0
            foreach ($rule in $asrRules.GetEnumerator()) {
                try {
                    Add-MpPreference -AttackSurfaceReductionRules_Ids $rule.Key -AttackSurfaceReductionRules_Actions $rule.Value -ErrorAction Stop
                } catch {
                    $asrFailed++
                }
            }
            if ($asrFailed -eq 0) {
                Write-Log -Message "Set all $($asrRules.Count) ASR rules to $asrMode mode"
            } elseif ($asrFailed -eq $asrRules.Count) {
                Write-Log -Message "Could not set ASR rules - Defender may not fully support them on this edition (requires Pro/Enterprise)" -Level "WARN"
            } else {
                Write-Log -Message "Set $($asrRules.Count - $asrFailed)/$($asrRules.Count) ASR rules to $asrMode ($asrFailed failed)" -Level "WARN"
            }

            # Update signatures
            try {
                Update-MpSignature -ErrorAction Stop
                Write-Log -Message "Updated Defender signatures"
            } catch {
                Write-Log -Message "Could not update Defender signatures: $_" -Level "WARN"
            }
        }
    }

    # --- Firewall ---
    Write-Log -Message "Enabling firewall on all profiles..."
    if (-not $DryRun) {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue
        Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block -DefaultOutboundAction Allow -ErrorAction SilentlyContinue
        Set-NetFirewallProfile -Profile Domain,Public,Private -LogBlocked True -LogMaxSizeKilobytes 4096 -ErrorAction SilentlyContinue
        Write-Log -Message "Firewall: enabled, inbound blocked, logging on"
    }

    # --- Disable Remote Desktop ---
    Write-Log -Message "Disabling Remote Desktop..."
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1 -Type "DWord" -Description "Deny RDP connections"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -Type "DWord" -Description "Require NLA for RDP"
    if (-not $DryRun) {
        Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    }

    # --- Disable SMBv1 ---
    Write-Log -Message "Disabling SMBv1..."
    if (-not $DryRun) {
        Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
    }
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "SMB1" -Value 0 -Type "DWord" -Description "Disable SMBv1 server"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10" -Name "Start" -Value 4 -Type "DWord" -Description "Disable SMBv1 client driver"

    # --- Credential Guard & VBS ---
    Write-Log -Message "Enabling Virtualization Based Security & Credential Guard..."
    Initialize-RegPath -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value 1 -Type "DWord" -Description "Enable VBS"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "RequirePlatformSecurityFeatures" -Value 3 -Type "DWord" -Description "Require Secure Boot + DMA"
    Initialize-RegPath -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -Value 1 -Type "DWord" -Description "Enable HVCI / Memory Integrity"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LsaCfgFlags" -Value 1 -Type "DWord" -Description "Enable Credential Guard with UEFI lock"

    # --- Disable NetBIOS over TCP/IP ---
    Write-Log -Message "Disabling NetBIOS over TCP/IP..."
    if (-not $DryRun) {
        $netbtPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"
        if (Test-Path $netbtPath) {
            Get-ChildItem $netbtPath | ForEach-Object {
                Set-ItemProperty -Path $_.PSPath -Name "NetbiosOptions" -Value 2 -Type DWord -ErrorAction SilentlyContinue
            }
        }
        Write-Log -Message "Disabled NetBIOS on all interfaces"
    }

    # --- Disable LLMNR ---
    Write-Log -Message "Disabling LLMNR..."
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -Value 0 -Type "DWord" -Description "Disable LLMNR"

    # --- DNS over HTTPS ---
    Write-Log -Message "Enabling DNS over HTTPS..."
    # Strict: force DoH (may break if DNS server doesn't support it), Moderate: auto (use DoH if available)
    $dohValue = if ($script:IsStrict) { 2 } else { 1 }
    $dohMode = if ($script:IsStrict) { "forced" } else { "automatic" }
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDoh" -Value $dohValue -Type "DWord" -Description "DNS over HTTPS: $dohMode"

    # --- Disable Autorun / Autoplay ---
    Write-Log -Message "Disabling AutoRun & AutoPlay..."
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Value 1 -Type "DWord" -Description "Disable AutoPlay"
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255 -Type "DWord" -Description "Disable AutoRun on all drives"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoAutorun" -Value 1 -Type "DWord" -Description "Disable AutoRun"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255 -Type "DWord" -Description "Disable AutoRun (user)"

    # --- UAC to Maximum ---
    Write-Log -Message "Setting UAC to maximum..."
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 2 -Type "DWord" -Description "UAC: prompt for consent on secure desktop"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "PromptOnSecureDesktop" -Value 1 -Type "DWord" -Description "UAC: secure desktop"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1 -Type "DWord" -Description "UAC: enabled"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableVirtualization" -Value 1 -Type "DWord" -Description "UAC: virtualization"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "FilterAdministratorToken" -Value 1 -Type "DWord" -Description "UAC: filter admin token"

    # --- LSA Hardening ---
    Write-Log -Message "Hardening LSA..."
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -Value 1 -Type "DWord" -Description "Enable LSA protection (PPL)"
    Initialize-RegPath -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -Name "UseLogonCredential" -Value 0 -Type "DWord" -Description "Disable WDigest plaintext passwords"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -Value 1 -Type "DWord" -Description "Restrict anonymous access"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymousSAM" -Value 1 -Type "DWord" -Description "Restrict anonymous SAM enumeration"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "EveryoneIncludesAnonymous" -Value 0 -Type "DWord" -Description "Exclude anonymous from Everyone"

    # --- Disable WPAD ---
    Write-Log -Message "Disabling WPAD & mDNS..."
    Initialize-RegPath -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad"
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad" -Name "WpadOverride" -Value 1 -Type "DWord" -Description "Disable WPAD"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableMDNS" -Value 0 -Type "DWord" -Description "Disable mDNS"

    # --- Disable Remote Assistance ---
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Value 0 -Type "DWord" -Description "Disable Remote Assistance"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowFullControl" -Value 0 -Type "DWord" -Description "Disable Remote Assistance full control"
    Disable-ServiceByName -Name "RemoteRegistry" -Description "Remote Registry"
    Disable-ServiceByName -Name "RemoteAccess" -Description "Routing and Remote Access"

    # --- Audit Policies ---
    Write-Log -Message "Enabling comprehensive audit policies..."
    if (-not $DryRun) {
        $auditCategories = @(
            "Account Logon", "Account Management", "Logon/Logoff",
            "Object Access", "Policy Change", "Privilege Use",
            "System", "Detailed Tracking"
        )
        foreach ($cat in $auditCategories) {
            auditpol /set /category:"$cat" /success:enable /failure:enable 2>$null | Out-Null
        }
        Write-Log -Message "Enabled audit policies for $($auditCategories.Count) categories"

        # Command-line logging in process creation
        Initialize-RegPath -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type "DWord" -Description "Log command lines in process creation events"
    }

    # --- PowerShell Logging & Hardening ---
    Write-Log -Message "Enabling PowerShell security logging..."
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -Value 1 -Type "DWord" -Description "Enable PS script block logging"
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name "EnableModuleLogging" -Value 1 -Type "DWord" -Description "Enable PS module logging"
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames" -Name "*" -Value "*" -Type "String" -Description "Log all PS modules"

    # Disable PowerShell v2 (downgrade attack vector)
    Write-Log -Message "Disabling PowerShell v2 engine (downgrade attack prevention)..."
    if (-not $DryRun) {
        Disable-WindowsOptionalFeature -Online -FeatureName "MicrosoftWindowsPowerShellV2Root" -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Disable-WindowsOptionalFeature -Online -FeatureName "MicrosoftWindowsPowerShellV2" -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Write-Log -Message "Disabled PowerShell v2 engine"
    }

    # --- System-Wide Exploit Protection (CIS / MSFT recommended) ---
    Write-Log -Message "Enabling system-wide exploit protection (DEP, ASLR, SEHOP, CFG)..."
    if (-not $DryRun) {
        try {
            Set-ProcessMitigation -System -Enable DEP,EmulateAtlThunks,BottomUp,HighEntropy,SEHOP,TerminateOnError,CFG -ErrorAction Stop
            Write-Log -Message "System exploit mitigations enabled: DEP, ASLR (BottomUp+HighEntropy), SEHOP, CFG"
        } catch {
            Write-Log -Message "Could not set system exploit mitigations: $_" -Level "WARN"
        }
    }

    # --- SMB Hardening (signing + encryption) ---
    Write-Log -Message "Hardening SMB (require signing + encryption)..."
    if (-not $DryRun) {
        try {
            Set-SmbServerConfiguration -RequireSecuritySignature $true -EncryptData $true -RejectUnencryptedAccess $true -Force -ErrorAction Stop
            Set-SmbClientConfiguration -RequireSecuritySignature $true -Force -ErrorAction SilentlyContinue
            Write-Log -Message "SMB: signing required, encryption enforced"
        } catch {
            Write-Log -Message "Could not harden SMB configuration: $_" -Level "WARN"
        }
    }

    # --- LSASS Audit Mode (detect credential dumping attempts) ---
    Write-Log -Message "Enabling LSASS audit mode for credential dump detection..."
    Initialize-RegPath -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe" -Name "AuditLevel" -Value 8 -Type "DWord" -Description "LSASS audit level for credential dump detection"

    # --- Disable legacy protocols ---
    Write-Log -Message "Disabling legacy/insecure protocols..."
    # Disable Internet Printing Client
    if (-not $DryRun) {
        Disable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-InternetPrinting-Client" -NoRestart -ErrorAction SilentlyContinue | Out-Null
    }
    # Disable TCP timestamps (OS fingerprinting mitigation)
    if (-not $DryRun) {
        netsh int tcp set global timestamps=disabled 2>$null | Out-Null
        Write-Log -Message "Disabled TCP timestamps"
    }

    # --- Developer Workstation Hardening ---
    Write-Log -Message "Applying developer workstation hardening..." -Level "SECTION"

    # Enable Windows SSH Agent service (secure key storage)
    Write-Log -Message "Enabling OpenSSH Agent for secure key management..."
    if (-not $DryRun) {
        $sshAgent = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
        if ($sshAgent) {
            Set-Service -Name "ssh-agent" -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
            Write-Log -Message "OpenSSH Agent enabled and started"
        } else {
            Write-Log -Message "OpenSSH Agent not installed - consider installing via Settings > Apps > Optional Features" -Level "WARN"
        }
    }

    # Configure Git Credential Manager to use Windows Credential Manager (DPAPI-backed)
    Write-Log -Message "Configuring Git credential storage..."
    if (-not $DryRun) {
        $gitPath = Get-Command git -ErrorAction SilentlyContinue
        if ($gitPath) {
            git config --global credential.helper manager -ErrorAction SilentlyContinue 2>$null
            # Prevent Git from storing credentials in plaintext
            git config --global credential.cacheOptions "" -ErrorAction SilentlyContinue 2>$null
            Write-Log -Message "Git: credential.helper set to manager (Windows Credential Manager)"
        } else {
            Write-Log -Message "Git not found in PATH - skipping credential config" -Level "SKIP"
        }
    }

    # Restrict WSL interop (Strict only - breaks WSL->Windows tool chains)
    if ($script:IsStrict) {
        Write-Log -Message "Restricting WSL interop..."
        Initialize-RegPath -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WSL"
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WSL" -Name "AllowInterop" -Value 0 -Type "DWord" -Description "Restrict WSL-to-Windows process interop"
    }

    # --- NTLMv1 Hardening (both profiles) ---
    Write-Log -Message "Enforcing NTLMv2 only..."
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 5 -Type "DWord" -Description "Send NTLMv2 response only, refuse LM & NTLMv1"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "NoLMHash" -Value 1 -Type "DWord" -Description "Do not store LAN Manager hash"

    # --- Restrict null sessions (both profiles) ---
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" -Name "RestrictNullSessAccess" -Value 1 -Type "DWord" -Description "Restrict null session access to named pipes and shares"

    # --- Restrict NTLM traffic (Strict: deny, Moderate: audit only) ---
    Initialize-RegPath -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "AuditReceivingNTLMTraffic" -Value 2 -Type "DWord" -Description "Audit all incoming NTLM"
    if ($script:IsStrict) {
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "RestrictReceivingNTLMTraffic" -Value 2 -Type "DWord" -Description "Deny all incoming NTLM traffic"
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "RestrictSendingNTLMTraffic" -Value 2 -Type "DWord" -Description "Deny all outgoing NTLM traffic"
    } else {
        Write-Log -Message "NTLM traffic set to audit-only (Moderate profile)"
    }

    # --- Speculative execution mitigations (both profiles) ---
    Write-Log -Message "Verifying speculative execution mitigations..."
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "FeatureSettingsOverride" -Value 72 -Type "DWord" -Description "Enable Spectre/Meltdown mitigations"
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "FeatureSettingsOverrideMask" -Value 3 -Type "DWord" -Description "Enable Spectre/Meltdown mitigation mask"

    # --- Disable Windows Script Host (Strict only - may break build scripts using .vbs/.js) ---
    if ($script:IsStrict) {
        Write-Log -Message "Disabling Windows Script Host..."
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings" -Name "Enabled" -Value 0 -Type "DWord" -Description "Disable Windows Script Host system-wide"
    }

    # --- Disable Office macros from the internet (both profiles) ---
    Write-Log -Message "Blocking internet-sourced Office macros..."
    $officeVersions = @("16.0", "15.0")
    $officeApps = @("Word", "Excel", "PowerPoint")
    foreach ($ver in $officeVersions) {
        foreach ($app in $officeApps) {
            $regPath = "HKCU:\Software\Microsoft\Office\$ver\$app\Security"
            Initialize-RegPath -Path $regPath
            Set-RegistryValue -Path $regPath -Name "blockcontentexecutionfrominternet" -Value 1 -Type "DWord"
        }
    }
    Write-Log -Message "Blocked macro execution from internet zone for Office apps"
}

# ---------------------------------------------------------------------------
# CATEGORY: CLEANUP
# ---------------------------------------------------------------------------
function Invoke-DiskCleanup {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    Write-Log -Message "DISK CLEANUP" -Level "SECTION"

    $freedBytes = [long]0

    # Helper to delete folder contents and track freed space
function Remove-FolderContent {
        [CmdletBinding(SupportsShouldProcess)]
        param([Parameter(Mandatory)][string]$Path, [string]$Label)
        if (-not (Test-Path $Path)) { return }
        if ($DryRun) {
            $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round(($size / 1MB), 1)
            Write-Log -Message "[DRY RUN] Would clean $Label ($sizeMB MB)" -Level "SKIP"
            return
        }
        if ($PSCmdlet.ShouldProcess($Path, "Clean $Label")) {
            $before = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            $script:freedBytes += $before
            $sizeMB = [math]::Round(($before / 1MB), 1)
            if ($sizeMB -gt 0) {
                Write-Log -Message "Cleaned $Label ($sizeMB MB)"
            }
        }
    }

    # --- User temp files ---
    Remove-FolderContent -Path "$env:TEMP" -Label "User temp files"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Temp" -Label "Local AppData temp"

    # --- System temp files ---
    Remove-FolderContent -Path "$env:SystemRoot\Temp" -Label "Windows temp"

    # --- Windows Update cache ---
    Write-Log -Message "Cleaning Windows Update cache..."
    if (-not $DryRun) {
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
    }
    Remove-FolderContent -Path "$env:SystemRoot\SoftwareDistribution\Download" -Label "Windows Update downloads"
    if (-not $DryRun) {
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    }

    # --- Delivery Optimization cache ---
    Write-Log -Message "Cleaning Delivery Optimization cache..."
    if (-not $DryRun) {
        try {
            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
            Write-Log -Message "Cleared Delivery Optimization cache"
        } catch {
            Remove-FolderContent -Path "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" -Label "Delivery Optimization cache"
        }
    }

    # --- Thumbnail cache ---
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Label "Thumbnail cache"

    # --- Windows Error Reports ---
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Microsoft\Windows\WER" -Label "Windows Error Reports (user)"
    Remove-FolderContent -Path "$env:ProgramData\Microsoft\Windows\WER" -Label "Windows Error Reports (system)"

    # --- Crash dumps ---
    Remove-FolderContent -Path "$env:LOCALAPPDATA\CrashDumps" -Label "User crash dumps"
    Remove-FolderContent -Path "$env:SystemRoot\Minidump" -Label "System minidumps"
    if (Test-Path "$env:SystemRoot\MEMORY.DMP") {
        if (-not $DryRun) {
            $dmpSize = (Get-Item "$env:SystemRoot\MEMORY.DMP" -ErrorAction SilentlyContinue).Length
            Remove-Item -Path "$env:SystemRoot\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
            $script:freedBytes += $dmpSize
            Write-Log -Message "Deleted MEMORY.DMP ($([math]::Round(($dmpSize / 1MB), 1)) MB)"
        }
    }

    # --- Font cache ---
    Remove-FolderContent -Path "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache" -Label "Font cache"

    # --- Windows Installer patch cache (orphaned) ---
    Remove-FolderContent -Path "$env:SystemRoot\Installer\$PatchCache$" -Label "Installer patch cache"

    # --- Recycle Bin ---
    Write-Log -Message "Emptying Recycle Bin..."
    if (-not $DryRun) {
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Log -Message "Recycle Bin emptied"
        } catch {
            Write-Log -Message "Could not empty Recycle Bin: $_" -Level "WARN"
        }
    }

    # --- DNS cache ---
    if (-not $DryRun) {
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-Log -Message "Flushed DNS cache"
    }

    # --- Browser caches (Edge, Chrome, Firefox) ---
    Write-Log -Message "Cleaning browser caches..."
    $browserCaches = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data"
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\Cache_Data"
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    )
    foreach ($cache in $browserCaches) {
        if (Test-Path $cache) {
            $browserName = if ($cache -match 'Edge') { "Edge" } elseif ($cache -match 'Chrome') { "Chrome" } else { "Firefox" }
            Remove-FolderContent -Path $cache -Label "$browserName cache"
        }
    }

    # --- npm / pip / NuGet caches (developer-relevant) ---
    Write-Log -Message "Cleaning developer tool caches..."
    Remove-FolderContent -Path "$env:LOCALAPPDATA\npm-cache" -Label "npm cache"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\pip\Cache" -Label "pip cache"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\NuGet\v3-cache" -Label "NuGet cache"

    # --- Summary ---
    $totalMB = [math]::Round(($script:freedBytes / 1MB), 1)
    $totalGB = [math]::Round(($script:freedBytes / 1GB), 2)
    if ($totalGB -ge 1) {
        Write-Log -Message "Total disk space freed: $totalGB GB"
    } else {
        Write-Log -Message "Total disk space freed: $totalMB MB"
    }
}

# ---------------------------------------------------------------------------
# INTERACTIVE MODE
# ---------------------------------------------------------------------------
function Show-InteractiveMenu {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Windows Optimizer - Interactive Mode" -ForegroundColor Cyan
    Write-Host "  Profile: $HardeningProfile" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Performance  - Visual effects, power plan, bloatware, services"
    Write-Host "  [2] Privacy      - Telemetry, tracking, Copilot/Recall, ads"
    Write-Host "  [3] Security     - Defender, firewall, LSA, SMBv1, auditing"
    Write-Host "  [4] Clean        - Temp files, caches, crash dumps, Recycle Bin"
    Write-Host "  [A] All          - Apply everything + clean"
    Write-Host "  [Q] Quit"
    Write-Host ""
    $choices = Read-Host "Select categories (comma-separated, e.g. 1,3)"
    return $choices
}

function Invoke-InteractiveMode {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    $choices = Show-InteractiveMenu
    if ($choices -match '[Qq]') { Write-Host "Aborted." -ForegroundColor Yellow; return }

    $runPerf = $false; $runPriv = $false; $runSec = $false; $runClean = $false
    if ($choices -match '[Aa]') {
        $runPerf = $true; $runPriv = $true; $runSec = $true; $runClean = $true
    } else {
        if ($choices -match '1') { $runPerf = $true }
        if ($choices -match '2') { $runPriv = $true }
        if ($choices -match '3') { $runSec = $true }
        if ($choices -match '4') { $runClean = $true }
    }

    if (-not ($runPerf -or $runPriv -or $runSec -or $runClean)) {
        Write-Host "No valid selection. Exiting." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    $confirm = Read-Host "Apply selected categories? A restore point will be created first. [Y/n]"
    if ($confirm -match '^[Nn]') { Write-Host "Aborted." -ForegroundColor Yellow; return }

    New-OptimizationRestorePoint

    if ($runPerf)  { Invoke-PerformanceOptimization }
    if ($runPriv)  { Invoke-PrivacyHardening }
    if ($runSec)   { Invoke-SecurityHardening }
    if ($runClean) { Invoke-DiskCleanup }

    Show-Summary
}

# ---------------------------------------------------------------------------
# RESTORE POINT & SUMMARY
# ---------------------------------------------------------------------------
function New-OptimizationRestorePoint {
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    if ($script:SkipRestore -or $DryRun) { return }
    Write-Log -Message "Creating system restore point..."
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Pre-Optimize-Windows $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log -Message "Restore point created successfully"
    } catch {
        Write-Log -Message "Could not create restore point (may be throttled by Windows): $_" -Level "WARN"
    }
}

function Show-Summary {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  OPTIMIZATION COMPLETE" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Changes applied:  $($script:ChangeCount)" -ForegroundColor Green
    Write-Host "  Log file:         $($script:LogFile)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  IMPORTANT:" -ForegroundColor Yellow
    Write-Host "  - Some changes require a REBOOT to take effect" -ForegroundColor Yellow
    Write-Host "    (Credential Guard, HVCI, GPU scheduling, power plan, SMBv1)" -ForegroundColor Yellow
    Write-Host "  - Camera/Mic are set to deny-by-default. Grant per-app in" -ForegroundColor Yellow
    Write-Host "    Settings > Privacy & security if needed." -ForegroundColor Yellow
    Write-Host "  - Controlled Folder Access is ON. Add app exceptions in" -ForegroundColor Yellow
    Write-Host "    Windows Security if apps can't write to protected folders." -ForegroundColor Yellow
    Write-Host "  - DNS over HTTPS is forced. Ensure your DNS server supports DoH." -ForegroundColor Yellow
    Write-Host ""
    $reboot = Read-Host "Reboot now? [y/N]"
    if ($reboot -match '^[Yy]') {
        Restart-Computer -Force
    }
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

# Self-elevate to admin if not already running elevated
# Reference: https://ss64.com/ps/syntax-elevate.html, https://blog.expta.com/2017/03/how-to-self-elevate-powershell-script.html
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  This script requires Administrator privileges." -ForegroundColor Yellow
    Write-Host "  Requesting UAC elevation..." -ForegroundColor Yellow
    # Rebuild bound parameters explicitly (UnboundArguments misses declared params like -Interactive)
    $passArgs = @()
    if ($Interactive)      { $passArgs += '-Interactive' }
    if ($Clean)            { $passArgs += '-Clean' }
    if ($DryRun)           { $passArgs += '-DryRun' }
    if ($SkipRestorePoint) { $passArgs += '-SkipRestorePoint' }
    if ($HardeningProfile -ne 'Strict') { $passArgs += "-HardeningProfile $HardeningProfile" }
    $commandLine = "-NoProfile -ExecutionPolicy Bypass -File `"" + $MyInvocation.MyCommand.Path + "`" " + ($passArgs -join ' ')
    try {
        Start-Process -FilePath PowerShell.exe -Verb RunAs -ArgumentList $commandLine -Wait
        exit 0
    } catch {
        Write-Host "  ERROR: Elevation was denied or failed. Please run as Administrator." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host " ___        _   _       _            __      ___         " -ForegroundColor Cyan
Write-Host "/ _ \ _ __ | |_(_)_ __ (_)______    / / /\  / (_)_ __   " -ForegroundColor Cyan
Write-Host "| | | | '_ \| __| | '_ \| |_  / _ \ / / /  \/ /| | '_ \  " -ForegroundColor Cyan
Write-Host "| |_| | |_) | |_| | | | | |/ /  __// / / /\  / | | | | | " -ForegroundColor Cyan
Write-Host "\___/| .__/ \__|_|_| |_|_/___\___/_/  \/  \/ |_|_| |_| " -ForegroundColor Cyan
Write-Host "     |_|                                                 " -ForegroundColor Cyan
Write-Host "  Windows 11 Performance + Privacy + Security Hardener" -ForegroundColor Gray
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

# Check Windows version
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "  OS: $($os.Caption) (Build $($os.BuildNumber))" -ForegroundColor Gray
if ([int]$os.BuildNumber -lt 22000) {
    Write-Host "  WARNING: This script is designed for Windows 11 (build 22000+)." -ForegroundColor Yellow
    Write-Host "  Some settings may not apply to your version." -ForegroundColor Yellow
}
Write-Host ""

if ($DryRun) {
    Write-Host "  *** DRY RUN MODE - No changes will be made ***" -ForegroundColor Yellow
    Write-Host ""
}

if ($Interactive) {
    Invoke-InteractiveMode
} elseif ($Clean -and -not ($Interactive)) {
    # Standalone clean mode: just clean, no hardening
    Write-Host "  Running disk cleanup only." -ForegroundColor White
    Write-Host ""
    Invoke-DiskCleanup
    Show-Summary
} else {
    Write-Host "  Profile: $HardeningProfile" -ForegroundColor White
    Write-Host "  Applying ALL optimizations (performance + privacy + security)." -ForegroundColor White
    Write-Host "  Use -Interactive for selective mode, -DryRun to preview, -HardeningProfile Moderate for less strict." -ForegroundColor DarkGray
    Write-Host ""

    New-OptimizationRestorePoint
    Invoke-PerformanceOptimization
    Invoke-PrivacyHardening
    Invoke-SecurityHardening
    Show-Summary
}
