#!/usr/bin/env bash
# test-serena-observer.sh — Verify hooks/serena-observer.sh logs missed-opportunity
# observations for Read/Glob/Edit but never emits user-visible additionalContext.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/serena-observer.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

mkdir -p "${HOME}/.claude"
cat >"${HOME}/.claude/.skill-registry-cache.json" <<JSON
{"context_capabilities":{"serena":true,"lsp":false}}
JSON

TELEM="${HOME}/.claude/.serena-nudge-telemetry"

_make_large_source() {
    local path="${TEST_TMPDIR}/big.ts"
    local i=1
    : >"${path}"
    while [ "${i}" -le 600 ]; do
        printf 'const x_%d = %d;\n' "${i}" "${i}" >>"${path}"
        i=$((i + 1))
    done
    printf '%s' "${path}"
}

_make_small_source() {
    local path="${TEST_TMPDIR}/small.ts"
    : >"${path}"
    printf 'const x = 1;\n' >"${path}"
    printf '%s' "${path}"
}

_make_md_file() {
    local path="${TEST_TMPDIR}/notes.md"
    local i=1; : >"${path}"
    while [ "${i}" -le 800 ]; do
        printf 'line %d\n' "${i}" >>"${path}"
        i=$((i + 1))
    done
    printf '%s' "${path}"
}

_invoke_observer() {
    local tool="$1" json="$2"
    local input
    input="$(jq -n --arg t "${tool}" --argjson ti "${json}" '{tool_name:$t, tool_input:$ti}')"
    printf '%s' "${input}" | bash "${HOOK}" 2>/dev/null
}

# --- Read on large source file → logs read_large_source observation ---

big="$(_make_large_source)"
rm -f "${TELEM}"
out="$(_invoke_observer Read "$(jq -n --arg p "${big}" '{file_path:$p}')")"
assert_equals "observer never emits additionalContext on Read" "" "${out}"
assert_file_exists "observer logs read_large_source on >500-line .ts" "${TELEM}"
assert_contains "telemetry contains observe keyword" "observe" "$(tail -1 "${TELEM}")"
assert_contains "telemetry classifies read_large_source" "read_large_source" "$(tail -1 "${TELEM}")"

# --- Read on small source file → no log ---

small="$(_make_small_source)"
rm -f "${TELEM}"
_invoke_observer Read "$(jq -n --arg p "${small}" '{file_path:$p}')" >/dev/null
if [ ! -f "${TELEM}" ]; then
    _record_pass "no log on small source Read"
else
    _record_fail "no log on small source Read" "telemetry exists despite small file"
fi

# --- Read on markdown (non-source) → no log ---

md="$(_make_md_file)"
rm -f "${TELEM}"
_invoke_observer Read "$(jq -n --arg p "${md}" '{file_path:$p}')" >/dev/null
if [ ! -f "${TELEM}" ]; then
    _record_pass "no log on markdown Read regardless of size"
else
    _record_fail "no log on markdown Read" "telemetry exists for markdown"
fi

# --- Read with offset/limit → no log (intentional partial read) ---

rm -f "${TELEM}"
_invoke_observer Read "$(jq -n --arg p "${big}" '{file_path:$p, offset:100, limit:50}')" >/dev/null
if [ ! -f "${TELEM}" ]; then
    _record_pass "no log on Read with offset/limit"
else
    _record_fail "no log on Read with offset/limit" "telemetry exists despite partial read"
fi

# --- Glob on definition-hunt pattern → log ---

rm -f "${TELEM}"
_invoke_observer Glob "$(jq -n '{pattern:"**/*UserService*"}')" >/dev/null
assert_file_exists "Glob definition-hunt logs observation" "${TELEM}"
assert_contains "Glob log carries glob_definition_hunt class" "glob_definition_hunt" "$(tail -1 "${TELEM}")"

# --- Glob on broad inventory → no log ---

rm -f "${TELEM}"
_invoke_observer Glob "$(jq -n '{pattern:"**/*.md"}')" >/dev/null
if [ ! -f "${TELEM}" ]; then
    _record_pass "no log on **/*.md inventory glob"
else
    _record_fail "no log on **/*.md inventory glob" "telemetry exists for markdown glob"
fi

rm -f "${TELEM}"
_invoke_observer Glob "$(jq -n '{pattern:"**/*.test.ts"}')" >/dev/null
if [ ! -f "${TELEM}" ]; then
    _record_pass "no log on test enumeration glob"
else
    _record_fail "no log on test enumeration glob" "telemetry exists for test glob"
fi

# --- Edit on symbol-shaped single-token diff → log ---

mv "${TEST_TMPDIR}/small.ts" "${TEST_TMPDIR}/svc.ts" 2>/dev/null || true
src="${TEST_TMPDIR}/svc.ts"
[ -f "${src}" ] || printf 'const x = 1;\n' >"${src}"
rm -f "${TELEM}"
_invoke_observer Edit "$(jq -n --arg p "${src}" '{file_path:$p, old_string:"UserService", new_string:"AccountService"}')" >/dev/null
assert_file_exists "Edit symbol-token diff logs observation" "${TELEM}"
assert_contains "Edit log carries edit_symbol_token class" "edit_symbol_token" "$(tail -1 "${TELEM}")"

# --- Edit on multi-line / non-symbol diff → no log ---

rm -f "${TELEM}"
_invoke_observer Edit "$(jq -n --arg p "${src}" '{file_path:$p, old_string:"const x = 1;\nconst y = 2;", new_string:"const x = 100;\nconst y = 200;"}')" >/dev/null
if [ ! -f "${TELEM}" ]; then
    _record_pass "no log on multi-line Edit"
else
    _record_fail "no log on multi-line Edit" "telemetry exists for multi-line Edit"
fi

# --- Disabled by env flag ---

rm -f "${TELEM}"
SERENA_TELEMETRY=0 _invoke_observer Read "$(jq -n --arg p "${big}" '{file_path:$p}')" >/dev/null
if [ ! -f "${TELEM}" ]; then
    _record_pass "SERENA_TELEMETRY=0 disables observer logging"
else
    _record_fail "SERENA_TELEMETRY=0 should disable observer" "telemetry exists with flag off"
fi

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
