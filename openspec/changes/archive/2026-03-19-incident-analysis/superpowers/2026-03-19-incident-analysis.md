# Incident Analysis Skill Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tiered incident-analysis skill that teaches Claude structured log investigation (MITIGATE → INVESTIGATE → POSTMORTEM) with GCP observability tools, behavioral guardrails, and postmortem generation.

**Architecture:** A SKILL.md (the "brain") defines the investigation methodology and behavioral constraints. It detects available tools at runtime (MCP observability > gcloud CLI > guidance-only) and adapts execution accordingly. Routing triggers in `default-triggers.json` activate the skill during DEBUG and SHIP phases.

**Tech Stack:** Bash 3.2 (macOS compatible), jq, gcloud CLI, `@google-cloud/observability-mcp` (optional Tier 1)

**Spec:** `docs/superpowers/specs/2026-03-19-incident-analysis-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `skills/incident-analysis/SKILL.md` | **Create** — Skill definition: behavioral constraints, state machine (3 stages), tiered tool detection, LQL cheat sheet, postmortem schema |
| `config/default-triggers.json` | **Modify** — (1) Update `gcp-observability` hint entry triggers+text, (2) add `incident-analysis` skill entry |
| `hooks/session-start-hook.sh` | **Modify** — Add `observability_capabilities` detection block (gcloud availability) after Step 8f |
| `skills/unified-context-stack/phases/testing-and-debug.md` | **Modify** — Add Section 4: Observability Truth tier |
| `tests/test-routing.sh` | **Modify** — Add incident-analysis routing tests |

---

### Task 1: Create the SKILL.md

**Files:**
- Create: `skills/incident-analysis/SKILL.md`
- Reference: `skills/security-scanner/SKILL.md` (structural pattern to follow)

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p skills/incident-analysis
```

- [ ] **Step 2: Write SKILL.md with frontmatter and behavioral constraints**

Create `skills/incident-analysis/SKILL.md` with this exact content:

```markdown
---
name: incident-analysis
description: Tiered GCP log investigation and structured postmortem generation with behavioral guardrails
---

# Incident Analysis

Structured incident investigation: detect tools, query logs, find root cause, generate postmortem.

## When to Use

During DEBUG phase when investigating production/staging errors, or during SHIP phase for post-incident analysis and postmortem generation. Also invocable on explicit incident/outage/postmortem requests.

## Behavioral Constraints (Always Active)

### No Autonomous Mutations
If a mutating action is identified (restart service, rollback deployment, scale pods, modify config), you MUST present the exact command you intend to run and halt completely. Proceed ONLY on explicit user confirmation. You are a copilot, not an autopilot.

### No Global Searches During Incidents
During active investigation, all file reads, log queries, and code searches MUST be constrained to the specific service or trace ID identified in Stage 1. Global codebase searches (unbounded grep, recursive find) are forbidden.

### Temp-File Execution Pattern (Tier 2 Only)
For any LQL query longer than 5 words or containing quotes/regex, you MUST write the query to a session-scoped temp file and execute via file read:

` ` `bash
LQL_FILE=$(mktemp /tmp/agent-lql-XXXXXX.txt)
cat > "$LQL_FILE" << 'QUERY'
YOUR_LQL_FILTER_HERE
QUERY
gcloud logging read "$(cat "$LQL_FILE")" \
  --project=PROJECT_ID --format=json --limit=50 ; rm -f "$LQL_FILE"
