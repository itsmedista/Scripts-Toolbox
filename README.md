
# Teams Rooms and Intune Remediation Scripts Guide

## Purpose
This folder contains:
- Teams Rooms scripts to inventory room accounts and enforce password never-expire policy for specific room-license SKUs.
- Intune Proactive Remediation scripts to detect and remediate devices where Remote Desktop is turned off.
- Intune Proactive Remediation scripts to detect and remediate devices where USB selective suspend is enabled.

## Files
- `Common-Functions.ps1`
- `Get-TeamsRoomAccountInventory.ps1`
- `Set-RoomAccountPasswordNeverExpires.ps1`
- `IntuneRemediation Scripts\EnableRDP\Detect-RemoteDesktopDisabled.ps1`
- `IntuneRemediation Scripts\EnableRDP\Remediate-EnableRemoteDesktop.ps1`
- `IntuneRemediation Scripts\USBSelectiveSuspend\Detect-UsbSelectiveSuspendEnabled.ps1`
- `IntuneRemediation Scripts\USBSelectiveSuspend\Remediate-DisableUsbSelectiveSuspend.ps1`
- `IntuneRemediation Scripts\DisableUSBPowerDrainage\Detect-UsbPowerDrainWakeArmed.ps1`
- `IntuneRemediation Scripts\DisableUSBPowerDrainage\Remediate-DisableUsbPowerDrainWake.ps1`

## Prerequisites
- PowerShell 5.1+ (or PowerShell 7+)
- Microsoft Graph PowerShell SDK installed
  - `Install-Module Microsoft.Graph -Scope CurrentUser`
- Permissions to read and update users in Microsoft Entra ID
- For Intune remediation scripts: run in Intune Management Extension context (typically `SYSTEM`) with local admin rights on target devices.

## Default Target Licenses
- `Microsoft Teams Rooms Pro`
  - SKU: `4cde982a-ede4-4409-9ae6-b003453c8ea6`
- `Microsoft Teams Shared Devices`
  - SKU: `295a8eb0-f78d-45c7-8b5b-1eed5ed02dff`

## Shared Helper File
### `Common-Functions.ps1`
Reusable functions used by multiple scripts:
- `Get-GraphPagedResults`: Handles Microsoft Graph paging and supports optional request headers. Retries failed requests up to 3 times with linear backoff (5 s → 10 s → 15 s), respecting the `Retry-After` header returned by Graph on HTTP 429 throttling responses.
- `Get-UserExtensionAttributes`: Flattens extension attributes 1-15.
- `Ensure-Directory`: Creates output/log directory if missing, and validates that an existing path is a directory.
- `Write-StepProgress`: Consistent main step progress bar.
- `Assert-GraphConnection`: Validates an existing Graph session and required scopes (used with `-SkipConnect`).
- `Write-LogEntry`: Writes timestamped log entries.
- `Get-TeamsRoomLicenseDefinitions`: Returns static Teams Rooms license objects.
- `ConvertTo-NormalizedSkuToken`: Normalizes license IDs for matching.
- `Get-TargetLicenseLookup`: Builds lookup map from static license objects and validates target SKUs.
- `ConvertTo-GraphGuidLiteral`: Converts a normalized SKU token into Graph GUID format.
- `Get-MatchingTargetLicensesForUser`: Resolves matched target licenses for a user.
- `Get-UsersWithTargetLicenses`: Uses server-side Graph filtering (`assignedLicenses/any(...)`) first, then falls back to client-side filtering with `Get-MgUser` if needed.
- `ConvertTo-PasswordPolicyList`: Normalizes `passwordPolicies` text.
- `Get-UpdatedPasswordPolicies`: Adds `DisablePasswordExpiration` if missing.

## Inventory Script
### `Get-TeamsRoomAccountInventory.ps1`
Builds a CSV inventory for room accounts that have one or more target licenses.

