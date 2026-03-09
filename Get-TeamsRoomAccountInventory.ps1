param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\Temp\TeamsRoomAccountInventory.csv",

    [Parameter(Mandatory = $false)]
    [string[]]$TargetSkuPartNumbers = @(
        "MICROSOFT_TEAMS_ROOMS_PRO",   # Alternate Teams Rooms Pro part number
        "MCOCAP"                       # Alternate Teams Shared Device part number
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

$mainProgressId = 0
$mainActivity = "Teams Rooms account inventory"
$totalSteps = 5

if (-not $SkipConnect) {
    Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Connecting to Microsoft Graph" -CurrentStep 1 -TotalSteps $totalSteps
    $scopes = @(
        "User.Read.All",
        "Directory.Read.All",
        "AuditLog.Read.All"
    )
    Connect-MgGraph -Scopes $scopes -NoWelcome
}
else {
    Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Skipping Graph connection (-SkipConnect)" -CurrentStep 1 -TotalSteps $totalSteps
}

# Subscribed SKUs in the tenant for mapping SkuId -> SkuPartNumber
Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Loading subscribed SKU map" -CurrentStep 2 -TotalSteps $totalSteps
$subscribedSkusUri = "https://graph.microsoft.com/v1.0/subscribedSkus?`$select=skuId,skuPartNumber"
$subscribedSkus = Get-GraphPagedResults -Uri $subscribedSkusUri -ProgressId 3 -ProgressActivity "Loading subscribed SKUs"

$skuIdToPartNumber = @{}
foreach ($sku in $subscribedSkus) {
    if ($sku.skuId) {
        $skuIdToPartNumber[[string]$sku.skuId] = [string]$sku.skuPartNumber
    }
}

$friendlyLicenseNames = @{
    "MICROSOFT_TEAMS_ROOMS_PRO" = "Microsoft Teams Rooms Pro"
    "MCOCAP"                    = "Microsoft Teams Shared Device"
}

$targetSkuLookup = @{}
foreach ($part in $TargetSkuPartNumbers) {
    $targetSkuLookup[$part.ToUpperInvariant()] = $true
}

# Use beta for signInActivity + lastNonInteractiveSignInDateTime
Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Loading users from Microsoft Graph (beta)" -CurrentStep 3 -TotalSteps $totalSteps
$usersUri = "https://graph.microsoft.com/beta/users?`$select=id,displayName,userPrincipalName,passwordPolicies,assignedLicenses,signInActivity,onPremisesExtensionAttributes&`$top=999"
$allUsers = Get-GraphPagedResults -Uri $usersUri -ProgressId 4 -ProgressActivity "Loading users"

Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Filtering and building inventory rows" -CurrentStep 4 -TotalSteps $totalSteps
$outputRows = @()
$totalUsers = $allUsers.Count

for ($index = 0; $index -lt $totalUsers; $index++) {
    $user = $allUsers[$index]
    $currentUserNumber = $index + 1
    $userIdentifier = if ([string]::IsNullOrWhiteSpace($user.userPrincipalName)) { "<no upn>" } else { $user.userPrincipalName }
    $userPercent = if ($totalUsers -gt 0) { [int](($currentUserNumber / $totalUsers) * 100) } else { 100 }
    Write-Progress -Id 2 -ParentId $mainProgressId -Activity "Processing users" -Status "User $currentUserNumber/$totalUsers - $userIdentifier" -PercentComplete $userPercent

    $assignedPartNumbers = @()
    if ($user.assignedLicenses) {
        foreach ($lic in $user.assignedLicenses) {
            if (-not $lic.skuId) { continue }
            $skuId = [string]$lic.skuId
            if ($skuIdToPartNumber.ContainsKey($skuId)) {
                $assignedPartNumbers += $skuIdToPartNumber[$skuId]
            }
        }
    }

    $assignedPartNumbers = $assignedPartNumbers | Sort-Object -Unique

    $matchedTargetParts = @(
        foreach ($part in $assignedPartNumbers) {
            if ($targetSkuLookup.ContainsKey($part.ToUpperInvariant())) {
                $part
            }
        }
    )

    if (-not $matchedTargetParts -or $matchedTargetParts.Count -eq 0) {
        continue
    }

    $assignedLicenseNames = foreach ($part in $assignedPartNumbers) {
        $partKey = $part.ToUpperInvariant()
        if ($friendlyLicenseNames.ContainsKey($partKey)) {
            $friendlyLicenseNames[$partKey]
        }
        else {
            $part
        }
    }

    $ext = Get-UserExtensionAttributes -ExtensionObject $user.onPremisesExtensionAttributes

    $outputRows += [PSCustomObject]@{
        AccountName                      = $user.displayName
        UPN                              = $user.userPrincipalName
        LastNonInteractiveSignInDateTime = $user.signInActivity.lastNonInteractiveSignInDateTime
        AssignedLicenseName              = ($assignedLicenseNames -join "; ")
        PasswordPolicies                 = $user.passwordPolicies
        ExtensionAttribute1              = $ext.extensionAttribute1
        ExtensionAttribute2              = $ext.extensionAttribute2
        ExtensionAttribute3              = $ext.extensionAttribute3
        ExtensionAttribute4              = $ext.extensionAttribute4
        ExtensionAttribute5              = $ext.extensionAttribute5
        ExtensionAttribute6              = $ext.extensionAttribute6
        ExtensionAttribute7              = $ext.extensionAttribute7
        ExtensionAttribute8              = $ext.extensionAttribute8
        ExtensionAttribute9              = $ext.extensionAttribute9
        ExtensionAttribute10             = $ext.extensionAttribute10
        ExtensionAttribute11             = $ext.extensionAttribute11
        ExtensionAttribute12             = $ext.extensionAttribute12
        ExtensionAttribute13             = $ext.extensionAttribute13
        ExtensionAttribute14             = $ext.extensionAttribute14
        ExtensionAttribute15             = $ext.extensionAttribute15
    }
}
Write-Progress -Id 2 -Activity "Processing users" -Completed

$outputDirectory = Split-Path -Path $OutputPath -Parent
Ensure-Directory -Path $outputDirectory

Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Exporting CSV to $OutputPath" -CurrentStep 5 -TotalSteps $totalSteps
$outputRows |
    Sort-Object AccountName |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Progress -Id $mainProgressId -Activity $mainActivity -Completed
Write-Host "Export complete: $OutputPath"
Write-Host "Rows exported: $($outputRows.Count)"
