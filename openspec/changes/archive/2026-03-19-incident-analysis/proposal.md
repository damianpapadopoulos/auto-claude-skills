# Proposal: Incident Analysis Skill

## Problem Statement
The auto-claude-skills plugin had routing entries for GCP observability (`gcp-observability`, `gke`, `cloud-run`) that fired during DEBUG and SHIP phases, but they emitted only generic hints ("If observability MCP tools are available..."). There was no skill teaching Claude how to investigate production incidents, generate structured postmortems, or safely interact with production systems.

The unified-context-stack's testing-and-debug phase covered Historical Truth, External Truth, and Internal Truth, but had no Observability Truth tier for production log analysis.

## Proposed Solution
A tiered incident-analysis skill ("Brain vs Hands" separation):
- **Brain** (`skills/incident-analysis/SKILL.md`): 3-stage state machine (MITIGATE → INVESTIGATE → POSTMORTEM) with 4 behavioral constraints (HITL gate, scope restriction, temp-file LQL pattern, context discipline)
- **Hands**: Tiered execution — Tier 1 MCP (`@google-cloud/observability-mcp`), Tier 2 gcloud CLI via Bash, Tier 3 guidance-only
- **Routing**: Updated `gcp-observability` hint + new `incident-analysis` domain skill entry (priority 20, DEBUG/SHIP phases)
- **Phase integration**: Observability Truth tier added to testing-and-debug.md
- **Detection**: gcloud availability emitted at session start

## Out of Scope
- Multi-service trace correlation (deferred to v1.1, gated behind Tier 1 MCP)
- Incident trend analysis / postmortem aggregation (v2.0)
- PR friction logging (v2.1)
- Jira/Linear auto-ticket creation for action items
- Alert/PagerDuty integration
- Proactive log monitoring
- Non-GCP backends (Datadog, Grafana, Splunk)
