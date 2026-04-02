#!/usr/bin/env bash
# test-skill-content.sh — SKILL.md behavioral contract assertions
# Validates that required concepts, safety invariants, and decision structures
# are documented in the incident-analysis skill file or its reference files.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-skill-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# ---------------------------------------------------------------------------
# CLASSIFY reference file (extracted from SKILL.md)
# ---------------------------------------------------------------------------
CLASSIFY_REF="${PROJECT_ROOT}/skills/incident-analysis/references/classify-scoring.md"
CLASSIFY_REF_CONTENT="$(cat "${CLASSIFY_REF}")"

# ---------------------------------------------------------------------------
# Confidence bands (now in reference file)
# ---------------------------------------------------------------------------
assert_contains "confidence band: 85 threshold" "85" "${CLASSIFY_REF_CONTENT}"
assert_contains "confidence band: 60 threshold" "60" "${CLASSIFY_REF_CONTENT}"
assert_contains "confidence band: < 60 path" "< 60" "${CLASSIFY_REF_CONTENT}"

# ---------------------------------------------------------------------------
# Signal scoring fields (now in reference file)
# ---------------------------------------------------------------------------
assert_contains "contradiction scoring documented" "contradiction_score" "${CLASSIFY_REF_CONTENT}"
assert_contains "veto_signals documented" "veto_signals" "${CLASSIFY_REF_CONTENT}"

# ---------------------------------------------------------------------------
# Decision records contain signal evaluation sections (both tiers)
# ---------------------------------------------------------------------------
assert_contains "SIGNALS EVALUATED in decision record" "CLASSIFY DECISION" "${CLASSIFY_REF_CONTENT}"
assert_contains "contradiction in signal evaluation" "contradiction" "${CLASSIFY_REF_CONTENT}"
assert_contains "high confidence decision record" "HIGH CONFIDENCE" "${CLASSIFY_REF_CONTENT}"
assert_contains "medium confidence decision record" "MEDIUM CONFIDENCE" "${CLASSIFY_REF_CONTENT}"
assert_contains "SIGNALS EVALUATED section in records" "SIGNALS EVALUATED" "${CLASSIFY_REF_CONTENT}"

# ---------------------------------------------------------------------------
# VALIDATE stage references stabilization_delay_seconds
# ---------------------------------------------------------------------------
assert_contains "VALIDATE references stabilization_delay_seconds" "stabilization_delay_seconds" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# Fingerprint recheck documented between approval and execution
# ---------------------------------------------------------------------------
assert_contains "fingerprint recheck documented" "Fingerprint Recheck" "${SKILL_CONTENT}"
assert_contains "fingerprint drift documented" "fingerprint has drifted" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# redact-evidence.sh referenced before persistence
# ---------------------------------------------------------------------------
assert_contains "redact-evidence.sh referenced" "redact-evidence.sh" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# Three VALIDATE exit paths
# ---------------------------------------------------------------------------
assert_contains "VALIDATE exit: verified" "verification_status: verified" "${SKILL_CONTENT}"
assert_contains "VALIDATE exit: failed" "verification_status: failed" "${SKILL_CONTENT}"
assert_contains "VALIDATE exit: unverified" "verification_status: unverified" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# CLASSIFY stage exists as a section header
# ---------------------------------------------------------------------------
assert_contains "CLASSIFY stage section" "## CLASSIFY" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# Loop termination — stall detection (now in reference file)
# ---------------------------------------------------------------------------
assert_contains "loop termination: 3 iterations" "3 reclassification iterations" "${CLASSIFY_REF_CONTENT}"
assert_contains "loop termination: improvement threshold" "improvement" "${CLASSIFY_REF_CONTENT}"

# ---------------------------------------------------------------------------
# Scope restriction has infrastructure escalation carve-out
# ---------------------------------------------------------------------------
CONSTRAINT_2_BLOCK=$(sed -n '/### 2\. Scope Restriction/,/### 3\./p' "${SKILL_FILE}")
assert_contains "scope restriction: infra escalation carve-out" "Infrastructure escalation" "${CONSTRAINT_2_BLOCK}"

# ---------------------------------------------------------------------------
# Decision record contains spec-required safety fields (now in reference file)
# ---------------------------------------------------------------------------
assert_contains "decision record: evidence age field" "Evidence Age" "${CLASSIFY_REF_CONTENT}"
assert_contains "decision record: state fingerprint field" "State Fingerprint" "${CLASSIFY_REF_CONTENT}"
assert_contains "decision record: explanation field" "Explanation" "${CLASSIFY_REF_CONTENT}"
assert_contains "decision record: veto signals field" "VETO" "${CLASSIFY_REF_CONTENT}"

