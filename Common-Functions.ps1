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

function Get-SkuIdToPartNumberMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$ProgressId = 10
    )

    $subscribedSkusUri = "https://graph.microsoft.com/v1.0/subscribedSkus?`$select=skuId,skuPartNumber"
    $subscribedSkus = Get-GraphPagedResults -Uri $subscribedSkusUri -ProgressId $ProgressId -ProgressActivity "Loading subscribed SKUs"

    $skuIdToPartNumber = @{}
    foreach ($sku in $subscribedSkus) {
        if ($sku.skuId) {
            $skuIdToPartNumber[[string]$sku.skuId] = [string]$sku.skuPartNumber
        }
    }

    return $skuIdToPartNumber
}

function Get-AssignedSkuPartNumbersForUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User,

        [Parameter(Mandatory = $true)]
        [hashtable]$SkuIdToPartNumberMap
    )

    $assignedPartNumbers = @()
    if (-not $User.assignedLicenses) {
        return $assignedPartNumbers
    }

    foreach ($lic in $User.assignedLicenses) {
        if (-not $lic.skuId) {
            continue
        }

        $skuId = [string]$lic.skuId
        if ($SkuIdToPartNumberMap.ContainsKey($skuId)) {
            $assignedPartNumbers += $SkuIdToPartNumberMap[$skuId]
        }
    }

    return ($assignedPartNumbers | Sort-Object -Unique)
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
