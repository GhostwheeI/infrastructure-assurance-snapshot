<#
.SYNOPSIS
    Generates a read-only Infrastructure Assurance Snapshot report.

.DESCRIPTION
    Prototype concept for correlating SCCM-style patch/deployment state with SolarWinds-style ticket/change evidence.

    This is deliberately a visibility tool, not a remediation tool. The point is to show how existing operational data
    could be turned into something leadership can actually use: what is exposed, what is overdue, who owns it, what ticket
    or change record proves the work, and what still needs a decision.

    Safe-by-default:
    - No remediation
    - No credential storage
    - No system changes
    - Mock-data mode supported
    - Local HTML/CSV/JSON/log output only
    - Dependency installation is simulated unless a future production version explicitly enables it

.PARAMETER MockData
    Uses built-in mock data. Recommended for review.

.PARAMETER OutputPath
    Directory where report files and logs are written.

.PARAMETER MockDependencyInstall
    Shows the install/remediation plan for missing optional tools without actually installing anything.

.PARAMETER StrictDependencies
    Treats missing optional integration tools as blocking. Off by default because the prototype can run with mock data.

.EXAMPLE
    .\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData

.EXAMPLE
    .\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData -MockDependencyInstall

.NOTES
    This prototype is intentionally conservative. In a real environment, the first useful production version would likely
    start from approved SCCM and SolarWinds exports before moving to direct read-only integrations.
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

$script:RunContext = [ordered]@{
    StartedAt = Get-Date
    OutputPath = $null
    LogPath = $null
    DependencyPlanPath = $null
}

function Initialize-AssuranceRun {
    <#
    .SYNOPSIS
        Prepares the output folder, log file, and dependency-plan file for the run.

    .DESCRIPTION
        A reporting script should leave a trail. This function creates the run directory up front and records where the
        log and dependency plan will live. That makes the workflow predictable and easier to review after the fact.

        It does not create scheduled tasks, registry entries, services, or anything persistent outside the chosen output
        folder.

    .PARAMETER Path
        The directory where all generated artifacts should be written.

    .OUTPUTS
        None. Updates the script-level run context.
    #>

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:RunContext.OutputPath = (Resolve-Path -LiteralPath $Path).Path
    $script:RunContext.LogPath = Join-Path $script:RunContext.OutputPath "Infrastructure-Assurance-$timestamp.log"
    $script:RunContext.DependencyPlanPath = Join-Path $script:RunContext.OutputPath "Dependency-Install-Plan-$timestamp.txt"

    "Infrastructure Assurance Snapshot log" | Set-Content -Path $script:RunContext.LogPath -Encoding UTF8
    "Started: $((Get-Date).ToString('o'))" | Add-Content -Path $script:RunContext.LogPath -Encoding UTF8
    "OutputPath: $($script:RunContext.OutputPath)" | Add-Content -Path $script:RunContext.LogPath -Encoding UTF8
    "" | Add-Content -Path $script:RunContext.LogPath -Encoding UTF8
}

function Write-AssuranceLog {
    <#
    .SYNOPSIS
        Writes a timestamped message to both console and log file.

    .DESCRIPTION
        This keeps the run transparent without making the user dig through a debugger. The console shows the current state,
        and the log file gives a simple artifact that can be attached to a ticket or reviewed later.

    .PARAMETER Message
        The message to write.

    .PARAMETER Level
        The message level. Supported values are INFO, WARN, ERROR, STEP, OK, and PLAN.

    .OUTPUTS
        None.
    #>

    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "STEP", "OK", "PLAN")]
        [string]$Level = "INFO"
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    if ($Level -eq "ERROR") {
        Write-Host $line -ForegroundColor Red
    }
    elseif ($Level -eq "WARN") {
        Write-Host $line -ForegroundColor Yellow
    }
    elseif ($Level -in @("OK", "STEP")) {
        Write-Host $line -ForegroundColor Green
    }
    else {
        Write-Host $line
    }

    if ($script:RunContext.LogPath) {
        Add-Content -Path $script:RunContext.LogPath -Value $line -Encoding UTF8
    }
}

