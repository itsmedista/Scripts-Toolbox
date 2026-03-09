Set-StrictMode -Version Latest

function Get-GraphPagedResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [int]$ProgressId = 1,

        [Parameter(Mandatory = $false)]
        [string]$ProgressActivity = "Calling Microsoft Graph"
    )

    $items = @()
    $nextLink = $Uri
    $page = 0

    while ($nextLink) {
        $page++
        Write-Progress -Id $ProgressId -Activity $ProgressActivity -Status "Retrieving page $page" -PercentComplete -1

        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink
        if ($response.value) {
            $items += $response.value
        }
        $nextLink = $response.'@odata.nextLink'
    }

    Write-Progress -Id $ProgressId -Activity $ProgressActivity -Completed
    return $items
}

function Get-UserExtensionAttributes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $ExtensionObject
    )

    $result = [ordered]@{}
    1..15 | ForEach-Object {
        $key = "extensionAttribute$_"
        $result[$key] = $null
    }

    if (-not $ExtensionObject) {
        return $result
    }

    foreach ($key in $result.Keys) {
        if ($ExtensionObject.PSObject.Properties.Name -contains $key) {
            $result[$key] = $ExtensionObject.$key
        }
    }

    return $result
}

function Ensure-Directory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Write-StepProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Id = 0,

        [Parameter(Mandatory = $true)]
        [string]$Activity,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [int]$CurrentStep,

        [Parameter(Mandatory = $true)]
        [int]$TotalSteps
    )

    $percentComplete = 0
    if ($TotalSteps -gt 0) {
        $percentComplete = [Math]::Min([int](($CurrentStep / $TotalSteps) * 100), 100)
    }

    Write-Progress -Id $Id -Activity $Activity -Status $Status -PercentComplete $percentComplete
}

function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Get-TeamsRoomLicenseDefinitions {
    [CmdletBinding()]
    param()

    return @(
        [PSCustomObject]@{
            Sku  = "4cde982a-ede4-4409-9ae6b003453c8ea6"
            Name = "Microsoft Teams Rooms Pro"
        },
        [PSCustomObject]@{
            Sku  = "295a8eb0-f78d045c708b5b01eed5ed02dff"
            Name = "Microsoft Teams Shared Devices"
        }
    )
}

function ConvertTo-NormalizedSkuToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SkuId
    )

    if ([string]::IsNullOrWhiteSpace($SkuId)) {
        return ""
    }

    return (($SkuId.ToLowerInvariant()) -replace "[^a-f0-9]", "")
}

function Get-TargetLicenseLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$LicenseDefinitions
    )

    $lookup = @{}
    foreach ($license in $LicenseDefinitions) {
        if (-not $license.Sku) {
            continue
        }

        $token = ConvertTo-NormalizedSkuToken -SkuId ([string]$license.Sku)
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        $lookup[$token] = [PSCustomObject]@{
            Sku  = [string]$license.Sku
            Name = [string]$license.Name
        }
    }

    return $lookup
}

function Get-MatchingTargetLicensesForUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User,

        [Parameter(Mandatory = $true)]
        [hashtable]$TargetLicenseLookup
    )

    $matchedLicenses = @()
    if (-not $User.assignedLicenses) {
        return $matchedLicenses
    }

    foreach ($lic in $User.assignedLicenses) {
        if (-not $lic.skuId) {
            continue
        }

        $token = ConvertTo-NormalizedSkuToken -SkuId ([string]$lic.skuId)
        if ($TargetLicenseLookup.ContainsKey($token)) {
            $matchedLicenses += $TargetLicenseLookup[$token]
        }
    }

    return @($matchedLicenses | Sort-Object -Property Sku -Unique)
}

function Get-UsersWithTargetLicenses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$LicenseDefinitions,

        [Parameter(Mandatory = $true)]
        [string[]]$UserProperties,

        [Parameter(Mandatory = $false)]
        [int]$ProgressId = 20,

        [Parameter(Mandatory = $false)]
        [string]$ProgressActivity = "Retrieving users with target licenses"
    )

    $licenses = @(
        foreach ($license in $LicenseDefinitions) {
            $token = ConvertTo-NormalizedSkuToken -SkuId ([string]$license.Sku)
            if (-not [string]::IsNullOrWhiteSpace($token)) {
                $token
            }
        }
    ) | Sort-Object -Unique

    $licenseSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($licenseToken in $licenses) {
        [void]$licenseSet.Add($licenseToken)
    }

    Write-Progress -Id $ProgressId -Activity $ProgressActivity -Status "Loading users with Get-MgUser" -PercentComplete -1
    $users = Get-MgUser -All -Property $UserProperties

    Write-Progress -Id $ProgressId -Activity $ProgressActivity -Status "Filtering users by assigned license SKU" -PercentComplete -1
    $matchedUsers = $users | Where-Object {
        if (-not $_.AssignedLicenses -or $_.AssignedLicenses.Count -eq 0) {
            return $false
        }

        foreach ($assignedLicense in $_.AssignedLicenses) {
            $assignedToken = ConvertTo-NormalizedSkuToken -SkuId ([string]$assignedLicense.SkuId)
            if ($licenseSet.Contains($assignedToken)) {
                return $true
            }
        }

        return $false
    }

    Write-Progress -Id $ProgressId -Activity $ProgressActivity -Completed
    return @($matchedUsers)
}

function ConvertTo-PasswordPolicyList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$PasswordPolicies
    )

    if ([string]::IsNullOrWhiteSpace($PasswordPolicies)) {
        return @()
    }

    return @(
        $PasswordPolicies.Split(",") |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                (-not [string]::IsNullOrWhiteSpace($_)) -and
                ($_ -ine "None")
            }
    )
}

function Get-UpdatedPasswordPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CurrentPasswordPolicies,

        [Parameter(Mandatory = $false)]
        [string]$RequiredPolicy = "DisablePasswordExpiration"
    )

    $policies = ConvertTo-PasswordPolicyList -PasswordPolicies $CurrentPasswordPolicies
    $hasPolicy = $false

    foreach ($policy in $policies) {
        if ($policy -ieq $RequiredPolicy) {
            $hasPolicy = $true
            break
        }
    }

    if (-not $hasPolicy) {
        $policies += $RequiredPolicy
    }

    $normalizedPolicies = @($policies | Sort-Object -Unique)
    $updatedValue = $normalizedPolicies -join ", "

    [PSCustomObject]@{
        AlreadyCompliant = $hasPolicy
        UpdatedValue     = $updatedValue
    }
}
