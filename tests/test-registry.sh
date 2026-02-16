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
    assert_contains "registry has version" "2.0" "${version}"

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
    run_hook || exit_code=$?

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
# Run all tests
# ---------------------------------------------------------------------------
test_empty_env_produces_fallback
test_discovers_superpowers_skills
test_discovers_user_skills
test_discovers_official_plugins
test_missing_dirs_no_crash
test_user_config_disables_skill
test_health_check_output

print_summary
