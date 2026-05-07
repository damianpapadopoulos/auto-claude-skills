#!/usr/bin/env bash
# test-serena-behavioral-pack.sh — Hermetic schema + structure validation for
# the Serena routing behavioral pack at tests/fixtures/serena/behavioral.json.
# Does NOT invoke claude — that path is opt-in via BEHAVIORAL_EVALS=1.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACK="${PROJECT_ROOT}/tests/fixtures/serena/behavioral.json"
STUB="${PROJECT_ROOT}/tests/fixtures/serena/skill-stub.md"
README="${PROJECT_ROOT}/tests/fixtures/serena/README.md"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

assert_file_exists "behavioral pack file exists" "${PACK}"
assert_file_exists "skill stub file exists" "${STUB}"
assert_file_exists "README documenting how to run exists" "${README}"

assert_json_valid "pack is valid JSON" "${PACK}"

# Pack must be a non-empty array.
PACK_KIND="$(jq -r 'type' "${PACK}" 2>/dev/null)"
assert_equals "pack root is an array" "array" "${PACK_KIND}"
PACK_LEN="$(jq -r 'length' "${PACK}" 2>/dev/null)"
[ "${PACK_LEN}" -ge 1 ] && _record_pass "pack has at least one scenario" \
    || _record_fail "pack has at least one scenario" "got length ${PACK_LEN}"

# Subagent-propagation scenario must exist by id.
SCENARIO="$(jq '.[] | select(.id == "subagent-propagation")' "${PACK}" 2>/dev/null)"
assert_not_empty "subagent-propagation scenario is present" "${SCENARIO}"

# Required fields per the runner's schema (tests/run-behavioral-evals.sh:124).
for field in id prompt expected_behavior assertions; do
    has="$(printf '%s' "${SCENARIO}" | jq -e --arg f "${field}" 'has($f)' 2>/dev/null)"
    assert_equals "scenario has required field '${field}'" "true" "${has}"
done

# Each assertion must have text and description.
ASSERTION_COUNT="$(printf '%s' "${SCENARIO}" | jq '.assertions | length')"
[ "${ASSERTION_COUNT}" -ge 1 ] && _record_pass "scenario has at least one assertion" \
    || _record_fail "scenario has at least one assertion" "got ${ASSERTION_COUNT}"

i=0
while [ "${i}" -lt "${ASSERTION_COUNT}" ]; do
    text="$(printf '%s' "${SCENARIO}" | jq -r ".assertions[${i}].text // empty")"
    desc="$(printf '%s' "${SCENARIO}" | jq -r ".assertions[${i}].description // empty")"
    assert_not_empty "assertion ${i} has 'text'" "${text}"
    assert_not_empty "assertion ${i} has 'description'" "${desc}"
    i=$((i + 1))
done

# Spot-check the assertion regexes are valid extended regex (case-insensitive).
# A bad regex would silently fail at runtime; catch it now.
i=0
while [ "${i}" -lt "${ASSERTION_COUNT}" ]; do
    text="$(printf '%s' "${SCENARIO}" | jq -r ".assertions[${i}].text")"
    if printf 'sentinel test string' | grep -Eiq -- "${text}" 2>/dev/null; then
        _record_pass "assertion ${i} regex compiles"
    elif printf '' | grep -Eiq -- "${text}" 2>/dev/null; then
        _record_pass "assertion ${i} regex compiles (no match on sentinel — fine)"
    else
        # Regex compiles only if grep doesn't error. Run grep once with the
        # pattern; non-zero from a bad pattern is exit 2, not 1.
        printf '' | grep -Ei -- "${text}" >/dev/null 2>&1
        rc=$?
        if [ "${rc}" -le 1 ]; then
            _record_pass "assertion ${i} regex compiles"
        else
            _record_fail "assertion ${i} regex compiles" "grep returned exit ${rc} for pattern: ${text}"
        fi
    fi
    i=$((i + 1))
done

# Skill stub should be intentionally short. The test guards against accidental
# bloat that would steer claude into a real skill workflow.
STUB_WORDS="$(wc -w <"${STUB}" | tr -d ' ')"
[ "${STUB_WORDS}" -lt 200 ] && _record_pass "skill stub is concise (<200 words)" \
    || _record_fail "skill stub is concise" "stub has ${STUB_WORDS} words; intentionally near-empty"

# README must mention the worktree-sandboxing safety advice and variance mode —
# both are load-bearing for honest interpretation of results.
assert_contains "README warns about worktree sandboxing" "worktree" "$(cat "${README}")"
assert_contains "README recommends --variance" "variance" "$(cat "${README}")"
assert_contains "README warns about Edit/Write tool revert risk" "revert" "$(cat "${README}")"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
