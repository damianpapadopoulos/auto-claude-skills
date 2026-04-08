# Design: Incident Analysis — Investigation Hardening

**Date:** 2026-04-08
**Skill:** incident-analysis (SKILL.md)
**Prerequisite:** Multi-service investigation improvements (Constraint 9, Step 3c, message broker Tier 1, baseline verification, recurring-workload trap, Q11) — shipped same day.
**Motivation:** Post-incident retrospective and independent review identified four remaining structural gaps: no mandatory dual-layer investigation, advisory completeness gate in full mode, no verification of intermediate conclusions, and no anti-anchoring guard for root-cause selection.

## Changes

### 1. Behavioral Constraint 10 — Dual-Layer Investigation

**Location:** `SKILL.md` § Behavioral Constraints, after Constraint 9

**Purpose:** Every root-cause candidate must be assessed on both the infrastructure layer and the application-logic layer. Neither layer alone is sufficient to close an investigation.

**Minimum per-service coverage (via Step 3c):**
- **Infrastructure layer:** deployment history (72h) + at least one runtime signal (pod state/events, resource metrics, or error rate trend)
- **Application layer:** the service's own ERROR logs queried, dominant exception/error class identified, and mechanism status recorded as `known` or `not_yet_traced`

**Full mechanism-level depth** (via Step 3 re-entry) is mandatory only for:
- The chosen root-cause service
- Services that trigger Step 3c → Step 3 re-entry (see Change 3)

For all other services, mechanism status `not_yet_traced` is acceptable — it records that the error class is known but the code path, cache state, and retry behavior were not investigated.

**Text:**

> ### 10. Dual-Layer Investigation
>
> For every service in the error chain, the investigation must assess both the infrastructure layer (deployment history, pod state, resource pressure) and the application layer (exception class, error mechanism). Neither layer alone is sufficient to close an investigation.
>
> **Minimum per-service evidence (enforced via Step 3c):**
> - **Infrastructure:** 72-hour deployment history + at least one runtime signal (pod state/events, resource metrics, or error rate trend)
> - **Application:** the service's own ERROR logs queried, dominant exception/error class identified, mechanism status recorded as `known` (traced to code path, cache state, or consumer behavior) or `not_yet_traced` (error class known, mechanism not investigated)
>
> **Full mechanism-level depth** is mandatory for:
> - The chosen root-cause service (must trace to specific code path, cache/config state, retry/amplification behavior, or consumer mechanism)
> - Any service that triggers Step 3c → Step 3 re-entry (see Step 3c escalation rule)
>
> For all other services, mechanism status `not_yet_traced` is acceptable — it records that the error class is known but the application-layer mechanism was not deeply investigated. This prevents over-investigation of obvious victims while ensuring the root-cause service is traced to mechanism.
>
> **Anti-pattern this prevents:** Building a complete, internally-consistent infrastructure narrative (timeouts, resource pressure, GC pauses) while the actual root cause is an application-layer bug (stale cache, template error, retry storm) in a service whose ERROR logs were never queried.

---

### 2. Extend `service_error_inventory` with layer evidence

**Location:** `SKILL.md` § Step 3c output YAML + § Step 7 investigation_summary YAML

**Purpose:** Record per-service layer assessment with proper status semantics instead of booleans.

**Per-service fields added to `service_error_inventory`:**

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

**Status semantics:**

| Status | Meaning |
|--------|---------|
| `assessed` | Minimum required evidence for that layer is complete — infrastructure: deployment history (72h) + runtime signal; application: ERROR logs queried + dominant exception class identified |
| `not_applicable` | Layer genuinely does not apply to this service in this incident |
| `unavailable` | Could not query — tool missing, auth expired, logs not available (reason required) |
| `not_captured` | Information not present in available evidence sources (reason required) |

**Top-level summary added to `investigation_summary`:**

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

Named `root_cause_layer_coverage` (not `layer_coverage`) to distinguish from per-service entries in `service_error_inventory`.

---

### 3. Step 3c amendment — Tier 1 escalation to full Step 3

**Location:** `SKILL.md` § Step 3c, after existing item 4 (rank services)

