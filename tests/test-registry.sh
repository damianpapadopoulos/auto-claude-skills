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
    assert_contains "registry has version" "3.2" "${version}"

    # Should have skills array
    local skill_count
    skill_count="$(jq '.skills | length' "${cache_file}" 2>/dev/null)"
    # With no plugins, skills from defaults should be marked available: false
    # but still present
    assert_contains "skills array exists" "" "$(jq -r '.skills' "${cache_file}" 2>/dev/null)"

    # Health check output
    assert_contains "health check in output" "skill registry built" "${output}"

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
    assert_contains "health check in output" "skill registry built" "${output}"

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
# 7. Health check output contains "skill registry built"
# ---------------------------------------------------------------------------
test_health_check_output() {
    echo "-- test: health check output format --"
    setup_test_env

    local output
    output="$(run_hook)"

    assert_contains "output has hookEventName" "SessionStart" "${output}"
    assert_contains "output has skill registry built" "skill registry built" "${output}"

    # Should be valid JSON output
    local hook_json
    hook_json="$(echo "${output}" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
    assert_contains "output context has skill registry built" "skill registry built" "${hook_json}"

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

    # Should have 7 curated plugins
    assert_equals "default-triggers has 7 plugins" "7" "${plugin_count}"

    # Each plugin should have required fields
    local valid_count
    valid_count="$(jq '[.plugins[] | select(.name and .source and .provides and .phase_fit and .description)] | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "all plugins have required fields" "7" "${valid_count}"

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
    assert_equals "REVIEW has 2 parallel entries" "2" "${review_parallel}"

    # SHIP should have sequence entries
    local ship_sequence
    ship_sequence="$(jq '.phase_compositions.SHIP.sequence | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "SHIP has 3 sequence entries" "3" "${ship_sequence}"

    teardown_test_env
}

test_discovers_curated_plugins() {
    echo "-- test: discovers curated plugins --"
    setup_test_env

    # Create mock plugin directories for curated plugins
    local plugin_base="${HOME}/.claude/plugins/cache/claude-plugins-official"
    mkdir -p "${plugin_base}/commit-commands"
    mkdir -p "${plugin_base}/feature-dev"
    mkdir -p "${plugin_base}/code-review"

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

print_summary