function Invoke-AssuranceStep {
    <#
    .SYNOPSIS
        Runs one named workflow step with basic timing and error handling.

    .DESCRIPTION
        This gives the script a clean operator-style workflow. Each major action is named, logged, timed, and either marked
        complete or failed. That is more useful than a script that silently jumps between unrelated blocks of code.

    .PARAMETER Name
        Human-readable step name.

    .PARAMETER Action
        The script block to execute.

    .OUTPUTS
        The output of the supplied script block, if any.

    .NOTES
        Errors are rethrown after logging. The top-level try/catch handles final exit behavior.
    #>

    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $stepStart = Get-Date
    Write-AssuranceLog -Level STEP -Message "Starting: $Name"

    try {
        $result = & $Action
        $elapsed = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 2)
        Write-AssuranceLog -Level OK -Message "Completed: $Name ($elapsed sec)"
        return $result
    }
    catch {
        $elapsed = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 2)
        Write-AssuranceLog -Level ERROR -Message "Failed: $Name ($elapsed sec). $($_.Exception.Message)"
        throw
    }
}

function ConvertTo-SafeHtml {
    <#
    .SYNOPSIS
        Encodes report values before they are written into the HTML output.

    .DESCRIPTION
        This is a small helper, but it matters. Even in a prototype, report generation should not blindly place raw values
        into HTML. Server names, ticket IDs, owners, and comments may eventually come from exports or outside systems.

        The goal here is simple: preserve the text, but make it safe to render in a browser.

    .PARAMETER Value
        The value that should be converted into browser-safe text.

    .OUTPUTS
        System.String

    .NOTES
        This does not sanitize files, scripts, or attachments. It only HTML-encodes text fields used in the generated report.
    #>

    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-DependencyManifest {
    <#
    .SYNOPSIS
        Defines the runtime dependencies and future integration tools the script knows how to check.

    .DESCRIPTION
        The prototype only needs built-in PowerShell capabilities to run in mock-data mode. The optional entries show the
        real-world path for SCCM, SolarWinds, and Microsoft cloud integration without pretending those tools are available
        everywhere.

        This is intentionally transparent: each dependency says what it is, why it matters, whether it is required, and what
        an approved install/import path might look like later.

    .OUTPUTS
        PSCustomObject[]
    #>

    @(
        [pscustomobject]@{
            Name = "PowerShell Runtime"
            Type = "Runtime"
            Required = $true
            Check = "PowerShellVersion"
            MinimumVersion = "5.1"
            Purpose = "Runs the prototype and generates local artifacts."
            InstallPlan = "Use Windows PowerShell 5.1+ or install PowerShell 7 through approved software deployment."
        }
        [pscustomobject]@{
            Name = "JSON Serialization"
            Type = "Command"
            Required = $true
            Check = "ConvertTo-Json"
            MinimumVersion = $null
            Purpose = "Writes the evidence file in JSON format."
            InstallPlan = "Built into supported PowerShell versions. If missing, repair/update PowerShell."
        }
        [pscustomobject]@{
            Name = "CSV Export"
            Type = "Command"
            Required = $true
            Check = "Export-Csv"
            MinimumVersion = $null
            Purpose = "Writes the infrastructure work queue."
            InstallPlan = "Built into supported PowerShell versions. If missing, repair/update PowerShell."
        }
        [pscustomobject]@{
            Name = "SCCM / MECM PowerShell Module"
            Type = "Module"
            Required = $false
            Check = "ConfigurationManager"
            MinimumVersion = $null
            Purpose = "Future read-only SCCM inventory, compliance, collection, and deployment-state integration."
            InstallPlan = "Install or repair the SCCM/MECM Admin Console from the approved internal software source, then import the ConfigurationManager module."
        }
        [pscustomobject]@{
            Name = "SolarWinds SWIS PowerShell Module"
            Type = "Module"
            Required = $false
            Check = "SwisPowerShell"
            MinimumVersion = $null
            Purpose = "Future read-only SolarWinds ticket/change/incident/evidence integration where SWIS is approved."
            InstallPlan = "Install-Module -Name SwisPowerShell -Scope CurrentUser -Force # only from an approved PSGallery/internal repository path"
        }
        [pscustomobject]@{
            Name = "Microsoft Graph PowerShell"
            Type = "Module"
            Required = $false
            Check = "Microsoft.Graph.Authentication"
            MinimumVersion = $null
            Purpose = "Future read-only Entra ID / Microsoft 365 identity hygiene integration."
            InstallPlan = "Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Force # only from an approved PSGallery/internal repository path"
        }
    )
}

function Test-AssuranceDependency {
    <#
    .SYNOPSIS
        Checks one dependency from the manifest and returns a structured result.

    .DESCRIPTION
        This function avoids magic. It checks exactly what the manifest says to check and returns a plain object with status,
        purpose, and install guidance. Missing required dependencies can stop the run. Missing optional dependencies are
        logged as future integration gaps unless StrictDependencies is used.

    .PARAMETER Dependency
        A dependency object from Get-DependencyManifest.

    .OUTPUTS
        PSCustomObject
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
            $minimum = [version]$Dependency.MinimumVersion
            $found = ($current -ge $minimum)
            $details = "Current PowerShell version: $current"
        }
        "Command" {
            $command = Get-Command -Name $Dependency.Check -ErrorAction SilentlyContinue
            $found = ($null -ne $command)
            $details = if ($found) { "Command found: $($command.Source)" } else { "Command not found: $($Dependency.Check)" }
        }
        "Module" {
            $module = Get-Module -ListAvailable -Name $Dependency.Check | Sort-Object Version -Descending | Select-Object -First 1
            $found = ($null -ne $module)
            $details = if ($found) { "Module found: $($module.Name) $($module.Version)" } else { "Module not found: $($Dependency.Check)" }
        }
        default {
            $found = $false
            $details = "Unknown dependency type: $($Dependency.Type)"
        }
    }

    [pscustomobject]@{
        Name = $Dependency.Name
        Type = $Dependency.Type
        Required = [bool]$Dependency.Required
        Found = [bool]$found
        Purpose = $Dependency.Purpose
        Details = $details
        InstallPlan = $Dependency.InstallPlan
    }
}

