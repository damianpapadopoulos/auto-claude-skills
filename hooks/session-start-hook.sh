#!/bin/bash
# --- Session Start Hook: Skill Registry Builder -------------------
# https://github.com/damianpapadopoulos/auto-claude-skills
#
# Runs at SessionStart. Scans plugin cache and user skills, merges
# with default triggers, applies user config overrides, and caches
# the result as ~/.claude/.skill-registry-cache.json.
#
# Output format:
#   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}
#
# Bash 3.2 compatible (macOS default). No associative arrays.
# -----------------------------------------------------------------
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# -----------------------------------------------------------------
# Step 1: Run fix-plugin-manifests.sh (backwards compat)
# -----------------------------------------------------------------
FIX_SCRIPT="${PLUGIN_ROOT}/hooks/fix-plugin-manifests.sh"
if [ -f "${FIX_SCRIPT}" ]; then
    bash "${FIX_SCRIPT}" 2>/dev/null || true
fi

# -----------------------------------------------------------------
# Step 2: Check jq availability
# -----------------------------------------------------------------
CACHE_FILE="${HOME}/.claude/.skill-registry-cache.json"
mkdir -p "$(dirname "${CACHE_FILE}")"

if ! command -v jq >/dev/null 2>&1; then
    FALLBACK="${PLUGIN_ROOT}/config/fallback-registry.json"
    if [ -f "${FALLBACK}" ]; then
        cp "${FALLBACK}" "${CACHE_FILE}"
    else
        printf '{"version":"2.0.0-fallback","warnings":["jq not available, no fallback found"],"skills":[]}\n' > "${CACHE_FILE}"
    fi
    MSG="SessionStart: skill registry built (0 skills from 0 sources, 1 warnings)"
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "${MSG}"
    exit 0
fi

# -----------------------------------------------------------------
# Path constants
# -----------------------------------------------------------------
DEFAULT_TRIGGERS="${PLUGIN_ROOT}/config/default-triggers.json"
SP_BASE="${HOME}/.claude/plugins/cache/claude-plugins-official/superpowers"
PLUGIN_CACHE="${HOME}/.claude/plugins/cache/claude-plugins-official"
USER_SKILLS_DIR="${HOME}/.claude/skills"
USER_CONFIG="${HOME}/.claude/skill-config.json"

# -----------------------------------------------------------------
# Step 3: Discover superpowers plugin skills
# -----------------------------------------------------------------
SP_SKILLS_DIR=""
if [ -d "${SP_BASE}" ]; then
    SP_VERSION="$(ls -1 "${SP_BASE}" 2>/dev/null | sort -V | tail -1)"
    if [ -n "${SP_VERSION}" ]; then
        SP_SKILLS_DIR="${SP_BASE}/${SP_VERSION}/skills"
    fi
fi

# Build a list of discovered superpowers skill names and paths
# Format: name|invoke_path (one per line)
SP_DISCOVERED=""
if [ -n "${SP_SKILLS_DIR}" ] && [ -d "${SP_SKILLS_DIR}" ]; then
    for skill_md in "${SP_SKILLS_DIR}"/*/SKILL.md; do
        [ -f "${skill_md}" ] || continue
        skill_name="$(basename "$(dirname "${skill_md}")")"
        SP_DISCOVERED="${SP_DISCOVERED}${skill_name}|Read ${skill_md}
"
    done
fi

# -----------------------------------------------------------------
# Step 4: Discover official plugin skills
# -----------------------------------------------------------------
OFFICIAL_DISCOVERED=""

if [ -d "${PLUGIN_CACHE}/frontend-design" ]; then
    OFFICIAL_DISCOVERED="${OFFICIAL_DISCOVERED}frontend-design|Call Skill(frontend-design:frontend-design)
"
fi

if [ -d "${PLUGIN_CACHE}/claude-md-management" ]; then
    OFFICIAL_DISCOVERED="${OFFICIAL_DISCOVERED}claude-md-improver|Call Skill(claude-md-management:claude-md-improver)
"
fi

if [ -d "${PLUGIN_CACHE}/claude-code-setup" ]; then
    OFFICIAL_DISCOVERED="${OFFICIAL_DISCOVERED}claude-automation-recommender|Call Skill(claude-code-setup:claude-automation-recommender)
"
fi

# -----------------------------------------------------------------
# Step 5: Discover user-installed skills
# -----------------------------------------------------------------
USER_DISCOVERED=""
if [ -d "${USER_SKILLS_DIR}" ]; then
    for skill_md in "${USER_SKILLS_DIR}"/*/SKILL.md; do
        [ -f "${skill_md}" ] || continue
        skill_name="$(basename "$(dirname "${skill_md}")")"
        USER_DISCOVERED="${USER_DISCOVERED}${skill_name}|Read ${skill_md}
