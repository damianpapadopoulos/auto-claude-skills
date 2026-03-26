#!/usr/bin/env bash
# test-incident-analysis-output.sh — Output quality validation for incident-analysis skill.
# Loads fixture files from tests/fixtures/incident-analysis/ and validates
# expected output fields. Fixtures must come from real incident postmortems.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-incident-analysis-output.sh ==="

FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/incident-analysis"

# ---------------------------------------------------------------------------
# Check fixture directory exists
# ---------------------------------------------------------------------------
if [ ! -d "${FIXTURE_DIR}" ]; then
    echo "  SKIP: No fixture directory at ${FIXTURE_DIR}"
    print_summary
    exit 0
fi

# ---------------------------------------------------------------------------
# Count fixtures (skip README)
# ---------------------------------------------------------------------------
fixture_count=0
for f in "${FIXTURE_DIR}"/*.json; do
    [ -f "${f}" ] || continue
    fixture_count=$((fixture_count + 1))
done

if [ "${fixture_count}" -eq 0 ]; then
    echo "  SKIP: No .json fixtures in ${FIXTURE_DIR}"
    echo "  NOTE: Fixtures must come from real incident postmortems (see README.md)"
    print_summary
    exit 0
fi

echo "  Found ${fixture_count} fixture(s)"

# ---------------------------------------------------------------------------
# Validate fixture schema
# ---------------------------------------------------------------------------
for fixture_file in "${FIXTURE_DIR}"/*.json; do
    [ -f "${fixture_file}" ] || continue
    fname="$(basename "${fixture_file}")"

    # Must be valid JSON
    if jq empty "${fixture_file}" 2>/dev/null; then
        _record_pass "${fname}: valid JSON"
    else
        _record_fail "${fname}: valid JSON" "JSON parse error"
        continue
    fi

    # Required fields
    for field in id description input expected; do
        val="$(jq -r ".${field} // empty" "${fixture_file}")"
        assert_not_empty "${fname}: has ${field}" "${val}"
    done

    # Input sub-fields
    for sub in service environment symptoms; do
        val="$(jq -r ".input.${sub} // empty" "${fixture_file}")"
        assert_not_empty "${fname}: input has ${sub}" "${val}"
    done

    # Expected must have at least one assertion field
    exp_keys="$(jq -r '.expected | keys | length' "${fixture_file}")"
    if [ "${exp_keys}" -gt 0 ] 2>/dev/null; then
        _record_pass "${fname}: expected has assertion fields (${exp_keys})"
    else
        _record_fail "${fname}: expected has assertion fields" "empty expected object"
    fi
done

print_summary
