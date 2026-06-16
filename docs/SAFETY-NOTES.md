# Safety Notes

This repository is intentionally designed for safe review before any production use.

## Default posture

The prototype is read-only and evidence-oriented.

It should not be treated as a remediation tool, deployment tool, privileged scanner, or production automation platform.

## Current prototype guarantees

The included PowerShell prototype is designed to:

- Generate reports locally
- Run with mock data
- Avoid credential storage
- Avoid production write operations
- Avoid AD, registry, service, firewall, or patch-state changes
- Avoid automatic remediation
- Avoid external dependencies

## What should happen before production use

Before connecting this concept to real systems, an organization should review:

- Approved data sources
- Required access level
- Least-privilege read permissions
- Data retention expectations
- Report distribution rules
- Sensitive asset naming rules
- Change-management requirements
- Security review requirements
- Logging and evidence-handling requirements

## Recommended production guardrails

- Start with exports or mock data before direct integrations
- Use read-only service accounts where possible
- Avoid storing secrets in scripts or config files
- Keep remediation workflows separate from reporting
- Require review before emailing or publishing reports
- Treat server names, vulnerability data, and identity findings as sensitive
- Version report logic so findings are reproducible

## Out-of-scope by design

This prototype does not:

- Patch systems
- Reboot systems
- Change account membership
- Disable users
- Modify GPOs
- Start restore jobs
- Open or close change tickets
- Push firewall or endpoint policy
- Replace SIEM/monitoring/backup/ITSM tools

## Production principle

Visibility first. Evidence second. Automation later.

A reporting layer should become trusted before it is used to drive automated action.