function Invoke-MockDependencyInstall {
    <#
    .SYNOPSIS
        Records a clear mock install plan for missing dependencies.

    .DESCRIPTION
        This does not install anything. It writes what would need to happen if the prototype were promoted into a real
        implementation and the missing tool was approved. That is the right line for a public repo: show that dependency
        handling was thought through without asking a reviewer to trust surprise downloads.

    .PARAMETER MissingDependency
        The dependency result object that needs an install/import plan.

    .OUTPUTS
        None. Writes to console, log, and the dependency-plan artifact.
    #>

    param(
        [Parameter(Mandatory)]
        [pscustomobject]$MissingDependency
    )

    $plan = @(
        "Dependency: $($MissingDependency.Name)"
        "Required:   $($MissingDependency.Required)"
        "Purpose:    $($MissingDependency.Purpose)"
        "Status:     Missing"
        "Plan:       $($MissingDependency.InstallPlan)"
        "Action:     Mock only. No download, install, import, or system change was performed."
        ""
    )

    Write-AssuranceLog -Level PLAN -Message "Mock install plan queued for missing dependency: $($MissingDependency.Name)"
    Add-Content -Path $script:RunContext.DependencyPlanPath -Value $plan -Encoding UTF8
}

function Test-AssuranceDependencies {
    <#
    .SYNOPSIS
        Checks required runtime dependencies and optional future integration tools.

    .DESCRIPTION
        This is the dependency gate. It checks the built-in requirements needed to produce reports and then checks optional
        tools that would matter in a real SCCM/SolarWinds/Microsoft 365 environment.

        Optional dependency misses do not block mock-data review by default. If MockDependencyInstall is used, the script
        writes a concrete install/import plan so the reviewer can see how those gaps would be handled later.

    .PARAMETER MockInstall
        When set, write mock install plans for missing dependencies.

    .PARAMETER Strict
        When set, missing optional dependencies are treated as blocking.

    .OUTPUTS
        PSCustomObject[]
    #>

    param(
        [switch]$MockInstall,
        [switch]$Strict
    )

    $manifest = Get-DependencyManifest
    $results = foreach ($dependency in $manifest) {
        $result = Test-AssuranceDependency -Dependency $dependency

        if ($result.Found) {
            Write-AssuranceLog -Level OK -Message "Dependency found: $($result.Name) - $($result.Details)"
        }
        else {
            $level = if ($result.Required) { "ERROR" } else { "WARN" }
            Write-AssuranceLog -Level $level -Message "Dependency missing: $($result.Name) - $($result.Details)"

            if ($MockInstall) {
                Invoke-MockDependencyInstall -MissingDependency $result
            }
        }

        $result
    }

    $blocking = @($results | Where-Object { -not $_.Found -and ($_.Required -or $Strict) })
    if ($blocking.Count -gt 0) {
        $names = ($blocking.Name -join ", ")
        throw "Blocking dependencies are missing: $names"
    }

    return $results
}