**Purpose:** When Step 3c discovers a service that should be the primary investigation target, elevate it to full Step 3 depth instead of leaving it at the Step 3c surface level.

**Trigger conditions (either sufficient):**
- Service ranks highest in diagnostic value in `service_error_inventory` but was not the original Step 3 target
- Service has errors that conflict with the current hypothesis (suggesting an independent root cause rather than a dependent failure)

**Text:**

> **Tier 1 escalation to full Step 3:** When a service meets either condition below, execute a full Step 3 deep dive for that service before proceeding to Step 5:
> - The service ranks highest in diagnostic value (highest tier + most anomalous baseline change) but was not the original Step 3 target
> - The service has errors of a different class than the hypothesized mechanism (suggesting independent failure, not dependent)
>
> The full Step 3 dive includes: error grouping, deployment correlation, resource metrics, and application-logic analysis (call patterns, retry/amplification behavior, cache/config/template state). This is the same depth applied to the primary service — not the Step 3c surface sweep.
>
> **Step 4b applicability:** Step 4b's existing gate conditions apply to re-entered services: source analysis runs when the re-entered service has (1) actionable stack frames, (2) a resolvable deployed ref, AND (3) one of the existing category gates is met (bad-release: deploy within incident window or 4h before; config-change: `config_change_correlated_with_errors` detected with git ref). The re-entry does not broaden Step 4b's gate — it extends Step 4b's applicability to additional services that meet the same criteria.
>
> **Scope:** This re-entry is bounded to the specific service(s) meeting the trigger conditions. It does not cascade — re-entered services do not trigger further re-entries.

---

### 4. Behavioral Constraint 11 — Intermediate Conclusion Verification

**Location:** `SKILL.md` § Behavioral Constraints, after Constraint 10

**Purpose:** Prevent building causal narratives on untested intermediate conclusions.

**Text:**

> ### 11. Intermediate Conclusion Verification
>
> Any intermediate conclusion that will be used in the causal narrative must be explicitly stated and tested with at least one disconfirming query before building on it. This applies to conclusions formed during any investigation step, not just the final hypothesis.
>
> **Common intermediate conclusions that require verification:**
> - "This error is baseline noise" → query the baseline rate and compare numerically (see Tier 3 verification rule)
> - "This service is healthy / not involved" → query its own ERROR logs in the incident window
> - "This failure is dependent on the primary root cause" → verify the service's error class matches the hypothesized mechanism
> - "This workload is the trigger" → check whether it ran without incident on the previous cycle (see recurring-workload trap)
> - "This service's 403/500 responses are expected" → verify the response rate against a non-incident baseline
>
> **Self-check:** Do not build the next investigation step on a conclusion that was inferred but not queried. If you catch yourself thinking "this is probably X" without having queried for confirmation, stop and query.

**Step 5 enforcement sweep:**

Add as a new item 7 in Step 5 (after capacity headroom check):

> 7. **Intermediate conclusion audit:** Before finalizing the hypothesis, list every intermediate conclusion in the causal chain (e.g., "Service X errors are dependent", "This error is baseline", "The batch job is the trigger"). For each, verify it was tested with a disconfirming query per Constraint 11. Any untested conclusion must either be tested now or moved to `open_questions`. Untested conclusions MUST NOT appear in the causal narrative as established facts.

**Structured YAML in `investigation_summary`:**

```yaml
tested_intermediate_conclusions:
  - conclusion: "<explicit statement>"
    used_in_causal_chain: true|false
    disconfirming_evidence_sought: "<query or check performed>"
    result: "supported" | "disproved" | "inconclusive"
    evidence: "<specific result>"
```

---

### 5. Anti-anchoring guard in Step 5

**Location:** `SKILL.md` § Step 5, as a new item 8 (after intermediate conclusion audit)

**Purpose:** When the chosen root-cause service doesn't match the highest-ranked service in `service_error_inventory`, force explicit justification.

**Text:**

