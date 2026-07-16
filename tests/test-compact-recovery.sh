#!/usr/bin/env bash
# test-compact-recovery.sh — compact-recovery prompt-carrier suite.
# Spec: openspec/changes/compact-recovery-prompt-carrier/specs/compact-recovery/spec.md
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-compact-recovery.sh ==="

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/crc-home-XXXXXX)"
mkdir -p "$HOME/.claude"
trap 'rm -rf "$HOME"; export HOME="$_OLDHOME"' EXIT

TOKEN="session-test-crc"
RENDER_LIB="${PROJECT_ROOT}/hooks/lib/compact-recovery-render.sh"

_seed_full_state() {
    printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
    printf '# Team checkpoint body\n' > "$HOME/.claude/team-checkpoint.md"
    printf '{"chain":["superpowers:brainstorming","superpowers:writing-plans"],"completed":["superpowers:brainstorming"],"current_index":1}\n' \
        > "$HOME/.claude/.skill-composition-state-${TOKEN}"
    printf 'fix auto-compact recovery :: out-of-scope: session-rules ledger\n' \
        > "$HOME/.claude/.skill-confirmed-intent-${TOKEN}"
    printf '{"changes":{"compact-recovery-prompt-carrier":{"capability_slug":"compact-recovery","archived_at":null},"old-archived-change":{"capability_slug":"x","archived_at":"2026-01-01"}}}\n' \
        > "$HOME/.claude/.skill-openspec-state-${TOKEN}"
}
_clear_state() {
    rm -f "$HOME/.claude/team-checkpoint.md" \
          "$HOME/.claude/.skill-composition-state-${TOKEN}" \
          "$HOME/.claude/.skill-confirmed-intent-${TOKEN}" \
          "$HOME/.claude/.skill-openspec-state-${TOKEN}" \
          "$HOME/.claude/.skill-compact-pending-${TOKEN}" 2>/dev/null
}

# --- renderer: full state emits all sections ---
_clear_state; _seed_full_state
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_contains "renderer emits team checkpoint" "Team checkpoint body" "$_out"
assert_contains "renderer emits composition chain" "superpowers:writing-plans" "$_out"
assert_contains "renderer emits confirmed intent" "fix auto-compact recovery" "$_out"
assert_contains "renderer emits non-archived change slug" "compact-recovery-prompt-carrier" "$_out"
assert_not_contains "renderer omits archived changes" "old-archived-change" "$_out"

# --- renderer: empty state emits nothing ---
_clear_state
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_equals "renderer emits nothing with no state" "" "$_out"

# --- renderer: malformed state degrades to remaining sections ---
_clear_state; _seed_full_state
printf 'NOT JSON{' > "$HOME/.claude/.skill-composition-state-${TOKEN}"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_contains "renderer survives malformed composition state" "fix auto-compact recovery" "$_out"
assert_not_contains "renderer does not leak malformed content" "NOT JSON" "$_out"

# --- renderer: empty token still renders team checkpoint ---
_clear_state
printf '# Team checkpoint body\n' > "$HOME/.claude/team-checkpoint.md"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '' manual" 2>/dev/null)"
assert_contains "empty token renders token-independent sections" "Team checkpoint body" "$_out"

# --- renderer: findings 1 + 4 — intent (and team checkpoint) degrade independently
# of jq; composition/openspec sections require jq and are absent without it. ---
_clear_state; _seed_full_state
_NOJQ_BIN="$(mktemp -d /tmp/crc-nojq-XXXXXX)"
ln -s /bin/cat "$_NOJQ_BIN/cat"
ln -s /usr/bin/head "$_NOJQ_BIN/head"
_out="$(env PATH="$_NOJQ_BIN" /bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
_status=$?
assert_equals "finding4: no-jq renderer exits 0" "0" "$_status"
assert_contains "finding4: no-jq renderer still emits team checkpoint" "Team checkpoint body" "$_out"
assert_contains "finding1: no-jq renderer still emits confirmed intent" "fix auto-compact recovery" "$_out"
assert_not_contains "finding1: no-jq renderer omits composition section (needs jq)" "superpowers:writing-plans" "$_out"
assert_not_contains "finding1: no-jq renderer omits openspec changes (needs jq)" "compact-recovery-prompt-carrier" "$_out"
rm -rf "$_NOJQ_BIN"

# --- renderer: finding 2 — negative current_index must not jq-wrap to the last
# chain element; it must clamp to "unknown". ---
_clear_state
printf '{"chain":["step-a","step-b"],"completed":["step-a"],"current_index":-1}\n' \
    > "$HOME/.claude/.skill-composition-state-${TOKEN}"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_contains "finding2: negative current_index clamps to unknown" "Current step: unknown" "$_out"
assert_not_contains "finding2: negative current_index does not name last chain element as current" "Current step: step-b" "$_out"

# --- renderer: finding 3 — openspec changes summary bounded to 6, deterministic
# survivors (jq to_entries preserves insertion order: slug-1..slug-6 survive). ---
_clear_state
_changes_json='{"changes":{'
_i=1
while [ "$_i" -le 8 ]; do
    _slug="$(printf 'slug-%02d' "$_i")"
    _changes_json="${_changes_json}\"${_slug}\":{\"archived_at\":null}"
    [ "$_i" -lt 8 ] && _changes_json="${_changes_json},"
    _i=$((_i + 1))
done
_changes_json="${_changes_json}}}"
printf '%s\n' "$_changes_json" > "$HOME/.claude/.skill-openspec-state-${TOKEN}"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_contains "finding3: bounded changes keeps slug-01" "slug-01" "$_out"
assert_contains "finding3: bounded changes keeps slug-06" "slug-06" "$_out"
assert_not_contains "finding3: bounded changes drops slug-07" "slug-07" "$_out"
assert_not_contains "finding3: bounded changes drops slug-08" "slug-08" "$_out"

# --- pre-compact: writes marker + log even with cozempic absent ---
PRE_HOOK="${PROJECT_ROOT}/hooks/pre-compact-hook.sh"
_clear_state
printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
_fake_transcript="$HOME/fake-transcript.jsonl"
printf '{"type":"user"}\n' > "$_fake_transcript"
printf '{"session_id":"s1","transcript_path":"%s","trigger":"auto"}' "$_fake_transcript" \
    | PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PRE_HOOK" >/dev/null 2>&1
assert_equals "pre-compact exits 0 without cozempic" "0" "$?"
assert_file_exists "pre-compact writes pending marker without cozempic" "$HOME/.claude/.skill-compact-pending-${TOKEN}"
_marker_body="$(cat "$HOME/.claude/.skill-compact-pending-${TOKEN}" 2>/dev/null)"
assert_contains "marker records the trigger" "trigger=auto" "$_marker_body"
assert_file_exists "pre-compact logs event without cozempic" "$HOME/.claude/.compact-events.log"

print_summary
