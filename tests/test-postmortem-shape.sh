#!/usr/bin/env bash
# test-postmortem-shape.sh — Regression test for incident-trend-analyzer compatibility.
# Validates that SKILL.md contains all 7 postmortem section headers.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-postmortem-shape.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# ---------------------------------------------------------------------------
# All 7 postmortem section headers must be present
# ---------------------------------------------------------------------------

# 1. Summary
assert_contains "postmortem header: Summary" "Summary" "${SKILL_CONTENT}"

# 2. Impact
assert_contains "postmortem header: Impact" "Impact" "${SKILL_CONTENT}"

# 3. Timeline
assert_contains "postmortem header: Timeline" "Timeline" "${SKILL_CONTENT}"

# 4. Root Cause (accept "Root Cause & Trigger" or "Root Cause")
if printf '%s' "${SKILL_CONTENT}" | grep -q "Root Cause"; then
    _record_pass "postmortem header: Root Cause"
else
    _record_fail "postmortem header: Root Cause" "neither 'Root Cause & Trigger' nor 'Root Cause' found"
fi

# 5. Resolution (accept "Resolution and Recovery" or "Resolution")
if printf '%s' "${SKILL_CONTENT}" | grep -q "Resolution"; then
    _record_pass "postmortem header: Resolution"
else
    _record_fail "postmortem header: Resolution" "neither 'Resolution and Recovery' nor 'Resolution' found"
fi

# 6. Lessons Learned
assert_contains "postmortem header: Lessons Learned" "Lessons Learned" "${SKILL_CONTENT}"

# 7. Action Items
assert_contains "postmortem header: Action Items" "Action Items" "${SKILL_CONTENT}"

print_summary
