# Proposal: Incident Trend Analyzer

## Problem Statement
The incident-analysis skill (v1.0-v1.2) generates structured postmortems in `docs/postmortems/` but provides no tooling to analyze trends across accumulated postmortems. Recurring failure modes go unnoticed, trigger patterns stay invisible, and MTTR/MTTD trends are never surfaced.

## Proposed Solution
A standalone skill (`incident-trend-analyzer`) that reads canonical postmortems, extracts normalized incident records with confidence-aware fields, and outputs recurrence patterns, trigger distributions, and timing metrics. Terminal-first output with optional persistence to `docs/postmortems/trends/`.

## Out of Scope
- Proactive advisory during postmortem generation (v2.1+)
- Hand-written postmortem compatibility (v2.2+)
- Action-item completion tracking (v2.1+)
- Git history / issue tracker correlation
- Backend-agnostic support (Datadog, Splunk — v3.0)
- Helper scripts
