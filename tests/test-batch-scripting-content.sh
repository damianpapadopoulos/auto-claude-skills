#!/usr/bin/env bash
# test-batch-scripting-content.sh — batch-scripting per-file postcondition assertions
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-batch-scripting-content.sh ==="

SKILL="${PROJECT_ROOT}/skills/batch-scripting/SKILL.md"
assert_file_exists "batch-scripting SKILL.md exists" "${SKILL}"
skill="$(cat "${SKILL}" 2>/dev/null)"

# Step 3 must gate OK on a per-file postcondition, not the exit code alone.
assert_contains "exit 0 is not proof"            "exit code is not proof" "${skill}"
assert_contains "postcondition named"            "postcondition"          "${skill}"
assert_contains "non-empty check"                "non-empty"              "${skill}"
assert_contains "differs-from-original check"    "cmp -s"                 "${skill}"
assert_contains "sanity/parse check"             "sanity_check"           "${skill}"
assert_contains "failed postcondition -> FAIL (no silent OK)" "silent OK" "${skill}"
assert_contains "unchanged output is SKIP not FAIL (no infinite retry)" "SKIP" "${skill}"

print_summary
exit $?
