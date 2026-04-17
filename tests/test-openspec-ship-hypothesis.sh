#!/usr/bin/env bash
# test-openspec-ship-hypothesis.sh — hypothesis extraction content assertions
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-openspec-ship-hypothesis.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/openspec-ship/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# Step 7a-bis exists
assert_contains "Step 7a-bis header" "Step 7a-bis" "${SKILL_CONTENT}"
assert_contains "hypothesis extraction documented" "discovery_path" "${SKILL_CONTENT}"
assert_contains "hypotheses written to session state" "hypotheses" "${SKILL_CONTENT}"

# Step 7b includes discovery_path in archival
STEP_7B_BLOCK=$(sed -n '/### Step 7b/,/### Step 7c/p' "${SKILL_FILE}")
assert_contains "discovery_path in 7b condition" "discovery_path" "${STEP_7B_BLOCK}"
assert_contains "discovery_path in 7b for loop" "discovery_path" "${STEP_7B_BLOCK}"

# Graceful skip when no discovery
assert_contains "skip when discovery absent" "Skip silently" "${SKILL_CONTENT}"

# Summary
echo ""
echo "=============================="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "=============================="
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '%s' "${FAIL_MESSAGES}"
    exit 1
else
    echo "All tests passed."
fi