` ` `

Never construct complex LQL inline. The `;` ensures cleanup runs regardless of gcloud success/failure.

### Context Discipline on Stage Transitions
When transitioning from INVESTIGATE to POSTMORTEM:
1. Write a synthesized summary of the timeline and root cause as an explicit output block
2. From that point forward, you are strictly forbidden from referencing the raw JSON log outputs from earlier in the conversation
3. Draft the postmortem ONLY from the synthesized summary
4. No further log queries or source code reads are permitted during POSTMORTEM

## Stage 1: MITIGATE (Reactive Debugging)

1. **Detect available tools:**

   **Tier 1 (MCP):** If you have access to `list_log_entries`, `search_traces`, `get_trace`, `list_time_series`, or `list_alert_policies` MCP tools, use Tier 1. These provide structured calls with transparent pagination.

   **Tier 2 (gcloud CLI):** If Tier 1 is not available, check for gcloud:
   ` ` `bash
   command -v gcloud && echo "gcloud: available" || echo "gcloud: not installed"
   ` ` `
   If gcloud is available but not authenticated, guide the user: `gcloud auth login`

   **Tier 3 (Guidance-only):** If neither is available, provide manual instructions for Google Cloud Console Logs Explorer and recommend installing gcloud.

2. Establish scope: which service? which environment (prod/staging)? what time window?
3. Query error rate / recent errors (scoped to service + 30-60 min window)
4. Identify the failing request pattern (endpoint, error code, frequency)
5. **HITL GATE:** If a mutating fix is obvious (restart, rollback, scale), present the exact command and HALT. Wait for explicit user confirmation.
6. If a code fix is needed, transition to Stage 2 (INVESTIGATE)

**Tier 1 query:**
Use `list_log_entries` with filter and project_id parameters.

**Tier 2 query (use temp-file pattern):**
` ` `bash
LQL_FILE=$(mktemp /tmp/agent-lql-XXXXXX.txt)
cat > "$LQL_FILE" << 'QUERY'
severity>=ERROR
AND timestamp>="YYYY-MM-DDTHH:MM:SSZ"
AND resource.labels.service_name="SERVICE_NAME"
QUERY
gcloud logging read "$(cat "$LQL_FILE")" \
  --project=PROJECT_ID --format=json --limit=50 ; rm -f "$LQL_FILE"
` ` `

## Stage 2: INVESTIGATE (Root Cause Analysis)

1. Query logs with narrowed LQL filter (service + severity + time window)
2. Extract key signals: stack traces, error messages, request IDs
3. Single-service deep dive:
   - Error grouping (frequency, first/last occurrence)
   - Recent deployment correlation (was there a deploy before the error spike?)
   - Resource metrics (CPU, memory, latency) if Tier 1 available
4. Formulate root cause hypothesis
5. **FLIGHT PLAN:** Before touching any code, output a bulleted list of:
   - Files to modify
   - Logic to change
   - Expected outcome

   Ask for explicit developer approval before proceeding with code changes.
6. **CONTEXT DISCIPLINE:** Write a synthesized summary of the timeline and root cause. From this point forward, reference ONLY this summary.
7. Transition to Stage 3 (POSTMORTEM)

## Stage 3: POSTMORTEM (Document Generation)

1. **Template discovery** (ordered):
   a. `docs/templates/postmortem.md` (project convention)
   b. `.github/ISSUE_TEMPLATE/postmortem.md` (GitHub-native)
   c. If neither exists, use this default schema:

` ` `markdown
# Postmortem: [Incident Title]

**Date:** YYYY-MM-DD
**Service:** [affected service]
**Severity:** [P1/P2/P3/P4]
**Author:** [generated by incident-analysis skill]

## 1. Summary
[One paragraph describing what happened]

## 2. Impact
[Quantify: users affected, error rate, duration]

## 3. Timeline
| Time (UTC) | Event |
|------------|-------|

## 4. Root Cause & Trigger
[What broke and why]

## 5. Resolution and Recovery
[How it was fixed and service restored]

## 6. Lessons Learned
**What went well:**
**What went wrong:**
**Where we got lucky:**

