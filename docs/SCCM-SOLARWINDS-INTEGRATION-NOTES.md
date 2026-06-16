# SCCM + SolarWinds Integration Notes

## Purpose

This document describes the most practical phase-one path for Infrastructure Assurance Snapshot when an environment already uses SCCM and SolarWinds.

The goal is not to replace either platform.

The goal is to correlate:

- SCCM technical state
- SolarWinds ticket/change/incident evidence
- Asset ownership
- Business criticality
- Exception status
- Leadership-readable risk

## SCCM as authoritative technical source

SCCM / MECM should remain the source of truth for endpoint/server patch deployment and compliance state.

Useful SCCM data points:

- Device name
- Operating system
- Collection membership
- Last hardware/software inventory time
- Update compliance status
- Deployment status
- Failed update state
- Unknown update state
- Required update count
- Pending reboot status where available
- Maintenance window / collection mapping

## SolarWinds as work and evidence source

SolarWinds should remain the source for service desk, incident, change, request, or approval evidence where applicable.

Useful SolarWinds data points:

- Ticket number
- Change number
- Incident number
- Request type
- Owner or assignment group
- Status
- Approval state
- Planned maintenance window
- Exception / accepted-risk reference
- Completion notes
- Validation evidence

## Correlation model

The first production model can be simple.

| Field | Source | Purpose |
|---|---|---|
| ServerName | SCCM | Technical identity |
| OwnerTeam | SolarWinds or asset mapping | Accountability |
| Criticality | Asset mapping | Risk prioritization |
| PatchCompliance | SCCM | Technical state |
| PendingReboot | SCCM / local read-only check | Completion status |
| MaintenanceWindow | SCCM collection / SolarWinds change | Scheduling context |
| TicketOrChange | SolarWinds | Evidence and workflow |
| ExceptionStatus | SolarWinds / manual register | Accepted-risk tracking |
| RecommendedAction | Assurance logic | Operational next step |

## First useful report

A weekly report should answer:

- Which Tier 1/Tier 2 systems are noncompliant?
- Which systems are patched but still pending reboot?
- Which systems have failed/unknown deployment status?
- Which systems have no linked ticket/change evidence?
- Which exceptions are still open?
- Which risks need leadership review?

## Recommended rollout

### Step 1: Export-based proof of value

Start with CSV exports from SCCM and SolarWinds.

No direct API or database access is needed for the first proof of value.

### Step 2: Normalize fields

Normalize common fields such as:

- ServerName
- OwnerTeam
- Criticality
- ComplianceStatus
- PendingReboot
- TicketId
- ChangeId
- ExceptionStatus

### Step 3: Generate weekly report

Generate:

- HTML leadership report
- CSV infrastructure work queue
- JSON evidence file

### Step 4: Review with stakeholders

Review with Infrastructure, Security, and Change Management before any automation.

## Guardrails

- Use read-only exports first
- Do not query production databases without approval
- Do not write back to SCCM or SolarWinds from the prototype
- Do not store credentials in scripts
- Treat server names and vulnerability findings as sensitive
- Keep remediation workflows separate from assurance reporting

## Best first win

The best first win is identifying systems that are technically patched but not operationally complete because a reboot, validation, ticket closure, or exception review is still pending.

That gap is common, measurable, and directly useful to both administrators and leadership.