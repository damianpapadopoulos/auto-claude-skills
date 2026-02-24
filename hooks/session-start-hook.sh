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
# Step 1b: Ensure cozempic is available (context protection)
# -----------------------------------------------------------------
if ! command -v cozempic >/dev/null 2>&1; then
    python3 -m pip install --quiet cozempic 2>/dev/null || true
    # Expand PATH to find newly installed binary
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
    command -v cozempic >/dev/null 2>&1 && cozempic init >/dev/null 2>&1 || true
fi

# -----------------------------------------------------------------
# Step 2: Check jq availability
# -----------------------------------------------------------------
CACHE_FILE="${HOME}/.claude/.skill-registry-cache.json"
mkdir -p "$(dirname "${CACHE_FILE}")"

if ! command -v jq >/dev/null 2>&1; then
    # Try to install jq (best-effort)
    if command -v brew >/dev/null 2>&1; then
        brew install --quiet jq 2>/dev/null || true
    elif command -v apt-get >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
        sudo apt-get install -y -qq jq 2>/dev/null || true
    fi
fi

if ! command -v jq >/dev/null 2>&1; then
    FALLBACK="${PLUGIN_ROOT}/config/fallback-registry.json"
    if [ -f "${FALLBACK}" ]; then
        cp "${FALLBACK}" "${CACHE_FILE}"
    else
        printf '{"version":"4.0.0-fallback","warnings":["jq not available, no fallback found"],"skills":[]}\n' > "${CACHE_FILE}"
    fi
    # NOTE: jq unavailable on this path; MSG must remain a simple ASCII string (no quotes or backslashes)
    MSG="SessionStart: jq not found -- skill routing disabled. Install jq: brew install jq (macOS) or apt install jq (Linux)"
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

# Read default triggers once into memory (avoid repeated file I/O)
DEFAULT_JSON=""
if [ -f "${DEFAULT_TRIGGERS}" ]; then
    DEFAULT_JSON="$(cat "${DEFAULT_TRIGGERS}")"
fi

# -----------------------------------------------------------------
# Step 3: Discover superpowers plugin skills
# -----------------------------------------------------------------
SP_SKILLS_DIR=""
if [ -d "${SP_BASE}" ]; then
    SP_VERSION="$(ls -1 "${SP_BASE}" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
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
        SP_DISCOVERED="${SP_DISCOVERED}${skill_name}|Skill(superpowers:${skill_name})
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
# Step 4b: Discover skills bundled with this plugin
# -----------------------------------------------------------------
PLUGIN_SKILLS_DIR="${PLUGIN_ROOT}/skills"
PLUGIN_DISCOVERED=""
if [ -d "${PLUGIN_SKILLS_DIR}" ]; then
    for skill_md in "${PLUGIN_SKILLS_DIR}"/*/SKILL.md; do
        [ -f "${skill_md}" ] || continue
        skill_name="$(basename "$(dirname "${skill_md}")")"
        PLUGIN_DISCOVERED="${PLUGIN_DISCOVERED}${skill_name}|Skill(auto-claude-skills:${skill_name})
"
    done
fi

# -----------------------------------------------------------------
# Step 5: Discover user-installed skills
# Skip any that share a name with plugin-bundled skills (avoid dupes)
# -----------------------------------------------------------------
USER_DISCOVERED=""
if [ -d "${USER_SKILLS_DIR}" ]; then
    for skill_md in "${USER_SKILLS_DIR}"/*/SKILL.md; do
        [ -f "${skill_md}" ] || continue
        skill_name="$(basename "$(dirname "${skill_md}")")"
        # Skip if already discovered as a plugin-bundled skill
        if printf '%s' "${PLUGIN_DISCOVERED}" | grep -q "^${skill_name}|"; then
            continue
        fi
        USER_DISCOVERED="${USER_DISCOVERED}${skill_name}|Skill(${skill_name})
"
    done
fi

