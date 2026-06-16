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
    - Local HTML/CSV/JSON output only

.PARAMETER MockData
    Uses built-in mock data. Recommended for review.

.PARAMETER OutputPath
    Directory where report files are written.

.EXAMPLE
    .\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData

.NOTES
    This prototype is intentionally conservative. In a real environment, the first useful production version would likely
    start from approved SCCM and SolarWinds exports before moving to direct read-only integrations.
#>

[CmdletBinding()]
param(
    [switch]$MockData,
    [string]$OutputPath = ".\InfrastructureAssuranceSnapshot"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

    # SCCM noncompliance is a real signal, but not always an emergency by itself.
    if ($SccmCompliance -ne "Compliant") { $score += 25 }

    # Failed or unknown deployment state is worse than simply being scheduled for later. It usually needs human follow-up.
    if ($DeploymentState -in @("Failed", "Unknown")) { $score += 20 }

    # Patch age is weighted in bands so the report does not overreact to normal maintenance-window timing.
    if ($DaysSincePatch -ge 45) {
        $score += 30
    }
    elseif ($DaysSincePatch -ge 30) {
        $score += 20
    }
    elseif ($DaysSincePatch -ge 15) {
        $score += 10
    }

    # Pending reboot means the technical work may not actually be complete yet.
    if ($PendingReboot) { $score += 15 }

    # Business criticality changes the priority. A stale Tier 1 system should rise faster than a low-impact utility server.
    if ($Criticality -eq "Tier 1") {
        $score += 15
    }
    elseif ($Criticality -eq "Tier 2") {
        $score += 8
    }

    # Known-exploited vulnerability exposure should cut through normal queue noise.
    if ($KnownExploitedVulns -gt 0) { $score += 35 }

    # Approved exceptions should be visible, not invisible. This lowers the score a bit but keeps the item in the report.
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

# Keep output local and predictable. This avoids creating files in a random working directory.
if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

if (-not $MockData) {
    Write-Warning "This prototype currently supports mock-data review mode only. Re-run with -MockData."
    return
}

$rows = @(Get-MockAssuranceData)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csvPath = Join-Path $OutputPath "Infrastructure-Assurance-Servers-$timestamp.csv"
$jsonPath = Join-Path $OutputPath "Infrastructure-Assurance-Evidence-$timestamp.json"
$htmlPath = Join-Path $OutputPath "Infrastructure-Assurance-Snapshot-$timestamp.html"

$rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$evidence = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString("o")
    Scope = "Mock SCCM + SolarWinds assurance data"
    Safety = @{ ReadOnly = $true; RemediationActions = $false; CredentialsStored = $false; ExternalDependencies = $false }
    Rows = $rows
}

$evidence | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
New-AssuranceHtml -Rows $rows -Path $htmlPath

Write-Host "Infrastructure Assurance Snapshot complete."
Write-Host "HTML report: $htmlPath"
Write-Host "Server CSV:  $csvPath"
Write-Host "Evidence:    $jsonPath"
