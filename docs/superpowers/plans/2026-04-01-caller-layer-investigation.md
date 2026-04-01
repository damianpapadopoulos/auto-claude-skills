# Caller-Layer Investigation Logic — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add mandatory caller-health investigation to the incident-analysis skill so shared-dependency incidents are investigated at all three layers (infrastructure, middleware, application) before declaring root cause.

**Architecture:** Strengthen existing INVESTIGATE Step 3 sub-escalations (shared resource escalation, amplification loop detection) from conditional guidance to mandatory checks when a shared dependency is identified. Add completeness gate enforcement. Wire new signal into playbook classification. Add behavioral contract tests and a regression fixture.

**Tech Stack:** Bash 3.2, YAML (signals.yaml, playbooks), Markdown (SKILL.md), JSON (test fixtures)

**Baseline failure (RED phase):** The 2026-03-09 OCS investigation correctly found SpiceDB CPU saturation but missed the application-level trigger — a chat-message-suggestion retry storm from a broken Handlebars template. The skill already contained the right concepts (shared resource escalation, amplification loop detection, chronic-vs-acute test) but they were conditional paths that the agent skipped because it didn't recognize the triggering conditions. This plan makes those checks mandatory and verifiable.

**Review findings addressed (rounds 1+2):**
- [P1] Signal wired into playbook (not just registry) — Task 6 + Task 7
- [P1] Tests written BEFORE implementation (true TDD) — Tasks 1-3 are RED, Tasks 4-7 are GREEN
- [P1] Behavioral assertions scoped to extracted blocks (no false positives) — Task 2
- [P1] Fixture includes optional fields so harness validation is exercised — Task 1 + Task 3
- [P2] Gate rule updated for Q9 — Task 5
- [P2] Compound signal uses inline method/params (matches existing registry) — Task 6
- [P2] Array type check before length check — Task 3
- [P3] Preserves 72-hour deployment history check — Task 4

**Task order rationale (TDD):**
- Tasks 1-3: **RED** — write tests that fail against the current SKILL.md
- Tasks 4-7: **GREEN** — implement changes that make tests pass
- Tasks 8-9: **VERIFY** — run full suite

---

### Task 1: Create test fixture (RED)

**Files:**
- Create: `tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json`

- [ ] **Step 1: Write the fixture file**

Includes the optional caller-investigation fields so Task 3's harness validation is exercised.

```json
{
  "id": "2026-03-09-ocs-spicedb-cascade",
  "description": "SpiceDB latency cascade triggered by chat-message-suggestion retry storm from broken Handlebars template cache. Infrastructure investigation found CPU saturation but the application-level trigger (poison-pill JMS messages causing tight retry loop) was only found by checking the dominant caller's own error logs.",
  "source_postmortem": "docs/postmortems/2026-03-09-ocs-spicedb-latency-cascade.md",
  "input": {
    "service": "spicedb",
    "environment": "oviva-k8s-prod",
    "symptoms": "coaches reporting OCS access issues, multiple services returning 502/500, readiness probe failures across all nodes",
    "time_window": "2026-03-09T13:00:00Z/2026-03-09T16:00:00Z"
  },
  "expected": {
    "root_cause_contains": [
      "retry storm",
      "chat-message-suggestion",
      "caller"
    ],
    "timeline_has_entries": true,
    "playbook_classification": "dependency-failure",
    "signals_detected": [
      "cpu_saturation_detected",
      "caller_retry_storm"
    ],
    "investigation_layer": "application",
    "caller_health_checked": true,
    "dominant_callers_identified": [
      "ocs_v2",
      "chat-message-suggestion"
    ]
  }
}
```

- [ ] **Step 2: Validate fixture passes existing schema checks**

Run: `bash tests/test-incident-analysis-output.sh`
Expected: PASS — fixture has `id`, `description`, `input` with required sub-fields, non-empty `expected`. (The new optional fields are ignored by the current harness — Task 3 adds validation for them.)

- [ ] **Step 3: Commit**

```bash
git add tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json
git commit -m "test(incident-analysis): add OCS/SpiceDB cascade fixture for caller-layer regression"
```

