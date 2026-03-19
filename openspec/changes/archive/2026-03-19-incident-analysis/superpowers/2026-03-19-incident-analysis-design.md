# Incident Analysis: Tiered Log Investigation & Structured Postmortem Generation

**Date:** 2026-03-19
**Status:** Draft
**Phase:** DESIGN

## Problem Statement

The auto-claude-skills plugin has routing entries for GCP observability (`gcp-observability`, `gke`, `cloud-run`) that fire during DEBUG and SHIP phases, but they emit only generic hints ("If observability MCP tools are available..."). There is no skill that teaches Claude:

1. **How to investigate production incidents** — what to query, how to narrow scope, how to correlate signals
2. **How to generate structured postmortems** — timeline, root cause, action items in a consistent format
3. **How to safely interact with production systems** — guardrails against unbounded queries, unsanctioned mutations, and context window exhaustion

The unified-context-stack's `testing-and-debug.md` phase covers Historical Truth (past solutions), External Truth (library issues), and Internal Truth (dependency tracing), but has no Observability Truth tier for production log analysis.

## Core Insight: Logs Are Not Security Scans

The initial temptation was to follow the security-scanner pattern (pure Skill+Bash). But log analysis has a fundamentally different interaction model:

| Dimension | Security scanning | Log analysis / Incident debugging |
|-----------|-------------------|-----------------------------------|
| Query complexity | Simple (`semgrep scan .`) | Complex (LQL with resource types, severity filters, regex, timestamps) |
| Result volume | Bounded (findings list) | Unbounded (0 to 100k+ entries) |
| Iteration pattern | Scan → fix → rescan | Query → refine → requery → correlate → timeline |
| Cross-entity correlation | No | Yes (trace IDs across services) |
| Shell escaping risk | Low (simple flags) | High (LQL quotes, regex, nested filters) |

This means the execution tier must be **tool-aware**, using the best available interface rather than forcing all interactions through raw Bash.

## Recommended Approach: Tiered Skill (Brain + Hands Separation)

### The Brain (Skill)

`skills/incident-analysis/SKILL.md` — owns the methodology, behavioral constraints, LQL reference patterns, and postmortem templates. This is where the SRE intelligence lives.

### The Hands (Tiered Execution)

The skill detects available tools at runtime and uses the best available tier:

| Tier | Tool | When Available | Advantage |
|------|------|----------------|-----------|
| 1 | `@google-cloud/observability-mcp` | MCP server configured | Structured calls, transparent pagination, multi-tool (logs + traces + metrics + errors) |
| 2 | `gcloud` CLI via Bash | `gcloud` installed | Available everywhere, temp-file pattern for LQL safety |
| 3 | Guidance-only | Neither available | Manual Cloud Console instructions |

### Why MCP Is Justified for Tier 1 (Despite Precedent)

The security-scanner design debate (2026-03-17) correctly rejected MCP for semgrep/trivy because those are simple, stateless, bounded CLI invocations. Log analysis differs:

1. **The MCP server is not wrapping a CLI tool** — `@google-cloud/observability-mcp` calls the Cloud Logging API directly with proper pagination and streaming. It is not a `gcloud` wrapper.
2. **LQL syntax is error-prone in Bash** — complex filters with quotes, regex, and resource types cause frequent escaping failures when constructed inline.
3. **It bundles logs + metrics + traces + errors** in one server — Tier 2 requires 4-5 different `gcloud` subcommands with different output formats.
4. **It is maintained by Google** — zero maintenance cost.
5. **Auth is handled via ADC** — same `gcloud auth` the developer already has.

The MCP vs Bash feedback memory ("Do not propose MCP wrappers for stateless CLI tools") still holds. This is not a stateless CLI wrapper — it's a purpose-built API client for an interactive, multi-query investigation workflow. The state lives in Claude's context (the investigation thread), but the tool interface quality matters for reliability.

**Tier 2 remains essential** for developers who don't have the MCP server configured. The skill must work well in both tiers.

## Architecture

