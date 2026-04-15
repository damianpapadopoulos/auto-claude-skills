#!/usr/bin/env bash
# test-eval-pack-schema.sh — Validate eval pack JSON schema
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EVALS_DIR="${PROJECT_ROOT}/tests/fixtures/evals"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-eval-pack-schema.sh ==="

setup_test_env

# ---------------------------------------------------------------------------
# Check that evals directory has at least one file
# ---------------------------------------------------------------------------
# At least one eval pack must exist (Task 1 creates the dog-food fixture)
assert_file_exists "dog-food eval pack exists" "${EVALS_DIR}/routing-validation.json"

# ---------------------------------------------------------------------------
# Validate each eval pack
# ---------------------------------------------------------------------------
for eval_file in "${EVALS_DIR}"/*.json; do
    [ -f "$eval_file" ] || continue
    fname="$(basename "$eval_file")"

    # Valid JSON
    assert_json_valid "${fname}: is valid JSON" "$eval_file"

    # Required top-level fields
    has_id="$(jq -r '.id // empty' "$eval_file")"
    assert_not_empty "${fname}: has 'id' field" "${has_id}"

    has_cap="$(jq -r '.capability // empty' "$eval_file")"
    assert_not_empty "${fname}: has 'capability' field" "${has_cap}"

    scenario_count="$(jq -r '.scenarios | length' "$eval_file")"
    assert_not_empty "${fname}: has at least one scenario" "${scenario_count}"

    # Validate each scenario
    local_i=0
    while [ "$local_i" -lt "$scenario_count" ]; do
        s_name="$(jq -r ".scenarios[${local_i}].name // empty" "$eval_file")"
        assert_not_empty "${fname}[${local_i}]: scenario has 'name'" "${s_name}"

        s_path="$(jq -r ".scenarios[${local_i}].path // empty" "$eval_file")"
        assert_not_empty "${fname}[${local_i}]: scenario has 'path'" "${s_path}"

        # Path must be one of: browser, api, cli
        case "$s_path" in
            browser|api|cli)
                assert_not_empty "${fname}[${local_i}]: path '${s_path}' is valid" "${s_path}" ;;
            *)
                assert_equals "${fname}[${local_i}]: path must be browser|api|cli" "browser|api|cli" "${s_path}" ;;
        esac

        s_expected="$(jq -r ".scenarios[${local_i}].expected // empty" "$eval_file")"
        assert_not_empty "${fname}[${local_i}]: scenario has 'expected'" "${s_expected}"

        local_i=$((local_i + 1))
    done
done

teardown_test_env

echo ""
echo "=== Eval Pack Schema Results ==="
echo "  Total: ${TESTS_RUN}"
echo "  Passed: ${TESTS_PASSED}"
echo "  Failed: ${TESTS_FAILED}"
[ "${TESTS_FAILED}" -eq 0 ] || exit 1