## 7. Action Items
| Action | Owner | Priority | Status |
|--------|-------|----------|--------|
` ` `

2. **Directory discovery:**
   - Check for `docs/postmortems/` or `docs/incidents/`
   - Create `docs/postmortems/` if neither exists

3. Generate postmortem from synthesized summary (NOT raw logs)

4. Write to `docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md`
   - The summary portion MUST be lowercase kebab-case (e.g., `checkout-500s`, `auth-timeout-spike`)
   - No spaces, no mixed casing

5. Terminal output ONLY:
   "Postmortem saved to docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md. Review the document and action items."

## LQL Reference Patterns

| Pattern | LQL Filter |
|---------|-----------|
| Recent errors | `severity>=ERROR AND timestamp>="YYYY-MM-DDTHH:MM:SSZ"` |
| Cloud Run service | `resource.type="cloud_run_revision" AND resource.labels.service_name="X"` |
| GKE pod errors | `resource.type="k8s_container" AND resource.labels.cluster_name="X"` |
| HTTP 5xx | `httpRequest.status>=500` |
| Trace correlation | `trace="projects/PROJECT/traces/TRACE_ID"` |
| Text search | `textPayload=~"pattern"` |
| JSON payload field | `jsonPayload.fieldName="value"` |

## Tier 1 MCP Tool Reference

| Investigation Step | MCP Tool | Key Parameters |
|-------------------|----------|----------------|
| Query logs | `list_log_entries` | filter (LQL), project_id, page_size |
| Search traces | `search_traces` | filter, project_id |
| Get trace detail | `get_trace` | trace_id, project_id |
| Check metrics | `list_time_series` | filter, interval |
| Check alerts | `list_alert_policies` | project_id |

## Tier 2 gcloud CLI Reference

| Investigation Step | Command |
|-------------------|---------|
| Query logs | `gcloud logging read "$(cat "$LQL_FILE")" --project=X --format=json --limit=50` |
| List traces | `gcloud traces list --project=X --format=json` |
| Error events | `gcloud beta error-reporting events list --service=X --format=json` |
| Metrics | `gcloud monitoring metrics list --project=X --format=json` |
```

**IMPORTANT:** The triple backticks inside the SKILL.md content above are written as `` ` ` ` `` for escaping in this plan. When creating the actual file, use normal triple backticks (` ``` `).

- [ ] **Step 3: Verify the skill file is valid markdown**

```bash
wc -l skills/incident-analysis/SKILL.md
# Expected: ~170-190 lines
head -5 skills/incident-analysis/SKILL.md
# Expected: frontmatter with name: incident-analysis
```

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat: add incident-analysis skill (SKILL.md)"
```

---

### Task 2: Update routing triggers in default-triggers.json

**Files:**
- Modify: `config/default-triggers.json:444-455` (existing `gcp-observability` entry)
- Modify: `config/default-triggers.json` (add new `incident-analysis` skill entry)
- Reference: `docs/superpowers/specs/2026-03-19-incident-analysis-design.md:273-314`

- [ ] **Step 1: Update the `gcp-observability` methodology hint**

In `config/default-triggers.json`, find the entry at ~line 445 with `"name": "gcp-observability"` and replace the `triggers` array and `hint` field:

Old triggers:
```json
"triggers": [
  "(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search)"
]
```

New triggers:
```json
"triggers": [
  "(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search|incident|postmortem|root.cause|outage|error.spike|log.analysis|5[0-9][0-9].error)"
]
```

Old hint:
```json
"hint": "GCP OBSERVABILITY: If observability MCP tools are available, verify runtime state. Scope queries to service + environment + narrow time window (30-60 min)."
```

New hint:
```json
"hint": "INCIDENT ANALYSIS: Use Skill(auto-claude-skills:incident-analysis) for structured investigation. Stages: MITIGATE -> INVESTIGATE -> POSTMORTEM. Detect tool tier (MCP > gcloud > guidance). Scope all queries to specific service + environment + narrow time window."
```

Keep `phases: ["SHIP", "DEBUG"]` unchanged.

- [ ] **Step 2: Add the `incident-analysis` skill entry**

Add this new entry to the `skills` array in `default-triggers.json` (after the existing GCP-related methodology hints, before the `firebase` entry at ~line 481):

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

- [ ] **Step 3: Syntax-check the JSON**

```bash
jq empty config/default-triggers.json && echo "JSON valid" || echo "JSON INVALID"
```
Expected: `JSON valid`

- [ ] **Step 4: Verify both entries exist**

```bash
jq '.. | objects | select(.name == "gcp-observability") | .triggers[0]' config/default-triggers.json
# Expected: contains "incident|postmortem|root.cause|outage|error.spike|log.analysis"

