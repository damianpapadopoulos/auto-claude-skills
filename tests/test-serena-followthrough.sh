#!/usr/bin/env bash
# test-serena-followthrough.sh — Verify hooks/serena-followthrough.sh appends a
# `followup` line when a Serena MCP tool runs within 3 turns of an unmarked nudge
# or observation in the same session.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/serena-followthrough.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env
TELEM="${HOME}/.claude/.serena-nudge-telemetry"
mkdir -p "${HOME}/.claude"

_invoke_followthrough() {
    local tool="$1" turn="$2" token="${3:-tok-A}"
    local input
    input="$(jq -n --arg t "${tool}" '{tool_name:$t, tool_input:{}, tool_response:{ok:true}}')"
    printf '%s' "${input}" | env CLAUDE_SESSION_TOKEN="${token}" CLAUDE_TURN_ID="${turn}" bash "${HOOK}" 2>/dev/null
}

# Seed: a nudge at turn 5 in session tok-A.
printf '1700000000\ttok-A\t5\tnudge\tword_boundary\tgrep_extension\n' >>"${TELEM}"

# Serena call at turn 6 — within 3 turns → should produce a followup line.
_invoke_followthrough mcp__serena__find_symbol 6 tok-A >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_contains "Serena call within 3 turns appends followup" "followup" "${LAST}"
assert_contains "followup carries original class word_boundary" "word_boundary" "${LAST}"
assert_contains "followup names the serena tool find_symbol" "find_symbol" "${LAST}"

# Already-correlated nudge → no double-followup on second Serena call.
_LINES_BEFORE="$(wc -l <"${TELEM}" | tr -d ' ')"
_invoke_followthrough mcp__serena__get_symbols_overview 6 tok-A >/dev/null
_LINES_AFTER="$(wc -l <"${TELEM}" | tr -d ' ')"
assert_equals "no double-followup once nudge correlated" "${_LINES_BEFORE}" "${_LINES_AFTER}"

# Far-apart Serena call (turn 5 nudge + turn 12 Serena call) → no followup.
rm -f "${TELEM}"
printf '1700000000\ttok-B\t5\tnudge\tword_boundary\tgrep_extension\n' >>"${TELEM}"
_invoke_followthrough mcp__serena__find_symbol 12 tok-B >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_not_contains "no followup beyond 3 turns" "followup" "${LAST}"

# Different session token → no followup.
rm -f "${TELEM}"
printf '1700000000\ttok-C\t5\tnudge\tword_boundary\tgrep_extension\n' >>"${TELEM}"
_invoke_followthrough mcp__serena__find_symbol 6 tok-D >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_not_contains "no followup across sessions" "followup" "${LAST}"

# Observation — also correlates to followup.
rm -f "${TELEM}"
printf '1700000000\ttok-E\t10\tobserve\tread_large_source\tsrc/big.ts\n' >>"${TELEM}"
_invoke_followthrough mcp__serena__get_symbols_overview 11 tok-E >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_contains "observation correlates to followup" "followup" "${LAST}"
assert_contains "observation followup carries read_large_source" "read_large_source" "${LAST}"

# Multi-session safety: a busy concurrent session writing 250 lines must not
# evict our own session's nudge out of the lookup window.
rm -f "${TELEM}"
printf '1700000000\ttok-OUR\t5\tnudge\tword_boundary\tgrep_extension\n' >>"${TELEM}"
i=1
while [ "${i}" -le 250 ]; do
    printf '1700000001\ttok-NOISY\t%d\tobserve\tread_large_source\tsrc/x.ts\n' "${i}" >>"${TELEM}"
    i=$((i+1))
done
_invoke_followthrough mcp__serena__find_symbol 6 tok-OUR >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_contains "concurrent session noise does not evict our nudge from the window" "followup" "${LAST}"
assert_contains "followup carries our session token" "tok-OUR" "${LAST}"

# Errored Serena tool result → no followup.
rm -f "${TELEM}"
printf '1700000000\ttok-F\t5\tnudge\tword_boundary\tgrep_extension\n' >>"${TELEM}"
err_input="$(jq -n '{tool_name:"mcp__serena__find_symbol", tool_input:{}, tool_response:{is_error:true}}')"
printf '%s' "${err_input}" | env CLAUDE_SESSION_TOKEN=tok-F CLAUDE_TURN_ID=6 bash "${HOOK}" 2>/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_not_contains "no followup on errored tool result" "followup" "${LAST}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
