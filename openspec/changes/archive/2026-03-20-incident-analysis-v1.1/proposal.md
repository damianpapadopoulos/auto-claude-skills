# Proposal: Incident Analysis v1.1 — One-Hop Trace Correlation

## Problem Statement
The v1.0 incident-analysis skill investigated single-service incidents only. In distributed systems, the root cause often lives in an upstream or downstream service. The SKILL.md had a placeholder at Stage 2, Step 4 acknowledging this gap.

## Proposed Solution
Bounded, evidence-gated, one-hop trace correlation: Service A → Service B, Tier 1 MCP only. The agent may autonomously correlate one additional service when explicit failure evidence or a timeout cascade is present in span data, then must stop and synthesize.

## Out of Scope
- Multi-hop correlation (3+ services) — deferred to v1.2+
- `search_traces` usage — explicitly excluded, retained for future versions
- Tier 2 (gcloud CLI) trace correlation — Step 4 skipped entirely in Tier 2
- Stage 3 (POSTMORTEM) changes — permalink requirements deferred to v1.2
