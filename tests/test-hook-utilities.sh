#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

. "${SCRIPT_DIR}/test-helpers.sh"

FIX_HOOK="${PROJECT_ROOT}/hooks/fix-plugin-manifests.sh"
SERENA_NUDGE_HOOK="${PROJECT_ROOT}/hooks/serena-nudge.sh"
PRE_COMPACT_HOOK="${PROJECT_ROOT}/hooks/pre-compact-hook.sh"
SETUP_DEV_SCRIPT="${PROJECT_ROOT}/scripts/setup-dev.sh"

write_serena_registry() {
    mkdir -p "${HOME}/.claude"
    cat > "${HOME}/.claude/.skill-registry-cache.json" <<'EOF'
{"context_capabilities":{"serena":true}}
EOF
}

echo "=== test-hook-utilities.sh ==="

test_fix_plugin_manifests_strips_invalid_keys() {
    echo "-- test: fix-plugin-manifests strips invalid keys --"
    setup_test_env

    local manifest_dir="${HOME}/.claude/plugins/cache/vendor/.claude-plugin"
    local manifest="${manifest_dir}/plugin.json"
    local unrelated_manifest="${HOME}/.claude/plugins/cache/vendor/plugin.json"
    mkdir -p "${manifest_dir}" "$(dirname "${unrelated_manifest}")"

    cat > "${manifest}" <<'EOF'
{"name":"demo","version":"1.0.0","category":"misc","source":"cache","strict":true,"hooks":{}}
EOF
    printf '{"name":"untouched","strict":true}\n' > "${unrelated_manifest}"

    bash "${FIX_HOOK}" >/dev/null 2>&1

    local has_invalid_keys
    has_invalid_keys="$(jq -r 'has("category") or has("source") or has("strict")' "${manifest}" 2>/dev/null)"
    assert_equals "invalid manifest keys removed" "false" "${has_invalid_keys}"

    local name_value
    name_value="$(jq -r '.name' "${manifest}" 2>/dev/null)"
    assert_equals "valid manifest fields preserved" "demo" "${name_value}"

    assert_contains "non-plugin manifest left untouched" '"strict":true' "$(cat "${unrelated_manifest}")"

    teardown_test_env
}
test_fix_plugin_manifests_strips_invalid_keys

test_fix_plugin_manifests_skips_invalid_json() {
    echo "-- test: fix-plugin-manifests skips invalid json --"
    setup_test_env

    local manifest_dir="${HOME}/.claude/plugins/cache/vendor/.claude-plugin"
    local manifest="${manifest_dir}/plugin.json"
    mkdir -p "${manifest_dir}"
    printf '{"name":"broken"\n' > "${manifest}"

    bash "${FIX_HOOK}" >/dev/null 2>&1
    local rc=$?
    assert_equals "hook exits cleanly on invalid json" "0" "${rc}"
    assert_equals "invalid manifest remains unchanged" '{"name":"broken"' "$(tr -d '\n' < "${manifest}")"

    teardown_test_env
}
test_fix_plugin_manifests_skips_invalid_json

test_serena_nudge_emits_hint_for_symbol_lookup() {
    echo "-- test: serena-nudge emits hint for symbol lookup --"
    setup_test_env
    write_serena_registry

    local output
    output="$(printf '%s' '{"tool_name":"Grep","tool_input":{"pattern":"OrderService"}}' | bash "${SERENA_NUDGE_HOOK}" 2>/dev/null)"

    assert_not_empty "serena hint output is present" "${output}"
    assert_contains "serena hint mentions Serena" "Serena is available" "${output}"

    local tmpfile="${TEST_TMPDIR}/serena-output.json"
    printf '%s' "${output}" > "${tmpfile}"
    assert_json_valid "serena hint output is valid JSON" "${tmpfile}"

    teardown_test_env
}
test_serena_nudge_emits_hint_for_symbol_lookup

test_serena_nudge_ignores_non_symbol_regex() {
    echo "-- test: serena-nudge ignores non-symbol regex --"
    setup_test_env
    write_serena_registry

    local output
    output="$(printf '%s' '{"tool_name":"Grep","tool_input":{"pattern":"foo.*bar"}}' | bash "${SERENA_NUDGE_HOOK}" 2>/dev/null)"

    assert_equals "regex search does not emit hint" "" "${output}"

    teardown_test_env
}
test_serena_nudge_ignores_non_symbol_regex

