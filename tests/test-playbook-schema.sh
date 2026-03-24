#!/usr/bin/env bash
# test-playbook-schema.sh — Validates all bundled playbook YAML files
# against the expected schema: mandatory fields, commandable contracts,
# cross-references, and mutual-exclusion invariants.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-playbook-schema.sh ==="

PLAYBOOK_DIR="${PROJECT_ROOT}/skills/incident-analysis/playbooks"

# ---------------------------------------------------------------------------
# Helper: convert YAML to JSON via ruby
# ---------------------------------------------------------------------------
yaml_to_json() {
    ruby -ryaml -rjson -e "puts YAML.load_file(ARGV[0]).to_json" "$1"
}

# ---------------------------------------------------------------------------
# Iterate all 6 playbook files
# ---------------------------------------------------------------------------
for yaml_file in "${PLAYBOOK_DIR}"/*.yaml; do
    filename="$(basename "${yaml_file}")"
    json="$(yaml_to_json "${yaml_file}")"

    # ------------------------------------------------------------------
    # Mandatory fields present in ALL playbooks
    # ------------------------------------------------------------------
    for field in id title category; do
        val="$(printf '%s' "${json}" | jq -r ".${field} // empty")"
        assert_not_empty "${filename}: has ${field}" "${val}"
    done

    # commandable is boolean — use has() to check presence, not truthiness
    commandable_check="$(printf '%s' "${json}" | jq 'has("commandable")')"
    if [ "${commandable_check}" = "true" ]; then
        _record_pass "${filename}: has commandable"
    else
        _record_fail "${filename}: has commandable" "field missing"
    fi

    # signals sub-fields
    for sub in supporting contradicting veto_signals; do
        val="$(printf '%s' "${json}" | jq ".signals.${sub} | type" 2>/dev/null)"
        if [ -n "${val}" ]; then
            _record_pass "${filename}: signals.${sub} present"
        else
            _record_fail "${filename}: signals.${sub} present" "field missing"
        fi
    done

    # contradiction_penalty can be 0, which is falsy — use has() on .signals
    val="$(printf '%s' "${json}" | jq '.signals | has("contradiction_penalty")')"
    if [ "${val}" = "true" ]; then
        _record_pass "${filename}: signals.contradiction_penalty present"
    else
        _record_fail "${filename}: signals.contradiction_penalty present" "field missing"
    fi

    # Timing fields
    for timing in freshness_window_seconds stabilization_delay_seconds validation_window_seconds sample_interval_seconds; do
        val="$(printf '%s' "${json}" | jq ".${timing} // \"MISSING\"")"
        if [ "${val}" = "\"MISSING\"" ]; then
            _record_fail "${filename}: has ${timing}" "field missing"
        else
            _record_pass "${filename}: has ${timing}"
        fi
    done

    # Condition arrays
    for cond in pre_conditions post_conditions hard_stop_conditions stop_conditions; do
        val="$(printf '%s' "${json}" | jq ".${cond} | type" 2>/dev/null)"
        if [ "${val}" = "\"array\"" ]; then
            _record_pass "${filename}: has ${cond}"
        else
            _record_fail "${filename}: has ${cond}" "field missing or not array"
        fi
    done

    # state_fingerprint_fields
    val="$(printf '%s' "${json}" | jq ".state_fingerprint_fields | type" 2>/dev/null)"
    if [ "${val}" = "\"array\"" ]; then
        _record_pass "${filename}: has state_fingerprint_fields"
    else
        _record_fail "${filename}: has state_fingerprint_fields" "field missing or not array"
    fi

    # ------------------------------------------------------------------
    # Commandable-specific fields
    # ------------------------------------------------------------------
    is_commandable="$(printf '%s' "${json}" | jq '.commandable')"

    if [ "${is_commandable}" = "true" ]; then
        # Must have required_tools, parameters, command (with argv and cas_mode), explanation, queries, destructive_action, requires_pre_execution_evidence
        for cmd_field in required_tools parameters explanation queries; do
            val="$(printf '%s' "${json}" | jq ".${cmd_field} // empty")"
            assert_not_empty "${filename}: commandable has ${cmd_field}" "${val}"
        done

        # command.argv
        val="$(printf '%s' "${json}" | jq -r '.command.argv // empty')"
        assert_not_empty "${filename}: commandable has command.argv" "${val}"

        # command.cas_mode
        val="$(printf '%s' "${json}" | jq -r '.command.cas_mode // empty')"
        assert_not_empty "${filename}: commandable has command.cas_mode" "${val}"

        # destructive_action (boolean, can be false — use has() to check presence)
        val="$(printf '%s' "${json}" | jq 'has("destructive_action")')"
        if [ "${val}" = "true" ]; then
            _record_pass "${filename}: commandable has destructive_action"
        else
            _record_fail "${filename}: commandable has destructive_action" "field missing"
        fi

        # requires_pre_execution_evidence (boolean, can be false — use has() to check presence)
        val="$(printf '%s' "${json}" | jq 'has("requires_pre_execution_evidence")')"
        if [ "${val}" = "true" ]; then
            _record_pass "${filename}: commandable has requires_pre_execution_evidence"
        else
            _record_fail "${filename}: commandable has requires_pre_execution_evidence" "field missing"
        fi

        # ------------------------------------------------------------------
        # Condition cross-refs: every query_ref must exist in queries object
        # ------------------------------------------------------------------
        query_refs="$(printf '%s' "${json}" | jq -r '
            [.pre_conditions[], .post_conditions[], .hard_stop_conditions[], .stop_conditions[]]
            | .[].query_ref // empty' 2>/dev/null | sort -u)"

        query_keys="$(printf '%s' "${json}" | jq -r '.queries | keys[]' 2>/dev/null)"

        if [ -n "${query_refs}" ]; then
            IFS_SAVE="$IFS"
            IFS='
'
            for ref in ${query_refs}; do
                IFS="${IFS_SAVE}"
                found=""
                for key in ${query_keys}; do
                    if [ "${ref}" = "${key}" ]; then
                        found="yes"
                        break
                    fi
                done
                if [ -n "${found}" ]; then
                    _record_pass "${filename}: query_ref '${ref}' exists in queries"
                else
                    _record_fail "${filename}: query_ref '${ref}' exists in queries" "not found in queries object"
                fi
            done
            IFS="${IFS_SAVE}"
        fi

    else
        # Investigation-only playbook: must NOT have command, parameters, or required_tools
        for excl_field in command parameters required_tools; do
            val="$(printf '%s' "${json}" | jq ".${excl_field} // empty")"
            if [ -z "${val}" ]; then
                _record_pass "${filename}: investigation-only lacks ${excl_field}"
            else
                _record_fail "${filename}: investigation-only lacks ${excl_field}" "field should not exist"
            fi
        done
    fi

    # ------------------------------------------------------------------
    # Threshold exclusivity: no condition has BOTH threshold and threshold_ref
    # ------------------------------------------------------------------
    both_count="$(printf '%s' "${json}" | jq '
        [.pre_conditions[], .post_conditions[], .hard_stop_conditions[], .stop_conditions[]]
        | map(select(.threshold != null and .threshold_ref != null))
        | length' 2>/dev/null)"
    if [ "${both_count}" = "0" ]; then
        _record_pass "${filename}: no condition has both threshold and threshold_ref"
    else
        _record_fail "${filename}: no condition has both threshold and threshold_ref" "${both_count} conditions violate exclusivity"
    fi

    # ------------------------------------------------------------------
    # Resolver cardinality: parameters with bind_to must have cardinality exactly_one
    # ------------------------------------------------------------------
    if [ "${is_commandable}" = "true" ]; then
        bad_cardinality="$(printf '%s' "${json}" | jq '
            [.parameters[] | select(.resolver.bind_to != null) | select(.resolver.cardinality != "exactly_one")]
            | length' 2>/dev/null)"
        if [ "${bad_cardinality}" = "0" ] || [ -z "${bad_cardinality}" ]; then
            _record_pass "${filename}: bind_to params have cardinality exactly_one"
        else
            _record_fail "${filename}: bind_to params have cardinality exactly_one" "${bad_cardinality} params missing exactly_one"
        fi
    fi

done

print_summary