```
Routing Layer (existing infrastructure)
  default-triggers.json: updated gcp-observability entry
  + triggers: incident, postmortem, outage, root.cause, error.spike
  Phases: DEBUG, SHIP
         |
         v
Brain: skills/incident-analysis/SKILL.md
  State Machine (stages, not SDLC phases): MITIGATE -> INVESTIGATE -> POSTMORTEM
  Behavioral Constraints (always active):
    - HITL gate on mutating commands
    - Flight Plan before code changes
    - Scope restriction (no global searches)
    - Token flush on phase transitions
    - Temp-file pattern for LQL queries (Tier 2)
         |
         v
Hands: Tiered Execution
  Tier 1: @google-cloud/observability-mcp
    -> list_log_entries, search_traces, get_trace
    -> list_time_series, list_alert_policies
  Tier 2: gcloud CLI via Bash
    -> Temp-file execution pattern for LQL
    -> gcloud logging read, gcloud traces list
  Tier 3: Guidance-only
    -> Manual Cloud Console instructions
```

## Behavioral Constraints

These are always-active rules at the top of SKILL.md, not phase-specific:

### 1. HITL Gate — No Autonomous Mutations

If a mutating action is identified (restart service, rollback deployment, scale pods, modify config), the agent MUST present the exact command it intends to run and halt completely, waiting for explicit user confirmation before executing. The agent is a copilot, not an autopilot.

### 2. Scope Restriction — No Global Searches During Incidents

During active investigation, all file reads, log queries, and code searches MUST be constrained to the specific service or trace ID identified in Phase 1 (MITIGATE). Global codebase searches (unbounded grep, recursive find) are forbidden. This prevents context window exhaustion and irrelevant noise during time-sensitive debugging.

### 3. Temp-File Execution Pattern (Tier 2 Only)

For any LQL query longer than 5 words or containing quotes/regex, Claude MUST write the query to a session-scoped temp file (via `mktemp`) and execute via file read. This avoids both escaping failures and concurrent-session race conditions:

```bash
LQL_FILE=$(mktemp /tmp/agent-lql-XXXXXX.txt)
cat > "$LQL_FILE" << 'QUERY'
resource.type="cloud_run_revision"
AND resource.labels.service_name="checkout-service"
AND severity>=ERROR
AND timestamp>="2026-03-19T10:00:00Z"
QUERY

gcloud logging read "$(cat "$LQL_FILE")" \
  --project=my-project --format=json --limit=50 ; rm -f "$LQL_FILE"
```

The `;` operator ensures cleanup runs regardless of whether `gcloud` succeeds or fails (network timeout, bad project ID, etc.), preventing orphan temp files. Using `mktemp` with a random suffix prevents concurrent sessions from overwriting each other's queries (consistent with the project's session-token scoping for `~/.claude/` shared state).

### 4. Context Discipline on Stage Transitions

Claude cannot literally clear its context window mid-session. This constraint is enforced **behaviorally** through prompt instructions:

When transitioning from INVESTIGATE to POSTMORTEM, the agent must:
1. Write a synthesized summary of the timeline and root cause as an explicit output block
2. From that point forward, the agent is **strictly forbidden from referencing the raw JSON log outputs** from earlier in the conversation
3. The agent must draft the postmortem **ONLY from the synthesized summary**
4. No further log queries or source code reads are permitted during POSTMORTEM

This prevents the agent from "drowning in logs" — referencing stale raw JSON that may be partially compressed or inconsistent, leading to hallucinated details in the postmortem.

## Skill State Machine

### Stage 1 — MITIGATE (Reactive Debugging)

```
1. Detect available tools (Tier 1/2/3)
2. Establish scope: which service? environment? time window?
3. Query error rate / recent errors (scoped to service + 30-60 min window)
4. Identify failing request pattern (endpoint, error code, frequency)
5. HITL GATE: If mutating fix is obvious (restart, rollback, scale),
   present exact command and HALT. Wait for explicit confirmation.
6. If code fix needed -> transition to INVESTIGATE
```

### Stage 2 — INVESTIGATE (Root Cause Analysis)

```
1. Query logs with narrowed LQL filter (service + severity + time window)
2. Extract key signals: stack traces, error messages, request IDs
3. Single-service deep dive:
   a. Error grouping (frequency, first/last occurrence)
   b. Recent deployment correlation (deploy before error spike?)
   c. Resource metrics (CPU, memory, latency) if available
4. [v1.1, Tier 1 only] Multi-service trace correlation:
   - Extract trace IDs -> search_traces -> follow spans
   - Query upstream/downstream service logs
5. Formulate root cause hypothesis
6. FLIGHT PLAN: Before touching any code, output a bulleted list of:
   - Files to modify
   - Logic to change
   - Expected outcome
   Ask for explicit developer approval before proceeding.
7. CONTEXT DISCIPLINE: Write a synthesized summary of timeline + root cause.
   From this point forward, reference ONLY this summary (not raw log JSON).
8. Transition to POSTMORTEM
```

