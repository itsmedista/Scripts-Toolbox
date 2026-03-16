<#
.SYNOPSIS
    SCCM Migration Audit - Applications, Packages, Task Sequences, Baselines
.DESCRIPTION
    Connects to the SCCM site server and exports all Applications, Packages,
    Task Sequences, and Configuration Baselines to a formatted HTML report.
.PARAMETER SiteServer
    FQDN or hostname of your SCCM Site Server
.PARAMETER SiteCode
    Your SCCM 3-character Site Code (e.g. "PS1")
.PARAMETER OutputPath
    Folder path where the HTML report will be saved
.EXAMPLE
    .\SCCM-MigrationAudit.ps1 -SiteServer "SCCM01.contoso.com" -SiteCode "PS1" -OutputPath "C:\AuditReports"
#>

param(
    [Parameter(Mandatory)]
    [string]$SiteServer,

    [Parameter(Mandatory)]
    [string]$SiteCode,

    [string]$OutputPath = "$env:USERPROFILE\Desktop"
)

#region --- SETUP ---
$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$reportFile = Join-Path $OutputPath "SCCM_Audit_$timestamp.html"

# Import the ConfigurationManager module (must be run from a machine with SCCM console installed)
if (-not (Get-Module ConfigurationManager)) {
    try {
        Import-Module "$env:SMS_ADMIN_UI_PATH\..\ConfigurationManager.psd1" -ErrorAction Stop
    } catch {
        Write-Error "Failed to import ConfigurationManager module. Ensure the SCCM console is installed on this machine."
        exit 1
    }
}

