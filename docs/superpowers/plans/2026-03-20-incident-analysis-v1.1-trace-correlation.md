# Incident Analysis v1.1: Trace Correlation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder Step 4 in the incident-analysis SKILL.md with a bounded, evidence-gated, one-hop trace correlation workflow (Tier 1 MCP only).

**Architecture:** Modify the existing SKILL.md Step 4 section (lines 110-116) with the full workflow from the v1.1 spec. Also update the v1.0 design spec to reflect the shipped state. No new files, no routing changes, no test changes.

**Tech Stack:** Markdown (SKILL.md prompt engineering)

**Spec:** `docs/superpowers/specs/2026-03-20-incident-analysis-v1.1-trace-correlation-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `skills/incident-analysis/SKILL.md:110-116` | **Modify** — Replace Step 4 placeholder with full one-hop correlation workflow |
| `skills/incident-analysis/SKILL.md:198-199` | **Modify** — Add note that `search_traces` is not used in Step 4 |
| `docs/superpowers/specs/2026-03-19-incident-analysis-design.md:157-159` | **Modify** — Replace Stage 2 Step 4 stub with shipped workflow |
| `docs/superpowers/specs/2026-03-19-incident-analysis-design.md:372,385` | **Modify** — Update "What's NOT in v1" and evolution path |

---

### Task 1: Replace Step 4 placeholder in SKILL.md

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:110-116`

- [ ] **Step 1: Read the current Step 4 placeholder to confirm exact lines**

```bash
sed -n '108,118p' skills/incident-analysis/SKILL.md
```

Expected: Lines 110-116 contain the current placeholder:
```
### Step 4: Multi-Service Trace Correlation (v1.1, Tier 1 Only)

If Tier 1 MCP tools are available:
- Extract trace IDs from log entries
- Use `search_traces` / `get_trace` to follow spans
- Query upstream/downstream service logs
```

- [ ] **Step 2: Replace lines 110-116 with the full workflow**

Replace the entire block from `### Step 4:` through the blank line before `### Step 5:` (lines 110-116) with this exact content:

```markdown
### Step 4: Autonomous Trace Correlation (Tier 1 Only)

If Tier 1 MCP tools are NOT available, skip this step entirely. Proceed to Step 5.

**Prerequisite:** If Stage 2 logs contain multiple failing requests (>1), select one exemplar trace from the dominant error group (most frequent pattern) or the most recent failure with a `trace` field. Analyze only this single exemplar.

**Extract trace_id and project_id** from the exemplar log entry's `trace` field (format: `projects/PROJECT_ID/traces/TRACE_ID`). Strip the prefix to get the raw TRACE_ID. Preserve PROJECT_ID for `get_trace`.

If no `trace` field is present in the failing log entries, skip this step entirely.

**Retrieve the trace:**
Call `get_trace(trace_id, project_id)` to retrieve the span timeline. Do NOT use `search_traces` in this step.

**Inspect spans for cross-service boundaries:**

1. **All spans within Service A only:** Skip hop. Proceed to Step 5.
2. **Exactly one other service (Service B) meets EITHER evidence path below:** Execute the hop (continue below).
3. **Multiple services meet evidence criteria, or 3+ services with any failure signals:** Present trace timeline to user. Do NOT autonomously choose. Let user specify which service.
4. **Other services appear but none meet either evidence path:** Skip hop. Note services in synthesis.

**Failure evidence (MUST be present in Service B span data — any one sufficient):**
- Span status code != OK (gRPC error)
- HTTP status >= 500 in span attributes
- Exception stack trace in span events

**Timeout cascade (ALL conditions required):**
- Service A failed with explicit timeout/deadline-exceeded error
- Service B span duration >= 80% of root span duration (computed: `(B span end - B span start) / (root span end - root span start)`)
- No other non-Service-A span >= 40% of root span duration

Latency-only spans (slow but no error/timeout) do NOT justify the hop.

If evidence is ambiguous or borderline, do NOT hop — present trace timeline and let user decide.

**Query Service B logs** using `list_log_entries`:
- **project_id:** Service B's project ID (from span resource labels). Same as Service A's if same project.
- **filter:** Scoped to `trace="projects/<Service B project>/traces/<TRACE_ID>"` AND Service B's concrete resource labels from the span data (e.g., `resource.type` plus `resource.labels.service_name` or equivalent — not all services use `service_name`; use whatever label the span provides)
- **time range:** Service B span start minus 1 minute to span end plus 1 minute
- **page_size:** <= 50 entries
- If Service B's identity (resource labels or project) is ambiguous, STOP and present trace to user.
- **STRICT CONSTRAINT:** Do not execute a second hop. Do not follow the trace into a third service.

**Synthesize the causal path only:**
- Map the failure chain from Service B → Service A (causal path only, not the full trace tree)
- Present both services' log evidence in chronological order
- Feed this synthesized causal timeline into Step 5 (root cause hypothesis)
```