### Stage 3 — POSTMORTEM (Structured Document Generation)

```
1. Template discovery (ordered):
   a. docs/templates/postmortem.md (project convention)
   b. .github/ISSUE_TEMPLATE/postmortem.md (GitHub-native)
   c. Built-in default schema (embedded in skill — structural constraints only,
      NOT a full boilerplate; ~50 tokens defining required section headers):
      ## 1. Summary
      ## 2. Impact (quantify user impact and duration)
      ## 3. Timeline (markdown table: timestamp | event)
      ## 4. Root Cause & Trigger
      ## 5. Resolution and Recovery
      ## 6. Lessons Learned (what went well, what went wrong, where we got lucky)
      ## 7. Action Items (actionable, assignable, with suggested owners)
2. Directory discovery:
   a. docs/postmortems/ or docs/incidents/ (check both)
   b. Create docs/postmortems/ if neither exists
3. Generate postmortem from synthesized summary (NOT raw logs):
   - Title and metadata (date, service, severity)
   - Timeline (from extracted timestamps, ordered)
   - Impact (from error rates/metrics, quantified)
   - Root cause (from investigation hypothesis)
   - Action items (concrete, assignable, with suggested owners)
4. Write to docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md
   The summary portion MUST be lowercase kebab-case (e.g., `checkout-500s`,
   `auth-timeout-spike`). No spaces, no mixed casing.
5. Terminal output ONLY:
   "Postmortem saved to docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md.
    Review the document and action items."
```

## Tiered Tool Detection

**Detection logic in SKILL.md (runtime, self-contained):**

```bash
# Step 1: Check for MCP observability tools
# The SKILL.md instructs Claude to check whether list_log_entries, search_traces,
# etc. are available as MCP tools in the current session.
# This is a prompt-level check: "If you have access to list_log_entries tool -> Tier 1"

# Step 2: Check for gcloud CLI
command -v gcloud && gcloud logging read --help >/dev/null 2>&1
# -> Tier 2 (Bash with temp-file pattern enforced)

# Step 3: Neither available -> Tier 3 (guidance-only)
# Print manual instructions for Cloud Console Logs Explorer
```

**Session-start awareness (optional, informational):**

Add `observability_capabilities` detection to `session-start-hook.sh` after the existing `context_capabilities` block (Step 8d). Same pattern as `security_capabilities`:

```bash
# Check for gcloud CLI availability
obs_gcloud=false
command -v gcloud >/dev/null 2>&1 && obs_gcloud=true
```

Append to `CONTEXT` in the emission block (Step 12), following the `Security tools:` line:

```bash
CONTEXT="${CONTEXT}
Observability tools: gcloud=${obs_gcloud}"
```

This field is **informational for the model only** — it helps Claude know what's available before the skill loads, but is not a routing gate. The skill's own detection (Stage 1 above) is authoritative. MCP tool availability is not detectable at session-start (MCP tools are discovered by the runtime, not by hooks).

### LQL Reference Patterns (Embedded in Skill — "Cheat Sheet")

These patterns are embedded directly in SKILL.md as few-shot examples (~100 tokens). This is non-negotiable: LLMs hallucinate syntax in specialized query languages (LQL, PromQL, KQL). Externalizing to a separate file would force a file read before every query. The embedded table gives Claude copy-pasteable, bulletproof patterns immediately.

| Pattern | LQL Filter |
|---------|-----------|
| Recent errors | `severity>=ERROR AND timestamp>="YYYY-MM-DDTHH:MM:SSZ"` |
| Cloud Run service | `resource.type="cloud_run_revision" AND resource.labels.service_name="X"` |
| GKE pod errors | `resource.type="k8s_container" AND resource.labels.cluster_name="X"` |
| HTTP 5xx | `httpRequest.status>=500` |
| Trace correlation | `trace="projects/PROJECT/traces/TRACE_ID"` |
| Text search | `textPayload=~"pattern"` |
| JSON payload field | `jsonPayload.fieldName="value"` |

### Tier 1 MCP Tool Mapping

