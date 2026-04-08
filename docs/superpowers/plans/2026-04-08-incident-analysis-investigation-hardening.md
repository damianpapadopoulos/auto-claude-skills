# Incident Analysis Investigation Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four structural investigation gaps: mandatory dual-layer assessment, blocking completeness gate, intermediate conclusion verification, and anti-anchoring guard.

**Architecture:** All changes target `skills/incident-analysis/SKILL.md` (behavioral instructions), `tests/test-incident-analysis-content.sh` (static assertions), `tests/test-skill-content.sh` (gate rule assertion), and `tests/fixtures/incident-analysis/evals/behavioral.json` (adversarial fixtures). No hook, routing, or registry changes.

**Tech Stack:** Markdown (SKILL.md), Bash (test assertions), JSON (eval fixtures)

**Spec:** `docs/superpowers/specs/2026-04-08-incident-analysis-investigation-hardening-design.md`

---

### Task 1: Add Behavioral Constraint 10 — Dual-Layer Investigation

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` (insert after Constraint 9, before `## Investigation Modes`)
- Modify: `tests/test-incident-analysis-content.sh` (add assertions before `print_summary`)

- [ ] **Step 1: Write the test assertions**

Add to `tests/test-incident-analysis-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Dual-Layer Investigation (Constraint 10)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has dual-layer investigation constraint" \
    "Dual-Layer Investigation" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 10 requires both layers" \
    "infrastructure layer.*application layer\|application layer.*infrastructure layer" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 10 defines mechanism_status" \
    "mechanism_status.*known.*not_yet_traced" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 10 requires mechanism for root cause" \
    "chosen root-cause service.*must trace\|mechanism.*mandatory.*root.cause" "${SKILL_FILE}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 4 FAIL for the new assertions

- [ ] **Step 3: Add Constraint 10 to SKILL.md**

Insert after line 154 (`Step 3c codifies this sweep...`) and before line 156 (`## Investigation Modes`):

```markdown

### 10. Dual-Layer Investigation

For every service in the error chain, the investigation must assess both the infrastructure layer (deployment history, pod state, resource pressure) and the application layer (exception class, error mechanism). Neither layer alone is sufficient to close an investigation.

**Minimum per-service evidence (enforced via Step 3c):**
- **Infrastructure:** 72-hour deployment history + at least one runtime signal (pod state/events, resource metrics, or error rate trend)
- **Application:** the service's own ERROR logs queried, dominant exception/error class identified, mechanism status recorded as `known` (traced to code path, cache state, or consumer behavior) or `not_yet_traced` (error class known, mechanism not investigated)

**Full mechanism-level depth** is mandatory for:
- The chosen root-cause service (must trace to specific code path, cache/config state, retry/amplification behavior, or consumer mechanism)
- Any service that triggers Step 3c → Step 3 re-entry (see Step 3c escalation rule)

For all other services, mechanism status `not_yet_traced` is acceptable — it records that the error class is known but the application-layer mechanism was not deeply investigated. This prevents over-investigation of obvious victims while ensuring the root-cause service is traced to mechanism.

**Anti-pattern this prevents:** Building a complete, internally-consistent infrastructure narrative (timeouts, resource pressure, GC pauses) while the actual root cause is an application-layer bug (stale cache, template error, retry storm) in a service whose ERROR logs were never queried.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add Constraint 10 — dual-layer investigation"
```

---

### Task 2: Extend `service_error_inventory` with layer fields

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` — Step 3c output YAML block + Step 7 investigation_summary YAML block
- Modify: `tests/test-incident-analysis-content.sh` (add assertions before `print_summary`)

- [ ] **Step 1: Write the test assertions**

Add to `tests/test-incident-analysis-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Per-service and top-level layer coverage schema
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: service_error_inventory has infra_status" \
    "infra_status:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: service_error_inventory has app_status" \
    "app_status:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: service_error_inventory has mechanism_status" \
    "mechanism_status:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: has root_cause_layer_coverage block" \
    "root_cause_layer_coverage:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: layer status uses assessed enum" \
    "assessed.*not_applicable.*unavailable.*not_captured" "${SKILL_FILE}"