jq '.. | objects | select(.name == "incident-analysis") | .invoke' config/default-triggers.json
# Expected: "Skill(auto-claude-skills:incident-analysis)"
```

- [ ] **Step 5: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: add incident-analysis routing triggers and skill entry"
```

---

### Task 3: Verify fallback-registry auto-regeneration

**Files:**
- Verify: `config/fallback-registry.json` (auto-regenerated, NOT hand-edited)
- Reference: Spec lines 312-314: "No hand-editing is required. After default-triggers.json is updated and a session is started, the fallback will self-correct."

The fallback registry is **auto-regenerated** by `session-start-hook.sh` (Step 10c) on every session start. Per the spec, we do NOT hand-edit it. We verify it self-corrects.

- [ ] **Step 1: Trigger a session-start to regenerate the fallback**

```bash
bash hooks/session-start-hook.sh > /dev/null 2>&1 || true
```

- [ ] **Step 2: Verify the fallback was updated with new entries**

```bash
jq -r '.. | objects | select(.name == "incident-analysis") | .invoke // empty' config/fallback-registry.json
# Expected: "Skill(auto-claude-skills:incident-analysis)"

jq -r '.. | objects | select(.name == "gcp-observability") | .hint // empty' config/fallback-registry.json | grep -q "INCIDENT ANALYSIS" && echo "Hint updated" || echo "Hint NOT updated"
# Expected: "Hint updated"
```

- [ ] **Step 3: Commit the auto-regenerated fallback**

```bash
git add config/fallback-registry.json
git commit -m "chore: sync fallback registry with incident-analysis triggers (auto-regenerated)"
```

---

### Task 4: Add observability_capabilities to session-start-hook.sh

**Files:**
- Modify: `hooks/session-start-hook.sh:671` (after Step 8f security caps)
- Modify: `hooks/session-start-hook.sh:919` (after Security tools emission)
- Reference: `hooks/session-start-hook.sh:666-671` (security caps pattern)

- [ ] **Step 1: Add gcloud detection after the security capabilities block**

After line 671 (`SECURITY_CAPS="semgrep=${_SEMGREP}, trivy=${_TRIVY}, gitleaks=${_GITLEAKS}"`), add:

```bash
# ── Step 8g: Detect observability capabilities ──────────────────────
_OBS_GCLOUD=false
command -v gcloud >/dev/null 2>&1 && _OBS_GCLOUD=true
```

- [ ] **Step 2: Add emission after the Security tools line**

After line 919 (`Security tools: ${SECURITY_CAPS}${_SEC_HINT}"`), add:

```bash
CONTEXT="${CONTEXT}
Observability tools: gcloud=${_OBS_GCLOUD}"
```

- [ ] **Step 3: Syntax-check the hook**

```bash
bash -n hooks/session-start-hook.sh && echo "Syntax OK" || echo "Syntax ERROR"
```
Expected: `Syntax OK`

- [ ] **Step 4: Verify emission**

```bash
# Quick smoke test: source and check the variable would be set
bash -c 'source hooks/session-start-hook.sh 2>/dev/null; echo "done"' || true
# Alternatively, just verify the string appears in the file:
grep -c "Observability tools:" hooks/session-start-hook.sh
# Expected: 1
```

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: detect gcloud availability at session start"
```

---

### Task 5: Add Observability Truth to testing-and-debug.md

**Files:**
- Modify: `skills/unified-context-stack/phases/testing-and-debug.md:24` (append after Section 3)

- [ ] **Step 1: Append Section 4 to the phase document**

After the existing Section 3 (Internal Truth, ending at line 24), append:

```markdown