| Investigation Step | MCP Tool | Parameters |
|-------------------|----------|------------|
| Query logs | `list_log_entries` | filter (LQL), project_id, page_size |
| Search traces | `search_traces` | filter, project_id |
| Get trace detail | `get_trace` | trace_id, project_id |
| Check metrics | `list_time_series` | filter, interval |
| Check alerts | `list_alert_policies` | project_id |

### Tier 2 gcloud CLI Mapping

| Investigation Step | Bash Command |
|-------------------|-------------|
| Query logs | `gcloud logging read "$(cat "$LQL_FILE")" --project=X --format=json --limit=50` (see temp-file pattern) |
| List traces | `gcloud traces list --project=X --format=json` |
| Error events | `gcloud beta error-reporting events list --service=X --format=json` (beta) |
| Metrics | `gcloud monitoring metrics list --project=X --format=json` (limited) |

## Routing Changes

### 1. Update `gcp-observability` methodology hint in `default-triggers.json`

Update the existing methodology hint entry with expanded triggers and updated hint text. Note: `5[0-9][0-9]` is used instead of `5[0-9]{2}` because Bash 3.2 ERE (macOS `/bin/bash`) does not reliably support `{n}` quantifiers in `[[ =~ ]]`.

```json
{
  "name": "gcp-observability",
  "triggers": [
    "(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search|incident|postmortem|root.cause|outage|error.spike|log.analysis|5[0-9][0-9].error)"
  ],
  "trigger_mode": "regex",
  "hint": "INCIDENT ANALYSIS: Use Skill(auto-claude-skills:incident-analysis) for structured investigation. Stages: MITIGATE -> INVESTIGATE -> POSTMORTEM. Detect tool tier (MCP > gcloud > guidance). Scope all queries to specific service + environment + narrow time window.",
  "phases": ["SHIP", "DEBUG"]
}
```

### 2. Add `incident-analysis` skill entry in `default-triggers.json`

The methodology hint above tells Claude *what to do*. This skill entry registers the skill in the routing engine so it can be scored, role-capped, and invoked via `Skill(auto-claude-skills:incident-analysis)`:

```json
{
  "name": "incident-analysis",
  "invoke": "Skill(auto-claude-skills:incident-analysis)",
  "role": "domain",
  "priority": 20,
  "triggers": [
    "(incident|postmortem|outage|root.cause|error.spike|log.analysis|production.error|staging.error)"
  ],
  "trigger_mode": "regex",
  "keywords": ["incident", "postmortem", "outage", "logs", "error spike"],
  "phases": ["DEBUG", "SHIP"]
}
```

**Role: `domain`** (not `process`) — this skill provides observability domain expertise but does not replace the `systematic-debugging` process skill. Both can fire together: `systematic-debugging` (process) + `incident-analysis` (domain).

### 3. Sync `config/fallback-registry.json`

`fallback-registry.json` is **auto-regenerated** by `session-start-hook.sh` (Step 10c) on every session start. No hand-editing is required. After `default-triggers.json` is updated and a session is started, the fallback will self-correct. The implementation step should verify that the fallback was regenerated correctly after the first session start, but the parity test should assert against `default-triggers.json` directly (the source of truth), not the derived fallback file.

## Phase Integration

Add Observability Truth tier to `skills/unified-context-stack/phases/testing-and-debug.md`:

```markdown
### 4. Observability Truth (Production State)
If the error may be production/staging related:
- **Tier 1** (MCP observability tools available): Use list_log_entries
  with scoped LQL filter (service + severity + time window <= 60 min)
- **Tier 2** (gcloud available): Use temp-file pattern for LQL queries
  via gcloud logging read --format=json
- **Tier 3** (neither): Guide developer to Cloud Console Logs Explorer
- ALWAYS scope: service + environment + narrow time window
- NEVER dump unbounded log results into context
```

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `skills/incident-analysis/SKILL.md` | **Create** | Brain: methodology, behavioral constraints, LQL patterns, templates, tiered detection. Invoke path: `Skill(auto-claude-skills:incident-analysis)` |
| `config/default-triggers.json` | **Modify** | (1) Update `gcp-observability` hint triggers and text, (2) add `incident-analysis` skill entry with invoke path, role=domain, priority=20 |
| `config/fallback-registry.json` | **Auto-regenerated** | Auto-synced by `session-start-hook.sh` Step 10c on next session start. No hand-editing needed. |
| `hooks/session-start-hook.sh` | **Modify** | Add `observability_capabilities` detection (gcloud availability) after Step 8d, same pattern as `security_capabilities` |
| `skills/unified-context-stack/phases/testing-and-debug.md` | **Modify** | Add Observability Truth tier (Section 4) |
| `tests/test-routing.sh` | **Modify** | Add routing tests for incident/postmortem/outage triggers + fallback parity |

