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
    # Check common install locations before warning
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
fi
if command -v cozempic >/dev/null 2>&1; then
    cozempic init >/dev/null 2>&1 || true
else
    printf '[session-start] cozempic not found. Install with: pip install cozempic\n' >&2
fi

# -----------------------------------------------------------------
# Step 1c: Reset depth counter for new session
# -----------------------------------------------------------------
# Generate a session-scoped token so concurrent sessions don't share counters.
# Clean up stale counter files from previous sessions first.
_SESSION_TOKEN="$(date +%s)-$$"
printf '%s' "$_SESSION_TOKEN" > "${HOME}/.claude/.skill-session-token" 2>/dev/null || true
# Read previous session's zero-match stats before cleanup
_PREV_ZM=0
_PREV_TOTAL=0
[[ -f "${HOME}/.claude/.skill-zero-match-count" ]] && _PREV_ZM="$(cat "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null)"
[[ "$_PREV_ZM" =~ ^[0-9]+$ ]] || _PREV_ZM=0
# Sum all prompt counters from previous session
for _pcf in "${HOME}/.claude/.skill-prompt-count-"*; do
    [[ -f "$_pcf" ]] || continue
    _pc="$(cat "$_pcf" 2>/dev/null)"
    [[ "$_pc" =~ ^[0-9]+$ ]] && _PREV_TOTAL=$((_PREV_TOTAL + _pc))
done
rm -f "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null || true
rm -f "${HOME}/.claude/.skill-prompt-count-"* 2>/dev/null || true
printf '0' > "${HOME}/.claude/.skill-prompt-count-${_SESSION_TOKEN}" 2>/dev/null || true

# -----------------------------------------------------------------
# Step 2: Check jq availability
# -----------------------------------------------------------------
CACHE_FILE="${HOME}/.claude/.skill-registry-cache.json"
mkdir -p "$(dirname "${CACHE_FILE}")"

if ! command -v jq >/dev/null 2>&1; then
    printf '[session-start] jq not found. Install with: brew install jq (macOS) or apt install jq (Linux)\n' >&2
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
# Official plugin directory -> skill-name|invoke-path mapping
# Format: dir_name|skill_name|plugin:skill_invoke (one per line)
OFFICIAL_PLUGIN_MAP="frontend-design|frontend-design|frontend-design:frontend-design
claude-md-management|claude-md-improver|claude-md-management:claude-md-improver
claude-code-setup|claude-automation-recommender|claude-code-setup:claude-automation-recommender"

OFFICIAL_DISCOVERED=""
while IFS='|' read -r _dir _skill _invoke; do
    [ -z "${_dir}" ] && continue
    if [ -d "${PLUGIN_CACHE}/${_dir}" ]; then
        OFFICIAL_DISCOVERED="${OFFICIAL_DISCOVERED}${_skill}|Call Skill(${_invoke})
"
    fi
done <<OPEOF
${OFFICIAL_PLUGIN_MAP}
OPEOF

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
# Step 7: Apply user config overrides (single jq call)
# -----------------------------------------------------------------
WARNINGS="[]"

