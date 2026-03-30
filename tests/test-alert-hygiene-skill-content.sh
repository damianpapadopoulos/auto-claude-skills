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

# --- Action-class grouped output (v3) ---
assert_contains "do now section" "Actionable Findings: Do Now" "${SKILL_CONTENT}"
assert_contains "investigate section" "Actionable Findings: Investigate" "${SKILL_CONTENT}"
assert_contains "needs decision section" "Needs Decision" "${SKILL_CONTENT}"
assert_contains "decision summary section" "Decision Summary" "${SKILL_CONTENT}"
assert_contains "systemic issues section" "Systemic Issues" "${SKILL_CONTENT}"

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

# --- Do Now per-item template fields (v3) ---
assert_contains "policy ID field" "Policy ID:" "${SKILL_CONTENT}"
assert_contains "target owner field" "Target Owner:" "${SKILL_CONTENT}"
assert_contains "scope field" "Scope:" "${SKILL_CONTENT}"
assert_contains "notification reach field" "Notification Reach:" "${SKILL_CONTENT}"
assert_contains "current policy snapshot" "Current Policy Snapshot" "${SKILL_CONTENT}"
assert_contains "iac location field" "IaC Location:" "${SKILL_CONTENT}"
assert_contains "config diff table" "Configuration Diff" "${SKILL_CONTENT}"
assert_contains "derivation column" "Derivation" "${SKILL_CONTENT}"
assert_contains "pre-change evidence field" "Pre-change Evidence:" "${SKILL_CONTENT}"
assert_contains "evidence basis field" "Evidence Basis:" "${SKILL_CONTENT}"
assert_contains "outcome dod field" "Outcome DoD:" "${SKILL_CONTENT}"
assert_contains "primary metric" "Primary:" "${SKILL_CONTENT}"
assert_contains "guardrail metric" "Guardrail:" "${SKILL_CONTENT}"
assert_contains "rollback signal field" "Rollback Signal:" "${SKILL_CONTENT}"

# --- Investigate per-item template fields (v3) ---
assert_contains "hypothesis field" "Hypothesis:" "${SKILL_CONTENT}"
assert_contains "stage 1 dod" "Stage 1 DoD" "${SKILL_CONTENT}"
assert_contains "stage 2 follow-up" "Stage 2" "${SKILL_CONTENT}"
assert_contains "to upgrade field" "To Upgrade:" "${SKILL_CONTENT}"

# --- Needs Decision per-item template fields (v3) ---
assert_contains "decision required field" "Decision Required:" "${SKILL_CONTENT}"
assert_contains "named decision owner" "Named Decision Owner:" "${SKILL_CONTENT}"
assert_contains "deadline field" "Deadline:" "${SKILL_CONTENT}"
assert_contains "default recommendation" "Default Recommendation:" "${SKILL_CONTENT}"

# --- Do Now gate behavioral contract ---
assert_contains "do now gate" "Do Now Gate" "${SKILL_CONTENT}"
assert_contains "heuristic exclusion" "heuristic alone never qualifies for Do Now" "${SKILL_CONTENT}"
assert_contains "iac confirmed status" "Confirmed" "${SKILL_CONTENT}"
assert_contains "iac likely status" "Likely" "${SKILL_CONTENT}"
assert_contains "iac search required status" "Search Required" "${SKILL_CONTENT}"
assert_contains "iac unknown drops" "Unknown" "${SKILL_CONTENT}"
assert_contains "search req repo hint" "repo" "${SKILL_CONTENT}"
assert_contains "search req policy id" "policy ID" "${SKILL_CONTENT}"
assert_contains "search req identifying fragment" "identifying fragment" "${SKILL_CONTENT}"
assert_contains "search req replacement guidance" "replacement guidance" "${SKILL_CONTENT}"

# --- Investigate behavioral contract ---
assert_contains "investigate structural evidence" "measured|structural|heuristic" "${SKILL_CONTENT}"
assert_contains "two-stage dod rule" "Two-Stage DoD" "${SKILL_CONTENT}"
assert_contains "structurally proven gate-blocked" "Structurally Proven" "${SKILL_CONTENT}"

# --- Confidence/Readiness vocabulary ---
assert_contains "pr-ready readiness" "PR-Ready" "${SKILL_CONTENT}"
assert_contains "high stage 1 readiness" "High / Stage 1" "${SKILL_CONTENT}"
assert_contains "medium stage 1 readiness" "Medium / Stage 1" "${SKILL_CONTENT}"
assert_contains "decision pending readiness" "Decision Pending" "${SKILL_CONTENT}"

