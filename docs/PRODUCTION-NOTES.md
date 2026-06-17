# Production Notes

This repository is a sanitized mock-data prototype. A production version should start conservatively and prove value before adding direct integrations.

## Recommended production path

Start with export-based correlation, not live API automation.

1. Export approved SCCM / MECM inventory, compliance, deployment, and pending reboot data.
2. Export approved SolarWinds ticket, incident, change, exception, and validation evidence.
3. Normalize server names, owner fields, criticality tiers, and maintenance windows.
4. Generate read-only assurance reports.
5. Review output with Infrastructure, Security, Change Management, and leadership.
6. Only then consider direct read-only API/module integrations.

## Integration boundaries

This should remain an assurance/reporting layer above existing tools.

It should not replace:

- SCCM / MECM
- SolarWinds
- vulnerability scanners
- monitoring platforms
- backup platforms
- SIEM tooling
- ITSM/change systems

## Current prototype guarantees

The included PowerShell prototype is designed to:

- generate reports locally
- run with mock data
- avoid credential storage
- avoid production write operations
- avoid AD, Entra ID, registry, service, firewall, ticket, or patch-state changes
- avoid automatic remediation
- avoid real dependency downloads or installs

## Credential handling

The prototype stores no credentials and performs no live authentication.

If this were expanded for production, credentials and secrets should use an approved enterprise method such as:

- managed service accounts where appropriate
- least-privilege read-only accounts
- approved credential vaulting
- Microsoft.PowerShell.SecretManagement or an organization-approved equivalent

Do not store credentials in the script, local JSON files, CSV files, environment dumps, or GitHub.

## Access model

Production access should be read-only first.

Suggested minimum permissions:

- read SCCM device inventory and deployment/compliance status
- read pending reboot/compliance exports or approved views
- read SolarWinds tickets, changes, incidents, and exception metadata
- read owner/criticality mapping from an approved source

The script should not:

- deploy patches
- restart servers
- modify AD or Entra ID
- modify registry or GPO state
- modify firewall rules
- close tickets
- approve changes
- write back to SCCM or SolarWinds

## Data handling

Treat server names, vulnerability findings, identity findings, exception records, and ticket details as sensitive.

Before production use, an organization should define:

- approved data sources
- required access level
- data retention expectations
- report distribution rules
- sensitive asset naming rules
- change-management requirements
- security review requirements
- logging and evidence-handling requirements

The sample output in this repository uses neutral hostnames and sanitized paths for public review.

## Code quality checks

Before production use, run the script through normal review steps:

```powershell
Invoke-ScriptAnalyzer -Path .\prototype\Invoke-InfrastructureAssuranceSnapshot.ps1
```

Expected review focus:

- parameter validation
- error handling
- logging behavior
- no hardcoded secrets
- no destructive commands
- clear output path handling
- HTML encoding for report output
- explicit handling of missing optional dependencies
- repeatable generated artifacts

## Operational posture

The intended value is not clever automation. The value is operational clarity:

- what is exposed
- what is overdue
- who owns it
- what evidence exists
- what exception exists
- what needs a decision

That keeps the project aligned with Systems Administration work instead of turning it into a software platform.

## Production principle

Visibility first. Evidence second. Automation later.

A reporting layer should become trusted before it is used to drive automated action.