### Test Strategy

Add to `tests/test-routing.sh`:

1. **Hint trigger matching**: Feed `incident`, `postmortem`, `root.cause`, `outage`, `error.spike`, `log.analysis` prompts to `skill-activation-hook.sh`, verify `gcp-observability` hint fires
2. **Skill trigger matching**: Verify `incident-analysis` skill entry scores and appears in output for the same prompts
3. **Phase gating**: Verify hint and skill fire in DEBUG and SHIP phases, do NOT fire in DESIGN, PLAN, IMPLEMENT, or REVIEW
4. **Existing trigger preservation**: Verify original triggers (`runtime.log`, `error.group`, etc.) still fire correctly after regex update
5. **Trigger source correctness**: Assert that `config/default-triggers.json` contains both the updated `gcp-observability` hint triggers and the new `incident-analysis` skill entry with correct invoke path `Skill(auto-claude-skills:incident-analysis)`. The fallback registry is auto-regenerated by `session-start-hook.sh` and does not need a separate assertion
6. **Invoke path correctness**: Verify the skill invoke path matches `Skill(auto-claude-skills:incident-analysis)` (not an external/user-skill path)

Existing `test-routing.sh` and `test-context.sh` tests must continue passing (no regression).

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| LQL syntax errors in Tier 2 | Temp-file execution pattern eliminates inline escaping; LQL reference patterns reduce invention |
| Unbounded log results exhausting context | Scope restriction constraint + `--limit` flag + skill instructs count-first approach |
| Agent executing mutating commands (restart, rollback) | HITL gate: explicit halt + confirmation required |
| Agent going down wrong debugging path | Flight Plan: bulleted list of intended changes, approval required before coding |
| Raw log JSON polluting postmortem writing | Token flush: synthesize before transitioning to POSTMORTEM phase |
| Global codebase search during incident | Scope restriction: all queries constrained to identified service/trace ID |
| MCP server not installed (most users) | Graceful degradation: Tier 2 (gcloud) and Tier 3 (guidance) always available |
| gcloud not authenticated | Skill instructs: check `gcloud auth list` first, guide through `gcloud auth login` if needed |
| Concurrent sessions overwriting temp files | Session-scoped `mktemp` with random suffix; consistent with project's session-token scoping |

## What's NOT in v1

- Multi-service trace correlation (v1.1, gated behind Tier 1 MCP availability)
- `incident-trend-analyzer` skill (v2 — reads `docs/postmortems/` for meta-analysis across historical incidents)
- `pr-friction-logger` skill (v2 — DX friction testing, Palladius frictionlog pattern)
- Jira/Linear auto-ticket creation for postmortem action items
- Alert/PagerDuty integration
- Proactive log monitoring
- Datadog/Grafana/Splunk backends (future `skills/incident-analysis-datadog/` etc.)
- Helper scripts (e.g., `scripts/parse_logs.py`) — evaluate need after v1 real-world usage

## Evolution Path

```
v1.0  Single-service investigation + structured postmortem (Tier 1/2/3)
v1.1  Multi-service trace correlation (Tier 1 MCP only)
v2.0  incident-trend-analyzer (Palladius aggregator pattern: read N postmortems, compute MTTR/MTTD, identify recurring failure modes)
v2.1  pr-friction-logger (Palladius frictionlog pattern: emulate new-dev experience on PR branches)
v3.0  Backend-agnostic (skills/incident-analysis-datadog/, skills/incident-analysis-splunk/)
```

## Decision

Approach selected through iterative brainstorming (5 rounds of clarification, multiple scoping decisions). Tiered execution strategy chosen on merit — not pattern-matching against security-scanner precedent. MCP justified for Tier 1 because log analysis is fundamentally different from security scanning (complex queries, unbounded results, multi-hop correlation). Skill+Bash retained as Tier 2 for universal availability.
