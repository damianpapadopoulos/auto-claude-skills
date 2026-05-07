#!/usr/bin/env bash
# test-serena-glob-sequence-check.sh — Verify the Glob sequence-aware analysis
# correctly classifies glob_definition_hunt observations as followed-up,
# intervening-Grep, or revival-signal.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOL="${REPO_ROOT}/scripts/serena-glob-sequence-check.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env
mkdir -p "${HOME}/.claude"
TELEM="${HOME}/.claude/.serena-nudge-telemetry"

NOW="$(date +%s)"

# Scenario 1: Glob followed by Serena call within 3 turns → followup bucket.
printf '%d\ttok-A\t10\tobserve\tglob_definition_hunt\t**/*Foo*\n' "$((NOW - 100))" >>"${TELEM}"
printf '%d\ttok-A\t11\tfollowup\tglob_definition_hunt\tget_symbols_overview\n' "$((NOW - 95))" >>"${TELEM}"

# Scenario 2: Glob followed by Grep nudge within 3 turns (no Serena) → intervening bucket.
printf '%d\ttok-B\t20\tobserve\tglob_definition_hunt\t**/*Bar*\n' "$((NOW - 90))" >>"${TELEM}"
printf '%d\ttok-B\t22\tnudge\tword_boundary\tgrep_extension\n' "$((NOW - 85))" >>"${TELEM}"

# Scenario 3: Glob with nothing after within 3 turns → revival-signal bucket.
printf '%d\ttok-C\t30\tobserve\tglob_definition_hunt\t**/*Baz*\n' "$((NOW - 80))" >>"${TELEM}"
# Far-future event in the same session — outside window, must not count.
printf '%d\ttok-C\t40\tnudge\tcamelcase\tgrep_extension\n' "$((NOW - 75))" >>"${TELEM}"

# Scenario 4: Cross-session noise must not affect another session's glob.
printf '%d\ttok-D\t50\tobserve\tglob_definition_hunt\t**/*Qux*\n' "$((NOW - 70))" >>"${TELEM}"
printf '%d\ttok-OTHER\t51\tnudge\tword_boundary\tgrep_extension\n' "$((NOW - 65))" >>"${TELEM}"
# tok-D's glob has no follow-up in its own session within 3 turns → revival.

out="$(bash "${TOOL}" 14 2>/dev/null)"

assert_contains "report includes total observations" "Total observations" "${out}"
assert_contains "report shows 4 total glob observations" "4" "${out}"
assert_contains "report includes Serena followup bucket" "Serena followup" "${out}"
assert_contains "report shows 1 followup" " 1" "${out}"
assert_contains "report includes intervening Grep bucket" "Intervening Grep" "${out}"
assert_contains "report includes revival-signal bucket" "revival" "${out}"

# Empty-state behaviour.
rm -f "${TELEM}"
out_empty="$(bash "${TOOL}" 14 2>/dev/null)"
assert_contains "empty telemetry yields recognisable empty output" "no telemetry" "${out_empty}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
