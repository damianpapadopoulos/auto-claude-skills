#!/usr/bin/env bash
# run-behavioral-evals.sh — Opt-in behavioral eval runner for incident-analysis v1.
# Not in default run-tests.sh; requires BEHAVIORAL_EVALS=1.
# Bash 3.2 compatible.
set -u

usage() {
    cat >&2 <<'EOF'
usage: BEHAVIORAL_EVALS=1 tests/run-behavioral-evals.sh --scenario <id> [options]

Options:
  --scenario <id>          required — scenario id from the pack
  --pack <path>            override default pack path
                           (default: tests/fixtures/incident-analysis/evals/behavioral.json)
  --variance <N>           run scenario N times and emit per-assertion pass-rate
                           summary (default: 1, single run)
  --variance-report <path> override default variance-report markdown path
                           (default: docs/plans/<today>-cast-eval-variance-report.md)
  -h, --help               show this message

Environment:
  BEHAVIORAL_EVALS=1      required to run; any other value is a no-op
  CLAUDE_BIN              override 'claude' binary (default: 'claude')
  ARTIFACTS_DIR           override artifact output directory (default: 'tests/artifacts')
  SKILL_PATH              override skill file (default: 'skills/incident-analysis/SKILL.md')

Exit codes:
  0  single run: all assertions passed | variance run: report written
  1  single run: at least one assertion failed
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
VARIANCE_N=1
VARIANCE_REPORT=""

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
        --variance)
            VARIANCE_N="${2:-}"
            shift 2
            ;;
        --variance-report)
            VARIANCE_REPORT="${2:-}"
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

# Validate VARIANCE_N is a positive integer
case "${VARIANCE_N}" in
    ''|*[!0-9]*)
        echo "error: --variance must be a positive integer (got '${VARIANCE_N}')" >&2
        exit 2
        ;;
    0)
        echo "error: --variance must be >= 1" >&2
        exit 2
        ;;
esac

# Default report path when --variance > 1 and no explicit path
if [ "${VARIANCE_N}" -gt 1 ] && [ -z "${VARIANCE_REPORT}" ]; then
    VARIANCE_REPORT="docs/plans/$(date +%Y-%m-%d)-cast-eval-variance-report.md"
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
ARTIFACTS_DIR="${ARTIFACTS_DIR:-tests/artifacts}"

# -------- helper: update_counter --------
# Increment pass or fail count for assertion idx in counter file.
# Counter file format: tab-separated, one line per assertion:
#   <idx>\t<pass_count>\t<fail_count>\t<assertion_text>|<description>
# Args: $1 cfile, $2 idx (0-based), $3 "true"|"false"
update_counter() {
    local cfile="$1"
    local idx="$2"
    local passed="$3"
    local tmp="${cfile}.tmp.$$"

    awk -F'\t' -v idx="${idx}" -v passed="${passed}" '
        BEGIN { found=0 }
        $1 == idx {
            found=1
            if (passed == "true") { $2 = $2 + 1 } else { $3 = $3 + 1 }
            printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $4
            next
        }
        { print }
        END {
            if (!found) {
                if (passed == "true") { printf "%s\t1\t0\t\n", idx }
                else { printf "%s\t0\t1\t\n", idx }
            }
        }
    ' "${cfile}" > "${tmp}"
    mv "${tmp}" "${cfile}"
}

