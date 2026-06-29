#!/usr/bin/env bash
# branch-ledger.sh — durable per-(repo+branch) gating-milestone ledger for the
# push gate. Decoupled from the transient composition .completed so gate
# readiness survives composition chain re-anchors. Bash 3.2; all functions
# fail-open: on any error they behave as "no ledger" so the caller falls back
# to the .completed check. Keying mirrors consol-marker.sh (remote-url → path).

branch_ledger_key() {
    local proj_root="${1:-}" key branch sha hash
    [ -z "$proj_root" ] && proj_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$proj_root" ] && return 1
    key="$(git -C "$proj_root" remote get-url origin 2>/dev/null || true)"
    [ -z "$key" ] && key="$proj_root"
    branch="$(git -C "$proj_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [ -z "$branch" ]; then
        sha="$(git -C "$proj_root" rev-parse --short HEAD 2>/dev/null || true)"
        [ -z "$sha" ] && return 1
        branch="detached-${sha}"
    fi
    hash="$(printf '%s\x1f%s' "$key" "$branch" | shasum 2>/dev/null | cut -d' ' -f1)"
    [ -z "$hash" ] && return 1
    printf '%s' "$hash"
}

branch_ledger_dir() {
    local k; k="$(branch_ledger_key "${1:-}")" || return 1
    [ -z "$k" ] && return 1
    printf '%s' "${HOME}/.claude/.skill-branch-ledger-${k}"
}

branch_ledger_record() {
    local milestone="${1:-}" proj_root="${2:-}" dir sha
    [ -z "$milestone" ] && return 0
    dir="$(branch_ledger_dir "$proj_root")" || return 0
    [ -z "$dir" ] && return 0
    [ -z "$proj_root" ] && proj_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    sha="$(git -C "${proj_root:-.}" rev-parse HEAD 2>/dev/null || true)"
    mkdir -p "$dir" 2>/dev/null || return 0
    # per-milestone file (no shared-JSON read-modify-write → no concurrent race);
    # atomic write; content = "<sha> <utc-ts>"
    printf '%s %s\n' "${sha:-unknown}" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
        > "${dir}/${milestone}.tmp.$$" 2>/dev/null \
        && mv "${dir}/${milestone}.tmp.$$" "${dir}/${milestone}" 2>/dev/null || return 0
    return 0
}

branch_ledger_has() {
    local milestone="${1:-}" proj_root="${2:-}" dir
    [ -z "$milestone" ] && return 1
    dir="$(branch_ledger_dir "$proj_root")" || return 1
    [ -z "$dir" ] && return 1
    [ -f "${dir}/${milestone}" ]
}

branch_ledger_sha() {
    local milestone="${1:-}" proj_root="${2:-}" dir
    dir="$(branch_ledger_dir "$proj_root")" || return 0
    [ -z "$dir" ] && return 0
    [ -f "${dir}/${milestone}" ] || return 0
    cut -d' ' -f1 < "${dir}/${milestone}" 2>/dev/null || true
}
