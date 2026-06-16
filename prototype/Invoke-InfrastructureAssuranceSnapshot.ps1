<#
.SYNOPSIS
    Generates a read-only Infrastructure Assurance Snapshot report.

.DESCRIPTION
    Correlates mock SCCM patch/deployment state with mock SolarWinds ticket/change evidence.

    This is intentionally written like a practical admin script:
    dependency checks first, clear workflow, simple functions, local artifacts, logging, and safe defaults.

    Safe-by-default:
    - No remediation
    - No credential storage
    - No system changes
    - No real downloads or installs
    - Mock-data mode only for now
    - Output defaults to the native OS temp directory

.PARAMETER MockData
    Uses built-in mock data. Currently required.

.PARAMETER OutputPath
    Base output directory. Defaults to the OS temp directory to avoid accidental writes into System32.

.PARAMETER MockDependencyInstall
    Writes a mock install/import plan for missing optional tools. Nothing is installed.

.PARAMETER StrictDependencies
    Treats missing optional integration tools as blocking.

.PARAMETER DemoPaceSeconds
    Optional visible delay between workflow steps for video walkthroughs. Off by default.

.PARAMETER OpenOutputFolder
    Ask, Yes, or No. Controls whether the generated artifact folder opens at the end.

.EXAMPLE
    .\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData -MockDependencyInstall -DemoPaceSeconds 1 -OpenOutputFolder Ask
#>

[CmdletBinding()]
param(
    [switch]$MockData,
    [string]$OutputPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'InfrastructureAssuranceSnapshot'),
    [switch]$MockDependencyInstall,
    [switch]$StrictDependencies,
    [ValidateRange(0, 10)]
    [int]$DemoPaceSeconds = 0,
    [ValidateSet('Ask', 'Yes', 'No')]
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
    <# .SYNOPSIS Creates a timestamped run folder under the selected base path. #>
    param([Parameter(Mandatory)][string]$BasePath)

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $runPath = Join-Path $BasePath "Run-$stamp"
    New-Item -ItemType Directory -Path $runPath -Force | Out-Null

    $script:Run.OutputPath = (Resolve-Path -LiteralPath $runPath).Path
    $script:Run.LogPath = Join-Path $script:Run.OutputPath 'Infrastructure-Assurance.log'
    $script:Run.DependencyPlanPath = Join-Path $script:Run.OutputPath 'Dependency-Plan.txt'

    @(
        'Infrastructure Assurance Snapshot log'
        "Started: $((Get-Date).ToString('o'))"
        "OutputPath: $($script:Run.OutputPath)"
        "DemoPaceSeconds: $($script:Run.DemoPaceSeconds)"
        ''
    ) | Set-Content -Path $script:Run.LogPath -Encoding UTF8
}

function Write-RunLog {
    <# .SYNOPSIS Writes a timestamped message to console and log file. #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'STEP', 'OK', 'WARN', 'ERROR', 'PLAN')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        'STEP'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }

    if ($script:Run.LogPath) {
        Add-Content -Path $script:Run.LogPath -Value $line -Encoding UTF8
    }
}

function Start-DemoPace {
    <# .SYNOPSIS Adds an optional visible pause for demo recordings. #>
    if ($script:Run.DemoPaceSeconds -gt 0) {
        Start-Sleep -Seconds $script:Run.DemoPaceSeconds
    }
}

function Invoke-Step {
    <# .SYNOPSIS Runs one named workflow step with timing and basic error handling. #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    $started = Get-Date
    Write-RunLog -Level STEP -Message "Starting: $Name"
    Start-DemoPace

    try {
        $result = & $ScriptBlock
        $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
        Write-RunLog -Level OK -Message "Completed: $Name ($elapsed sec)"
        Start-DemoPace
        return $result
    }
    catch {
        Write-RunLog -Level ERROR -Message "Failed: $Name. $($_.Exception.Message)"
        throw
    }
}

