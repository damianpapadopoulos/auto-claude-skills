#!/usr/bin/env bash
# test-install.sh — Validation tests for installed plugin structure
# These tests verify that all required files exist and are valid.

set -euo pipefail

# Set SCRIPT_DIR for portability
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use CLAUDE_PLUGIN_ROOT if set, otherwise fallback to parent directory
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "${SCRIPT_DIR}")}"

# Source test helpers for assert functions
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Install Validation Tests"
echo "======================="
echo "Plugin root: ${PLUGIN_ROOT}"
echo ""

# Test 1: config/default-triggers.json exists and is valid JSON
assert_file_exists \
    "config/default-triggers.json exists" \
    "${PLUGIN_ROOT}/config/default-triggers.json"

assert_json_valid \
    "config/default-triggers.json is valid JSON" \
    "${PLUGIN_ROOT}/config/default-triggers.json"

# Test 2: config/fallback-registry.json exists and is valid JSON
assert_file_exists \
    "config/fallback-registry.json exists" \
    "${PLUGIN_ROOT}/config/fallback-registry.json"

assert_json_valid \
    "config/fallback-registry.json is valid JSON" \
    "${PLUGIN_ROOT}/config/fallback-registry.json"

# Test 3: hooks/skill-activation-hook.sh exists and is executable
assert_file_exists \
    "hooks/skill-activation-hook.sh exists" \
    "${PLUGIN_ROOT}/hooks/skill-activation-hook.sh"

if [ -x "${PLUGIN_ROOT}/hooks/skill-activation-hook.sh" ]; then
    _record_pass "hooks/skill-activation-hook.sh is executable"
else
    _record_fail "hooks/skill-activation-hook.sh is executable" \
        "file is not executable"
fi

# Test 4: hooks/session-start-hook.sh exists and is executable
assert_file_exists \
    "hooks/session-start-hook.sh exists" \
    "${PLUGIN_ROOT}/hooks/session-start-hook.sh"

if [ -x "${PLUGIN_ROOT}/hooks/session-start-hook.sh" ]; then
    _record_pass "hooks/session-start-hook.sh is executable"
else
    _record_fail "hooks/session-start-hook.sh is executable" \
        "file is not executable"
fi

# Test 5: hooks/fix-plugin-manifests.sh exists and is executable
assert_file_exists \
    "hooks/fix-plugin-manifests.sh exists" \
    "${PLUGIN_ROOT}/hooks/fix-plugin-manifests.sh"

if [ -x "${PLUGIN_ROOT}/hooks/fix-plugin-manifests.sh" ]; then
    _record_pass "hooks/fix-plugin-manifests.sh is executable"
else
    _record_fail "hooks/fix-plugin-manifests.sh is executable" \
        "file is not executable"
fi

# Test 6: hooks/hooks.json exists, is valid JSON, and references both hooks
assert_file_exists \
    "hooks/hooks.json exists" \
    "${PLUGIN_ROOT}/hooks/hooks.json"

assert_json_valid \
    "hooks/hooks.json is valid JSON" \
    "${PLUGIN_ROOT}/hooks/hooks.json"

# Verify hooks.json references session-start-hook.sh
HOOKS_CONTENT=$(cat "${PLUGIN_ROOT}/hooks/hooks.json")
assert_contains \
    "hooks.json references session-start-hook.sh" \
    "session-start-hook.sh" \
    "${HOOKS_CONTENT}"

# Verify hooks.json references skill-activation-hook.sh
assert_contains \
    "hooks.json references skill-activation-hook.sh" \
    "skill-activation-hook.sh" \
    "${HOOKS_CONTENT}"

# Test 7: .claude-plugin/plugin.json exists and is valid JSON
assert_file_exists \
    ".claude-plugin/plugin.json exists" \
    "${PLUGIN_ROOT}/.claude-plugin/plugin.json"

assert_json_valid \
    ".claude-plugin/plugin.json is valid JSON" \
    "${PLUGIN_ROOT}/.claude-plugin/plugin.json"

# ---------------------------------------------------------------------------
# Print summary and exit with appropriate code
# ---------------------------------------------------------------------------
print_summary
