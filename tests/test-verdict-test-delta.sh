#!/usr/bin/env bash
# test-verdict-test-delta.sh — verify-and-record records test_delta covered|missing|n/a.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-verdict-test-delta.sh ==="

SBOX="$(mktemp -d)"
R="${SBOX}/repo"; mkdir -p "${R}/scripts" "${R}/tests" "${R}/docs"
export SKILL_SESSION_TOKEN="tdtest-$$"
trap 'rm -rf "${SBOX}"; rm -f "${HOME}/.claude/.skill-project-verified-${SKILL_SESSION_TOKEN}"' EXIT
( cd "${R}"; git init -q; git config user.email t@t.t; git config user.name t
  printf 'substrate: local\nchecks:\n  - name: noop\n    run: "true"\n' > .verify.yml
  echo base > scripts/foo.sh; echo base > tests/test-foo.sh; echo base > docs/x.md
  git add -A; git commit -qm base ) >/dev/null 2>&1

_run_case() { # $1 = expected test_delta ; edits already staged/committed on top of base
  ( cd "${R}"; git add -A; git commit -qm change >/dev/null 2>&1 )
  # verify-and-record.sh computes ROOT from `git rev-parse --show-toplevel` in the
  # CURRENT WORKING DIRECTORY — it does NOT honor SKILL_PROJECT_ROOT — so we must
  # cd into the temp repo before invoking it (a real bug in the original brief).
  ( cd "${R}"; bash "${PROJECT_ROOT}/scripts/verify-and-record.sh" >/dev/null 2>&1 ) || true
  # read the verdict the script wrote for our token
  local v="${HOME}/.claude/.skill-project-verified-${SKILL_SESSION_TOKEN}"
  jq -r '.test_delta // "ABSENT"' "$v" 2>/dev/null
}

# Case missing: source changed, no test changed
( cd "${R}"; echo change1 > scripts/foo.sh )
got="$(_run_case)"; [ "$got" = "missing" ] && _record_pass "source w/o test -> missing" || _record_fail "source w/o test -> missing" "got=$got"

# Case covered: source + test changed
( cd "${R}"; echo change2 > scripts/foo.sh; echo change2 > tests/test-foo.sh )
got="$(_run_case)"; [ "$got" = "covered" ] && _record_pass "source + test -> covered" || _record_fail "source + test -> covered" "got=$got"

# Case n/a: docs only
( cd "${R}"; echo change3 > docs/x.md )
got="$(_run_case)"; [ "$got" = "n/a" ] && _record_pass "docs only -> n/a" || _record_fail "docs only -> n/a" "got=$got"

print_summary
