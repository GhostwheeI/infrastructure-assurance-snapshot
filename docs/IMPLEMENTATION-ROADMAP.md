# Implementation Roadmap

This roadmap assumes a conservative public-sector or regulated-environment rollout.

## Phase 0: Review-only concept

Goal: validate the reporting model without touching production.

Deliverables:

- One-page concept
- Static sample HTML report
- Sample CSV/JSON evidence files
- Read-only prototype script with mock data

Exit criteria:

- Leadership understands the report format
- Infrastructure and Security agree the data model is useful
- No production access is required

## Phase 1: SCCM + SolarWinds Patch / Reboot / Vulnerability Assurance

Goal: produce a weekly operational risk view for Windows servers by correlating SCCM technical state with SolarWinds work/evidence records.

SCCM remains the authoritative source for patch/deployment/compliance status. SolarWinds remains the authoritative source for tickets, incidents, changes, approvals, exceptions, and work notes.

Data sources:

- SCCM server inventory
- SCCM collection membership
- SCCM update compliance status
- SCCM deployment status
- SCCM failed/unknown update state
- Pending reboot state
- SolarWinds ticket/change/incident reference
- SolarWinds assignment group / owner
- SolarWinds approval or exception status
- Criticality tier / asset owner mapping
- Vulnerability export or known-exploited vulnerability mapping

Outputs:

- Executive dashboard
- CSV infrastructure work queue
- JSON evidence file
- Top-risk action list
- Exception register
- SCCM/SolarWinds evidence-gap list

Acceptance criteria:

- At least 90% of in-scope servers are represented
- Unknown owner count is below 10%
- SCCM compliance state is visible
- Pending reboot state is visible
- Failed/unknown update state is visible
- Critical/high-risk systems are clearly prioritized
- Findings map to SolarWinds ticket/change/exception evidence where available

Kill criteria:

- Existing SCCM/SolarWinds reporting already provides the same cross-source leadership view reliably
- Server ownership data is not available or cannot be maintained
- Findings cannot be mapped to accountable owners or work records

## Phase 2: Identity Drift Sentinel

Goal: detect and report privileged-access drift across hybrid identity.

Data sources:

- Active Directory privileged groups
- Entra ID role assignments
- MFA / Conditional Access / PIM exports where approved
- Service-account inventory
- GPO baseline exports

Outputs:

- Privileged group membership diff
- Dormant privileged account list
- Password-never-expires review list
- Admin MFA/PIM coverage summary
- GPO baseline drift indicators

Acceptance criteria:

- Privileged changes are visible within 24 hours
- Dormant privileged accounts are reported
- Findings distinguish user, service, and break-glass accounts
- Reports avoid exposing unnecessary sensitive details

## Phase 3: Backup / Restore Evidence Ledger

Goal: prove recoverability, not just backup job success.

Data sources:

- Backup job exports
- Restore-test evidence
- System criticality map
- RTO/RPO targets
- Application owner mapping
- SolarWinds ticket/change/evidence references where applicable

Outputs:

- Last backup status
- Last restore-test date
- Restore-test overdue list
- RTO/RPO target vs actual
- Evidence reference or ticket link

Acceptance criteria:

- Tier 1/Tier 2 systems have restore-test status
- Missing evidence is clearly visible
- Restore tests map to owner and date

## Phase 4: Change Evidence Generator

Goal: reduce friction around CAB and audit evidence.

Inputs:

- Planned change
- Affected systems
- Risk summary
- Backout plan
- Validation steps
- SolarWinds change/ticket/evidence links

Outputs:

- CAB-ready summary
- Risk statement
- Validation checklist
- Backout checklist
- Post-change evidence packet

## Long-term direction

The mature version is not a replacement platform. It is an assurance layer that sits above authoritative systems.

The long-term goal is a repeatable weekly report that lets leadership and technical teams agree on:

- Current operational risk
- Ownership
- Exceptions
- Remediation progress
- Recovery proof
- Audit evidence