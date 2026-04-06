# Incident-Analysis Attribution Rigor Upgrade

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the incident-analysis skill's rigor symmetrical: it must prove why each implicated service belongs in the hypothesis, not just disprove the hypothesis itself. Prevent speculative attribution ("likely because...") by requiring per-service evidence.

**Architecture:** Five targeted insertions into the existing SKILL.md flow (no structural refactor). New behavioral constraint, Step 3 application-logic checklist, Step 5 attribution proof, Step 7 YAML schema extension, Step 8 new completeness gate question. All changes backed by content tests, behavioral evals, and output fixture updates.

**Tech Stack:** Markdown (SKILL.md), JSON (evals, fixtures), Bash 3.2 (tests)

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `skills/incident-analysis/SKILL.md` | Add Constraint 7, extend Step 3/5/7/8, fix "likely" on line 422 |
| Modify | `tests/test-incident-analysis-content.sh` | Add 8 content assertions for new sections |
| Modify | `tests/fixtures/incident-analysis/evals/behavioral.json` | Add 2 eval scenarios, extend 1 existing |
| Modify | `tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json` | Add `service_attribution` expected field |
| Modify | `tests/test-incident-analysis-output.sh` | Add `service_attribution` validation |

**Not changed:** Investigation stage structure, CLASSIFY logic, playbook framework, evidence bundles, caller-investigation.md, postmortem template.

---

### Task 1: Add Behavioral Constraint 7 — Evidence-Only Attribution

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:100-109` (after Constraint 6)

- [ ] **Step 1: Write the content test first**

Add to `tests/test-incident-analysis-content.sh`, before the `print_summary` line:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Evidence-Only Attribution constraint (Constraint 7)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has evidence-only attribution constraint" \
    "Evidence-Only Attribution" "${SKILL_FILE}"
assert_file_contains "SKILL.md: forbids speculative language in synthesis" \
    "likely.*prohibited\|prohibited.*likely\|forbidden.*likely\|likely.*forbidden" "${SKILL_FILE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep -E "FAIL|evidence-only|speculative"`
Expected: 2 FAIL lines.

- [ ] **Step 3: Renumber existing Constraint 7 and add new Constraint 7 to SKILL.md**

The current SKILL.md has `### 7. MCP Result Processing` at line ~100. Renumber it to `### 8. MCP Result Processing` first. Then insert the new constraint after Constraint 6 (line ~109, after "live state matters."):

```markdown
### 7. Evidence-Only Attribution — No Speculative Causal Claims

Every causal claim in the investigation synthesis, `investigation_summary` YAML, and postmortem draft must reference a specific query result. Speculative language is prohibited in final attribution:

| Prohibited in synthesis/YAML | Required replacement |
|------------------------------|---------------------|
| "likely caused by X" | "caused by X (evidence: [query result])" or "not investigated" |
| "probably due to X" | "due to X (evidence: [query result])" or "inconclusive — [what's missing]" |
| "possibly related to X" | Add to `open_questions` with the missing evidence described |
| "may have contributed" | "contributed (evidence: [query result])" or "not investigated" |

**Speculative language IS permitted** in intermediate investigation notes (e.g., "this might indicate X — querying to confirm") where it drives the next query. It is prohibited only in synthesis output, YAML blocks, and postmortem prose where it would be consumed as a conclusion.

**Self-check:** Before emitting the Step 7 synthesis, scan for "likely", "probably", "possibly", "presumably", "may have", "might be" in causal sentences. Replace each with evidence-backed language or move to `open_questions`.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep -E "PASS|FAIL" | tail -5`
Expected: Both new assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add evidence-only attribution constraint"
```

---

### Task 2: Fix Existing "likely" in Step 3 Infrastructure Escalation

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:422`

- [ ] **Step 1: Write the content test**

