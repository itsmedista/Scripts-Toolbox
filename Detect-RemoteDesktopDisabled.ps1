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
    $enabledRules = @($firewallRules | Where-Object { $_.Enabled -eq "True" })
    if ($enabledRules.Count -eq 0) {
        [void]$issues.Add("Remote Desktop firewall rules are not enabled.")
    }
}
catch {
    [void]$issues.Add("Unable to validate Remote Desktop firewall rules: $($_.Exception.Message)")
}

if ($issues.Count -eq 0) {
    Write-Output "Compliant: Remote Desktop is enabled and firewall rules are active."
    exit 0
}

Write-Output ("Non-compliant: {0}" -f ($issues -join " "))
exit 1