# ---------------------------------------------------------------------------
# Step 7 synthesis preserves investigation path material
# ---------------------------------------------------------------------------
STEP7_BLOCK=$(sed -n '/### Step 7: Context Discipline/,/### Step 8/p' "${SKILL_FILE}")
assert_contains "step 7: preserves ruled-out hypotheses" "ruled-out" "${STEP7_BLOCK}"
assert_contains "step 7: preserves hypothesis revisions" "hypothesis revision" "${STEP7_BLOCK}"

# ---------------------------------------------------------------------------
# Evidence persistence is operationalized in EXECUTE and VALIDATE
# ---------------------------------------------------------------------------
EXECUTE_BLOCK=$(sed -n '/## EXECUTE/,/## VALIDATE/p' "${SKILL_FILE}")
assert_contains "EXECUTE: write pre.json step" "pre.json" "${EXECUTE_BLOCK}"

VALIDATE_BLOCK=$(sed -n '/## VALIDATE/,/## Evidence Bundle/p' "${SKILL_FILE}")
assert_contains "VALIDATE: write validate.json step" "validate.json" "${VALIDATE_BLOCK}"

# ---------------------------------------------------------------------------
# SLO burn rate context signal in MITIGATE
# ---------------------------------------------------------------------------
assert_contains "SKILL.md mentions SLO burn rate in MITIGATE" "SLO burn rate alert" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# Disambiguation probe behavioral contracts (now in reference file)
# ---------------------------------------------------------------------------
assert_contains "SKILL.md has SHORTLIST artifact" "SHORTLIST:" "${CLASSIFY_REF_CONTENT}"
assert_contains "SKILL.md has classification_fingerprint" "classification_fingerprint" "${CLASSIFY_REF_CONTENT}"
assert_contains "SKILL.md has disambiguation_round" "disambiguation_round" "${CLASSIFY_REF_CONTENT}"
assert_contains "SKILL.md has pre_probe fingerprint" "pre_probe" "${CLASSIFY_REF_CONTENT}"
assert_contains "SKILL.md has MITIGATE Step 2b (inventory)" "Step 2b: Establish Inventory" "${SKILL_CONTENT}"
assert_contains "SKILL.md has Targeted Disambiguation Probes" "Targeted Disambiguation Probes" "${SKILL_CONTENT}"
assert_not_contains "SKILL.md has no duplicate Step 2b in INVESTIGATE" "### Step 2b: Targeted" "${SKILL_CONTENT}"
assert_contains "SKILL.md has scope exception for dependency probes" "declared/known dependencies" "${SKILL_CONTENT}"
assert_contains "SKILL.md has one probe round limit" "one probe round" "${CLASSIFY_REF_CONTENT}"

# ---------------------------------------------------------------------------
# Step 4b: Source Analysis — reference file
# ---------------------------------------------------------------------------
ref_file="${PROJECT_ROOT}/skills/incident-analysis/references/source-analysis.md"
assert_file_exists "source-analysis.md reference file" "${ref_file}"

ref_content="$(cat "${ref_file}")"
assert_contains "reference has GitHub API" "GitHub" "${ref_content}"
assert_contains "reference has regression heuristic" "regression" "${ref_content}"
assert_contains "reference has fail-open" "GitHub API unavailable" "${ref_content}"
assert_contains "reference has deployed_ref" "deployed_ref" "${ref_content}"
assert_contains "reference has resolved_commit_sha" "resolved_commit_sha" "${ref_content}"
assert_not_contains "reference does not use deployed_sha" "deployed_sha" "${ref_content}"
assert_contains "reference has structured source_files" "status: analyzed" "${ref_content}"
assert_contains "reference has workload identity" "workload identity" "${ref_content}"

# ---------------------------------------------------------------------------
# Step 4b: Source Analysis — SKILL.md placement
# ---------------------------------------------------------------------------
assert_contains "SKILL.md has Step 4b" "### Step 4b" "${SKILL_CONTENT}"
assert_contains "SKILL.md references source-analysis.md" "references/source-analysis.md" "${SKILL_CONTENT}"
assert_not_contains "SKILL.md has no separate SOURCE_ANALYSIS stage" "## SOURCE_ANALYSIS" "${SKILL_CONTENT}"

# Step 4b must appear before Step 5 (ordering check)
step4b_line="$(grep -n '### Step 4b' "${SKILL_FILE}" | head -1 | cut -d: -f1)"
step5_line="$(grep -n '### Step 5: Formulate Root Cause' "${SKILL_FILE}" | head -1 | cut -d: -f1)"

assert_not_empty "SKILL.md has Step 4b line number" "${step4b_line}"
assert_not_empty "SKILL.md has Step 5 line number" "${step5_line}"

if [ -n "${step4b_line}" ] && [ -n "${step5_line}" ] && [ "${step4b_line}" -lt "${step5_line}" ]; then
    _record_pass "Step 4b appears before Step 5"
else
    _record_fail "Step 4b appears before Step 5" "Step 4b line=${step4b_line:-missing}, Step 5 line=${step5_line:-missing}"
