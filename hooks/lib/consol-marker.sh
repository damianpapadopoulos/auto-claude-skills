#!/usr/bin/env bash
# consol-marker.sh — Shared helper for the memory-consolidation marker path.
# Sourced by openspec-guard.sh and consolidation-stop.sh so both compute the
# same marker path for the same repo — even across worktrees and clones.
# Bash 3.2 compatible. No external deps beyond git and shasum.

# --- consol_marker_path [<proj_root>] ------------------------------
# Echo the absolute path of the consolidation marker for a project.
# Key precedence:
#   1. git remote.origin.url — stable across worktrees/clones of the same repo
#   2. absolute project path — fallback when there's no remote
# Stdout: full marker path (never trailing newline-only output).
consol_marker_path() {
    local proj_root="${1:-}"
    if [ -z "$proj_root" ]; then
        proj_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi

    local key
    key="$(git -C "$proj_root" remote get-url origin 2>/dev/null || true)"
    [ -z "$key" ] && key="$proj_root"

    local hash
    hash="$(printf '%s' "$key" | shasum | cut -d' ' -f1)"

    printf '%s' "${HOME}/.claude/.context-stack-consolidated-${hash}"
}
