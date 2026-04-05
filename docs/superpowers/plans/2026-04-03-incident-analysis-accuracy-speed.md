# Incident-Analysis Accuracy & Speed Improvements

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve investigation accuracy through aggregate-first error fingerprinting, structured synthesis output, and an evidence ledger; improve speed through an opt-in live-triage mode; improve reliability through behavioral eval fixtures and selective disambiguation probes.

**Architecture:** All changes are edits to SKILL.md, reference files, playbook YAML, and test files. No new scripts, no new architecture. The core single-agent sequential investigation flow is preserved. Live-triage is an explicit opt-in mode, not a heuristic switch.

**Tech Stack:** Bash 3.2, YAML playbooks, JSON test fixtures, Markdown skill docs

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `skills/incident-analysis/SKILL.md` | Modify | Aggregate fingerprint step, live-triage mode, evidence ledger, canonical summary schema |
| `skills/incident-analysis/references/query-patterns.md` | Modify | Add aggregate query patterns for Tier 1 and Tier 2 |
| `skills/incident-analysis/playbooks/bad-release-rollback.yaml` | Modify | Add disambiguation probe |
| `commands/investigate.md` | Modify | Add live-triage mode entry, update pipeline description |
| `tests/test-incident-analysis-content.sh` | Modify | Content assertions for new sections |
| `tests/test-routing.sh` | Modify | Wire routing eval fixtures into live hook validation |
| `tests/test-incident-analysis-evals.sh` | Create | Eval fixture schema validator |
| `tests/fixtures/incident-analysis/evals/routing.json` | Create | Trigger routing eval cases |
| `tests/fixtures/incident-analysis/evals/behavioral.json` | Create | Workflow behavior assertion fixtures |

---

### Task 1: Aggregate-First Error Fingerprinting

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:164-174` (Steps 3-4 in MITIGATE)
- Modify: `skills/incident-analysis/references/query-patterns.md:17-25` (Tier 1/2 reference)
- Test: `tests/test-incident-analysis-content.sh`

- [ ] **Step 1: Write failing content tests**

Add to `tests/test-incident-analysis-content.sh` before the node-resource-exhaustion section:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Aggregate-first error fingerprinting (Step 3b)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has aggregate fingerprint step" "Aggregate.*[Ff]ingerprint" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions error distribution" "error distribution\|error.*group\|error.*bucket" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions dominant bucket" "dominant.*bucket\|dominant.*error" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions sample-biased warning" "sample.biased\|sample bias" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions exemplar reads" "exemplar" "${SKILL_FILE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 5 FAIL on aggregate fingerprint assertions

- [ ] **Step 3: Add aggregate query patterns to query-patterns.md**

Add a new section to `skills/incident-analysis/references/query-patterns.md` after the Tier 1 MCP table (line 25):

```markdown
## Aggregate Error Fingerprinting

Prefer aggregate queries to identify the dominant error class before reading raw logs. Availability varies — use the best source available and label the result.

| Tier | Method | Command/Tool | Identifies Error Signatures? | Notes |
|------|--------|-------------|------------------------------|-------|
| Tier 1 | Error group stats | `list_group_stats` with project_id, time_range | **Yes** — groups by recurring stack trace/message | Best source. Not always available (requires Error Reporting API enabled on project). Check availability before relying on it. |
| Tier 2 | Error reporting CLI | `gcloud beta error-reporting events list --service=X --format=json --limit=20` | **Yes** — groups by error signature with counts | Beta command. Same backend as `list_group_stats`. Requires Error Reporting API. |
| Tier 1/2 | Severity-level counts | `list_time_series` with `metric.type="logging.googleapis.com/log_entry_count"` | **No** — counts by severity/container only | Tells you "200 ERRORs on service X" but not which error classes. Useful for magnitude, not fingerprinting. |
| Tier 2 | Client-side bucketing | `gcloud logging read ... --limit=100` piped through jq `group_by(.jsonPayload.message[:80])` | **Partial** — groups within a capped sample | ⚠ Sample-biased. Label as `aggregation_source: sample`. Better than no grouping but still over-represents recent entries. |
```

- [ ] **Step 4: Add Step 3b to SKILL.md between Step 3 and Step 4**

Insert after the current Step 3 block (line 170) and before Step 4 (line 172):

```markdown
### Step 3b: Aggregate Error Fingerprint

Before reading raw log entries for pattern extraction, query the error distribution to identify the dominant error class. This prevents sample bias — 50 recent entries can overrepresent the latest error class instead of the most frequent one.