if [ -f "${USER_CONFIG}" ] && jq empty "${USER_CONFIG}" >/dev/null 2>&1; then
    USER_CONFIG_JSON="$(cat "${USER_CONFIG}")"
    SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --argjson cfg "$(printf '%s' "${USER_CONFIG_JSON}")" '
        # Process overrides
        ($cfg.overrides // {}) as $overrides |
        [.[] | . as $skill |
            if $overrides[$skill.name] then
                ($overrides[$skill.name]) as $ovr |
                (if $ovr | has("enabled") then {enabled: $ovr.enabled} else {} end) as $enable |
                (if $ovr.triggers then
                    ($ovr.triggers | map(select(startswith("+"))) | map(ltrimstr("+"))) as $add |
                    ($ovr.triggers | map(select(startswith("-"))) | map(ltrimstr("-"))) as $rem |
                    ($ovr.triggers | map(select((startswith("+") or startswith("-")) | not))) as $replace |
                    if ($replace | length) > 0 then {triggers: $replace}
                    else {triggers: ((.triggers + $add) | [.[] | select(. as $t | $rem | any(. == $t) | not)])}
                    end
                else {} end) as $trigs |
                . + $enable + $trigs
            else . end
        ] +
        [($cfg.custom_skills // [])[] | . + {available: true, enabled: true}]
    ')"
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
    # 1) Get all curated plugin names in one jq call
    _curated_names="$(printf '%s' "${DEFAULT_JSON}" | jq -r '.plugins // [] | .[].name')"

    # 2) Check installation bash-side — iterate names, check dirs
    _installed_names=""
    while IFS= read -r _cn; do
        [ -z "${_cn}" ] && continue
        for _mkt_dir in "${HOME}/.claude/plugins/cache"/*/; do
            [ -d "${_mkt_dir}" ] || continue
            if [ -d "${_mkt_dir}${_cn}" ]; then
                _installed_names="${_installed_names}${_cn}
"
                break
            fi
        done
    done <<CURATED_EOF
${_curated_names}
CURATED_EOF

    # 3) Single jq call — produce full PLUGINS_JSON with available flag
    PLUGINS_JSON="$(printf '%s' "${DEFAULT_JSON}" | jq --arg installed "${_installed_names}" '
        ($installed | split("\n") | map(select(. != ""))) as $inst |
        [.plugins // [] | .[] | .name as $n | . + {available: ([$inst[] | select(. == $n)] | length > 0)}]
    ')"
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

# Collect all unknown plugin data bash-side, then merge in one jq call
_DISCOVERED_ENTRIES=""
_ENTRY_DELIM="@@ENTRY@@"
_FIELD_DELIM="@@F@@"

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

        # Collect skill names as newline-separated string (no jq per item)
        _skill_names=""
        if [ -d "${_plugin_root}skills" ]; then
            for _smd in "${_plugin_root}skills"/*/SKILL.md; do
                [ -f "${_smd}" ] || continue
                _skill_names="${_skill_names}$(basename "$(dirname "${_smd}")")
"
            done
        fi

        # Collect command names with "/" prefix bash-side (no jq per item)
        _cmd_names=""
        if [ -d "${_plugin_root}commands" ]; then
            for _cmd in "${_plugin_root}commands"/*.md; do
                [ -f "${_cmd}" ] || continue
                _cmd_names="${_cmd_names}/$(basename "${_cmd}" .md)
"
            done
        fi

        # Collect agent names as newline-separated string (no jq per item)
        _agent_names=""
        if [ -d "${_plugin_root}agents" ]; then
            for _agent in "${_plugin_root}agents"/*.md; do
                [ -f "${_agent}" ] || continue
                _agent_names="${_agent_names}$(basename "${_agent}" .md)
"
            done
        fi

        # Accumulate entry as delimited string (no jq fork)
        _DISCOVERED_ENTRIES="${_DISCOVERED_ENTRIES}${_DISCOVERED_ENTRIES:+${_ENTRY_DELIM}}${_pname}${_FIELD_DELIM}${_skill_names}${_FIELD_DELIM}${_cmd_names}${_FIELD_DELIM}${_agent_names}"
    done
done

# Single jq call to merge all discovered plugins into PLUGINS_JSON
if [ -n "${_DISCOVERED_ENTRIES}" ]; then
    PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq \
        --arg entries "${_DISCOVERED_ENTRIES}" \
        --arg edelim "${_ENTRY_DELIM}" \
        --arg fdelim "${_FIELD_DELIM}" \
        '. + [
            $entries | split($edelim)[] |
            split($fdelim) as $f |
            {
                name: $f[0],
                source: "auto-discovered",
                provides: {
                    commands: ($f[2] | split("\n") | map(select(. != ""))),
                    skills:  ($f[1] | split("\n") | map(select(. != ""))),
                    agents:  ($f[3] | split("\n") | map(select(. != ""))),
                    hooks: []
                },
                phase_fit: ["*"],
                description: "Auto-discovered plugin",
                available: true
            }
        ]')"
fi

# -----------------------------------------------------------------
# Step 8d: Detect context stack capabilities
# -----------------------------------------------------------------
# Check which tools in the Unified Context Stack are available.
# Results written to registry as context_capabilities object.

# Context Hub CLI: check PATH (bash-side, before single jq call)
_has_chub_cli=false
if command -v chub >/dev/null 2>&1; then
    _has_chub_cli=true
fi

# Single jq call: detect all plugin capabilities, derive bindings, build CONTEXT_CAPS
# (Context7 detection checks plugin name, not MCP tool names. Covers the standard
# install path via claude-plugins-official. If Context7 were ever provided by a
# differently-named plugin, this would need MCP tool detection instead.)
CONTEXT_CAPS="$(printf '%s' "${PLUGINS_JSON}" | jq \
    --argjson chub "${_has_chub_cli}" \
    '[.[] | select(.available == true) | .name] as $avail |
    ($avail | index("context7") != null) as $c7 |
    ($avail | index("serena") != null) as $ser |
    ($avail | index("forgetful") != null) as $fm |
    {context7:$c7, context_hub_cli:$chub, context_hub_indexed:$c7, serena:$ser, forgetful_memory:$fm}'
)"

# Override unified-context-stack plugin available flag when any capability is present
if printf '%s' "${CONTEXT_CAPS}" | jq -e 'to_entries | any(.value == true)' >/dev/null 2>&1; then
    PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq '
        map(if .name == "unified-context-stack" then .available = true else . end)
    ')"
fi

# -----------------------------------------------------------------
# Step 9+10: Build final registry JSON, extract stats, and cache
# -----------------------------------------------------------------
RESULT="$(jq -n \
    --arg version "4.0.0" \
    --argjson skills "${SKILLS_JSON}" \
    --argjson plugins "${PLUGINS_JSON}" \
    --argjson caps "${CONTEXT_CAPS}" \
    --argjson pc "${PHASE_COMPOSITIONS}" \
    --argjson pg "${PHASE_GUIDE}" \
    --argjson mh "${METHODOLOGY_HINTS}" \
    --argjson warnings "${WARNINGS}" \
    '{
        registry: {version:$version, skills:$skills, plugins:$plugins, context_capabilities:$caps,
                   phase_compositions:$pc, phase_guide:$pg,
                   methodology_hints:$mh, warnings:$warnings},
        stats: {
            skill_count: ($skills | length),
            available: ([$skills[] | select(.available)] | length),
            warning_count: ($warnings | length),
            plugin_count: ($plugins | length),
            plugin_available: ([$plugins[] | select(.available)] | length)
        }
    }')"

# Write registry to cache (strip the stats wrapper)
printf '%s' "${RESULT}" | jq '.registry' > "${CACHE_FILE}"

# Extract stats for health message
read -r SKILL_COUNT AVAILABLE_COUNT WARNING_COUNT PLUGIN_COUNT PLUGIN_AVAILABLE <<EOF
$(printf '%s' "${RESULT}" | jq -r '.stats | "\(.skill_count) \(.available) \(.warning_count) \(.plugin_count) \(.plugin_available)"')
EOF
UNAVAILABLE_COUNT=$((SKILL_COUNT - AVAILABLE_COUNT))

# -----------------------------------------------------------------
# Step 11: Detect missing companion plugins, MCPs, skills, and features
# -----------------------------------------------------------------

# Helper: check if a plugin is installed in any marketplace cache
_plugin_installed() {
    local _name="$1"
    case "${_name}" in
        superpowers)
            [ -d "${HOME}/.claude/plugins/cache/claude-plugins-official/superpowers" ] || \
            [ -d "${HOME}/.claude/plugins/cache/superpowers-marketplace/superpowers" ]
            ;;
        *)
            [ -d "${HOME}/.claude/plugins/cache/claude-plugins-official/${_name}" ]
            ;;
    esac
}

# Core plugins (essential for the SDLC loop)
MISSING_CORE=""
MISSING_CORE_COUNT=0
for _plugin in superpowers frontend-design claude-md-management claude-code-setup pr-review-toolkit; do
    if ! _plugin_installed "${_plugin}"; then
        MISSING_CORE="${MISSING_CORE:+${MISSING_CORE}, }${_plugin}"
        MISSING_CORE_COUNT=$((MISSING_CORE_COUNT + 1))
    fi
done

# MCP plugins (SDLC data sources — live docs, GitHub, Atlassian)
# Note: Atlassian may be available as a claude.ai managed integration
# (mcp__claude_ai_Atlassian__) without a marketplace install.
MISSING_MCP=""
MISSING_MCP_COUNT=0
for _plugin in context7 github; do
    if ! _plugin_installed "${_plugin}"; then
        MISSING_MCP="${MISSING_MCP:+${MISSING_MCP}, }${_plugin}"
        MISSING_MCP_COUNT=$((MISSING_MCP_COUNT + 1))
    fi
done

# Phase enhancer plugins (improve specific SDLC phases)
MISSING_ENHANCERS=""
MISSING_ENHANCERS_COUNT=0
for _plugin in commit-commands security-guidance feature-dev hookify skill-creator; do
    if ! _plugin_installed "${_plugin}"; then
        MISSING_ENHANCERS="${MISSING_ENHANCERS:+${MISSING_ENHANCERS}, }${_plugin}"
        MISSING_ENHANCERS_COUNT=$((MISSING_ENHANCERS_COUNT + 1))
    fi
done

# Recommended skills (external)
MISSING_SKILLS=""
MISSING_SKILLS_COUNT=0
for _skill in doc-coauthoring webapp-testing security-scanner; do
    if [ ! -f "${HOME}/.claude/skills/${_skill}/SKILL.md" ]; then
        MISSING_SKILLS="${MISSING_SKILLS:+${MISSING_SKILLS}, }${_skill}"
        MISSING_SKILLS_COUNT=$((MISSING_SKILLS_COUNT + 1))
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

# Count total and installed companion plugins (core + MCP + enhancers)
TOTAL_COMPANIONS=12  # 5 core + 2 MCP + 5 enhancers
MISSING_COMPANION_COUNT=$((MISSING_CORE_COUNT + MISSING_MCP_COUNT + MISSING_ENHANCERS_COUNT))
INSTALLED_COMPANIONS=$((TOTAL_COMPANIONS - MISSING_COMPANION_COUNT))

# -----------------------------------------------------------------
# Step 12: Emit health check
# -----------------------------------------------------------------
SETUP_CTA=""
if [ "${MISSING_COMPANION_COUNT}" -gt 0 ] || [ "${MISSING_SKILLS_COUNT}" -gt 0 ] || [ "${AGENT_TEAMS_MISSING}" -eq 1 ]; then
    SETUP_CTA=". Run /setup for the full experience"
else
    SETUP_CTA=". Setup complete"
fi
_ZM_STAT=""
if [[ "$_PREV_TOTAL" -gt 10 ]] && [[ "$_PREV_ZM" -gt 0 ]]; then
    _ZM_STAT=" | prev: ${_PREV_ZM}/${_PREV_TOTAL} unmatched"
fi
STATUS="SessionStart: ${AVAILABLE_COUNT} skills active (${INSTALLED_COMPANIONS} of ${TOTAL_COMPANIONS} plugins)${_ZM_STAT}${SETUP_CTA}"

# Build model context: status + first-response instruction + any warnings
CONTEXT="${STATUS}
MANDATORY: Before any other output, report the skill system status to the user in one line (e.g. '24 skills active across 7 plugins — run /setup to complete installation'). Do not skip or defer this."

# Append context capabilities summary for model consumption
# CONTEXT_CAPS is always set on the jq-available path (jq-unavailable exits at step 2)
_CAP_LINE="$(printf '%s' "${CONTEXT_CAPS}" | jq -r 'to_entries | map("\(.key)=\(.value)") | "Context Stack: " + join(", ")')"
if [ -n "${_CAP_LINE}" ]; then
    CONTEXT="${CONTEXT}
${_CAP_LINE}"
fi

if [ "${WARNING_COUNT}" -gt 0 ]; then
    CONTEXT="${CONTEXT}
Warnings: $(printf '%s' "${WARNINGS}" | jq -r '.[]')"
fi

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
    "$(printf '%s' "${CONTEXT}" | jq -Rs .)"

exit 0
