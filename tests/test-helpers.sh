#!/usr/bin/env bash
# test-helpers.sh — Source-able test helper library for auto-claude-skills
# Bash 3.2 compatible (macOS default). No external deps beyond bash and jq.

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAIL_MESSAGES=""

# ---------------------------------------------------------------------------
# Environment setup / teardown
# ---------------------------------------------------------------------------
setup_test_env() {
    TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/acs-test.XXXXXXXX")"

    TEST_HOME="${TEST_TMPDIR}/home"
    TEST_PLUGIN_CACHE="${TEST_HOME}/.claude/plugin-cache"
    TEST_USER_SKILLS="${TEST_HOME}/.claude/user-skills"
    TEST_REGISTRY_CACHE="${TEST_HOME}/.claude/registry-cache"
    TEST_USER_CONFIG="${TEST_HOME}/.claude/config.json"

    mkdir -p "${TEST_PLUGIN_CACHE}"
    mkdir -p "${TEST_USER_SKILLS}"
    mkdir -p "${TEST_REGISTRY_CACHE}"
    mkdir -p "$(dirname "${TEST_USER_CONFIG}")"

    export HOME="${TEST_HOME}"
    export CLAUDE_PLUGIN_ROOT="${TEST_HOME}/.claude"

    export TEST_TMPDIR TEST_HOME TEST_PLUGIN_CACHE TEST_USER_SKILLS
    export TEST_REGISTRY_CACHE TEST_USER_CONFIG
}

teardown_test_env() {
    if [ -n "${TEST_TMPDIR:-}" ] && [ -d "${TEST_TMPDIR}" ]; then
        rm -rf "${TEST_TMPDIR}"
    fi
    unset TEST_TMPDIR TEST_HOME TEST_PLUGIN_CACHE TEST_USER_SKILLS
    unset TEST_REGISTRY_CACHE TEST_USER_CONFIG
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

# _record_pass description
_record_pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "  PASS: %s\n" "$1"
}

# _record_fail description detail
_record_fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "  FAIL: %s\n" "$1"
    if [ -n "${2:-}" ]; then
        printf "        %s\n" "$2"
    fi
    if [ -n "${FAIL_MESSAGES}" ]; then
        FAIL_MESSAGES="${FAIL_MESSAGES}
"
    fi
    FAIL_MESSAGES="${FAIL_MESSAGES}FAIL: $1"
}

# assert_equals description expected actual
assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [ "${expected}" = "${actual}" ]; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "expected: '${expected}', got: '${actual}'"
    fi
}

# assert_contains description needle haystack
assert_contains() {
    local description="$1"
    local needle="$2"
    local haystack="$3"

    case "${haystack}" in
        *"${needle}"*)
            _record_pass "${description}"
            ;;
        *)
            _record_fail "${description}" "expected to contain: '${needle}'"
            ;;
    esac
}

# assert_not_contains description needle haystack
assert_not_contains() {
    local description="$1"
    local needle="$2"
    local haystack="$3"

    case "${haystack}" in
        *"${needle}"*)
            _record_fail "${description}" "expected NOT to contain: '${needle}'"
            ;;
        *)
            _record_pass "${description}"
            ;;
    esac
}

# assert_json_valid description file
assert_json_valid() {
    local description="$1"
    local file="$2"

    if [ ! -f "${file}" ]; then
        _record_fail "${description}" "file does not exist: ${file}"
        return
    fi

    if jq empty "${file}" >/dev/null 2>&1; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "invalid JSON in: ${file}"
    fi
}

# assert_file_exists description file
assert_file_exists() {
    local description="$1"
    local file="$2"

    if [ -f "${file}" ]; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "file not found: ${file}"
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "=============================="
    printf "Tests run:    %d\n" "${TESTS_RUN}"
    printf "Tests passed: %d\n" "${TESTS_PASSED}"
    printf "Tests failed: %d\n" "${TESTS_FAILED}"
    echo "=============================="

    if [ "${TESTS_FAILED}" -gt 0 ]; then
        echo ""
        echo "Failures:"
        printf "%s\n" "${FAIL_MESSAGES}"
        return 1
    fi

    echo "All tests passed."
    return 0
}
