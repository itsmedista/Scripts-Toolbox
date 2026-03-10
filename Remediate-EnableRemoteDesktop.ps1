[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
        $enabledRules = @($firewallRules | Where-Object { $_.Enabled -eq "True" })
        if ($enabledRules.Count -eq 0) {
            [void]$issues.Add("Remote Desktop firewall rules are not enabled.")
        }
    }
    catch {
        [void]$issues.Add("Unable to validate Remote Desktop firewall rules: $($_.Exception.Message)")
    }

    return @($issues)
}

try {
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Type DWord -Value 0
}
catch {
    Write-Output "Remediation failed while enabling Remote Desktop: $($_.Exception.Message)"
    exit 1
}

try {
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop | Out-Null
}
catch {
    Write-Output "Remediation failed while enabling firewall rules: $($_.Exception.Message)"
    exit 1
}

$remainingIssues = Get-RdpComplianceIssues
if ($remainingIssues.Count -eq 0) {
    Write-Output "Remediated: Remote Desktop is enabled and firewall rules are active."
    exit 0
}

Write-Output ("Remediation incomplete: {0}" -f ($remainingIssues -join " "))
exit 1
