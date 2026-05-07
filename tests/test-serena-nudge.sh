#!/usr/bin/env bash
# test-serena-nudge.sh — Verify hooks/serena-nudge.sh fires on the right
# Grep patterns and stays silent on the wrong ones, plus telemetry write.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/serena-nudge.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

# Build a fake registry cache marking serena=true.
mkdir -p "${HOME}/.claude"
cat >"${HOME}/.claude/.skill-registry-cache.json" <<JSON
{"context_capabilities":{"serena":true,"lsp":false,"openspec":false,"context7":false,"context_hub_cli":false,"context_hub_available":false,"forgetful_memory":false,"posthog":false}}
JSON

# Helper — invoke hook with a Grep tool call carrying the given pattern.
_invoke_hook() {
    local pattern="$1"
    local input
    input="$(jq -n --arg p "${pattern}" '{tool_name:"Grep", tool_input:{pattern:$p}}')"
    printf '%s' "${input}" | bash "${HOOK}" 2>/dev/null
}

# --- Patterns that SHOULD fire the nudge ---

assert_contains "fires on plain CamelCase" "find_symbol" "$(_invoke_hook 'UserService')"
assert_contains "fires on plain snake_case" "find_symbol" "$(_invoke_hook 'load_user_profile')"
assert_contains "fires on word-boundary CamelCase" "find_symbol" "$(_invoke_hook '\bUserService\b')"
assert_contains "fires on anchored CamelCase" "find_symbol" "$(_invoke_hook '^UserService$')"
assert_contains "fires on dotted member access" "find_symbol" "$(_invoke_hook 'User\.profile')"
assert_contains "fires on Rust/C++ member access" "find_symbol" "$(_invoke_hook 'User::profile')"
assert_contains "fires on definition prefix in richer regex" "find_symbol" "$(_invoke_hook '^class +Foo\b')"
assert_contains "fires on def-prefix in regex" "find_symbol" "$(_invoke_hook 'def +process_\w+')"

# --- Patterns that should NOT fire ---

# Heavy alternation — likely a free-text or multi-error grep.
assert_not_contains "stays silent on heavy alternation" "find_symbol" "$(_invoke_hook 'foo|bar|baz|qux|quux')"
# Lookaround — clearly not a symbol search.
assert_not_contains "stays silent on lookahead" "find_symbol" "$(_invoke_hook '(?=Foo)bar')"
# Broad character class — not a symbol shape.
assert_not_contains "stays silent on broad char class" "find_symbol" "$(_invoke_hook '[A-Za-z 0-9_-]+ failed')"
# Free-text quoted phrase.
assert_not_contains "stays silent on free text" "find_symbol" "$(_invoke_hook 'Connection refused')"
# Suppressors are authoritative — definition-prefix combined with heavy alternation
# is a free-text-style grep, not a symbol lookup. The spec MUST NOT applies.
assert_not_contains "stays silent on definition-prefix + heavy alternation" "find_symbol" "$(_invoke_hook 'class |def |function |interface |struct ')"
assert_not_contains "stays silent on definition-prefix + lookaround" "find_symbol" "$(_invoke_hook '(?<=^)class +Foo')"

# --- Telemetry — fires append a TSV line ---

TELEMETRY="${HOME}/.claude/.serena-nudge-telemetry"
rm -f "${TELEMETRY}"
_invoke_hook '\bUserService\b' >/dev/null
assert_file_exists "telemetry file is created on nudge fire" "${TELEMETRY}"
TELEM_LINE="$(tail -1 "${TELEMETRY}" 2>/dev/null || true)"
assert_contains "telemetry line contains nudge keyword" "nudge" "${TELEM_LINE}"
assert_contains "telemetry line records word_boundary class" "word_boundary" "${TELEM_LINE}"
assert_contains "telemetry line records grep_extension as matcher source" "grep_extension" "${TELEM_LINE}"
# Class must be in field 5 (after ts, token, turn, kind), so the followthrough
# correlator's $5-keying produces per-class follow-through buckets.
TELEM_FIELD5="$(printf '%s' "${TELEM_LINE}" | awk -F'\t' '{print $5}')"
assert_equals "telemetry field 5 is the class (not the matcher source)" "word_boundary" "${TELEM_FIELD5}"

# --- Telemetry — no log when nudge does not fire ---

rm -f "${TELEMETRY}"
_invoke_hook 'Connection refused' >/dev/null
if [ ! -f "${TELEMETRY}" ]; then
    _record_pass "no telemetry on non-fire"
else
    _record_fail "no telemetry on non-fire" "telemetry file exists despite no nudge"
fi

teardown_test_env

# Final exit status
if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
