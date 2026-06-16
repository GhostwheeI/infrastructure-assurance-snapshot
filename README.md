# Infrastructure Assurance Snapshot

A read-only infrastructure assurance prototype for turning operational signals into leadership-ready evidence.

This project is built around a common public-sector / regulated IT problem: teams often have patch, identity, backup, monitoring, and change data spread across several tools, but leadership needs one clear answer: what is exposed, what is overdue, who owns it, what changed, and what proof exists.

## What this is

Infrastructure Assurance Snapshot is a lightweight reporting concept. It demonstrates how a Systems Administrator could consolidate existing operational data into a weekly assurance report covering:

- Patch and reboot risk
- Vulnerability remediation status
- Identity hygiene indicators
- Backup and restore validation proof
- Change-ticket / exception evidence
- Executive-readable operational risk summaries

The primary output is a local HTML report backed by CSV, JSON evidence, and a run log.

## Practical phase-one fit

The most practical first implementation path is **SCCM + SolarWinds assurance reporting**.

SCCM can remain the authoritative patch/deployment source. SolarWinds can remain the ticketing/change/incident evidence source. This project is the reporting layer above them: it correlates technical state with ownership, ticket/change evidence, exceptions, and leadership-readable risk.

That means the first useful question is not "can this replace SCCM or SolarWinds?" It cannot and should not.

The first useful question is:

> Can we quickly see which systems are patched, which still need reboot/validation, which have known risk, which ticket/change record owns the work, and which exceptions need leadership review?

## Demo video

GitHub Markdown does not support direct YouTube iframe embeds. The clean way is a clickable thumbnail.

After the walkthrough video is uploaded, replace `REPLACE_WITH_VIDEO_ID` below with the YouTube video ID:

[![Watch the walkthrough](https://img.youtube.com/vi/REPLACE_WITH_VIDEO_ID/maxresdefault.jpg)](https://www.youtube.com/watch?v=REPLACE_WITH_VIDEO_ID)

Fallback plain link:

```text
https://www.youtube.com/watch?v=REPLACE_WITH_VIDEO_ID
```

## What this is not

This is not a monitoring platform, SIEM, backup product, ticketing system, vulnerability scanner, or endpoint management replacement.

It is designed to sit above existing tools and make their outputs easier to review, explain, and defend.

Examples of systems it could consume data from in a real environment:

- SCCM / MECM, WSUS, Intune, or Azure Update Manager
- SolarWinds ticketing/change/incident exports
- Microsoft Defender Vulnerability Management
- Tenable, Qualys, Rapid7, or similar vulnerability platforms
- Active Directory and Entra ID / Microsoft Graph exports
- Veeam, Rubrik, Commvault, NetBackup, or similar backup platforms
- SIEM or monitoring platforms such as Sentinel, Splunk, SolarWinds, PRTG, or similar tools

## Prototype workflow

The PowerShell prototype is intentionally simple and modular. The main function reads like the workflow:

1. Initialize output and logging
2. Check required runtime dependencies
3. Check optional future integration dependencies
4. Write a mock install/import plan for missing optional tools when requested
5. Load mock SCCM + SolarWinds assurance data
6. Validate normalized rows and evidence references
7. Generate HTML, CSV, JSON, dependency-plan, and log artifacts
8. Fail cleanly with a logged error if something breaks

This is still a prototype. Dependency installation is simulated, not performed.

## Safety model

The prototype is intentionally safe-by-default.

- Read-only
- No remediation actions
- No stored credentials
- No registry writes
- No Active Directory writes
- No service restarts
- No firewall changes
- No real dependency downloads or installs
- Mock-data mode available for safe review
- Basic error handling and timestamped logging included

The PowerShell prototype is separated under [`prototype/`](prototype/) so reviewers can inspect it without treating the repo as something that should be run in production.

## Sample output

A static sample report is included here:

[`sample-output/Infrastructure-Assurance-Snapshot-SAMPLE.html`](sample-output/Infrastructure-Assurance-Snapshot-SAMPLE.html)

Supporting sample evidence files:

- [`sample-output/Infrastructure-Assurance-Servers-SAMPLE.csv`](sample-output/Infrastructure-Assurance-Servers-SAMPLE.csv)
- [`sample-output/Infrastructure-Assurance-Evidence-SAMPLE.json`](sample-output/Infrastructure-Assurance-Evidence-SAMPLE.json)

## Repository layout

```text
.
├─ README.md
├─ ONE-PAGE-CONCEPT.md
├─ sample-output/
│  ├─ Infrastructure-Assurance-Snapshot-SAMPLE.html
│  ├─ Infrastructure-Assurance-Servers-SAMPLE.csv
│  └─ Infrastructure-Assurance-Evidence-SAMPLE.json
├─ prototype/
│  └─ Invoke-InfrastructureAssuranceSnapshot.ps1
└─ docs/
   ├─ SAFETY-NOTES.md
   ├─ SCCM-SOLARWINDS-INTEGRATION-NOTES.md
   └─ IMPLEMENTATION-ROADMAP.md
```

## Quick review path

For a non-technical or leadership review:

1. Watch the walkthrough video, if linked above
2. Read [`ONE-PAGE-CONCEPT.md`](ONE-PAGE-CONCEPT.md)
3. Open the sample HTML report in [`sample-output/`](sample-output/)
4. Review [`docs/SAFETY-NOTES.md`](docs/SAFETY-NOTES.md)

For a technical review:

1. Inspect [`prototype/Invoke-InfrastructureAssuranceSnapshot.ps1`](prototype/Invoke-InfrastructureAssuranceSnapshot.ps1)
2. Run it only in mock-data mode first
3. Review the generated HTML, CSV, JSON, dependency-plan, and log outputs

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\prototype\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData -MockDependencyInstall
```

## Dependency behavior

The prototype checks built-in requirements and future integration tools.

Required for mock-data report generation:

- PowerShell 5.1+
- `ConvertTo-Json`
- `Export-Csv`
- Local file write access to the output directory

Optional future integration checks:

- SCCM / MECM `ConfigurationManager` PowerShell module
- SolarWinds `SwisPowerShell` module
- Microsoft Graph authentication module

When `-MockDependencyInstall` is used, missing optional dependencies are written to a dependency-plan text file. No download, install, import, or system change is performed.

## MVP recommendation

The most practical first production module is Patch / Reboot / Vulnerability Assurance using SCCM as the authoritative technical source and SolarWinds as the work/evidence source.

It should correlate:

- SCCM device/server inventory
- SCCM update compliance state
- SCCM deployment status
- Pending reboot state
- Owner/team
- Business criticality
- Maintenance window
- Known-exploited vulnerability exposure
- SolarWinds ticket/change/incident reference
- Approved exception or accepted-risk reference
- Recommended next action

That produces a direct operational work queue for infrastructure teams and a clean risk view for leadership.

## Design principles

- Do not replace authoritative tools
- Do not automate remediation before visibility is trusted
- Keep production access least-privilege and read-only first
- Prefer evidence over opinion
- Show ownership, exception status, and next action
- Make the output useful to both administrators and leadership

## Status

Prototype / concept stage. The included data is mock data for demonstration only.