Add to `tests/test-incident-analysis-content.sh`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — No speculative language in routing heuristics
# ---------------------------------------------------------------------------
# The infrastructure escalation paragraph must not use "likely" as a conclusion
investigate_section="$(sed -n '/^## Stage 2 — INVESTIGATE/,/^## EXECUTE/p' "${SKILL_FILE}")"
if echo "${investigate_section}" | grep -q "root cause is likely"; then
    _record_fail "SKILL.md: no speculative 'likely' in infrastructure escalation" \
        "found 'root cause is likely' in INVESTIGATE section"
else
    _record_pass "SKILL.md: no speculative 'likely' in infrastructure escalation"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep "speculative"`
Expected: FAIL — the current line 422 says "the root cause is likely at the node..."

- [ ] **Step 3: Rewrite line 422**

Replace:
```
**Infrastructure escalation (conditional):** If Step 3 reveals that multiple pods or services are failing simultaneously — especially with `context deadline exceeded`, widespread probe timeouts, or errors localized to a single node — the root cause is likely at the node or infrastructure level, not the application level. Shift investigation to:
```

With:
```
**Infrastructure escalation (conditional):** If Step 3 reveals that multiple pods or services are failing simultaneously — especially with `context deadline exceeded`, widespread probe timeouts, or errors localized to a single node — verify whether the root cause is at the node or infrastructure level by checking:
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep "speculative"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "fix(incident-analysis): replace speculative 'likely' with evidence-directed language"
```

---

### Task 3: Extend Step 3 with Application-Logic Analysis

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:368-372` (Step 3 deep-dive checklist)

- [ ] **Step 1: Write the content test**

