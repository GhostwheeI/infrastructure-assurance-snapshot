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

The primary output is a local HTML report backed by CSV and JSON evidence files.

## What this is not

This is not a monitoring platform, SIEM, backup product, ticketing system, vulnerability scanner, or endpoint management replacement.

It is designed to sit above existing tools and make their outputs easier to review, explain, and defend.

Examples of systems it could consume data from in a real environment:

- MECM / SCCM, WSUS, Intune, or Azure Update Manager
- Microsoft Defender Vulnerability Management
- Tenable, Qualys, Rapid7, or similar vulnerability platforms
- Active Directory and Entra ID / Microsoft Graph exports
- Veeam, Rubrik, Commvault, NetBackup, or similar backup platforms
- ServiceNow, Jira Service Management, or other ITSM/change systems
- SIEM or monitoring platforms such as Sentinel, Splunk, SolarWinds, PRTG, or similar tools

## Safety model

The prototype is intentionally safe-by-default.

- Read-only
- No remediation actions
- No stored credentials
- No registry writes
- No Active Directory writes
- No service restarts
- No firewall changes
- No external dependencies
- Mock-data mode available for safe review

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
   └─ IMPLEMENTATION-ROADMAP.md
```

## Quick review path

For a non-technical or leadership review:

1. Read [`ONE-PAGE-CONCEPT.md`](ONE-PAGE-CONCEPT.md)
2. Open the sample HTML report in [`sample-output/`](sample-output/)
3. Review [`docs/SAFETY-NOTES.md`](docs/SAFETY-NOTES.md)

For a technical review:

1. Inspect [`prototype/Invoke-InfrastructureAssuranceSnapshot.ps1`](prototype/Invoke-InfrastructureAssuranceSnapshot.ps1)
2. Run it only in mock-data mode first
3. Review the generated HTML, CSV, and JSON outputs

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\prototype\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData
```

## MVP recommendation

The most practical first production module is Patch / Reboot / Vulnerability Assurance.

It should correlate:

- Server inventory
- Owner/team
- Business criticality
- Last patch date
- Pending reboot state
- Maintenance window
- Known-exploited vulnerability exposure
- Change ticket or approved exception
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