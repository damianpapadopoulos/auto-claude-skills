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

    # Optional caller-investigation fields
    inv_layer="$(jq -r '.expected.investigation_layer // empty' "${fixture_file}")"
    if [ -n "${inv_layer}" ]; then
        case "${inv_layer}" in
            application|infrastructure|middleware)
                _record_pass "${fname}: investigation_layer is valid (${inv_layer})"
                ;;
            *)
                _record_fail "${fname}: investigation_layer is valid" "expected application|infrastructure|middleware, got: ${inv_layer}"
                ;;
        esac
    fi

    caller_checked="$(jq -r '.expected.caller_health_checked // empty' "${fixture_file}")"
    if [ -n "${caller_checked}" ]; then
        case "${caller_checked}" in
            true|false)
                _record_pass "${fname}: caller_health_checked is boolean (${caller_checked})"
                ;;
            *)
                _record_fail "${fname}: caller_health_checked is boolean" "got: ${caller_checked}"
                ;;
        esac
    fi

    dom_callers_type="$(jq -r '.expected.dominant_callers_identified | type // empty' "${fixture_file}" 2>/dev/null)"
    if [ -n "${dom_callers_type}" ] && [ "${dom_callers_type}" != "null" ]; then
        if [ "${dom_callers_type}" = "array" ]; then
            caller_count="$(jq '.expected.dominant_callers_identified | length' "${fixture_file}")"
            if [ "${caller_count}" -gt 0 ] 2>/dev/null; then
                _record_pass "${fname}: dominant_callers_identified is array with entries (${caller_count})"
            else
                _record_fail "${fname}: dominant_callers_identified has entries" "array is empty"
            fi
        else
            _record_fail "${fname}: dominant_callers_identified is array" "got type: ${dom_callers_type}"
        fi
    fi

    # Timeline completeness (Improvement A)
    timeline_min="$(jq -r '.expected.timeline_events_min // empty' "${fixture_file}")"
    if [ -n "${timeline_min}" ]; then
        if [ "${timeline_min}" -gt 0 ] 2>/dev/null; then
            _record_pass "${fname}: timeline_events_min is positive (${timeline_min})"
        else
            _record_fail "${fname}: timeline_events_min is positive" "got: ${timeline_min}"
        fi
    fi

    timeline_recovery="$(jq -r '.expected.timeline_has_recovery // empty' "${fixture_file}")"
    if [ -n "${timeline_recovery}" ]; then
        case "${timeline_recovery}" in
            true|false)
                _record_pass "${fname}: timeline_has_recovery is boolean (${timeline_recovery})" ;;
            *)
                _record_fail "${fname}: timeline_has_recovery is boolean" "got: ${timeline_recovery}" ;;
        esac
    fi

    # Timeline precision labels (Improvement A)
    precision="$(jq -r '.expected.timeline_precision_labels // empty' "${fixture_file}")"
    if [ -n "${precision}" ]; then
        case "${precision}" in
            true|false)
                _record_pass "${fname}: timeline_precision_labels is boolean (${precision})" ;;
            *)
                _record_fail "${fname}: timeline_precision_labels is boolean" "got: ${precision}" ;;
        esac
    fi

    # Source analysis status (Improvements B, C, D)
    sa_status="$(jq -r '.expected.source_analysis_status // empty' "${fixture_file}")"
    if [ -n "${sa_status}" ]; then
        case "${sa_status}" in
            skipped|reviewed_no_regression|candidate_found|unavailable)
                _record_pass "${fname}: source_analysis_status valid (${sa_status})" ;;
            *)
                _record_fail "${fname}: source_analysis_status valid" \
                  "expected skipped|reviewed_no_regression|candidate_found|unavailable, got: ${sa_status}" ;;
        esac
    fi

    # Analysis basis (Improvement C) — null is a valid value (Step 4b didn't fire)
    if jq -e '.expected | has("source_analysis_basis")' "${fixture_file}" >/dev/null 2>&1; then
        sa_basis="$(jq -r '.expected.source_analysis_basis | tostring' "${fixture_file}")"
        case "${sa_basis}" in
            primary_frame|bounded_expansion_same_commit|bounded_expansion_same_package)
                _record_pass "${fname}: source_analysis_basis valid (${sa_basis})" ;;
            null)
                _record_pass "${fname}: source_analysis_basis is null (Step 4b skipped)" ;;
            *)
                _record_fail "${fname}: source_analysis_basis valid" "got: ${sa_basis}" ;;
        esac
    fi

    # Cross-reference patterns (Improvement B) — false is a valid value
    if jq -e '.expected | has("cross_reference_patterns")' "${fixture_file}" >/dev/null 2>&1; then
        xref="$(jq -r '.expected.cross_reference_patterns | tostring' "${fixture_file}")"
        case "${xref}" in
            true|false)
                _record_pass "${fname}: cross_reference_patterns is boolean (${xref})" ;;
            *)
                _record_fail "${fname}: cross_reference_patterns is boolean" "got: ${xref}" ;;
        esac
    fi

    # Service attribution (Attribution Rigor upgrade)
    sa_present="$(jq -r '.expected.service_attribution_present // empty' "${fixture_file}")"
    if [ -n "${sa_present}" ]; then
        case "${sa_present}" in
            true|false)
                _record_pass "${fname}: service_attribution_present is boolean (${sa_present})" ;;
            *)
                _record_fail "${fname}: service_attribution_present is boolean" "got: ${sa_present}" ;;
        esac
    fi

    # Co-occurrence: if attribution is present, statuses must exist
    if [ "${sa_present}" = "true" ]; then
        sa_count="$(jq -r '.expected.service_attribution_statuses | length' "${fixture_file}" 2>/dev/null)"
        if [ "${sa_count}" -gt 0 ] 2>/dev/null; then
            _record_pass "${fname}: service_attribution_present=true has statuses (${sa_count})"
        else
            _record_fail "${fname}: service_attribution_present=true requires service_attribution_statuses" \
                "service_attribution_present is true but statuses array is missing or empty"
        fi
    fi

    sa_statuses_type="$(jq -r '.expected.service_attribution_statuses | type // empty' "${fixture_file}" 2>/dev/null)"
    if [ -n "${sa_statuses_type}" ] && [ "${sa_statuses_type}" != "null" ]; then
        if [ "${sa_statuses_type}" = "array" ]; then
            # Each status must be one of the four valid values
            all_valid_sa=true
            for status_val in $(jq -r '.expected.service_attribution_statuses[]' "${fixture_file}" 2>/dev/null); do
                case "${status_val}" in
                    confirmed-dependent|independent|inconclusive|not-investigated) ;;
                    *)
                        _record_fail "${fname}: service_attribution_statuses contains valid value" \
                            "got: ${status_val}"
                        all_valid_sa=false ;;
                esac
            done
            if [ "${all_valid_sa}" = "true" ]; then
                _record_pass "${fname}: service_attribution_statuses all valid"
            fi
        else
            _record_fail "${fname}: service_attribution_statuses is array" "got type: ${sa_statuses_type}"
        fi
    fi
done

print_summary