function Get-DependencyManifest {
    <# .SYNOPSIS Defines required runtime checks and optional future integration tools. #>
    @(
        [pscustomobject]@{ Name='PowerShell Runtime'; Required=$true; Type='Runtime'; Check='PowerShellVersion'; Minimum='5.1'; Purpose='Runs the prototype.'; Plan='Use Windows PowerShell 5.1+ or PowerShell 7 through the approved software channel.' }
        [pscustomobject]@{ Name='JSON Serialization'; Required=$true; Type='Command'; Check='ConvertTo-Json'; Minimum=$null; Purpose='Writes structured evidence output.'; Plan='Built into supported PowerShell versions.' }
        [pscustomobject]@{ Name='CSV Export'; Required=$true; Type='Command'; Check='Export-Csv'; Minimum=$null; Purpose='Writes the work queue.'; Plan='Built into supported PowerShell versions.' }
        [pscustomobject]@{ Name='SCCM / MECM PowerShell Module'; Required=$false; Type='Module'; Check='ConfigurationManager'; Minimum=$null; Purpose='Future read-only SCCM integration.'; Plan='Install or repair the SCCM Admin Console from the approved internal source, then import ConfigurationManager.' }
        [pscustomobject]@{ Name='SolarWinds SWIS PowerShell Module'; Required=$false; Type='Module'; Check='SwisPowerShell'; Minimum=$null; Purpose='Future read-only SolarWinds integration.'; Plan='Use the approved internal repository or approved package source for SwisPowerShell.' }
        [pscustomobject]@{ Name='Microsoft Graph Authentication'; Required=$false; Type='Module'; Check='Microsoft.Graph.Authentication'; Minimum=$null; Purpose='Future read-only Entra ID integration.'; Plan='Use the approved internal repository or approved package source for Microsoft Graph PowerShell.' }
    )
}