fi

# --- Observability preflight wiring ---
test_incident_analysis_references_preflight() {
    echo "-- test: incident-analysis references obs-preflight --"
    local skill="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md"
    local content
    content="$(cat "${skill}")"
    assert_contains "incident-analysis references obs-preflight" "obs-preflight.sh" "${content}"
}
test_incident_analysis_references_preflight

test_alert_hygiene_references_preflight() {
    echo "-- test: alert-hygiene references obs-preflight --"
    local skill="${PROJECT_ROOT}/skills/alert-hygiene/SKILL.md"
    local content
    content="$(cat "${skill}")"
    assert_contains "alert-hygiene references obs-preflight" "obs-preflight.sh" "${content}"
}
test_alert_hygiene_references_preflight

test_investigate_references_preflight() {
    echo "-- test: investigate references obs-preflight --"
    local cmd="${PROJECT_ROOT}/commands/investigate.md"
    local content
    content="$(cat "${cmd}")"
    assert_contains "investigate references obs-preflight" "obs-preflight.sh" "${content}"
}
test_investigate_references_preflight

# ---------------------------------------------------------------------------
# Caller-layer investigation rules (shared-dependency incidents)
# ---------------------------------------------------------------------------
echo "-- test: caller investigation rules --"

# Step 3: inline summary still references mandatory escalation and the reference file
STEP3_BLOCK=$(sed -n '/### Step 3: Single-Service Deep Dive/,/### Step 4/p' "${SKILL_FILE}")
assert_contains "step 3: escalation is mandatory" "mandatory" "${STEP3_BLOCK}"
assert_contains "step 3: references caller-investigation.md" "caller-investigation.md" "${STEP3_BLOCK}"

# Full procedure is now in the reference file
CALLER_REF="${PROJECT_ROOT}/skills/incident-analysis/references/caller-investigation.md"
CALLER_REF_CONTENT="$(cat "${CALLER_REF}")"
assert_contains "caller ref: identify dominant callers" "Identify dominant callers" "${CALLER_REF_CONTENT}"
assert_contains "caller ref: check dominant caller ERROR logs" "Check each dominant caller" "${CALLER_REF_CONTENT}"
assert_contains "caller ref: compare to different day baseline" "different day" "${CALLER_REF_CONTENT}"
assert_contains "caller ref: deployment history scoped to dominant callers" "deployment history" "${CALLER_REF_CONTENT}"
assert_contains "caller ref: amplification loop inside caller check" "amplification" "${CALLER_REF_CONTENT}"

# Step 5: chronic-vs-acute requires caller evidence for traffic hypotheses
STEP5_BLOCK=$(sed -n '/### Step 5: Formulate Root Cause/,/### Step 6/p' "${SKILL_FILE}")
assert_contains "step 5: caller retry loop candidate" "caller entering a failure/retry loop" "${STEP5_BLOCK}"
assert_contains "step 5: traffic baseline from different day" "different day at the same time" "${STEP5_BLOCK}"

# Step 8: completeness gate has caller-health question and updated rule
GATE_BLOCK=$(sed -n '/### Step 8: Investigation Completeness Gate/,/### Step 9/p' "${SKILL_FILE}")
assert_contains "gate: caller question exists" "dominant callers" "${GATE_BLOCK}"
assert_contains "gate: rule covers Q9" "4-9" "${GATE_BLOCK}"

# ---------------------------------------------------------------------------
# Reference file extractions exist
# ---------------------------------------------------------------------------
assert_file_exists "references/classify-scoring.md exists" \
    "${PROJECT_ROOT}/skills/incident-analysis/references/classify-scoring.md"
assert_file_exists "references/postmortem-template.md exists" \
    "${PROJECT_ROOT}/skills/incident-analysis/references/postmortem-template.md"
assert_file_exists "references/query-patterns.md exists" \
    "${PROJECT_ROOT}/skills/incident-analysis/references/query-patterns.md"
assert_file_exists "references/caller-investigation.md exists" \
    "${PROJECT_ROOT}/skills/incident-analysis/references/caller-investigation.md"

# ---------------------------------------------------------------------------
# Quick reference table and "When NOT to Use"
# ---------------------------------------------------------------------------
assert_contains "SKILL.md: has quick reference table" "Quick Reference" "${SKILL_CONTENT}"
assert_contains "SKILL.md: has when not to use" "When NOT to use" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# Frontmatter starts with "Use when"
# ---------------------------------------------------------------------------
desc_line="$(sed -n '3p' "${SKILL_FILE}")"
case "${desc_line}" in
    *"Use when"*)
        _record_pass "SKILL.md: description starts with 'Use when'"
        ;;
    *)
        _record_fail "SKILL.md: description starts with 'Use when'" "got: ${desc_line}"
        ;;
esac

print_summary
