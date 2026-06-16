# Infrastructure Assurance Snapshot

A read-only prototype that turns SCCM-style patch/deployment state and SolarWinds-style ticket/change evidence into a leadership-ready infrastructure assurance report.

The point is not to replace SCCM, SolarWinds, monitoring, vulnerability scanning, backup tooling, or SIEM. The point is to sit above existing tools and answer the operational questions leadership actually needs answered:

> What is exposed, what is overdue, who owns it, what ticket/change record proves the work, and what still needs a decision?

## Practical phase-one fit

The strongest first use case is **SCCM + SolarWinds patch / reboot / vulnerability assurance**.

SCCM remains the technical source for inventory, compliance, deployment state, failed updates, and pending reboot status. SolarWinds remains the evidence source for tickets, incidents, changes, approvals, exceptions, and validation notes.

This prototype demonstrates how those signals could be combined into:

- an HTML leadership report
- a CSV infrastructure work queue
- a JSON evidence file
- a run log
- a dependency plan when optional tools are missing

## Demo video

GitHub Markdown does not support direct YouTube iframe embeds. After the walkthrough is uploaded, replace `REPLACE_WITH_VIDEO_ID` with the YouTube video ID:

[![Watch the walkthrough](https://img.youtube.com/vi/REPLACE_WITH_VIDEO_ID/maxresdefault.jpg)](https://www.youtube.com/watch?v=REPLACE_WITH_VIDEO_ID)

## Safe-by-default behavior

The prototype is intentionally conservative.

- Read-only
- Mock-data mode only for now
- No remediation
- No credential storage
- No registry writes
- No AD writes
- No service restarts
- No real dependency downloads or installs
- Output defaults to the native OS temp directory
- Each run creates its own timestamped output folder

By default, artifacts are written under a temp path like:

```text
%TEMP%\InfrastructureAssuranceSnapshot\Run-yyyyMMdd-HHmmss\
```

That avoids accidental output under `C:\Windows\System32` when PowerShell is launched elevated.

## Prototype workflow

The script is dependency-first and grouped for easy review:

1. Create a temp-based run folder and log file
2. Run one grouped dependency preflight section
3. Show configurable mock targeting scope
4. Load mock SCCM + SolarWinds rows
5. Generate HTML, CSV, JSON, and log artifacts
6. Ask whether to open the output folder

The dependency preflight prints all required checks, optional checks, warnings, and mock install-plan notes together before the report work begins.

## Configurable mock targeting

The run displays a YAML-style mock targeting block so it is clear the concept is scoped and configurable, not blindly targeting an entire environment.

Available mock scopes:

```text
Default
PatchOnly
Tier1Only
IdentityAndRecoveryPreview
```

Example of what the script displays:

```yaml
mock_targeting:
  scope_name: Default
  data_mode: Mock only
  install_policy: Auto-install denied by default
  sccm_collections:
    - All Windows Servers - Production
    - Domain Controllers
    - Tier 1 Application Servers
  solarwinds_queues:
    - Infrastructure Change
    - Application/Data Change
    - End User Services Incidents
  report_sections:
    - Patch/Reboot Risk
    - SCCM Deployment State
    - SolarWinds Evidence
    - Exceptions
    - Recommended Actions
```

## Running the prototype

Best command for a short walkthrough video:

```powershell
.\prototype\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData -MockScope Default -MockDependencyInstall -DemoPaceSeconds 1 -OpenOutputFolder Ask
```

Non-interactive review:

```powershell
.\prototype\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData -MockScope Default -MockDependencyInstall -OpenOutputFolder No
```

Focused Tier 1 demo:

```powershell
.\prototype\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData -MockScope Tier1Only -MockDependencyInstall -DemoPaceSeconds 1 -OpenOutputFolder Ask
```

## Dependency behavior

Required for mock-data report generation:

- PowerShell 5.1+
- `ConvertTo-Json`
- `Export-Csv`
- local file write access to the output directory

Optional future integration checks:

- SCCM / MECM `ConfigurationManager` module
- SolarWinds `SwisPowerShell` module
- Microsoft Graph authentication module

Auto-install is denied by default. If `-MockDependencyInstall` is used, the script writes a plan showing what would be needed later, but performs no install, import, download, or system change.

## Production notes

A real implementation should start export-first and read-only before any direct API/module integrations are considered.

See [`docs/PRODUCTION-NOTES.md`](docs/PRODUCTION-NOTES.md) for recommended production boundaries, credential handling, access model, and review checks.

## Code quality posture

The script is intentionally simple rather than overengineered.

It uses:

- strict mode
- stop-on-error behavior
- grouped dependency preflight
- default-deny install posture
- temp-based output
- explicit mock targeting
- local report/evidence/log artifacts
- HTML encoding before report rendering

Before any production use, review with normal PowerShell standards and run PSScriptAnalyzer:

```powershell
Invoke-ScriptAnalyzer -Path .\prototype\Invoke-InfrastructureAssuranceSnapshot.ps1
```

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
   ├─ PRODUCTION-NOTES.md
   ├─ SCCM-SOLARWINDS-INTEGRATION-NOTES.md
   └─ IMPLEMENTATION-ROADMAP.md
```

## MVP recommendation

The first production version should start with export-based correlation before direct integrations:

- SCCM device/server inventory
- SCCM update compliance state
- SCCM deployment status
- pending reboot state
- owner/team
- criticality tier
- SolarWinds ticket/change/incident reference
- approved exception or accepted-risk reference
- recommended next action

That creates a direct operational work queue for infrastructure teams and a clean risk view for leadership.

## Status

Prototype / concept stage. The included data is mock data for demonstration only.