---

### Task 2: Add behavioral contract tests for caller investigation rules (RED)

**Files:**
- Modify: `tests/test-skill-content.sh` (insert before the final `print_summary`)

These assertions will **FAIL** against the current SKILL.md because the mandatory caller investigation wording doesn't exist yet. That's the point — this is the RED phase.

- [ ] **Step 1: Read current end of test-skill-content.sh**

Run: read `tests/test-skill-content.sh` lines 188-192.
Confirm: ends with `test_investigate_references_preflight` and `print_summary`.

- [ ] **Step 2: Add scoped assertions before print_summary**

Replace the final `print_summary` with:

```bash
# ---------------------------------------------------------------------------
# Caller-layer investigation rules (shared-dependency incidents)
# Scoped to specific SKILL.md sections to avoid false positives.
# ---------------------------------------------------------------------------
echo "-- test: caller investigation rules --"

# Step 3: shared resource escalation must contain mandatory caller checks
STEP3_BLOCK=$(sed -n '/### Step 3: Single-Service Deep Dive/,/### Step 4/p' "${SKILL_FILE}")
assert_contains "step 3: escalation is mandatory" "mandatory when detected" "${STEP3_BLOCK}"
assert_contains "step 3: enumerate callers from access logs" "Enumerate callers from access logs" "${STEP3_BLOCK}"
assert_contains "step 3: check dominant caller ERROR logs" "Check each dominant caller" "${STEP3_BLOCK}"
assert_contains "step 3: compare to different day baseline" "different day" "${STEP3_BLOCK}"
assert_contains "step 3: deployment history scoped to dominant callers" "deployment history for all dominant callers" "${STEP3_BLOCK}"
assert_contains "step 3: amplification loop inside caller check" "Check for amplification loops" "${STEP3_BLOCK}"

# Step 5: chronic-vs-acute requires caller evidence for traffic hypotheses
STEP5_BLOCK=$(sed -n '/### Step 5: Formulate Root Cause/,/### Step 6/p' "${SKILL_FILE}")
assert_contains "step 5: caller retry loop candidate" "caller entering a failure/retry loop" "${STEP5_BLOCK}"
assert_contains "step 5: traffic baseline from different day" "different day at the same time" "${STEP5_BLOCK}"

# Step 8: completeness gate has caller-health question and updated rule
GATE_BLOCK=$(sed -n '/### Step 8: Investigation Completeness Gate/,/### Step 9/p' "${SKILL_FILE}")
assert_contains "gate: caller question exists" "dominant callers" "${GATE_BLOCK}"
assert_contains "gate: rule covers Q9" "4-9" "${GATE_BLOCK}"

print_summary
```

- [ ] **Step 3: Run tests to confirm RED (these MUST fail)**

Run: `bash tests/test-skill-content.sh`
Expected: **FAIL** on 8 of 10 new assertions. The two that match existing wording (`"deployment history for all dominant callers"` and `"Check for amplification loops"`) will fail because the current text uses different phrasing ("check deployment history for all consumers" and "check for amplification loops" with lowercase "check"). The remaining 8 assert phrases that don't exist at all in the current SKILL.md. Existing assertions still pass.

- [ ] **Step 4: Commit the failing tests**

```bash
git add tests/test-skill-content.sh
git commit -m "test(incident-analysis): RED - add caller investigation contract tests (expected to fail)"
```

---

### Task 3: Extend fixture harness with caller-investigation field validation (RED)

**Files:**
- Modify: `tests/test-incident-analysis-output.sh:68-75`

- [ ] **Step 1: Read current fixture loop end**

Run: read `tests/test-incident-analysis-output.sh` lines 68-76.
Confirm: ends with `exp_keys` check, `fi`, `done`, `print_summary`.

- [ ] **Step 2: Add optional field validation inside the fixture loop**

After the `exp_keys` assertion block (`fi` at ~line 74), before the `done` at ~line 75, insert:

