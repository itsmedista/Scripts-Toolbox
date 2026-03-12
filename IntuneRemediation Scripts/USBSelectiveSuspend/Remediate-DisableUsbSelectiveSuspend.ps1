[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$usbSubgroupGuid = "2a737441-1930-4402-8d77-b2bebba308a3"
$usbSelectiveSuspendGuid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
$powerSchemesRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes"

function Get-UsbSelectiveSuspendState {
    [CmdletBinding()]
    param()

    $activeSchemeGuid = (Get-ItemProperty -Path $powerSchemesRoot -Name "ActivePowerScheme" -ErrorAction Stop).ActivePowerScheme
    $settingPath = Join-Path $powerSchemesRoot "$activeSchemeGuid\$usbSubgroupGuid\$usbSelectiveSuspendGuid"
    $settingValues = Get-ItemProperty -Path $settingPath -Name "ACSettingIndex", "DCSettingIndex" -ErrorAction Stop

    [PSCustomObject]@{
        ActiveSchemeGuid = $activeSchemeGuid
        ACSettingIndex   = [int]$settingValues.ACSettingIndex
        DCSettingIndex   = [int]$settingValues.DCSettingIndex
    }
}

function Invoke-PowerCfg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Action
    )

    $output = & powercfg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg failed while $Action. ExitCode=$LASTEXITCODE. Output: $($output -join ' ')"
    }
}

try {
    $state = Get-UsbSelectiveSuspendState

    Invoke-PowerCfg -Arguments @('/SETACVALUEINDEX', $state.ActiveSchemeGuid, $usbSubgroupGuid, $usbSelectiveSuspendGuid, '0') -Action 'disabling USB selective suspend for AC power'
    Invoke-PowerCfg -Arguments @('/SETDCVALUEINDEX', $state.ActiveSchemeGuid, $usbSubgroupGuid, $usbSelectiveSuspendGuid, '0') -Action 'disabling USB selective suspend for battery power'
    Invoke-PowerCfg -Arguments @('/SETACTIVE', $state.ActiveSchemeGuid) -Action 're-applying active power scheme'
}
catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}

try {
    $updatedState = Get-UsbSelectiveSuspendState
}
catch {
    Write-Output "Remediation ran, but validation failed: $($_.Exception.Message)"
    exit 1
}

if ($updatedState.ACSettingIndex -eq 0 -and $updatedState.DCSettingIndex -eq 0) {
    Write-Output "Remediated: USB selective suspend is disabled for AC and DC power."
    exit 0
}

Write-Output "Remediation incomplete: ACSettingIndex=$($updatedState.ACSettingIndex), DCSettingIndex=$($updatedState.DCSettingIndex)."
exit 1