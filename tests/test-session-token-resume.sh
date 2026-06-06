#!/usr/bin/env bash
# test-session-token-resume.sh — Regression test: the session token MUST stay
# stable across resume/compact.
#
# Root cause (investigated 2026-06-05): session-start-hook keyed the token off
# stdin `.session_id`, assuming it is stable for the life of a conversation. It
# is NOT — `resume` and `compact` deliver a fresh `session_id` while the same
# conversation continues (the plugin's SessionStart hook has an empty matcher, so
# it fires on resume/compact too). Each fire rewrote the shared token, orphaning
# every composition/openspec-state file keyed off it and producing false-negative
# push-gate and consolidation-guard blocks even though REVIEW/VERIFY/consolidation
# genuinely happened.
#
# Fix: derive the token from a conversation-stable id — the `transcript_path`
# basename — when available. `transcript_path` IS the conversation log and
# persists across resume/compact, whereas `session_id` is regenerated. Falls back
# to `session_id`, then to the reuse-window/random logic, preserving prior
# contracts.
#
# Bash 3.2 compatible. Sources test-helpers.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-session-token-resume.sh ==="

# The transcript-derived token requires jq to parse stdin. Honor the repo's
# "jq optional at runtime" contract: if jq is absent, this derivation cannot run,
# so skip rather than fail.
if ! command -v jq >/dev/null 2>&1; then
    _record_pass "jq unavailable — transcript token derivation is jq-gated; skipping"
    print_summary
    exit 0
fi

run_hook_with() {
    # $1 = JSON payload delivered on the hook's stdin (as Claude Code does).
    printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" >/dev/null 2>&1 || true
}
read_token() { cat "${HOME}/.claude/.skill-session-token" 2>/dev/null; }

# ---------------------------------------------------------------------------
# R1 — Resume preserves the token (session_id rotates, transcript_path stable)
# ---------------------------------------------------------------------------
echo "--- R1: resume preserves token across session_id rotation ---"
setup_test_env
mkdir -p "${HOME}/.claude"
run_hook_with '{"session_id":"aaaaaaaa-1111-2222-3333-444444444444","transcript_path":"/tmp/proj/conv-ALPHA.jsonl"}'
R1_FIRST="$(read_token)"
# Resume: Claude Code regenerates session_id but continues the SAME conversation.
run_hook_with '{"session_id":"bbbbbbbb-5555-6666-7777-888888888888","transcript_path":"/tmp/proj/conv-ALPHA.jsonl"}'
R1_RESUME="$(read_token)"
assert_not_empty "R1: first token non-empty" "${R1_FIRST}"
assert_equals "R1: resume preserves token across session_id rotation" "${R1_FIRST}" "${R1_RESUME}"
teardown_test_env

# ---------------------------------------------------------------------------
# R2 — Distinct conversations (different transcript_path) get distinct tokens
# ---------------------------------------------------------------------------
echo "--- R2: distinct conversations get distinct tokens ---"
setup_test_env
mkdir -p "${HOME}/.claude"
# Same session_id on purpose: only transcript_path differs. With the old
# session_id-keyed logic these would collide; the fix must keep them distinct.
run_hook_with '{"session_id":"cccccccc-0000","transcript_path":"/tmp/proj/conv-ALPHA.jsonl"}'
R2_A="$(read_token)"
run_hook_with '{"session_id":"cccccccc-0000","transcript_path":"/tmp/proj/conv-BETA.jsonl"}'
R2_B="$(read_token)"
if [ -n "${R2_A}" ] && [ "${R2_A}" != "${R2_B}" ]; then
    _record_pass "R2: different transcript_path -> different token"
else
    _record_fail "R2: different transcript_path -> different token" "A='${R2_A}' B='${R2_B}'"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# R3 — Back-compat: transcript_path absent but session_id present
# ---------------------------------------------------------------------------
echo "--- R3: session_id-only path preserved when transcript_path absent ---"
setup_test_env
mkdir -p "${HOME}/.claude"
run_hook_with '{"session_id":"dddddddd-9999"}'
R3="$(read_token)"
assert_equals "R3: session_id-only -> session-<id>" "session-dddddddd-9999" "${R3}"
teardown_test_env

print_summary