### 4. Observability Truth (Production State)
If the error may be production/staging related:
- **Tier 1** (MCP observability tools available): Use `list_log_entries` with scoped LQL filter (service + severity + time window <= 60 min)
- **Tier 2** (gcloud available): Use temp-file pattern for LQL queries via `gcloud logging read --format=json`
- **Tier 3** (neither): Guide developer to Cloud Console Logs Explorer
- ALWAYS scope: service + environment + narrow time window
- NEVER dump unbounded log results into context
```

- [ ] **Step 2: Verify the file is well-formed**

```bash
wc -l skills/unified-context-stack/phases/testing-and-debug.md
# Expected: ~32 lines (was 24, added ~8)
```

- [ ] **Step 3: Commit**

```bash
git add skills/unified-context-stack/phases/testing-and-debug.md
git commit -m "feat: add Observability Truth tier to testing-and-debug phase"
```

---

### Task 6: Add routing tests

**Files:**
- Modify: `tests/test-routing.sh` (add registry helper, test functions, and register in runner)
- Reference: `tests/test-routing.sh:340-358` (existing `install_registry_with_batch` pattern)
- Reference: `tests/test-routing.sh:882-908` (existing `test_phase_scoped_methodology_hints` pattern)

**CRITICAL NOTE:** The test's `install_registry` writes a static mock JSON cache. This cache does NOT contain the new `gcp-observability` hint or `incident-analysis` skill entry. Tests that call `run_hook` must use a helper that injects these entries into the mock cache, following the `install_registry_with_batch` pattern.

- [ ] **Step 1: Add the `install_registry_with_incident_analysis` helper**

Add after the existing `install_registry_with_batch` function (~line 358):

```bash
install_registry_with_incident_analysis() {
    install_registry
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    # Add incident-analysis skill entry
    jq '.skills += [{
      "name": "incident-analysis",
      "role": "domain",
      "phase": "DEBUG",
      "triggers": ["(incident|postmortem|outage|root.cause|error.spike|log.analysis|production.error|staging.error)"],
      "trigger_mode": "regex",
      "priority": 20,
      "precedes": [],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:incident-analysis)",
      "keywords": ["incident", "postmortem", "outage", "logs", "error spike"],
      "available": true,
      "enabled": true
    }] | .methodology_hints += [{
      "name": "gcp-observability",
      "triggers": ["(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search|incident|postmortem|root.cause|outage|error.spike|log.analysis|5[0-9][0-9].error)"],
      "trigger_mode": "regex",
      "hint": "INCIDENT ANALYSIS: Use Skill(auto-claude-skills:incident-analysis) for structured investigation. Stages: MITIGATE -> INVESTIGATE -> POSTMORTEM. Detect tool tier (MCP > gcloud > guidance). Scope all queries to specific service + environment + narrow time window.",
      "phases": ["SHIP", "DEBUG"]
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"
}
```

- [ ] **Step 2: Write the incident-analysis hint trigger test**

Add test functions before the SDLC enforcement section (~line 1503):

```bash
test_incident_analysis_hint_fires() {
    echo "-- test: incident-analysis hint fires on incident keywords --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    # "incident" should trigger gcp-observability hint in DEBUG phase
    output="$(run_hook "debug this production incident in checkout service")"
    context="$(extract_context "${output}")"
    assert_contains "incident triggers gcp-observability hint" "INCIDENT ANALYSIS" "${context}"

    # "postmortem" should also trigger
    output="$(run_hook "write a postmortem for the outage last night")"
    context="$(extract_context "${output}")"
    assert_contains "postmortem triggers gcp-observability hint" "INCIDENT ANALYSIS" "${context}"

    teardown_test_env
}
```

- [ ] **Step 3: Write the incident-analysis skill scoring test**

```bash
test_incident_analysis_skill_scores() {
    echo "-- test: incident-analysis skill entry scores on incident keywords --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "debug this production incident in the auth service")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis skill appears" "incident-analysis" "${context}"

    teardown_test_env
}
```

- [ ] **Step 4: Write the phase gating test**

```bash
test_incident_analysis_phase_gating() {
    echo "-- test: incident-analysis only fires in DEBUG and SHIP phases --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    # DEBUG phase: "debug" triggers systematic-debugging (DEBUG) + incident hint should fire
    output="$(run_hook "debug the incident in checkout service logs")"
    context="$(extract_context "${output}")"
    assert_contains "hint fires in DEBUG phase" "INCIDENT ANALYSIS" "${context}"

    # DESIGN phase: "design" triggers brainstorming (DESIGN) — incident hint should NOT fire
    output="$(run_hook "design an incident tracking dashboard")"
    context="$(extract_context "${output}")"
    assert_not_contains "hint suppressed in DESIGN phase" "INCIDENT ANALYSIS" "${context}"

    teardown_test_env
}
```

- [ ] **Step 5: Write the existing trigger preservation test**

```bash
test_incident_analysis_preserves_existing_triggers() {
    echo "-- test: existing gcp-observability triggers still work --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    # Original trigger "runtime.log" should still fire the hint
    output="$(run_hook "debug the runtime.log errors in production")"
    context="$(extract_context "${output}")"
    assert_contains "runtime.log still triggers hint" "INCIDENT ANALYSIS" "${context}"

    teardown_test_env
}
```

- [ ] **Step 6: Write the default-triggers source correctness test**

```bash
test_incident_analysis_trigger_source() {
    echo "-- test: default-triggers.json contains incident-analysis entry --"

    # Verify the skill entry exists with correct invoke path
    local invoke_path
    invoke_path="$(jq -r '.. | objects | select(.name == "incident-analysis") | .invoke // empty' config/default-triggers.json)"
    assert_equals "invoke path correct" "Skill(auto-claude-skills:incident-analysis)" "${invoke_path}"

    # Verify the hint entry was updated
    local hint_text
    hint_text="$(jq -r '.. | objects | select(.name == "gcp-observability") | .hint // empty' config/default-triggers.json)"
    assert_contains "hint text updated" "INCIDENT ANALYSIS" "${hint_text}"
}
```

- [ ] **Step 7: Write the invoke path correctness test (spec item 6)**

```bash
test_incident_analysis_invoke_path() {
    echo "-- test: invoke path uses bundled plugin prefix --"

    local invoke_path
    invoke_path="$(jq -r '.. | objects | select(.name == "incident-analysis") | .invoke // empty' config/default-triggers.json)"

    # Must use auto-claude-skills: prefix (bundled), not external/user-skill path
    assert_contains "uses bundled plugin prefix" "auto-claude-skills:" "${invoke_path}"
    assert_not_contains "not external skill" "~/.claude/skills" "${invoke_path}"
}
```

- [ ] **Step 8: Register all new tests in the test runner**

Add these lines to the test runner invocation list after `test_domain_instruction_no_process` (line 1501, which is the last test before the SDLC enforcement section):

```bash
test_incident_analysis_hint_fires
test_incident_analysis_skill_scores
test_incident_analysis_phase_gating
test_incident_analysis_preserves_existing_triggers
test_incident_analysis_trigger_source
test_incident_analysis_invoke_path
```

- [ ] **Step 9: Run the full test suite**

```bash
bash tests/test-routing.sh
```
Expected: All tests pass, including the 6 new ones and all existing tests (no regression).

- [ ] **Step 10: Commit**

```bash
git add tests/test-routing.sh
git commit -m "test: add incident-analysis routing and phase gating tests"
```

---

### Task 7: Run full test suite and verify no regressions

**Files:**
- None (verification only)

- [ ] **Step 1: Run all test suites**

```bash
bash tests/run-tests.sh
```
Expected: All suites pass.

- [ ] **Step 2: Run routing tests specifically**

```bash
bash tests/test-routing.sh
```
Expected: All tests pass (existing + 6 new).

- [ ] **Step 3: Run context tests for phase doc changes**

```bash
bash tests/test-context.sh
```
Expected: All tests pass.

- [ ] **Step 4: Syntax-check all modified hooks**

```bash
bash -n hooks/session-start-hook.sh && echo "session-start: OK"
bash -n hooks/skill-activation-hook.sh && echo "skill-activation: OK"
```
Expected: Both OK.

- [ ] **Step 5: Verify the skill is discoverable**

```bash
# The skill should be discoverable by session-start as a bundled plugin skill
ls skills/incident-analysis/SKILL.md && echo "Skill file exists"
grep -q "^name: incident-analysis" skills/incident-analysis/SKILL.md && echo "Frontmatter correct"
```

- [ ] **Step 6: Quick routing smoke test**

```bash
SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh <<< "debug this production incident in the checkout service" 2>&1 | head -30
```
Expected: Should show `incident-analysis` scoring and `gcp-observability` hint in the output.
