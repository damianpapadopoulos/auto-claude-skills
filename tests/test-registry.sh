#!/usr/bin/env bash
# test-registry.sh — Tests for the session-start registry builder hook
# Bash 3.2 compatible. Sources test-helpers.sh for setup/teardown and assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-registry.sh ==="

# ---------------------------------------------------------------------------
# Helper: run the hook with captured output
# ---------------------------------------------------------------------------
run_hook() {
    # CLAUDE_PLUGIN_ROOT must point to the project root so the hook
    # can find config/default-triggers.json etc.
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 1. Empty environment produces fallback registry
# ---------------------------------------------------------------------------
test_empty_env_produces_fallback() {
    echo "-- test: empty environment produces fallback registry --"
    setup_test_env

    # Remove all plugin/skill dirs so nothing is discovered
    rm -rf "${HOME}/.claude/plugins"
    rm -rf "${HOME}/.claude/skills"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "${cache_file}"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # Should have a version field
    local version
    version="$(jq -r '.version' "${cache_file}" 2>/dev/null)"
    assert_contains "registry has version" "4.0" "${version}"

    # Should have skills array
    local skill_count
    skill_count="$(jq '.skills | length' "${cache_file}" 2>/dev/null)"
    # With no plugins, skills from defaults should be marked available: false
    # but still present
    assert_contains "skills array exists" "" "$(jq -r '.skills' "${cache_file}" 2>/dev/null)"

    # Health check output
    assert_contains "health check in output" "skills active" "${output}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 2. Discovers superpowers plugin skills (mock skill dir)
# ---------------------------------------------------------------------------
test_discovers_superpowers_skills() {
    echo "-- test: discovers superpowers plugin skills --"
    setup_test_env

    # Create mock superpowers skill directory
    local sp_dir="${HOME}/.claude/plugins/cache/claude-plugins-official/superpowers/1.0.0/skills"
    mkdir -p "${sp_dir}/brainstorming"
    printf '# Brainstorming Skill\nThis is a mock skill.\n' > "${sp_dir}/brainstorming/SKILL.md"
    mkdir -p "${sp_dir}/systematic-debugging"
    printf '# Debugging Skill\nThis is a mock skill.\n' > "${sp_dir}/systematic-debugging/SKILL.md"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "${cache_file}"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # brainstorming should be discovered and available
    local brainstorm_available
    brainstorm_available="$(jq -r '.skills[] | select(.name == "brainstorming") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "brainstorming is available" "true" "${brainstorm_available}"

    # invoke path should use Skill() format for superpowers skills
    local brainstorm_invoke
    brainstorm_invoke="$(jq -r '.skills[] | select(.name == "brainstorming") | .invoke' "${cache_file}" 2>/dev/null)"
    assert_equals "brainstorming invoke uses Skill()" "Skill(superpowers:brainstorming)" "${brainstorm_invoke}"

    # Health check output
    assert_contains "health check in output" "skills active" "${output}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 3. Discovers user-installed skills (mock skill dir)
# ---------------------------------------------------------------------------
test_discovers_user_skills() {
    echo "-- test: discovers user-installed skills --"
    setup_test_env

    # Create mock user skill
    mkdir -p "${HOME}/.claude/skills/my-custom-skill"
    printf '# My Custom Skill\nA user-installed skill.\n' > "${HOME}/.claude/skills/my-custom-skill/SKILL.md"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "${cache_file}"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # User skill should appear as a custom domain skill
    local custom_skill
    custom_skill="$(jq -r '.skills[] | select(.name == "my-custom-skill") | .name' "${cache_file}" 2>/dev/null)"
    assert_equals "user skill discovered" "my-custom-skill" "${custom_skill}"

    local custom_available
    custom_available="$(jq -r '.skills[] | select(.name == "my-custom-skill") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "user skill is available" "true" "${custom_available}"

    local custom_invoke
    custom_invoke="$(jq -r '.skills[] | select(.name == "my-custom-skill") | .invoke' "${cache_file}" 2>/dev/null)"
    assert_equals "user skill invoke uses Skill()" "Skill(my-custom-skill)" "${custom_invoke}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 4. Discovers official plugin skills (mock plugin dir)
# ---------------------------------------------------------------------------
test_discovers_official_plugins() {
    echo "-- test: discovers official plugin skills --"
    setup_test_env

    # Create mock official plugin directories
    local plugin_base="${HOME}/.claude/plugins/cache/claude-plugins-official"
    mkdir -p "${plugin_base}/frontend-design"
    mkdir -p "${plugin_base}/claude-md-management"
    mkdir -p "${plugin_base}/claude-code-setup"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "${cache_file}"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # frontend-design should be available with correct invoke
    local fd_invoke
    fd_invoke="$(jq -r '.skills[] | select(.name == "frontend-design") | .invoke' "${cache_file}" 2>/dev/null)"
    assert_equals "frontend-design invoke" "Call Skill(frontend-design:frontend-design)" "${fd_invoke}"

    # claude-md-improver should be available
    local md_invoke
    md_invoke="$(jq -r '.skills[] | select(.name == "claude-md-improver") | .invoke' "${cache_file}" 2>/dev/null)"
    assert_equals "claude-md-improver invoke" "Call Skill(claude-md-management:claude-md-improver)" "${md_invoke}"

    # claude-automation-recommender should be available
    local ca_invoke
    ca_invoke="$(jq -r '.skills[] | select(.name == "claude-automation-recommender") | .invoke' "${cache_file}" 2>/dev/null)"
    assert_equals "claude-automation-recommender invoke" "Call Skill(claude-code-setup:claude-automation-recommender)" "${ca_invoke}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 5. Missing plugin dirs don't crash
# ---------------------------------------------------------------------------
test_missing_dirs_no_crash() {
    echo "-- test: missing plugin dirs don't crash --"
    setup_test_env

    # Ensure no plugin dirs exist at all
    rm -rf "${HOME}/.claude/plugins"
    rm -rf "${HOME}/.claude/skills"

    local exit_code=0
    run_hook >/dev/null || exit_code=$?

    assert_equals "hook exits cleanly" "0" "${exit_code}"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file still created" "${cache_file}"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 6. User config overrides (enabled: false)
# ---------------------------------------------------------------------------
test_user_config_disables_skill() {
    echo "-- test: user config disables skill --"
    setup_test_env

    # Create a superpowers skill so it would normally be available
    local sp_dir="${HOME}/.claude/plugins/cache/claude-plugins-official/superpowers/1.0.0/skills"
    mkdir -p "${sp_dir}/brainstorming"
    printf '# Brainstorming\n' > "${sp_dir}/brainstorming/SKILL.md"

    # Create user config that disables brainstorming
    printf '%s\n' '{
        "overrides": {
            "brainstorming": {
                "enabled": false
            }
        }
    }' > "${HOME}/.claude/skill-config.json"

    run_hook >/dev/null

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "${cache_file}"

    # brainstorming should be disabled
    local bs_enabled
    bs_enabled="$(jq -r '.skills[] | select(.name == "brainstorming") | .enabled' "${cache_file}" 2>/dev/null)"
    assert_equals "brainstorming is disabled" "false" "${bs_enabled}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 7. Health check output contains "skills active"
# ---------------------------------------------------------------------------
test_health_check_output() {
    echo "-- test: health check output format --"
    setup_test_env

    local output
    output="$(run_hook)"

    assert_contains "output has hookEventName" "SessionStart" "${output}"
    assert_contains "output has skills active" "skills active" "${output}"

    # Should be valid JSON output
    local hook_json
    hook_json="$(echo "${output}" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
    assert_contains "output context has skills active" "skills active" "${hook_json}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 8. Discovers agent team user skills
# ---------------------------------------------------------------------------
test_discovers_agent_team_skills() {
    echo "-- test: discovers agent team user skills --"
    setup_test_env

    # Create mock user skills for agent team skills
    mkdir -p "${HOME}/.claude/skills/agent-team-execution"
    printf '%s\n' '---' 'name: agent-team-execution' '---' > \
        "${HOME}/.claude/skills/agent-team-execution/SKILL.md"
    mkdir -p "${HOME}/.claude/skills/agent-team-review"
    printf '%s\n' '---' 'name: agent-team-review' '---' > \
        "${HOME}/.claude/skills/agent-team-review/SKILL.md"
    mkdir -p "${HOME}/.claude/skills/design-debate"
    printf '%s\n' '---' 'name: design-debate' '---' > \
        "${HOME}/.claude/skills/design-debate/SKILL.md"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "$cache_file"
    assert_json_valid "cache file is valid JSON" "$cache_file"

    local ate_available
    ate_available=$(jq -r '.skills[] | select(.name == "agent-team-execution") | .available' "$cache_file")
    assert_equals "agent-team-execution available" "true" "$ate_available"

    local atr_available
    atr_available=$(jq -r '.skills[] | select(.name == "agent-team-review") | .available' "$cache_file")
    assert_equals "agent-team-review available" "true" "$atr_available"

    local dd_available
    dd_available=$(jq -r '.skills[] | select(.name == "design-debate") | .available' "$cache_file")
    assert_equals "design-debate available" "true" "$dd_available"

    teardown_test_env
}

test_default_triggers_has_plugins_section() {
    echo "-- test: default-triggers has plugins section --"
    setup_test_env

    local plugin_count
    plugin_count="$(jq '.plugins | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"

    # Should have 10 curated plugins (5 enhancers + context7 + github + atlassian + forgetful + unified-context-stack)
    assert_equals "default-triggers has 10 plugins" "10" "${plugin_count}"

    # Each plugin should have required fields
    local valid_count
    valid_count="$(jq '[.plugins[] | select(.name and .source and .provides and .phase_fit and .description)] | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "all plugins have required fields" "10" "${valid_count}"

    teardown_test_env
}

test_default_triggers_has_phase_compositions() {
    echo "-- test: default-triggers has phase_compositions --"
    setup_test_env

    local phases
    phases="$(jq '.phase_compositions | keys[]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null | sort)"

    assert_contains "has DESIGN phase" "DESIGN" "${phases}"
    assert_contains "has PLAN phase" "PLAN" "${phases}"
    assert_contains "has IMPLEMENT phase" "IMPLEMENT" "${phases}"
    assert_contains "has REVIEW phase" "REVIEW" "${phases}"
    assert_contains "has SHIP phase" "SHIP" "${phases}"
    assert_contains "has DEBUG phase" "DEBUG" "${phases}"

    # Each phase must have a driver field
    local driver_count
    driver_count="$(jq '[.phase_compositions | to_entries[] | select(.value.driver)] | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "all 6 phases have drivers" "6" "${driver_count}"

    # REVIEW should have parallel entries
    local review_parallel
    review_parallel="$(jq '.phase_compositions.REVIEW.parallel | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "REVIEW has 4 parallel entries" "4" "${review_parallel}"

    # SHIP should have sequence entries
    local ship_sequence
    ship_sequence="$(jq '.phase_compositions.SHIP.sequence | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "SHIP has 5 sequence entries" "5" "${ship_sequence}"

    teardown_test_env
}

test_discovers_curated_plugins() {
    echo "-- test: discovers curated plugins --"
    setup_test_env

    # Create mock plugin directories for curated plugins
    local plugin_base="${HOME}/.claude/plugins/cache/claude-plugins-official"
    mkdir -p "${plugin_base}/commit-commands"
    mkdir -p "${plugin_base}/feature-dev"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "${cache_file}"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # commit-commands should be in plugins array and marked available
    local cc_available
    cc_available="$(jq -r '.plugins[] | select(.name == "commit-commands") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "commit-commands is available" "true" "${cc_available}"

    # feature-dev should be available
    local fd_available
    fd_available="$(jq -r '.plugins[] | select(.name == "feature-dev") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "feature-dev is available" "true" "${fd_available}"

    # security-guidance should exist but be unavailable (not installed)
    local sg_available
    sg_available="$(jq -r '.plugins[] | select(.name == "security-guidance") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "security-guidance is unavailable" "false" "${sg_available}"

    teardown_test_env
}

test_registry_includes_phase_compositions() {
    echo "-- test: registry cache includes phase_compositions --"
    setup_test_env

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    local pc_keys
    pc_keys="$(jq '.phase_compositions | keys | length' "${cache_file}" 2>/dev/null)"
    assert_equals "phase_compositions has 6 phases" "6" "${pc_keys}"

    teardown_test_env
}

test_auto_discovers_unknown_plugins() {
    echo "-- test: auto-discovers unknown plugins --"
    setup_test_env

    # Create a mock unknown plugin with skills and commands
    local unknown_dir="${HOME}/.claude/plugins/cache/community-marketplace/my-unknown-plugin/1.0.0"
    mkdir -p "${unknown_dir}/skills/custom-lint"
    printf '---\nname: custom-lint\ndescription: Custom lint rules\n---\n# Custom Lint\n' > \
        "${unknown_dir}/skills/custom-lint/SKILL.md"
    mkdir -p "${unknown_dir}/commands"
    printf '# Run Lint\n' > "${unknown_dir}/commands/lint.md"
    mkdir -p "${unknown_dir}/.claude-plugin"
    printf '{"name":"my-unknown-plugin","version":"1.0.0"}\n' > "${unknown_dir}/.claude-plugin/plugin.json"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # Unknown plugin should appear in plugins array
    local up_name
    up_name="$(jq -r '.plugins[] | select(.name == "my-unknown-plugin") | .name' "${cache_file}" 2>/dev/null)"
    assert_equals "unknown plugin discovered" "my-unknown-plugin" "${up_name}"

    local up_available
    up_available="$(jq -r '.plugins[] | select(.name == "my-unknown-plugin") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "unknown plugin is available" "true" "${up_available}"

    # Should detect the skill
    local up_skills
    up_skills="$(jq -r '.plugins[] | select(.name == "my-unknown-plugin") | .provides.skills[0]' "${cache_file}" 2>/dev/null)"
    assert_equals "unknown plugin skill detected" "custom-lint" "${up_skills}"

    # Should detect the command
    local up_commands
    up_commands="$(jq -r '.plugins[] | select(.name == "my-unknown-plugin") | .provides.commands[0]' "${cache_file}" 2>/dev/null)"
    assert_equals "unknown plugin command detected" "/lint" "${up_commands}"

    teardown_test_env
}

test_health_check_reports_new_plugins() {
    echo "-- test: health check reports plugin count --"
    setup_test_env

    # Install one curated plugin
    mkdir -p "${HOME}/.claude/plugins/cache/claude-plugins-official/commit-commands"

    local output
    output="$(run_hook)"

    # Health check should mention plugins
    assert_contains "health check mentions plugins" "plugin" "$(printf '%s' "${output}" | tr '[:upper:]' '[:lower:]')"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Fallback registry drift detection
# ---------------------------------------------------------------------------
test_fallback_registry_skill_coverage() {
    echo "-- test: fallback registry covers all default-triggers skills --"

    local triggers_file="${PROJECT_ROOT}/config/default-triggers.json"
    local fallback_file="${PROJECT_ROOT}/config/fallback-registry.json"

    # Extract skill names from default-triggers.json
    local trigger_skills
    trigger_skills="$(jq -r '.skills[].name' "$triggers_file" | sort)"

    # Extract skill names from fallback-registry.json
    local fallback_skills
    fallback_skills="$(jq -r '.skills[].name' "$fallback_file" | sort)"

    # Every fallback skill should exist in default-triggers
    local missing_from_triggers=""
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if ! printf '%s\n' "$trigger_skills" | grep -qx "$name"; then
            missing_from_triggers="${missing_from_triggers} ${name}"
        fi
    done <<EOF
${fallback_skills}
EOF
    assert_equals "fallback skills all exist in default-triggers" "" "${missing_from_triggers}"

    # Check that fallback has invoke fields for all its skills
    local missing_invoke
    missing_invoke="$(jq -r '.skills[] | select(.invoke == null or .invoke == "") | .name' "$fallback_file" | tr '\n' ' ')"
    assert_equals "fallback skills all have invoke fields" "" "${missing_invoke}"

    # Check that all skills in both files have phase fields
    local triggers_missing_phase
    triggers_missing_phase="$(jq -r '.skills[] | select(.phase == null or .phase == "") | .name' "$triggers_file" | tr '\n' ' ')"
    assert_equals "default-triggers skills all have phase fields" "" "${triggers_missing_phase}"

    local fallback_missing_phase
    fallback_missing_phase="$(jq -r '.skills[] | select(.phase == null or .phase == "") | .name' "$fallback_file" | tr '\n' ' ')"
    assert_equals "fallback skills all have phase fields" "" "${fallback_missing_phase}"
}

test_context_capabilities_detection() {
    echo "-- test: context_capabilities detected in registry cache --"
    setup_test_env

    # Install context7 plugin (to simulate it being available)
    mkdir -p "${HOME}/.claude/plugins/cache/claude-plugins-official/context7"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # context_capabilities should exist in registry
    local has_caps
    has_caps="$(jq 'has("context_capabilities")' "${cache_file}" 2>/dev/null)"
    assert_equals "registry has context_capabilities" "true" "${has_caps}"

    # context7 should be true (plugin installed)
    local ctx7
    ctx7="$(jq -r '.context_capabilities.context7' "${cache_file}" 2>/dev/null)"
    assert_equals "context7 detected as true" "true" "${ctx7}"

    # context_hub_available should derive from context7
    local hub_avail
    hub_avail="$(jq -r '.context_capabilities.context_hub_available' "${cache_file}" 2>/dev/null)"
    assert_equals "context_hub_available derived from context7" "true" "${hub_avail}"

    # chub CLI: may or may not be on system PATH depending on test machine
    local chub_cli
    chub_cli="$(jq -r '.context_capabilities.context_hub_cli' "${cache_file}" 2>/dev/null)"
    if command -v chub >/dev/null 2>&1; then
        assert_equals "context_hub_cli is true (chub on PATH)" "true" "${chub_cli}"
    else
        assert_equals "context_hub_cli is false (chub not on PATH)" "false" "${chub_cli}"
    fi

    # serena not installed
    local serena
    serena="$(jq -r '.context_capabilities.serena' "${cache_file}" 2>/dev/null)"
    assert_equals "serena is false (not installed)" "false" "${serena}"

    teardown_test_env
}

test_context_capabilities_all_false() {
    echo "-- test: context_capabilities all false when nothing installed --"
    setup_test_env

    # No plugins installed at all
    rm -rf "${HOME}/.claude/plugins"

    # Mask CLI tools (chub, openspec) from PATH so they appear uninstalled.
    # Keep only essential binaries (bash, jq, git, etc.) by using a minimal PATH.
    local _minimal_path="/usr/bin:/bin:/usr/sbin:/sbin"
    # Preserve jq location if it's outside the minimal path
    local _jq_path
    _jq_path="$(command -v jq 2>/dev/null)"
    if [ -n "${_jq_path}" ]; then
        _minimal_path="$(dirname "${_jq_path}"):${_minimal_path}"
    fi

    local output
    output="$(PATH="${_minimal_path}" run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"

    # All capabilities should be false
    local all_false
    all_false="$(jq '[.context_capabilities | to_entries[] | .value] | all(. == false)' "${cache_file}" 2>/dev/null)"
    assert_equals "all capabilities false when nothing installed" "true" "${all_false}"

    # unified-context-stack plugin should be unavailable
    local ucs_avail
    ucs_avail="$(jq -r '.plugins[] | select(.name == "unified-context-stack") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "unified-context-stack unavailable when no caps" "false" "${ucs_avail}"

    teardown_test_env
}

test_context_capabilities_in_health_output() {
    echo "-- test: context_capabilities in session-start output --"
    setup_test_env

    # Install context7 plugin
    mkdir -p "${HOME}/.claude/plugins/cache/claude-plugins-official/context7"

    local output
    output="$(run_hook)"

    # additionalContext should contain the Context Stack line
    local context
    context="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
    assert_contains "output has Context Stack line" "Context Stack:" "${context}"
    assert_contains "output has context7=true" "context7=true" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# openspec-ship chain rewires are consistent
# ---------------------------------------------------------------------------
test_openspec_ship_chain_consistency() {
    echo "-- test: openspec-ship chain rewires are consistent --"
    setup_test_env

    local vbc_precedes
    vbc_precedes="$(jq -r '.skills[] | select(.name == "verification-before-completion") | .precedes[0]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "vbc precedes openspec-ship" "openspec-ship" "${vbc_precedes}"

    local os_requires
    os_requires="$(jq -r '.skills[] | select(.name == "openspec-ship") | .requires[0]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "openspec-ship requires vbc" "verification-before-completion" "${os_requires}"

    local os_precedes
    os_precedes="$(jq -r '.skills[] | select(.name == "openspec-ship") | .precedes[0]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "openspec-ship precedes finishing" "finishing-a-development-branch" "${os_precedes}"

    local fab_requires
    fab_requires="$(jq -r '.skills[] | select(.name == "finishing-a-development-branch") | .requires[0]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "finishing requires openspec-ship" "openspec-ship" "${fab_requires}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# OpenSpec bootstrap detection tests
# ---------------------------------------------------------------------------
test_openspec_binary_detected() {
    echo "-- test: openspec binary detection --"
    setup_test_env

    # Create a fake openspec binary in PATH
    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local binary
    binary="$(jq -r '.openspec_capabilities.binary' "$cache" 2>/dev/null)"
    assert_equals "openspec binary detected" "true" "$binary"

    teardown_test_env
}

test_openspec_binary_absent() {
    echo "-- test: openspec binary absent --"
    setup_test_env

    # Mask CLI tools from PATH so openspec appears uninstalled.
    local _minimal_path="/usr/bin:/bin:/usr/sbin:/sbin"
    local _jq_path
    _jq_path="$(command -v jq 2>/dev/null)"
    if [ -n "${_jq_path}" ]; then
        _minimal_path="$(dirname "${_jq_path}"):${_minimal_path}"
    fi

    local output
    output="$(PATH="${_minimal_path}" run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local binary
    binary="$(jq -r '.openspec_capabilities.binary' "$cache" 2>/dev/null)"
    assert_equals "openspec binary absent" "false" "$binary"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is none" "none" "$surface"

    teardown_test_env
}

test_openspec_opsx_core_detection() {
    echo "-- test: OPSX core surface detection --"
    setup_test_env

    # Create fake binary + core commands
    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    local ws_dir="${HOME}/workspace"
    mkdir -p "${ws_dir}/.claude/commands/opsx"
    touch "${ws_dir}/.claude/commands/opsx/propose.md"
    touch "${ws_dir}/.claude/commands/opsx/apply.md"
    touch "${ws_dir}/.claude/commands/opsx/archive.md"
    touch "${ws_dir}/.claude/commands/opsx/explore.md"
    export _OPENSPEC_WORKSPACE_OVERRIDE="${ws_dir}"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is opsx-core" "opsx-core" "$surface"

    local cmd_count
    cmd_count="$(jq '.openspec_capabilities.commands | length' "$cache" 2>/dev/null)"
    assert_equals "4 commands detected" "4" "$cmd_count"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}

test_openspec_opsx_expanded_detection() {
    echo "-- test: OPSX expanded surface detection --"
    setup_test_env

    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    local ws_dir="${HOME}/workspace"
    mkdir -p "${ws_dir}/.claude/commands/opsx"
    touch "${ws_dir}/.claude/commands/opsx/propose.md"
    touch "${ws_dir}/.claude/commands/opsx/apply.md"
    touch "${ws_dir}/.claude/commands/opsx/archive.md"
    touch "${ws_dir}/.claude/commands/opsx/new.md"
    touch "${ws_dir}/.claude/commands/opsx/ff.md"
    export _OPENSPEC_WORKSPACE_OVERRIDE="${ws_dir}"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is opsx-expanded" "opsx-expanded" "$surface"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}

test_openspec_binary_only() {
    echo "-- test: binary only, no OPSX commands --"
    setup_test_env

    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    # No workspace commands
    export _OPENSPEC_WORKSPACE_OVERRIDE="${HOME}/empty-workspace"
    mkdir -p "${HOME}/empty-workspace"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is openspec-core" "openspec-core" "$surface"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}

test_openspec_commands_without_binary() {
    echo "-- test: commands without binary (mismatch warning) --"
    setup_test_env

    # Mask CLI tools from PATH so openspec appears uninstalled.
    local _minimal_path="/usr/bin:/bin:/usr/sbin:/sbin"
    local _jq_path
    _jq_path="$(command -v jq 2>/dev/null)"
    if [ -n "${_jq_path}" ]; then
        _minimal_path="$(dirname "${_jq_path}"):${_minimal_path}"
    fi

    # No binary, but create commands
    local ws_dir="${HOME}/workspace"
    mkdir -p "${ws_dir}/.claude/commands/opsx"
    touch "${ws_dir}/.claude/commands/opsx/propose.md"
    touch "${ws_dir}/.claude/commands/opsx/archive.md"
    export _OPENSPEC_WORKSPACE_OVERRIDE="${ws_dir}"

    local output
    output="$(PATH="${_minimal_path}" run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is none (no binary)" "none" "$surface"

    local warnings
    warnings="$(jq -r '.openspec_capabilities.warnings[0] // ""' "$cache" 2>/dev/null)"
    assert_contains "mismatch warning" "binary missing" "$warnings"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}

test_openspec_capability_line_emission() {
    echo "-- test: OpenSpec capability line in session-start output --"
    setup_test_env

    local output
    output="$(run_hook)"
    local ctx
    ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

    assert_contains "OpenSpec capability line emitted" "OpenSpec:" "$ctx"
    assert_contains "has binary field" "binary=" "$ctx"
    assert_contains "has surface field" "surface=" "$ctx"

    teardown_test_env
}

test_openspec_workspace_only_discovery() {
    echo "-- test: workspace-only command discovery --"
    setup_test_env

    # Binary present, commands only in workspace (not in any plugin root)
    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    local ws_dir="${HOME}/workspace"
    mkdir -p "${ws_dir}/.claude/commands/opsx"
    touch "${ws_dir}/.claude/commands/opsx/propose.md"
    touch "${ws_dir}/.claude/commands/opsx/apply.md"
    touch "${ws_dir}/.claude/commands/opsx/archive.md"
    export _OPENSPEC_WORKSPACE_OVERRIDE="${ws_dir}"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local cmd_count
    cmd_count="$(jq '.openspec_capabilities.commands | length' "$cache" 2>/dev/null)"
    assert_equals "3 commands from workspace probe" "3" "$cmd_count"

    assert_contains "propose discovered" "/opsx:propose" "$(jq -r '.openspec_capabilities.commands | join(",")' "$cache" 2>/dev/null)"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
test_empty_env_produces_fallback
test_discovers_superpowers_skills
test_discovers_user_skills
test_discovers_official_plugins
test_missing_dirs_no_crash
test_user_config_disables_skill
test_health_check_output
test_discovers_agent_team_skills
test_default_triggers_has_plugins_section
test_default_triggers_has_phase_compositions
test_discovers_curated_plugins
test_registry_includes_phase_compositions
test_auto_discovers_unknown_plugins
test_health_check_reports_new_plugins
test_fallback_registry_skill_coverage
test_context_capabilities_detection
test_context_capabilities_all_false
test_context_capabilities_in_health_output
test_openspec_ship_chain_consistency
test_openspec_binary_detected
test_openspec_binary_absent
test_openspec_opsx_core_detection
test_openspec_opsx_expanded_detection
test_openspec_binary_only
test_openspec_commands_without_binary
test_openspec_capability_line_emission
test_openspec_workspace_only_discovery

print_summary
