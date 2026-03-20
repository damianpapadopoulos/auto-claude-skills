# Incident Analysis v1.1: Autonomous Trace Correlation

**Date:** 2026-03-20
**Status:** Draft
**Phase:** DESIGN
**Parent:** `docs/superpowers/specs/2026-03-19-incident-analysis-design.md` (v1.0)

## Problem Statement

The v1.0 incident-analysis skill investigates single-service incidents. In distributed systems, the root cause often lives in an upstream or downstream service. The v1.0 SKILL.md has a placeholder at Stage 2, Step 4 (line 110) that acknowledges this gap but defers to v1.1.

## Scope

Replace the placeholder at `skills/incident-analysis/SKILL.md` line 110 with a bounded, evidence-gated, one-hop trace correlation workflow. Tier 1 MCP only — no Tier 2 equivalent. Stage 3 (POSTMORTEM) is NOT modified in v1.1 — permalink requirements deferred to v1.2.

## Design: Strict One-Hop Trace Correlation

### Core Rule

The agent may correlate Service A (initially failing) → Service B (one upstream/downstream service) autonomously, then MUST stop and synthesize. No second hop, no best-guess recursion.

### Trigger Condition

The hop is triggered ONLY when ALL of these are true:
1. Tier 1 MCP tools are available (`get_trace`, `list_log_entries`)
2. A `trace_id` is present in the initial failing log entries from Service A
3. The trace contains a span from a different service (Service B) that meets EITHER:
   - **Explicit failure path:** span status != OK, HTTP >= 500, or exception in span events
   - **Timeout cascade path:** Service A failed with timeout/deadline-exceeded AND Service B's span duration is >= 80% of the trace's longest sequential path duration (see Error Evidence Criteria below)

**No `trace_id` = no hop.** The `search_traces` tool is NOT used in v1.1. If the failing log entries do not contain a `trace` field, Step 4 is skipped entirely. There is no fallback search.

### Trace ID and Project Extraction

Extract from the log entry's `trace` field (format: `projects/PROJECT_ID/traces/TRACE_ID`):
- **`TRACE_ID`**: The raw trace identifier (after stripping prefix) — used for `get_trace`
- **`PROJECT_ID`**: The GCP project of Service A — used for `get_trace`

**Cross-project rule:**
- **`get_trace`**: Use Service A's `PROJECT_ID` (traces are stored in the project that owns the trace).
- **Service B `list_log_entries`**: Use Service B's project ID (extractable from the span's resource labels). If Service B is in the same project as Service A, use the same `PROJECT_ID`.
- **LQL `trace=` filter for Service B**: The `trace` field in Cloud Logging uses the fully-qualified form `projects/SERVICE_B_PROJECT_ID/traces/TRACE_ID`. When querying Service B's logs, construct the filter as `trace="projects/<Service B project>/traces/<TRACE_ID>"` — do NOT reuse Service A's `projects/PROJECT_ID/traces/...` prefix if projects differ.
- If Service B's project ID cannot be determined from span data, STOP and ask the user.

### Representative Trace Selection

If Stage 2 logs contain multiple failing requests (>1, e.g., repeated 500s), the agent MUST select one exemplar trace before entering Step 4:
- Prefer the most recent failure from the dominant error group (most frequent error pattern)
- If error groups are unclear, select the most recent failure with a `trace` field present
- Analyze only this single exemplar trace in Step 4 — do not attempt to correlate multiple traces

### Error Evidence Criteria (Span-Specific)

