#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-verdict-lib.sh ==="

# ---- Content assertion: project-verification artifact documents the sha field ----
SKILL="${PROJECT_ROOT}/skills/project-verification/SKILL.md"
s="$(cat "${SKILL}")"
assert_contains "artifact snippet computes HEAD sha" "git rev-parse HEAD" "${s}"
assert_contains "artifact schema documents sha field" '"sha"' "${s}"

# ---- Unit tests for hooks/lib/verdict.sh ----
LIB="${PROJECT_ROOT}/hooks/lib/verdict.sh"
assert_file_exists "verdict.sh exists" "${LIB}"
# shellcheck disable=SC1090
. "${LIB}"

_bool() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }

TMP="$(mktemp -d /tmp/verdict-XXXXXX)"
_OLDHOME="$HOME"
REPO="${TMP}/repo"
mkdir -p "${REPO}"
(
  cd "${REPO}"
  git init -q
  git config user.email t@t; git config user.name t
  mkdir -p config; echo '{}' > config/default-triggers.json
  git add -A; git commit -qm c1
)
C1="$(git -C "${REPO}" rev-parse HEAD)"

export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
TOKEN="tok1"
ART="${HOME}/.claude/.skill-project-verified-${TOKEN}"
mkart() { printf '%s' "$1" > "${ART}"; }

# clean verdict at C1
mkart "$(jq -nc --arg s "${C1}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "clean verdict detected"        "0" "$(_bool verdict_is_clean "${TOKEN}")"
assert_equals "sha_is_head at C1"             "0" "$(_bool verdict_sha_is_head "${TOKEN}" "${REPO}")"
assert_equals "covers_head at C1"             "0" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"
assert_equals "clean => no test failure"      "1" "$(_bool verdict_has_test_failure "${TOKEN}")"
assert_equals "routing repo detected"         "0" "$(_bool is_routing_repo "${REPO}")"

# failing verdict at C1
mkart "$(jq -nc --arg s "${C1}" '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "test failure detected"         "0" "$(_bool verdict_has_test_failure "${TOKEN}")"
assert_equals "failing gate named"        "tests" "$(verdict_failing_gates "${TOKEN}")"
assert_equals "failing => not clean"          "1" "$(_bool verdict_is_clean "${TOKEN}")"

# ancestor sha: add C2, artifact still references C1
( cd "${REPO}"; echo x >> config/default-triggers.json; git commit -qam c2 )
mkart "$(jq -nc --arg s "${C1}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "ancestor covers_head"          "0" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"
assert_equals "ancestor is not head"          "1" "$(_bool verdict_sha_is_head "${TOKEN}" "${REPO}")"

# unrelated sha (cross-branch) MUST NOT cover HEAD -- false-block guard
mkart "$(jq -nc '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:"0000000000000000000000000000000000000000"}')"
assert_equals "unrelated sha !covers (false-block guard)" "1" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"

# no-sha artifact MUST NOT cover HEAD
mkart "$(jq -nc '{failed:[],could_not_verify:[],gate_gaming_status:"clean"}')"
assert_equals "missing sha !covers"           "1" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"

# absent artifact
rm -f "${ART}"
assert_equals "absent => not clean"           "1" "$(_bool verdict_is_clean "${TOKEN}")"
assert_equals "absent => no failure"          "1" "$(_bool verdict_has_test_failure "${TOKEN}")"
assert_equals "absent => no cover"            "1" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"

# non-routing repo (no config/default-triggers.json)
REPO2="${TMP}/repo2"; mkdir -p "${REPO2}"
( cd "${REPO2}"; git init -q; git config user.email t@t; git config user.name t; echo hi > f; git add -A; git commit -qm c )
assert_equals "non-routing repo not detected" "1" "$(_bool is_routing_repo "${REPO2}")"

# diff_touches_routing: routing change vs base
( cd "${REPO}"
  git checkout -q -b feature
  git branch -q main C1 2>/dev/null || git branch -q -f main "${C1}"
  mkdir -p hooks; echo 'echo hi' > hooks/x.sh
  git add -A; git commit -qm routing-change )
assert_equals "diff touches routing (hooks/)" "0" "$(_bool diff_touches_routing "${REPO}")"

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary
exit $?