> **Note:** The output directory is validated and created before any Graph queries run. If the path is invalid or unwritable the script fails immediately rather than after expensive API calls complete.

Parameters:
- `-OutputPath` (default: `C:\Temp\TeamsRoomAccountInventory.csv`)
- `-TargetLicenses` (optional override array of `{ Name, Sku }`)
- `-SkipConnect` (uses existing Graph context and validates required scopes)

Output fields:
- `AccountName`
- `UPN`
- `LastNonInteractiveSignInDateTime`
- `AssignedLicenseName`
- `PasswordPolicies`
- `ExtensionAttribute1` through `ExtensionAttribute15`

The script returns a summary object to the pipeline after export:
- `OutputPath`
- `RowsExported`
- `GeneratedAt`

Example usage:
```powershell
.\Get-TeamsRoomAccountInventory.ps1
```

Custom output path:
```powershell
.\Get-TeamsRoomAccountInventory.ps1 -OutputPath "C:\Temp\MyRoomInventory.csv"
```

Use existing Graph connection:
```powershell
Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All","AuditLog.Read.All"
.\Get-TeamsRoomAccountInventory.ps1 -SkipConnect
```

## Password Remediation Script
### `Set-RoomAccountPasswordNeverExpires.ps1`
Finds room accounts with target licenses and ensures password policy includes `DisablePasswordExpiration`.

Behavior:
- Uses static target license objects (no `subscribedSkus` query).
- Resolves target users through helper logic that attempts server-side Graph license filtering first.
- Falls back to client-side filtering if server-side filtering is unavailable.
- Checks `passwordPolicies`.
- If needed, patches the user to add `DisablePasswordExpiration`.
- Logs all actions to a log file. Log file creation is validated at startup — a failure to create the log file throws immediately with a descriptive error before any Graph queries run.
- Shows overall and per-account progress bars.

Default log path:
- `C:\Temp\Set-RoomAccountPasswordNeverExpires_yyyyMMdd_HHmmss.log`

Safe test run (no changes):
```powershell
.\Set-RoomAccountPasswordNeverExpires.ps1 -WhatIf
```

Live run (applies changes):
```powershell
.\Set-RoomAccountPasswordNeverExpires.ps1
```

Custom log path:
```powershell
.\Set-RoomAccountPasswordNeverExpires.ps1 -LogPath "C:\Temp\RoomPasswordPolicyFix.log"
```

## Intune Proactive Remediation (Remote Desktop)
### Detection Script: `IntuneRemediation Scripts\EnableRDP\Detect-RemoteDesktopDisabled.ps1`
Detects non-compliant devices when any of these are true:
- `HKLM:\System\CurrentControlSet\Control\Terminal Server\fDenyTSConnections` is not `0`
- No **inbound** enabled firewall rules exist in display group `Remote Desktop` (outbound-only rules no longer falsely pass)
- The `TermService` (Remote Desktop Services) service is disabled or not running

Exit behavior:
- `0`: Compliant — registry allows RDP, inbound firewall rules are enabled, and TermService is running
- `1`: Non-compliant (triggers remediation in Intune)

### Remediation Script: `IntuneRemediation Scripts\EnableRDP\Remediate-EnableRemoteDesktop.ps1`
Remediates non-compliant devices by:
1. Saving the current `fDenyTSConnections` value for rollback
2. Setting `fDenyTSConnections` to `0`
3. Enabling firewall rules in display group `Remote Desktop` — if this step fails, the registry change is **rolled back** automatically
4. Enabling `TermService` startup type (if `Disabled`) and starting the service
5. Re-checking full compliance after all changes

> **Elevation required:** The script exits with a clear error message if not running as Administrator or SYSTEM.

Exit behavior:
- `0`: Remediation successful — registry, firewall, and TermService all verified compliant
- `1`: Remediation failed or still non-compliant

Recommended Intune assignment settings:
- Run this script using the logged-on credentials: `No`
- Enforce script signature check: `No` (unless you sign scripts)
- Run script in 64-bit PowerShell: `Yes`