function Get-AssuranceRisk {
    <#
    .SYNOPSIS
        Converts patch, reboot, vulnerability, criticality, and exception signals into a simple risk label.

    .DESCRIPTION
        This function is intentionally straightforward. A CIO or infrastructure manager does not need a fake-perfect risk
        algorithm in a prototype. They need a consistent way to sort the work queue and see what deserves attention first.

        The score favors the things that usually matter operationally:
        - SCCM says the system is not compliant
        - Deployment failed or is unknown
        - Patch age is getting stale
        - A reboot is still pending
        - The system is business-critical
        - Known-exploited vulnerability exposure exists
        - An exception exists, but still needs visibility

        The output is a plain label: Low, Medium, High, or Critical.

    .PARAMETER SccmCompliance
        SCCM-style compliance state. Expected values in the mock data are Compliant or NonCompliant.

    .PARAMETER DeploymentState
        SCCM-style deployment result. Failed and Unknown are treated as higher risk.

    .PARAMETER DaysSincePatch
        Number of days since the system was last patched or last reported as current.

    .PARAMETER PendingReboot
        True when the system still needs a reboot to complete patching or validation.

    .PARAMETER Criticality
        Business criticality tier. Tier 1 receives the most weight.

    .PARAMETER KnownExploitedVulns
        Count of known-exploited vulnerability indicators associated with the system.

    .PARAMETER ExceptionStatus
        Exception or accepted-risk status. An approved exception reduces score slightly, but does not hide the risk.

    .OUTPUTS
        System.String

    .NOTES
        These weights are not sacred. In production, Security, Infrastructure, and leadership should tune them together.
        The important part is that the scoring is visible and explainable instead of buried in a black box.
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

    if ($DaysSincePatch -ge 45) {
        $score += 30
    }
    elseif ($DaysSincePatch -ge 30) {
        $score += 20
    }
    elseif ($DaysSincePatch -ge 15) {
        $score += 10
    }

    if ($PendingReboot) { $score += 15 }

    if ($Criticality -eq "Tier 1") {
        $score += 15
    }
    elseif ($Criticality -eq "Tier 2") {
        $score += 8
    }

    if ($KnownExploitedVulns -gt 0) { $score += 35 }
    if ($ExceptionStatus -match "Exception") { $score -= 10 }

    if ($score -ge 70) { return "Critical" }
    if ($score -ge 45) { return "High" }
    if ($score -ge 20) { return "Medium" }
    return "Low"
}

