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

SIGNAL_FILE="${PROJECT_ROOT}/skills/incident-analysis/signals.yaml"
signal_json="$(yaml_to_json "${SIGNAL_FILE}")"

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

    # ------------------------------------------------------------------
    # Disambiguation probe validation (optional field)
    # ------------------------------------------------------------------
    has_probe="$(printf '%s' "${json}" | jq 'has("disambiguation_probe")')"

    if [ "${has_probe}" = "true" ]; then
        # query_ref must reference a valid key in queries
        probe_ref="$(printf '%s' "${json}" | jq -r '.disambiguation_probe.query_ref // empty')"
        assert_not_empty "${filename}: disambiguation_probe has query_ref" "${probe_ref}"

        if [ -n "${probe_ref}" ]; then
            has_queries="$(printf '%s' "${json}" | jq 'has("queries")')"
            if [ "${has_queries}" = "true" ]; then
                ref_exists="$(printf '%s' "${json}" | jq --arg ref "${probe_ref}" '.queries | has($ref)')"
                if [ "${ref_exists}" = "true" ]; then
                    _record_pass "${filename}: probe query_ref '${probe_ref}' exists in queries"
                else
                    _record_fail "${filename}: probe query_ref '${probe_ref}' exists in queries" "not found in queries object"
                fi
            else
                _record_fail "${filename}: probe query_ref '${probe_ref}' exists in queries" "playbook has no queries section"
            fi
        fi

        # resolves_signals must be non-empty array
        sig_count="$(printf '%s' "${json}" | jq '.disambiguation_probe.resolves_signals | length' 2>/dev/null)"
        if [ -n "${sig_count}" ] && [ "${sig_count}" -gt 0 ] 2>/dev/null; then
            _record_pass "${filename}: disambiguation_probe.resolves_signals is non-empty (${sig_count})"
        else
            _record_fail "${filename}: disambiguation_probe.resolves_signals is non-empty" "empty or missing"
        fi

        # Probe query must declare max_results (payload cap)
        if [ -n "${probe_ref}" ] && [ "${has_queries}" = "true" ]; then
            max_r="$(printf '%s' "${json}" | jq --arg ref "${probe_ref}" '.queries[$ref].params.max_results // empty')"
            if [ -n "${max_r}" ]; then
                _record_pass "${filename}: probe query '${probe_ref}' has max_results cap"
            else
                _record_fail "${filename}: probe query '${probe_ref}' has max_results cap" "payload cap missing"
            fi
        fi

        # Probe query kind must be read-only (not kubectl apply/patch/delete/scale)
        if [ -n "${probe_ref}" ] && [ "${has_queries}" = "true" ]; then
            probe_kind="$(printf '%s' "${json}" | jq -r --arg ref "${probe_ref}" '.queries[$ref].kind // empty')"
            probe_argv="$(printf '%s' "${json}" | jq -r --arg ref "${probe_ref}" '(.queries[$ref].command_argv // []) | join(" ")' 2>/dev/null)"
            write_cmd=""
            case "${probe_argv}" in
                *"kubectl apply"*|*"kubectl patch"*|*"kubectl delete"*|*"kubectl scale"*) write_cmd="yes" ;;
            esac
            if [ -z "${write_cmd}" ]; then
                _record_pass "${filename}: probe query '${probe_ref}' is read-only"
            else
                _record_fail "${filename}: probe query '${probe_ref}' is read-only" "contains write command: ${probe_argv}"
            fi
        fi

        # Warn if resolves_signals references a signal with distribution or ratio method
        resolve_sigs="$(printf '%s' "${json}" | jq -r '.disambiguation_probe.resolves_signals[]' 2>/dev/null)"
        if [ -n "${resolve_sigs}" ]; then
            IFS_SAVE="$IFS"
            IFS='
'
            for rsig in ${resolve_sigs}; do
                IFS="${IFS_SAVE}"
                sig_method="$(printf '%s' "${signal_json}" | jq -r --arg s "${rsig}" '.signals[$s].detection.method // empty')"
                case "${sig_method}" in
                    distribution|ratio)
                        printf "  WARN: %s: resolves_signals '%s' uses '%s' method (cannot be resolved from single probe)\n" "${filename}" "${rsig}" "${sig_method}"
                        ;;
                esac
            done
            IFS="${IFS_SAVE}"
        fi
    fi

done

print_summary
