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

# ---------------------------------------------------------------------------
# Invocation: stubbed claude returns a response that matches the assertion
# ---------------------------------------------------------------------------
echo "-- invocation: stubbed claude pass case --"

# Build a canned response that satisfies the 'well-formed-scenario' assertion
# (regex: "exit.code|termination")
CANNED_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-mock-response-$$.txt"
trap 'rm -f "${CANNED_RESPONSE_FILE}"' EXIT
cat > "${CANNED_RESPONSE_FILE}" <<'EOF'
Investigation: the pods are in CrashLoopBackOff with exit code 137,
indicating an OOMKilled termination. Check previous container logs.
EOF

output="$(MOCK_RESPONSE_FILE="${CANNED_RESPONSE_FILE}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
ARTIFACTS_DIR="${TMPDIR:-/tmp}/acs-artifacts-$$" \
SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
bash "${RUNNER}" \
  --scenario well-formed-scenario \
  --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" 2>&1)"
exit_code=$?

assert_equals "exits 0 when invocation completes and assertions pass" "0" "${exit_code}"
assert_contains "output reports PASS for the matching assertion" "PASS" "${output}"
assert_contains "output names the matched scenario id" "well-formed-scenario" "${output}"

# ---------------------------------------------------------------------------
# Verdict: stubbed claude returns a response that does NOT match the assertion
# ---------------------------------------------------------------------------
echo "-- verdict: stubbed claude fail case --"

FAIL_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-mock-fail-$$.txt"
cat > "${FAIL_RESPONSE_FILE}" <<'EOF'
I don't know much about this incident. Could you provide more details?
EOF

output="$(MOCK_RESPONSE_FILE="${FAIL_RESPONSE_FILE}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
ARTIFACTS_DIR="${TMPDIR:-/tmp}/acs-artifacts-$$" \
SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
bash "${RUNNER}" \
  --scenario well-formed-scenario \
  --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" 2>&1)"
exit_code=$?

assert_equals "exits 1 when at least one assertion fails" "1" "${exit_code}"
assert_contains "output reports FAIL for the unmatched assertion" "FAIL" "${output}"
assert_contains "output names the failing assertion description" "Mentions exit codes" "${output}"

rm -f "${FAIL_RESPONSE_FILE}"

# ---------------------------------------------------------------------------
# Artifact: runner writes a JSON file with expected fields
# ---------------------------------------------------------------------------
echo "-- artifact: JSON file with expected fields --"

ART_DIR="${TMPDIR:-/tmp}/acs-artifacts-$$"
rm -rf "${ART_DIR}"
mkdir -p "${ART_DIR}"

ART_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-art-resp-$$.txt"
cat > "${ART_RESPONSE_FILE}" <<'EOF'
Exit code 137 suggests OOMKilled termination.
EOF

MOCK_RESPONSE_FILE="${ART_RESPONSE_FILE}" \
    BEHAVIORAL_EVALS=1 \
    CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
    ARTIFACTS_DIR="${ART_DIR}" \
    SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
    bash "${RUNNER}" \
        --scenario well-formed-scenario \
        --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" >/dev/null 2>&1

# Exactly one JSON artifact should exist in ART_DIR
artifact_file="$(ls "${ART_DIR}"/*.json 2>/dev/null | head -n1)"

assert_not_empty "artifact file was created" "${artifact_file}"
assert_json_valid "artifact is valid JSON" "${artifact_file}"

if [ -n "${artifact_file}" ] && [ -f "${artifact_file}" ]; then
    scenario_id="$(jq -r '.scenario_id // empty' "${artifact_file}")"
    model="$(jq -r '.model // empty' "${artifact_file}")"
    raw_output="$(jq -r '.raw_output // empty' "${artifact_file}")"
    overall="$(jq -r '.overall_passed // empty' "${artifact_file}")"
    assertion_count="$(jq '.assertions | length' "${artifact_file}")"

    assert_equals "artifact scenario_id matches" "well-formed-scenario" "${scenario_id}"
    assert_contains "artifact model field is populated" "mock" "${model}"
    assert_not_contains "artifact model is not 'unknown' (parser reaches real .model or .modelUsage key)" "unknown" "${model}"
    assert_contains "artifact raw_output contains captured text" "137" "${raw_output}"
    assert_equals "artifact overall_passed is true" "true" "${overall}"
    assert_equals "artifact records one assertion" "1" "${assertion_count}"
fi

rm -f "${ART_RESPONSE_FILE}"
rm -rf "${ART_DIR}"

# ---------------------------------------------------------------------------
# Sandbox: runner passes --disallowedTools to deny Edit/Write/Bash in inner
# claude -p invocation. Prevents the inner agent from mutating committed
# files during fixture runs (see feedback_inner_claude_p_tool_access.md).
# ---------------------------------------------------------------------------
echo "-- sandbox: --disallowedTools is passed to inner claude -p --"

SANDBOX_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-sandbox-resp-$$.txt"
SANDBOX_ARGS_FILE="${TMPDIR:-/tmp}/acs-sandbox-args-$$.txt"
SANDBOX_ART_DIR="${TMPDIR:-/tmp}/acs-sandbox-art-$$"
# Compose with the earlier trap (line 85) — bash trap-EXIT is single-slot,
# so the earlier CANNED_RESPONSE_FILE must be re-listed here or it leaks.
trap 'rm -f "${CANNED_RESPONSE_FILE}" "${SANDBOX_RESPONSE_FILE}" "${SANDBOX_ARGS_FILE}"; rm -rf "${SANDBOX_ART_DIR}"' EXIT
cat > "${SANDBOX_RESPONSE_FILE}" <<'EOF'
Exit code 137 indicates OOMKilled termination.
EOF

MOCK_RESPONSE_FILE="${SANDBOX_RESPONSE_FILE}" \
    MOCK_ARGS_FILE="${SANDBOX_ARGS_FILE}" \
    BEHAVIORAL_EVALS=1 \
    CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
    ARTIFACTS_DIR="${SANDBOX_ART_DIR}" \
    SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
    bash "${RUNNER}" \
        --scenario well-formed-scenario \
        --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" >/dev/null 2>&1

# Each argv arrives on its own line in MOCK_ARGS_FILE. Checking the line
# *immediately after* --disallowedTools avoids matching the prompt body,
# which contains "Edit"/"Write"/"Bash" as ordinary text from the skill.
flag_line="$(grep -nxF -- '--disallowedTools' "${SANDBOX_ARGS_FILE}" 2>/dev/null | head -n1 | cut -d: -f1)"
sandbox_value=""
if [ -n "${flag_line}" ]; then
    sandbox_value="$(sed -n "$((flag_line + 1))p" "${SANDBOX_ARGS_FILE}")"
fi

assert_not_empty "runner passes --disallowedTools flag as standalone argv" "${flag_line}"
assert_contains "sandbox value denies Edit tool" "Edit" "${sandbox_value}"
assert_contains "sandbox value denies Write tool" "Write" "${sandbox_value}"
assert_contains "sandbox value denies Bash tool" "Bash" "${sandbox_value}"

print_summary
