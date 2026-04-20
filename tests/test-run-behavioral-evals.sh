#!/usr/bin/env bash
# test-run-behavioral-evals.sh — Hermetic self-tests for the behavioral eval runner.
# Bash 3.2 compatible. No network, no real claude invocation.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER="${PROJECT_ROOT}/tests/run-behavioral-evals.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-run-behavioral-evals.sh ==="

# ---------------------------------------------------------------------------
# Guard: missing BEHAVIORAL_EVALS env var
# ---------------------------------------------------------------------------
echo "-- guard: missing BEHAVIORAL_EVALS --"

unset BEHAVIORAL_EVALS
output="$(bash "${RUNNER}" --scenario anything 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when BEHAVIORAL_EVALS is unset" "2" "${exit_code}"
assert_contains "prints opt-in notice naming BEHAVIORAL_EVALS" "BEHAVIORAL_EVALS" "${output}"

# ---------------------------------------------------------------------------
# Guard: missing claude binary
# ---------------------------------------------------------------------------
echo "-- guard: missing claude binary --"

BEHAVIORAL_EVALS=1 CLAUDE_BIN=/nonexistent/claude-xyz \
    output="$(bash "${RUNNER}" --scenario well-formed-scenario \
              --pack tests/fixtures/behavioral-runner/scenarios.json 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when claude binary missing" "2" "${exit_code}"
assert_contains "names the missing binary in error" "claude" "${output}"

# ---------------------------------------------------------------------------
# Guard: missing --scenario argument
# ---------------------------------------------------------------------------
echo "-- guard: missing --scenario --"

output="$(BEHAVIORAL_EVALS=1 bash "${RUNNER}" 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when --scenario is missing" "2" "${exit_code}"
assert_contains "error names the missing flag" "--scenario" "${output}"

# ---------------------------------------------------------------------------
# Guard: scenario id not found in pack
# ---------------------------------------------------------------------------
echo "-- guard: scenario id not in pack --"

output="$(BEHAVIORAL_EVALS=1 bash "${RUNNER}" \
          --scenario does-not-exist \
          --pack tests/fixtures/behavioral-runner/scenarios.json 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when scenario id unknown" "2" "${exit_code}"
assert_contains "error names the unknown id" "does-not-exist" "${output}"

# ---------------------------------------------------------------------------
# Guard: scenario malformed (missing assertions field)
# ---------------------------------------------------------------------------
echo "-- guard: malformed scenario --"

output="$(BEHAVIORAL_EVALS=1 bash "${RUNNER}" \
          --scenario malformed-missing-assertions \
          --pack tests/fixtures/behavioral-runner/scenarios.json 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when scenario is malformed" "2" "${exit_code}"
assert_contains "error names the missing field" "assertions" "${output}"

print_summary
