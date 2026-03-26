#!/usr/bin/env bash
# test-skill-content.sh — SKILL.md behavioral contract assertions
# Validates that required concepts, safety invariants, and decision structures
# are documented in the incident-analysis skill file.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-skill-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# ---------------------------------------------------------------------------
# Confidence bands
# ---------------------------------------------------------------------------
assert_contains "confidence band: 85 threshold" "85" "${SKILL_CONTENT}"
assert_contains "confidence band: 60 threshold" "60" "${SKILL_CONTENT}"
assert_contains "confidence band: < 60 path" "< 60" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# Signal scoring fields
# ---------------------------------------------------------------------------
assert_contains "contradiction scoring documented" "contradiction_score" "${SKILL_CONTENT}"
assert_contains "veto_signals documented" "veto_signals" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# Decision records contain signal evaluation sections (both tiers)
# ---------------------------------------------------------------------------
assert_contains "SIGNALS EVALUATED in high-confidence record" "CLASSIFY DECISION" "${SKILL_CONTENT}"
# Both decision record templates show signal states with contradiction weights
assert_contains "contradiction in signal evaluation" "contradiction" "${SKILL_CONTENT}"
# Both high and medium confidence decision records exist
assert_contains "high confidence decision record" "HIGH CONFIDENCE" "${SKILL_CONTENT}"
assert_contains "medium confidence decision record" "MEDIUM CONFIDENCE" "${SKILL_CONTENT}"
# SIGNALS EVALUATED header present in decision record templates
assert_contains "SIGNALS EVALUATED section in records" "SIGNALS EVALUATED" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# VALIDATE stage references stabilization_delay_seconds
# ---------------------------------------------------------------------------
assert_contains "VALIDATE references stabilization_delay_seconds" "stabilization_delay_seconds" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# Fingerprint recheck documented between approval and execution
# ---------------------------------------------------------------------------
# The EXECUTE stage has a "Fingerprint Recheck" step
assert_contains "fingerprint recheck documented" "Fingerprint Recheck" "${SKILL_CONTENT}"
# Drift detection is part of the recheck
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
# Loop termination — stall detection
# ---------------------------------------------------------------------------
assert_contains "loop termination: 3 iterations" "3 reclassification iterations" "${SKILL_CONTENT}"
assert_contains "loop termination: improvement threshold" "improvement" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# Scope restriction has infrastructure escalation carve-out
# ---------------------------------------------------------------------------
CONSTRAINT_2_BLOCK=$(sed -n '/### 2\. Scope Restriction/,/### 3\./p' "${SKILL_FILE}")
assert_contains "scope restriction: infra escalation carve-out" "Infrastructure escalation" "${CONSTRAINT_2_BLOCK}"

# ---------------------------------------------------------------------------
# Decision record contains spec-required safety fields
# ---------------------------------------------------------------------------
# Extract the high-confidence decision record template block
HC_RECORD=$(sed -n '/### Decision Record — High Confidence/,/### Decision Record — Medium Confidence/p' "${SKILL_FILE}")
assert_contains "decision record: evidence age field" "Evidence Age" "${HC_RECORD}"
assert_contains "decision record: state fingerprint field" "State Fingerprint" "${HC_RECORD}"
assert_contains "decision record: explanation field" "Explanation" "${HC_RECORD}"
assert_contains "decision record: veto signals field" "VETO" "${HC_RECORD}"

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
# Disambiguation probe behavioral contracts
# (SKILL_CONTENT is already defined at the top of this test file)
# ---------------------------------------------------------------------------
assert_contains "SKILL.md has SHORTLIST artifact" "SHORTLIST:" "${SKILL_CONTENT}"
assert_contains "SKILL.md has classification_fingerprint" "classification_fingerprint" "${SKILL_CONTENT}"
assert_contains "SKILL.md has disambiguation_round" "disambiguation_round" "${SKILL_CONTENT}"
assert_contains "SKILL.md has pre_probe fingerprint" "pre_probe" "${SKILL_CONTENT}"
assert_contains "SKILL.md has Step 2b" "Step 2b" "${SKILL_CONTENT}"
assert_contains "SKILL.md has Targeted Disambiguation Probes" "Targeted Disambiguation Probes" "${SKILL_CONTENT}"
assert_contains "SKILL.md has scope exception for dependency probes" "declared/known dependencies" "${SKILL_CONTENT}"
assert_contains "SKILL.md has one probe round limit" "one probe round" "${SKILL_CONTENT}"

# ---------------------------------------------------------------------------
# SOURCE_ANALYSIS reference file
# ---------------------------------------------------------------------------
ref_file="${PROJECT_ROOT}/skills/incident-analysis/references/source-analysis.md"
assert_file_exists "source-analysis.md reference file" "${ref_file}"

ref_content="$(cat "${ref_file}")"
assert_contains "reference has GitHub API" "GitHub" "${ref_content}"
assert_contains "reference has regression heuristic" "regression" "${ref_content}"
assert_contains "reference has fail-open" "GitHub API unavailable" "${ref_content}"
assert_contains "reference has deployed SHA" "deployed_sha" "${ref_content}"

# ---------------------------------------------------------------------------
# SOURCE_ANALYSIS stage in SKILL.md
# ---------------------------------------------------------------------------
assert_contains "SKILL.md has SOURCE_ANALYSIS stage" "SOURCE_ANALYSIS" "${SKILL_CONTENT}"
assert_contains "SKILL.md references source-analysis.md" "references/source-analysis.md" "${SKILL_CONTENT}"

print_summary
