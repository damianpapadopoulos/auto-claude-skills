#!/bin/bash
# test-improvement-miner.sh — unit tests for skills/improvement-miner/
# (content-coverage gate: this file references skills/improvement-miner/)
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MINE="${REPO_ROOT}/skills/improvement-miner/scripts/mine-evidence.sh"

test_fingerprint_stable_and_distinct() {
    echo "-- test: fingerprint is stable across calls, distinct across ids --"
    setup_test_env
    local a b c
    a="$(/bin/bash "${MINE}" fingerprint memory feedback_bash_ere_no_pcre_quantifiers)"
    b="$(/bin/bash "${MINE}" fingerprint memory feedback_bash_ere_no_pcre_quantifiers)"
    c="$(/bin/bash "${MINE}" fingerprint memory feedback_jq_separator_escapes)"
    assert_equals "same input same fp" "$a" "$b"
    [ "$a" != "$c" ] && _record_pass "distinct ids same fp" || _record_fail "distinct ids same fp" "a=$a, c=$c"
    assert_equals "fp length 16" "16" "${#a}"
    teardown_test_env
}

test_missing_gh_fails_loud() {
    echo "-- test: missing gh aborts non-zero with ERROR --"
    setup_test_env
    # stub dir contains jq+shasum+git passthroughs but NO gh; PATH restricted
    local out rc
    mkdir -p "${TEST_TMPDIR}/stub"
    for t in jq shasum git sed grep cut sort ls cat dirname basename mktemp printf; do
        p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "${TEST_TMPDIR}/stub/$t" 2>/dev/null
    done
    out="$(cd "${TEST_TMPDIR}" && PATH="${TEST_TMPDIR}/stub" /bin/bash "${MINE}" bundle 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] && _record_pass "expected non-zero exit" || _record_fail "expected non-zero exit" "rc=$rc"
    assert_contains "ERROR mentions gh" "gh" "$out"
    teardown_test_env
}

test_fingerprint_stable_and_distinct
test_missing_gh_fails_loud

print_summary
