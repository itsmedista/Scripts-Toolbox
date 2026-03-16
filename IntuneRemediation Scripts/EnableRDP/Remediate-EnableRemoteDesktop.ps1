[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Output "Remediation failed: Script requires elevation (run as Administrator or SYSTEM)."
    exit 1
}

function Get-RdpComplianceIssues {
    [CmdletBinding()]
    param()

    $issues = [System.Collections.Generic.List[string]]::new()

    try {
        $rdpValue = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections").fDenyTSConnections
        if ($rdpValue -ne 0) {
            [void]$issues.Add("Remote Desktop is disabled (fDenyTSConnections=$rdpValue).")
        }
    }
    catch {
        [void]$issues.Add("Unable to read fDenyTSConnections: $($_.Exception.Message)")
    }

    try {
        $firewallRules = @(Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop)
        $enabledInboundRules = @($firewallRules | Where-Object { $_.Enabled -eq "True" -and $_.Direction -eq "Inbound" })
        if ($enabledInboundRules.Count -eq 0) {
            [void]$issues.Add("No enabled inbound Remote Desktop firewall rules found.")
        }
    }
    catch {
        [void]$issues.Add("Unable to validate Remote Desktop firewall rules: $($_.Exception.Message)")
    }

    try {
        $svc = Get-Service -Name 'TermService' -ErrorAction Stop
        if ($svc.StartType -eq 'Disabled') {
            [void]$issues.Add("Remote Desktop service (TermService) is disabled.")
        }
        elseif ($svc.Status -ne 'Running') {
            [void]$issues.Add("Remote Desktop service (TermService) is not running (Status=$($svc.Status)).")
        }
    }
    catch {
        [void]$issues.Add("Unable to check Remote Desktop service: $($_.Exception.Message)")
    }

    return @($issues)
}

$rdpRegPath = "HKLM:\System\CurrentControlSet\Control\Terminal Server"

# Save original registry value for rollback if subsequent steps fail
$originalRdpValue = $null
try {
    $originalRdpValue = (Get-ItemProperty -Path $rdpRegPath -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections
    Set-ItemProperty -Path $rdpRegPath -Name "fDenyTSConnections" -Type DWord -Value 0
}
catch {
    Write-Output "Remediation failed while enabling Remote Desktop: $($_.Exception.Message)"
    exit 1
}

try {
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop
}
catch {
    # Roll back registry change so the machine isn't left in a half-enabled state
    if ($null -ne $originalRdpValue) {
        Set-ItemProperty -Path $rdpRegPath -Name "fDenyTSConnections" -Type DWord -Value $originalRdpValue -ErrorAction SilentlyContinue
    }
    Write-Output "Remediation failed while enabling firewall rules (registry rolled back): $($_.Exception.Message)"
    exit 1
}

try {
    $svc = Get-Service -Name 'TermService' -ErrorAction Stop
    if ($svc.StartType -eq 'Disabled') {
        Set-Service -Name 'TermService' -StartupType Automatic -ErrorAction Stop
    }
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'TermService' -ErrorAction Stop
    }
}
catch {
    Write-Output "Remediation failed while starting Remote Desktop service: $($_.Exception.Message)"
    exit 1
}

$remainingIssues = Get-RdpComplianceIssues
if ($remainingIssues.Count -eq 0) {
    Write-Output "Remediated: Remote Desktop is enabled, firewall rules are active, and TermService is running."
    exit 0
}

Write-Output ("Remediation incomplete: {0}" -f ($remainingIssues -join " "))
exit 1