# -----------------------------------------------------------------
# Combine all discovered skills into one list
# -----------------------------------------------------------------
ALL_DISCOVERED="${SP_DISCOVERED}${OFFICIAL_DISCOVERED}${PLUGIN_DISCOVERED}${USER_DISCOVERED}"

# Count sources
SOURCE_COUNT=0
if [ -n "${SP_DISCOVERED}" ]; then SOURCE_COUNT=$((SOURCE_COUNT + 1)); fi
if [ -n "${OFFICIAL_DISCOVERED}" ]; then SOURCE_COUNT=$((SOURCE_COUNT + 1)); fi
if [ -n "${PLUGIN_DISCOVERED}" ]; then SOURCE_COUNT=$((SOURCE_COUNT + 1)); fi
if [ -n "${USER_DISCOVERED}" ]; then SOURCE_COUNT=$((SOURCE_COUNT + 1)); fi

# -----------------------------------------------------------------
# Step 6: Merge discovered skills with default-triggers.json
# -----------------------------------------------------------------
# Build invoke map from ALL_DISCOVERED as a JSON object {"name":"invoke_path",...}
# Single jq call instead of per-skill lookups
if [ -n "${ALL_DISCOVERED}" ]; then
    INVOKE_MAP="$(printf '%s' "${ALL_DISCOVERED}" | while IFS='|' read -r _n _p; do
        [ -z "${_n}" ] && continue
        printf '%s\n%s\n' "${_n}" "${_p}"
    done | jq -Rn '[inputs] | [range(0; length; 2) as $i | {(.[($i)]): .[($i)+1]}] | add // {}')"
else
    INVOKE_MAP="{}"
fi

# Merge defaults + invoke map in a SINGLE jq call (replaces ~80 forks)
if [ -n "${DEFAULT_JSON}" ]; then
    SKILLS_JSON="$(printf '%s' "${DEFAULT_JSON}" | jq --argjson imap "${INVOKE_MAP}" '
        [.skills[] | . + (
            if $imap[.name] then
                {invoke: $imap[.name], available: true, enabled: true}
            else
                {available: false, enabled: true}
            end
        )]
    ')"
else
    SKILLS_JSON="[]"
fi

# Extract default skill names once for custom-skill detection
DEFAULT_NAMES=""
if [ -n "${DEFAULT_JSON}" ]; then
    DEFAULT_NAMES="$(printf '%s' "${DEFAULT_JSON}" | jq -r '.skills[].name')"
fi

# Collect custom skills (discovered but not in defaults) and batch-append
# Build newline-delimited name|path pairs, then create all custom entries in one jq call
CUSTOMS_INPUT=""
printf '%s' "${ALL_DISCOVERED}" | while IFS='|' read -r sname spath; do
    [ -z "${sname}" ] && continue
    # Check if name is in defaults using bash string matching
    _found=0
    while IFS= read -r _dn; do
        [ -z "${_dn}" ] && continue
        if [ "${_dn}" = "${sname}" ]; then
            _found=1
            break
        fi
    done <<DNAMES
${DEFAULT_NAMES}
DNAMES
    if [ "${_found}" -eq 0 ]; then
        printf '%s\n%s\n' "${sname}" "${spath}"
    fi
done > "${CACHE_FILE}.customs.$$" 2>/dev/null || true

if [ -f "${CACHE_FILE}.customs.$$" ] && [ -s "${CACHE_FILE}.customs.$$" ]; then
    CUSTOMS_JSON="$(jq -Rn '[inputs] | [range(0; length; 2) as $i | {
        name: .[($i)],
        role: "domain",
        triggers: [],
        trigger_mode: "regex",
        priority: 200,
        precedes: [],
        requires: [],
        description: "User-installed skill",
        invoke: .[($i)+1],
        available: true,
        enabled: true
    }]' < "${CACHE_FILE}.customs.$$")"
    SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --argjson c "${CUSTOMS_JSON}" '. + $c')"