**Preferred path — Error Reporting API (identifies error signatures):**

**Tier 1:** If `list_group_stats` is available as an MCP tool, use it with the service's project_id and the investigation time range. This provides server-side grouping by recurring error signature with counts.

**Tier 2:** If gcloud is available, try `gcloud beta error-reporting events list --service=<service> --format=json --limit=20`. Same backend, same output.

**If Error Reporting is unavailable** (API not enabled, tool not present, or service doesn't emit structured errors):

**Tier 1/2 fallback — severity counts:** Query `list_time_series` with `logging.googleapis.com/log_entry_count` to get error volume by severity and container. This answers "how many errors?" but not "which error classes?" — use it for magnitude only.

**Tier 2 fallback — client-side bucketing:** Fetch up to 100 log entries (2× the normal Step 3 sample) and group by error message prefix (first 80 chars of `jsonPayload.message` or `textPayload`). **⚠ This is sample-biased** — label results as `aggregation_source: sample` in the synthesis.

**If no aggregate source is available at all:** Proceed with Step 3's existing 50-entry sample. Note `aggregation_source: unavailable` in the synthesis and record as a gap.

**Output:** Identify the top 3-5 error buckets by frequency. Record:
- `aggregation_source`: `error_reporting` (signature-grouped), `metric` (severity counts only), `sample` (client-side bucketing), or `unavailable`
- Dominant bucket with count/percentage
- Whether dominance is clear (>50% of errors) or ambiguous (no bucket >30%)

**Step 4 then becomes exemplar-driven:** Fetch 3-5 raw log entries per dominant bucket for detailed analysis (stack traces, request IDs, trace IDs). Raw logs are exemplars for known buckets, not the discovery mechanism.
```

- [ ] **Step 5: Update Step 4 header to reflect exemplar role**

Change the current `### Step 4: Identify Failing Request Pattern` (line 172) to:

```markdown
### Step 4: Identify Failing Request Pattern (Exemplar-Driven)

Using the dominant error buckets from Step 3b, fetch 3-5 raw log entries per top bucket as exemplars. Extract: endpoint, error code, stack traces, request/trace IDs. If Step 3b was skipped (aggregate tools unavailable), fall back to the current behavior: extract patterns from the Step 3 sample, but note `aggregation_source: unavailable` in the synthesis.
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All pass including 5 new aggregate fingerprint assertions

- [ ] **Step 7: Commit**

```bash
git add skills/incident-analysis/SKILL.md skills/incident-analysis/references/query-patterns.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add aggregate-first error fingerprinting step"
```

---

### Task 2: Canonical Investigation Summary Schema

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:445-484` (Step 7 synthesis)
- Test: `tests/test-incident-analysis-content.sh`

- [ ] **Step 1: Write failing content tests**

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Canonical summary schema (Step 7)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: summary has structured block" "investigation_summary:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has scope" "scope:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has dominant_errors" "dominant_errors:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has chosen_hypothesis" "chosen_hypothesis:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has ruled_out" "ruled_out:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has recovery_status" "recovery_status:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has open_questions" "open_questions:" "${SKILL_FILE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 7 FAIL on canonical summary assertions

- [ ] **Step 3: Add canonical schema to Step 7 in SKILL.md**

After the existing evidence_coverage block (line 482), before "From this point forward", insert:

```markdown
**Canonical investigation summary (mandatory structured block):**

In addition to the prose synthesis above, emit a structured YAML block that the completeness gate, POSTMORTEM stage, and future evals reference. This block captures the investigation's key findings in a consistent, machine-parseable format.

```yaml
investigation_summary:
  scope:
    service: "<service name>"
    environment: "<environment>"
    time_window: "<ISO start>/<ISO end>"
    mode: "full" | "live-triage"
  dominant_errors:
    - bucket: "<error signature or class>"
      count: <N>
      percentage: <N>%
      aggregation_source: "metric" | "error_reporting" | "sample" | "unavailable"
  chosen_hypothesis:
    statement: "<one sentence>"
    confidence: "high" | "medium" | "low"
    supporting_evidence:
      - "<evidence reference>"
    contradicting_evidence_sought: "<what was looked for>"
    contradicting_evidence_found: "<what was found, or 'none'>"
  ruled_out:
    - hypothesis: "<alternative>"
      reason: "<disconfirming evidence>"
  evidence_coverage:
    logs: "complete" | "partial" | "unavailable"
    k8s_state: "complete" | "partial" | "unavailable"
    metrics: "complete" | "partial" | "unavailable"
    source_analysis: "complete" | "partial" | "skipped" | "unavailable"
    trace_correlation: "complete" | "partial" | "skipped" | "unavailable"
  gaps:
    - "<what could not be checked> (<reason>)"
  timeline_entries:
    - timestamp_utc: "<UTC>"
      time_precision: "exact" | "minute" | "approximate"
      event_kind: "<kind>"
      description: "<what happened>"
  recovery_status:
    recovered: true | false | "unknown"
    recovery_time_utc: "<UTC or null>"
    recovery_evidence: "<source>"
    verification: "verified" | "estimated" | "not_verified"
  open_questions:
    - "<question>"
```

The `evidence_coverage` and `gaps` fields in this block replace the standalone evidence_coverage block above — do not duplicate them. The standalone block definition (coverage levels table and gap recording rules) remains as the reference for how to populate these fields.
```

- [ ] **Step 4: Update the standalone evidence_coverage block to reference the canonical schema**

Replace the standalone `evidence_coverage` YAML block (lines 461-471) with a note pointing to the canonical schema:

```markdown
**Evidence coverage and gaps** are captured in the `investigation_summary` structured block below. See the coverage level definitions and gap recording rules that follow for how to populate those fields.
```

Keep the coverage levels table and gap recording rules in place — they define the semantics. Only the duplicate YAML example moves into the canonical block.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add canonical investigation summary schema to Step 7"
```

---

### Task 3: Session-Local Evidence Ledger

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` (new Behavioral Constraint 6)
- Test: `tests/test-incident-analysis-content.sh`

- [ ] **Step 1: Write failing content tests**

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Evidence ledger (Constraint 6)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has evidence ledger constraint" "[Ee]vidence [Ll]edger" "${SKILL_FILE}"
assert_file_contains "SKILL.md: ledger has freshness semantics" "freshness" "${SKILL_FILE}"
assert_file_contains "SKILL.md: ledger excludes EXECUTE recheck" "EXECUTE.*fingerprint\|fingerprint.*recheck\|always re-query" "${SKILL_FILE}"
assert_file_contains "SKILL.md: ledger labels reused evidence" "reused\|original collection" "${SKILL_FILE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 4 FAIL on evidence ledger assertions

- [ ] **Step 3: Add Constraint 6 to SKILL.md**

After the existing Constraint 5 (Evidence Freshness Gate, ~line 73), add:

```markdown
### 6. Evidence Ledger — Reuse Within Freshness Window

Maintain a mental ledger of evidence collected during the investigation, keyed by query fingerprint. The fingerprint varies by query type to prevent false collisions:

| Query type | Fingerprint key |
|-----------|----------------|
| Log queries (LQL) | `(service, environment, severity, LQL_filter_hash, time_window)` |
| Metric queries | `(service, environment, metric_type, aggregation, time_window)` |
| kubectl queries | `(resource_kind, name, namespace, context)` |
| Trace queries | `(trace_id, project_id)` |
| Source analysis | `(repo, commit_ref, file_path)` |

The key must include enough dimensions to prevent collapsing different namespaces, trace-scoped vs service-scoped reads, or caller-vs-affected-service queries. Before issuing a query that matches a prior ledger entry:

1. Check if the entry is within the active playbook's `freshness_window_seconds` (default: 300s if no playbook is active)
2. If fresh: reuse the cached result. Label it as `reused (collected at <UTC>)` in any synthesis or decision record that references it
3. If stale: re-query and update the ledger entry

**Mandatory re-query exceptions — never reuse cached evidence for:**
- EXECUTE Stage fingerprint recheck (Step 1) — always re-query live state
- VALIDATE Stage sampling (Phase 2) — always re-query at each sample interval
- Any query where the user explicitly requests fresh data

This reduces duplicate tool calls across MITIGATE → INVESTIGATE → CLASSIFY cycles while preserving the safety contract where live state matters.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add evidence ledger constraint with freshness semantics"
```

---

### Task 4: Opt-In Live-Triage Mode

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` (new section after Behavioral Constraints, before Stage 1)
- Test: `tests/test-incident-analysis-content.sh`

- [ ] **Step 1: Write failing content tests**

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Live-triage mode
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has live-triage mode" "[Ll]ive.triage" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage is opt-in" "opt.in\|explicit" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage has non-blocking access" "non.blocking" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage has light inventory" "[Ll]ight inventory" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage defers deep inventory" "[Dd]efer.*deep\|[Dd]eep.*defer" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage preserves safety" "fingerprint recheck\|completeness gate\|safety" "${SKILL_FILE}"
assert_file_contains "SKILL.md: full investigation is default" "[Dd]efault.*full\|[Ff]ull.*default" "${SKILL_FILE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 7 FAIL on live-triage assertions

- [ ] **Step 3: Add Investigation Modes section to SKILL.md**

Insert after the Behavioral Constraints section (after new Constraint 6) and before `## Stage 1 — MITIGATE`:

```markdown
## Investigation Modes

### Default: Full Investigation

The complete 6-stage pipeline with all steps executed in order: access gate, full inventory, impact quantification, aggregate fingerprint, investigation, classification, and postmortem. This is the default for `/investigate` and all incident-analysis activations.

### Opt-In: Live Triage

An explicit fast path that prioritizes time-to-first-hypothesis for active, ongoing incidents. Activated only when the user explicitly requests it (e.g., "quick triage", "what's happening right now", "live triage"). The skill may suggest this mode when the prompt describes an active incident, but must not silently switch into it.

**Live-triage behavior — what changes:**

| Step | Full Investigation | Live Triage |
|------|-------------------|-------------|
| Step 1b (Access Gate) | Blocking — wait for fix or explicit proceed | Non-blocking — snapshot access state, proceed immediately, note gaps |
| Step 2b (Inventory) | Full — replicas, distribution, resources, probes, scheduling | Light inventory only — replica count and current status (one query). Deep inventory deferred until after first hypothesis or when symptoms indicate node/distribution dependence |
| Step 2c (Impact) | Before first log query | Deferred until after first hypothesis |
| Steps 3-4 | Unchanged | Unchanged |
| Steps 5-9 | Unchanged | Unchanged |
| CLASSIFY/EXECUTE/VALIDATE | Unchanged | Unchanged — fingerprint recheck, completeness gate, and all safety rules apply |
| POSTMORTEM | Unchanged | Unchanged |

**What does NOT change in live-triage:**
- Access state is still recorded for evidence_coverage
- Light inventory still captures replica count (prevents gross mis-scoping)
- The completeness gate still runs — deferred steps are flagged as gaps if never backfilled
- EXECUTE fingerprint recheck is never skipped
- HITL gate for mutations is never skipped

**Mode recorded in synthesis:** The `investigation_summary.scope.mode` field captures which mode was used, so the postmortem and completeness gate know whether deferred steps were intentional.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All pass

- [ ] **Step 5: Update commands/investigate.md to document live-triage mode**

Add to `commands/investigate.md` after the existing "## Important" section:

```markdown
## Investigation Modes

**Full investigation (default):** All stages run in order with full inventory, impact
quantification, and aggregate fingerprinting before classification.

**Live triage (opt-in):** For active, ongoing incidents where time-to-first-hypothesis matters.
Activated by including "quick triage", "live triage", or "what's happening right now" in
the prompt. Uses non-blocking access check, light inventory (replica count only), and defers
impact quantification until after the first hypothesis.

All safety guarantees (HITL gate, fingerprint recheck, completeness gate) remain active
in both modes.
```

Update the existing "## Important" bullet (line 47) from:
```
- Must not bypass MITIGATE steps (tool detection, inventory, impact quantification)
```
to:
```
- Full investigation must not bypass MITIGATE steps; live-triage defers deep inventory and impact until after first hypothesis
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add skills/incident-analysis/SKILL.md commands/investigate.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add opt-in live-triage mode with deferred inventory"
```

---

### Task 5: Selective Disambiguation Probe for bad-release-rollback

**Files:**
- Modify: `skills/incident-analysis/playbooks/bad-release-rollback.yaml:27` (after veto_signals)
- Test: `tests/test-incident-analysis-content.sh`

- [ ] **Step 1: Write failing content test**

```bash
# ---------------------------------------------------------------------------
# bad-release-rollback.yaml — Disambiguation probe
# ---------------------------------------------------------------------------
assert_file_contains "bad-release-rollback.yaml: has disambiguation probe" \
    "disambiguation_probe" "${PLAYBOOK_DIR}/bad-release-rollback.yaml"
assert_file_contains "bad-release-rollback.yaml: probe resolves error_pattern_predates_deploy" \
    "error_pattern_predates_deploy" "${PLAYBOOK_DIR}/bad-release-rollback.yaml"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 2 FAIL (bad-release-rollback.yaml has no disambiguation_probe yet; note that `error_pattern_predates_deploy` exists in the file as a veto_signal, so only the first assertion should fail)

- [ ] **Step 3: Add disambiguation probe and query to bad-release-rollback.yaml**

After the `error_pattern_query` in the queries section (~line 55), add:

```yaml
  pre_deploy_error_scan:
    kind: log_query
    description: "Check if dominant error signature exists in logs before the deploy timestamp"
    params:
      scope: affected_service
      time_window: "pre_deploy_60m"
      severity: ERROR
      pattern_ref: dominant_error_signature
      max_results: 10
```

After the `contradiction_penalty: 20` line (~line 27), add:

```yaml
disambiguation_probe:
  query_ref: pre_deploy_error_scan
  resolves_signals:
    - error_pattern_predates_deploy
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/playbooks/bad-release-rollback.yaml tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add disambiguation probe to bad-release-rollback playbook"
```

---

### Task 6: Eval Fixture Scaffolding

Scaffolds eval fixtures for future behavioral testing. This task creates the fixture files, a schema validator, and wires the routing fixtures into the existing routing test. It does NOT execute the behavioral assertions against a live agent — that requires an eval runner which is out of scope. The value is: (a) regression-testable fixture format, (b) documented behavioral scenarios ready for a future runner, (c) **routing cases validated against the live routing hook in test-routing.sh**.

**Files:**
- Create: `tests/fixtures/incident-analysis/evals/routing.json` (in `evals/` subdirectory — NOT in the root fixtures dir, which is reserved for real-incident output fixtures per README.md)
- Create: `tests/fixtures/incident-analysis/evals/behavioral.json`
- Create: `tests/test-incident-analysis-evals.sh`
- Modify: `tests/test-routing.sh` (add routing fixture consumer)

- [ ] **Step 1: Write the eval fixture schema test**

Create `tests/test-incident-analysis-evals.sh`:

```bash
#!/usr/bin/env bash
# test-incident-analysis-evals.sh — Validates behavioral eval fixtures for incident-analysis.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-incident-analysis-evals.sh ==="

EVALS_DIR="${PROJECT_ROOT}/tests/fixtures/incident-analysis/evals"
EVALS_FILE="${EVALS_DIR}/routing.json"
ASSERTIONS_FILE="${EVALS_DIR}/behavioral.json"

# ---------------------------------------------------------------------------
# evals.json — Trigger routing eval cases
# ---------------------------------------------------------------------------
if [ ! -f "${EVALS_FILE}" ]; then
    _record_fail "routing.json exists" "file not found"
    print_summary
    exit 0
fi

if jq empty "${EVALS_FILE}" 2>/dev/null; then
    _record_pass "routing.json: valid JSON"
else
    _record_fail "routing.json: valid JSON" "JSON parse error"
    print_summary
    exit 0
fi

# Must have both positive and negative cases
pos_count="$(jq '[.[] | select(.should_trigger == true)] | length' "${EVALS_FILE}")"
neg_count="$(jq '[.[] | select(.should_trigger == false)] | length' "${EVALS_FILE}")"

if [ "${pos_count}" -gt 0 ]; then
    _record_pass "routing.json: has positive trigger cases (${pos_count})"
else
    _record_fail "routing.json: has positive trigger cases" "none found"
fi

if [ "${neg_count}" -gt 0 ]; then
    _record_pass "routing.json: has negative trigger cases (${neg_count})"
else
    _record_fail "routing.json: has negative trigger cases" "none found"
fi

# Each entry must have query and should_trigger
for i in $(jq -r 'keys[]' "${EVALS_FILE}"); do
    query="$(jq -r ".[$i].query // empty" "${EVALS_FILE}")"
    trigger="$(jq -r ".[$i].should_trigger // empty" "${EVALS_FILE}")"
    if [ -z "${query}" ] || [ -z "${trigger}" ]; then
        _record_fail "routing.json entry ${i}: has query and should_trigger" "missing field"
    fi
done
_record_pass "routing.json: all entries have required fields"

# ---------------------------------------------------------------------------
# behavioral-assertions.json — Workflow behavior assertions
# ---------------------------------------------------------------------------
if [ ! -f "${ASSERTIONS_FILE}" ]; then
    _record_fail "behavioral.json exists" "file not found"
    print_summary
    exit 0
fi

if jq empty "${ASSERTIONS_FILE}" 2>/dev/null; then
    _record_pass "behavioral.json: valid JSON"
else
    _record_fail "behavioral.json: valid JSON" "JSON parse error"
    print_summary
    exit 0
fi

# Each scenario must have id, prompt, and assertions array
scenario_count="$(jq 'length' "${ASSERTIONS_FILE}")"
if [ "${scenario_count}" -gt 0 ]; then
    _record_pass "behavioral.json: has scenarios (${scenario_count})"
else
    _record_fail "behavioral.json: has scenarios" "empty array"
fi

for i in $(jq -r 'keys[]' "${ASSERTIONS_FILE}"); do
    sid="$(jq -r ".[$i].id // empty" "${ASSERTIONS_FILE}")"
    prompt="$(jq -r ".[$i].prompt // empty" "${ASSERTIONS_FILE}")"
    assertions="$(jq -r ".[$i].assertions // empty" "${ASSERTIONS_FILE}")"
    if [ -z "${sid}" ] || [ -z "${prompt}" ] || [ -z "${assertions}" ]; then
        _record_fail "behavioral.json entry ${i}: has id, prompt, assertions" "missing field"
    fi
done
_record_pass "behavioral.json: all entries have required fields"

# At least one scenario must test each key behavior
for behavior in "exit.code.*triage\|crashloop.*exit" "evidence_coverage\|gaps" "rollback\|bad.release" "live.triage\|triage.*mode"; do
    if jq -r '.[].assertions[].description' "${ASSERTIONS_FILE}" 2>/dev/null | grep -qi "${behavior}"; then
        _record_pass "behavioral.json: covers ${behavior}"
    else
        _record_fail "behavioral.json: covers ${behavior}" "no assertion matches pattern"
    fi
done

print_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-evals.sh`
Expected: FAIL on "routing.json exists"

- [ ] **Step 3: Create routing.json with trigger routing cases**

Create `tests/fixtures/incident-analysis/evals/routing.json`:

```json
[
  {"query": "payment-service is returning 500s in prod since 2pm, it was fine this morning", "should_trigger": true},
  {"query": "pods for diet-service keep getting OOMKilled, 15 restarts in the last hour", "should_trigger": true},
  {"query": "latency spike on the API gateway, p99 went from 200ms to 5s twenty minutes ago", "should_trigger": true},
  {"query": "we deployed v3.2.1 thirty minutes ago and error rates jumped from 0.1% to 15%, should we rollback?", "should_trigger": true},
  {"query": "there's a production outage affecting auth-service, need to investigate the root cause", "should_trigger": true},
  {"query": "pods stuck in ImagePullBackOff after the deploy, nothing is starting", "should_trigger": true},
  {"query": "connection pool exhausted on the database proxy, timeouts across multiple services", "should_trigger": true},
  {"query": "SLO burn rate alert fired for checkout-service, error budget nearly exhausted", "should_trigger": true},
  {"query": "node gke-prod-pool-abc123 went NotReady, several pods rescheduling", "should_trigger": true},
  {"query": "quick triage — auth-service is down right now, what's happening?", "should_trigger": true},
  {"query": "how does alert routing work in our monitoring setup?", "should_trigger": false},
  {"query": "the helm values for staging aren't being applied correctly, replicas should be 3", "should_trigger": false},
  {"query": "I want to add distributed tracing to my service, what's the right OpenTelemetry setup?", "should_trigger": false},
  {"query": "what branch naming convention should I use for a hotfix?", "should_trigger": false},
  {"query": "can you help me write unit tests for the payment controller?", "should_trigger": false},
  {"query": "I need to create a new microservice for prescription management", "should_trigger": false}
]
```

- [ ] **Step 4: Create behavioral.json**

Create `tests/fixtures/incident-analysis/evals/behavioral.json`:

```json
[
  {
    "id": "crashloop-exit-code-triage",
    "prompt": "user-service pods in CrashLoopBackOff in prod, 12 restarts in the last 30 minutes",
    "expected_behavior": "Must check exit code and termination reason before proposing workload-restart. Exit code 137 should redirect to resource investigation, not restart.",
    "assertions": [
      {"text": "exit.code|termination|exit code", "description": "Mentions exit code triage before restart proposal"},
      {"text": "137|OOMKilled|memory", "description": "Checks for OOMKilled / exit code 137 as restart blocker"},
      {"text": "previous.*log|container.*log", "description": "Checks previous container logs for crash cause"},
      {"text": "rollout.*history|deploy", "description": "Checks rollout history for deploy correlation"}
    ]
  },
  {
    "id": "degraded-access-gap-reporting",
    "prompt": "checkout-service returning 500s in prod. Note: gcloud auth is expired and kubectl is not configured.",
    "expected_behavior": "Must record degraded access in evidence_coverage, list gaps explicitly, and qualify completeness gate answers.",
    "assertions": [
      {"text": "evidence_coverage|coverage", "description": "Emits evidence coverage assessment"},
      {"text": "gap|unavailable|degraded", "description": "Lists explicit gaps from degraded tool access"},
      {"text": "partial|unavailable", "description": "Marks affected domains as partial or unavailable"},
      {"text": "could change|cannot rule out|not possible", "description": "Qualifies conclusions given gaps"}
    ]
  },
  {
    "id": "deploy-correlation-rollback-priority",
    "prompt": "api-gateway v2.5.0 deployed to prod 20 minutes ago, error rate jumped from 0.5% to 12%. Users reporting failures.",
    "expected_behavior": "Must investigate deploy correlation and prefer bad-release-rollback investigation over generic restart.",
    "assertions": [
      {"text": "deploy|deployment|rollback", "description": "Investigates deployment correlation"},
      {"text": "bad.release|rollback|previous.*revision", "description": "Prefers rollback investigation over restart"},
      {"text": "error.*spike.*deploy|deploy.*error", "description": "Correlates error spike with deployment timing"},
      {"text": "HITL|approval|confirm", "description": "Requires user approval before executing rollback"}
    ]
  },
  {
    "id": "live-triage-mode-behavior",
    "prompt": "quick triage — payment-service is down RIGHT NOW, what's happening?",
    "expected_behavior": "Should suggest or enter live-triage mode with non-blocking access check and light inventory.",
    "assertions": [
      {"text": "triage|fast|quick", "description": "Acknowledges urgency or triage mode"},
      {"text": "error|log|status", "description": "Gets to first evidence quickly"},
      {"text": "replica|pod|instance", "description": "Does at least light inventory check"},
      {"text": "hypothesis|cause|root cause", "description": "Produces initial hypothesis"}
    ]
  },
  {
    "id": "multi-service-shared-dependency",
    "prompt": "Multiple services returning 502s and timeouts, all seem to depend on the auth-service which is showing high latency",
    "expected_behavior": "Must identify shared dependency pattern and investigate caller-side amplification.",
    "assertions": [
      {"text": "shared|dependency|upstream", "description": "Identifies shared dependency pattern"},
      {"text": "caller|consumer|dominant", "description": "Investigates caller-side behavior"},
      {"text": "amplification|retry|loop", "description": "Checks for amplification loops"}
    ]
  }
]
```

- [ ] **Step 5: Run eval tests to verify they pass**

Run: `bash tests/test-incident-analysis-evals.sh`
Expected: All pass

- [ ] **Step 6: Wire routing.json into test-routing.sh**

Add a new section to `tests/test-routing.sh` that loads `routing.json` and validates each case against the live routing hook. Add after the existing test sections, before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Routing eval fixtures — incident-analysis trigger/no-trigger cases
# Uses isolated registry with incident-analysis skill installed.
# ---------------------------------------------------------------------------
ROUTING_EVALS="${PROJECT_ROOT}/tests/fixtures/incident-analysis/evals/routing.json"
if [ -f "${ROUTING_EVALS}" ] && command -v jq >/dev/null 2>&1; then
    setup_test_env
    install_registry_with_incident_analysis

    eval_count="$(jq 'length' "${ROUTING_EVALS}")"
    for i in $(seq 0 $((eval_count - 1))); do
        query="$(jq -r ".[$i].query" "${ROUTING_EVALS}")"
        should_trigger="$(jq -r ".[$i].should_trigger" "${ROUTING_EVALS}")"
        short_query="$(printf '%.60s' "${query}")"

        output="$(run_hook "${query}")"
        context="$(extract_context "${output}")"

        if [ "${should_trigger}" = "true" ]; then
            if printf '%s' "${context}" | grep -q "incident-analysis"; then
                _record_pass "routing-eval: triggers on '${short_query}...'"
            else
                _record_fail "routing-eval: triggers on '${short_query}...'" "incident-analysis not in context"
            fi
        else
            if printf '%s' "${context}" | grep -q "incident-analysis"; then
                _record_fail "routing-eval: no trigger on '${short_query}...'" "incident-analysis unexpectedly triggered"
            else
                _record_pass "routing-eval: no trigger on '${short_query}...'"
            fi
        fi
    done

    teardown_test_env
fi
```

- [ ] **Step 7: Run full test suite to verify routing evals pass**

Run: `bash tests/run-tests.sh`
Expected: All test files pass including routing eval fixture tests.

- [ ] **Step 8: Commit**

```bash
git add tests/test-incident-analysis-evals.sh tests/test-routing.sh tests/fixtures/incident-analysis/evals/routing.json tests/fixtures/incident-analysis/evals/behavioral.json
git commit -m "feat(incident-analysis): add eval fixture scaffolding with routing validation and behavioral cases"
```

---

### Task 7: Prepare OpenSpec Proposal Content

The repo uses a change-set driven OpenSpec workflow. Do NOT edit the canonical spec directly, and do NOT create the change-set directory manually — the `openspec-ship` skill at SHIP phase scaffolds the folder via `openspec new change`. This task only prepares the proposal content so the SHIP phase can populate it.

**Files:**
- No files created in this task. The proposal content below is used during SHIP phase (Step 6 in the composition chain) when `openspec-ship` runs.

- [ ] **Step 1: Record proposal content for SHIP phase**

When the `openspec-ship` skill runs at SHIP phase and creates the change folder, populate the generated `proposal.md` with:

```markdown
## Why

Investigation accuracy suffers from sample-biased error fingerprinting (50 recent entries overrepresent the latest error class), freeform synthesis output that makes evals and handoffs inconsistent, and duplicate queries across pipeline stages. Investigation speed is limited by front-loading all MITIGATE steps before the first log query, even during active incidents where time-to-first-hypothesis matters most.

## What Changes

Add aggregate-first error fingerprinting, opt-in live-triage mode, session-local evidence ledger, canonical investigation summary schema, and a disambiguation probe for bad-release-rollback. Preserve the full investigation pipeline as default.

## Capabilities

### New Capabilities
- `aggregate-fingerprint`: Query error distribution before reading raw logs to prevent sample bias. Records aggregation source in synthesis.
- `live-triage-mode`: Opt-in fast path with non-blocking access check, light inventory, and deferred deep inventory. All safety guarantees remain active.
- `evidence-ledger`: Session-local evidence reuse within freshness windows. Per-query-type fingerprinting. EXECUTE recheck always bypasses.
- `canonical-summary`: Structured `investigation_summary` YAML block in Step 7 alongside prose. Enables evals and consistent handoffs.

### Modified Capabilities
- `bad-release-rollback`: Added disambiguation probe that checks if dominant error signature predates the deploy.
- `investigate-command`: Updated to document live-triage mode and mode-specific MITIGATE behavior.

## Impact

Affected: SKILL.md (MITIGATE Steps 3-4, Constraint 6, Investigation Modes, Step 7), query-patterns.md, bad-release-rollback.yaml, commands/investigate.md, test-routing.sh, test-incident-analysis-content.sh. New files: eval fixtures, eval schema test.
```

No commit in this task — the proposal content is consumed by `openspec-ship` during SHIP phase (Step 6), which handles folder creation, spec delta, design, and tasks artifacts.

---

### Task 8: Full Test Suite Verification

- [ ] **Step 1: Run complete test suite**

Run: `bash tests/run-tests.sh`
Expected: All test files pass, including the new eval tests.

- [ ] **Step 2: Verify diff is clean**

Run: `git diff --stat`
Expected: Only the planned files are modified/created.

- [ ] **Step 3: Final commit if any uncommitted changes**

Only if prior tasks left anything unstaged.

---

## Excluded from This Plan (with rationale)

| Item | Reason for exclusion |
|------|---------------------|
| Executable signal engine | High effort, low marginal accuracy gain over declarative guidance |
| Multi-agent investigation | Reduces accuracy through cross-domain context loss (per earlier analysis) |
| Probes for workload-restart, node-resource-exhaustion | Depend on distribution/ratio/observation evidence — single probes can't resolve |
| Traffic-scale-out probe | HPA-managed workloads already blocked by precondition; no bounded yes/no question remaining |
| Infra-failure probe | Already has `disambiguation_probe` referencing `node_status_scan` — refinement only if needed |
| Certificate/DNS/DB playbooks | Each is a separate skill development cycle with its own plan |
| Context discipline code enforcement | Would require structural changes to the investigation flow |
| Additional real-incident fixtures | Require actual production incidents — cannot be authored synthetically per README rules |