# -------- helper: write_variance_report --------
# Emit a markdown summary table from a counter file.
# Args: $1 cfile, $2 report_path, $3 N, $4 scenario_id
write_variance_report() {
    local cfile="$1"
    local report_path="$2"
    local n="$3"
    local sid="$4"

    mkdir -p "$(dirname "${report_path}")"

    {
        echo "# Behavioral Eval Variance Report — ${sid}"
        echo ""
        echo "**Scenario:** \`${sid}\`"
        echo "**Iterations:** ${n}"
        echo "**Captured:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "## Per-assertion pass rates"
        echo ""
        echo "| # | Description | Pass | Fail | Pass rate | Classification |"
        echo "|---|---|---|---|---|---|"

        local stable_threshold flaky_threshold
        stable_threshold="$(awk -v n="${n}" 'BEGIN { print int(n*0.9) }')"
        flaky_threshold="$(awk -v n="${n}" 'BEGIN { print int(n*0.5) }')"

        sort -n "${cfile}" | while IFS=$'\t' read -r idx p f rest; do
            local desc text classification rate
            text="${rest%%|*}"
            desc="${rest#*|}"
            if [ "${n}" -eq 0 ]; then
                rate="—"
                classification="—"
            else
                rate="$(awk -v p="${p}" -v n="${n}" 'BEGIN { printf "%.0f%%", (p/n)*100 }')"
                if [ "${p}" -ge "${stable_threshold}" ]; then
                    classification="stable"
                elif [ "${p}" -ge "${flaky_threshold}" ]; then
                    classification="flaky"
                else
                    classification="broken"
                fi
            fi
            local desc_md="${desc//|/\\|}"
            printf '| %s | %s | %s | %s | %s | %s |\n' \
                "${idx}" "${desc_md}" "${p}" "${f}" "${rate}" "${classification}"
        done

        echo ""
        echo "## Classification thresholds"
        echo ""
        echo "- \`stable\`: ≥ 90% pass rate"
        echo "- \`flaky\`: 50–89% pass rate"
        echo "- \`broken\`: < 50% pass rate"
        echo ""
        echo "## Mutation test (PR2)"
        echo ""
        echo "_Pending — appended after PR2 is executed._"
    } > "${report_path}"
}

# -------- helper: run_one_iteration --------
# Args: $1 iter_idx (1-based), $2 counter_file (empty in single-run mode)
# Returns: 0 if all assertions passed, 1 if any failed, 2 on tooling failure.
run_one_iteration() {
    local iter_idx="$1"
    local counter_file="$2"

    local SCENARIO_PROMPT
    SCENARIO_PROMPT="$(printf '%s' "${SCENARIO_JSON}" | jq -r '.prompt')"
    local CONSTRUCTED_PROMPT="<skill_guidance>
${SKILL_BODY}
</skill_guidance>

<user_request>
${SCENARIO_PROMPT}
</user_request>"

    local start_ts end_ts elapsed claude_exit CLAUDE_JSON
    start_ts="$(date +%s)"
    CLAUDE_JSON="$("${CLAUDE_BIN}" -p --output-format json "${CONSTRUCTED_PROMPT}" 2>&1)"
    claude_exit=$?
    end_ts="$(date +%s)"
    elapsed=$((end_ts - start_ts))

    if [ "${claude_exit}" -ne 0 ]; then
        echo "error: claude invocation failed (exit ${claude_exit}) on iteration ${iter_idx}" >&2
        echo "${CLAUDE_JSON}" >&2
        return 2
    fi

    local RAW_OUTPUT MODEL
    RAW_OUTPUT="$(printf '%s' "${CLAUDE_JSON}" | jq -r '.result // empty')"
    MODEL="$(printf '%s' "${CLAUDE_JSON}" | jq -r '(.model // (.modelUsage | keys[0]? // empty)) // "unknown"')"
    if [ -z "${RAW_OUTPUT}" ]; then
        echo "error: claude response has no 'result' field on iteration ${iter_idx}" >&2
        echo "${CLAUDE_JSON}" >&2
        return 2
    fi

    if [ "${VARIANCE_N}" -gt 1 ]; then
        echo "iter ${iter_idx}/${VARIANCE_N}: ${SCENARIO_ID} (model=${MODEL}, elapsed=${elapsed}s)"
    else
        echo "scenario: ${SCENARIO_ID} (model=${MODEL}, elapsed=${elapsed}s)"
        echo "--- raw output (first 200 chars) ---"
        printf '%s\n' "${RAW_OUTPUT}" | head -c 200
        echo ""
    fi

    local ASSERTION_RESULTS_JSON="[]"
    local ALL_PASSED=1
    local i=0
    while [ "${i}" -lt "${ASSERTION_COUNT}" ]; do
        local a_text a_desc verdict passed
        a_text="$(printf '%s' "${SCENARIO_JSON}" | jq -r ".assertions[${i}].text")"
        a_desc="$(printf '%s' "${SCENARIO_JSON}" | jq -r ".assertions[${i}].description")"

        if printf '%s' "${RAW_OUTPUT}" | grep -E -i -q "${a_text}"; then
            verdict="PASS"
            passed=true
        else
            verdict="FAIL"
            passed=false
            ALL_PASSED=0
        fi

        if [ "${VARIANCE_N}" -eq 1 ]; then
            printf '  %s [%d]: %s  (regex: %s)\n' "${verdict}" "${i}" "${a_desc}" "${a_text}"
        fi

        ASSERTION_RESULTS_JSON="$(
            printf '%s' "${ASSERTION_RESULTS_JSON}" | jq \
                --argjson idx "${i}" \
                --arg desc "${a_desc}" \
                --arg regex "${a_text}" \
                --argjson passed "${passed}" \
                '. + [{index: $idx, description: $desc, regex: $regex, passed: $passed}]'
        )"

        if [ "${VARIANCE_N}" -gt 1 ] && [ -n "${counter_file}" ]; then
            update_counter "${counter_file}" "${i}" "${passed}"
        fi

        i=$((i + 1))
    done

    local artifact_suffix=""
    if [ "${VARIANCE_N}" -gt 1 ]; then
        artifact_suffix="-iter${iter_idx}"
    fi
    local timestamp_utc artifact_file overall_json
    timestamp_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    artifact_file="${ARTIFACTS_DIR}/${SCENARIO_ID}-$(date -u +%Y%m%dT%H%M%SZ)${artifact_suffix}.json"
    mkdir -p "${ARTIFACTS_DIR}"
    if [ "${ALL_PASSED}" = "1" ]; then
        overall_json=true
    else
        overall_json=false
    fi

    jq -n \
        --arg scenario_id "${SCENARIO_ID}" \
        --arg timestamp "${timestamp_utc}" \
        --arg model "${MODEL}" \
        --arg prompt "${SCENARIO_PROMPT}" \
        --arg raw_output "${RAW_OUTPUT}" \
        --argjson assertions "${ASSERTION_RESULTS_JSON}" \
        --argjson overall "${overall_json}" \
        --argjson elapsed "${elapsed}" \
        '{
            scenario_id: $scenario_id,
            timestamp_utc: $timestamp,
            model: $model,
            prompt: $prompt,
            raw_output: $raw_output,
            assertions: $assertions,
            overall_passed: $overall,
            elapsed_seconds: $elapsed
        }' > "${artifact_file}"

    if [ "${VARIANCE_N}" -eq 1 ]; then
        if [ "${ALL_PASSED}" = "1" ]; then
            echo "scenario ${SCENARIO_ID}: OVERALL PASS"
        else
            echo "scenario ${SCENARIO_ID}: OVERALL FAIL"
        fi
        echo "artifact: ${artifact_file}"
    fi

    [ "${ALL_PASSED}" = "1" ] && return 0 || return 1
}

