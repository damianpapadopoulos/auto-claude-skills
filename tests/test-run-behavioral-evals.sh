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

print_summary