Evidence that justifies the autonomous hop (MUST be present in Service B's span data):

**Explicit failure (any one sufficient):**
- Span status code != OK (gRPC error)
- HTTP status >= 500 in span attributes
- Exception stack trace in span events

**Timeout cascade (all conditions required):**
- Service A failed with an explicit timeout/deadline-exceeded error
- Service B's span duration consumes >= 80% of the trace's longest sequential path duration. **Operational definition:** the longest sequential path is the root span's duration (start to end). Service B's share = `(Service B span end - Service B span start) / (root span end - root span start)`.
- No other non-Service-A span consumes >= 40% of the root span duration (i.e., Service B is the clear dominant contributor, not one of several)

**Latency-only spans (slow but no error/timeout evidence) do NOT justify the hop.**

If the evidence is ambiguous or borderline, do NOT hop — present the trace timeline and let the user decide.

### Workflow

```
1. Select representative trace:
   - If multiple failing requests exist, pick one exemplar from the
     dominant error group (most frequent pattern) or the most recent failure.
   - Extract trace_id and project_id from the exemplar log entry's
     trace field (format: projects/PROJECT_ID/traces/TRACE_ID).

2. Call get_trace(trace_id, project_id) to retrieve the span timeline.
   - Do NOT use search_traces in v1.1. No trace field = no hop.

3. Inspect spans for cross-service boundaries:
   a. If all spans are within Service A only:
      → Skip hop. Proceed to Stage 2, Step 5 with single-service evidence.
   b. If exactly one other service (Service B) meets EITHER evidence path:
      - Explicit failure: span status != OK, HTTP >= 500, or exception
      - Timeout cascade: Service A failed with timeout/deadline-exceeded
        AND Service B span duration >= 80% of root span duration
        AND no other non-Service-A span >= 40% of root span duration
      → Execute the hop (continue to step 4).
   c. If multiple services meet evidence criteria, OR the trace fans out
      to 3+ services with any failure signals:
      → Present trace timeline to user. Do NOT autonomously choose.
      → Let user specify which service to investigate.
   d. If other services appear but none meet either evidence path:
      → Skip hop. Note the services in synthesis for user awareness.

4. Query Service B logs using list_log_entries:
   - project_id: Service B's project ID (extracted from span resource
     labels). Falls back to Service A's PROJECT_ID if same project.
   - filter: Scoped to same trace_id AND Service B's concrete resource
     labels (resource.type, resource.labels.service_name or equivalent)
   - time range: Service B span start time minus 1 minute to span end
     time plus 1 minute (narrow buffer around the span)
   - page_size: <= 50 entries
   - STRICT CONSTRAINT: Do not execute a second hop. Do not follow
     the trace into a third service, even if additional spans appear.
   - If Service B's identity (resource labels) is ambiguous from the
     span data, STOP and present the trace to the user instead.

5. Synthesize the causal path only:
   - Map the failure chain from Service B → Service A (causal path)
   - Do NOT dump the full trace tree — include only spans on the
     path linking Service B's failure to Service A's error
   - Present both services' log evidence in chronological order
   - Feed this synthesized causal timeline into Stage 2, Step 5
     (root cause hypothesis)
```

### What Does NOT Change

- Stage 2, Step 5 (root cause hypothesis) — uses synthesized timeline, unchanged
- Stage 2, Step 6 (flight plan) — unchanged
- Stage 2, Step 7 (context discipline) — unchanged
- Stage 3 (POSTMORTEM) — unchanged in v1.1 (permalink requirements deferred to v1.2)
- Behavioral constraints — all 4 remain active (HITL, scope restriction, temp-file, context discipline)
- Tier 2 behavior — Step 4 is skipped entirely in Tier 2 (gcloud CLI). No Tier 2 trace correlation.

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `skills/incident-analysis/SKILL.md` | **Modify** | Replace Step 4 placeholder (line 110-116, including trailing blank line) with full one-hop correlation workflow. Remove `search_traces` from Step 4 usage. Note in Tier 1 MCP Tool Reference table that `search_traces` is not used in Step 4 (retained for future v1.2+ use only). |
| `docs/superpowers/specs/2026-03-19-incident-analysis-design.md` | **Modify** | Replace Stage 2 Step 4 stub with the full bounded one-hop workflow prose, remove "[v1.1]" marker |

No routing, hook, or phase doc changes needed. Verification is phased: (1) structured document review at ship time (trace through SKILL.md decision paths against each scenario), then (2) live prompt testing when the skill is first exercised on a real incident with Tier 1 MCP tools and trace data available. Automated routing tests are not applicable — the behavior lives in prompt logic.

## Test Plan

These are behavioral verification scenarios. Since the behavior lives in a SKILL.md (not hook code), verification is phased: (1) structured document review at ship time — trace through SKILL.md decision paths for each scenario, (2) live prompt testing when the skill is first exercised on a real incident with Tier 1 MCP tools and trace data. Automated routing tests are not applicable.

| Scenario | Expected Behavior |
|----------|-------------------|
| Clear downstream error span (status != OK) | One scoped `list_log_entries` query for Service B, then stop and synthesize causal path |
| Clear upstream timeout cascade (Service B span >= 80% critical path) | One scoped `list_log_entries` query for Service B, then stop and synthesize |
| Ambiguous trace with multiple candidate services | No autonomous hop; present trace timeline, let user choose |
| Trace fans out to 3+ services with failure signals | No autonomous hop; present trace timeline, let user choose |
| No trace ID in failing logs (no `trace` field) | Skip Step 4 entirely, proceed to Stage 2, Step 5 |
| Trace ID present but all spans within Service A | Skip hop, proceed to Stage 2, Step 5 with single-service evidence |
| Service B logs return no useful signal | Note in synthesis, proceed to Stage 2, Step 5 |
| Service B identity ambiguous from span data | Stop and present trace to user instead of guessing |
| Multiple failing requests in Stage 2 logs | Select one exemplar trace from dominant error group before hop |
| Tier 2 (gcloud CLI) active, no MCP | Step 4 skipped entirely, proceed directly to Stage 2, Step 5 |

## Assumptions

- "One hop" means one additional service beyond the initially failing service
- Latency-only spans without explicit failure/timeout evidence do not justify the autonomous hop
- `get_trace` is the only trace tool used in v1.1 (direct lookup by trace ID); `search_traces` is explicitly excluded from v1.1 and retained in the MCP tool table only for future versions
- The timeout cascade exception requires >= 80% of root span duration, with no other non-Service-A span >= 40%
- `get_trace` uses Service A's project ID; Service B `list_log_entries` uses Service B's project ID (may differ in cross-project setups; see Cross-project rule)
- If the agent cannot deterministically construct the Service B query (ambiguous resource labels, unclear service identity), it MUST stop and ask the user

## Decision

Design derived from v1.0 spec evolution path, refined through brainstorming with input from Palladius cloud-build-investigation bounded-correlation pattern and postmortem-generator synthesis-first posture. Key refinement: removed `search_traces` fallback, added deterministic query construction requirements, added representative trace selection, tightened timeout evidence to measurable >= 80% critical-path threshold.