> 8. **Anti-anchoring check (when `service_error_inventory` exists):** Compare the chosen root-cause service against the `service_error_inventory` rankings. If the chosen service is NOT the highest diagnostic-value entry, the hypothesis must include explicit evidence for why the lower-ranked service was selected instead. Valid reasons include:
>    - The higher-ranked service's errors were confirmed as dependent on the chosen service (per-service attribution)
>    - The higher-ranked service's errors have a known independent root cause
>    - The higher-ranked service's error count is inflated by retry amplification from the actual root cause
>
>    Without explicit justification, the gate should reject the hypothesis and redirect investigation to the highest-ranked service.

---

### 6. Tighten Step 8 gate for full investigation mode

**Location:** `SKILL.md` § Step 8, replace the current gate rule paragraph

**Purpose:** In full investigation mode, require explicit resolution of all questions while preserving pragmatic handling of genuinely unavailable information.

**Replacement text for the gate rule:**

> **Gate rule — mode-dependent:**
>
> **Full investigation mode:**
> - Q1-Q3 must have confident answers (accounting for evidence gaps). If any is "No" or "Unknown," return to INVESTIGATE Step 1.
> - Q4-Q11 must each be explicitly resolved with one of: an evidence-backed answer, `not_applicable` (genuinely does not apply — with reason), `unavailable` (tool/data missing — with reason), or `not_captured` (information not in available evidence — with reason). Bare "not assessed" is not allowed.
> - **Closure is blocked** when any unresolved item weakens the chosen root cause, the named causal chain, or the root-cause layer coverage. Specifically: for the chosen root-cause service, either layer in `root_cause_layer_coverage` being anything other than `assessed` or a narrow `not_applicable` blocks closure. Additionally, the chosen root-cause service's `mechanism_status` must be `known` — `not_yet_traced` blocks closure for the root-cause service (though it is acceptable for non-root-cause services).
> - Peripheral items may be `not_captured` or `unavailable` and remain as open questions without blocking closure, provided they do not affect the causal chain.
>
> **Live-triage mode:**
> - Q1-Q3 must have answers (may be provisional). If any is "No" or "Unknown," return to INVESTIGATE Step 1.
> - Q4-Q11 remain advisory, but every unresolved item must populate `open_questions` in the synthesis.

---

### 7. Behavioral eval fixtures

**Location:** `tests/fixtures/incident-analysis/evals/behavioral.json`

**Purpose:** Add adversarial scenarios that test the new rules via fixture structure and assertion coverage. These fixtures validate that the skill text contains the right behavioral anchors — they do not execute live investigations. Runtime end-to-end evals (executing prompts and asserting emitted YAML) are a separate follow-up project, explicitly out of scope for this change.

**New fixtures:**

1. **`infra-narrative-hides-app-trigger`** — Strong infrastructure narrative (timeouts, GC pressure, thread exhaustion) on a large monolith, but the actual root cause is a small service with a parsing exception causing a retry storm. Asserts: the small service's ERROR logs are queried, its Tier 1 errors are identified, the investigation shifts focus.

2. **`smaller-service-outranks-familiar-large`** — Two services behind a proxy. Large service has Tier 2 timeout errors. Small service has Tier 1 application exception. Asserts: small service ranks higher, gets Step 3 deep dive, anti-anchoring check passes.

3. **`intermediate-conclusion-challenged`** — A high-frequency error appears "baseline" but is actually 10x elevated. Asserts: baseline is queried quantitatively, error is reclassified to Tier 1, `tested_intermediate_conclusions` includes the baseline verification.

---

## Testing

- Static content tests: Constraints 10-11 exist, Step 3c escalation rule exists, `root_cause_layer_coverage` in schema, gate forbids bare "not assessed" in full mode, `tested_intermediate_conclusions` in schema, anti-anchoring check exists
- Behavioral fixture structure validation (existing test framework)
- Full test suite regression check
- Test file: `tests/test-skill-content.sh` gate rule updated from `4-11` to match new wording

## Files Modified

| File | Change |
|------|--------|
| `skills/incident-analysis/SKILL.md` | Constraints 10-11, Step 3c escalation, Step 5 items 7-8, schema extensions, gate rule replacement |
| `tests/test-incident-analysis-content.sh` | Assertions for all new content |
| `tests/test-skill-content.sh` | Gate rule assertion update |
| `tests/fixtures/incident-analysis/evals/behavioral.json` | 3 new adversarial fixtures |