# Connect to the site
$originalLocation = Get-Location
if (-not (Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer | Out-Null
}
Set-Location "$SiteCode`:\"
#endregion

#region --- DATA COLLECTION ---
Write-Host "Collecting Applications..." -ForegroundColor Cyan
$applications = Get-CMApplication | Select-Object LocalizedDisplayName, Manufacturer, SoftwareVersion,
    NumberOfDeploymentTypes, IsDeployed, IsEnabled, DateCreated, DateLastModified,
    CreatedBy, LastModifiedBy, LocalizedDescription |
    Sort-Object LocalizedDisplayName

Write-Host "Collecting Packages..." -ForegroundColor Cyan
$packages = Get-CMPackage | Select-Object Name, Manufacturer, Version, Language,
    PackageType, PkgSourcePath, HasContent, PackageID,
    DateCreated, LastRefreshTime |
    Sort-Object Name

Write-Host "Collecting Task Sequences..." -ForegroundColor Cyan
$taskSequences = Get-CMTaskSequence | Select-Object Name, PackageID, Enabled,
    BootImageID, Category, Description,
    @{N="DeploymentCount"; E={ (Get-CMTaskSequenceDeployment -TaskSequenceId $_.PackageID -ErrorAction SilentlyContinue | Measure-Object).Count }} |
    Sort-Object Name

Write-Host "Collecting Configuration Baselines..." -ForegroundColor Cyan
$baselines = Get-CMBaseline | Select-Object LocalizedDisplayName, IsAssigned,
    IsEnabled, IsDeployed, AssignedCI_UniqueID,
    @{N="DeploymentCount"; E={ (Get-CMBaselineDeployment -BaselineId $_.CI_ID -ErrorAction SilentlyContinue | Measure-Object).Count }},
    DateCreated, DateLastModified, CreatedBy, LastModifiedBy |
    Sort-Object LocalizedDisplayName
#endregion

#region --- RESTORE LOCATION ---
Set-Location $originalLocation
#endregion

#region --- HTML REPORT GENERATION ---
function New-HtmlTable {
    param([object[]]$Data, [string]$EmptyMessage = "No items found.")

    if (-not $Data -or $Data.Count -eq 0) {
        return "<p class='empty'>$EmptyMessage</p>"
    }

    $headers = ($Data[0].PSObject.Properties.Name | ForEach-Object { "<th>$_</th>" }) -join ""
    $rows = $Data | ForEach-Object {
        $obj = $_
        $cells = $obj.PSObject.Properties.Value | ForEach-Object {
            $val = if ($null -eq $_) { "" } else { [System.Web.HttpUtility]::HtmlEncode($_) }
            "<td>$val</td>"
        }
        "<tr>$($cells -join '')</tr>"
    }
    return "<table><thead><tr>$headers</tr></thead><tbody>$($rows -join '')</tbody></table>"
}

$summaryRows = @(
    @{ Category = "Applications";           Count = $applications.Count;  Icon = "📦" }
    @{ Category = "Packages";               Count = $packages.Count;      Icon = "🗂️" }
    @{ Category = "Task Sequences";         Count = $taskSequences.Count; Icon = "⚙️" }
    @{ Category = "Configuration Baselines";Count = $baselines.Count;     Icon = "🛡️" }
)
$totalItems = ($summaryRows | Measure-Object -Property Count -Sum).Sum

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>SCCM Migration Audit Report</title>
<style>
  :root {
    --blue-dark: #1F3864;
    --blue-mid:  #2E75B6;
    --blue-light:#D6E4F0;
    --accent:    #BDD7EE;
    --gray:      #f5f7fa;
    --border:    #d0d7e3;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: Arial, sans-serif; font-size: 13px; color: #222; background: #f0f4f8; }

  /* Header */
  .report-header { background: var(--blue-dark); color: white; padding: 32px 40px; }
  .report-header h1 { font-size: 26px; font-weight: bold; letter-spacing: 1px; }
  .report-header .meta { margin-top: 8px; font-size: 12px; color: var(--accent); }

  /* Summary cards */
  .summary { display: flex; gap: 16px; padding: 24px 40px; background: white;
             border-bottom: 2px solid var(--blue-light); flex-wrap: wrap; }
  .card { flex: 1; min-width: 160px; background: var(--blue-light);
          border-left: 5px solid var(--blue-mid); border-radius: 6px;
          padding: 16px 20px; }
  .card .icon { font-size: 22px; }
  .card .count { font-size: 32px; font-weight: bold; color: var(--blue-dark); line-height: 1; margin: 4px 0; }
  .card .label { font-size: 12px; color: #555; }
  .card.total { background: var(--blue-dark); border-left-color: var(--blue-mid); }
  .card.total .count, .card.total .label { color: white; }

  /* Nav tabs */
  .tabs { display: flex; background: white; padding: 0 40px;
          border-bottom: 3px solid var(--blue-mid); gap: 4px; }
  .tab { padding: 12px 24px; cursor: pointer; font-weight: bold; font-size: 13px;
         color: #555; border-bottom: 3px solid transparent; margin-bottom: -3px; transition: all 0.2s; }
  .tab:hover { color: var(--blue-mid); }
  .tab.active { color: var(--blue-dark); border-bottom-color: var(--blue-dark); }

  /* Content */
  .content { padding: 24px 40px; }
  .section { display: none; }
  .section.active { display: block; }
  .section-title { font-size: 18px; font-weight: bold; color: var(--blue-dark);
                   margin-bottom: 16px; padding-bottom: 8px;
                   border-bottom: 2px solid var(--blue-light); }

  /* Table */
  table { width: 100%; border-collapse: collapse; font-size: 12px;
          background: white; border-radius: 6px; overflow: hidden;
          box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
  thead tr { background: var(--blue-dark); color: white; }
  th { padding: 10px 12px; text-align: left; font-size: 11px;
       letter-spacing: 0.5px; white-space: nowrap; }
  td { padding: 9px 12px; border-bottom: 1px solid var(--border); vertical-align: top; }
  tbody tr:nth-child(even) { background: var(--gray); }
  tbody tr:hover { background: var(--accent); }

  /* Search */
  .search-bar { margin-bottom: 14px; }
  .search-bar input { width: 320px; padding: 8px 14px; border: 1px solid var(--border);
                      border-radius: 4px; font-size: 13px; }

  .empty { color: #888; font-style: italic; padding: 20px; }
  .footer { text-align: center; padding: 20px; color: #999; font-size: 11px; }
</style>
</head>
<body>

<div class="report-header">
  <h1>SCCM Migration Audit Report</h1>
  <div class="meta">
    Site Server: $SiteServer &nbsp;|&nbsp; Site Code: $SiteCode &nbsp;|&nbsp;
    Generated: $(Get-Date -Format "dddd, MMMM dd yyyy HH:mm")
  </div>
</div>

<div class="summary">
  $(foreach ($s in $summaryRows) {
    "<div class='card'><div class='icon'>$($s.Icon)</div><div class='count'>$($s.Count)</div><div class='label'>$($s.Category)</div></div>"
  })
  <div class='card total'><div class='icon'>📊</div><div class='count'>$totalItems</div><div class='label'>Total Items</div></div>
</div>

<div class="tabs">
  <div class="tab active" onclick="showTab('apps', this)">📦 Applications ($($applications.Count))</div>
  <div class="tab" onclick="showTab('pkgs', this)">🗂️ Packages ($($packages.Count))</div>
  <div class="tab" onclick="showTab('ts', this)">⚙️ Task Sequences ($($taskSequences.Count))</div>
  <div class="tab" onclick="showTab('bl', this)">🛡️ Baselines ($($baselines.Count))</div>
</div>

<div class="content">

  <div id="apps" class="section active">
    <div class="section-title">Applications</div>
    <div class="search-bar"><input type="text" placeholder="Filter applications..." oninput="filterTable(this, 'apps-table')"></div>
    $(New-HtmlTable -Data $applications -EmptyMessage "No applications found.")
  </div>

  <div id="pkgs" class="section">
    <div class="section-title">Packages</div>
    <div class="search-bar"><input type="text" placeholder="Filter packages..." oninput="filterTable(this, 'pkgs-table')"></div>
    $(New-HtmlTable -Data $packages -EmptyMessage "No packages found.")
  </div>

  <div id="ts" class="section">
    <div class="section-title">Task Sequences</div>
    <div class="search-bar"><input type="text" placeholder="Filter task sequences..." oninput="filterTable(this, 'ts-table')"></div>
    $(New-HtmlTable -Data $taskSequences -EmptyMessage "No task sequences found.")
  </div>

  <div id="bl" class="section">
    <div class="section-title">Configuration Baselines</div>
    <div class="search-bar"><input type="text" placeholder="Filter baselines..." oninput="filterTable(this, 'bl-table')"></div>
    $(New-HtmlTable -Data $baselines -EmptyMessage "No baselines found.")
  </div>

</div>

<div class="footer">SCCM Migration Audit &bull; Generated by SCCM-MigrationAudit.ps1 &bull; $(Get-Date -Format "yyyy")</div>

<script>
  // Assign IDs to tables after render
  document.querySelectorAll('.section table').forEach((t, i) => {
    const ids = ['apps-table','pkgs-table','ts-table','bl-table'];
    t.id = ids[i];
  });

  function showTab(id, el) {
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.getElementById(id).classList.add('active');
    el.classList.add('active');
  }

  function filterTable(input, tableId) {
    const filter = input.value.toLowerCase();
    const rows = document.getElementById(tableId)?.querySelectorAll('tbody tr') || [];
    rows.forEach(row => {
      row.style.display = row.textContent.toLowerCase().includes(filter) ? '' : 'none';
    });
  }
</script>
</body>
</html>
"@

Add-Type -AssemblyName System.Web
$html | Out-File -FilePath $reportFile -Encoding UTF8
#endregion

Write-Host "`n✅ Audit complete!" -ForegroundColor Green
Write-Host "   Applications  : $($applications.Count)" -ForegroundColor White
Write-Host "   Packages      : $($packages.Count)" -ForegroundColor White
Write-Host "   Task Sequences: $($taskSequences.Count)" -ForegroundColor White
Write-Host "   Baselines     : $($baselines.Count)" -ForegroundColor White
Write-Host "`n📄 Report saved to: $reportFile" -ForegroundColor Yellow
Start-Process $reportFile