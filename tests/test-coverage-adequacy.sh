#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-coverage-adequacy.sh ==="

CAC="${PROJECT_ROOT}/skills/project-verification/scripts/coverage-adequacy-check.sh"
assert_file_exists "coverage-adequacy-check.sh exists" "${CAC}"

# _changed_lines: added lines get new-file line numbers; deletions do not advance.
diff_in="$(printf '%s\n' \
  '--- a/src/foo.py' \
  '+++ b/src/foo.py' \
  '@@ -1,3 +1,4 @@' \
  ' import os' \
  '+def added():' \
  '+    return 1' \
  ' x = 1')"
out_cl="$(printf '%s' "${diff_in}" | COVERAGE_ADEQUACY_MODE=changed-lines bash "${CAC}" 2>/dev/null)"
assert_contains "added def line 2 reported" "src/foo.py	2" "${out_cl}"
assert_contains "added return line 3 reported" "src/foo.py	3" "${out_cl}"
assert_not_contains "context line not reported" "src/foo.py	4" "${out_cl}"

# --- lcov lookup ---
mkdir -p "${PROJECT_ROOT}/tests/fixtures/coverage"
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/sample.lcov" <<'LCOV'
SF:/repo/src/foo.py
DA:2,0
DA:3,5
DA:4,1
end_of_record
LCOV
lc="$(COVERAGE_ADEQUACY_MODE=lcov-hits COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/sample.lcov" bash "${CAC}" </dev/null 2>/dev/null)"
assert_contains "lcov line 2 hits 0"  "/repo/src/foo.py	2	0" "${lc}"
assert_contains "lcov line 3 hits 5"  "/repo/src/foo.py	3	5" "${lc}"

print_summary
exit $?
