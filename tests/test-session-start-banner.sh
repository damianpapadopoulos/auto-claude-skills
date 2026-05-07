#!/usr/bin/env bash
# test-session-start-banner.sh — Verify the SessionStart banner contains the
# subagent-propagation line when serena=true and does NOT mention the third-pole
# diagnostics tool get_diagnostics_for_file.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK_FILE="${REPO_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

# This is a content-level test: we grep the source for the specific banner copy
# rather than execute the full hook, because session-start has heavy capability
# discovery and would require stubbing the entire MCP/registry pipeline.

assert_file_exists "session-start hook source exists" "${HOOK_FILE}"

# Read the source for inspection.
SRC="$(cat "${HOOK_FILE}")"

assert_contains "Serena banner mentions mcp__serena__ tools" "mcp__serena__" "${SRC}"
assert_contains "Serena banner mentions Task tool propagation" "Task tool" "${SRC}"
assert_contains "Serena banner names the propagated guidance string" "Serena available" "${SRC}"
assert_contains "LSP banner still names mcp__ide__getDiagnostics" "mcp__ide__getDiagnostics" "${SRC}"
assert_not_contains "banner does NOT mention get_diagnostics_for_file" "get_diagnostics_for_file" "${SRC}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
