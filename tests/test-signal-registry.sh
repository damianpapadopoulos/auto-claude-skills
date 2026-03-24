#!/usr/bin/env bash
# test-signal-registry.sh — Cross-reference validation between signals.yaml,
# playbooks, compatibility.yaml, and SKILL.md.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-signal-registry.sh ==="

SIGNAL_FILE="${PROJECT_ROOT}/skills/incident-analysis/signals.yaml"
COMPAT_FILE="${PROJECT_ROOT}/skills/incident-analysis/compatibility.yaml"
PLAYBOOK_DIR="${PROJECT_ROOT}/skills/incident-analysis/playbooks"
SKILL_FILE="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md"

# ---------------------------------------------------------------------------
# Helper: convert YAML to JSON via ruby
# ---------------------------------------------------------------------------
yaml_to_json() {
    ruby -ryaml -rjson -e "puts YAML.load_file(ARGV[0]).to_json" "$1"
}

# ---------------------------------------------------------------------------
# Load signals registry
# ---------------------------------------------------------------------------
signal_json="$(yaml_to_json "${SIGNAL_FILE}")"
signal_keys="$(printf '%s' "${signal_json}" | jq -r '.signals | keys[]')"

# ---------------------------------------------------------------------------
# For every signal referenced in any playbook, assert it exists in signals.yaml
# ---------------------------------------------------------------------------
for yaml_file in "${PLAYBOOK_DIR}"/*.yaml; do
    filename="$(basename "${yaml_file}")"
    pb_json="$(yaml_to_json "${yaml_file}")"

    # Collect all signal IDs from supporting, contradicting, veto_signals
    all_refs="$(printf '%s' "${pb_json}" | jq -r '
        (.signals.supporting // [])[] ,
        (.signals.contradicting // [])[] ,
        (.signals.veto_signals // [])[]
    ' 2>/dev/null)"

    if [ -z "${all_refs}" ]; then
        continue
    fi

    IFS_SAVE="$IFS"
    IFS='
'
    for sig_id in ${all_refs}; do
        IFS="${IFS_SAVE}"
        found=""
        for key in ${signal_keys}; do
            if [ "${sig_id}" = "${key}" ]; then
                found="yes"
                break
            fi
        done
        if [ -n "${found}" ]; then
            _record_pass "${filename}: signal '${sig_id}' exists in signals.yaml"
        else
            _record_fail "${filename}: signal '${sig_id}' exists in signals.yaml" "not found in signals.yaml"
        fi
    done
    IFS="${IFS_SAVE}"
done

# ---------------------------------------------------------------------------
# Load compatibility.yaml and collect all referenced categories
# ---------------------------------------------------------------------------
compat_json="$(yaml_to_json "${COMPAT_FILE}")"

# Extract all unique categories from both incompatible_pairs and compatible_pairs
compat_categories="$(printf '%s' "${compat_json}" | jq -r '
    ((.incompatible_pairs // [])[][] , (.compatible_pairs // [])[][])
' 2>/dev/null | sort -u)"

# Collect all playbook categories
playbook_categories=""
for yaml_file in "${PLAYBOOK_DIR}"/*.yaml; do
    cat="$(yaml_to_json "${yaml_file}" | jq -r '.category // empty')"
    if [ -n "${cat}" ]; then
        playbook_categories="${playbook_categories}
${cat}"
    fi
done
playbook_categories="$(printf '%s' "${playbook_categories}" | sort -u)"

# For every category in compatibility.yaml, assert at least one playbook has that category
IFS_SAVE="$IFS"
IFS='
'
for compat_cat in ${compat_categories}; do
    IFS="${IFS_SAVE}"
    [ -z "${compat_cat}" ] && continue
    found=""
    for pb_cat in ${playbook_categories}; do
        if [ "${compat_cat}" = "${pb_cat}" ]; then
            found="yes"
            break
        fi
    done
    if [ -n "${found}" ]; then
        _record_pass "compatibility category '${compat_cat}' has at least one playbook"
    else
        _record_fail "compatibility category '${compat_cat}' has at least one playbook" "no playbook found with this category"
    fi
done
IFS="${IFS_SAVE}"

# ---------------------------------------------------------------------------
# SKILL.md mentions contradiction collapse concept
# ---------------------------------------------------------------------------
skill_content="$(cat "${SKILL_FILE}")"
# Check for "contradiction collapse" or "collapse" near "incompatible"
if printf '%s' "${skill_content}" | grep -qi "contradiction.*collapse\|collapse.*incompatible\|incompatible.*collapse"; then
    _record_pass "SKILL.md references contradiction collapse"
else
    _record_fail "SKILL.md references contradiction collapse" "neither 'contradiction collapse' nor 'collapse' near 'incompatible' found"
fi

print_summary