function Get-MockAssuranceData {
    <#
    .SYNOPSIS
        Returns realistic mock assurance rows for safe review.

    .DESCRIPTION
        This function exists so the repo can be reviewed without asking anyone to connect to SCCM, SolarWinds, AD, Entra,
        a backup platform, or a vulnerability scanner.

        The mock rows are intentionally shaped like a real operational report:
        - Some systems are clean
        - Some are patched but still need reboot/validation
        - Some have failed or stale patch state
        - Some have SolarWinds evidence attached
        - One has an approved exception so the report shows risk governance instead of pretending exceptions do not exist

        This makes the prototype safe to inspect and easy to discuss.

    .OUTPUTS
        PSCustomObject[]

    .NOTES
        In production, this function would be replaced by import/connectors for approved SCCM and SolarWinds data sources.
        Keeping mock data separate also makes it obvious that this prototype is not touching any real environment.
    #>

    $rows = @(
        @{ServerName="OAG-DC01"; Environment="On-Prem"; Owner="Infrastructure"; Criticality="Tier 1"; OS="Windows Server 2022"; SCCMCompliance="Compliant"; DeploymentState="Success"; DaysSincePatch=9; PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord="CHG-10482"; ExceptionStatus="None"; RecommendedAction="No immediate action. Maintain normal cadence."},
        @{ServerName="OAG-FS02"; Environment="On-Prem"; Owner="End User Services"; Criticality="Tier 1"; OS="Windows Server 2019"; SCCMCompliance="NonCompliant"; DeploymentState="Success"; DaysSincePatch=38; PendingReboot=$true; KnownExploitedVulns=1; SolarWindsRecord="CHG-10511"; ExceptionStatus="None"; RecommendedAction="Prioritize remediation; reboot pending after approved patch window."},
        @{ServerName="OAG-APP07"; Environment="Azure"; Owner="Application/Data"; Criticality="Tier 2"; OS="Windows Server 2022"; SCCMCompliance="Compliant"; DeploymentState="Success"; DaysSincePatch=22; PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord="INC-88412"; ExceptionStatus="None"; RecommendedAction="Patch in next scheduled maintenance cycle."},
        @{ServerName="OAG-SQL03"; Environment="On-Prem"; Owner="Application/Data"; Criticality="Tier 1"; OS="Windows Server 2019"; SCCMCompliance="NonCompliant"; DeploymentState="Failed"; DaysSincePatch=51; PendingReboot=$true; KnownExploitedVulns=2; SolarWindsRecord="CHG-10526"; ExceptionStatus="Approved Exception"; RecommendedAction="Leadership review required. High-risk exception should have compensating controls."},
        @{ServerName="OAG-PRINT01"; Environment="On-Prem"; Owner="Infrastructure"; Criticality="Tier 3"; OS="Windows Server 2016"; SCCMCompliance="Compliant"; DeploymentState="Success"; DaysSincePatch=17; PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord="CHG-10477"; ExceptionStatus="None"; RecommendedAction="Continue standard remediation cadence."},
        @{ServerName="OAG-MGMT01"; Environment="Azure"; Owner="Infrastructure"; Criticality="Tier 2"; OS="Windows Server 2022"; SCCMCompliance="Compliant"; DeploymentState="Success"; DaysSincePatch=5; PendingReboot=$false; KnownExploitedVulns=0; SolarWindsRecord="CHG-10518"; ExceptionStatus="None"; RecommendedAction="No immediate action."}
    )

    foreach ($r in $rows) {
        $risk = Get-AssuranceRisk -SccmCompliance $r.SCCMCompliance -DeploymentState $r.DeploymentState -DaysSincePatch $r.DaysSincePatch -PendingReboot $r.PendingReboot -Criticality $r.Criticality -KnownExploitedVulns $r.KnownExploitedVulns -ExceptionStatus $r.ExceptionStatus

        [pscustomobject]@{
            ServerName          = $r.ServerName
            Environment         = $r.Environment
            Owner               = $r.Owner
            Criticality         = $r.Criticality
            OS                  = $r.OS
            SCCMCompliance      = $r.SCCMCompliance
            DeploymentState     = $r.DeploymentState
            DaysSincePatch      = $r.DaysSincePatch
            PendingReboot       = $r.PendingReboot
            KnownExploitedVulns = $r.KnownExploitedVulns
            SolarWindsRecord    = $r.SolarWindsRecord
            ExceptionStatus     = $r.ExceptionStatus
            Risk                = $risk
            RecommendedAction   = $r.RecommendedAction
        }
    }
}