"
    done
fi

# -----------------------------------------------------------------
# Combine all discovered skills into one list
# -----------------------------------------------------------------
ALL_DISCOVERED="${SP_DISCOVERED}${OFFICIAL_DISCOVERED}${USER_DISCOVERED}"

# Count sources
SOURCE_COUNT=0
if [ -n "${SP_DISCOVERED}" ]; then SOURCE_COUNT=$((SOURCE_COUNT + 1)); fi
if [ -n "${OFFICIAL_DISCOVERED}" ]; then SOURCE_COUNT=$((SOURCE_COUNT + 1)); fi
if [ -n "${USER_DISCOVERED}" ]; then SOURCE_COUNT=$((SOURCE_COUNT + 1)); fi

# -----------------------------------------------------------------
# Step 6: Merge discovered skills with default-triggers.json
# -----------------------------------------------------------------
# Helper: check if a skill name is in the discovered list, return invoke path
lookup_discovered() {
    local name="$1"
    local line
    # Use printf to avoid issues with echo -n
    printf '%s' "${ALL_DISCOVERED}" | while IFS='|' read -r sname spath; do
        if [ "${sname}" = "${name}" ]; then
            printf '%s' "${spath}"
            return 0
        fi
    done
}

# Helper: check if a skill name exists in the defaults
is_in_defaults() {
    local name="$1"
    if [ -f "${DEFAULT_TRIGGERS}" ]; then
        jq -e --arg n "${name}" '.skills[] | select(.name == $n)' "${DEFAULT_TRIGGERS}" >/dev/null 2>&1
        return $?
    fi
    return 1
}

# Build skills JSON array using jq
# Start with default skills, overlay discovered paths
SKILLS_JSON="[]"

if [ -f "${DEFAULT_TRIGGERS}" ]; then
    # Process each default skill
    SKILL_COUNT="$(jq '.skills | length' "${DEFAULT_TRIGGERS}")"
    i=0
    while [ "${i}" -lt "${SKILL_COUNT}" ]; do
        skill_name="$(jq -r ".skills[${i}].name" "${DEFAULT_TRIGGERS}")"
        skill_json="$(jq ".skills[${i}]" "${DEFAULT_TRIGGERS}")"

        # Look up discovered invoke path
        invoke_path=""
        invoke_path="$(lookup_discovered "${skill_name}")"

        if [ -n "${invoke_path}" ]; then
            # Discovered: add invoke path and mark available
            skill_json="$(printf '%s' "${skill_json}" | jq --arg inv "${invoke_path}" '. + {invoke: $inv, available: true, enabled: true}')"
        else
            # Not discovered: mark unavailable
            skill_json="$(printf '%s' "${skill_json}" | jq '. + {available: false, enabled: true}')"
        fi

        SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --argjson s "${skill_json}" '. + [$s]')"
        i=$((i + 1))
    done
fi

# Add discovered skills not in defaults (custom/user skills).
# Pipe to tmp file to avoid subshell variable scoping issues.
printf '%s' "${ALL_DISCOVERED}" | while IFS='|' read -r sname spath; do
    [ -z "${sname}" ] && continue
    if ! is_in_defaults "${sname}"; then
        printf '%s|%s\n' "${sname}" "${spath}"
    fi
done > "${CACHE_FILE}.customs.tmp" 2>/dev/null || true

if [ -f "${CACHE_FILE}.customs.tmp" ]; then
    while IFS='|' read -r sname spath; do
        [ -z "${sname}" ] && continue
        custom_skill="$(jq -n --arg name "${sname}" --arg invoke "${spath}" '{
            name: $name,
            role: "domain",
            triggers: [],
            trigger_mode: "regex",
            priority: 200,
            precedes: [],
            requires: [],
            description: "User-installed skill",
            invoke: $invoke,
            available: true,
            enabled: true
        }')"
        SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --argjson s "${custom_skill}" '. + [$s]')"
    done < "${CACHE_FILE}.customs.tmp"
    rm -f "${CACHE_FILE}.customs.tmp"
fi