# -------- variance counter setup (only when N>1) --------
COUNTER_FILE=""
if [ "${VARIANCE_N}" -gt 1 ]; then
    COUNTER_FILE="$(mktemp -t cast-eval-counter.XXXXXX)"
    trap 'rm -f "${COUNTER_FILE}"' EXIT
    seed_i=0
    while [ "${seed_i}" -lt "${ASSERTION_COUNT}" ]; do
        a_text_init="$(printf '%s' "${SCENARIO_JSON}" | jq -r ".assertions[${seed_i}].text")"
        a_desc_init="$(printf '%s' "${SCENARIO_JSON}" | jq -r ".assertions[${seed_i}].description")"
        printf '%d\t0\t0\t%s|%s\n' "${seed_i}" "${a_text_init}" "${a_desc_init}" >> "${COUNTER_FILE}"
        seed_i=$((seed_i + 1))
    done
fi

# -------- run iterations --------
ANY_TOOL_FAILURE=0
LAST_RC=0
iter=1
while [ "${iter}" -le "${VARIANCE_N}" ]; do
    if run_one_iteration "${iter}" "${COUNTER_FILE}"; then
        LAST_RC=0
    else
        rc=$?
        if [ "${rc}" -eq 2 ]; then
            ANY_TOOL_FAILURE=1
            break
        fi
        LAST_RC="${rc}"
    fi
    iter=$((iter + 1))
done

# -------- variance summary or single-run exit --------
if [ "${VARIANCE_N}" -gt 1 ] && [ "${ANY_TOOL_FAILURE}" -eq 0 ]; then
    write_variance_report "${COUNTER_FILE}" "${VARIANCE_REPORT}" "${VARIANCE_N}" "${SCENARIO_ID}"
    echo "variance report: ${VARIANCE_REPORT}"
    exit 0
fi

if [ "${ANY_TOOL_FAILURE}" -eq 1 ]; then
    exit 2
fi

exit "${LAST_RC}"
