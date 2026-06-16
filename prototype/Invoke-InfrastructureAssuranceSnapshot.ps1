<#
.SYNOPSIS
    Generates a read-only Infrastructure Assurance Snapshot report.

.DESCRIPTION
    Dependency-first mock prototype for SCCM + SolarWinds infrastructure assurance.
    Written to be simple, reviewable, and safe by default.
#>

[CmdletBinding()]
param(
    [switch]$MockData,
    [ValidateSet('Default','PatchOnly','Tier1Only','IdentityAndRecoveryPreview')]
    [string]$MockScope = 'Default',
    [string]$OutputPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'InfrastructureAssuranceSnapshot'),
    [switch]$MockDependencyInstall,
    [switch]$StrictDependencies,
    [ValidateRange(0,10)]
    [int]$DemoPaceSeconds = 0,
    [ValidateSet('Ask','Yes','No')]
    [string]$OpenOutputFolder = 'Ask'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Run = [ordered]@{ OutputPath=$null; LogPath=$null; DependencyPlanPath=$null; DemoPaceSeconds=$DemoPaceSeconds }

function Initialize-Run {
    param([string]$BasePath)
    $runPath = Join-Path $BasePath ('Run-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $runPath -Force | Out-Null
    $script:Run.OutputPath = (Resolve-Path -LiteralPath $runPath).Path
    $script:Run.LogPath = Join-Path $script:Run.OutputPath 'Infrastructure-Assurance.log'
    $script:Run.DependencyPlanPath = Join-Path $script:Run.OutputPath 'Dependency-Plan.txt'
    "Started: $((Get-Date).ToString('o'))`nOutputPath: $($script:Run.OutputPath)`nMockScope: $MockScope`n" | Set-Content -Path $script:Run.LogPath -Encoding UTF8
}

function Write-RunLog {
    param([string]$Message,[ValidateSet('INFO','STEP','OK','WARN','ERROR','PLAN')][string]$Level='INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    switch ($Level) { 'ERROR'{Write-Host $line -ForegroundColor Red} 'WARN'{Write-Host $line -ForegroundColor Yellow} 'OK'{Write-Host $line -ForegroundColor Green} 'STEP'{Write-Host $line -ForegroundColor Cyan} 'PLAN'{Write-Host $line -ForegroundColor DarkCyan} default{Write-Host $line} }
    Add-Content -Path $script:Run.LogPath -Value $line -Encoding UTF8
}

function Start-DemoPace {
    if ($script:Run.DemoPaceSeconds -gt 0) { Start-Sleep -Seconds $script:Run.DemoPaceSeconds }
}

function Invoke-Step {
    param([string]$Name,[scriptblock]$Action)
    Write-RunLog -Level STEP -Message "Starting: $Name"
    Start-DemoPace
    try { $result = & $Action; Write-RunLog -Level OK -Message "Completed: $Name"; Start-DemoPace; return $result }
    catch { Write-RunLog -Level ERROR -Message "Failed: $Name. $($_.Exception.Message)"; throw }
}

function Get-DependencyManifest {
    @(
        [pscustomobject]@{Name='PowerShell Runtime';Required=$true;Type='Runtime';Check='PowerShellVersion';Minimum='5.1';Purpose='Runs the prototype';Plan='Use Windows PowerShell 5.1+ or approved PowerShell 7 deployment'}
        [pscustomobject]@{Name='JSON Serialization';Required=$true;Type='Command';Check='ConvertTo-Json';Minimum=$null;Purpose='Writes JSON evidence';Plan='Built into supported PowerShell'}
        [pscustomobject]@{Name='CSV Export';Required=$true;Type='Command';Check='Export-Csv';Minimum=$null;Purpose='Writes work queue';Plan='Built into supported PowerShell'}
        [pscustomobject]@{Name='SCCM / MECM Module';Required=$false;Type='Module';Check='ConfigurationManager';Minimum=$null;Purpose='Future SCCM read-only integration';Plan='Use approved SCCM Admin Console source'}
        [pscustomobject]@{Name='SolarWinds SWIS Module';Required=$false;Type='Module';Check='SwisPowerShell';Minimum=$null;Purpose='Future SolarWinds read-only integration';Plan='Use approved internal package source'}
        [pscustomobject]@{Name='Microsoft Graph Auth';Required=$false;Type='Module';Check='Microsoft.Graph.Authentication';Minimum=$null;Purpose='Future Entra ID read-only integration';Plan='Use approved internal package source'}
    )
}

function Test-Dependency {
    param([pscustomobject]$Dependency)
    $found = $false
    $details = ''
    if ($Dependency.Type -eq 'Runtime') { $found = ($PSVersionTable.PSVersion -ge [version]$Dependency.Minimum); $details = "PowerShell version: $($PSVersionTable.PSVersion)" }
    elseif ($Dependency.Type -eq 'Command') { $found = $null -ne (Get-Command $Dependency.Check -ErrorAction SilentlyContinue); $details = if ($found) {'Command found'} else {"Command missing: $($Dependency.Check)"} }
    elseif ($Dependency.Type -eq 'Module') { $module = Get-Module -ListAvailable -Name $Dependency.Check | Select-Object -First 1; $found = $null -ne $module; $details = if ($found) {"Module found: $($module.Name)"} else {"Module missing: $($Dependency.Check)"} }
    [pscustomobject]@{Name=$Dependency.Name;Required=[bool]$Dependency.Required;Found=[bool]$found;Purpose=$Dependency.Purpose;Details=$details;Plan=$Dependency.Plan}
}

function Test-Dependencies {
    param([switch]$MockInstall,[switch]$Strict)
    Write-RunLog 'Dependency policy: default auto-install is No. Missing optional tools are documented and skipped.'
    $results = foreach ($dependency in Get-DependencyManifest) {
        $result = Test-Dependency $dependency
        if ($result.Found) { Write-RunLog -Level OK -Message "Dependency found: $($result.Name) - $($result.Details)" }
        else {
            Write-RunLog -Level ($(if ($result.Required) {'ERROR'} else {'WARN'})) -Message "Dependency missing: $($result.Name) - $($result.Details)"
            if ($MockInstall) {
                @("Dependency: $($result.Name)","Default: Auto-install denied; continuing safely.","Plan: $($result.Plan)",'Action: Mock only. No download, install, import, or system change was performed.','') | Add-Content -Path $script:Run.DependencyPlanPath
                Write-RunLog -Level PLAN -Message "Mock dependency plan written for: $($result.Name)"
            }
        }
        $result
    }
    $blocking = @($results | Where-Object { -not $_.Found -and ($_.Required -or $Strict) })
    if ($blocking.Count -gt 0) { throw "Blocking dependencies missing: $($blocking.Name -join ', ')" }
    $results
}

function Get-MockScopeConfiguration {
    param([string]$Scope)
    $config = [ordered]@{ScopeName=$Scope;DataMode='Mock only';InstallPolicy='Auto-install denied by default';Output=@('HTML report','CSV work queue','JSON evidence','run log')}
    switch ($Scope) {
        'PatchOnly' { $config.Description='Patch, reboot, SCCM compliance, deployment state, and SolarWinds evidence only'; $config.SccmCollections=@('All Windows Servers - Patch Review','Servers Pending Reboot'); $config.SolarWindsQueues=@('Infrastructure Change','Patch Remediation'); $config.ReportSections=@('Patch/Reboot Risk','Evidence Gaps','Recommended Actions') }
        'Tier1Only' { $config.Description='Focused Tier 1 review for leadership-sensitive systems'; $config.SccmCollections=@('Domain Controllers','Tier 1 Application Servers','Critical SQL Servers'); $config.SolarWindsQueues=@('Infrastructure Change','Application/Data Change'); $config.ReportSections=@('Critical System Risk','Pending Reboots','Exceptions') }
        'IdentityAndRecoveryPreview' { $config.Description='Preview of identity hygiene and recovery evidence joining later'; $config.SccmCollections=@('All Windows Servers - Production'); $config.SolarWindsQueues=@('Infrastructure Change','Identity Requests','Backup/Restore Validation'); $config.ReportSections=@('Patch/Reboot Risk','Identity Placeholder','Recovery Placeholder') }
        default { $config.Description='Default mock review scope for a balanced infrastructure assurance snapshot'; $config.SccmCollections=@('All Windows Servers - Production','Domain Controllers','Tier 1 Application Servers'); $config.SolarWindsQueues=@('Infrastructure Change','Application/Data Change','End User Services Incidents'); $config.ReportSections=@('Patch/Reboot Risk','SCCM Deployment State','SolarWinds Evidence','Exceptions','Recommended Actions') }
    }
    [pscustomobject]$config
}

function Show-MockScopeConfiguration {
    param([pscustomobject]$Config)
    Write-RunLog "Effective mock scope: $($Config.ScopeName)"
    Write-RunLog 'Displaying configurable mock targeting block.'
    Write-Host ''
    Write-Host '```yaml' -ForegroundColor DarkGray
    Write-Host 'mock_targeting:' -ForegroundColor White
    Write-Host "  scope_name: $($Config.ScopeName)" -ForegroundColor White
    Write-Host "  data_mode: $($Config.DataMode)" -ForegroundColor White
    Write-Host "  install_policy: $($Config.InstallPolicy)" -ForegroundColor White
    Write-Host '  sccm_collections:' -ForegroundColor White
    foreach ($item in $Config.SccmCollections) { Write-Host "    - $item" -ForegroundColor White }
    Write-Host '  solarwinds_queues:' -ForegroundColor White
    foreach ($item in $Config.SolarWindsQueues) { Write-Host "    - $item" -ForegroundColor White }
    Write-Host '  report_sections:' -ForegroundColor White
    foreach ($item in $Config.ReportSections) { Write-Host "    - $item" -ForegroundColor White }
    Write-Host '```' -ForegroundColor DarkGray
    Write-Host ''
    Start-DemoPace
    Write-RunLog "Scope description: $($Config.Description)"
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

function ConvertTo-HtmlText { param([object]$Value) if ($null -eq $Value) { '' } else { [System.Net.WebUtility]::HtmlEncode([string]$Value) } }

function New-HtmlReport {
    param([array]$Rows,[string]$Path,[pscustomobject]$Config)
    $total = $Rows.Count
    $patchCurrent = [math]::Round((@($Rows | Where-Object SCCMCompliance -eq 'Compliant').Count / $total) * 100,1)
    $criticalHigh = @($Rows | Where-Object { $_.Risk -in @('Critical','High') }).Count
    $pendingReboots = @($Rows | Where-Object PendingReboot -eq $true).Count
    $kev = (@($Rows | Measure-Object KnownExploitedVulns -Sum).Sum); if ($null -eq $kev) { $kev = 0 }
    $tableRows = foreach ($r in $Rows) { '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td><td>{9}</td><td>{10}</td></tr>' -f (ConvertTo-HtmlText $r.ServerName),(ConvertTo-HtmlText $r.Owner),(ConvertTo-HtmlText $r.Criticality),(ConvertTo-HtmlText $r.SCCMCompliance),(ConvertTo-HtmlText $r.DeploymentState),(ConvertTo-HtmlText $r.DaysSincePatch),(ConvertTo-HtmlText $r.PendingReboot),(ConvertTo-HtmlText $r.KnownExploitedVulns),(ConvertTo-HtmlText $r.SolarWindsRecord),(ConvertTo-HtmlText $r.Risk),(ConvertTo-HtmlText $r.RecommendedAction) }
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
    if ($open) { Write-RunLog "Opening output folder: $($script:Run.OutputPath)"; Invoke-Item -LiteralPath $script:Run.OutputPath } else { Write-RunLog 'Output folder was not opened.' }
}

function Start-AssuranceSnapshot {
    Initialize-Run -BasePath $OutputPath
    Write-RunLog 'Infrastructure Assurance Snapshot starting.'
    Write-RunLog "Artifacts will be written to: $($script:Run.OutputPath)"
    if ($DemoPaceSeconds -gt 0) { Write-RunLog "Demo pacing enabled: $DemoPaceSeconds second(s)." }
    $dependencies = Invoke-Step 'Check dependencies first' { Test-Dependencies -MockInstall:$MockDependencyInstall -Strict:$StrictDependencies }
    $config = Invoke-Step 'Show effective mock scope and configurable targeting' { $c = Get-MockScopeConfiguration -Scope $MockScope; Show-MockScopeConfiguration -Config $c; $c }
    if (-not $MockData) { throw 'This prototype currently supports mock-data review mode only. Re-run with -MockData.' }
    $rows = Invoke-Step 'Load mock SCCM and SolarWinds rows' { @(Get-MockRows -Scope $MockScope) }
    if ($rows.Count -eq 0) { throw 'No rows returned for selected mock scope.' }
    $artifacts = Invoke-Step 'Generate report artifacts' { Export-Artifacts -Rows $rows -Dependencies $dependencies -Config $config }
    Write-RunLog -Level OK -Message 'Infrastructure Assurance Snapshot complete.'
    Write-RunLog "HTML report: $($artifacts.HtmlReport)"
    Write-RunLog "Server CSV:  $($artifacts.ServerCsv)"
    Write-RunLog "Evidence:    $($artifacts.EvidenceJson)"
    Write-RunLog "Log file:    $($artifacts.Log)"
    if ($artifacts.DependencyPlan) { Write-RunLog "Dependency plan: $($artifacts.DependencyPlan)" }
    Open-OutputFolderIfRequested -Mode $OpenOutputFolder
}

try { Start-AssuranceSnapshot }
catch { if($script:Run.LogPath){ Write-RunLog -Level ERROR -Message $_.Exception.Message } else { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }; exit 1 }
