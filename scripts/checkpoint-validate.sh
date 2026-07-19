#!/bin/bash
# checkpoint-validate.sh — deterministic integrity floor for the
# [checkpoint: <sha7>] stamps openspec-ship writes into a retrospective
# tasks.md (issue #129). A stamped lie is worse than no stamp: every stamp
# must be exactly 7 hex chars (case-insensitive) and name a commit inside
# merge-base..HEAD of the CURRENT feature branch.
#
# SCOPE: pre-merge, feature-branch use only. After squash-merge the stamped
# branch SHAs are no longer in main's history, so re-validating an archived
# tasks.md is unsupported by design (every stamp would spuriously fail).
#
# Usage: checkpoint-validate.sh <tasks.md-path> [base-ref]
#   base-ref: optional mainline ref; default = first resolvable of
#             origin/HEAD, @{upstream}, origin/main, main, origin/master, master
# Exit: 0 all stamps valid; 1 integrity violation (details on stderr);
#       2 unrunnable (missing file / not a git repo / unresolvable base).
# Stdout: "checkpoints: N stamped / M completed tasks"
# Advisory tooling — consumed by skills/openspec-ship; never wired into hooks.
set -u

TASKS_FILE="${1:-}"
BASE_REF="${2:-}"

if [ -z "$TASKS_FILE" ] || [ ! -f "$TASKS_FILE" ]; then
    echo "checkpoint-validate: tasks file not found: ${TASKS_FILE:-<missing arg>}" >&2
    exit 2
fi
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "checkpoint-validate: not inside a git repository" >&2
    exit 2
fi

BASE=""
if [ -n "$BASE_REF" ]; then
    BASE="$(git merge-base HEAD "$BASE_REF" 2>/dev/null)" || BASE=""
else
    for _ref in origin/HEAD '@{upstream}' origin/main main origin/master master; do
        BASE="$(git merge-base HEAD "$_ref" 2>/dev/null)" && [ -n "$BASE" ] && break
        BASE=""
    done
fi
if [ -z "$BASE" ]; then
    echo "checkpoint-validate: cannot resolve a mainline merge base" >&2
    exit 2
fi

STAMPED=0
VIOLATIONS=0
# grep -o extracts EVERY stamp, including multiple on one line.
STAMPS="$(grep -o '\[checkpoint: [^]]*\]' "$TASKS_FILE" 2>/dev/null \
    | sed -e 's/^\[checkpoint: //' -e 's/\]$//')"

while IFS= read -r _sha || [ -n "$_sha" ]; do
    [ -z "$_sha" ] && continue
    STAMPED=$((STAMPED + 1))
    _norm="$(printf '%s' "$_sha" | tr 'A-F' 'a-f')"
    if ! printf '%s' "$_norm" | grep -Eq '^[0-9a-f]{7}$'; then
        echo "checkpoint-validate: malformed stamp [checkpoint: ${_sha}] — need exactly 7 hex chars" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        continue
    fi
    # Ambiguous or unknown short SHAs fail closed here.
    _full="$(git rev-parse --verify --quiet "${_norm}^{commit}" 2>/dev/null)" || _full=""
    if [ -z "$_full" ]; then
        echo "checkpoint-validate: unknown or ambiguous commit [checkpoint: ${_sha}]" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        continue
    fi
    # In range = reachable from HEAD and NOT reachable from the base.
    if ! git merge-base --is-ancestor "$_full" HEAD 2>/dev/null \
        || git merge-base --is-ancestor "$_full" "$BASE" 2>/dev/null; then
        echo "checkpoint-validate: commit not in ${BASE}..HEAD [checkpoint: ${_sha}]" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done <<EOF
$STAMPS
EOF

COMPLETED="$(grep -c '^- \[x\]' "$TASKS_FILE" 2>/dev/null)" || COMPLETED=0
echo "checkpoints: ${STAMPED} stamped / ${COMPLETED} completed tasks"
[ "$VIOLATIONS" -eq 0 ] || exit 1
exit 0
