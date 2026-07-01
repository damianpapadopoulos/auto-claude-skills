#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-verdict.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

# ---- Wiring assertions ----
g="$(cat "${GUARD}")"
assert_contains "gate sources verdict lib"          "verdict.sh"             "${g}"
assert_contains "gate does verify-hardening"        "verdict_has_test_failure" "${g}"
assert_contains "gate does routing governance"      "diff_touches_routing"   "${g}"

# ---- Behavioral setup (token resolves from transcript basename: t.jsonl -> session-t) ----
_OLDHOME="$HOME"
TMP="$(mktemp -d /tmp/pgv-XXXXXX)"
export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
_TPATH="${HOME}/t.jsonl"; touch "${_TPATH}"
TOK="session-t"
ART="${HOME}/.claude/.skill-project-verified-${TOK}"
COMP="${HOME}/.claude/.skill-composition-state-${TOK}"
# Status layer: review+verify both completed, so the existing status checks pass
# and ONLY a verdict can produce a new denial.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":2,"completed":["requesting-code-review","verification-before-completion"]}' > "${COMP}"

mkinput() { jq -n --arg tp "${_TPATH}" '{"transcript_path":$tp,"tool_input":{"command":"git push origin HEAD"}}'; }
run_in() { ( cd "$1" && mkinput | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null ); }
mkart() { printf '%s' "$1" > "${ART}"; }

# ================= Verify-verdict hardening (non-routing repo, isolated) =================
NR="${TMP}/nonrouting"; mkdir -p "${NR}"
( cd "${NR}"; git init -q; git config user.email t@t; git config user.name t; echo a > f; git add -A; git commit -qm c1 )
NRHEAD="$(git -C "${NR}" rev-parse HEAD)"

# (1) failing verdict covering HEAD -> DENY (status says done, but tests failed)
mkart "$(jq -nc --arg s "${NRHEAD}" '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${NR}")"
assert_contains     "failing verdict at HEAD => deny"        '"deny"' "${out:-<empty>}"
assert_contains     "deny names the failing gate"           "tests"  "${out:-<empty>}"

# (2) failing verdict NOT covering HEAD (unrelated sha) -> NO deny  [FALSE-BLOCK GUARD]
mkart "$(jq -nc '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:"0000000000000000000000000000000000000000"}')"
out="$(run_in "${NR}")"
assert_not_contains "stale/cross-branch fail => no deny"     '"deny"' "${out:-}"

# (3) no artifact -> NO deny on verdict grounds (status governs, unchanged)
rm -f "${ART}"
out="$(run_in "${NR}")"
assert_not_contains "absent verdict => no deny"             '"deny"' "${out:-}"

# (4) clean verdict covering HEAD -> NO deny
mkart "$(jq -nc --arg s "${NRHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${NR}")"
assert_not_contains "clean verdict => no deny"             '"deny"' "${out:-}"

# ================= Routing-governance gate (routing repo) =================
RR="${TMP}/routing"; mkdir -p "${RR}"
( cd "${RR}"; git init -q; git config user.email t@t; git config user.name t
  mkdir config; echo '{}' > config/default-triggers.json; git add -A; git commit -qm c1 )
RRBASE="$(git -C "${RR}" rev-parse HEAD)"
( cd "${RR}"; git checkout -q -b feature; git branch -f main "${RRBASE}"
  mkdir hooks; echo 'echo x' > hooks/y.sh; git add -A; git commit -qm routing-change )
RRHEAD="$(git -C "${RR}" rev-parse HEAD)"

# (5) routing diff + NO clean verdict -> DENY with project-verification remedy
rm -f "${ART}"
out="$(run_in "${RR}")"
assert_contains     "routing change, no verdict => deny"    '"deny"'              "${out:-<empty>}"
assert_contains     "routing deny names project-verification" "project-verification" "${out:-<empty>}"

# (6) routing diff + clean verdict covering HEAD -> NO deny
mkart "$(jq -nc --arg s "${RRHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${RR}")"
assert_not_contains "routing + clean@HEAD => no deny"       '"deny"' "${out:-}"

# (7) routing diff + clean verdict at ancestor (base) -> NO deny (stale => advisory only)
mkart "$(jq -nc --arg s "${RRBASE}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${RR}")"
assert_not_contains "routing + clean@ancestor => no deny"   '"deny"' "${out:-}"

# (8) non-routing repo + routing-named diff + no verdict -> NO deny (routing gate scoped out)
( cd "${NR}"; git checkout -q -b feature2; mkdir -p hooks; echo z > hooks/z.sh; git add -A; git commit -qm h )
rm -f "${ART}"
out="$(run_in "${NR}")"
assert_not_contains "non-routing repo => routing gate scoped out" '"deny"' "${out:-}"

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary
exit $?