Add to `tests/test-incident-analysis-content.sh`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Application-logic analysis in Step 3
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: Step 3 has call pattern analysis" \
    "[Cc]all pattern analysis" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Step 3 mentions N+1 or sequential fan-out" \
    "N+1\|sequential fan.out\|sequential.*permission" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Step 3 mentions gRPC connection analysis" \
    "peer.address\|connection pinning\|gRPC.*caller.*skew" "${SKILL_FILE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep -E "call pattern|N.1|gRPC connection"`
Expected: 3 FAIL lines.

- [ ] **Step 3: Add application-logic checklist to Step 3**

After the existing Step 3 bullets (line 372, after "Resource metrics (CPU, memory, latency) if available"), add:

```markdown
- **Application-logic analysis (for the dominant error path):**
  - **Call pattern detection:** From stack traces in Step 2 exemplars, determine whether the failing code path makes sequential (N+1) calls to the degraded dependency. A loop calling `checkPermission()` per item is N+1; a single `batchCheck()` call is not. If N+1 is detected, note the amplification factor (items per request x latency per call = total request latency).
  - **Retry/amplification analysis:** Check whether the calling code retries failed requests. If a 3-second timeout triggers a retry, each retry adds 3 more seconds of dependency pressure. Look for retry configuration in the stack trace's framework (e.g., Camel redelivery, Spring Retry, gRPC retry policy).
  - **gRPC connection distribution (conditional — when dependency uses gRPC):** If server-side logs include `peer.address`, sample 1 minute of calls and group by caller IP. Compare the distribution against the expected even split (1/N where N = number of client pods). If one caller's share is disproportionately high relative to the expected baseline, flag as potential connection pinning (HTTP/2 over K8s Service ClusterIP load-balances at connection level, not request level). Note: there is no universal threshold — what matters is whether the skew is large enough to explain the observed latency. Report the actual distribution and let the investigator judge.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep -E "call pattern|N.1|gRPC connection"`
Expected: 3 PASS lines.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add application-logic analysis to Step 3 deep dive"
```

---

### Task 4: Add Per-Service Attribution Proof to Step 5

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:490-496` (Step 5, after symptom coverage)

- [ ] **Step 1: Write the content test**

Add to `tests/test-incident-analysis-content.sh`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Per-Service Attribution Proof in Step 5
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has per-service attribution proof" \
    "Per-Service Attribution Proof\|Per-service attribution" "${SKILL_FILE}"
assert_file_contains "SKILL.md: attribution has four-state model" \
    "confirmed-dependent.*independent.*inconclusive.*not-investigated" "${SKILL_FILE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep -E "attribution"`
Expected: 2 FAIL lines.

- [ ] **Step 3: Add attribution proof subsection to Step 5**

After Step 5.2 (Symptom coverage, line ~496), before Step 5.3 (Alternative hypotheses), insert:

```markdown
3. **Per-service attribution proof (when 2+ services/components are implicated):** For every service or component named in the causal story beyond the primary, verify that its errors match the hypothesized mechanism:
   - **Query the service's own error logs** for the specific error class of the hypothesis (e.g., `DEADLINE_EXCEEDED` for a SpiceDB timeout hypothesis, `ConnectionRefused` for a database outage hypothesis).
   - **Classify attribution:**

     | Status | Criteria |
     |--------|----------|
     | `confirmed-dependent` | Service's errors match the hypothesized error class (e.g., DEADLINE_EXCEEDED found) |
     | `independent` | Service has errors but of a different class (e.g., NoResultException instead of DEADLINE_EXCEEDED). Investigate its own failure path: deployment events, application-layer bugs, config changes. |
     | `inconclusive` | Evidence queried but insufficient to determine — e.g., service has errors but error class is ambiguous, or logs are incomplete |
     | `not-investigated` | Service's own error logs were not queried. Must be recorded as a gap in `evidence_coverage`. |

   - **When `independent` is found:** The service has a separate root cause. Check deployment events (FluxCD, ArgoCD, Helm rollout events in k8s_cluster audit logs), recent config changes, and application-layer errors for that service. Record the independent root cause in the synthesis.
   - **When `inconclusive` or `not-investigated`:** Add to `open_questions` in the synthesis. Do NOT attribute the service to the shared root cause without evidence.
```

Then renumber existing items 3→4, 4→5, 5→6.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep -E "attribution"`
Expected: 2 PASS lines.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add per-service attribution proof to Step 5"
```

---

### Task 5: Extend Step 7 YAML Schema with service_attribution

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:570-613` (investigation_summary YAML block)

- [ ] **Step 1: Write the content test**

Add to `tests/test-incident-analysis-content.sh`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — service_attribution in investigation_summary YAML
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: summary schema has service_attribution" \
    "service_attribution:" "${SKILL_FILE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep "service_attribution"`
Expected: FAIL.

- [ ] **Step 3: Add service_attribution to the YAML schema**

In the `investigation_summary` YAML block (after `open_questions`, line ~612), add:

```yaml
  service_attribution:  # optional — required when 2+ services evaluated in one causal narrative
    - service: "<service name>"
      status: "confirmed-dependent" | "independent" | "inconclusive" | "not-investigated"
      evidence: "<specific query result or 'not queried'>"
      independent_root_cause: "<one sentence, only when status=independent and cause known>"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep "service_attribution"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add service_attribution to investigation_summary schema"
```

---

### Task 6: Add Completeness Gate Q10

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:619-637` (Step 8 table)

- [ ] **Step 1: Write the content test**

Add to `tests/test-incident-analysis-content.sh`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Completeness gate Q10 (multi-service attribution)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: completeness gate has Q10" \
    "| 10 |" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Q10 mentions attribution verification" \
    "attribution\|independently\|error.*match" "${SKILL_FILE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep "Q10"`
Expected: 2 FAIL lines.

- [ ] **Step 3: Add Q10 to the completeness gate table**

After Q9 row (line ~633), add:

```markdown
| 10 | For each service attributed to the root cause: does its error class match the hypothesized mechanism? Were non-matching services investigated independently? | `service_attribution` entries with status and evidence per service. Any `not-investigated` or `inconclusive` entries must be flagged as open questions. |
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-incident-analysis-content.sh 2>&1 | grep "Q10"`
Expected: 2 PASS lines.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add completeness gate Q10 for multi-service attribution"
```

---

### Task 7: Add Behavioral Eval Scenarios

**Files:**
- Modify: `tests/fixtures/incident-analysis/evals/behavioral.json`

- [ ] **Step 1: Read the current behavioral.json**

Run: `cat tests/fixtures/incident-analysis/evals/behavioral.json | jq '.[].id'`
Expected: 5 existing scenario IDs.

- [ ] **Step 2: Add two new scenarios and extend one existing**

Add to the JSON array. Each scenario MUST include `id`, `prompt`, `expected_behavior`, and `assertions` with both `text` (regex pattern for machine matching) and `description` fields — matching the existing fixture schema:

```json
{
  "id": "multi-service-independent-failures",
  "prompt": "ocs-proxy shows timeouts to both diet-suggestions and calendar. diet-suggestions has DEADLINE_EXCEEDED from SpiceDB after 3s. Calendar has NoResultException from a database query on mustFindUserByLegacyId. Both started around 14:30 UTC. A FluxCD deployment of calendar v1.194.0-rc.0 happened at 14:12.",
  "expected_behavior": "Must identify two independent root causes. Must prove calendar independence from SpiceDB by querying calendar's own error logs. Must check calendar deployment events. Must not use speculative language in attribution.",
  "assertions": [
    {"text": "independent|separate.*root.*cause|two.*root.*cause", "description": "Identifies two independent root causes, not one shared cause"},
    {"text": "zero.*DEADLINE|no.*DEADLINE|calendar.*not.*SpiceDB", "description": "Proves calendar independence with zero-DEADLINE_EXCEEDED evidence"},
    {"text": "deploy|Flux|rollout|calendar.*v1\\.194", "description": "Checks calendar deployment events independently"},
    {"text": "confirmed.dependent|independent|attribution", "description": "Emits service_attribution with both confirmed-dependent and independent statuses"}
  ]
},
{
  "id": "incomplete-attribution-evidence",
  "prompt": "Three services failing through a shared proxy. Service A has clear database timeout errors. Service B has ambiguous 500 errors with no stack trace. Service C was not queried due to tool unavailability.",
  "expected_behavior": "Must not force all three into a shared hypothesis. Service A is confirmed-dependent, Service B is inconclusive, Service C is not-investigated. Open questions must capture the gaps.",
  "assertions": [
    {"text": "confirmed.dependent", "description": "Service A attributed as confirmed-dependent with evidence"},
    {"text": "inconclusive", "description": "Service B marked as inconclusive, not forced into shared hypothesis"},
    {"text": "not.investigated|gap|unavailable", "description": "Service C marked as not-investigated and recorded as a gap"},
    {"text": "open.question|gap|insufficient", "description": "Does not claim all three share a root cause without per-service evidence"}
  ]
}
```

Find the existing `multi-service-shared-dependency` scenario and add one more assertion to its `assertions` array:

```json
{"text": "N.1|sequential|amplification|connection.*pin|fan.out", "description": "Checks for application-layer amplification patterns (N+1, retry loops, connection pinning)"}
```

- [ ] **Step 3: Update the evals test harness to require attribution-specific coverage**

In `tests/test-incident-analysis-evals.sh`, extend the behavior coverage loop (line 101) to include attribution-specific patterns. Replace the existing `for behavior in ...` line:

```bash
for behavior in "exit.code.*triage\|crashloop.*exit" "evidence_coverage\|gaps" "rollback\|bad.release" "live.triage\|triage.*mode" "independent.*root.*cause\|attribution\|confirmed.dependent" "inconclusive\|not.investigated"; do
```

This adds two new required coverage patterns:
- Attribution proof (independent root causes, confirmed-dependent)
- Incomplete evidence handling (inconclusive, not-investigated)

- [ ] **Step 4: Validate JSON**

Run: `jq empty tests/fixtures/incident-analysis/evals/behavioral.json && echo "valid" || echo "invalid"`
Expected: `valid`

- [ ] **Step 5: Run eval test**

Run: `bash tests/test-incident-analysis-evals.sh 2>&1 | tail -10`
Expected: All PASS, including the two new coverage checks.

- [ ] **Step 6: Commit**

```bash
git add tests/fixtures/incident-analysis/evals/behavioral.json tests/test-incident-analysis-evals.sh
git commit -m "feat(incident-analysis): add attribution rigor behavioral eval scenarios"
```

---

### Task 8: Extend Output Fixture and Output Tests

**Files:**
- Modify: `tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json`
- Modify: `tests/test-incident-analysis-output.sh`

- [ ] **Step 1: Add service_attribution to existing fixture**

Read the current fixture, then add to the `expected` object:

```json
"service_attribution_present": true,
"service_attribution_statuses": ["confirmed-dependent"]
```

This reflects that the SpiceDB cascade fixture has a confirmed-dependent caller (chat-message-suggestion was the dominant caller in that fixture).

- [ ] **Step 2: Add output test validation for service_attribution**

In `tests/test-incident-analysis-output.sh`, after the `cross_reference_patterns` block (line ~180), before `done`, add:

```bash
    # Service attribution (Attribution Rigor upgrade)
    sa_present="$(jq -r '.expected.service_attribution_present // empty' "${fixture_file}")"
    if [ -n "${sa_present}" ]; then
        case "${sa_present}" in
            true|false)
                _record_pass "${fname}: service_attribution_present is boolean (${sa_present})" ;;
            *)
                _record_fail "${fname}: service_attribution_present is boolean" "got: ${sa_present}" ;;
        esac
    fi

    sa_statuses_type="$(jq -r '.expected.service_attribution_statuses | type // empty' "${fixture_file}" 2>/dev/null)"
    if [ -n "${sa_statuses_type}" ] && [ "${sa_statuses_type}" != "null" ]; then
        if [ "${sa_statuses_type}" = "array" ]; then
            # Each status must be one of the four valid values
            all_valid_sa=true
            for status_val in $(jq -r '.expected.service_attribution_statuses[]' "${fixture_file}" 2>/dev/null); do
                case "${status_val}" in
                    confirmed-dependent|independent|inconclusive|not-investigated) ;;
                    *)
                        _record_fail "${fname}: service_attribution_statuses contains valid value" \
                            "got: ${status_val}"
                        all_valid_sa=false ;;
                esac
            done
            if [ "${all_valid_sa}" = "true" ]; then
                _record_pass "${fname}: service_attribution_statuses all valid"
            fi
        else
            _record_fail "${fname}: service_attribution_statuses is array" "got type: ${sa_statuses_type}"
        fi
    fi
