#!/usr/bin/env bash
# tests/test-redact-evidence.sh — Tests for the evidence redaction script
# Bash 3.2 compatible. Sources test-helpers.sh for assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REDACT_SCRIPT="${PROJECT_ROOT}/skills/incident-analysis/scripts/redact-evidence.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-redact-evidence.sh ==="

# ---------------------------------------------------------------------------
# Guard: script must exist and be executable
# ---------------------------------------------------------------------------
if [ ! -f "${REDACT_SCRIPT}" ]; then
    _record_fail "redact-evidence.sh exists" "not found at: ${REDACT_SCRIPT}"
    print_summary
    exit 1
fi

if [ ! -x "${REDACT_SCRIPT}" ]; then
    _record_fail "redact-evidence.sh is executable" "file exists but is not executable"
    print_summary
    exit 1
fi

# ---------------------------------------------------------------------------
# Helper: pipe a string through the redaction script
# ---------------------------------------------------------------------------
redact() {
    printf '%s\n' "$1" | bash "${REDACT_SCRIPT}"
}

# ---------------------------------------------------------------------------
# Test 1: Email address is redacted
# ---------------------------------------------------------------------------
test_email_redaction() {
    local input="Contact user@example.com for details"
    local output
    output="$(redact "${input}")"
    assert_contains     "email: output contains [REDACTED]"       "[REDACTED]"         "${output}"
    assert_not_contains "email: output does not contain address"   "user@example.com"   "${output}"
}

# ---------------------------------------------------------------------------
# Test 2: IPv4 address is redacted
# ---------------------------------------------------------------------------
test_ipv4_redaction() {
    local input="Server 10.0.0.1 responded"
    local output
    output="$(redact "${input}")"
    assert_contains     "ipv4: output contains [REDACTED]"         "[REDACTED]"  "${output}"
    assert_not_contains "ipv4: output does not contain IP address"  "10.0.0.1"   "${output}"
}

# ---------------------------------------------------------------------------
# Test 3: IPv6 address is redacted
# ---------------------------------------------------------------------------
test_ipv6_redaction() {
    local input="Address fe80::1 unreachable"
    local output
    output="$(redact "${input}")"
    assert_contains     "ipv6: output contains [REDACTED]"          "[REDACTED]"  "${output}"
    assert_not_contains "ipv6: output does not contain IP address"   "fe80::1"    "${output}"
}

# ---------------------------------------------------------------------------
# Test 4: Bearer token is redacted (preserves Bearer keyword)
# ---------------------------------------------------------------------------
test_bearer_token_redaction() {
    local input="Bearer eyJhbGciOiJIUzI1NiJ9"
    local output
    output="$(redact "${input}")"
    assert_contains     "bearer: output contains Bearer [REDACTED]"  "Bearer [REDACTED]"          "${output}"
    assert_not_contains "bearer: output does not contain token"       "eyJ"                        "${output}"
}

# ---------------------------------------------------------------------------
# Test 5: Full JWT is redacted
# ---------------------------------------------------------------------------
test_jwt_redaction() {
    local jwt="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
    local input="Token: ${jwt}"
    local output
    output="$(redact "${input}")"
    assert_contains     "jwt: output contains [REDACTED]"       "[REDACTED]"  "${output}"
    assert_not_contains "jwt: output does not contain jwt"       "${jwt}"      "${output}"
}

# ---------------------------------------------------------------------------
# Test 6: API key header is redacted (preserves key name)
# ---------------------------------------------------------------------------
test_api_key_redaction() {
    local input="X-Api-Key: sk-abc123def456"
    local output
    output="$(redact "${input}")"
    assert_contains     "api-key: output contains [REDACTED]"       "[REDACTED]"     "${output}"
    assert_not_contains "api-key: output does not contain key value" "sk-abc123"     "${output}"
}

# ---------------------------------------------------------------------------
# Test 7: Cookie session value is redacted
# ---------------------------------------------------------------------------
test_cookie_redaction() {
    local input="Cookie: session=abc123"
    local output
    output="$(redact "${input}")"
    assert_contains     "cookie: output contains [REDACTED]"          "[REDACTED]"  "${output}"
    assert_not_contains "cookie: output does not contain session value" "abc123"    "${output}"
}

# ---------------------------------------------------------------------------
# Test 8: Secret-like env var value is redacted (preserves var name)
# ---------------------------------------------------------------------------
test_secret_env_var_redaction() {
    local input="DB_PASSWORD=supersecret123"
    local output
    output="$(redact "${input}")"
    assert_contains     "secret-env: output contains DB_PASSWORD=[REDACTED]"  "DB_PASSWORD=[REDACTED]"  "${output}"
    assert_not_contains "secret-env: output does not contain secret value"    "supersecret"             "${output}"
}

# ---------------------------------------------------------------------------
# Test 9: Authorization header is redacted (preserves header name)
# ---------------------------------------------------------------------------
test_auth_header_redaction() {
    local input="Authorization: Basic dXNlcjpwYXNz"
    local output
    output="$(redact "${input}")"
    assert_contains     "auth-header: output contains Authorization: [REDACTED]"  "Authorization: [REDACTED]"  "${output}"
    assert_not_contains "auth-header: output does not contain credential"          "dXNlcjpwYXNz"              "${output}"
}

# ---------------------------------------------------------------------------
# Test 10: Clean log line passes through unchanged
# ---------------------------------------------------------------------------
test_passthrough_clean_line() {
    local input="Normal log message with no secrets"
    local output
    output="$(redact "${input}")"
    assert_equals "passthrough: clean line is unchanged" "${input}" "${output}"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
test_email_redaction
test_ipv4_redaction
test_ipv6_redaction
test_bearer_token_redaction
test_jwt_redaction
test_api_key_redaction
test_cookie_redaction
test_secret_env_var_redaction
test_auth_header_redaction
test_passthrough_clean_line

print_summary