function New-AssuranceHtml {
    <#
    .SYNOPSIS
        Builds the local HTML version of the assurance report.

    .DESCRIPTION
        This function turns the normalized assurance rows into a browser-readable report. It is intentionally simple:
        no web server, no dashboard framework, no external CSS, no CDN, and no authentication layer.

        That is on purpose. For an early operational prototype, a self-contained HTML file is easy to review, easy to email
        internally if approved, and easy to archive as evidence.

    .PARAMETER Rows
        The normalized assurance rows to render into the report.

    .PARAMETER Path
        The full path where the HTML report should be written.

    .OUTPUTS
        None. Writes an HTML file to disk.

    .NOTES
        The report is not meant to be pretty for its own sake. It is meant to make the risk queue obvious in under a minute.
        Values are HTML-encoded before rendering so exported data does not become raw browser content.
    #>

    param(
        [array]$Rows,
        [string]$Path
    )

    $total = $Rows.Count
    $patchCurrent = if ($total -gt 0) { [math]::Round((@($Rows | Where-Object SCCMCompliance -eq "Compliant").Count / $total) * 100, 1) } else { 0 }
    $criticalHigh = @($Rows | Where-Object { $_.Risk -in @("Critical", "High") }).Count
    $pendingReboots = @($Rows | Where-Object PendingReboot -eq $true).Count
    $kev = (@($Rows | Measure-Object -Property KnownExploitedVulns -Sum).Sum)

    if ($null -eq $kev) {
        $kev = 0
    }

    $bodyRows = foreach ($row in $Rows) {
        "<tr><td>$(ConvertTo-SafeHtml $row.ServerName)</td><td>$(ConvertTo-SafeHtml $row.Owner)</td><td>$(ConvertTo-SafeHtml $row.Criticality)</td><td>$(ConvertTo-SafeHtml $row.SCCMCompliance)</td><td>$(ConvertTo-SafeHtml $row.DeploymentState)</td><td>$(ConvertTo-SafeHtml $row.DaysSincePatch)</td><td>$(ConvertTo-SafeHtml $row.PendingReboot)</td><td>$(ConvertTo-SafeHtml $row.KnownExploitedVulns)</td><td>$(ConvertTo-SafeHtml $row.SolarWindsRecord)</td><td>$(ConvertTo-SafeHtml $row.Risk)</td><td>$(ConvertTo-SafeHtml $row.RecommendedAction)</td></tr>"
    }

    $html = @"
<!doctype html>
<html><head><meta charset='utf-8'><title>Infrastructure Assurance Snapshot</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:28px;color:#1f2937;background:#f8fafc}table{width:100%;border-collapse:collapse;background:#fff}th,td{border:1px solid #e5e7eb;padding:8px;text-align:left;font-size:13px}th{background:#eef2f7}.cards{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:18px 0}.card{background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:12px}.metric{font-size:24px;font-weight:700}.subtle{color:#6b7280}.callout{background:#fff;border-left:4px solid #374151;padding:12px;margin:16px 0}
</style></head><body>
<h1>Infrastructure Assurance Snapshot</h1>
<div class='subtle'>SCCM + SolarWinds assurance concept | Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class='callout'><strong>Purpose:</strong> Correlate SCCM patch/deployment state with SolarWinds ticket/change evidence into a leadership-readable risk view.</div>
<div class='cards'><div class='card'><div>Servers</div><div class='metric'>$total</div></div><div class='card'><div>Patch Current</div><div class='metric'>$patchCurrent%</div></div><div class='card'><div>Critical/High</div><div class='metric'>$criticalHigh</div></div><div class='card'><div>Pending Reboots</div><div class='metric'>$pendingReboots</div></div><div class='card'><div>KEV Exposure</div><div class='metric'>$kev</div></div></div>
<h2>Risk Work Queue</h2>
<table><tr><th>Server</th><th>Owner</th><th>Criticality</th><th>SCCM</th><th>Deployment</th><th>Patch Age</th><th>Pending Reboot</th><th>KEV</th><th>SolarWinds</th><th>Risk</th><th>Recommended Action</th></tr>
$($bodyRows -join "`n")
</table>
</body></html>
"@

    Set-Content -Path $Path -Value $html -Encoding UTF8
}

