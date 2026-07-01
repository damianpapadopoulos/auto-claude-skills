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

# --- verdict: suspect when changed lines uncovered ---
diff3="$(printf '%s\n' \
  '--- a/src/foo.py' '+++ b/src/foo.py' '@@ -1,1 +1,3 @@' \
  ' import os' '+def added():' '+    return 1')"
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/foo-uncovered.lcov" <<'LCOV'
SF:src/foo.py
DA:2,0
DA:3,0
end_of_record
LCOV
v_susp="$(printf '%s' "${diff3}" | COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/foo-uncovered.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "uncovered changed lines are suspect" "suspect" "${v_susp}"
assert_contains "suspect cites the uncovered line" "src/foo.py:2" "${v_susp}"

# --- verdict: clean when changed lines covered above floor ---
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/foo-covered.lcov" <<'LCOV'
SF:src/foo.py
DA:2,3
DA:3,3
end_of_record
LCOV
v_clean="$(printf '%s' "${diff3}" | COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/foo-covered.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "covered changed lines are clean" "clean" "${v_clean}"

# --- verdict: unverified when no artifact ---
v_unv="$(printf '%s' "${diff3}" | COVERAGE_ADEQUACY_LCOV="/nonexistent.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "no artifact is unverified" "unverified" "${v_unv}"

# --- verdict: unverified when changed lines have no coverage overlap (all non-code) ---
diff_docs="$(printf '%s\n' '--- a/README.md' '+++ b/README.md' '@@ -1,0 +1,1 @@' '+new docs line')"
v_noov="$(printf '%s' "${diff_docs}" | COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/foo-covered.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "no coverable overlap is unverified" "unverified" "${v_noov}"

# --- deletion does not inflate new-file line numbers (Task-1 path regression) ---
diff_del="$(printf '%s\n' '--- a/src/foo.py' '+++ b/src/foo.py' '@@ -1,3 +1,2 @@' ' import os' '-old_line = 1' '+new_line = 2')"
out_del="$(printf '%s' "${diff_del}" | COVERAGE_ADEQUACY_MODE=changed-lines bash "${CAC}" 2>/dev/null)"
assert_contains "added line after deletion is line 2" "src/foo.py	2" "${out_del}"
assert_not_contains "deletion did not inflate to line 3" "src/foo.py	3" "${out_del}"

print_summary
exit $?
