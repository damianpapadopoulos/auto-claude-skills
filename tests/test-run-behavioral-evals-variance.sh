#!/usr/bin/env bash
# test-run-behavioral-evals-variance.sh — Hermetic self-test for the --variance N
# mode added to tests/run-behavioral-evals.sh. Stubs `claude` via CLAUDE_BIN.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-run-behavioral-evals-variance.sh ==="

RUNNER="${PROJECT_ROOT}/tests/run-behavioral-evals.sh"

# Build a tmpdir with a stub claude that always returns CAST-matching output
TMPDIR_TEST="$(mktemp -d -t cast-variance-test.XXXXXX)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

# Stub claude — emits a 'result' field that matches every CAST assertion regex
cat > "${TMPDIR_TEST}/claude" <<'STUBEOF'
#!/usr/bin/env bash
cat <<JSONEOF
{
  "type": "result",
  "is_error": false,
  "duration_ms": 1000,
  "result": "Mental model gaps Systemic factors Safety Culture Communication/Coordination Management of Change Safety Information System Environmental Change cast-framing.md believed actual was",
  "modelUsage": {
    "claude-test-stub": {"inputTokens": 10, "outputTokens": 20}
  }
}
JSONEOF
STUBEOF
chmod +x "${TMPDIR_TEST}/claude"

ARTIFACTS_DIR_TEST="${TMPDIR_TEST}/artifacts"
REPORT_PATH_TEST="${TMPDIR_TEST}/variance-report.md"

# ---------------------------------------------------------------------------
# Variance mode (N=3) with all-pass stub
# ---------------------------------------------------------------------------
echo "-- variance N=3 happy path --"

ARTIFACTS_DIR="${ARTIFACTS_DIR_TEST}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${TMPDIR_TEST}/claude" \
bash "${RUNNER}" \
    --scenario cast-systemic-factors-coverage \
    --variance 3 \
    --variance-report "${REPORT_PATH_TEST}" \
    > "${TMPDIR_TEST}/run.log" 2>&1
runner_exit=$?

assert_equals "variance runner exits 0" "0" "${runner_exit}"

artifact_count="$(find "${ARTIFACTS_DIR_TEST}" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
assert_equals "3 iteration artifacts written" "3" "${artifact_count}"

assert_file_exists "variance report file written" "${REPORT_PATH_TEST}"

if [ -f "${REPORT_PATH_TEST}" ]; then
    report_content="$(cat "${REPORT_PATH_TEST}")"
    assert_contains "report has per-assertion table header" \
        "| # | Description | Pass | Fail | Pass rate | Classification |" \
        "${report_content}"

    # With stub-claude returning all-pass, every assertion classifies 'stable'
    stable_count="$(printf '%s' "${report_content}" | grep -c -F " stable " 2>/dev/null || true)"
    if [ "${stable_count:-0}" -ge 9 ]; then
        _record_pass "all 9 assertions classify as stable when stub passes all"
    else
        _record_fail "all 9 assertions classify as stable" "stable_count=${stable_count:-0}"
    fi

    assert_contains "report has PR2 placeholder" \
        "Pending — appended after PR2" \
        "${report_content}"
fi

# ---------------------------------------------------------------------------
# Argument validation: non-integer --variance
# ---------------------------------------------------------------------------
echo "-- guard: --variance abc --"

ARTIFACTS_DIR="${ARTIFACTS_DIR_TEST}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${TMPDIR_TEST}/claude" \
bash "${RUNNER}" \
    --scenario cast-systemic-factors-coverage \
    --variance abc \
    > "${TMPDIR_TEST}/bad.log" 2>&1
bad_exit=$?

assert_equals "non-integer --variance rejected with exit 2" "2" "${bad_exit}"

# ---------------------------------------------------------------------------
# Argument validation: --variance 0
# ---------------------------------------------------------------------------
echo "-- guard: --variance 0 --"

ARTIFACTS_DIR="${ARTIFACTS_DIR_TEST}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${TMPDIR_TEST}/claude" \
bash "${RUNNER}" \
    --scenario cast-systemic-factors-coverage \
    --variance 0 \
    > "${TMPDIR_TEST}/zero.log" 2>&1
zero_exit=$?

assert_equals "--variance 0 rejected with exit 2" "2" "${zero_exit}"

# ---------------------------------------------------------------------------
# Single-run regression (default --variance 1) still works after refactor
# ---------------------------------------------------------------------------
echo "-- regression: single-run mode --"

ARTIFACTS_DIR="${ARTIFACTS_DIR_TEST}/single" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${TMPDIR_TEST}/claude" \
bash "${RUNNER}" \
    --scenario cast-systemic-factors-coverage \
    > "${TMPDIR_TEST}/single.log" 2>&1
single_exit=$?

assert_equals "single-run mode exits 0 on all-pass output" "0" "${single_exit}"

print_summary