assert_file_contains "SKILL.md: assessed means minimum evidence complete" \
    "Minimum required evidence.*layer.*complete" "${SKILL_FILE}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 6 FAIL for the new assertions

- [ ] **Step 3: Replace the Step 3c service_error_inventory YAML block**

In `SKILL.md`, replace the Step 3c output YAML block. Find:

```yaml
service_error_inventory:
  - service: "<name>"
    error_class: "<dominant error>"
    tier: 1|2|3
    count_incident: <N>
    count_baseline: <N>
    deployment_in_72h: true|false
    deployment_timestamp: "<UTC or null>"
    investigated: true|false
```

Replace with:

```yaml
service_error_inventory:
  - service: "<name>"
    error_class: "<dominant error>"
    tier: 1|2|3
    count_incident: <N>
    count_baseline: <N>
    deployment_in_72h: true|false
    deployment_timestamp: "<UTC or null>"
    investigated: true|false
    infra_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
    infra_evidence: "<what was checked>"
    infra_reason: "<why not assessed, if status != assessed>"
    app_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
    app_evidence: "<what was checked>"
    app_reason: "<why not assessed, if status != assessed>"
    mechanism_status: "known" | "not_yet_traced" | "not_applicable"
```

Apply the same replacement to the Step 7 investigation_summary copy of the `service_error_inventory` block.

**Status semantics note:** Add after the Step 3c YAML block, before `Services with investigated: false`:

```markdown

**Layer status semantics:**

| Status | Meaning |
|--------|---------|
| `assessed` | Minimum required evidence for that layer is complete — infrastructure: deployment history (72h) + runtime signal; application: ERROR logs queried + dominant exception class identified |
| `not_applicable` | Layer genuinely does not apply to this service in this incident |
| `unavailable` | Could not query — tool missing, auth expired, logs not available (reason required) |
| `not_captured` | Information not present in available evidence sources (reason required) |
```

- [ ] **Step 4: Add `root_cause_layer_coverage` to investigation_summary YAML**

In `SKILL.md`, in the Step 7 investigation_summary YAML block, insert after the `service_error_inventory` block (the extended one) and before the closing ` ``` `:

```yaml
  root_cause_layer_coverage:
    infrastructure_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
    infrastructure_evidence: "<summary of what was checked for the root-cause service>"
    infrastructure_reason: "<why not assessed, if status != assessed>"
    application_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
    application_evidence: "<summary of what was checked for the root-cause service>"
    application_reason: "<why not assessed, if status != assessed>"
    mechanism_status: "known" | "not_yet_traced"
    mechanism_evidence: "<code path, cache/config state, retry behavior, or consumer mechanism identified>"
```

Note: `tested_intermediate_conclusions` is NOT added here — it is added in Task 4 alongside Constraint 11 to preserve clean TDD (all Task 4 assertions fail before implementation).

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): extend service_error_inventory with dual-layer fields and root_cause_layer_coverage"
```

---

### Task 3: Step 3c amendment — Tier 1 escalation to full Step 3

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` — Step 3c, after the re-entry paragraph
- Modify: `tests/test-incident-analysis-content.sh` (add assertions before `print_summary`)

- [ ] **Step 1: Write the test assertions**

Add to `tests/test-incident-analysis-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Step 3c Tier 1 escalation to full Step 3
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: step 3c has Tier 1 escalation rule" \
    "Tier 1 escalation to full Step 3" "${SKILL_FILE}"
assert_file_contains "SKILL.md: step 3c escalation preserves Step 4b gates" \
    "Step 4b.*existing.*gate\|existing.*category gate" "${SKILL_FILE}"
assert_file_contains "SKILL.md: step 3c escalation is bounded" \
    "does not cascade" "${SKILL_FILE}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 3 FAIL for the new assertions

- [ ] **Step 3: Insert escalation rule in Step 3c**

In `SKILL.md`, insert after the "Re-entry from Step 4" paragraph (line 512) and before `### Step 4: Autonomous Trace Correlation` (line 514):