fi
rm -f "${CACHE_FILE}.customs.$$"

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
            # Collect plain triggers (replace-all) separately to apply in one batch
            replace_triggers=""
            while IFS= read -r trigger; do
                [ -z "${trigger}" ] && continue
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
                        # Collect plain triggers for batch replacement
                        if [ -z "${replace_triggers}" ]; then
                            replace_triggers="${trigger}"
                        else
                            replace_triggers="${replace_triggers}
${trigger}"
                        fi
                        ;;
                esac
            done <<TEOF
${trigger_overrides}
TEOF
            # Apply all plain triggers as a single replacement
            if [ -n "${replace_triggers}" ]; then
                replace_json="$(printf '%s\n' "${replace_triggers}" | jq -R . | jq -s .)"
                if [ -n "${replace_json}" ] && printf '%s' "${replace_json}" | jq empty >/dev/null 2>&1; then
                    SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --arg n "${skill_name}" --argjson t "${replace_json}" '
                        [.[] | if .name == $n then .triggers = $t else . end]
                    ')"
                else
                    WARNINGS="$(printf '%s' "${WARNINGS}" | jq --arg w "Failed to parse trigger overrides for ${skill_name}" '. + [$w]')"
                fi
            fi
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
if [ -n "${DEFAULT_JSON}" ]; then
    _meta="$(printf '%s' "${DEFAULT_JSON}" | jq -r -j '
        (.methodology_hints // [] | tojson),
        "\u001f",
        (.phase_compositions // {} | tojson),
        "\u001f",
        (.phase_guide // {} | tojson)
    ')"
    METHODOLOGY_HINTS="${_meta%%$'\x1f'*}"; _meta="${_meta#*$'\x1f'}"
    PHASE_COMPOSITIONS="${_meta%%$'\x1f'*}"
    PHASE_GUIDE="${_meta#*$'\x1f'}"
else
    METHODOLOGY_HINTS="[]"
    PHASE_COMPOSITIONS="{}"
    PHASE_GUIDE="{}"
fi

# -----------------------------------------------------------------
# Step 8b: Discover curated plugins from default-triggers.json
# -----------------------------------------------------------------
PLUGINS_JSON="[]"
if [ -n "${DEFAULT_JSON}" ]; then
    CURATED_COUNT="$(printf '%s' "${DEFAULT_JSON}" | jq '.plugins // [] | length' 2>/dev/null)" || CURATED_COUNT=0
    pi=0
    while [ "${pi}" -lt "${CURATED_COUNT}" ]; do
        plugin_name="$(printf '%s' "${DEFAULT_JSON}" | jq -r ".plugins[${pi}].name")"
        plugin_json="$(printf '%s' "${DEFAULT_JSON}" | jq ".plugins[${pi}]")"

        # Check if installed in any marketplace cache dir
        _installed=false
        for _mkt_dir in "${HOME}/.claude/plugins/cache"/*/; do
            [ -d "${_mkt_dir}" ] || continue
            if [ -d "${_mkt_dir}${plugin_name}" ]; then
                _installed=true
                break
            fi
        done

        plugin_json="$(printf '%s' "${plugin_json}" | jq --argjson avail "${_installed}" '. + {available: $avail}')"
        PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq --argjson p "${plugin_json}" '. + [$p]')"

        pi=$((pi + 1))
    done
fi

# -----------------------------------------------------------------
# Step 8c: Auto-discover unknown plugins from all marketplaces
# -----------------------------------------------------------------
# Build list of curated plugin names for exclusion
CURATED_NAMES="$(printf '%s' "${PLUGINS_JSON}" | jq -r '.[].name' 2>/dev/null)"
# Also exclude plugins we already handle as skill sources
KNOWN_NAMES="${CURATED_NAMES}
superpowers
frontend-design
claude-md-management
claude-code-setup
pr-review-toolkit
ralph-loop
auto-claude-skills"

for _mkt_dir in "${HOME}/.claude/plugins/cache"/*/; do
    [ -d "${_mkt_dir}" ] || continue
    for _plugin_dir in "${_mkt_dir}"*/; do
        [ -d "${_plugin_dir}" ] || continue
        _pname="$(basename "${_plugin_dir}")"

        # Skip known/curated plugins
        _skip=0
        while IFS= read -r _kn; do
            [ -z "${_kn}" ] && continue
            if [ "${_kn}" = "${_pname}" ]; then
                _skip=1
                break
            fi
        done <<KNEOF
${KNOWN_NAMES}
KNEOF
        [ "${_skip}" -eq 1 ] && continue

        # Look for plugin.json — may be directly in plugin dir or in a version subdir
        _pjson=""
        _plugin_root=""
        if [ -f "${_plugin_dir}.claude-plugin/plugin.json" ]; then
            _pjson="${_plugin_dir}.claude-plugin/plugin.json"
            _plugin_root="${_plugin_dir}"
        else
            for _vdir in "${_plugin_dir}"*/; do
                [ -d "${_vdir}" ] || continue
                if [ -f "${_vdir}.claude-plugin/plugin.json" ]; then
                    _pjson="${_vdir}.claude-plugin/plugin.json"
                    _plugin_root="${_vdir}"
                    break
                fi
            done
        fi
        [ -z "${_pjson}" ] && continue

        # Scan for skills
        _skills="[]"
        if [ -d "${_plugin_root}skills" ]; then
            for _smd in "${_plugin_root}skills"/*/SKILL.md; do
                [ -f "${_smd}" ] || continue
                _sname="$(basename "$(dirname "${_smd}")")"
                _skills="$(printf '%s' "${_skills}" | jq --arg s "${_sname}" '. + [$s]')"
            done
        fi

        # Scan for commands
        _commands="[]"
        if [ -d "${_plugin_root}commands" ]; then
            for _cmd in "${_plugin_root}commands"/*.md; do
                [ -f "${_cmd}" ] || continue
                _cname="/$(basename "${_cmd}" .md)"
                _commands="$(printf '%s' "${_commands}" | jq --arg c "${_cname}" '. + [$c]')"
            done
        fi

        # Scan for agents
        _agents="[]"
        if [ -d "${_plugin_root}agents" ]; then
            for _agent in "${_plugin_root}agents"/*.md; do
                [ -f "${_agent}" ] || continue
                _aname="$(basename "${_agent}" .md)"
                _agents="$(printf '%s' "${_agents}" | jq --arg a "${_aname}" '. + [$a]')"
            done
        fi

        # Build plugin entry
        _entry="$(jq -n \
            --arg name "${_pname}" \
            --arg source "auto-discovered" \
            --argjson skills "${_skills}" \
            --argjson commands "${_commands}" \
            --argjson agents "${_agents}" \
            '{
                name: $name,
                source: $source,
                provides: {commands: $commands, skills: $skills, agents: $agents, hooks: []},
                phase_fit: ["*"],
                description: "Auto-discovered plugin",
                available: true
            }')"
        PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq --argjson p "${_entry}" '. + [$p]')"
    done
done

# -----------------------------------------------------------------
# Step 9: Build final registry JSON
# -----------------------------------------------------------------
SKILL_COUNT="$(printf '%s' "${SKILLS_JSON}" | jq 'length' 2>/dev/null)" || SKILL_COUNT=0
AVAILABLE_COUNT="$(printf '%s' "${SKILLS_JSON}" | jq '[.[] | select(.available == true)] | length' 2>/dev/null)" || AVAILABLE_COUNT=0
UNAVAILABLE_COUNT=$((SKILL_COUNT - AVAILABLE_COUNT))
WARNING_COUNT="$(printf '%s' "${WARNINGS}" | jq 'length' 2>/dev/null)" || WARNING_COUNT=0

REGISTRY="$(jq -n \
    --arg version "4.0.0" \
    --argjson skills "${SKILLS_JSON}" \
    --argjson plugins "${PLUGINS_JSON}" \
    --argjson phase_compositions "${PHASE_COMPOSITIONS}" \
    --argjson phase_guide "${PHASE_GUIDE}" \
    --argjson methodology_hints "${METHODOLOGY_HINTS}" \
    --argjson warnings "${WARNINGS}" \
    '{
        version: $version,
        skills: $skills,
        plugins: $plugins,
        phase_compositions: $phase_compositions,
        phase_guide: $phase_guide,
        methodology_hints: $methodology_hints,
        warnings: $warnings
    }'
)"

# -----------------------------------------------------------------
# Step 10: Cache to ~/.claude/.skill-registry-cache.json
# -----------------------------------------------------------------
printf '%s\n' "${REGISTRY}" > "${CACHE_FILE}"

# -----------------------------------------------------------------
# Step 11: Detect missing companion plugins and features
# -----------------------------------------------------------------
MISSING_PLUGINS=""
MISSING_COUNT=0

# Check companion plugins
for _plugin in superpowers frontend-design claude-md-management pr-review-toolkit claude-code-setup commit-commands security-guidance hookify feature-dev code-review code-simplifier skill-creator; do
    _found=0
    case "${_plugin}" in
        superpowers)
            if [ -d "${HOME}/.claude/plugins/cache/claude-plugins-official/superpowers" ] || \
               [ -d "${HOME}/.claude/plugins/cache/superpowers-marketplace/superpowers" ]; then
                _found=1
            fi
            ;;
        *)
            [ -d "${HOME}/.claude/plugins/cache/claude-plugins-official/${_plugin}" ] && _found=1
            ;;
    esac
    if [ "${_found}" -eq 0 ]; then
        if [ -n "${MISSING_PLUGINS}" ]; then
            MISSING_PLUGINS="${MISSING_PLUGINS}, ${_plugin}"
        else
            MISSING_PLUGINS="${_plugin}"
        fi
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done

# Check agent teams
AGENT_TEAMS_MISSING=0
if [ -f "${HOME}/.claude/settings.json" ]; then
    _at_val="$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // ""' "${HOME}/.claude/settings.json" 2>/dev/null)"
    [ "${_at_val}" != "1" ] && AGENT_TEAMS_MISSING=1
else
    AGENT_TEAMS_MISSING=1
fi

# Build setup hints
SETUP_HINTS=""
if [ "${MISSING_COUNT}" -gt 0 ]; then
    SETUP_HINTS="\\nTip: ${MISSING_COUNT} companion plugin(s) not installed (${MISSING_PLUGINS}). Run /setup to install."
fi
if [ "${UNAVAILABLE_COUNT}" -gt 0 ] && [ "${MISSING_COUNT}" -eq 0 ]; then
    SETUP_HINTS="\\nTip: ${UNAVAILABLE_COUNT} skill(s) unavailable (missing plugins or user skills). Run /setup to install."
fi
if [ "${AGENT_TEAMS_MISSING}" -eq 1 ]; then
    SETUP_HINTS="${SETUP_HINTS}\\nTip: Agent teams not enabled. Run /setup to configure."
fi

# -----------------------------------------------------------------
# Step 12: Emit health check
# -----------------------------------------------------------------
PLUGIN_COUNT="$(printf '%s' "${PLUGINS_JSON}" | jq 'length' 2>/dev/null)" || PLUGIN_COUNT=0
PLUGIN_AVAILABLE="$(printf '%s' "${PLUGINS_JSON}" | jq '[.[] | select(.available == true)] | length' 2>/dev/null)" || PLUGIN_AVAILABLE=0

MSG="SessionStart: skill registry built (${SKILL_COUNT} skills, ${AVAILABLE_COUNT} available, from ${SOURCE_COUNT} sources, ${PLUGIN_COUNT} plugins (${PLUGIN_AVAILABLE} installed), ${WARNING_COUNT} warnings)${SETUP_HINTS}"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
    "$(printf '%s' "${MSG}" | jq -Rs .)"

exit 0
