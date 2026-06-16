<#
.SYNOPSIS
    Generates a read-only Infrastructure Assurance Snapshot report.

.DESCRIPTION
    Correlates mock SCCM patch/deployment state with mock SolarWinds ticket/change evidence.

    This is a prototype, but it is written like a production-minded admin script:
    simple functions, clear workflow, predictable output, basic dependency checks, logging, and controlled failure behavior.

    Safe-by-default:
    - No remediation
    - No credential storage
    - No system changes
    - No real downloads or installs
    - Mock-data mode only for now
    - Local HTML/CSV/JSON/log output only

.PARAMETER MockData
    Uses built-in mock data. This is currently required.

.PARAMETER OutputPath
    Directory where report files and logs are written.

.PARAMETER MockDependencyInstall
    Writes a mock dependency install/import plan for missing optional tools. Nothing is actually installed.

.PARAMETER StrictDependencies
    Treats missing optional integration tools as blocking. Off by default because mock mode does not need them.

.EXAMPLE
    .\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData -MockDependencyInstall

.NOTES
    First production step should be export-based: SCCM export + SolarWinds export + asset owner mapping.
    Direct integrations should come later, after the data model is trusted.
#>

[CmdletBinding()]
param(
    [switch]$MockData,
    [string]$OutputPath = ".\InfrastructureAssuranceSnapshot",
    [switch]$MockDependencyInstall,
    [switch]$StrictDependencies
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Run = [ordered]@{
    StartedAt          = Get-Date
    OutputPath         = $null
    LogPath            = $null
    DependencyPlanPath = $null
}

function Initialize-Run {
    <#
    .SYNOPSIS
        Creates the output folder and starts the run log.

    .DESCRIPTION
        Keeps the run predictable. Everything this script creates lives under the selected output folder.
        No scheduled tasks, services, registry entries, or external state.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:Run.OutputPath = (Resolve-Path -LiteralPath $Path).Path
    $script:Run.LogPath = Join-Path $script:Run.OutputPath "Infrastructure-Assurance-$stamp.log"
    $script:Run.DependencyPlanPath = Join-Path $script:Run.OutputPath "Dependency-Plan-$stamp.txt"

    @(
        "Infrastructure Assurance Snapshot log"
        "Started: $((Get-Date).ToString('o'))"
        "OutputPath: $($script:Run.OutputPath)"
        ""
    ) | Set-Content -Path $script:Run.LogPath -Encoding UTF8
}

function Write-RunLog {
    <#
    .SYNOPSIS
        Writes a timestamped line to the console and log file.

    .DESCRIPTION
        Lightweight logging. Enough to show what happened, where it happened, and what failed without making the script noisy.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "STEP", "OK", "WARN", "ERROR", "PLAN")]
        [string]$Level = "INFO"
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "OK"    { Write-Host $line -ForegroundColor Green }
        "STEP"  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }

    if ($script:Run.LogPath) {
        Add-Content -Path $script:Run.LogPath -Value $line -Encoding UTF8
    }
}

function Invoke-Step {
    <#
    .SYNOPSIS
        Runs one named workflow step with timing and basic error handling.

    .DESCRIPTION
        Makes the script read like an operator workflow instead of a loose pile of commands.
        If a step fails, the error is logged and re-thrown to the top-level handler.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $started = Get-Date
    Write-RunLog -Level STEP -Message "Starting: $Name"

    try {
        $result = & $ScriptBlock
        $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
        Write-RunLog -Level OK -Message "Completed: $Name ($seconds sec)"
        return $result
    }
    catch {
        $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
        Write-RunLog -Level ERROR -Message "Failed: $Name ($seconds sec). $($_.Exception.Message)"
        throw
    }
}

