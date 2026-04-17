#!/usr/bin/env bash
# test-design-debate-content.sh — Content-contract assertions for design-debate skill
# Verifies the dual-mode output template (spec-driven + solo) is documented.
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-design-debate-content.sh ==="

setup_test_env

DEBATE_SKILL="${PROJECT_ROOT}/skills/design-debate/SKILL.md"
DEBATE_CONTENT="$(cat "${DEBATE_SKILL}")"

# Dual-mode output template
assert_contains "design-debate: spec-driven mode output documented" "openspec/changes/" "$DEBATE_CONTENT"
assert_contains "design-debate: solo mode output documented" "docs/plans/" "$DEBATE_CONTENT"
assert_contains "design-debate: mode check instruction" "Check session preset" "$DEBATE_CONTENT"
assert_contains "design-debate: spec-driven section heading" "Spec-driven mode" "$DEBATE_CONTENT"
assert_contains "design-debate: solo section heading" "Solo mode" "$DEBATE_CONTENT"

# Spec-driven mode content
assert_contains "design-debate: creates proposal.md" "proposal.md" "$DEBATE_CONTENT"
assert_contains "design-debate: creates specs/<capability>/" "specs/<capability>/" "$DEBATE_CONTENT"
assert_contains "design-debate: new capability warning" "NEW CAPABILITY" "$DEBATE_CONTENT"

# Capability inference heuristic (taxonomy polish from PR-B)
assert_contains "design-debate: lists existing capabilities before create" "ls openspec/specs/" "$DEBATE_CONTENT"
assert_contains "design-debate: prefers extending existing capability" "prefer extending" "$DEBATE_CONTENT"
assert_contains "design-debate: ask when uncertain" "ask the user" "$DEBATE_CONTENT"

teardown_test_env

echo ""
echo "=== Design-Debate Content Results ==="
echo "  Total: ${TESTS_RUN}"
echo "  Passed: ${TESTS_PASSED}"
echo "  Failed: ${TESTS_FAILED}"
[ "${TESTS_FAILED}" -eq 0 ] || exit 1
