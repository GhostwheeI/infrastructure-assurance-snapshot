<#
.SYNOPSIS
    Generates a read-only Infrastructure Assurance Snapshot report.

.DESCRIPTION
    Dependency-first mock prototype for SCCM + SolarWinds infrastructure assurance.
    Console output is intentionally structured for short walkthroughs: clear sections, grouped warnings, and minimal noise.
#>

[CmdletBinding()]
param(
    [switch]$MockData,
    [ValidateSet('Default','PatchOnly','Tier1Only','IdentityAndRecoveryPreview')]
    [string]$MockScope = 'Default',
    [string]$OutputPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'InfrastructureAssuranceSnapshot'),
    [switch]$MockDependencyInstall,
    [switch]$StrictDependencies,
    [ValidateRange(0,5)]
    [int]$DemoPaceSeconds = 0,
    [ValidateSet('Ask','Yes','No')]
    [string]$OpenOutputFolder = 'Ask'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Run = [ordered]@{
    OutputPath         = $null
    LogPath            = $null
    DependencyPlanPath = $null
    DemoPaceSeconds    = $DemoPaceSeconds
}

function Initialize-Run {
    param([Parameter(Mandatory)][string]$BasePath)

    $runPath = Join-Path $BasePath ('Run-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $runPath -Force | Out-Null

    $script:Run.OutputPath = (Resolve-Path -LiteralPath $runPath).Path
    $script:Run.LogPath = Join-Path $script:Run.OutputPath 'Infrastructure-Assurance.log'
    $script:Run.DependencyPlanPath = Join-Path $script:Run.OutputPath 'Dependency-Plan.txt'

    @(
        'Infrastructure Assurance Snapshot log'
        "Started: $((Get-Date).ToString('o'))"
        "OutputPath: $($script:Run.OutputPath)"
        "MockScope: $MockScope"
        "DemoPaceSeconds: $DemoPaceSeconds"
        ''
    ) | Set-Content -Path $script:Run.LogPath -Encoding UTF8
}

function Write-LogOnly {
    param([string]$Message,[string]$Level='INFO')
    Add-Content -Path $script:Run.LogPath -Encoding UTF8 -Value ('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message)
}

function Write-Section {
    param([string]$Title,[string]$Subtitle)
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    if ($Subtitle) { Write-Host "  $Subtitle" -ForegroundColor DarkGray }
    Write-LogOnly $Title 'STEP'
}

function Write-StatusLine {
    param(
        [ValidateSet('OK','WARN','SKIP','INFO','PLAN','ERROR')]
        [string]$Status,
        [string]$Name,
        [string]$Detail
    )

    $label = switch ($Status) {
        'OK'    { '[OK]  ' }
        'WARN'  { '[WARN]' }
        'SKIP'  { '[SKIP]' }
        'PLAN'  { '[PLAN]' }
        'ERROR' { '[FAIL]' }
        default { '[INFO]' }
    }

    $color = switch ($Status) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'SKIP'  { 'DarkGray' }
        'PLAN'  { 'DarkCyan' }
        'ERROR' { 'Red' }
        default { 'White' }
    }

    $line = "  $label $Name"
    if ($Detail) { $line += " - $Detail" }
    Write-Host $line -ForegroundColor $color
    Write-LogOnly "$Status | $Name | $Detail" $Status
}

function Start-DemoPace {
    if ($script:Run.DemoPaceSeconds -gt 0) { Start-Sleep -Seconds $script:Run.DemoPaceSeconds }
}

function Get-DependencyManifest {
    @(
        [pscustomobject]@{Name='PowerShell Runtime';Required=$true;Type='Runtime';Check='PowerShellVersion';Minimum='5.1';Purpose='Runs the prototype';Plan='Use Windows PowerShell 5.1+ or approved PowerShell 7 deployment'}
        [pscustomobject]@{Name='JSON Serialization';Required=$true;Type='Command';Check='ConvertTo-Json';Minimum=$null;Purpose='Writes JSON evidence';Plan='Built into supported PowerShell'}
        [pscustomobject]@{Name='CSV Export';Required=$true;Type='Command';Check='Export-Csv';Minimum=$null;Purpose='Writes CSV work queue';Plan='Built into supported PowerShell'}
        [pscustomobject]@{Name='SCCM / MECM Module';Required=$false;Type='Module';Check='ConfigurationManager';Minimum=$null;Purpose='Future SCCM read-only integration';Plan='Use approved SCCM Admin Console source'}
        [pscustomobject]@{Name='SolarWinds SWIS Module';Required=$false;Type='Module';Check='SwisPowerShell';Minimum=$null;Purpose='Future SolarWinds read-only integration';Plan='Use approved internal package source'}
        [pscustomobject]@{Name='Microsoft Graph Auth';Required=$false;Type='Module';Check='Microsoft.Graph.Authentication';Minimum=$null;Purpose='Future Entra ID read-only integration';Plan='Use approved internal package source'}
    )
}

function Test-Dependency {
    param([pscustomobject]$Dependency)

    $found = $false
    $details = ''

    if ($Dependency.Type -eq 'Runtime') {
        $found = ($PSVersionTable.PSVersion -ge [version]$Dependency.Minimum)
        $details = "PowerShell $($PSVersionTable.PSVersion)"
    }
    elseif ($Dependency.Type -eq 'Command') {
        $found = $null -ne (Get-Command $Dependency.Check -ErrorAction SilentlyContinue)
        $details = if ($found) { 'available' } else { "missing command: $($Dependency.Check)" }
    }
    elseif ($Dependency.Type -eq 'Module') {
        $module = Get-Module -ListAvailable -Name $Dependency.Check | Select-Object -First 1
        $found = $null -ne $module
        $details = if ($found) { "available: $($module.Name)" } else { "not installed; optional for mock run" }
    }

    [pscustomobject]@{
        Name     = $Dependency.Name
        Required = [bool]$Dependency.Required
        Found    = [bool]$found
        Purpose  = $Dependency.Purpose
        Details  = $details
        Plan     = $Dependency.Plan
    }
}

function Write-DependencyPlanFile {
    param([array]$MissingOptional)

    if ($MissingOptional.Count -eq 0) { return }

    $lines = @(
        'Dependency install/import plan',
        'Policy: Auto-install is denied by default. These are mock plans only.',
        'Action: No download, install, import, or system change was performed.',
        ''
    )

    foreach ($item in $MissingOptional) {
        $lines += @(
            "Dependency: $($item.Name)",
            "Purpose:    $($item.Purpose)",
            "Plan:       $($item.Plan)",
            ''
        )
    }

    $lines | Set-Content -Path $script:Run.DependencyPlanPath -Encoding UTF8
}

function Invoke-DependencyPreflight {
    param([switch]$MockInstall,[switch]$Strict)

    Write-Section '[1/5] Dependency preflight' 'Grouped checks; optional integrations are not required for mock mode.'
    Write-Host '  Policy: auto-install = denied by default; continue safely on missing optional tools.' -ForegroundColor DarkGray

    $results = foreach ($dependency in Get-DependencyManifest) { Test-Dependency $dependency }
    $required = @($results | Where-Object Required)
    $optional = @($results | Where-Object { -not $_.Required })
    $missingOptional = @($optional | Where-Object { -not $_.Found })
    $missingRequired = @($required | Where-Object { -not $_.Found })

    Write-Host ''
    Write-Host '  Required runtime' -ForegroundColor White
    foreach ($item in $required) {
        Write-StatusLine -Status $(if ($item.Found) {'OK'} else {'ERROR'}) -Name $item.Name -Detail $item.Details
    }

    Write-Host ''
    Write-Host '  Optional future integrations' -ForegroundColor White
    foreach ($item in $optional) {
        Write-StatusLine -Status $(if ($item.Found) {'OK'} else {'SKIP'}) -Name $item.Name -Detail $item.Details
    }

    if ($missingOptional.Count -gt 0) {
        Write-Host ''
        Write-StatusLine -Status 'WARN' -Name 'Optional integrations skipped' -Detail 'mock data run continues without SCCM/SolarWinds/Graph modules'
    }

    if ($MockInstall -and $missingOptional.Count -gt 0) {
        Write-DependencyPlanFile -MissingOptional $missingOptional
        Write-StatusLine -Status 'PLAN' -Name 'Mock dependency plan' -Detail $script:Run.DependencyPlanPath
    }

    if ($missingRequired.Count -gt 0) {
        throw "Blocking dependencies missing: $($missingRequired.Name -join ', ')"
    }

    if ($Strict) {
        $strictMissing = @($results | Where-Object { -not $_.Found })
        if ($strictMissing.Count -gt 0) { throw "Strict mode missing dependencies: $($strictMissing.Name -join ', ')" }
    }

    Start-DemoPace
    $results
}

function Get-MockScopeConfiguration {
    param([string]$Scope)

    $config = [ordered]@{
        ScopeName     = $Scope
        DataMode      = 'Mock only'
        InstallPolicy = 'Auto-install denied by default'
        Output        = @('HTML report','CSV work queue','JSON evidence','run log')
    }

    switch ($Scope) {
        'PatchOnly' {
            $config.Description = 'Patch, reboot, SCCM compliance, deployment state, and SolarWinds evidence only'
            $config.SccmCollections = @('Windows Servers - Patch Review','Servers Pending Reboot')
            $config.SolarWindsQueues = @('Infrastructure Change Queue','Patch Remediation Queue')
            $config.ReportSections = @('Patch/Reboot Risk','Evidence Gaps','Recommended Actions')
        }
        'Tier1Only' {
            $config.Description = 'Focused Tier 1 review for leadership-sensitive systems'
            $config.SccmCollections = @('Domain Controllers - Patch Validation','Tier 1 Application Servers','Critical SQL Servers')
            $config.SolarWindsQueues = @('Infrastructure Change Queue','Application/Data Change Queue')
            $config.ReportSections = @('Critical System Risk','Pending Reboots','Exceptions')
        }
        'IdentityAndRecoveryPreview' {
            $config.Description = 'Preview of identity hygiene and recovery evidence joining later'
            $config.SccmCollections = @('Windows Servers - Production')
            $config.SolarWindsQueues = @('Infrastructure Change Queue','Identity Request Queue','Backup Validation Queue')
            $config.ReportSections = @('Patch/Reboot Risk','Identity Placeholder','Recovery Placeholder')
        }
        default {
            $config.Description = 'Default scoped review for a balanced infrastructure assurance snapshot'
            $config.SccmCollections = @('Windows Servers - Production','Domain Controllers - Patch Validation','Tier 1 Application Servers')
            $config.SolarWindsQueues = @('Infrastructure Change Queue','Application/Data Change Queue','Incident Follow-up Queue')
            $config.ReportSections = @('Patch/Reboot Risk','SCCM Deployment State','SolarWinds Evidence','Exceptions','Recommended Actions')
        }
    }

    [pscustomobject]$config
}

function Show-MockScopeConfiguration {
    param([pscustomobject]$Config)

    Write-Section '[2/5] Scoped mock targeting' 'Shows what would be configurable in a real environment.'
    Write-Host '  This is intentionally scoped; it is not targeting an entire inventory.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  mock_targeting:' -ForegroundColor White
    Write-Host "    scope_name: $($Config.ScopeName)" -ForegroundColor White
    Write-Host "    data_mode: $($Config.DataMode)" -ForegroundColor White
    Write-Host "    install_policy: $($Config.InstallPolicy)" -ForegroundColor White
    Write-Host '    sccm_collections:' -ForegroundColor White
    foreach ($item in $Config.SccmCollections) { Write-Host "      - $item" -ForegroundColor White }
    Write-Host '    solarwinds_queues:' -ForegroundColor White
    foreach ($item in $Config.SolarWindsQueues) { Write-Host "      - $item" -ForegroundColor White }
    Write-Host '    report_sections:' -ForegroundColor White
    foreach ($item in $Config.ReportSections) { Write-Host "      - $item" -ForegroundColor White }

    Write-LogOnly "Mock scope: $($Config.ScopeName) | $($Config.Description)" 'INFO'
    Start-DemoPace
}

function Get-RiskLevel {
    param([string]$SccmCompliance,[string]$DeploymentState,[int]$DaysSincePatch,[bool]$PendingReboot,[string]$Criticality,[int]$KnownExploitedVulns,[string]$ExceptionStatus)

    $score = 0
    if ($SccmCompliance -ne 'Compliant') { $score += 25 }
    if ($DeploymentState -in @('Failed','Unknown')) { $score += 20 }
    if ($DaysSincePatch -ge 45) { $score += 30 } elseif ($DaysSincePatch -ge 30) { $score += 20 } elseif ($DaysSincePatch -ge 15) { $score += 10 }
    if ($PendingReboot) { $score += 15 }
    if ($Criticality -eq 'Tier 1') { $score += 15 } elseif ($Criticality -eq 'Tier 2') { $score += 8 }
    if ($KnownExploitedVulns -gt 0) { $score += 35 }
    if ($ExceptionStatus -match 'Exception') { $score -= 10 }

    if ($score -ge 70) { 'Critical' } elseif ($score -ge 45) { 'High' } elseif ($score -ge 20) { 'Medium' } else { 'Low' }
}

function Get-MockRows {
    param([string]$Scope)

    $rows = @(
        @{ServerName='OAG-DC01';Owner='Infrastructure';Criticality='Tier 1';SCCMCompliance='Compliant';DeploymentState='Success';DaysSincePatch=9;PendingReboot=$false;KnownExploitedVulns=0;SolarWindsRecord='CHG-10482';ExceptionStatus='None';RecommendedAction='No immediate action. Maintain normal cadence.'}
        @{ServerName='OAG-FS02';Owner='End User Services';Criticality='Tier 1';SCCMCompliance='NonCompliant';DeploymentState='Success';DaysSincePatch=38;PendingReboot=$true;KnownExploitedVulns=1;SolarWindsRecord='CHG-10511';ExceptionStatus='None';RecommendedAction='Prioritize remediation; reboot pending after approved patch window.'}
        @{ServerName='OAG-APP07';Owner='Application/Data';Criticality='Tier 2';SCCMCompliance='Compliant';DeploymentState='Success';DaysSincePatch=22;PendingReboot=$false;KnownExploitedVulns=0;SolarWindsRecord='INC-88412';ExceptionStatus='None';RecommendedAction='Patch in next scheduled maintenance cycle.'}
        @{ServerName='OAG-SQL03';Owner='Application/Data';Criticality='Tier 1';SCCMCompliance='NonCompliant';DeploymentState='Failed';DaysSincePatch=51;PendingReboot=$true;KnownExploitedVulns=2;SolarWindsRecord='CHG-10526';ExceptionStatus='Approved Exception';RecommendedAction='Leadership review required. High-risk exception should have compensating controls.'}
        @{ServerName='OAG-PRINT01';Owner='Infrastructure';Criticality='Tier 3';SCCMCompliance='Compliant';DeploymentState='Success';DaysSincePatch=17;PendingReboot=$false;KnownExploitedVulns=0;SolarWindsRecord='CHG-10477';ExceptionStatus='None';RecommendedAction='Continue standard remediation cadence.'}
        @{ServerName='OAG-MGMT01';Owner='Infrastructure';Criticality='Tier 2';SCCMCompliance='Compliant';DeploymentState='Success';DaysSincePatch=5;PendingReboot=$false;KnownExploitedVulns=0;SolarWindsRecord='CHG-10518';ExceptionStatus='None';RecommendedAction='No immediate action.'}
    )

    if ($Scope -eq 'Tier1Only') { $rows = @($rows | Where-Object { $_.Criticality -eq 'Tier 1' }) }

    foreach ($row in $rows) {
        $risk = Get-RiskLevel $row.SCCMCompliance $row.DeploymentState $row.DaysSincePatch $row.PendingReboot $row.Criticality $row.KnownExploitedVulns $row.ExceptionStatus
        [pscustomobject]($row + @{Risk=$risk})
    }
}

function ConvertTo-HtmlText {
    param([object]$Value)
    if ($null -eq $Value) { '' } else { [System.Net.WebUtility]::HtmlEncode([string]$Value) }
}

function New-HtmlReport {
    param([array]$Rows,[string]$Path,[pscustomobject]$Config)

    $total = $Rows.Count
    $patchCurrent = [math]::Round((@($Rows | Where-Object SCCMCompliance -eq 'Compliant').Count / $total) * 100,1)
    $criticalHigh = @($Rows | Where-Object { $_.Risk -in @('Critical','High') }).Count
    $pendingReboots = @($Rows | Where-Object PendingReboot -eq $true).Count
    $kev = (@($Rows | Measure-Object KnownExploitedVulns -Sum).Sum); if ($null -eq $kev) { $kev = 0 }

    $tableRows = foreach ($r in $Rows) {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td><td>{9}</td><td>{10}</td></tr>' -f `
            (ConvertTo-HtmlText $r.ServerName),(ConvertTo-HtmlText $r.Owner),(ConvertTo-HtmlText $r.Criticality),(ConvertTo-HtmlText $r.SCCMCompliance),(ConvertTo-HtmlText $r.DeploymentState),(ConvertTo-HtmlText $r.DaysSincePatch),(ConvertTo-HtmlText $r.PendingReboot),(ConvertTo-HtmlText $r.KnownExploitedVulns),(ConvertTo-HtmlText $r.SolarWindsRecord),(ConvertTo-HtmlText $r.Risk),(ConvertTo-HtmlText $r.RecommendedAction)
    }

    @"
<!doctype html><html><head><meta charset='utf-8'><title>Infrastructure Assurance Snapshot</title><style>body{font-family:Segoe UI,Arial,sans-serif;margin:28px;background:#f8fafc;color:#1f2937}.card,.callout,table{background:#fff;border:1px solid #e5e7eb}.cards{display:grid;grid-template-columns:repeat(5,1fr);gap:12px}.card{padding:12px;border-radius:8px}.metric{font-size:24px;font-weight:700}td,th{padding:8px;border:1px solid #e5e7eb;text-align:left;font-size:13px}table{width:100%;border-collapse:collapse}.callout{padding:12px;margin:16px 0}</style></head><body>
<h1>Infrastructure Assurance Snapshot</h1><div>SCCM + SolarWinds assurance concept | Scope: $(ConvertTo-HtmlText $Config.ScopeName)</div>
<div class='callout'><b>Effective mock configuration:</b> $(ConvertTo-HtmlText $Config.Description)<br><b>SCCM collections:</b> $(ConvertTo-HtmlText ($Config.SccmCollections -join '; '))<br><b>SolarWinds queues:</b> $(ConvertTo-HtmlText ($Config.SolarWindsQueues -join '; '))<br><b>Report sections:</b> $(ConvertTo-HtmlText ($Config.ReportSections -join '; '))</div>
<div class='cards'><div class='card'>Servers<div class='metric'>$total</div></div><div class='card'>Patch Current<div class='metric'>$patchCurrent%</div></div><div class='card'>Critical/High<div class='metric'>$criticalHigh</div></div><div class='card'>Pending Reboots<div class='metric'>$pendingReboots</div></div><div class='card'>KEV Exposure<div class='metric'>$kev</div></div></div>
<h2>Risk Work Queue</h2><table><tr><th>Server</th><th>Owner</th><th>Criticality</th><th>SCCM</th><th>Deployment</th><th>Patch Age</th><th>Pending Reboot</th><th>KEV</th><th>SolarWinds</th><th>Risk</th><th>Action</th></tr>$($tableRows -join "`n")</table></body></html>
"@ | Set-Content -Path $Path -Encoding UTF8
}

function Export-Artifacts {
    param([array]$Rows,[array]$Dependencies,[pscustomobject]$Config)

    $csv = Join-Path $script:Run.OutputPath 'Infrastructure-Assurance-Servers.csv'
    $json = Join-Path $script:Run.OutputPath 'Infrastructure-Assurance-Evidence.json'
    $html = Join-Path $script:Run.OutputPath 'Infrastructure-Assurance-Snapshot.html'

    $Rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    [pscustomobject]@{GeneratedAt=(Get-Date).ToString('o');EffectiveMockConfiguration=$Config;Dependencies=$Dependencies;Rows=$Rows} | ConvertTo-Json -Depth 8 | Set-Content -Path $json -Encoding UTF8
    New-HtmlReport -Rows $Rows -Path $html -Config $Config

    [pscustomobject]@{HtmlReport=$html;ServerCsv=$csv;EvidenceJson=$json;Log=$script:Run.LogPath;DependencyPlan=if(Test-Path $script:Run.DependencyPlanPath){$script:Run.DependencyPlanPath}else{$null}}
}

function Open-OutputFolderIfRequested {
    param([ValidateSet('Ask','Yes','No')][string]$Mode)

    $open = $Mode -eq 'Yes'
    if ($Mode -eq 'Ask') { $open = (Read-Host 'Open the output folder now? [y/N]') -match '^(y|yes)$' }

    if ($open) { Invoke-Item -LiteralPath $script:Run.OutputPath } else { Write-LogOnly 'Output folder was not opened.' }
}

function Start-AssuranceSnapshot {
    Initialize-Run -BasePath $OutputPath

    Write-Host ''
    Write-Host 'Infrastructure Assurance Snapshot' -ForegroundColor Cyan
    Write-Host 'Read-only SCCM + SolarWinds assurance prototype' -ForegroundColor DarkGray
    Write-Host "Output: $($script:Run.OutputPath)" -ForegroundColor DarkGray

    if ($DemoPaceSeconds -gt 0) { Write-Host "Demo pacing: $DemoPaceSeconds second(s) between major sections" -ForegroundColor DarkGray }

    $dependencies = Invoke-DependencyPreflight -MockInstall:$MockDependencyInstall -Strict:$StrictDependencies
    $config = Get-MockScopeConfiguration -Scope $MockScope
    Show-MockScopeConfiguration -Config $config

    if (-not $MockData) { throw 'This prototype currently supports mock-data review mode only. Re-run with -MockData.' }

    Write-Section '[3/5] Mock data load' 'Loading scoped SCCM/SolarWinds sample rows.'
    $rows = @(Get-MockRows -Scope $MockScope)
    if ($rows.Count -eq 0) { throw 'No rows returned for selected mock scope.' }
    Write-StatusLine -Status 'OK' -Name 'Rows loaded' -Detail "$($rows.Count) mock infrastructure records"
    Start-DemoPace

    Write-Section '[4/5] Artifact generation' 'Writing local report, work queue, evidence, and log files.'
    $artifacts = Export-Artifacts -Rows $rows -Dependencies $dependencies -Config $config
    Write-StatusLine -Status 'OK' -Name 'HTML report' -Detail $artifacts.HtmlReport
    Write-StatusLine -Status 'OK' -Name 'CSV work queue' -Detail $artifacts.ServerCsv
    Write-StatusLine -Status 'OK' -Name 'JSON evidence' -Detail $artifacts.EvidenceJson
    Write-StatusLine -Status 'OK' -Name 'Run log' -Detail $artifacts.Log
    if ($artifacts.DependencyPlan) { Write-StatusLine -Status 'PLAN' -Name 'Dependency plan' -Detail $artifacts.DependencyPlan }
    Start-DemoPace

    Write-Section '[5/5] Complete' 'No live systems were contacted. No changes were made.'
    Write-StatusLine -Status 'OK' -Name 'Run complete' -Detail 'review generated artifacts in the output folder'

    Open-OutputFolderIfRequested -Mode $OpenOutputFolder
}

try { Start-AssuranceSnapshot }
catch {
    if ($script:Run.LogPath) { Write-LogOnly $_.Exception.Message 'ERROR' }
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
