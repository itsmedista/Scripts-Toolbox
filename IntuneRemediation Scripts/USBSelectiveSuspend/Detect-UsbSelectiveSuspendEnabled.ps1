
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Power subgroup GUID for USB settings (USB Settings subgroup)
# Ref: https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options
$usbSubgroupGuid = "2a737441-1930-4402-8d77-b2bebba308a3"
# Power setting GUID for USB selective suspend (USB selective suspend setting)
$usbSelectiveSuspendGuid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
$powerSchemesRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes"

function Get-UsbSelectiveSuspendState {
    [CmdletBinding()]
    param()

    $activeSchemeGuid = (Get-ItemProperty -Path $powerSchemesRoot -Name "ActivePowerScheme" -ErrorAction Stop).ActivePowerScheme
    $settingPath = Join-Path $powerSchemesRoot "$activeSchemeGuid\$usbSubgroupGuid\$usbSelectiveSuspendGuid"

    if (-not (Test-Path -LiteralPath $settingPath)) {
        throw "USB selective suspend setting not found in active power scheme ($activeSchemeGuid). The scheme may not include USB settings."
    }

    $settingValues = Get-ItemProperty -Path $settingPath -Name "ACSettingIndex", "DCSettingIndex" -ErrorAction Stop

    [PSCustomObject]@{
        ActiveSchemeGuid = $activeSchemeGuid
        ACSettingIndex   = [int]$settingValues.ACSettingIndex
        DCSettingIndex   = [int]$settingValues.DCSettingIndex
    }
}

$issues = [System.Collections.Generic.List[string]]::new()

try {
    $state = Get-UsbSelectiveSuspendState

    if ($state.ACSettingIndex -ne 0) {
        [void]$issues.Add("AC power USB selective suspend is enabled (ACSettingIndex=$($state.ACSettingIndex)).")
    }

    if ($state.DCSettingIndex -ne 0) {
        [void]$issues.Add("Battery power USB selective suspend is enabled (DCSettingIndex=$($state.DCSettingIndex)).")
    }
}
catch {
    [void]$issues.Add("Unable to read USB selective suspend state: $($_.Exception.Message)")
}

if ($issues.Count -eq 0) {
    Write-Output "Compliant: USB selective suspend is disabled for AC and DC power."
    exit 0
}

Write-Output ("Non-compliant: {0}" -f ($issues -join " "))
exit 1