```markdown

**Tier 1 escalation to full Step 3:** When a service meets either condition below, execute a full Step 3 deep dive for that service before proceeding to Step 5:
- The service ranks highest in diagnostic value (highest tier + most anomalous baseline change) but was not the original Step 3 target
- The service has errors of a different class than the hypothesized mechanism (suggesting independent failure, not dependent)

The full Step 3 dive includes: error grouping, deployment correlation, resource metrics, and application-logic analysis (call patterns, retry/amplification behavior, cache/config/template state). This is the same depth applied to the primary service — not the Step 3c surface sweep.

**Step 4b applicability:** Step 4b's existing gate conditions apply to re-entered services: source analysis runs when the re-entered service has (1) actionable stack frames, (2) a resolvable deployed ref, AND (3) one of the existing category gates is met (bad-release: deploy within incident window or 4h before; config-change: `config_change_correlated_with_errors` detected with git ref). The re-entry does not broaden Step 4b's gate — it extends Step 4b's applicability to additional services that meet the same criteria.

**Scope:** This re-entry is bounded to the specific service(s) meeting the trigger conditions. It does not cascade — re-entered services do not trigger further re-entries.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): Step 3c Tier 1 escalation to full Step 3 with Step 4b gate preservation"
```

---

### Task 4: Add Constraint 11 + Step 5 items 7-8

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` — after Constraint 10 (new), Step 5 after item 6
- Modify: `tests/test-incident-analysis-content.sh` (add assertions before `print_summary`)

- [ ] **Step 1: Write the test assertions**

Add to `tests/test-incident-analysis-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Intermediate Conclusion Verification (Constraint 11) + Step 5 items 7-8
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has intermediate conclusion constraint" \
    "Intermediate Conclusion Verification" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 11 requires disconfirming query" \
    "tested with at least one disconfirming query" "${SKILL_FILE}"
assert_file_contains "SKILL.md: step 5 has intermediate conclusion audit" \
    "Intermediate conclusion audit" "${SKILL_FILE}"
assert_file_contains "SKILL.md: step 5 has anti-anchoring check" \
    "Anti-anchoring check" "${SKILL_FILE}"
assert_file_contains "SKILL.md: has tested_intermediate_conclusions schema" \
    "tested_intermediate_conclusions:" "${SKILL_FILE}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 5 FAIL for the new assertions

- [ ] **Step 3: Add Constraint 11 to SKILL.md**

Insert after the Constraint 10 block (which ends with the "Anti-pattern this prevents" paragraph) and before `## Investigation Modes`:

```markdown

### 11. Intermediate Conclusion Verification

Any intermediate conclusion that will be used in the causal narrative must be explicitly stated and tested with at least one disconfirming query before building on it. This applies to conclusions formed during any investigation step, not just the final hypothesis.

**Common intermediate conclusions that require verification:**
- "This error is baseline noise" → query the baseline rate and compare numerically (see Tier 3 verification rule)
- "This service is healthy / not involved" → query its own ERROR logs in the incident window
- "This failure is dependent on the primary root cause" → verify the service's error class matches the hypothesized mechanism
- "This workload is the trigger" → check whether it ran without incident on the previous cycle (see recurring-workload trap)
- "This service's 403/500 responses are expected" → verify the response rate against a non-incident baseline

**Self-check:** Do not build the next investigation step on a conclusion that was inferred but not queried. If you catch yourself thinking "this is probably X" without having queried for confirmation, stop and query.
```

- [ ] **Step 4: Add `tested_intermediate_conclusions` to investigation_summary YAML**

In `SKILL.md`, in the Step 7 investigation_summary YAML block, insert after the `root_cause_layer_coverage` block (added in Task 2) and before the closing ` ``` `:

```yaml
  tested_intermediate_conclusions:
    - conclusion: "<explicit statement>"
      used_in_causal_chain: true|false
      disconfirming_evidence_sought: "<query or check performed>"
      result: "supported" | "disproved" | "inconclusive"
      evidence: "<specific result>"
