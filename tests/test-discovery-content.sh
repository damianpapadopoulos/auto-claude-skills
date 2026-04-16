#!/usr/bin/env bash
# test-discovery-content.sh — product-discovery SKILL.md content assertions
# and DISCOVER/SHIP composition assertions for hypothesis-to-learning loop
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-discovery-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/product-discovery/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# Hypotheses section exists (bold label, consistent with other brief fields)
assert_contains "Hypotheses section header" "**Hypotheses:**" "${SKILL_CONTENT}"

# Structured fields documented
assert_contains "Metric field in hypothesis template" "**Metric:**" "${SKILL_CONTENT}"
assert_contains "Baseline field in hypothesis template" "**Baseline:**" "${SKILL_CONTENT}"
assert_contains "Target field in hypothesis template" "**Target:**" "${SKILL_CONTENT}"
assert_contains "Window field in hypothesis template" "**Window:**" "${SKILL_CONTENT}"

# Hypothesis ID pattern documented
assert_contains "Hypothesis H1 pattern" "### H1:" "${SKILL_CONTENT}"

# Brief still has original sections
assert_contains "Problem Statement section preserved" "**Problem Statement:**" "${SKILL_CONTENT}"
assert_contains "Acceptance Criteria section preserved" "**Acceptance Criteria:**" "${SKILL_CONTENT}"
assert_contains "Open Questions section preserved" "**Open Questions:**" "${SKILL_CONTENT}"

# --- Registry: DISCOVER persistence hint ---
REGISTRY="${PROJECT_ROOT}/config/default-triggers.json"
REGISTRY_CONTENT="$(cat "${REGISTRY}")"

assert_contains "DISCOVER persistence hint in registry" "PERSIST DISCOVERY" "${REGISTRY_CONTENT}"
assert_contains "discovery_path state write in hint" "openspec_state_set_discovery_path" "${REGISTRY_CONTENT}"

FALLBACK="${PROJECT_ROOT}/config/fallback-registry.json"
FALLBACK_CONTENT="$(cat "${FALLBACK}")"

assert_contains "DISCOVER persistence hint in fallback" "PERSIST DISCOVERY" "${FALLBACK_CONTENT}"

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