function ConvertTo-HtmlText {
    <#
    .SYNOPSIS
        HTML-encodes a value before it is rendered in the report.

    .DESCRIPTION
        Even mock reports should avoid writing raw exported values into HTML. This keeps the output safe and boring.
    #>
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return "" }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-DependencyManifest {
    <#
    .SYNOPSIS
        Lists required runtime checks and optional future integration tools.

    .DESCRIPTION
        Mock mode only needs built-in PowerShell features. SCCM, SolarWinds, and Graph modules are checked as optional
        future integration points so reviewers can see the path without the script trying to install anything.
    #>
    return @(
        [pscustomobject]@{
            Name        = "PowerShell Runtime"
            Type        = "Runtime"
            Required    = $true
            Check       = "PowerShellVersion"
            Minimum     = "5.1"
            Purpose     = "Runs the prototype and generates local artifacts."
            InstallPlan = "Use Windows PowerShell 5.1+ or deploy PowerShell 7 through the approved software channel."
        }
        [pscustomobject]@{
            Name        = "JSON Serialization"
            Type        = "Command"
            Required    = $true
            Check       = "ConvertTo-Json"
            Minimum     = $null
            Purpose     = "Writes structured evidence output."
            InstallPlan = "Built into supported PowerShell versions. Repair/update PowerShell if missing."
        }
        [pscustomobject]@{
            Name        = "CSV Export"
            Type        = "Command"
            Required    = $true
            Check       = "Export-Csv"
            Minimum     = $null
            Purpose     = "Writes the infrastructure work queue."
            InstallPlan = "Built into supported PowerShell versions. Repair/update PowerShell if missing."
        }
        [pscustomobject]@{
            Name        = "SCCM / MECM PowerShell Module"
            Type        = "Module"
            Required    = $false
            Check       = "ConfigurationManager"
            Minimum     = $null
            Purpose     = "Future read-only SCCM inventory, compliance, collection, and deployment-state integration."
            InstallPlan = "Install/repair the SCCM Admin Console from the approved internal source, then import ConfigurationManager."
        }
        [pscustomobject]@{
            Name        = "SolarWinds SWIS PowerShell Module"
            Type        = "Module"
            Required    = $false
            Check       = "SwisPowerShell"
            Minimum     = $null
            Purpose     = "Future read-only SolarWinds ticket/change/incident/evidence integration."
            InstallPlan = "Install SwisPowerShell only from an approved PSGallery mirror or internal repository."
        }
        [pscustomobject]@{
            Name        = "Microsoft Graph Authentication"
            Type        = "Module"
            Required    = $false
            Check       = "Microsoft.Graph.Authentication"
            Minimum     = $null
            Purpose     = "Future read-only Entra ID / Microsoft 365 identity hygiene integration."
            InstallPlan = "Install Microsoft.Graph.Authentication only from an approved PSGallery mirror or internal repository."
        }
    )
}

function Test-Dependency {
    <#
    .SYNOPSIS
        Checks one dependency and returns a structured result.

    .DESCRIPTION
        Keeps dependency logic small and explicit. The caller decides whether a missing optional item blocks the run.
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Dependency
    )

    $found = $false
    $details = ""

    switch ($Dependency.Type) {
        "Runtime" {
            $current = $PSVersionTable.PSVersion
            $found = ($current -ge [version]$Dependency.Minimum)
            $details = "Current PowerShell version: $current"
        }
        "Command" {
            $command = Get-Command -Name $Dependency.Check -ErrorAction SilentlyContinue
            $found = ($null -ne $command)
            $details = if ($found) { "Command found" } else { "Command not found: $($Dependency.Check)" }
        }
        "Module" {
            $module = Get-Module -ListAvailable -Name $Dependency.Check | Sort-Object Version -Descending | Select-Object -First 1
            $found = ($null -ne $module)
            $details = if ($found) { "Module found: $($module.Name) $($module.Version)" } else { "Module not found: $($Dependency.Check)" }
        }
        default {
            $details = "Unknown dependency type: $($Dependency.Type)"
        }
    }

    [pscustomobject]@{
        Name        = $Dependency.Name
        Type        = $Dependency.Type
        Required    = [bool]$Dependency.Required
        Found       = [bool]$found
        Purpose     = $Dependency.Purpose
        Details     = $details
        InstallPlan = $Dependency.InstallPlan
    }
}

function Write-DependencyPlan {
    <#
    .SYNOPSIS
        Writes a mock install/import plan for a missing dependency.

    .DESCRIPTION
        This is intentionally not an installer. It documents what would need to happen after approval.
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$DependencyResult
    )

    $block = @(
        "Dependency: $($DependencyResult.Name)"
        "Required:   $($DependencyResult.Required)"
        "Purpose:    $($DependencyResult.Purpose)"
        "Status:     Missing"
        "Plan:       $($DependencyResult.InstallPlan)"
        "Action:     Mock only. No download, install, import, or system change was performed."
        ""
    )

    Add-Content -Path $script:Run.DependencyPlanPath -Value $block -Encoding UTF8
    Write-RunLog -Level PLAN -Message "Mock dependency plan written for: $($DependencyResult.Name)"
}