```

- [ ] **Step 5: Add Step 5 items 7 and 8**

In `SKILL.md`, insert after the last paragraph of Step 5 item 6 (line 615: `...note it as "chronic contributing factor without identified trigger" rather than confirmed root cause.`) and before `### Step 6: Flight Plan` (line 617):

```markdown

7. **Intermediate conclusion audit:** Before finalizing the hypothesis, list every intermediate conclusion in the causal chain (e.g., "Service X errors are dependent", "This error is baseline", "The batch job is the trigger"). For each, verify it was tested with a disconfirming query per Constraint 11. Any untested conclusion must either be tested now or moved to `open_questions`. Untested conclusions MUST NOT appear in the causal narrative as established facts.

8. **Anti-anchoring check (when `service_error_inventory` exists):** Compare the chosen root-cause service against the `service_error_inventory` rankings. If the chosen service is NOT the highest diagnostic-value entry, the hypothesis must include explicit evidence for why the lower-ranked service was selected instead. Valid reasons include:
   - The higher-ranked service's errors were confirmed as dependent on the chosen service (per-service attribution)
   - The higher-ranked service's errors have a known independent root cause
   - The higher-ranked service's error count is inflated by retry amplification from the actual root cause

   Without explicit justification, the gate should reject the hypothesis and redirect investigation to the highest-ranked service.
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add Constraint 11 (intermediate conclusion verification) + Step 5 items 7-8"
```

---

### Task 5: Tighten Step 8 gate for full investigation mode

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` — replace gate rule paragraph
- Modify: `tests/test-incident-analysis-content.sh` (add assertions before `print_summary`)
- Modify: `tests/test-skill-content.sh` (update gate rule assertion)

- [ ] **Step 1: Write the test assertions**

Add to `tests/test-incident-analysis-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Tightened gate rule (full mode vs live-triage)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: gate has full investigation mode section" \
    "Full investigation mode:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate forbids bare not assessed" \
    "Bare.*not assessed.*not allowed" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate requires mechanism_status known for root cause" \
    "mechanism_status.*must be.*known\|mechanism_status.*known.*blocks" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate has live-triage mode section" \
    "Live-triage mode:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate governs Q4-Q11 explicitly" \
    "Q4-Q11 must each be explicitly resolved" "${SKILL_FILE}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 5 FAIL for the new assertions

- [ ] **Step 3: Replace the gate rule paragraph**

In `SKILL.md`, replace the current gate rule (find the exact text):

Old:
```
**Gate rule:** If questions 1-3 have confident answers (accounting for evidence gaps), proceed to POSTMORTEM. Questions 4-11 may be "not assessed" if investigation time is constrained, but must be flagged as open items. If question 1, 2, or 3 is "No" or "Unknown," return to INVESTIGATE Step 1 — for questions 1-2 with a revised hypothesis, for question 3 with targeted recovery-evidence queries.
```

New:
```
**Gate rule — mode-dependent:**

**Full investigation mode:**
- Q1-Q3 must have confident answers (accounting for evidence gaps). If any is "No" or "Unknown," return to INVESTIGATE Step 1 — for questions 1-2 with a revised hypothesis, for question 3 with targeted recovery-evidence queries.
- Q4-Q11 must each be explicitly resolved with one of: an evidence-backed answer, `not_applicable` (genuinely does not apply — with reason), `unavailable` (tool/data missing — with reason), or `not_captured` (information not in available evidence — with reason). Bare "not assessed" is not allowed.
- **Closure is blocked** when any unresolved item weakens the chosen root cause, the named causal chain, or the root-cause layer coverage. Specifically: for the chosen root-cause service, either layer in `root_cause_layer_coverage` being anything other than `assessed` or a narrow `not_applicable` blocks closure. Additionally, the chosen root-cause service's `mechanism_status` must be `known` — `not_yet_traced` blocks closure for the root-cause service (though it is acceptable for non-root-cause services).
- Peripheral items may be `not_captured` or `unavailable` and remain as open questions without blocking closure, provided they do not affect the causal chain.

**Live-triage mode:**
- Q1-Q3 must have answers (may be provisional). If any is "No" or "Unknown," return to INVESTIGATE Step 1.
- Q4-Q11 remain advisory, but every unresolved item must populate `open_questions` in the synthesis.
```

