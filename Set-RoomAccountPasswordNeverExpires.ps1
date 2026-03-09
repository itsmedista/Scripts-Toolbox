[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = ("C:\Temp\Set-RoomAccountPasswordNeverExpires_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")),

    [Parameter(Mandatory = $false)]
    [string[]]$TargetSkuPartNumbers = @(
        "MICROSOFT_TEAMS_ROOMS_PRO",
        "MCOCAP"
    ),

    [Parameter(Mandatory = $false)]
    [switch]$SkipConnect
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path -Path $PSScriptRoot -ChildPath "Common-Functions.ps1"
if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "Required helper file was not found: $helperPath"
}
. $helperPath

$logDirectory = Split-Path -Path $LogPath -Parent
Ensure-Directory -Path $logDirectory
New-Item -Path $LogPath -ItemType File -Force | Out-Null

$mainProgressId = 0
$mainActivity = "Room account password expiration remediation"
$totalSteps = 5

Write-LogEntry -LogPath $LogPath -Message "Script started."
Write-LogEntry -LogPath $LogPath -Message ("Target SKUs: {0}" -f ($TargetSkuPartNumbers -join ", "))

if (-not $SkipConnect) {
    Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Connecting to Microsoft Graph" -CurrentStep 1 -TotalSteps $totalSteps
    $scopes = @(
        "User.Read.All",
        "User.ReadWrite.All",
        "Directory.Read.All"
    )
    Connect-MgGraph -Scopes $scopes -NoWelcome
    Write-LogEntry -LogPath $LogPath -Message "Connected to Microsoft Graph."
}
else {
    Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Skipping Graph connection (-SkipConnect)" -CurrentStep 1 -TotalSteps $totalSteps
    Write-LogEntry -LogPath $LogPath -Message "Skipped Graph connection due to -SkipConnect." -Level "WARN"
}

Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Loading subscribed SKU mapping" -CurrentStep 2 -TotalSteps $totalSteps
$skuIdToPartNumber = Get-SkuIdToPartNumberMap -ProgressId 3
Write-LogEntry -LogPath $LogPath -Message ("Loaded {0} subscribed SKUs." -f $skuIdToPartNumber.Count)

Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Loading users" -CurrentStep 3 -TotalSteps $totalSteps
$usersUri = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,passwordPolicies,assignedLicenses&`$top=999"
$allUsers = Get-GraphPagedResults -Uri $usersUri -ProgressId 4 -ProgressActivity "Loading users"
Write-LogEntry -LogPath $LogPath -Message ("Loaded {0} users from Graph." -f $allUsers.Count)

Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Filtering room accounts by target SKUs" -CurrentStep 4 -TotalSteps $totalSteps
$targetSkuLookup = @{}
foreach ($part in $TargetSkuPartNumbers) {
    $targetSkuLookup[$part.ToUpperInvariant()] = $true
}

$licensedRoomUsers = @()
foreach ($user in $allUsers) {
    $assignedPartNumbers = Get-AssignedSkuPartNumbersForUser -User $user -SkuIdToPartNumberMap $skuIdToPartNumber
    if (-not $assignedPartNumbers -or $assignedPartNumbers.Count -eq 0) {
        continue
    }

    $matchedSkuPartNumbers = @(
        foreach ($part in $assignedPartNumbers) {
            if ($targetSkuLookup.ContainsKey($part.ToUpperInvariant())) {
                $part
            }
        }
    )

    if (-not $matchedSkuPartNumbers -or $matchedSkuPartNumbers.Count -eq 0) {
        continue
    }

    $licensedRoomUsers += [PSCustomObject]@{
        User                  = $user
        MatchedSkuPartNumbers = ($matchedSkuPartNumbers | Sort-Object -Unique)
    }
}

Write-LogEntry -LogPath $LogPath -Message ("Matched {0} room accounts with target SKUs." -f $licensedRoomUsers.Count)

Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Checking and remediating password policies" -CurrentStep 5 -TotalSteps $totalSteps
$totalTargets = $licensedRoomUsers.Count
$checkedCount = 0
$alreadyCompliantCount = 0
$updatedCount = 0
$failedCount = 0
$simulatedCount = 0

for ($index = 0; $index -lt $totalTargets; $index++) {
    $entry = $licensedRoomUsers[$index]
    $user = $entry.User
    $checkedCount++

    $upn = if ([string]::IsNullOrWhiteSpace($user.userPrincipalName)) { "<no upn>" } else { $user.userPrincipalName }
    $displayName = if ([string]::IsNullOrWhiteSpace($user.displayName)) { "<no display name>" } else { $user.displayName }
    $percent = if ($totalTargets -gt 0) { [int](($checkedCount / $totalTargets) * 100) } else { 100 }

    Write-Progress -Id 2 -ParentId $mainProgressId -Activity "Account check in progress" -Status "Checking $checkedCount/$totalTargets - $upn" -PercentComplete $percent

    $evaluation = Get-UpdatedPasswordPolicies -CurrentPasswordPolicies $user.passwordPolicies -RequiredPolicy "DisablePasswordExpiration"

    if ($evaluation.AlreadyCompliant) {
        $alreadyCompliantCount++
        Write-LogEntry -LogPath $LogPath -Message ("Compliant: {0} ({1}) already has DisablePasswordExpiration. SKUs: {2}" -f $displayName, $upn, ($entry.MatchedSkuPartNumbers -join ", "))
        continue
    }

    $actionDescription = "Set password policy to never expire. New passwordPolicies value: $($evaluation.UpdatedValue)"
    if (-not $PSCmdlet.ShouldProcess($upn, $actionDescription)) {
        $simulatedCount++
        Write-LogEntry -LogPath $LogPath -Message ("WhatIf: Would update {0} ({1}) to '{2}'. SKUs: {3}" -f $displayName, $upn, $evaluation.UpdatedValue, ($entry.MatchedSkuPartNumbers -join ", "))
        continue
    }

    try {
        $patchUri = "https://graph.microsoft.com/v1.0/users/$($user.id)"
        $body = @{
            passwordPolicies = $evaluation.UpdatedValue
        } | ConvertTo-Json -Compress

        Invoke-MgGraphRequest -Method PATCH -Uri $patchUri -Body $body -ContentType "application/json"
        $updatedCount++
        Write-LogEntry -LogPath $LogPath -Message ("Updated: {0} ({1}) passwordPolicies changed to '{2}'. SKUs: {3}" -f $displayName, $upn, $evaluation.UpdatedValue, ($entry.MatchedSkuPartNumbers -join ", "))
    }
    catch {
        $failedCount++
        Write-LogEntry -LogPath $LogPath -Message ("Failed: {0} ({1}) - {2}" -f $displayName, $upn, $_.Exception.Message) -Level "ERROR"
    }
}

Write-Progress -Id 2 -Activity "Account check in progress" -Completed
Write-Progress -Id $mainProgressId -Activity $mainActivity -Completed

Write-LogEntry -LogPath $LogPath -Message ("Summary: Checked={0}, AlreadyCompliant={1}, Updated={2}, Failed={3}, Simulated={4}" -f $checkedCount, $alreadyCompliantCount, $updatedCount, $failedCount, $simulatedCount)
Write-LogEntry -LogPath $LogPath -Message "Script completed."

Write-Host "Completed room account password policy remediation."
Write-Host "Checked: $checkedCount"
Write-Host "Already compliant: $alreadyCompliantCount"
Write-Host "Updated: $updatedCount"
Write-Host "Failed: $failedCount"
Write-Host "Simulated (WhatIf): $simulatedCount"
Write-Host "Log file: $LogPath"
