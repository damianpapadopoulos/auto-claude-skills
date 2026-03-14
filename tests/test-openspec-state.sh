#!/usr/bin/env bash
# test-openspec-state.sh — Tests for OpenSpec session state persistence
# Bash 3.2 compatible. Sources test-helpers.sh for assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

# Source the helper under test
. "${PROJECT_ROOT}/hooks/lib/openspec-state.sh"

echo "=== test-openspec-state.sh ==="

# ---------------------------------------------------------------------------
# 1. Hooks alone do not create state file
# ---------------------------------------------------------------------------
test_hooks_do_not_create_state() {
    echo "-- test: hooks alone do not create OpenSpec state file --"
    setup_test_env

    # Run session-start hook
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" >/dev/null 2>&1

    # Run routing hook with a prompt
    printf '{"userMessage":"ship this"}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" >/dev/null 2>&1

    # Assert no openspec state file was created
    local state_files
    state_files="$(ls "${HOME}/.claude/.skill-openspec-state-"* 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "no openspec state file created by hooks" "0" "${state_files}"

    teardown_test_env
}
test_hooks_do_not_create_state

# ---------------------------------------------------------------------------
# 2. mark_verified creates state file
# ---------------------------------------------------------------------------
test_mark_verified_creates_state() {
    echo "-- test: mark_verified creates state file --"
    setup_test_env

    local token="test-$$"
    openspec_state_mark_verified "$token" "opsx-core"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    assert_equals "state file exists" "true" "$([ -f "$state_file" ] && echo true || echo false)"

    local verified
    verified="$(jq -r '.verification_seen' "$state_file" 2>/dev/null)"
    assert_equals "verification_seen is true" "true" "$verified"

    local surface
    surface="$(jq -r '.openspec_surface' "$state_file" 2>/dev/null)"
    assert_equals "openspec_surface is opsx-core" "opsx-core" "$surface"

    local changes_count
    changes_count="$(jq '.changes | length' "$state_file" 2>/dev/null)"
    assert_equals "changes map is empty" "0" "$changes_count"

    teardown_test_env
}
test_mark_verified_creates_state

# ---------------------------------------------------------------------------
# 3. upsert_change adds to changes map without overwriting
# ---------------------------------------------------------------------------
test_upsert_change_preserves_entries() {
    echo "-- test: upsert_change adds multiple entries --"
    setup_test_env

    local token="test-$$"
    # First: create state with verification
    openspec_state_mark_verified "$token" "opsx-core"

    # Add first change
    openspec_state_upsert_change "$token" "feature-a" "plans/a.md" "specs/a.md" "billing"

    # Add second change
    openspec_state_upsert_change "$token" "feature-b" "plans/b.md" "specs/b.md" "auth"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    # Both entries should exist
    local count
    count="$(jq '.changes | length' "$state_file" 2>/dev/null)"
    assert_equals "two entries in changes map" "2" "$count"

    local a_plan
    a_plan="$(jq -r '.changes["feature-a"].sp_plan_path' "$state_file" 2>/dev/null)"
    assert_equals "feature-a plan preserved" "plans/a.md" "$a_plan"

    local b_cap
    b_cap="$(jq -r '.changes["feature-b"].capability_slug' "$state_file" 2>/dev/null)"
    assert_equals "feature-b capability preserved" "auth" "$b_cap"

    # Verification fields should still be intact
    local verified
    verified="$(jq -r '.verification_seen' "$state_file" 2>/dev/null)"
    assert_equals "verification still intact" "true" "$verified"

    teardown_test_env
}
test_upsert_change_preserves_entries

# ---------------------------------------------------------------------------
# 4. write_provenance produces valid source.json
# ---------------------------------------------------------------------------
test_write_provenance_produces_source_json() {
    echo "-- test: write_provenance produces valid source.json --"
    setup_test_env

    local token="test-$$"
    openspec_state_mark_verified "$token" "opsx-core"
    openspec_state_upsert_change "$token" "my-feature" "plans/my.md" "specs/my.md" "my-cap"

    local archive_dir="${HOME}/test-archive"
    mkdir -p "$archive_dir"

    openspec_write_provenance "$archive_dir" "$token" "my-feature"

    local source_json="${archive_dir}/superpowers/source.json"
    assert_equals "source.json exists" "true" "$([ -f "$source_json" ] && echo true || echo false)"

    # Validate schema
    local schema_version
    schema_version="$(jq -r '.schema_version' "$source_json" 2>/dev/null)"
    assert_equals "schema_version is 1" "1" "$schema_version"

    local plan
    plan="$(jq -r '.sp_plan_path' "$source_json" 2>/dev/null)"
    assert_equals "sp_plan_path populated" "plans/my.md" "$plan"

    local cap
    cap="$(jq -r '.capability_slug' "$source_json" 2>/dev/null)"
    assert_equals "capability_slug populated" "my-cap" "$cap"

    local surface
    surface="$(jq -r '.openspec_surface' "$source_json" 2>/dev/null)"
    assert_equals "openspec_surface from state" "opsx-core" "$surface"

    # base_commit should be non-null (we're in a git repo)
    local commit
    commit="$(jq -r '.base_commit' "$source_json" 2>/dev/null)"
    assert_not_contains "base_commit not null" "null" "$commit"

    teardown_test_env
}
test_write_provenance_produces_source_json

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "=============================="
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '%s' "${FAIL_MESSAGES}"
    exit 1
else
    echo "All tests passed."
fi