```bash

    # Optional caller-investigation fields
    inv_layer="$(jq -r '.expected.investigation_layer // empty' "${fixture_file}")"
    if [ -n "${inv_layer}" ]; then
        case "${inv_layer}" in
            application|infrastructure|middleware)
                _record_pass "${fname}: investigation_layer is valid (${inv_layer})"
                ;;
            *)
                _record_fail "${fname}: investigation_layer is valid" "expected application|infrastructure|middleware, got: ${inv_layer}"
                ;;
        esac
    fi

    caller_checked="$(jq -r '.expected.caller_health_checked // empty' "${fixture_file}")"
    if [ -n "${caller_checked}" ]; then
        case "${caller_checked}" in
            true|false)
                _record_pass "${fname}: caller_health_checked is boolean (${caller_checked})"
                ;;
            *)
                _record_fail "${fname}: caller_health_checked is boolean" "got: ${caller_checked}"
                ;;
        esac
    fi

    dom_callers_type="$(jq -r '.expected.dominant_callers_identified | type // empty' "${fixture_file}" 2>/dev/null)"
    if [ -n "${dom_callers_type}" ] && [ "${dom_callers_type}" != "null" ]; then
        if [ "${dom_callers_type}" = "array" ]; then
            caller_count="$(jq '.expected.dominant_callers_identified | length' "${fixture_file}")"
            if [ "${caller_count}" -gt 0 ] 2>/dev/null; then
                _record_pass "${fname}: dominant_callers_identified is array with entries (${caller_count})"
            else
                _record_fail "${fname}: dominant_callers_identified has entries" "array is empty"
            fi
        else
            _record_fail "${fname}: dominant_callers_identified is array" "got type: ${dom_callers_type}"
        fi
    fi
```

- [ ] **Step 3: Run fixture tests to confirm new fields are exercised**

Run: `bash tests/test-incident-analysis-output.sh`
Expected: PASS — the OCS fixture from Task 1 includes `investigation_layer: "application"`, `caller_health_checked: true`, and `dominant_callers_identified: [...]`, all of which now get validated. Existing fixtures without these fields still pass (validation is optional).

- [ ] **Step 4: Commit**

```bash
git add tests/test-incident-analysis-output.sh
git commit -m "test(incident-analysis): RED - validate caller-investigation fields in fixtures"
```

---

### Task 4: Make caller investigation mandatory in SKILL.md Step 3 (GREEN)

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:368-383`

- [ ] **Step 1: Read current content to confirm line range**

Run: read `skills/incident-analysis/SKILL.md` lines 366-384.
Confirm: starts with `**Shared resource escalation (conditional):**` at line 368, amplification loop detection ends at line 383.

- [ ] **Step 2: Replace shared resource escalation + amplification loop detection**

Replace from `**Shared resource escalation (conditional):**` through `...is likely the root cause.` with:

```markdown
**Shared resource escalation (mandatory when detected):** If the degraded service is used by multiple consumers (authorization service, database, message broker, cache cluster, shared API gateway), this escalation is **mandatory**, not optional. Detection heuristic — any of these confirm a shared dependency:
- Multiple different services show correlated errors in the same time window
- The degraded service's access logs show requests from multiple distinct peer addresses/pods
- The degraded service is a known infrastructure component (SpiceDB, Redis, PostgreSQL, RabbitMQ, etc.)

When a shared dependency is identified:

