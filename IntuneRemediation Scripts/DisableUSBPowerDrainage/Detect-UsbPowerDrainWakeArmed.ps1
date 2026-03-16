[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Output "Non-compliant: Script requires elevation to query wake-armed devices."
    exit 1
}

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

    # USB-related device classes: USB controllers, USB hubs, and composite USB devices
    $usbClasses = @('USB', 'USBHub', 'USBDevice')

    foreach ($deviceName in $wakeArmedDevices) {
        $matchingDevices = @(Get-PnpDevice -FriendlyName $deviceName -ErrorAction SilentlyContinue)

        if ($matchingDevices.Count -gt 0) {
            if (($matchingDevices | Where-Object { $_.Class -in $usbClasses }).Count -gt 0) {
                [void]$usbDevices.Add($deviceName)
            }
        } else {
            # PnP lookup returned nothing (driver not loaded, suppressed error, etc.) — fall back to
            # name-based heuristic. Require "USB" as a standalone word to reduce false positives.
            if ($deviceName -match '(?i)\bUSB\b') {
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
    Write-Output "Non-compliant: Unable to detect USB wake-armed devices. $($_.Exception.Message)"
    exit 1
}

if ($usbWakeArmedDevices.Count -eq 0) {
    Write-Output "Compliant: No USB devices are wake-armed."
    exit 0
}

$deviceNames = $usbWakeArmedDevices -join '; '
Write-Output "Non-compliant: USB wake-armed devices detected: $deviceNames"
exit 1