- [ ] **Step 3: Verify the replacement**

```bash
grep -n "Step 4" skills/incident-analysis/SKILL.md
```

Expected: `### Step 4: Autonomous Trace Correlation (Tier 1 Only)` appears (no "v1.1" or "Multi-Service" in the title).

```bash
grep -c "search_traces" skills/incident-analysis/SKILL.md
```

Expected: Should still appear in the MCP Tool Reference table (line ~198) but NOT in Step 4. Count should be 1 (table only) or 2 (table + the "Do NOT use" instruction).

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat: replace Step 4 placeholder with one-hop trace correlation (v1.1)"
```

---

### Task 2: Annotate search_traces in MCP Tool Reference table

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:198`

- [ ] **Step 1: Read the current table row**

```bash
sed -n '196,201p' skills/incident-analysis/SKILL.md
```

Expected: Line 198 contains `| Search traces | `search_traces` | filter, project_id |`

- [ ] **Step 2: Add annotation to the search_traces row**

Change line 198 from:
```
| Search traces | `search_traces` | filter, project_id |
```
To:
```
| Search traces | `search_traces` | filter, project_id (not used in Step 4; retained for future versions) |
```

- [ ] **Step 3: Verify**

```bash
grep "search_traces" skills/incident-analysis/SKILL.md
```

