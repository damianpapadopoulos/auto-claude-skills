#!/usr/bin/env bash
# test-alert-hygiene-skill-content.sh — SKILL.md behavioral contract assertions
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-alert-hygiene-skill-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/alert-hygiene/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# --- Frontmatter ---
assert_contains "has name frontmatter" "name: alert-hygiene" "${SKILL_CONTENT}"
assert_contains "has description frontmatter" "description: Use when" "${SKILL_CONTENT}"

# --- Tier detection documented (REST first, MCP second) ---
assert_contains "tier 1 REST documented" "Tier 1" "${SKILL_CONTENT}"
assert_contains "REST is default" "REST API" "${SKILL_CONTENT}"
assert_contains "tier 2 MCP documented" "Tier 2" "${SKILL_CONTENT}"
assert_contains "MCP enrichment only" "enrichment" "${SKILL_CONTENT}"
assert_contains "temp file pattern" "mktemp" "${SKILL_CONTENT}"

# --- Analysis stages ---
assert_contains "pull policies stage" "pull-policies" "${SKILL_CONTENT}"
assert_contains "pull incidents stage" "pull-incidents" "${SKILL_CONTENT}"
assert_contains "compute clusters stage" "compute-clusters" "${SKILL_CONTENT}"

# --- Prescriptive reasoning ---
assert_contains "threshold recommendation" "threshold" "${SKILL_CONTENT}"
assert_contains "duration recommendation" "duration" "${SKILL_CONTENT}"
assert_contains "auto_close recommendation" "auto_close" "${SKILL_CONTENT}"

# --- Confidence-grouped output ---
assert_contains "high confidence section" "High-Confidence Actions" "${SKILL_CONTENT}"
assert_contains "medium confidence section" "Medium-Confidence Actions" "${SKILL_CONTENT}"
assert_contains "analyst input section" "Needs Analyst Input" "${SKILL_CONTENT}"

# --- Action types ---
assert_contains "tune action" "Tune the alert" "${SKILL_CONTENT}"
assert_contains "fix action" "Fix the underlying issue" "${SKILL_CONTENT}"
assert_contains "SLO redesign action" "Redesign around SLO" "${SKILL_CONTENT}"
assert_contains "coverage action" "Add/extend coverage" "${SKILL_CONTENT}"
assert_contains "no action" "No action" "${SKILL_CONTENT}"

# --- Label inconsistency check ---
assert_contains "label inconsistency" "label_inconsistency" "${SKILL_CONTENT}"

# --- Noise scoring ---
assert_contains "noise scoring" "noise_score" "${SKILL_CONTENT}"
assert_contains "pattern classification" "flapping" "${SKILL_CONTENT}"
assert_contains "pattern classification" "chronic" "${SKILL_CONTENT}"
assert_contains "pattern classification" "recurring" "${SKILL_CONTENT}"

# --- Coverage gap analysis ---
assert_contains "SSL cert coverage" "SSL" "${SKILL_CONTENT}"
assert_contains "probe failure coverage" "probe" "${SKILL_CONTENT}"
assert_contains "node pressure coverage" "node" "${SKILL_CONTENT}"

# --- Confidence levels ---
assert_contains "high confidence" "High" "${SKILL_CONTENT}"
assert_contains "low confidence inline flag" "Low" "${SKILL_CONTENT}"

# --- Report structure ---
assert_contains "frequency table" "frequency table" "${SKILL_CONTENT}"
assert_contains "prescriptive" "prescriptive" "${SKILL_CONTENT}"

# --- Per-item template fields ---
assert_contains "observed/inferred split" "Observed:" "${SKILL_CONTENT}"
assert_contains "inferred field" "Inferred:" "${SKILL_CONTENT}"
assert_contains "evidence basis field" "Evidence basis:" "${SKILL_CONTENT}"
assert_contains "owner routing field" "Owner:" "${SKILL_CONTENT}"
assert_contains "policy ID field" "Policy ID:" "${SKILL_CONTENT}"
assert_contains "notification reach field" "Notification reach:" "${SKILL_CONTENT}"
assert_contains "risk of change field" "Risk of change:" "${SKILL_CONTENT}"
assert_contains "rollback signal field" "Rollback signal:" "${SKILL_CONTENT}"
assert_contains "impact derivation field" "Impact derivation:" "${SKILL_CONTENT}"
assert_contains "to upgrade field for medium" "To upgrade:" "${SKILL_CONTENT}"

# --- Report sections ---
assert_contains "definitions section" "Definitions" "${SKILL_CONTENT}"
assert_contains "action type legend" "Action Type Legend" "${SKILL_CONTENT}"
assert_contains "dual track A" "Track A" "${SKILL_CONTENT}"
assert_contains "dual track B" "Track B" "${SKILL_CONTENT}"
assert_contains "keep section" "No Action Required" "${SKILL_CONTENT}"
assert_contains "verification plan" "Verification Plan" "${SKILL_CONTENT}"
assert_contains "evidence coverage appendix" "Evidence Coverage" "${SKILL_CONTENT}"

# --- Evidence basis methodology ---
assert_contains "measured evidence type" "measured" "${SKILL_CONTENT}"
assert_contains "heuristic evidence type" "heuristic" "${SKILL_CONTENT}"
assert_contains "key terms section" "Key Terms" "${SKILL_CONTENT}"

# --- Behavioral constraints ---
assert_contains "no checkpoint gate" "straight through" "${SKILL_CONTENT}"
assert_contains "scope restriction" "monitoring project" "${SKILL_CONTENT}"

# --- Step 0 validation guard ---
assert_contains "step 0 validation" "Stage 0" "${SKILL_CONTENT}"
assert_contains "fail early" "Fail early" "${SKILL_CONTENT}"

print_summary
