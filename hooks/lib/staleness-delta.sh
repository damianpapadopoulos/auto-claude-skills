#!/usr/bin/env bash
# staleness-delta.sh — classify the commit delta between a review-evidence SHA
# and a target SHA (default HEAD) into docs vs source, with file and line
# counts. Shared instrument: the post-review-staleness backtest
# (openspec/changes/gate-status/backtest-protocol.md) and the gate-status
# staleness observation line MUST both use this classifier so live data stays
# comparable to the backtest.
#
# Bash 3.2; fail-open: on any error emits nothing and returns 0 so callers
# render "unknown" instead of breaking.
#
# staleness_delta <from-sha> [<to-sha>] [<repo-root>]
#   stdout on success (single line, space-separated key=value):
#     files=N docs_files=N src_files=N docs_lines=N src_lines=N
#   lines = additions + deletions (git diff --numstat); binary files count as
#   a file with 0 lines.
#
# Docs classification (frozen in the backtest protocol — change requires a
# re-registered backtest): docs/**, openspec/**, any *.md. Everything else is
# source. (The protocol also names CHANGELOG.md explicitly; it is subsumed by
# the *.md rule — the classifier is functionally identical to the frozen set.)

staleness_delta_is_docs() {
    case "$1" in
        docs/*|openspec/*|*.md) return 0 ;;
        *) return 1 ;;
    esac
}

staleness_delta() {
    local from="${1:-}" to="${2:-HEAD}" root="${3:-}"
    [ -z "$from" ] && return 0
    [ -z "$root" ] && root="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$root" ] && return 0
    git -C "$root" rev-parse --verify --quiet "${from}^{commit}" >/dev/null 2>&1 || return 0
    git -C "$root" rev-parse --verify --quiet "${to}^{commit}" >/dev/null 2>&1 || return 0

    local numstat
    # --no-renames: rename rows ("dir/{a.md => b.md}") would defeat the
    # suffix classification; as add+delete pairs every path is literal.
    numstat="$(git -C "$root" diff --no-renames --numstat "$from" "$to" -- 2>/dev/null)" || return 0

    local files=0 docs_files=0 src_files=0 docs_lines=0 src_lines=0
    local add del path
    while IFS="$(printf '\t')" read -r add del path; do
        [ -z "$path" ] && continue
        files=$(( files + 1 ))
        # binary files report "-" for add/del
        [[ "$add" =~ ^[0-9]+$ ]] || add=0
        [[ "$del" =~ ^[0-9]+$ ]] || del=0
        if staleness_delta_is_docs "$path"; then
            docs_files=$(( docs_files + 1 ))
            docs_lines=$(( docs_lines + add + del ))
        else
            src_files=$(( src_files + 1 ))
            src_lines=$(( src_lines + add + del ))
        fi
    done <<EOF
$numstat
EOF
    printf 'files=%d docs_files=%d src_files=%d docs_lines=%d src_lines=%d\n' \
        "$files" "$docs_files" "$src_files" "$docs_lines" "$src_lines"
    return 0
}
