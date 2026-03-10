
# Teams Rooms and Intune Remediation Scripts Guide

## Purpose
This folder contains:
- Teams Rooms scripts to inventory room accounts and enforce password never-expire policy for specific room-license SKUs.
- Intune Proactive Remediation scripts to detect and remediate devices where Remote Desktop is turned off.

## Files
- `Common-Functions.ps1`
- `Get-TeamsRoomAccountInventory.ps1`
- `Set-RoomAccountPasswordNeverExpires.ps1`
- `Detect-RemoteDesktopDisabled.ps1`
- `Remediate-EnableRemoteDesktop.ps1`

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
- `Get-GraphPagedResults`: Handles Microsoft Graph paging and supports optional request headers.
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
- Logs all actions to a log file.
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
### Detection Script: `Detect-RemoteDesktopDisabled.ps1`
Detects non-compliant devices when either of these is true:
- `HKLM:\System\CurrentControlSet\Control\Terminal Server\fDenyTSConnections` is not `0`
- No enabled firewall rules exist in display group `Remote Desktop`

Exit behavior:
- `0`: Compliant
- `1`: Non-compliant (triggers remediation in Intune)

### Remediation Script: `Remediate-EnableRemoteDesktop.ps1`
Remediates non-compliant devices by:
- Setting `fDenyTSConnections` to `0`
- Enabling firewall rules in display group `Remote Desktop`
- Re-checking compliance after changes

Exit behavior:
- `0`: Remediation successful / compliant
- `1`: Remediation failed or still non-compliant

Recommended Intune assignment settings:
- Run this script using the logged-on credentials: `No`
- Enforce script signature check: `No` (unless you sign scripts)
- Run script in 64-bit PowerShell: `Yes`

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
- Keep `Common-Functions.ps1` in the same folder as the scripts.
- For Intune Proactive Remediation, upload `Detect-RemoteDesktopDisabled.ps1` as Detection and `Remediate-EnableRemoteDesktop.ps1` as Remediation.