1. **Enumerate callers from access logs:** Extract the distinct peer addresses (caller IPs) from the shared service's own logs during the incident window. Group by caller and count. Identify the top 3 callers by volume.
2. **Identify caller services:** For each dominant caller IP, resolve to a service name via trace correlation (`get_trace` on a trace ID from that caller's requests), pod events (health probe targets contain pod IPs), or log correlation.
3. **Check each dominant caller's ERROR logs:** Query `severity>=ERROR` for each identified caller service in the same time window. This is the critical step that infrastructure-only investigation misses — a caller may be in a failure/retry loop that is *generating* the shared dependency overload, not just suffering from it.
4. **Check deployment history for all dominant callers:** Query deployments across dominant callers in the preceding 72 hours (not just the incident day). Account for delayed triggers: cached configurations, lazy initialization, and traffic-pattern-dependent code paths that may not execute until weekday/peak hours.
5. **Compare caller distribution to baseline:** Compare the current caller distribution to a **different day's same time window** (not just the same day's morning). If a single caller's share increased by >2x compared to baseline, it is a suspect — especially if that caller is also logging errors. If access logs or caller IP resolution are unavailable, note "caller distribution not assessed" and flag as an open question.
6. **Check for amplification loops:** If any dominant caller shows error counts disproportionate to normal traffic volume, check for amplification signatures:
   - Rapidly repeating identical error messages from a single source (same exception, same stack frame)
   - Message broker redelivery patterns (JMS/AMQP poison-pill messages that fail processing and get requeued)
   - Transaction management annotations that acquire new connections per retry (`REQUIRES_NEW`, nested transactions)
   - Error counts that cannot be explained by user traffic volume (e.g., 60K errors in a 2-hour window from a low-traffic service)
   When an amplification loop is identified, trace it to the original failing operation — that operation's failure reason (not the resource exhaustion it caused) is the root cause.

This escalation is bounded to the shared resource's known consumer set. It does not permit unbounded global searches.
```

- [ ] **Step 3: Run scoped tests**

Run: `bash tests/test-skill-content.sh 2>&1 | tee /dev/stderr | grep "step 3:" | grep -c "FAIL"` — must output `0`. Then verify: `bash tests/test-skill-content.sh 2>&1 | grep "step 3:" | grep -c "PASS"` — must output `6`.
Expected: 6 PASS, 0 FAIL for "step 3:" assertions. If `test-skill-content.sh` exits non-zero, check full output for which assertion failed.

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): make caller investigation mandatory for shared-dependency incidents"
```

---

### Task 5: Strengthen Step 5 chronic-vs-acute test + add completeness gate Q9 (GREEN)

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:466-472` (Step 5) and `skills/incident-analysis/SKILL.md:500-511` (Step 8)

- [ ] **Step 1: Read Step 5 chronic-vs-acute section**

Run: read `skills/incident-analysis/SKILL.md` lines 466-472.
Confirm: bullet list ends with `(amplification loop — see Step 3)`.

- [ ] **Step 2: Add caller-evidence requirement to Step 5**

After the line ending with `(amplification loop — see Step 3)`, insert:

```markdown
   - A caller entering a failure/retry loop (check Step 3 shared resource escalation findings — if dominant callers were not yet checked, return to Step 3 and complete the caller investigation before accepting a chronic hypothesis)

   **Mandatory evidence for traffic-pattern hypotheses:** If the hypothesis attributes the trigger to a traffic pattern change (e.g., "afternoon peak traffic"), verify against a baseline from a **different day at the same time**. Compare: caller distribution, call volume per caller, and method mix. If the pattern matches the baseline (same callers, same volume), the traffic hypothesis is supported. If one caller's volume is anomalously high, investigate that caller's health before accepting the hypothesis.
```

- [ ] **Step 3: Read Step 8 completeness gate**

Run: read `skills/incident-analysis/SKILL.md` lines 496-512.
Confirm: table ends with question 8, gate rule says "Questions 4-8".

- [ ] **Step 4: Add question 9 to the table**

After the row for question 8, add:

```markdown
| 9 | For shared-dependency failures: were dominant callers' error logs checked? | List top callers by volume, state whether their error logs were queried, and whether any caller was in a failure/retry loop. If shared-dependency escalation was not triggered, state "N/A — not a shared-dependency failure". |
```

- [ ] **Step 5: Update the gate rule**

Replace `Questions 4-8 may be "not assessed"` with `Questions 4-9 may be "not assessed"`.

- [ ] **Step 6: Run scoped tests**

Run: `bash tests/test-skill-content.sh 2>&1 | grep -E "step 5:|gate:" | grep -c "FAIL"` — must output `0`. Then: `bash tests/test-skill-content.sh 2>&1 | grep -E "step 5:|gate:" | grep -c "PASS"` — must output `4`.
Expected: 4 PASS, 0 FAIL for "step 5:" and "gate:" assertions.

- [ ] **Step 7: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): require caller evidence in hypothesis + add completeness gate Q9"
```