Expected: The table row now has the annotation.

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "docs: annotate search_traces as not used in Step 4"
```

---

### Task 3: Verify and run tests (before marking shipped)

**Files:**
- None (verification only)

- [ ] **Step 1: Verify SKILL.md structure is intact**

```bash
grep -n "^### Step" skills/incident-analysis/SKILL.md
```

Expected: Steps 1-7 in order, Step 4 now titled "Autonomous Trace Correlation (Tier 1 Only)".

- [ ] **Step 2: Run routing tests (no regressions)**

```bash
bash tests/test-routing.sh
```

Expected: 243/243 pass. No routing changes were made, so this is a pure regression check.

- [ ] **Step 3: Run all test suites**

```bash
bash tests/run-tests.sh 2>&1; echo "exit: $?"
```

Expected: Exit code 1 (non-zero) due to known baseline failure. The summary should show exactly 1 failed file (`test-registry.sh`) with 2 pre-existing parity assertions (`fallback skills all exist in default-triggers`, `fallback skills all have phase fields`). All other test files (test-routing.sh, test-context.sh, test-security-scanner.sh, etc.) MUST pass. If any file OTHER than test-registry.sh fails, STOP — that is a regression.

- [ ] **Step 4: Syntax check hooks**

```bash
bash -n hooks/session-start-hook.sh && echo "OK"
bash -n hooks/skill-activation-hook.sh && echo "OK"
```

Expected: Both OK.

- [ ] **Step 5: Behavioral verification — structured skill review**

The behavior lives in a SKILL.md (prompt logic), not hook code. Full live testing requires a GCP project with Tier 1 MCP tools and real trace data, which is not available in CI. This step is a structured document review against the spec's scenario matrix — not a substitute for live prompt testing, which should happen when the skill is first used on a real incident.

**Verification method:** Read the full Step 4 section of SKILL.md. For each scenario below, trace through the SKILL.md instructions and confirm the decision path is unambiguous and correct. If any scenario could produce wrong behavior (e.g., the agent could hop when it shouldn't, or fail to stop after one hop), fix before proceeding.

| # | Scenario | Expected behavior per SKILL.md | Check |
|---|----------|-------------------------------|-------|
| 1 | Clear downstream error span (status != OK) | Agent calls `get_trace`, finds one Service B span with error status, queries Service B logs (scoped to trace + resource labels + span time ± 1min, page_size <= 50), synthesizes causal path, feeds to Step 5 | [ ] |
| 2 | Timeout cascade (Service A timeout, Service B >= 80% root span) | Agent computes `(B end - B start) / (root end - root start)`, confirms >= 80% and no other non-A span >= 40%, queries Service B logs, synthesizes | [ ] |
| 3 | Fan-out to 3+ services with failure signals | Agent presents trace timeline to user, does NOT autonomously choose any service | [ ] |
| 4 | Multiple services show error evidence (2 services) | Agent presents trace timeline to user, does NOT autonomously choose | [ ] |
| 5 | No `trace` field in failing logs | Agent skips Step 4 entirely, proceeds to Step 5 | [ ] |
| 6 | All spans within Service A only | Agent skips hop, proceeds to Step 5 with single-service evidence | [ ] |
| 7 | Service B identity ambiguous from span data | Agent stops and presents trace to user instead of guessing | [ ] |
| 8 | Cross-project Service B | Agent uses Service B's project ID for `list_log_entries` and constructs `trace="projects/<Service B project>/traces/..."` in LQL filter | [ ] |
| 9 | Multiple failing requests in Stage 2 logs | Agent selects one exemplar trace from dominant error group before entering Step 4 | [ ] |
| 10 | Service B logs queried but return no useful signal | Agent notes the gap in synthesis, proceeds to Step 5 — does not retry, expand scope, or improvise | [ ] |
| 11 | Tier 2 (gcloud CLI, no MCP) | Step 4 skipped entirely, agent proceeds to Step 5 | [ ] |

For each row: read the SKILL.md instructions and confirm they unambiguously produce the expected behavior. If any scenario is ambiguous or could lead to wrong behavior, STOP and fix the SKILL.md before proceeding to Task 4.

---

### Task 4: Update v1.0 design spec (after verification passes)

**Files:**
- Modify: `docs/superpowers/specs/2026-03-19-incident-analysis-design.md:157-159`
- Modify: `docs/superpowers/specs/2026-03-19-incident-analysis-design.md:372`
- Modify: `docs/superpowers/specs/2026-03-19-incident-analysis-design.md:385`

Only execute this task AFTER Task 3 verification passes with no new failures.

- [ ] **Step 1: Replace Stage 2 Step 4 stub**

In the v1.0 spec, find lines 157-159:
```
4. [v1.1, Tier 1 only] Multi-service trace correlation:
   - Extract trace IDs -> search_traces -> follow spans
   - Query upstream/downstream service logs
```

Replace with:
```
4. Autonomous trace correlation (Tier 1 MCP only):
   - Select exemplar trace from dominant error group
   - Call get_trace to retrieve span timeline
   - If exactly one cross-service span has failure evidence (error status,
     HTTP >= 500, exception, or timeout cascade >= 80% root span duration):
     query Service B logs (one hop max, scoped to trace_id + service labels)
   - Synthesize causal path only, feed into Step 5
   - See v1.1 spec for full workflow details
```

- [ ] **Step 2: Update "What's NOT in v1" section**

Find line 372:
```
- Multi-service trace correlation (v1.1, gated behind Tier 1 MCP availability)
```

Replace with:
```
- Multi-service trace correlation beyond one hop (v1.2+, currently limited to Service A → Service B)
```

- [ ] **Step 3: Update evolution path**

Find line 385:
```
v1.1  Multi-service trace correlation (Tier 1 MCP only)
```

Replace with:
```
v1.1  One-hop trace correlation: Service A → Service B (Tier 1 MCP only) [SHIPPED]
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-03-19-incident-analysis-design.md
git commit -m "docs: update v1.0 spec to reflect v1.1 trace correlation (shipped)"
```
