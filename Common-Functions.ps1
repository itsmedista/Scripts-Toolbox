Set-StrictMode -Version Latest

function Get-GraphPagedResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [int]$ProgressId = 1,

        [Parameter(Mandatory = $false)]
        [string]$ProgressActivity = "Calling Microsoft Graph",

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers = @{}
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri
    $page = 0

    while ($nextLink) {
        $page++
        Write-Progress -Id $ProgressId -Activity $ProgressActivity -Status "Retrieving page $page" -PercentComplete -1

        $response = if ($Headers.Count -gt 0) {
            Invoke-MgGraphRequest -Method GET -Uri $nextLink -Headers $Headers
        }
        else {
            Invoke-MgGraphRequest -Method GET -Uri $nextLink
        }

        if ($response.value) {
            foreach ($item in @($response.value)) {
                [void]$items.Add($item)
            }
        }
        $nextLink = $response.'@odata.nextLink'
    }

    Write-Progress -Id $ProgressId -Activity $ProgressActivity -Completed
    return @($items)
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

    foreach ($key in @($result.Keys)) {
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

    if (Test-Path -LiteralPath $Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw "Path exists but is not a directory: $Path"
        }
        return
    }

    New-Item -Path $Path -ItemType Directory -Force | Out-Null
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

function Assert-GraphConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredScopes = @()
    )

    $context = Get-MgContext
    if (-not $context) {
        throw "No active Microsoft Graph context found. Run Connect-MgGraph first or remove -SkipConnect."
    }

    if ($RequiredScopes -and $RequiredScopes.Count -gt 0) {
        $grantedScopes = @($context.Scopes)
        $missingScopes = @(
            foreach ($scope in $RequiredScopes) {
                if ($grantedScopes -inotcontains $scope) {
                    $scope
                }
            }
        )

        if ($missingScopes.Count -gt 0) {
            throw ("The active Microsoft Graph context is missing required scopes: {0}" -f ($missingScopes -join ", "))
        }
    }

    return $context
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
            Sku  = "4cde982a-ede4-4409-9ae6-b003453c8ea6"
            Name = "Microsoft Teams Rooms Pro"
        },
        [PSCustomObject]@{
            Sku  = "295a8eb0-f78d-45c7-8b5b-1eed5ed02dff"
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
        if ($token.Length -ne 32) {
            continue
        }

        if (-not $lookup.ContainsKey($token)) {
            $lookup[$token] = [PSCustomObject]@{
                Sku  = [string]$license.Sku
                Name = [string]$license.Name
            }
        }
    }

    if ($lookup.Count -eq 0) {
        throw "No valid target license definitions were provided. Provide GUID-like SKU values."
    }

    return $lookup
}

function ConvertTo-GraphGuidLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SkuToken
    )

    if ([string]::IsNullOrWhiteSpace($SkuToken) -or $SkuToken.Length -ne 32) {
        return ""
    }

    try {
        return ([Guid]::ParseExact($SkuToken, "N")).ToString()
    }
    catch {
        return ""
    }
}

function Get-MatchingTargetLicensesForUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User,

        [Parameter(Mandatory = $true)]
        [hashtable]$TargetLicenseLookup
    )

    $matchedLicenses = [System.Collections.Generic.List[object]]::new()
    if (-not $User.assignedLicenses) {
        return @()
    }

    foreach ($lic in $User.assignedLicenses) {
        if (-not $lic.skuId) {
            continue
        }

        $token = ConvertTo-NormalizedSkuToken -SkuId ([string]$lic.skuId)
        if ($TargetLicenseLookup.ContainsKey($token)) {
            [void]$matchedLicenses.Add($TargetLicenseLookup[$token])
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
            if ($token.Length -eq 32) {
                $token
            }
        }
    ) | Sort-Object -Unique

    if ($licenses.Count -eq 0) {
        throw "No valid target license tokens were provided."
    }

    $licenseGuids = @(
        foreach ($licenseToken in $licenses) {
            $guidLiteral = ConvertTo-GraphGuidLiteral -SkuToken $licenseToken
            if (-not [string]::IsNullOrWhiteSpace($guidLiteral)) {
                $guidLiteral
            }
        }
    ) | Sort-Object -Unique

    if ($licenseGuids.Count -eq 0) {
        throw "No valid GUID-formatted target license values were provided."
    }

    $filterClauses = @($licenseGuids | ForEach-Object { "assignedLicenses/any(x:x/skuId eq $_)" })
    $filterQuery = $filterClauses -join " or "
    $selectQuery = [System.Uri]::EscapeDataString(($UserProperties -join ","))
    $escapedFilter = [System.Uri]::EscapeDataString($filterQuery)
    $uri = "https://graph.microsoft.com/v1.0/users?`$count=true&`$select=$selectQuery&`$filter=$escapedFilter"
    $headers = @{
        ConsistencyLevel = "eventual"
    }

    try {
        $matchedUsers = Get-GraphPagedResults -Uri $uri -ProgressId $ProgressId -ProgressActivity $ProgressActivity -Headers $headers
    }
    catch {
        Write-Warning ("Server-side license filtering failed; falling back to client-side filtering. {0}" -f $_.Exception.Message)
        $licenseSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($licenseToken in $licenses) {
            [void]$licenseSet.Add($licenseToken)
        }

        Write-Progress -Id $ProgressId -Activity $ProgressActivity -Status "Loading users with Get-MgUser" -PercentComplete -1
        $users = Get-MgUser -All -Property $UserProperties

        Write-Progress -Id $ProgressId -Activity $ProgressActivity -Status "Filtering users by assigned license SKU" -PercentComplete -1
        $filteredUsers = [System.Collections.Generic.List[object]]::new()
        foreach ($user in @($users)) {
            if (-not $user.AssignedLicenses -or $user.AssignedLicenses.Count -eq 0) {
                continue
            }

            foreach ($assignedLicense in $user.AssignedLicenses) {
                $assignedToken = ConvertTo-NormalizedSkuToken -SkuId ([string]$assignedLicense.SkuId)
                if ($licenseSet.Contains($assignedToken)) {
                    [void]$filteredUsers.Add($user)
                    break
                }
            }
        }

        $matchedUsers = @($filteredUsers)
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