function Test-Dependencies {
    <#
    .SYNOPSIS
        Checks dependencies and optionally writes a mock install plan.

    .DESCRIPTION
        Required items must exist. Optional integration modules are allowed to be missing in mock mode unless StrictDependencies is used.
    #>
    param(
        [switch]$MockInstall,
        [switch]$Strict
    )

    $results = foreach ($dependency in Get-DependencyManifest) {
        $result = Test-Dependency -Dependency $dependency

        if ($result.Found) {
            Write-RunLog -Level OK -Message "Dependency found: $($result.Name) - $($result.Details)"
        }
        else {
            $level = if ($result.Required) { "ERROR" } else { "WARN" }
            Write-RunLog -Level $level -Message "Dependency missing: $($result.Name) - $($result.Details)"

            if ($MockInstall) {
                Write-DependencyPlan -DependencyResult $result
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
    <#
    .SYNOPSIS
        Converts operational signals into a simple risk label.

    .DESCRIPTION
        The math is intentionally visible. This is not meant to be a magic score; it is a practical sort order for the work queue.
    #>
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

    if ($SccmCompliance -ne "Compliant") { $score += 25 }
    if ($DeploymentState -in @("Failed", "Unknown")) { $score += 20 }
    if ($DaysSincePatch -ge 45) { $score += 30 } elseif ($DaysSincePatch -ge 30) { $score += 20 } elseif ($DaysSincePatch -ge 15) { $score += 10 }
    if ($PendingReboot) { $score += 15 }
    if ($Criticality -eq "Tier 1") { $score += 15 } elseif ($Criticality -eq "Tier 2") { $score += 8 }
    if ($KnownExploitedVulns -gt 0) { $score += 35 }
    if ($ExceptionStatus -match "Exception") { $score -= 10 }

    if ($score -ge 70) { return "Critical" }
    if ($score -ge 45) { return "High" }
    if ($score -ge 20) { return "Medium" }
    return "Low"
}

function Get-MockAssuranceRows {
    <#
    .SYNOPSIS
        Builds mock SCCM + SolarWinds assurance rows.

    .DESCRIPTION
        The rows are intentionally realistic: clean systems, pending reboots, failed deployment state, known risk, and an approved exception.
    #>

    $sourceRows = @(
        @{ServerName="OAG-DC01";    Environment="On-Prem"; Owner="Infrastructure"; Criticality="Tier 1"; OS="Windows Server 2022"; SCCMCompliance="Compliant";    DeploymentState="Success"; DaysSincePatch=9;  PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord="CHG-10482"; ExceptionStatus="None";               RecommendedAction="No immediate action. Maintain normal cadence."}
        @{ServerName="OAG-FS02";    Environment="On-Prem"; Owner="End User Services"; Criticality="Tier 1"; OS="Windows Server 2019"; SCCMCompliance="NonCompliant"; DeploymentState="Success"; DaysSincePatch=38; PendingReboot=$true;  KnownExploitedVulns=1; SolarWindsRecord="CHG-10511"; ExceptionStatus="None";               RecommendedAction="Prioritize remediation; reboot pending after approved patch window."}
        @{ServerName="OAG-APP07";   Environment="Azure";   Owner="Application/Data"; Criticality="Tier 2"; OS="Windows Server 2022"; SCCMCompliance="Compliant";    DeploymentState="Success"; DaysSincePatch=22; PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord="INC-88412"; ExceptionStatus="None";               RecommendedAction="Patch in next scheduled maintenance cycle."}
        @{ServerName="OAG-SQL03";   Environment="On-Prem"; Owner="Application/Data"; Criticality="Tier 1"; OS="Windows Server 2019"; SCCMCompliance="NonCompliant"; DeploymentState="Failed";  DaysSincePatch=51; PendingReboot=$true;  KnownExploitedVulns=2; SolarWindsRecord="CHG-10526"; ExceptionStatus="Approved Exception"; RecommendedAction="Leadership review required. High-risk exception should have compensating controls."}
        @{ServerName="OAG-PRINT01"; Environment="On-Prem"; Owner="Infrastructure"; Criticality="Tier 3"; OS="Windows Server 2016"; SCCMCompliance="Compliant";    DeploymentState="Success"; DaysSincePatch=17; PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord="CHG-10477"; ExceptionStatus="None";               RecommendedAction="Continue standard remediation cadence."}
        @{ServerName="OAG-MGMT01";  Environment="Azure";   Owner="Infrastructure"; Criticality="Tier 2"; OS="Windows Server 2022"; SCCMCompliance="Compliant";    DeploymentState="Success"; DaysSincePatch=5;  PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord="CHG-10518"; ExceptionStatus="None";               RecommendedAction="No immediate action."}
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
            Environment         = $row.Environment
            Owner               = $row.Owner
            Criticality         = $row.Criticality
            OS                  = $row.OS
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
    <#
    .SYNOPSIS
        Performs basic validation before reports are written.

    .DESCRIPTION
        Catches the obvious stuff early: empty data, missing server names, or rows without evidence references.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Rows
    )

    if ($Rows.Count -eq 0) {
        throw "No assurance rows were loaded."
    }

    $missingNames = @($Rows | Where-Object { [string]::IsNullOrWhiteSpace($_.ServerName) })
    if ($missingNames.Count -gt 0) {
        throw "$($missingNames.Count) row(s) are missing ServerName."
    }

    $missingEvidence = @($Rows | Where-Object { [string]::IsNullOrWhiteSpace($_.SolarWindsRecord) })
    if ($missingEvidence.Count -gt 0) {
        Write-RunLog -Level WARN -Message "$($missingEvidence.Count) row(s) do not have SolarWinds evidence attached."
    }
    else {
        Write-RunLog -Level OK -Message "All rows include SolarWinds evidence references."
    }
}

function New-HtmlReport {
    <#
    .SYNOPSIS
        Builds the local HTML report.

    .DESCRIPTION
        Self-contained by design. No web server, no CDN, no framework. Easy to inspect, archive, and send internally.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Rows,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $total = $Rows.Count
    $patchCurrent = if ($total -gt 0) { [math]::Round((@($Rows | Where-Object SCCMCompliance -eq "Compliant").Count / $total) * 100, 1) } else { 0 }
    $criticalHigh = @($Rows | Where-Object { $_.Risk -in @("Critical", "High") }).Count
    $pendingReboots = @($Rows | Where-Object PendingReboot -eq $true).Count
    $kev = (@($Rows | Measure-Object -Property KnownExploitedVulns -Sum).Sum)
    if ($null -eq $kev) { $kev = 0 }

    $tableRows = foreach ($row in $Rows) {
        "<tr><td>$(ConvertTo-HtmlText $row.ServerName)</td><td>$(ConvertTo-HtmlText $row.Owner)</td><td>$(ConvertTo-HtmlText $row.Criticality)</td><td>$(ConvertTo-HtmlText $row.SCCMCompliance)</td><td>$(ConvertTo-HtmlText $row.DeploymentState)</td><td>$(ConvertTo-HtmlText $row.DaysSincePatch)</td><td>$(ConvertTo-HtmlText $row.PendingReboot)</td><td>$(ConvertTo-HtmlText $row.KnownExploitedVulns)</td><td>$(ConvertTo-HtmlText $row.SolarWindsRecord)</td><td>$(ConvertTo-HtmlText $row.Risk)</td><td>$(ConvertTo-HtmlText $row.RecommendedAction)</td></tr>"
    }

    $html = @"
<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<title>Infrastructure Assurance Snapshot</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:28px;color:#1f2937;background:#f8fafc}h1{margin-bottom:4px}.subtle{color:#6b7280}.callout{background:#fff;border-left:4px solid #374151;padding:12px;margin:16px 0}.cards{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:18px 0}.card{background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:12px}.metric{font-size:24px;font-weight:700}table{width:100%;border-collapse:collapse;background:#fff}th,td{border:1px solid #e5e7eb;padding:8px;text-align:left;font-size:13px;vertical-align:top}th{background:#eef2f7}
</style>
</head>
<body>
<h1>Infrastructure Assurance Snapshot</h1>
<div class='subtle'>SCCM + SolarWinds assurance concept | Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class='callout'><strong>Purpose:</strong> Correlate SCCM patch/deployment state with SolarWinds ticket/change evidence into a leadership-readable risk view.</div>
<div class='cards'>
  <div class='card'><div>Servers</div><div class='metric'>$total</div></div>
  <div class='card'><div>Patch Current</div><div class='metric'>$patchCurrent%</div></div>
  <div class='card'><div>Critical/High</div><div class='metric'>$criticalHigh</div></div>
  <div class='card'><div>Pending Reboots</div><div class='metric'>$pendingReboots</div></div>
  <div class='card'><div>KEV Exposure</div><div class='metric'>$kev</div></div>
</div>
<h2>Risk Work Queue</h2>
<table>
<tr><th>Server</th><th>Owner</th><th>Criticality</th><th>SCCM</th><th>Deployment</th><th>Patch Age</th><th>Pending Reboot</th><th>KEV</th><th>SolarWinds</th><th>Risk</th><th>Recommended Action</th></tr>
$($tableRows -join "`n")
</table>
</body>
</html>
"@

    Set-Content -Path $Path -Value $html -Encoding UTF8
}

function Export-Artifacts {
    <#
    .SYNOPSIS
        Writes CSV, JSON, HTML, and returns the generated paths.

    .DESCRIPTION
        Keeps artifact generation in one place. CSV is the work queue, JSON is evidence, HTML is the leadership view.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Rows,

        [Parameter(Mandatory)]
        [array]$Dependencies
    )

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $csvPath = Join-Path $script:Run.OutputPath "Infrastructure-Assurance-Servers-$stamp.csv"
    $jsonPath = Join-Path $script:Run.OutputPath "Infrastructure-Assurance-Evidence-$stamp.json"
    $htmlPath = Join-Path $script:Run.OutputPath "Infrastructure-Assurance-Snapshot-$stamp.html"

    $Rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString("o")
        Scope       = "Mock SCCM + SolarWinds assurance data"
        Safety      = [ordered]@{
            ReadOnly                  = $true
            RemediationActions         = $false
            CredentialsStored          = $false
            ExternalDownloadsPerformed = $false
            DependencyInstallMockOnly  = [bool]$MockDependencyInstall
        }
        Dependencies = $Dependencies
        Rows         = $Rows
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

    New-HtmlReport -Rows $Rows -Path $htmlPath

    [pscustomobject]@{
        HtmlReport     = $htmlPath
        ServerCsv      = $csvPath
        EvidenceJson   = $jsonPath
        Log            = $script:Run.LogPath
        DependencyPlan = if (Test-Path -LiteralPath $script:Run.DependencyPlanPath) { $script:Run.DependencyPlanPath } else { $null }
    }
}

function Start-AssuranceSnapshot {
    <#
    .SYNOPSIS
        Runs the full prototype workflow.

    .DESCRIPTION
        Main orchestration stays short on purpose. The function names should explain the run without needing a diagram.
    #>

    Initialize-Run -Path $OutputPath
    Write-RunLog -Message "Infrastructure Assurance Snapshot starting."
    Write-RunLog -Message "Mode: $(if ($MockData) { 'Mock data' } else { 'No live connector enabled' })"

    $dependencies = Invoke-Step -Name "Check dependencies" -ScriptBlock {
        Test-Dependencies -MockInstall:$MockDependencyInstall -Strict:$StrictDependencies
    }

    if (-not $MockData) {
        throw "This prototype currently supports mock-data review mode only. Re-run with -MockData."
    }

    $rows = Invoke-Step -Name "Load mock SCCM and SolarWinds rows" -ScriptBlock {
        @(Get-MockAssuranceRows)
    }

    Invoke-Step -Name "Validate assurance rows" -ScriptBlock {
        Test-AssuranceRows -Rows $rows
    } | Out-Null

    $artifacts = Invoke-Step -Name "Generate report artifacts" -ScriptBlock {
        Export-Artifacts -Rows $rows -Dependencies $dependencies
    }

    Write-RunLog -Level OK -Message "Infrastructure Assurance Snapshot complete."
    Write-RunLog -Message "HTML report: $($artifacts.HtmlReport)"
    Write-RunLog -Message "Server CSV:  $($artifacts.ServerCsv)"
    Write-RunLog -Message "Evidence:    $($artifacts.EvidenceJson)"
    Write-RunLog -Message "Log file:    $($artifacts.Log)"

    if ($artifacts.DependencyPlan) {
        Write-RunLog -Message "Dependency plan: $($artifacts.DependencyPlan)"
    }
}

try {
    Start-AssuranceSnapshot
}
catch {
    if (-not $script:Run.LogPath) {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
    else {
        Write-RunLog -Level ERROR -Message $_.Exception.Message
        Write-RunLog -Level ERROR -Message "Run failed. Last known log file: $($script:Run.LogPath)"
    }

    exit 1
}
