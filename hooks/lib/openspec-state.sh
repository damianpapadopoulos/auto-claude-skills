#!/usr/bin/env bash
# openspec-state.sh — Persistence helper for OpenSpec session state
# Sourced by skills/hooks that need state file access.
# Bash 3.2 compatible. Requires jq.

# State file path: ~/.claude/.skill-openspec-state-<session_token>

# --- openspec_state_mark_verified <session_token> <surface> -------
# Create or update state file with verification fields.
# Idempotent merge: preserves existing 'changes' map.
openspec_state_mark_verified() {
    local token="${1:-}"
    local surface="${2:-none}"
    [ -z "$token" ] && echo "[openspec-state] WARN: no session token, skipping state write" >&2 && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [ -f "$state_file" ]; then
        # Merge into existing file
        local tmp
        tmp="$(jq --arg surface "$surface" --arg now "$now" '
            .verification_seen = true |
            .verification_at = $now |
            .openspec_surface = (.openspec_surface // $surface)
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        # Create new file
        jq -n --arg surface "$surface" --arg now "$now" '{
            openspec_surface: $surface,
            verification_seen: true,
            verification_at: $now,
            changes: {}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_upsert_change <token> <slug> <plan_path> <spec_path> <capability> [<design_path>] ---
# Add or update a change entry in the changes map.
# Idempotent: existing entries for other slugs are preserved.
# Writes canonical field names (design_path, plan_path, spec_path) and
# legacy aliases (sp_plan_path, sp_spec_path) for backward compatibility.
openspec_state_upsert_change() {
    local token="${1:-}"
    local slug="${2:-}"
    local plan_path="${3:-}"
    local spec_path="${4:-}"
    local capability="${5:-}"
    local design_path="${6:-}"
    [ -z "$token" ] && echo "[openspec-state] WARN: no session token, skipping state write" >&2 && return 0
    [ -z "$slug" ] && echo "[openspec-state] WARN: no change slug, skipping state write" >&2 && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    if [ -f "$state_file" ]; then
        local tmp
        tmp="$(jq --arg slug "$slug" --arg pp "$plan_path" --arg sp "$spec_path" --arg cap "$capability" --arg dp "$design_path" '
            .changes[$slug] = {
                design_path: $dp,
                plan_path: $pp,
                spec_path: $sp,
                sp_plan_path: $pp,
                sp_spec_path: $sp,
                capability_slug: $cap,
                archived_at: null
            }
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        # Create new file with just the change entry
        jq -n --arg slug "$slug" --arg pp "$plan_path" --arg sp "$spec_path" --arg cap "$capability" --arg dp "$design_path" '{
            openspec_surface: "none",
            verification_seen: false,
            verification_at: null,
            changes: {($slug): {
                design_path: $dp,
                plan_path: $pp,
                spec_path: $sp,
                sp_plan_path: $pp,
                sp_spec_path: $sp,
                capability_slug: $cap,
                archived_at: null
            }}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_set_discovery_path <token> <slug> <discovery_path> ---
# Set discovery_path for a change entry.
# Creates the change entry if it doesn't exist (merges with existing fields).
# Same jq-merge pattern as openspec_state_mark_verified.
openspec_state_set_discovery_path() {
    local token="${1:-}"
    local slug="${2:-}"
    local discovery_path="${3:-}"
    [ -z "$token" ] && return 0
    [ -z "$slug" ] && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    if [ -f "$state_file" ]; then
        local tmp
        tmp="$(jq --arg slug "$slug" --arg dp "$discovery_path" '
            .changes[$slug] = ((.changes[$slug] // {}) + {discovery_path: $dp})
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        jq -n --arg slug "$slug" --arg dp "$discovery_path" '{
            openspec_surface: "none",
            verification_seen: false,
            verification_at: null,
            changes: {($slug): {discovery_path: $dp}}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_read <session_token> --------------------------
# Read and output current state file as JSON.
# Returns empty {} if file doesn't exist or is malformed.
openspec_state_read() {
    local token="${1:-}"
    [ -z "$token" ] && echo '{}' && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    if [ -f "$state_file" ]; then
        jq '.' "$state_file" 2>/dev/null || echo '{}'
    else
        echo '{}'
    fi
}

# --- openspec_write_provenance <archive_path> <session_token> <slug> ---
# Write source.json to <archive_path>/superpowers/source.json.
# Creates the superpowers/ directory if needed.
openspec_write_provenance() {
    local archive_path="${1:-}"
    local token="${2:-}"
    local slug="${3:-}"
    [ -z "$archive_path" ] && echo "[openspec-state] WARN: no archive path, skipping provenance" >&2 && return 0
    [ -z "$token" ] && echo "[openspec-state] WARN: no session token, skipping provenance" >&2 && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
    local commit
    commit="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    mkdir -p "${archive_path}/superpowers"

    if [ -f "$state_file" ] && [ -n "$slug" ]; then
        jq --arg slug "$slug" --arg branch "$branch" --arg commit "$commit" --arg now "$now" '
            {
                schema_version: 1,
                discovery_path: (.changes[$slug].discovery_path // null),
                design_path: (.changes[$slug].design_path // null),
                plan_path: (.changes[$slug].plan_path // .changes[$slug].sp_plan_path // null),
                spec_path: (.changes[$slug].spec_path // .changes[$slug].sp_spec_path // null),
                # Legacy aliases (deprecated — readers should use canonical names above)
                sp_plan_path: (.changes[$slug].sp_plan_path // .changes[$slug].plan_path // null),
                sp_spec_path: (.changes[$slug].sp_spec_path // .changes[$slug].spec_path // null),
                change_slug: $slug,
                capability_slug: (.changes[$slug].capability_slug // null),
                source_branch: $branch,
                base_commit: $commit,
                openspec_surface: (.openspec_surface // "none"),
                archived_at: $now
            }
        ' "$state_file" > "${archive_path}/superpowers/source.json" 2>/dev/null || {
            echo "[openspec-state] WARN: provenance write failed" >&2
            return 0
        }
    else
        # No state file — write minimal provenance
        jq -n --arg slug "$slug" --arg branch "$branch" --arg commit "$commit" --arg now "$now" '{
            schema_version: 1,
            discovery_path: null,
            design_path: null,
            plan_path: null,
            spec_path: null,
            sp_plan_path: null,
            sp_spec_path: null,
            change_slug: $slug,
            capability_slug: null,
            source_branch: $branch,
            base_commit: $commit,
            openspec_surface: "none",
            archived_at: $now
        }' > "${archive_path}/superpowers/source.json" 2>/dev/null || {
            echo "[openspec-state] WARN: provenance write failed" >&2
            return 0
        }
    fi
}