test_pre_compact_hook_fail_open_without_cozempic() {
    echo "-- test: pre-compact hook exits cleanly without cozempic --"
    setup_test_env

    printf '%s' '{"trigger":"manual"}' | PATH=/usr/bin:/bin bash "${PRE_COMPACT_HOOK}" >/dev/null 2>&1
    local rc=$?
    assert_equals "hook exits 0 when cozempic is absent" "0" "${rc}"

    teardown_test_env
}
test_pre_compact_hook_fail_open_without_cozempic

test_pre_compact_hook_logs_and_runs_cozempic() {
    echo "-- test: pre-compact hook logs and runs cozempic --"
    setup_test_env

    local transcript="${TEST_TMPDIR}/session.jsonl"
    local command_log="${TEST_TMPDIR}/cozempic.log"
    mkdir -p "${HOME}/.local/bin"
    printf 'transcript body\n' > "${transcript}"

    cat > "${HOME}/.local/bin/cozempic" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${command_log}"
exit 0
EOF
    chmod +x "${HOME}/.local/bin/cozempic"

    printf '%s' "{\"trigger\":\"auto\",\"transcript_path\":\"${transcript}\"}" | bash "${PRE_COMPACT_HOOK}" >/dev/null 2>&1
    local rc=$?
    assert_equals "hook exits 0 with fake cozempic" "0" "${rc}"

    assert_contains "checkpoint command executed" "checkpoint" "$(cat "${command_log}")"
    assert_contains "treat command executed" "treat current -rx standard --execute" "$(cat "${command_log}")"
    assert_contains "compaction event logged" "trigger=auto" "$(cat "${HOME}/.claude/.compact-events.log")"
    assert_contains "log references transcript path" "${transcript}" "$(cat "${HOME}/.claude/.compact-events.log")"

    teardown_test_env
}
test_pre_compact_hook_logs_and_runs_cozempic

test_setup_dev_fails_without_installed_plugin() {
    echo "-- test: setup-dev fails without installed plugin --"
    setup_test_env

    local output
    output="$(bash "${SETUP_DEV_SCRIPT}" 2>&1 >/dev/null)"
    local rc=$?

    assert_equals "setup-dev exits 1 when plugin is missing" "1" "${rc}"
    assert_contains "setup-dev explains missing install" "Install the plugin first" "${output}"

    teardown_test_env
}
test_setup_dev_fails_without_installed_plugin

test_setup_dev_links_and_restores_plugin_cache() {
    echo "-- test: setup-dev links and restores plugin cache --"
    setup_test_env

    local plugin_dir="${HOME}/.claude/plugins/cache/vendor/auto-claude-skills"
    local version_dir="${plugin_dir}/1.2.3"
    mkdir -p "${version_dir}"
    printf 'cached copy\n' > "${version_dir}/marker.txt"

    local link_output
    link_output="$(bash "${SETUP_DEV_SCRIPT}" 2>&1)"
    assert_contains "setup-dev reports linking" "Linked:" "${link_output}"

    if [ -L "${version_dir}" ]; then
        _record_pass "version directory replaced with symlink"
    else
        _record_fail "version directory replaced with symlink" "expected symlink at ${version_dir}"
    fi

    assert_equals "symlink points at repository root" "${PROJECT_ROOT}" "$(readlink "${version_dir}")"

    local undo_output
    undo_output="$(bash "${SETUP_DEV_SCRIPT}" --undo 2>&1)"
    assert_contains "setup-dev reports restore" "Restored:" "${undo_output}"

    if [ -d "${version_dir}" ] && [ ! -L "${version_dir}" ]; then
        _record_pass "undo restores original directory"
    else
        _record_fail "undo restores original directory" "expected directory restored at ${version_dir}"
    fi

    assert_contains "restored directory keeps original content" "cached copy" "$(cat "${version_dir}/marker.txt")"

    teardown_test_env
}
test_setup_dev_links_and_restores_plugin_cache

print_summary