- [ ] **Step 4: Update `tests/test-skill-content.sh` gate assertion**

In `tests/test-skill-content.sh`, replace:

Old:
```bash
assert_contains "gate: rule covers Q11" "4-11" "${GATE_BLOCK}"
```

New:
```bash
assert_contains "gate: full mode requires explicit resolution" "Bare.*not assessed.*not allowed" "${GATE_BLOCK}"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh && bash tests/test-skill-content.sh`
Expected: All PASS in both files

- [ ] **Step 6: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh tests/test-skill-content.sh
git commit -m "feat(incident-analysis): tighten Step 8 gate — full mode blocks on unresolved items and mechanism_status"
```

---

### Task 6: Add behavioral eval fixtures

**Files:**
- Modify: `tests/fixtures/incident-analysis/evals/behavioral.json` (append 3 new entries)
- Modify: `tests/test-incident-analysis-evals.sh` (add coverage assertions for new behaviors)

- [ ] **Step 1: Write the eval coverage test assertions**

In `tests/test-incident-analysis-evals.sh`, find the coverage check loop (line 113):

```bash
for behavior in "exit.code.*triage\|crashloop.*exit" "evidence_coverage\|gaps" "rollback\|bad.release" "live.triage\|triage.*mode" "independent.*root.*cause\|attribution\|confirmed.dependent" "inconclusive\|not.investigated"; do
```

Replace with:

```bash
for behavior in "exit.code.*triage\|crashloop.*exit" "evidence_coverage\|gaps" "rollback\|bad.release" "live.triage\|triage.*mode" "independent.*root.*cause\|attribution\|confirmed.dependent" "inconclusive\|not.investigated" "dual.layer\|app.*layer\|infra.*layer" "anchoring\|rank\|diagnostic.value" "baseline.*verif\|intermediate.*conclusion\|tier.*reclassif"; do
```

- [ ] **Step 2: Run eval tests to verify new coverage checks fail**

Run: `bash tests/test-incident-analysis-evals.sh`
Expected: 3 FAIL for the new behavior coverage patterns

- [ ] **Step 3: Add three new fixtures to behavioral.json**

Read the current `tests/fixtures/incident-analysis/evals/behavioral.json`, then append these three entries before the closing `]`:

```json
  ,
  {
    "id": "infra-narrative-hides-app-trigger",
    "prompt": "Coaches report being logged out from OCS around 14:30 UTC. The ocs-proxy (Apache HTTPD) shows AH01102 timeout errors against backend-core:8080. Backend-core has 7 pods with CPU at 1.0-1.3 cores, memory sawtooth 6.5-11.7 GiB, and Hibernate HHH000104 warnings. A weekday batch job correlates temporally. A smaller service (chat-message-suggestion) also returns 403/500 through the proxy but has not been queried directly.",
    "expected_behavior": "Must query chat-message-suggestion's own container logs (not just the proxy view). Must check both infrastructure layer (deployment, pod state) and application layer (exception class, mechanism) for every service. Must not accept the infrastructure narrative for backend-core as sufficient without checking app-layer triggers in all proxy backends. The dual-layer constraint and intermediary sweep should force investigation of the smaller service.",
    "assertions": [
      {"text": "chat.message.suggestion|smaller.*service|downstream.*service", "description": "Queries the smaller service's own logs, not just proxy access logs"},
      {"text": "dual.layer|infra.*layer.*app.*layer|both.*layer", "description": "Explicitly checks both infrastructure and application layers"},
      {"text": "mechanism|exception.*class|parsing|template|cache", "description": "Traces application-layer mechanism, not just infrastructure symptoms"},
      {"text": "service_error_inventory|rank|diagnostic.value", "description": "Ranks services by diagnostic value and checks for anchoring"}
    ]
  },
  {
    "id": "smaller-service-outranks-familiar-large",
    "prompt": "Two services behind an nginx reverse proxy both returning errors. backend-monolith (8 pods) shows Tier 2 TimeoutException errors at 3x baseline. helper-service (1 pod) shows Tier 1 HandlebarsException at 50x baseline with JMS delivery failures. backend-monolith was investigated first in the single-service deep dive.",
    "expected_behavior": "Must rank helper-service higher due to Tier 1 errors with greater baseline deviation. Must trigger full Step 3 re-entry for helper-service. Anti-anchoring check must fire because the chosen investigation focus (backend-monolith) is not the highest-ranked service. Must trace helper-service mechanism to application level.",
    "assertions": [
      {"text": "helper.service.*rank\|higher.*diagnostic\|tier.1.*outrank", "description": "Ranks the smaller service higher than the familiar monolith"},
      {"text": "re.entry\|full.*step.3\|deep.dive.*helper", "description": "Triggers full Step 3 deep dive for the higher-ranked service"},
      {"text": "anchoring\|not.*highest.*diagnostic\|justify.*lower.ranked", "description": "Anti-anchoring guard fires when focus differs from highest-ranked"},
      {"text": "mechanism.*known\|HandlebarsException\|template.*error", "description": "Traces the application-layer mechanism of the root cause service"}
    ]
  },
  {
    "id": "intermediate-conclusion-challenged",
    "prompt": "A proxy shows 403 errors on /chat-suggestion endpoint. Initial observation: 403s on this endpoint appear in logs from the previous day too, suggesting baseline noise. The proxy also shows timeouts to a large backend service. Investigation focuses on the backend timeout pattern.",
    "expected_behavior": "Must not dismiss the 403s as baseline without querying the quantitative rate. Must compare incident-day count vs baseline-day count. If the rate is significantly elevated (e.g., 10x), must reclassify from Tier 3 to Tier 1. The intermediate conclusion 'this is baseline noise' must appear in tested_intermediate_conclusions with the disconfirming evidence.",
    "assertions": [
      {"text": "baseline.*rate\|quantitative\|compare.*count", "description": "Queries baseline rate quantitatively before dismissing as noise"},
      {"text": "reclassif\|tier.1\|elevated\|order.of.magnitude", "description": "Reclassifies error when baseline comparison shows significant increase"},
      {"text": "tested_intermediate_conclusions\|intermediate.*conclusion.*tested", "description": "Records the baseline verification as a tested intermediate conclusion"},
      {"text": "not.*dismiss\|cannot.*assume\|verify.*before", "description": "Does not accept baseline classification without evidence"}
    ]
  }
