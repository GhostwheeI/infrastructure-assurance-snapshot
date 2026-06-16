# Infrastructure Assurance Snapshot Demo
A read-only prototype that turns SCCM-style patch/deployment state and SolarWinds-style ticket/change evidence into a leadership-ready infrastructure assurance report.

[![Watch the walkthrough](https://i.postimg.cc/Qx8V742d/Capture.png)](https://www.youtube.com/watch?v=bXrC129iTeo)

A read-only prototype that turns SCCM-style patch/deployment state and SolarWinds-style ticket/change evidence into a leadership-ready infrastructure assurance report.

The point is not to replace SCCM, SolarWinds, monitoring, vulnerability scanning, backup tooling, or SIEM. The point is to sit above those tools and answer the operational questions leadership needs answered:

> What is exposed, what is overdue, who owns it, what ticket/change record proves the work, and what still needs a decision?

## Practical phase-one fit

The strongest first use case is **SCCM + SolarWinds patch / reboot / vulnerability assurance**.

SCCM stays the technical source for inventory, compliance, deployment state, failed updates, and pending reboot status.

SolarWinds stays the evidence source for tickets, incidents, changes, approvals, exceptions, and validation notes.

This prototype shows how those signals could be combined into:

- an HTML leadership report
- a CSV infrastructure work queue
- a JSON evidence file
- a run log
- a dependency plan when optional tools are missing

## Sample output

The [`sample-output/`](sample-output/) folder includes static examples of the artifacts the prototype generates during a mock run.

| Artifact | Purpose |
|---|---|
| [`Infrastructure-Assurance-Snapshot-SAMPLE.html`](sample-output/Infrastructure-Assurance-Snapshot-SAMPLE.html) | Leadership-readable snapshot showing patch posture, pending reboot exposure, high-risk systems, SolarWinds evidence references, and recommended next actions. |
| [`Infrastructure-Assurance-Servers-SAMPLE.csv`](sample-output/Infrastructure-Assurance-Servers-SAMPLE.csv) | Administrator-facing work queue that can be filtered by server, owner, criticality, compliance state, deployment status, pending reboot, exception status, and risk. |
| [`Infrastructure-Assurance-Evidence-SAMPLE.json`](sample-output/Infrastructure-Assurance-Evidence-SAMPLE.json) | Structured evidence output that preserves run context, scope, safety posture, summary counts, and review questions for audit or change-review use. |

These files are mock artifacts only. They are included so the report format and evidence model can be reviewed without running the script or touching a live environment.

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

## Prototype workflow

The script is dependency-first and grouped for easier review. Console output is timestamped, but it is structured so the run does not turn into a wall of unrelated log lines.

The walkthrough is organized into five sections:

1. Dependency preflight
2. Scoped mock targeting
3. Mock data load
4. Artifact generation
5. Completion summary

The dependency preflight prints required checks, optional checks, summary, warnings, and mock install-plan notes together before report generation starts.

## Running the prototype

Focused Tier 1 demo:

```powershell
.\prototype\Invoke-InfrastructureAssuranceSnapshot.ps1 -MockData -MockScope Tier1Only -MockDependencyInstall -OpenOutputFolder Ask
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

Auto-install is denied by default. If `-MockDependencyInstall` is used, the script writes a plan showing what would be needed later, but does not install, import, download, or change anything.

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

## Status

Prototype / concept stage. The included data is mock data for demonstration only.
