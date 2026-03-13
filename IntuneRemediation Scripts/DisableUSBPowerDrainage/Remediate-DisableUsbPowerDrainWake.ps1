[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-PowerCfgQuery {
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

    return @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
}

function Get-UsbWakeArmedDevices {
    [CmdletBinding()]
    param()

    $wakeArmedDevices = Invoke-PowerCfgQuery -Arguments @('/DEVICEQUERY', 'WAKE_ARMED') -Action 'querying wake-armed devices'
    $usbDevices = [System.Collections.Generic.List[string]]::new()

    foreach ($deviceName in $wakeArmedDevices) {
        $matchingDevices = @(Get-PnpDevice -FriendlyName $deviceName -ErrorAction SilentlyContinue)

        if ($matchingDevices.Count -gt 0) {
            if (($matchingDevices | Where-Object { $_.Class -eq 'USB' }).Count -gt 0) {
                [void]$usbDevices.Add($deviceName)
            }
        } else {
            # Device not found via PnP (no result or suppressed error) - fall back to name check
            if ($deviceName -match '\bUSB\b') {
                [void]$usbDevices.Add($deviceName)
            }
        }
    }

    return @($usbDevices)
}

try {
    $usbWakeArmedDevices = Get-UsbWakeArmedDevices
}
catch {
    Write-Output "Remediation failed during detection: $($_.Exception.Message)"
    exit 1
}

if ($usbWakeArmedDevices.Count -eq 0) {
    Write-Output "Remediated: No USB wake-armed devices found."
    exit 0
}

$remediationErrors = [System.Collections.Generic.List[string]]::new()

foreach ($device in $usbWakeArmedDevices) {
    try {
        Invoke-PowerCfgQuery -Arguments @('/DEVICEDISABLEWAKE', $device) -Action "disabling wake on '$device'" | Out-Null
    }
    catch {
        [void]$remediationErrors.Add("Failed for '$device': $($_.Exception.Message)")
    }
}

if ($remediationErrors.Count -gt 0) {
    $successCount = $usbWakeArmedDevices.Count - $remediationErrors.Count
    $label = if ($successCount -gt 0) { 'Remediation partially failed' } else { 'Remediation failed' }
    Write-Output ("${label} ($successCount/$($usbWakeArmedDevices.Count) devices disabled): $($remediationErrors -join ' ')")
    exit 1
}

try {
    $remainingUsbWakeDevices = Get-UsbWakeArmedDevices
}
catch {
    Write-Output "Remediation ran, but validation failed: $($_.Exception.Message)"
    exit 1
}

if ($remainingUsbWakeDevices.Count -eq 0) {
    Write-Output "Remediated: USB wake-armed devices have been disabled."
    exit 0
}

$remainingNames = $remainingUsbWakeDevices -join '; '
Write-Output "Remediation incomplete: USB wake-armed devices still present: $remainingNames"
exit 1