# --- Systemic Issues subsections ---
assert_contains "ownership routing debt" "Ownership/Routing Debt" "${SKILL_CONTENT}"
assert_contains "dead orphaned config" "Dead/Orphaned Config" "${SKILL_CONTENT}"
assert_contains "missing coverage" "Missing Coverage" "${SKILL_CONTENT}"
assert_contains "inventory health" "Inventory Health" "${SKILL_CONTENT}"

# --- Verification metric families ---
assert_contains "metric family noise" "Noise tuning" "${SKILL_CONTENT}"
assert_contains "metric family auto_close" "auto_close fixes" "${SKILL_CONTENT}"
assert_contains "metric family routing" "Routing/ownership" "${SKILL_CONTENT}"
assert_contains "finding-type-aligned outcome" "aligned to finding type" "${SKILL_CONTENT}"

# --- Definitions additions ---
assert_contains "open-incident hours defined" "open-incident hours" "${SKILL_CONTENT}"

# --- Skill intro describes v3 action-class model ---
assert_contains "intro do now" "Do Now" "${SKILL_CONTENT}"
assert_contains "intro investigate" "Investigate" "${SKILL_CONTENT}"
assert_contains "intro needs decision" "Needs Decision" "${SKILL_CONTENT}"

# --- Report sections ---
assert_contains "definitions section" "Definitions" "${SKILL_CONTENT}"
assert_contains "action type legend" "Action Type Legend" "${SKILL_CONTENT}"
# --- Decision Summary table columns ---
assert_contains "summary category column" "Category" "${SKILL_CONTENT}"
assert_contains "summary target owner column" "Target Owner" "${SKILL_CONTENT}"
assert_contains "summary readiness column" "Confidence / Readiness" "${SKILL_CONTENT}"
assert_contains "summary expected outcome column" "Primary Expected Outcome" "${SKILL_CONTENT}"
assert_contains "summary next action column" "Next Action" "${SKILL_CONTENT}"
assert_contains "summary cap rule" "8-12" "${SKILL_CONTENT}"
assert_contains "summary selection rule" "non-empty category" "${SKILL_CONTENT}"
assert_contains "summary anchor links" "linked to detailed section" "${SKILL_CONTENT}"
assert_contains "keep section" "No Action Required" "${SKILL_CONTENT}"
assert_contains "verification scorecard" "Verification Scorecard" "${SKILL_CONTENT}"
assert_contains "global implementation standard" "Global Implementation Standard" "${SKILL_CONTENT}"
assert_contains "every mutated field" "every mutated field" "${SKILL_CONTENT}"
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

# --- New sections from terraform/routing/SLO refinements ---

# SLO enrichment in Stage 1
assert_contains "SKILL.md has SLO enrichment section" \
    "SLO Config Enrichment" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions slo-services.json artifact" \
    "slo-services.json" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions slo-source-status.json artifact" \
    "slo-source-status.json" "${SKILL_CONTENT}"
assert_contains "SKILL.md SLO uses Ruby not PyYAML" \
    "ruby -ryaml -rjson" "${SKILL_CONTENT}"

# Routing validation in Stage 4
assert_contains "SKILL.md has routing validation section" \
    "Routing Validation" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions zero-channel policies" \
    "Zero-channel policies" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions unlabeled high-noise" \
    "ownership is implicit and unauditable" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions label inconsistency promotion" \
    "Label inconsistency promotion" "${SKILL_CONTENT}"

# SLO cross-reference in Stage 4
assert_contains "SKILL.md has SLO cross-reference section" \
    "SLO Coverage Cross-Reference" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions SLO migration candidates" \
    "SLO migration candidate" "${SKILL_CONTENT}"
assert_contains "SKILL.md gates SLO xref on signal_family" \
    "signal_family" "${SKILL_CONTENT}"
assert_contains "SKILL.md excludes other from SLO xref" \
    "exclude" "${SKILL_CONTENT}"

# IaC location resolution in Stage 5
assert_contains "SKILL.md has IaC search section" \
    "IaC Location Resolution" "${SKILL_CONTENT}"
assert_contains "SKILL.md preserves original tier on no results" \
    "Preserve original tier" "${SKILL_CONTENT}"
assert_contains "SKILL.md says Confirmed not achievable from search" \
    "Confirmed is not achievable from search alone" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions gh auth status precondition" \
    "gh auth status" "${SKILL_CONTENT}"

print_summary
