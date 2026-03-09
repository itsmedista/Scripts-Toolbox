param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\Temp\TeamsRoomAccountInventory.csv",

    [Parameter(Mandatory = $false)]
    [array]$TargetLicenses = @(),

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

Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Preparing static target licenses" -CurrentStep 2 -TotalSteps $totalSteps
if (-not $TargetLicenses -or $TargetLicenses.Count -eq 0) {
    $TargetLicenses = Get-TeamsRoomLicenseDefinitions
}

$invalidTargetSkus = @(
    foreach ($license in $TargetLicenses) {
        $token = ConvertTo-NormalizedSkuToken -SkuId ([string]$license.Sku)
        if ($token.Length -ne 32) {
            [string]$license.Sku
        }
    }
)
if ($invalidTargetSkus.Count -gt 0) {
    Write-Warning ("One or more target SKU values are not 32-character GUID tokens after normalization: {0}" -f ($invalidTargetSkus -join ", "))
}

$targetLicenseLookup = Get-TargetLicenseLookup -LicenseDefinitions $TargetLicenses

Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Retrieving accounts with target licenses" -CurrentStep 3 -TotalSteps $totalSteps
$userProperties = @(
    "id",
    "displayName",
    "userPrincipalName",
    "passwordPolicies",
    "assignedLicenses",
    "signInActivity",
    "onPremisesExtensionAttributes"
)
$allUsers = Get-UsersWithTargetLicenses -LicenseDefinitions $TargetLicenses -UserProperties $userProperties -ProgressId 4 -ProgressActivity "Retrieving accounts with target licenses"

Write-StepProgress -Id $mainProgressId -Activity $mainActivity -Status "Building inventory rows" -CurrentStep 4 -TotalSteps $totalSteps
$outputRows = @()
$totalUsers = $allUsers.Count

for ($index = 0; $index -lt $totalUsers; $index++) {
    $user = $allUsers[$index]
    $currentUserNumber = $index + 1
    $userIdentifier = if ([string]::IsNullOrWhiteSpace($user.userPrincipalName)) { "<no upn>" } else { $user.userPrincipalName }
    $userPercent = if ($totalUsers -gt 0) { [int](($currentUserNumber / $totalUsers) * 100) } else { 100 }
    Write-Progress -Id 2 -ParentId $mainProgressId -Activity "Processing users" -Status "User $currentUserNumber/$totalUsers - $userIdentifier" -PercentComplete $userPercent

    $matchedLicenses = Get-MatchingTargetLicensesForUser -User $user -TargetLicenseLookup $targetLicenseLookup
    if (-not $matchedLicenses -or $matchedLicenses.Count -eq 0) {
        continue
    }

    $assignedLicenseNames = @($matchedLicenses | ForEach-Object { $_.Name } | Sort-Object -Unique)

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
