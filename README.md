# Infrastructure Assurance Snapshot Demo
A read-only prototype that turns SCCM-style patch/deployment state and SolarWinds-style ticket/change evidence into a leadership-ready infrastructure assurance report.

[![Watch the walkthrough](https://i.postimg.cc/Qx8V742d/Capture.png)](https://www.youtube.com/watch?v=bXrC129iTeo)

A read-only prototype that turns SCCM-style patch/deployment state and SolarWinds-style ticket/change evidence into a leadership-ready infrastructure assurance report.

The point is not to replace SCCM, SolarWinds, monitoring, vulnerability scanning, backup tooling, or SIEM. The point is to sit above those tools and answer the operational questions leadership needs answered.

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

![Infrastructure Assurance Snapshot Dashboard](https://i.postimg.cc/NjWgdpzd/Infrastructure-Assurance-Snapshot.jpg)

```text
Infrastructure Assurance Snapshot log
Started: 2026-06-16T18:45:45.7531990-04:00
OutputPath: C:\Users\Ghostwheel\AppData\Local\Temp\InfrastructureAssuranceSnapshot\Run-20260616-184545
MockScope: Default
DemoPaceSeconds: 1

[2026-06-16 18:45:45] [STEP] Infrastructure Assurance Snapshot
[2026-06-16 18:45:45] [INFO] Read-only SCCM + SolarWinds assurance prototype
[2026-06-16 18:45:45] [INFO] Output: C:\Users\Ghostwheel\AppData\Local\Temp\InfrastructureAssuranceSnapshot\Run-20260616-184545
[2026-06-16 18:45:45] [INFO] Demo pacing: 1 second(s) between major sections
[2026-06-16 18:45:45] [STEP] [1/5] Dependency preflight
[2026-06-16 18:45:45] [INFO]   Grouped checks before report generation. Optional integrations are not required for mock mode.
[2026-06-16 18:45:45] [INFO]   Install policy:    Default deny; no downloads or installs are performed
[2026-06-16 18:45:45] [INFO]   Mock mode:         Missing optional modules are skipped and documented
[2026-06-16 18:45:45] [INFO]   Required runtime
[2026-06-16 18:45:45] [OK]   [OK]   PowerShell Runtime               PowerShell 7.6.1
[2026-06-16 18:45:45] [OK]   [OK]   JSON Serialization               available
[2026-06-16 18:45:45] [OK]   [OK]   CSV Export                       available
[2026-06-16 18:45:45] [INFO]   Optional future integrations
[2026-06-16 18:45:45] [SKIP]   [SKIP] SCCM / MECM Module               not installed; optional for mock run
[2026-06-16 18:45:45] [SKIP]   [SKIP] SolarWinds SWIS Module           not installed; optional for mock run
[2026-06-16 18:45:45] [SKIP]   [SKIP] Microsoft Graph Auth             not installed; optional for mock run
[2026-06-16 18:45:45] [OK]   [OK]   Preflight summary                required 3/3 ok; optional skipped 3/3
[2026-06-16 18:45:45] [WARN]   [WARN] Optional integrations            skipped for mock run; production notes cover approved setup path
[2026-06-16 18:45:45] [PLAN]   [PLAN] Mock dependency plan             C:\Users\Ghostwheel\AppData\Local\Temp\InfrastructureAssuranceSnapshot\Run-20260616-184545\Dependency-Plan.txt
[2026-06-16 18:45:46] [STEP] [2/5] Scoped mock targeting
[2026-06-16 18:45:46] [INFO]   Displays what is configurable without implying full-environment access.
[2026-06-16 18:45:46] [INFO]   Description:       Default scoped review for a balanced infrastructure assurance snapshot
[2026-06-16 18:45:46] [INFO]   Scope:             Default
[2026-06-16 18:45:46] [INFO]   Install policy:    Auto-install denied by default
[2026-06-16 18:45:46] [INFO]   Mode:              Mock only
[2026-06-16 18:45:46] [INFO]   SCCM collections
[2026-06-16 18:45:46] [INFO]     - Windows Servers - Production
[2026-06-16 18:45:46] [INFO]     - Domain Controllers - Patch Validation
[2026-06-16 18:45:46] [INFO]     - Tier 1 Application Servers
[2026-06-16 18:45:46] [INFO]   SolarWinds queues
[2026-06-16 18:45:46] [INFO]     - Infrastructure Change Queue
[2026-06-16 18:45:46] [INFO]     - Application/Data Change Queue
[2026-06-16 18:45:46] [INFO]     - Incident Follow-up Queue
[2026-06-16 18:45:46] [INFO]   Report sections
[2026-06-16 18:45:47] [INFO]     - Patch/Reboot Risk
[2026-06-16 18:45:47] [INFO]     - SCCM Deployment State
[2026-06-16 18:45:47] [INFO]     - SolarWinds Evidence
[2026-06-16 18:45:47] [INFO]     - Exceptions
[2026-06-16 18:45:47] [INFO]     - Recommended Actions
[2026-06-16 18:45:48] [STEP] [3/5] Mock data load
[2026-06-16 18:45:48] [INFO]   Loading scoped SCCM/SolarWinds sample rows.
[2026-06-16 18:45:48] [INFO]   Live systems:      none contacted
[2026-06-16 18:45:48] [INFO]   Source mode:       local mock data only
[2026-06-16 18:45:48] [INFO]   Rows loaded:       6 mock infrastructure records
[2026-06-16 18:45:49] [STEP] [4/5] Artifact generation
[2026-06-16 18:45:49] [INFO]   Writing local report, work queue, evidence, and log files.
[2026-06-16 18:45:49] [OK]   [OK]   HTML report                      C:\Users\Ghostwheel\AppData\Local\Temp\InfrastructureAssuranceSnapshot\Run-20260616-184545\Infrastructure-Assurance-Snapshot.html
[2026-06-16 18:45:49] [OK]   [OK]   CSV work queue                   C:\Users\Ghostwheel\AppData\Local\Temp\InfrastructureAssuranceSnapshot\Run-20260616-184545\Infrastructure-Assurance-Servers.csv
[2026-06-16 18:45:49] [OK]   [OK]   JSON evidence                    C:\Users\Ghostwheel\AppData\Local\Temp\InfrastructureAssuranceSnapshot\Run-20260616-184545\Infrastructure-Assurance-Evidence.json
[2026-06-16 18:45:49] [OK]   [OK]   Run log                          C:\Users\Ghostwheel\AppData\Local\Temp\InfrastructureAssuranceSnapshot\Run-20260616-184545\Infrastructure-Assurance.log
[2026-06-16 18:45:49] [PLAN]   [PLAN] Dependency plan                  C:\Users\Ghostwheel\AppData\Local\Temp\InfrastructureAssuranceSnapshot\Run-20260616-184545\Dependency-Plan.txt
[2026-06-16 18:45:50] [STEP] [5/5] Complete
[2026-06-16 18:45:50] [INFO]   No live systems were contacted. No changes were made.
[2026-06-16 18:45:50] [INFO]   Next review:       open the generated HTML report and CSV work queue
[2026-06-16 18:45:50] [INFO]   Result:            complete
```


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
