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
  State Machine: MITIGATE -> INVESTIGATE -> POSTMORTEM
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

For any LQL query longer than 5 words or containing quotes/regex, Claude MUST write the query to `/tmp/agent-lql-query.txt` and execute via:

```bash
cat > /tmp/agent-lql-query.txt << 'QUERY'
resource.type="cloud_run_revision"
AND resource.labels.service_name="checkout-service"
AND severity>=ERROR
AND timestamp>="2026-03-19T10:00:00Z"
QUERY

gcloud logging read "$(cat /tmp/agent-lql-query.txt)" \
  --project=my-project --format=json --limit=50
```

This eliminates escaping-related syntax failures that occur when constructing complex LQL inline.

### 4. Token Flush on Phase Transitions

When transitioning from INVESTIGATE to POSTMORTEM, the agent must:
1. Synthesize the timeline and root cause into a structured summary
2. Stop querying logs or reading source code
3. Discard raw JSON/log context from working memory
4. Draft the postmortem from the synthesized summary only

This prevents the agent from "drowning in logs" and hallucinating during the writing phase.

## Skill State Machine

### Phase 1 — MITIGATE (Reactive Debugging)

```
1. Detect available tools (Tier 1/2/3)
2. Establish scope: which service? environment? time window?
3. Query error rate / recent errors (scoped to service + 30-60 min window)
4. Identify failing request pattern (endpoint, error code, frequency)
5. HITL GATE: If mutating fix is obvious (restart, rollback, scale),
   present exact command and HALT. Wait for explicit confirmation.
6. If code fix needed -> transition to INVESTIGATE
```

### Phase 2 — INVESTIGATE (Root Cause Analysis)

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
7. TOKEN FLUSH: Synthesize timeline + root cause into structured summary
8. Transition to POSTMORTEM
```

### Phase 3 — POSTMORTEM (Structured Document Generation)

```
1. Template discovery (ordered):
   a. docs/templates/postmortem.md (project convention)
   b. .github/ISSUE_TEMPLATE/postmortem.md (GitHub-native)
   c. Convention in CLAUDE.md (postmortem_template_path key)
   d. Built-in default template (embedded in skill)
2. Directory discovery:
   a. docs/postmortems/ or docs/incidents/ (check both)
   b. Create docs/postmortems/ if neither exists
3. Generate postmortem from synthesized summary (NOT raw logs):
   - Title and metadata (date, service, severity)
   - Timeline (from extracted timestamps, ordered)
   - Impact (from error rates/metrics, quantified)
   - Root cause (from investigation hypothesis)
   - Action items (concrete, assignable, with suggested owners)
4. Write to docs/postmortems/YYYY-MM-DD-<summary>.md
5. Terminal output ONLY:
   "Postmortem saved to docs/postmortems/YYYY-MM-DD-<summary>.md.
    Review the document and action items."
```

## Tiered Tool Detection

```bash
# Step 1: Check for MCP observability tools
# If list_log_entries tool exists in Claude's tool context -> Tier 1 (MCP)
# Detection: Check session-start additionalContext for observability MCP presence

# Step 2: Check for gcloud CLI
command -v gcloud && gcloud logging read --help >/dev/null 2>&1
# -> Tier 2 (Bash with temp-file pattern enforced)

# Step 3: Neither available -> Tier 3 (guidance-only)
# Print manual instructions for Cloud Console Logs Explorer
```

### LQL Reference Patterns (Embedded in Skill)

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
| Query logs | `gcloud logging read "$(cat /tmp/agent-lql-query.txt)" --project=X --format=json --limit=50` |
| List traces | `gcloud traces list --project=X --format=json` |
| Error events | `gcloud error-events list --service=X --format=json` |
| Metrics | `gcloud monitoring metrics list --project=X --format=json` (limited) |

## Routing Changes

### Update `gcp-observability` in `default-triggers.json`

```json
{
  "name": "gcp-observability",
  "triggers": [
    "(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search|incident|postmortem|root.cause|outage|error.spike|log.analysis|5[0-9]{2}.error)"
  ],
  "trigger_mode": "regex",
  "hint": "INCIDENT ANALYSIS: Use the incident-analysis skill for structured investigation. State machine: MITIGATE -> INVESTIGATE -> POSTMORTEM. Detect tool tier (MCP > gcloud > guidance). Scope all queries to specific service + environment + narrow time window.",
  "phases": ["SHIP", "DEBUG"]
}
```

Sync to `config/fallback-registry.json`.

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
| `skills/incident-analysis/SKILL.md` | **Create** | Brain: methodology, behavioral constraints, LQL patterns, templates, tiered detection |
| `config/default-triggers.json` | **Modify** | Update `gcp-observability` triggers and hint text |
| `config/fallback-registry.json` | **Modify** | Sync with default-triggers changes |
| `skills/unified-context-stack/phases/testing-and-debug.md` | **Modify** | Add Observability Truth tier (Section 4) |
| `tests/test-routing.sh` | **Modify** | Add routing tests for incident/postmortem/outage triggers |

### Test Strategy

Add to `tests/test-routing.sh`:

1. **Trigger matching**: Feed `incident`, `postmortem`, `root.cause`, `outage`, `error.spike`, `log.analysis` prompts to `skill-activation-hook.sh`, verify `gcp-observability` hint fires
2. **Phase gating**: Verify hint fires in DEBUG and SHIP phases, does NOT fire in IMPLEMENT or DESIGN
3. **Existing trigger preservation**: Verify original triggers (`runtime.log`, `error.group`, etc.) still fire correctly after regex update

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