## Intune Proactive Remediation (USB Selective Suspend)
### Detection Script: `IntuneRemediation Scripts\USBSelectiveSuspend\Detect-UsbSelectiveSuspendEnabled.ps1`
Detects non-compliant devices when either of these is true for the active power plan:
- `ACSettingIndex` for USB selective suspend is not `0`
- `DCSettingIndex` for USB selective suspend is not `0`

Registry path checked:
- `HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\<ActiveSchemeGuid>\2a737441-1930-4402-8d77-b2bebba308a3\48e6b7a6-50f5-4782-a5d4-53bb8f07e226`

The GUIDs used:
- `2a737441-1930-4402-8d77-b2bebba308a3` — USB Settings subgroup
- `48e6b7a6-50f5-4782-a5d4-53bb8f07e226` — USB selective suspend setting

If the USB selective suspend setting path is absent in the active power scheme (e.g., a custom scheme without USB settings), the script reports a clear error instead of a generic registry exception.

Exit behavior:
- `0`: Compliant — USB selective suspend disabled for both AC and DC
- `1`: Non-compliant (triggers remediation in Intune)

### Remediation Script: `IntuneRemediation Scripts\USBSelectiveSuspend\Remediate-DisableUsbSelectiveSuspend.ps1`
Remediates non-compliant devices by:
1. Reading and saving the current AC and DC setting values for rollback
2. Setting USB selective suspend to `0` for both AC and DC on the active power plan via `powercfg`
3. Re-applying the active plan
4. Re-validating the applied settings — if any step fails, the original AC and DC values are **restored automatically**

> **Elevation required:** The script exits with a clear error message if not running as Administrator or SYSTEM.

Exit behavior:
- `0`: Remediation successful — both ACSettingIndex and DCSettingIndex verified as `0`
- `1`: Remediation failed or still non-compliant (original values restored if failure occurred mid-remediation)

## Intune Proactive Remediation (USB Power Drain / Wake-Armed Devices)
### Detection Script: `IntuneRemediation Scripts\DisableUSBPowerDrainage\Detect-UsbPowerDrainWakeArmed.ps1`
Detects non-compliant devices where one or more USB devices are configured to wake the system from sleep.

Detection method:
1. Queries wake-armed devices via `powercfg /DEVICEQUERY WAKE_ARMED`
2. For each device, looks up its PnP class via `Get-PnpDevice`. Devices with class `USB`, `USBHub`, or `USBDevice` are flagged.
3. If the PnP lookup returns no result, falls back to a case-insensitive name match for the standalone word `USB`.

> **Elevation required:** The script exits with a clear error message if not running as Administrator or SYSTEM.

Exit behavior:
- `0`: Compliant — no USB wake-armed devices found
- `1`: Non-compliant (triggers remediation in Intune), or script could not run due to insufficient elevation

### Remediation Script: `IntuneRemediation Scripts\DisableUSBPowerDrainage\Remediate-DisableUsbPowerDrainWake.ps1`
Remediates non-compliant devices by:
1. Detecting all USB wake-armed devices (same logic as the detection script)
2. Running `powercfg /DEVICEDISABLEWAKE <device>` for each one
3. Re-querying to confirm all USB wake devices have been disabled

If some devices fail to be disabled, the script reports partial success (count of devices disabled vs. total) and exits with `1`.

> **Elevation required:** The script exits with a clear error message if not running as Administrator or SYSTEM.

Exit behavior:
- `0`: Remediation successful — no USB wake-armed devices remain
- `1`: Remediation failed, partially failed, or validation after remediation failed

## Graph Permission Notes
- Inventory script requires:
  - `User.Read.All`
  - `Directory.Read.All`
  - `AuditLog.Read.All`
- Remediation script requires:
  - `User.Read.All`
  - `User.ReadWrite.All`
  - `Directory.Read.All`