```

- [ ] **Step 4: Run eval tests to verify they pass**

Run: `bash tests/test-incident-analysis-evals.sh`
Expected: All PASS including 3 new coverage checks

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/incident-analysis/evals/behavioral.json tests/test-incident-analysis-evals.sh
git commit -m "feat(incident-analysis): add 3 adversarial behavioral eval fixtures for hardening rules"
```

---

### Task 7: Run full test suite and verify structure

**Files:**
- None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All test files pass. 0 failures.

- [ ] **Step 2: Syntax-check the hook**

Run: `bash -n hooks/skill-activation-hook.sh`
Expected: No syntax errors (exit 0)

- [ ] **Step 3: Verify SKILL.md constraint numbering**

Run: `grep -n '^### [0-9]' skills/incident-analysis/SKILL.md`
Expected: Sequential 1-11 with no duplicates or gaps.

- [ ] **Step 4: Verify Step 5 item numbering**

Run: `grep -n '^[0-9]\+\.' skills/incident-analysis/SKILL.md | grep -A1 "Step 5"`
Alternatively: visually verify items 1-8 in Step 5 are sequential.

- [ ] **Step 5: Verify investigation_summary schema has all new blocks**

Run: `grep -c 'root_cause_layer_coverage:' skills/incident-analysis/SKILL.md && grep -c 'tested_intermediate_conclusions:' skills/incident-analysis/SKILL.md && grep -c 'mechanism_status:' skills/incident-analysis/SKILL.md`
Expected: Each returns at least 1 (root_cause_layer_coverage appears once in synthesis, tested_intermediate_conclusions once in synthesis, mechanism_status appears in both Step 3c and synthesis schema).
