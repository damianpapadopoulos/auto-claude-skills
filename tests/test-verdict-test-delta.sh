#!/usr/bin/env bash
# test-verdict-test-delta.sh — verify-and-record records test_delta covered|missing|n/a,
# and hooks/lib/verdict.sh's verdict_test_delta reader agrees with the on-disk verdict.
# Hermetic: HOME is redirected to an isolated sandbox (setup_test_env) so the real
# ~/.claude/.skill-project-verified-* artifacts are never touched.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-verdict-test-delta.sh ==="

setup_test_env
export CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}"   # verify-and-record.sh resolves gate-gaming-check from here
trap 'teardown_test_env' EXIT

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/verdict.sh"

SBOX="${TEST_TMPDIR}/sandbox"
R="${SBOX}/repo"
mkdir -p "${R}/scripts" "${R}/tests" "${R}/tests/fixtures/routing" "${R}/docs"
TOKEN="tdtest-$$"
export SKILL_SESSION_TOKEN="${TOKEN}"
ARTIFACT="${TEST_HOME}/.claude/.skill-project-verified-${TOKEN}"

( cd "${R}"; git init -q -b main; git config user.email t@t.t; git config user.name t
  printf 'substrate: local\nchecks:\n  - name: noop\n    run: "true"\n' > .verify.yml
  echo base > scripts/foo.sh; echo base > tests/test-foo.sh; echo base > docs/x.md
  echo base > tests/fixtures/routing/mock.sh
  git add -A; git commit -qm base ) >/dev/null 2>&1

# verify-and-record.sh now scopes test_delta to the BRANCH diff against the mainline
# base (git merge-base main HEAD), not just the last commit — so each case must run on
# its OWN feature branch cut from "main", exactly like real usage. Committing case after
# case straight onto "main" would self-merge-base to HEAD (empty diff, always "n/a").
_run_case() { # $1 = branch label, $2 = shell snippet (cwd already $R) that produces edits
  local branch="tc-${1}-$$"
  ( cd "${R}" && git checkout -q -b "${branch}" main ) >/dev/null 2>&1
  ( cd "${R}" && eval "$2" )
  ( cd "${R}" && git add -A && git commit -qm change ) >/dev/null 2>&1
  # verify-and-record.sh computes ROOT from `git rev-parse --show-toplevel` in the
  # CURRENT WORKING DIRECTORY — it does NOT honor SKILL_PROJECT_ROOT — so we must
  # cd into the temp repo before invoking it (a real bug in the original brief).
  ( cd "${R}" && bash "${PROJECT_ROOT}/scripts/verify-and-record.sh" ) >/dev/null 2>&1 || true
  jq -r '.test_delta // "ABSENT"' "${ARTIFACT}" 2>/dev/null
  ( cd "${R}" && git checkout -q main ) >/dev/null 2>&1
}

_assert_reader_matches() { # $1 = on-disk value, $2 = case label
  local disk="$1" label="$2" reader
  reader="$(verdict_test_delta "${TOKEN}")"
  [ "$reader" = "$disk" ] && _record_pass "verdict_test_delta reader matches on-disk (${label})" \
      || _record_fail "verdict_test_delta reader matches on-disk (${label})" "reader=$reader disk=$disk"
}

# Case missing: source changed, no test changed
got="$(_run_case missing 'echo change1 > scripts/foo.sh')"
[ "$got" = "missing" ] && _record_pass "source w/o test -> missing" || _record_fail "source w/o test -> missing" "got=$got"
_assert_reader_matches "$got" "missing"

# Case covered: source + test changed
got="$(_run_case covered 'echo change2 > scripts/foo.sh; echo change2 > tests/test-foo.sh')"
[ "$got" = "covered" ] && _record_pass "source + test -> covered" || _record_fail "source + test -> covered" "got=$got"
_assert_reader_matches "$got" "covered"

# Case n/a: docs only
got="$(_run_case docs 'echo change3 > docs/x.md')"
[ "$got" = "n/a" ] && _record_pass "docs only -> n/a" || _record_fail "docs only -> n/a" "got=$got"

# Case: a nested tests/**/*.sh fixture is scaffolding, not a real top-level test file —
# case globs (tests/*.sh) let '*' cross '/', so this guards the classification fix.
got="$(_run_case nested-only 'echo change4 > tests/fixtures/routing/mock.sh')"
[ "$got" = "n/a" ] && _record_pass "nested tests/fixtures/*.sh only -> n/a (not material, not counted as test)" || _record_fail "nested tests/fixtures/*.sh only -> n/a" "got=$got"

# Case: material source change + only a nested fixture .sh touched -> still missing
# (nested test scaffolding must never satisfy the "test changed" requirement).
got="$(_run_case nested-plus-source 'echo change5 > scripts/foo.sh; echo change5 > tests/fixtures/routing/mock.sh')"
[ "$got" = "missing" ] && _record_pass "source + nested fixture only -> missing (nested doesn't count as coverage)" || _record_fail "source + nested fixture only -> missing" "got=$got"

print_summary
