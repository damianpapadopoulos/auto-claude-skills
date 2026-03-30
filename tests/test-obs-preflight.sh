#!/usr/bin/env bash
# test-obs-preflight.sh — Tests for on-demand observability preflight
# Bash 3.2 compatible. Sources test-helpers.sh for assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

. "${SCRIPT_DIR}/test-helpers.sh"

PREFLIGHT="${PROJECT_ROOT}/scripts/obs-preflight.sh"

echo "=== test-obs-preflight.sh ==="

# ---------------------------------------------------------------------------
# 1. Script exits 0 and produces valid JSON even when tools are missing
# ---------------------------------------------------------------------------
test_missing_tools_produce_valid_json() {
    echo "-- test: missing tools produce valid JSON --"
    setup_test_env

    # Override PATH to ensure gcloud/kubectl are not found
    local output
    output="$(PATH=/usr/bin:/bin bash "${PREFLIGHT}" 2>/dev/null)"

    assert_not_empty "output is non-empty" "${output}"

    local tmpfile="${TEST_TMPDIR}/preflight.json"
    printf '%s' "${output}" > "${tmpfile}"
    assert_json_valid "output is valid JSON" "${tmpfile}"

    local gcloud_status
    gcloud_status="$(printf '%s' "${output}" | jq -r '.gcloud' 2>/dev/null)"
    assert_equals "gcloud is missing" "missing" "${gcloud_status}"

    local kubectl_status
    kubectl_status="$(printf '%s' "${output}" | jq -r '.kubectl' 2>/dev/null)"
    assert_equals "kubectl is missing" "missing" "${kubectl_status}"

    local obs_mcp_status
    obs_mcp_status="$(printf '%s' "${output}" | jq -r '.observability_mcp' 2>/dev/null)"
    assert_equals "observability_mcp is unavailable" "unavailable" "${obs_mcp_status}"

    teardown_test_env
}
test_missing_tools_produce_valid_json

# ---------------------------------------------------------------------------
# 2. MCP detection reads from ~/.claude.json
# ---------------------------------------------------------------------------
test_mcp_detection_from_claude_json() {
    echo "-- test: MCP detection reads ~/.claude.json --"
    setup_test_env

    # Create a fake ~/.claude.json with gcp-observability configured
    cat > "${HOME}/.claude.json" << 'MCPEOF'
{"mcpServers":{"gcp-observability":{"command":"npx","args":["@anthropic/gcp-observability-mcp"]}}}
MCPEOF

    local output
    output="$(PATH=/usr/bin:/bin bash "${PREFLIGHT}" 2>/dev/null)"

    local obs_mcp_status
    obs_mcp_status="$(printf '%s' "${output}" | jq -r '.observability_mcp' 2>/dev/null)"
    assert_equals "observability_mcp is configured" "configured" "${obs_mcp_status}"

    teardown_test_env
}
test_mcp_detection_from_claude_json

# ---------------------------------------------------------------------------
# 3. gcloud present but unauthenticated
# ---------------------------------------------------------------------------
test_gcloud_unauthenticated() {
    echo "-- test: gcloud present but unauthenticated --"
    setup_test_env

    # Create a fake gcloud that exits 1 on auth check
    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/gcloud" << 'GCEOF'
#!/bin/bash
if [[ "$*" == *"auth list"* ]]; then
    echo "No credentialed accounts."
    exit 1
fi
exit 0
GCEOF
    chmod +x "${TEST_TMPDIR}/bin/gcloud"

    local output
    output="$(PATH="${TEST_TMPDIR}/bin:/usr/bin:/bin" bash "${PREFLIGHT}" 2>/dev/null)"

    local gcloud_status
    gcloud_status="$(printf '%s' "${output}" | jq -r '.gcloud' 2>/dev/null)"
    assert_equals "gcloud is unauthenticated" "unauthenticated" "${gcloud_status}"

    teardown_test_env
}
test_gcloud_unauthenticated

# ---------------------------------------------------------------------------
# 4. gcloud present and authenticated
# ---------------------------------------------------------------------------
test_gcloud_authenticated() {
    echo "-- test: gcloud present and authenticated --"
    setup_test_env

    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/gcloud" << 'GCEOF'
#!/bin/bash
if [[ "$*" == *"auth list"* ]]; then
    echo "       ACTIVE  ACCOUNT"
    echo "*      user@example.com"
    exit 0
fi
exit 0
GCEOF
    chmod +x "${TEST_TMPDIR}/bin/gcloud"

    local output
    output="$(PATH="${TEST_TMPDIR}/bin:/usr/bin:/bin" bash "${PREFLIGHT}" 2>/dev/null)"

    local gcloud_status
    gcloud_status="$(printf '%s' "${output}" | jq -r '.gcloud' 2>/dev/null)"
    assert_equals "gcloud is ready" "ready" "${gcloud_status}"

    teardown_test_env
}
test_gcloud_authenticated

# ---------------------------------------------------------------------------
# 5. kubectl present but unreachable
# ---------------------------------------------------------------------------
test_kubectl_unreachable() {
    echo "-- test: kubectl present but unreachable --"
    setup_test_env

    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/kubectl" << 'KEOF'
#!/bin/bash
exit 1
KEOF
    chmod +x "${TEST_TMPDIR}/bin/kubectl"

    local output
    output="$(PATH="${TEST_TMPDIR}/bin:/usr/bin:/bin" bash "${PREFLIGHT}" 2>/dev/null)"

    local kubectl_status
    kubectl_status="$(printf '%s' "${output}" | jq -r '.kubectl' 2>/dev/null)"
    assert_equals "kubectl is unreachable" "unreachable" "${kubectl_status}"

    teardown_test_env
}
test_kubectl_unreachable

# ---------------------------------------------------------------------------
# 6. Summary line present
# ---------------------------------------------------------------------------
test_summary_line() {
    echo "-- test: summary line present --"
    setup_test_env

    local output
    output="$(PATH=/usr/bin:/bin bash "${PREFLIGHT}" 2>/dev/null)"

    local summary
    summary="$(printf '%s' "${output}" | jq -r '.summary' 2>/dev/null)"
    assert_not_empty "summary is non-empty" "${summary}"

    teardown_test_env
}
test_summary_line

# ---------------------------------------------------------------------------
# 7. Exit code is always 0 (fail-open)
# ---------------------------------------------------------------------------
test_exit_code_always_zero() {
    echo "-- test: exit code is always 0 --"
    setup_test_env

    PATH=/usr/bin:/bin bash "${PREFLIGHT}" >/dev/null 2>&1
    local rc=$?
    assert_equals "exit code is 0" "0" "${rc}"

    teardown_test_env
}
test_exit_code_always_zero

# ---------------------------------------------------------------------------
print_summary