# -----------------------------------------------------------------
# Step 7: Apply user config overrides
# -----------------------------------------------------------------
WARNINGS="[]"

if [ -f "${USER_CONFIG}" ] && jq empty "${USER_CONFIG}" >/dev/null 2>&1; then
    # Process overrides
    override_keys="$(jq -r '.overrides // {} | keys[]' "${USER_CONFIG}" 2>/dev/null)" || true
    for skill_name in ${override_keys}; do
        [ -z "${skill_name}" ] && continue

        # Check if enabled: false
        has_enabled="$(jq -r --arg n "${skill_name}" 'if .overrides[$n] | has("enabled") then .overrides[$n].enabled | tostring else "unset" end' "${USER_CONFIG}" 2>/dev/null)"
        if [ "${has_enabled}" = "false" ]; then
            SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --arg n "${skill_name}" '
                [.[] | if .name == $n then .enabled = false else . end]
            ')"
        fi

        # Check for trigger overrides
        trigger_overrides="$(jq -r --arg n "${skill_name}" '.overrides[$n].triggers // empty | .[]' "${USER_CONFIG}" 2>/dev/null)" || true
        if [ -n "${trigger_overrides}" ]; then
            for trigger in ${trigger_overrides}; do
                case "${trigger}" in
                    +*)
                        # Add trigger
                        new_trigger="${trigger#+}"
                        SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --arg n "${skill_name}" --arg t "${new_trigger}" '
                            [.[] | if .name == $n then .triggers += [$t] else . end]
                        ')"
                        ;;
                    -*)
                        # Remove trigger
                        rem_trigger="${trigger#-}"
                        SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --arg n "${skill_name}" --arg t "${rem_trigger}" '
                            [.[] | if .name == $n then .triggers = [.triggers[] | select(. != $t)] else . end]
                        ')"
                        ;;
                    *)
                        # Replace triggers entirely
                        SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --arg n "${skill_name}" --arg t "${trigger}" '
                            [.[] | if .name == $n then .triggers = [$t] else . end]
                        ')"
                        ;;
                esac
            done
        fi
    done

    # Process custom_skills additions
    custom_count="$(jq '.custom_skills // [] | length' "${USER_CONFIG}" 2>/dev/null)" || custom_count=0
    ci=0
    while [ "${ci}" -lt "${custom_count}" ]; do
        custom_skill="$(jq ".custom_skills[${ci}]" "${USER_CONFIG}")"
        custom_skill="$(printf '%s' "${custom_skill}" | jq '. + {available: true, enabled: true}')"
        SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --argjson s "${custom_skill}" '. + [$s]')"
        ci=$((ci + 1))
    done
fi

# -----------------------------------------------------------------
# Step 8: Extract methodology_hints from default-triggers.json
# -----------------------------------------------------------------
METHODOLOGY_HINTS="[]"
if [ -f "${DEFAULT_TRIGGERS}" ]; then
    METHODOLOGY_HINTS="$(jq '.methodology_hints // []' "${DEFAULT_TRIGGERS}" 2>/dev/null)" || METHODOLOGY_HINTS="[]"
fi

# -----------------------------------------------------------------
# Step 9: Build final registry JSON
# -----------------------------------------------------------------
SKILL_COUNT="$(printf '%s' "${SKILLS_JSON}" | jq 'length' 2>/dev/null)" || SKILL_COUNT=0
WARNING_COUNT="$(printf '%s' "${WARNINGS}" | jq 'length' 2>/dev/null)" || WARNING_COUNT=0

REGISTRY="$(jq -n \
    --arg version "2.0.0" \
    --argjson skills "${SKILLS_JSON}" \
    --argjson methodology_hints "${METHODOLOGY_HINTS}" \
    --argjson warnings "${WARNINGS}" \
    '{
        version: $version,
        skills: $skills,
        methodology_hints: $methodology_hints,
        warnings: $warnings
    }'
)"

# -----------------------------------------------------------------
# Step 10: Cache to ~/.claude/.skill-registry-cache.json
# -----------------------------------------------------------------
printf '%s\n' "${REGISTRY}" > "${CACHE_FILE}"

# -----------------------------------------------------------------
# Step 11: Emit health check
# -----------------------------------------------------------------
MSG="SessionStart: skill registry built (${SKILL_COUNT} skills from ${SOURCE_COUNT} sources, ${WARNING_COUNT} warnings)"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "${MSG}"

exit 0