- When using `-SkipConnect`, the current Graph session must already include the required scopes.

## Operational Notes
- Use `-WhatIf` first on remediation script to validate intended changes.
- Override defaults with `-TargetLicenses` if you need a different license set.
- Keep `Common-Functions.ps1` in the same folder as the Teams Room scripts.
- All Intune remediation scripts require elevation. Intune runs scripts as SYSTEM by default, which satisfies this requirement. For local testing, run PowerShell as Administrator.
- For Intune Proactive Remediation (RDP), upload `EnableRDP\Detect-RemoteDesktopDisabled.ps1` as Detection and `EnableRDP\Remediate-EnableRemoteDesktop.ps1` as Remediation.
- For Intune Proactive Remediation (USB Selective Suspend), upload `USBSelectiveSuspend\Detect-UsbSelectiveSuspendEnabled.ps1` as Detection and `USBSelectiveSuspend\Remediate-DisableUsbSelectiveSuspend.ps1` as Remediation.
- For Intune Proactive Remediation (USB Power Drain), upload `DisableUSBPowerDrainage\Detect-UsbPowerDrainWakeArmed.ps1` as Detection and `DisableUSBPowerDrainage\Remediate-DisableUsbPowerDrainWake.ps1` as Remediation.

## Changelog

### 2026-03-15
**Common-Functions.ps1**
- `Get-GraphPagedResults`: Added retry logic (up to 3 attempts) with linear backoff (5 s, 10 s, 15 s). Respects the `Retry-After` header returned by Microsoft Graph during HTTP 429 throttling.

**Get-TeamsRoomAccountInventory.ps1**
- Output directory is now validated and created before connecting to Graph or running any queries. Previously, an invalid output path was only discovered after all API calls completed.

**Set-RoomAccountPasswordNeverExpires.ps1**
- Log file creation is now wrapped in `try/catch`. A failure to create the log file throws immediately with a descriptive message rather than surfacing as a confusing write error later.

**Detect-UsbPowerDrainWakeArmed.ps1** / **Remediate-DisableUsbPowerDrainWake.ps1**
- Added elevation check — scripts exit with a clear message if not running as Administrator or SYSTEM.
- USB class detection expanded from `USB` only to `USB`, `USBHub`, and `USBDevice` to cover hubs and composite devices.
- Name-based fallback regex made case-insensitive (`(?i)\bUSB\b`).

**Detect-RemoteDesktopDisabled.ps1**
- Firewall compliance check now filters to **inbound** rules only. Previously, an enabled outbound rule in the "Remote Desktop" display group would incorrectly satisfy the check.
- Added `TermService` (Remote Desktop Services) check: reports non-compliant if the service is disabled or not running.
- Updated compliant output message to reflect all three checks.

**Remediate-EnableRemoteDesktop.ps1**
- Added elevation check.
- Removed `| Out-Null` from `Enable-NetFirewallRule` so errors are no longer silently swallowed.
- Saves the original `fDenyTSConnections` registry value before modification. If enabling firewall rules fails, the registry change is rolled back automatically.
- Enables `TermService` startup type (if `Disabled`) and starts the service as part of remediation.
- `Get-RdpComplianceIssues` (post-remediation validation) updated to match the detection script: inbound-only firewall filter and TermService check.

**Detect-UsbSelectiveSuspendEnabled.ps1** / **Remediate-DisableUsbSelectiveSuspend.ps1**
- Added inline comments documenting both power setting GUIDs with a reference to Microsoft docs.
- Added `Test-Path` check before reading the USB selective suspend registry path. Provides a descriptive error when the active power scheme does not include USB settings, instead of a generic registry exception.

**Remediate-DisableUsbSelectiveSuspend.ps1** (additional)
- Added elevation check.
- Saves original `ACSettingIndex` and `DCSettingIndex` values before modification. If any `powercfg` step fails, both values and the active scheme are restored automatically.
