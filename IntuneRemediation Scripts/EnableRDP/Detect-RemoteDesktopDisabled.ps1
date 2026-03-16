[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

if ($issues.Count -eq 0) {
    Write-Output "Compliant: Remote Desktop is enabled, firewall rules are active, and TermService is running."
    exit 0
}

Write-Output ("Non-compliant: {0}" -f ($issues -join " "))
exit 1
