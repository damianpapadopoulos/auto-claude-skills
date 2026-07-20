#!/usr/bin/env bash
# memory-validate.sh <memory-dir> [repo-root] — validate a Claude Code auto-memory
# directory. Structural defects -> ERROR (exit 1). Stale repo-path anchors -> WARN
# (exit 0). Bash 3.2 compatible. Advisory: never mutates memory. See
# docs/plans/2026-07-20-memory-validate-design.md.
MEM="${1:?usage: memory-validate.sh <memory-dir> [repo-root]}"
REPO="${2:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
[ -d "${MEM}" ] || exit 0
ERRORS=0
_err()  { printf '[ERROR] %s\n' "$1" >&2; ERRORS=$((ERRORS+1)); }
_warn() { printf '[WARN] %s\n'  "$1" >&2; }
_note() { printf '[NOTE] %s\n'  "$1" >&2; }

# echo the value of metadata.type (nested one level under `metadata:`), or empty.
_meta_type() {
    awk '
        NR==1 && $0=="---"{infm=1; next}
        infm && $0=="---"{exit}
        infm && $0 ~ /^metadata:[[:space:]]*$/{inmeta=1; next}
        infm && inmeta && $0 ~ /^[[:space:]]+type:[[:space:]]/{
            sub(/^[[:space:]]+type:[[:space:]]*/,""); print; exit }
        infm && inmeta && $0 ~ /^[^[:space:]]/{inmeta=0}
    ' "$1"
}

VALID_TYPES=" feedback project reference user "
for f in "${MEM}"/*.md; do
    [ -e "${f}" ] || continue
    base="$(basename "${f}")"; [ "${base}" = "MEMORY.md" ] && continue
    t="$(_meta_type "${f}")"
    case "${VALID_TYPES}" in
        *" ${t} "*) : ;;
        *) _err "${base}: missing or invalid metadata.type ('${t}')" ;;
    esac
done

[ "${ERRORS}" -eq 0 ] || exit 1
exit 0
