# Teams Rooms Scripts Guide

## Purpose
This folder contains PowerShell scripts to inventory Teams room accounts and enforce password never-expire policy for specific room-license SKUs.

## Files
- `Common-Functions.ps1`
- `Get-TeamsRoomAccountInventory.ps1`
- `Set-RoomAccountPasswordNeverExpires.ps1`

## Prerequisites
- PowerShell 5.1+ (or PowerShell 7+)
- Microsoft Graph PowerShell SDK installed
  - `Install-Module Microsoft.Graph -Scope CurrentUser`
- Permissions to read and update users in Microsoft Entra ID

## Shared Helper File
### `Common-Functions.ps1`
Reusable functions used by multiple scripts:
- `Get-GraphPagedResults`: Handles Microsoft Graph paging.
- `Get-UserExtensionAttributes`: Flattens extension attributes 1-15.
- `Ensure-Directory`: Creates output/log directory if missing.
- `Write-StepProgress`: Consistent main step progress bar.
- `Write-LogEntry`: Writes timestamped log entries.
- `Get-SkuIdToPartNumberMap`: Maps SKU GUIDs to SKU part numbers.
- `Get-AssignedSkuPartNumbersForUser`: Resolves assigned user SKUs.
- `ConvertTo-PasswordPolicyList`: Normalizes `passwordPolicies` text.
- `Get-UpdatedPasswordPolicies`: Adds `DisablePasswordExpiration` if missing.

## Inventory Script
### `Get-TeamsRoomAccountInventory.ps1`
Builds a CSV inventory for room accounts that have one or more target SKUs.

Default target SKUs:
- `MICROSOFT_TEAMS_ROOMS_PRO`
- `MCOCAP`

Output fields:
- AccountName
- UPN
- LastNonInteractiveSignInDateTime
- AssignedLicenseName
- PasswordPolicies
- ExtensionAttribute1 through ExtensionAttribute15

Default output path:
- `C:\Temp\TeamsRoomAccountInventory.csv`

Example usage:
```powershell
.\Get-TeamsRoomAccountInventory.ps1
```

Custom output path:
```powershell
.\Get-TeamsRoomAccountInventory.ps1 -OutputPath "C:\Temp\MyRoomInventory.csv"
```

## Password Remediation Script
### `Set-RoomAccountPasswordNeverExpires.ps1`
Finds room accounts with target SKUs and ensures password policy includes:
- `DisablePasswordExpiration`

Default target SKUs:
- `MICROSOFT_TEAMS_ROOMS_PRO`
- `MCOCAP`

Behavior:
- Reads users and assigned licenses from Graph.
- Filters users matching the target SKUs.
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

## Graph Permission Notes
- Inventory script connects with:
  - `User.Read.All`
  - `Directory.Read.All`
  - `AuditLog.Read.All`
- Remediation script connects with:
  - `User.Read.All`
  - `User.ReadWrite.All`
  - `Directory.Read.All`

## Operational Notes
- Use `-WhatIf` first on remediation script to validate intended changes.
- Verify your tenant’s exact SKU part numbers and pass `-TargetSkuPartNumbers` if needed.
- Keep `Common-Functions.ps1` in the same folder as the scripts.