---

### Task 6: Add `caller_retry_storm` signal to signals.yaml (GREEN)

**Files:**
- Modify: `skills/incident-analysis/signals.yaml`

Uses inline `method`/`params` objects inside the compound, matching the existing pattern (see `memory_pressure_detected` at lines 52-67).

- [ ] **Step 1: Find insertion point**

Run: read `skills/incident-analysis/signals.yaml` lines 195-240.
Find: the boundary between workload health signals and config/dependency signals.

- [ ] **Step 2: Insert caller behavior signals**

After the last workload health signal, before the config/dependency section header, insert:

```yaml

  # ---------------------------------------------------------------------------
  # Caller behavior signals
  # ---------------------------------------------------------------------------

  caller_retry_storm:
    title: "Dominant caller in retry/error loop"
    base_weight: 30
    detection:
      method: compound
      params:
        all_of:
          - method: distribution
            params:
              group_by: peer_address
              distribution_threshold: 0.5
              min_sample_size: 20
          - method: log_pattern
            params:
              pattern: "severity>=ERROR from dominant caller service"
              source: caller_service_logs
              min_occurrences: 10
              recency_window_seconds: 600
```

- [ ] **Step 3: Validate YAML syntax**

Run: `ruby -ryaml -e "YAML.load_file('skills/incident-analysis/signals.yaml')" && echo "YAML OK"`
Expected: `YAML OK`

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/signals.yaml
git commit -m "feat(incident-analysis): add caller_retry_storm signal with inline compound detection"
```

---

### Task 7: Wire `caller_retry_storm` into dependency-failure playbook (GREEN)

**Files:**
- Modify: `skills/incident-analysis/playbooks/dependency-failure.yaml:11-13`

- [ ] **Step 1: Read current playbook signals**

Run: read `skills/incident-analysis/playbooks/dependency-failure.yaml` lines 11-16.
Confirm: `supporting` has only `upstream_dependency_errors`.

- [ ] **Step 2: Insert `caller_retry_storm` under supporting signals**

This is a targeted single-line insertion. Leave `contradicting`, `veto_signals`, and `contradiction_penalty` unchanged.

Insert `    - caller_retry_storm` after the existing `    - upstream_dependency_errors` line (line 13). The result should be:

```yaml
signals:
  supporting:
    - upstream_dependency_errors
    - caller_retry_storm
  contradicting: []
  veto_signals: []
  contradiction_penalty: 0
```

- [ ] **Step 3: Run signal registry cross-reference**

Run: `bash tests/test-signal-registry.sh`
Expected: `dependency-failure.yaml: signal 'caller_retry_storm' exists in signals.yaml` PASS. All existing cross-references still pass.

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/playbooks/dependency-failure.yaml
git commit -m "feat(incident-analysis): wire caller_retry_storm into dependency-failure playbook"
```

---

### Task 8: Run full test suite (VERIFY)

- [ ] **Step 1: Run all tests**

Run: `bash tests/run-tests.sh`
Expected: all test suites pass

- [ ] **Step 2: Run skill content contract tests (the RED assertions from Task 2)**

Run: `bash tests/test-skill-content.sh`
Expected: all 10 caller investigation assertions PASS. All existing assertions still pass.

- [ ] **Step 3: Run signal registry cross-reference**

Run: `bash tests/test-signal-registry.sh`
Expected: `caller_retry_storm` resolved in signals.yaml and referenced by dependency-failure.yaml. All existing checks pass.

- [ ] **Step 4: Run fixture validation**

Run: `bash tests/test-incident-analysis-output.sh`
Expected: OCS/SpiceDB fixture passes schema validation AND the new optional field validation (investigation_layer, caller_health_checked, dominant_callers_identified).

- [ ] **Step 5: Verify SKILL.md step numbering consistency**

Run: `grep -n '### Step' skills/incident-analysis/SKILL.md`
Expected: sequential numbering in INVESTIGATE stage (Steps 1-9), no gaps or duplicates.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(incident-analysis): caller-layer investigation logic for shared-dependency incidents"
```
