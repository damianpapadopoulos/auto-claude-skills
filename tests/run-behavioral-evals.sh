#!/usr/bin/env bash
# run-behavioral-evals.sh — Opt-in behavioral eval runner for incident-analysis v1.
# Not in default run-tests.sh; requires BEHAVIORAL_EVALS=1.
# Bash 3.2 compatible.
set -u

usage() {
    cat >&2 <<'EOF'
usage: BEHAVIORAL_EVALS=1 tests/run-behavioral-evals.sh --scenario <id> [--pack <path>]

Environment:
  BEHAVIORAL_EVALS=1      required to run; any other value is a no-op
  CLAUDE_BIN              override 'claude' binary (default: 'claude')
  ARTIFACTS_DIR           override artifact output directory (default: 'tests/artifacts')
  SKILL_PATH              override skill file (default: 'skills/incident-analysis/SKILL.md')

Exit codes:
  0  all assertions passed
  1  at least one assertion failed
  2  guard / schema / precondition failure
EOF
}

if [ "${BEHAVIORAL_EVALS:-0}" != "1" ]; then
    echo "error: BEHAVIORAL_EVALS=1 required to run this runner. See usage:" >&2
    usage
    exit 2
fi

# -------- argument parsing --------
SCENARIO_ID=""
PACK_PATH="tests/fixtures/incident-analysis/evals/behavioral.json"

while [ $# -gt 0 ]; do
    case "$1" in
        --scenario)
            SCENARIO_ID="${2:-}"
            shift 2
            ;;
        --pack)
            PACK_PATH="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [ -z "${SCENARIO_ID}" ]; then
    echo "error: --scenario <id> is required" >&2
    usage
    exit 2
fi

# -------- claude binary check --------
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
if ! command -v "${CLAUDE_BIN}" >/dev/null 2>&1; then
    echo "error: claude binary not found on PATH (CLAUDE_BIN='${CLAUDE_BIN}')" >&2
    exit 2
fi

# -------- pack existence + JSON validity --------
if [ ! -f "${PACK_PATH}" ]; then
    echo "error: pack file not found: ${PACK_PATH}" >&2
    exit 2
fi
if ! jq empty "${PACK_PATH}" >/dev/null 2>&1; then
    echo "error: pack file is not valid JSON: ${PACK_PATH}" >&2
    exit 2
fi

# -------- scenario lookup --------
SCENARIO_JSON="$(jq --arg id "${SCENARIO_ID}" '.[] | select(.id == $id)' "${PACK_PATH}")"
if [ -z "${SCENARIO_JSON}" ]; then
    echo "error: scenario id '${SCENARIO_ID}' not found in pack ${PACK_PATH}" >&2
    exit 2
fi

# -------- scenario schema validation --------
for field in id prompt expected_behavior assertions; do
    if ! printf '%s' "${SCENARIO_JSON}" | jq -e ". | has(\"${field}\")" >/dev/null 2>&1; then
        echo "error: scenario '${SCENARIO_ID}' missing required field: ${field}" >&2
        exit 2
    fi
done

ASSERTION_COUNT="$(printf '%s' "${SCENARIO_JSON}" | jq '.assertions | length')"
if [ "${ASSERTION_COUNT}" -lt 1 ]; then
    echo "error: scenario '${SCENARIO_ID}' has empty assertions array" >&2
    exit 2
fi

# Subsequent tasks: skill loading + invocation + evaluation + artifact.
echo "error: runner body not yet implemented (post-preflight)" >&2
exit 2