function Export-AssuranceArtifacts {
    <#
    .SYNOPSIS
        Writes the HTML, CSV, and JSON artifacts for the current run.

    .DESCRIPTION
        This function keeps output generation in one place. The CSV gives the technical work queue, the JSON gives structured
        evidence, and the HTML gives leadership a fast readout.

    .PARAMETER Rows
        The normalized assurance rows to export.

    .PARAMETER DependencyResults
        The dependency-check results to include in the evidence file.

    .OUTPUTS
        PSCustomObject describing the generated artifact paths.
    #>

    param(
        [Parameter(Mandatory)]
        [array]$Rows,

        [Parameter(Mandatory)]
        [array]$DependencyResults
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $csvPath = Join-Path $script:RunContext.OutputPath "Infrastructure-Assurance-Servers-$timestamp.csv"
    $jsonPath = Join-Path $script:RunContext.OutputPath "Infrastructure-Assurance-Evidence-$timestamp.json"
    $htmlPath = Join-Path $script:RunContext.OutputPath "Infrastructure-Assurance-Snapshot-$timestamp.html"

    $Rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    $evidence = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString("o")
        Scope = "Mock SCCM + SolarWinds assurance data"
        Safety = @{
            ReadOnly = $true
            RemediationActions = $false
            CredentialsStored = $false
            ExternalDependencies = $false
            DependencyInstallWasMockOnly = [bool]$MockDependencyInstall
        }
        Dependencies = $DependencyResults
        Rows = $Rows
    }

    $evidence | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
    New-AssuranceHtml -Rows $Rows -Path $htmlPath

    [pscustomobject]@{
        HtmlReport = $htmlPath
        ServerCsv = $csvPath
        EvidenceJson = $jsonPath
        Log = $script:RunContext.LogPath
        DependencyPlan = if (Test-Path -LiteralPath $script:RunContext.DependencyPlanPath) { $script:RunContext.DependencyPlanPath } else { $null }
    }
}

try {
    Initialize-AssuranceRun -Path $OutputPath
    Write-AssuranceLog -Message "Infrastructure Assurance Snapshot starting."
    Write-AssuranceLog -Message "Mode: $(if ($MockData) { 'Mock data' } else { 'No live connector enabled' })"

    $dependencyResults = Invoke-AssuranceStep -Name "Check runtime and integration dependencies" -Action {
        Test-AssuranceDependencies -MockInstall:$MockDependencyInstall -Strict:$StrictDependencies
    }

    if (-not $MockData) {
        throw "This prototype currently supports mock-data review mode only. Re-run with -MockData."
    }

    $rows = Invoke-AssuranceStep -Name "Load mock SCCM and SolarWinds assurance data" -Action {
        @(Get-MockAssuranceData)
    }

    Invoke-AssuranceStep -Name "Validate normalized assurance rows" -Action {
        if ($rows.Count -eq 0) {
            throw "No assurance rows were loaded."
        }

        $missingEvidence = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.SolarWindsRecord) })
        if ($missingEvidence.Count -gt 0) {
            Write-AssuranceLog -Level WARN -Message "$($missingEvidence.Count) row(s) do not have SolarWinds evidence attached."
        }
        else {
            Write-AssuranceLog -Level OK -Message "All mock rows include SolarWinds evidence references."
        }
    }

    $artifacts = Invoke-AssuranceStep -Name "Generate HTML, CSV, JSON, and log artifacts" -Action {
        Export-AssuranceArtifacts -Rows $rows -DependencyResults $dependencyResults
    }

    Write-AssuranceLog -Level OK -Message "Infrastructure Assurance Snapshot complete."
    Write-AssuranceLog -Message "HTML report: $($artifacts.HtmlReport)"
    Write-AssuranceLog -Message "Server CSV:  $($artifacts.ServerCsv)"
    Write-AssuranceLog -Message "Evidence:    $($artifacts.EvidenceJson)"
    Write-AssuranceLog -Message "Log file:    $($artifacts.Log)"

    if ($artifacts.DependencyPlan) {
        Write-AssuranceLog -Message "Dependency plan: $($artifacts.DependencyPlan)"
    }
}
catch {
    Write-AssuranceLog -Level ERROR -Message $_.Exception.Message
    Write-AssuranceLog -Level ERROR -Message "Run failed. Check the log file for the last completed step: $($script:RunContext.LogPath)"
    exit 1
}