```

- [ ] **Step 3: Run output test**

Run: `bash tests/test-incident-analysis-output.sh 2>&1 | tail -10`
Expected: All PASS including new service_attribution assertions.

- [ ] **Step 4: Run all incident-analysis tests**

Run: `bash tests/run-tests.sh 2>&1 | grep -E "incident-analysis|PASS|FAIL|Summary"`
Expected: All test suites pass.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json tests/test-incident-analysis-output.sh
git commit -m "feat(incident-analysis): add service_attribution output fixture and validation"
```

---

### Task 9: Final Verification

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass, zero failures.

- [ ] **Step 2: Verify SKILL.md has no remaining speculative "likely" in causal conclusions**

Run: `grep -n "likely\|probably\|possibly\|presumably\|may have\|might be" skills/incident-analysis/SKILL.md | grep -v "Likely Playbook" | grep -v "Prohibited in" | grep -v "likely caused by" | grep -v "probably due to" | grep -v "possibly related" | grep -v "may have contributed" | grep -v "IS permitted"`

Expected: Zero lines. Allowed matches that are filtered out:
- "Likely Playbook" — quick-reference table column header (not a causal claim)
- "Prohibited in synthesis" table entries — examples of what NOT to write
- "IS permitted" — the intermediate-notes exception clause

If any unfiltered matches remain, they are causal conclusions that must be rewritten.

- [ ] **Step 3: Count the word delta**

Run: `wc -l skills/incident-analysis/SKILL.md`
Expected: ~870 lines (up from 810, ~60 lines added across 5 insertion points).

- [ ] **Step 4: Final commit (if any stragglers)**

```bash
git add -A
git status
# Only commit if there are unstaged changes
```
