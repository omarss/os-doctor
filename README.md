# Optimize-Windows

Opinionated Windows 11 hardening script covering **performance**, **privacy**, **security**, and **disk cleanup** in a single run. Creates a system restore point before making changes.

## Quick Start

```powershell
# Run everything with Strict profile (default)
powershell -ExecutionPolicy Bypass -File .\Optimize-Windows.ps1

# Less aggressive — won't break workflows
.\Optimize-Windows.ps1 -HardeningProfile Moderate

# Preview changes without applying
.\Optimize-Windows.ps1 -DryRun

# Pick and choose
.\Optimize-Windows.ps1 -Interactive

# Cleanup only
.\Optimize-Windows.ps1 -Clean
```

Auto-elevates via UAC if not running as Administrator. All flags are forwarded through elevation.

## Parameters

| Flag | Description |
|---|---|
| `-HardeningProfile Strict` | Maximum hardening (default) |
| `-HardeningProfile Moderate` | Recommended practices without breaking things |
| `-Interactive` | Choose categories interactively |
| `-Clean` | Run disk cleanup only (no hardening) |
| `-DryRun` | Preview all changes without applying |
| `-SkipRestorePoint` | Skip creating a system restore point |

Flags can be combined: `.\Optimize-Windows.ps1 -HardeningProfile Moderate -Interactive -DryRun`

## Profiles

### Strict (default)

Full lockdown for security-focused workstations.

| Area | What it does |
|---|---|
| Visual effects | All disabled (best performance) |
| Power plan | Ultimate Performance, hibernation off |
| SysMain/Prefetch | Disabled (SSD optimized) |
| Background apps | Force denied |
| Bloatware | 50+ apps removed (MS first-party + third-party) |
| Services | 14 unnecessary services disabled |
| Telemetry | Level 0 + DiagTrack/dmwappushservice killed |
| Camera/Mic | Deny by default (grant per-app manually) |
| Capabilities | 14 categories denied (contacts, email, radios, etc.) |
| ASR rules | 15 rules in **Block** mode |
| Controlled Folder Access | **Enabled** (blocks unauthorized writes) |
| DNS over HTTPS | **Forced** |
| NTLM traffic | Denied both directions |
| WSL interop | Restricted |
| Windows Script Host | Disabled |
| Error Reporting | Disabled |

### Moderate

Sensible defaults following Microsoft/CIS recommended practices. Won't break video calls, WSL workflows, or background apps.

| Area | What it does |
|---|---|
| Visual effects | Kept (just reduce menu delay) |
| Power plan | High Performance |
| SysMain/Prefetch | Kept running |
| Background apps | User-controlled |
| Bloatware | Third-party junk only (12 apps) |
| Services | 4 obvious ones (Fax, RetailDemo, etc.) |
| Telemetry | Level 1 (Required/Basic) |
| Camera/Mic | User-controlled |
| Capabilities | Left accessible |
| ASR rules | 15 rules in **Audit** mode (logs, no blocking) |
| Controlled Folder Access | **Audit** mode (logs only) |
| DNS over HTTPS | **Automatic** (if server supports) |
| NTLM traffic | Audit only |
| WSL interop | Left open |
| Windows Script Host | Kept |
| Error Reporting | Kept |

### Shared (both profiles)

Applied regardless of profile:

- Windows Defender hardening (real-time, cloud, PUA, network protection)
- Firewall on all profiles (inbound blocked, logging enabled)
- Remote Desktop disabled
- SMBv1 disabled + SMB signing/encryption enforced
- VBS, Credential Guard, HVCI (Memory Integrity)
- NetBIOS, LLMNR, WPAD, mDNS disabled
- UAC set to maximum
- LSA hardening (PPL, WDigest disabled, anonymous restricted)
- NTLMv2 enforced (LM/NTLMv1 refused), no LM hash storage
- Null session restriction
- AutoRun/AutoPlay disabled
- System exploit protection (DEP, ASLR, SEHOP, CFG)
- PowerShell v2 disabled (downgrade attack prevention)
- PowerShell script block + module logging enabled
- Comprehensive audit policies (8 categories)
- Command-line logging in process creation events
- LSASS audit mode (credential dump detection)
- Spectre/Meltdown mitigations
- Office macros from internet blocked
- OpenSSH Agent enabled
- Git credential helper set to Windows Credential Manager
- TCP timestamps disabled (OS fingerprinting mitigation)
- Internet Printing Client disabled
- Remote Assistance disabled
- Remote Registry / Remote Access disabled

## Cleanup (`-Clean`)

Purges temporary and cached files. Can be run standalone or selected as category [4] in interactive mode.

| Target | What it cleans |
|---|---|
| Temp files | `%TEMP%`, `%LOCALAPPDATA%\Temp`, `%SystemRoot%\Temp` |
| Windows Update | `SoftwareDistribution\Download` (stops/restarts wuauserv) |
| Delivery Optimization | DO cache |
| Thumbnails | Explorer thumbnail cache |
| Error reports | WER (user + system) |
| Crash dumps | User CrashDumps, Minidump, MEMORY.DMP |
| Font cache | FontCache service data |
| Installer cache | Orphaned `$PatchCache$` |
| Recycle Bin | All drives |
| DNS cache | Flushed |
| Browser caches | Edge, Chrome, Firefox |
| Dev tool caches | npm, pip, NuGet |

Reports total freed space at the end.

## Logging

Every run creates a timestamped log file:

```
%USERPROFILE%\Optimize-Windows_20260404_153022.log
```

## Recovery

A system restore point is created before any changes (unless `-SkipRestorePoint` is used).

To revert:
1. Open **System Restore** (`rstrui.exe`)
2. Select the `Pre-Optimize-Windows` restore point
3. Follow the wizard

## Notes

- **Windows edition matters**: Telemetry level 0 only works on Enterprise/Education. Credential Guard requires Pro+. Some ASR rules require Defender to be the active AV.
- **Third-party antivirus**: If Defender is disabled by another AV, Defender settings are skipped gracefully with a single message.
- **Reboot required** for: Credential Guard, HVCI, GPU scheduling, PowerShell v2 removal, SMBv1 removal, exploit protection.
- **Camera/Mic** (Strict): Denied by default. Grant per-app in Settings > Privacy & security.
- **Controlled Folder Access** (Strict): May block apps from writing to Documents/Desktop. Add exceptions in Windows Security.
- **DNS over HTTPS** (Strict): Forced. Ensure your DNS server supports DoH (Cloudflare 1.1.1.1, Google 8.8.8.8, etc.).

## References

- [CIS Microsoft Windows 11 Enterprise Benchmark v5.0.0](https://www.cisecurity.org/benchmark/microsoft_windows_desktop)
- [Microsoft - Exploit Protection Reference](https://learn.microsoft.com/en-us/defender-endpoint/exploit-protection-reference)
- [Microsoft - Credential Guard](https://learn.microsoft.com/en-us/windows/security/identity-protection/credential-guard/)
- [Microsoft - Attack Surface Reduction Rules](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference)
- [Atlant Security - Windows 11 Hardening Script](https://github.com/atlantsecurity/windows-hardening-scripts)
