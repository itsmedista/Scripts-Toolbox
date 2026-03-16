[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Output "Remediation failed: Script requires elevation (run as Administrator or SYSTEM)."
    exit 1
}

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
}
catch {
    Write-Output "Remediation failed while reading current state: $($_.Exception.Message)"
    exit 1
}

# Store original values so we can roll back if a subsequent step fails
$originalAC = $state.ACSettingIndex
$originalDC = $state.DCSettingIndex

try {
    Invoke-PowerCfg -Arguments @('/SETACVALUEINDEX', $state.ActiveSchemeGuid, $usbSubgroupGuid, $usbSelectiveSuspendGuid, '0') -Action 'disabling USB selective suspend for AC power'
    Invoke-PowerCfg -Arguments @('/SETDCVALUEINDEX', $state.ActiveSchemeGuid, $usbSubgroupGuid, $usbSelectiveSuspendGuid, '0') -Action 'disabling USB selective suspend for battery power'
    Invoke-PowerCfg -Arguments @('/SETACTIVE', $state.ActiveSchemeGuid) -Action 're-applying active power scheme'
}
catch {
    # Attempt to restore original values before exiting
    & powercfg.exe /SETACVALUEINDEX $state.ActiveSchemeGuid $usbSubgroupGuid $usbSelectiveSuspendGuid $originalAC 2>&1 | Out-Null
    & powercfg.exe /SETDCVALUEINDEX $state.ActiveSchemeGuid $usbSubgroupGuid $usbSelectiveSuspendGuid $originalDC 2>&1 | Out-Null
    & powercfg.exe /SETACTIVE $state.ActiveSchemeGuid 2>&1 | Out-Null
    Write-Output "Remediation failed (original values restored): $($_.Exception.Message)"
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