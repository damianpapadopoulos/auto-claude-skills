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

# -------- skill loading --------
SKILL_PATH="${SKILL_PATH:-skills/incident-analysis/SKILL.md}"
if [ ! -f "${SKILL_PATH}" ]; then
    echo "error: skill file not found: ${SKILL_PATH}" >&2
    exit 2
fi
SKILL_BODY="$(cat "${SKILL_PATH}")"

# -------- prompt construction --------
SCENARIO_PROMPT="$(printf '%s' "${SCENARIO_JSON}" | jq -r '.prompt')"
CONSTRUCTED_PROMPT="<skill_guidance>
${SKILL_BODY}
</skill_guidance>

<user_request>
${SCENARIO_PROMPT}
</user_request>"

# -------- invoke claude -p --------
start_ts="$(date +%s)"
CLAUDE_JSON="$("${CLAUDE_BIN}" -p --output-format json "${CONSTRUCTED_PROMPT}" 2>&1)"
claude_exit=$?
end_ts="$(date +%s)"
elapsed=$((end_ts - start_ts))

if [ "${claude_exit}" -ne 0 ]; then
    echo "error: claude invocation failed (exit ${claude_exit})" >&2
    echo "${CLAUDE_JSON}" >&2
    exit 2
fi

# -------- parse claude output --------
RAW_OUTPUT="$(printf '%s' "${CLAUDE_JSON}" | jq -r '.result // empty')"
MODEL="$(printf '%s' "${CLAUDE_JSON}" | jq -r '.model // "unknown"')"
if [ -z "${RAW_OUTPUT}" ]; then
    echo "error: claude response has no 'result' field" >&2
    echo "${CLAUDE_JSON}" >&2
    exit 2
fi

# -------- info header --------
echo "scenario: ${SCENARIO_ID} (model=${MODEL}, elapsed=${elapsed}s)"
echo "--- raw output (first 200 chars) ---"
printf '%s\n' "${RAW_OUTPUT}" | head -c 200
echo ""

# -------- assertion evaluation --------
ASSERTION_RESULTS_JSON="[]"
ALL_PASSED=1

i=0
while [ "${i}" -lt "${ASSERTION_COUNT}" ]; do
    a_text="$(printf '%s' "${SCENARIO_JSON}" | jq -r ".assertions[${i}].text")"
    a_desc="$(printf '%s' "${SCENARIO_JSON}" | jq -r ".assertions[${i}].description")"

    # Case-insensitive regex match via grep -E -i. Non-zero exit = no match.
    if printf '%s' "${RAW_OUTPUT}" | grep -E -i -q "${a_text}"; then
        verdict="PASS"
        passed=true
    else
        verdict="FAIL"
        passed=false
        ALL_PASSED=0
    fi

    printf '  %s [%d]: %s  (regex: %s)\n' "${verdict}" "${i}" "${a_desc}" "${a_text}"

    ASSERTION_RESULTS_JSON="$(
        printf '%s' "${ASSERTION_RESULTS_JSON}" | jq \
            --argjson idx "${i}" \
            --arg desc "${a_desc}" \
            --arg regex "${a_text}" \
            --argjson passed "${passed}" \
            '. + [{index: $idx, description: $desc, regex: $regex, passed: $passed}]'
    )"
    i=$((i + 1))
done

# -------- overall verdict --------
if [ "${ALL_PASSED}" = "1" ]; then
    echo "scenario ${SCENARIO_ID}: OVERALL PASS"
    overall=0
else
    echo "scenario ${SCENARIO_ID}: OVERALL FAIL"
    overall=1
fi

# Artifact emission added in Task 5.
exit "${overall}"