function Test-Dependency {
    <# .SYNOPSIS Checks one dependency and returns a structured result. #>
    param([Parameter(Mandatory)][pscustomobject]$Dependency)

    $found = $false
    $details = ''

    switch ($Dependency.Type) {
        'Runtime' {
            $found = ($PSVersionTable.PSVersion -ge [version]$Dependency.Minimum)
            $details = "PowerShell version: $($PSVersionTable.PSVersion)"
        }
        'Command' {
            $found = $null -ne (Get-Command -Name $Dependency.Check -ErrorAction SilentlyContinue)
            $details = if ($found) { 'Command found' } else { "Command missing: $($Dependency.Check)" }
        }
        'Module' {
            $module = Get-Module -ListAvailable -Name $Dependency.Check | Sort-Object Version -Descending | Select-Object -First 1
            $found = $null -ne $module
            $details = if ($found) { "Module found: $($module.Name) $($module.Version)" } else { "Module missing: $($Dependency.Check)" }
        }
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

function Write-DependencyPlan {
    <# .SYNOPSIS Writes a mock plan for a missing optional dependency. #>
    param([Parameter(Mandatory)][pscustomobject]$Dependency)

    @(
        "Dependency: $($Dependency.Name)"
        "Required:   $($Dependency.Required)"
        "Purpose:    $($Dependency.Purpose)"
        "Status:     Missing"
        'Default:    Auto-install denied; continuing safely.'
        "Plan:       $($Dependency.Plan)"
        'Action:     Mock only. No install, import, download, or system change was performed.'
        ''
    ) | Add-Content -Path $script:Run.DependencyPlanPath -Encoding UTF8

    Write-RunLog -Level PLAN -Message "Auto-install denied by default; mock plan written for: $($Dependency.Name)"
}

function Test-Dependencies {
    <# .SYNOPSIS Checks dependencies first and returns all results. #>
    param([switch]$MockInstall, [switch]$Strict)

    Write-RunLog -Message 'Dependency check policy: auto-install is denied by default; missing optional tools are documented and the run continues.'

    $results = foreach ($dependency in Get-DependencyManifest) {
        $result = Test-Dependency -Dependency $dependency

        if ($result.Found) {
            Write-RunLog -Level OK -Message "Dependency found: $($result.Name) - $($result.Details)"
        }
        else {
            $level = if ($result.Required) { 'ERROR' } else { 'WARN' }
            Write-RunLog -Level $level -Message "Dependency missing: $($result.Name) - $($result.Details)"

            if ($MockInstall) {
                Write-DependencyPlan -Dependency $result
            }
        }

        $result
    }

    $blocking = @($results | Where-Object { -not $_.Found -and ($_.Required -or $Strict) })
    if ($blocking.Count -gt 0) {
        throw "Blocking dependencies are missing: $($blocking.Name -join ', ')"
    }

    return $results
}

function Get-RiskLevel {
    <# .SYNOPSIS Converts operational signals into a simple risk label. #>
    param(
        [string]$SccmCompliance,
        [string]$DeploymentState,
        [int]$DaysSincePatch,
        [bool]$PendingReboot,
        [string]$Criticality,
        [int]$KnownExploitedVulns,
        [string]$ExceptionStatus
    )

    $score = 0
    if ($SccmCompliance -ne 'Compliant') { $score += 25 }
    if ($DeploymentState -in @('Failed', 'Unknown')) { $score += 20 }
    if ($DaysSincePatch -ge 45) { $score += 30 } elseif ($DaysSincePatch -ge 30) { $score += 20 } elseif ($DaysSincePatch -ge 15) { $score += 10 }
    if ($PendingReboot) { $score += 15 }
    if ($Criticality -eq 'Tier 1') { $score += 15 } elseif ($Criticality -eq 'Tier 2') { $score += 8 }
    if ($KnownExploitedVulns -gt 0) { $score += 35 }
    if ($ExceptionStatus -match 'Exception') { $score -= 10 }

    if ($score -ge 70) { return 'Critical' }
    if ($score -ge 45) { return 'High' }
    if ($score -ge 20) { return 'Medium' }
    return 'Low'
}

function Get-MockAssuranceRows {
    <# .SYNOPSIS Builds mock SCCM + SolarWinds assurance rows. #>
    $sourceRows = @(
        @{ServerName='OAG-DC01';    Owner='Infrastructure';     Criticality='Tier 1'; SCCMCompliance='Compliant';    DeploymentState='Success'; DaysSincePatch=9;  PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord='CHG-10482'; ExceptionStatus='None';               RecommendedAction='No immediate action. Maintain normal cadence.'}
        @{ServerName='OAG-FS02';    Owner='End User Services';  Criticality='Tier 1'; SCCMCompliance='NonCompliant'; DeploymentState='Success'; DaysSincePatch=38; PendingReboot=$true;  KnownExploitedVulns=1; SolarWindsRecord='CHG-10511'; ExceptionStatus='None';               RecommendedAction='Prioritize remediation; reboot pending after approved patch window.'}
        @{ServerName='OAG-APP07';   Owner='Application/Data';   Criticality='Tier 2'; SCCMCompliance='Compliant';    DeploymentState='Success'; DaysSincePatch=22; PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord='INC-88412'; ExceptionStatus='None';               RecommendedAction='Patch in next scheduled maintenance cycle.'}
        @{ServerName='OAG-SQL03';   Owner='Application/Data';   Criticality='Tier 1'; SCCMCompliance='NonCompliant'; DeploymentState='Failed';  DaysSincePatch=51; PendingReboot=$true;  KnownExploitedVulns=2; SolarWindsRecord='CHG-10526'; ExceptionStatus='Approved Exception'; RecommendedAction='Leadership review required. High-risk exception should have compensating controls.'}
        @{ServerName='OAG-PRINT01'; Owner='Infrastructure';     Criticality='Tier 3'; SCCMCompliance='Compliant';    DeploymentState='Success'; DaysSincePatch=17; PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord='CHG-10477'; ExceptionStatus='None';               RecommendedAction='Continue standard remediation cadence.'}
        @{ServerName='OAG-MGMT01';  Owner='Infrastructure';     Criticality='Tier 2'; SCCMCompliance='Compliant';    DeploymentState='Success'; DaysSincePatch=5;  PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord='CHG-10518'; ExceptionStatus='None';               RecommendedAction='No immediate action.'}
    )

    foreach ($row in $sourceRows) {
        $risk = Get-RiskLevel `
            -SccmCompliance $row.SCCMCompliance `
            -DeploymentState $row.DeploymentState `
            -DaysSincePatch $row.DaysSincePatch `
            -PendingReboot $row.PendingReboot `
            -Criticality $row.Criticality `
            -KnownExploitedVulns $row.KnownExploitedVulns `
            -ExceptionStatus $row.ExceptionStatus

        [pscustomobject]@{
            ServerName          = $row.ServerName
            Owner               = $row.Owner
            Criticality         = $row.Criticality
            SCCMCompliance      = $row.SCCMCompliance
            DeploymentState     = $row.DeploymentState
            DaysSincePatch      = $row.DaysSincePatch
            PendingReboot       = $row.PendingReboot
            KnownExploitedVulns = $row.KnownExploitedVulns
            SolarWindsRecord    = $row.SolarWindsRecord
            ExceptionStatus     = $row.ExceptionStatus
            Risk                = $risk
            RecommendedAction   = $row.RecommendedAction
        }
    }
}

function Test-AssuranceRows {
    <# .SYNOPSIS Performs basic validation before reports are written. #>
    param([Parameter(Mandatory)][array]$Rows)

    if ($Rows.Count -eq 0) { throw 'No assurance rows were loaded.' }

    $missingNames = @($Rows | Where-Object { [string]::IsNullOrWhiteSpace($_.ServerName) })
    if ($missingNames.Count -gt 0) { throw "$($missingNames.Count) row(s) are missing ServerName." }

    $missingEvidence = @($Rows | Where-Object { [string]::IsNullOrWhiteSpace($_.SolarWindsRecord) })
    if ($missingEvidence.Count -gt 0) {
        Write-RunLog -Level WARN -Message "$($missingEvidence.Count) row(s) do not have SolarWinds evidence attached."
    }
    else {
        Write-RunLog -Level OK -Message 'All rows include SolarWinds evidence references.'
    }
}

function ConvertTo-HtmlText {
    <# .SYNOPSIS Encodes text before rendering it in HTML. #>
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function New-HtmlReport {
    <# .SYNOPSIS Builds a self-contained HTML report. #>
    param([Parameter(Mandatory)][array]$Rows, [Parameter(Mandatory)][string]$Path)

    $total = $Rows.Count
    $patchCurrent = [math]::Round((@($Rows | Where-Object SCCMCompliance -eq 'Compliant').Count / $total) * 100, 1)
    $criticalHigh = @($Rows | Where-Object { $_.Risk -in @('Critical', 'High') }).Count
    $pendingReboots = @($Rows | Where-Object PendingReboot -eq $true).Count
    $kev = (@($Rows | Measure-Object -Property KnownExploitedVulns -Sum).Sum)
    if ($null -eq $kev) { $kev = 0 }

    $tableRows = foreach ($row in $Rows) {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td><td>{9}</td><td>{10}</td></tr>' -f `
            (ConvertTo-HtmlText $row.ServerName), (ConvertTo-HtmlText $row.Owner), (ConvertTo-HtmlText $row.Criticality),
            (ConvertTo-HtmlText $row.SCCMCompliance), (ConvertTo-HtmlText $row.DeploymentState), (ConvertTo-HtmlText $row.DaysSincePatch),
            (ConvertTo-HtmlText $row.PendingReboot), (ConvertTo-HtmlText $row.KnownExploitedVulns), (ConvertTo-HtmlText $row.SolarWindsRecord),
            (ConvertTo-HtmlText $row.Risk), (ConvertTo-HtmlText $row.RecommendedAction)
    }

    $html = @"
<!doctype html><html lang='en'><head><meta charset='utf-8'><title>Infrastructure Assurance Snapshot</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:28px;color:#1f2937;background:#f8fafc}h1{margin-bottom:4px}.subtle{color:#6b7280}.callout{background:#fff;border-left:4px solid #374151;padding:12px;margin:16px 0}.cards{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:18px 0}.card{background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:12px}.metric{font-size:24px;font-weight:700}table{width:100%;border-collapse:collapse;background:#fff}th,td{border:1px solid #e5e7eb;padding:8px;text-align:left;font-size:13px;vertical-align:top}th{background:#eef2f7}</style>
</head><body><h1>Infrastructure Assurance Snapshot</h1>
<div class='subtle'>SCCM + SolarWinds assurance concept | Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class='callout'><strong>Purpose:</strong> Correlate SCCM patch/deployment state with SolarWinds ticket/change evidence into a leadership-readable risk view.</div>
<div class='cards'><div class='card'><div>Servers</div><div class='metric'>$total</div></div><div class='card'><div>Patch Current</div><div class='metric'>$patchCurrent%</div></div><div class='card'><div>Critical/High</div><div class='metric'>$criticalHigh</div></div><div class='card'><div>Pending Reboots</div><div class='metric'>$pendingReboots</div></div><div class='card'><div>KEV Exposure</div><div class='metric'>$kev</div></div></div>
<h2>Risk Work Queue</h2><table><tr><th>Server</th><th>Owner</th><th>Criticality</th><th>SCCM</th><th>Deployment</th><th>Patch Age</th><th>Pending Reboot</th><th>KEV</th><th>SolarWinds</th><th>Risk</th><th>Recommended Action</th></tr>
$($tableRows -join "`n")
</table></body></html>
"@

    Set-Content -Path $Path -Value $html -Encoding UTF8
}

function Export-Artifacts {
    <# .SYNOPSIS Writes CSV, JSON, HTML, and returns artifact paths. #>
    param([Parameter(Mandatory)][array]$Rows, [Parameter(Mandatory)][array]$Dependencies)

    $csvPath = Join-Path $script:Run.OutputPath 'Infrastructure-Assurance-Servers.csv'
    $jsonPath = Join-Path $script:Run.OutputPath 'Infrastructure-Assurance-Evidence.json'
    $htmlPath = Join-Path $script:Run.OutputPath 'Infrastructure-Assurance-Snapshot.html'

    $Rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('o')
        Scope       = 'Mock SCCM + SolarWinds assurance data'
        Safety      = [ordered]@{ ReadOnly=$true; RemediationActions=$false; CredentialsStored=$false; ExternalDownloadsRun=$false; DependencyInstallMockOnly=[bool]$MockDependencyInstall; DemoPacingSeconds=$script:Run.DemoPaceSeconds }
        Dependencies = $Dependencies
        Rows = $Rows
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

    New-HtmlReport -Rows $Rows -Path $htmlPath

    [pscustomobject]@{
        HtmlReport = $htmlPath
        ServerCsv = $csvPath
        EvidenceJson = $jsonPath
        Log = $script:Run.LogPath
        DependencyPlan = if (Test-Path -LiteralPath $script:Run.DependencyPlanPath) { $script:Run.DependencyPlanPath } else { $null }
    }
}

function Open-OutputFolderIfRequested {
    <# .SYNOPSIS Opens the output folder based on the selected Yes/No/Ask setting. #>
    param([ValidateSet('Ask','Yes','No')][string]$Mode)

    $open = $false

    if ($Mode -eq 'Yes') {
        $open = $true
    }
    elseif ($Mode -eq 'Ask') {
        $answer = Read-Host 'Open the output folder now? [y/N]'
        $open = $answer -match '^(y|yes)$'
    }

    if ($open) {
        Write-RunLog -Message "Opening output folder: $($script:Run.OutputPath)"
        Invoke-Item -LiteralPath $script:Run.OutputPath
    }
    else {
        Write-RunLog -Message 'Output folder was not opened.'
    }
}

function Start-AssuranceSnapshot {
    <# .SYNOPSIS Runs the full prototype workflow. #>
    Initialize-Run -BasePath $OutputPath
    Write-RunLog -Message 'Infrastructure Assurance Snapshot starting.'
    Write-RunLog -Message "Artifacts will be written to: $($script:Run.OutputPath)"
    Write-RunLog -Message "Dependency install policy: default is No. Missing optional tools are documented and skipped."

    if ($script:Run.DemoPaceSeconds -gt 0) {
        Write-RunLog -Message "Demo pacing enabled: $($script:Run.DemoPaceSeconds) second(s)."
    }

    $dependencies = Invoke-Step -Name 'Check dependencies first' -ScriptBlock { Test-Dependencies -MockInstall:$MockDependencyInstall -Strict:$StrictDependencies }

    if (-not $MockData) { throw 'This prototype currently supports mock-data review mode only. Re-run with -MockData.' }

    $rows = Invoke-Step -Name 'Load mock SCCM and SolarWinds rows' -ScriptBlock { @(Get-MockAssuranceRows) }
    Invoke-Step -Name 'Validate assurance rows' -ScriptBlock { Test-AssuranceRows -Rows $rows } | Out-Null
    $artifacts = Invoke-Step -Name 'Generate report artifacts' -ScriptBlock { Export-Artifacts -Rows $rows -Dependencies $dependencies }

    Write-RunLog -Level OK -Message 'Infrastructure Assurance Snapshot complete.'
    Write-RunLog -Message "HTML report: $($artifacts.HtmlReport)"
    Write-RunLog -Message "Server CSV:  $($artifacts.ServerCsv)"
    Write-RunLog -Message "Evidence:    $($artifacts.EvidenceJson)"
    Write-RunLog -Message "Log file:    $($artifacts.Log)"
    if ($artifacts.DependencyPlan) { Write-RunLog -Message "Dependency plan: $($artifacts.DependencyPlan)" }

    Open-OutputFolderIfRequested -Mode $OpenOutputFolder
}

try {
    Start-AssuranceSnapshot
}
catch {
    if ($script:Run.LogPath) {
        Write-RunLog -Level ERROR -Message $_.Exception.Message
        Write-RunLog -Level ERROR -Message "Run failed. Last known log file: $($script:Run.LogPath)"
    }
    else {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
    exit 1
}
