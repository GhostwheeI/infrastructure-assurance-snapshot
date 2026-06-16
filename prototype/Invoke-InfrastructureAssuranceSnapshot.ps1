<#
.SYNOPSIS
    Generates a read-only Infrastructure Assurance Snapshot report.

.DESCRIPTION
    Prototype concept for correlating SCCM-style patch/deployment state with SolarWinds-style ticket/change evidence.

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
#>

[CmdletBinding()]
param(
    [switch]$MockData,
    [string]$OutputPath = ".\InfrastructureAssuranceSnapshot"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AssuranceRisk {
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

function Get-MockAssuranceData {
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
    param(
        [array]$Rows,
        [string]$Path
    )

    $total = $Rows.Count
    $patchCurrent = if ($total -gt 0) { [math]::Round((@($Rows | Where-Object SCCMCompliance -eq "Compliant").Count / $total) * 100, 1) } else { 0 }
    $criticalHigh = @($Rows | Where-Object { $_.Risk -in @("Critical", "High") }).Count
    $pendingReboots = @($Rows | Where-Object PendingReboot -eq $true).Count
    $kev = (@($Rows | Measure-Object -Property KnownExploitedVulns -Sum).Sum)

    $bodyRows = foreach ($row in $Rows) {
        "<tr><td>$($row.ServerName)</td><td>$($row.Owner)</td><td>$($row.Criticality)</td><td>$($row.SCCMCompliance)</td><td>$($row.DeploymentState)</td><td>$($row.DaysSincePatch)</td><td>$($row.PendingReboot)</td><td>$($row.KnownExploitedVulns)</td><td>$($row.SolarWindsRecord)</td><td>$($row.Risk)</td><td>$($row.RecommendedAction)</td></tr>"
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
