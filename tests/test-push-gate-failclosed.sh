#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-failclosed.sh ==="

# The global fail-closed gate closes the pre-existing fail-open hole: a git push
# with NO active composition state used to be allowed unconditionally. Now every
# push requires a durable review record AND a passing verification signal for the
# branch, unless explicitly bypassed. Fail-open on infra error is preserved.

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

# --- Content assertions (wiring) ---
g="$(cat "${GUARD}")"
assert_contains "gate is fail-closed"                 "fail-closed"           "${g}"
assert_contains "gate honors ACSM_SKIP_PUSH_GATE"     "ACSM_SKIP_PUSH_GATE"   "${g}"

# --- Behavioral setup (mirrors test-push-gate-ledger.sh) ---
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pg-fc-home-XXXXXX)"
mkdir -p "$HOME/.claude"

_TPATH="$HOME/t.jsonl"
touch "$_TPATH"               # basename "t" -> token "session-t"
_TOK="session-t"
_COMP="$HOME/.claude/.skill-composition-state-${_TOK}"

# CRITICAL: no composition state file exists (the fail-open hole). Provide a clean
# verdict covering HEAD so (a) the routing-governance gate is satisfied and (b) the
# VERIFY leg is met — isolating the REVIEW leg as the sole reason for any denial.
_PVHEAD="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null)"
jq -nc --arg s "${_PVHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' \
    > "$HOME/.claude/.skill-project-verified-${_TOK}"

_mkinput() {
    local cmd="${1:-git push origin HEAD}"
    jq -n --arg tp "$_TPATH" --arg cmd "$cmd" \
        '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'
}
run_guard() { _mkinput "${1:-}" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null; }

# (a) No composition, no ledger, verify satisfied but REVIEW missing -> DENY.
#     Under the old fail-open behavior this push was allowed (no _COMP file).
[ -f "${_COMP}" ] && rm -f "${_COMP}"
out="$(run_guard)"
assert_contains     "no composition + no review record => deny" '"deny"'                    "${out:-<empty>}"
assert_contains     "deny names the missing review gate"        "requesting-code-review"    "${out:-<empty>}"

# (b) Record the review milestone in the durable ledger -> ALLOW (both legs met).
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
branch_ledger_record "requesting-code-review" "${PROJECT_ROOT}"
out="$(run_guard)"
assert_not_contains "review recorded + clean verdict => no deny" '"deny"' "${out:-}"

# (c) Escape hatch via inline command prefix -> ALLOW even with no records at all.
#     Remove the ledger + verdict so ONLY the bypass can explain a non-deny.
rm -rf "$(branch_ledger_dir "${PROJECT_ROOT}")" 2>/dev/null
rm -f "$HOME/.claude/.skill-project-verified-${_TOK}"
out="$(run_guard "ACSM_SKIP_PUSH_GATE=1 git push origin HEAD")"
assert_not_contains "inline ACSM_SKIP_PUSH_GATE=1 bypasses gate" '"deny"' "${out:-}"

# (d) Escape hatch via exported env var -> ALLOW.
out="$(_mkinput | ACSM_SKIP_PUSH_GATE=1 CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null)"
assert_not_contains "exported ACSM_SKIP_PUSH_GATE=1 bypasses gate" '"deny"' "${out:-}"

# (e) Non-push commands are never gated (fast-path unchanged).
out="$(_mkinput "git status" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null)"
assert_not_contains "git status is not gated" '"deny"' "${out:-}"

export HOME="$_OLDHOME"
print_summary
exit $?
