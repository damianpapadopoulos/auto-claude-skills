#!/usr/bin/env bash
# test-skill-content-coverage.sh — every owned, trigger-routed skill MUST be asserted on
# by at least one test under tests/ (detected by CONTENT — a reference to skills/<name>/ —
# NOT by filename, since content tests follow no naming convention). Companion to
# test-fixture-coverage.sh (routing fixtures); same owned-skill population + exemptions.
#
# Limitation (documented, deliberate): this proves a test REFERENCES the skill, not that
# it asserts anything meaningful — presence, not quality. Same pragmatic bar as
# test-skill-anatomy.sh; assertion quality stays a human-review concern.
# Bash 3.2 compatible.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTS_DIR="${SCRIPT_DIR}"
TRIGGERS_JSON="${PROJECT_ROOT}/config/default-triggers.json"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-skill-content-coverage.sh ==="
command -v jq >/dev/null 2>&1 || { echo "error: jq required" >&2; exit 2; }

# Same population as test-fixture-coverage.sh: owned (auto-claude-skills:) skills with
# at least one trigger regex. External-plugin and composition-only skills are excluded.
owned_with_triggers="$(jq -r '
  .skills[]
  | select((.invoke // "") | contains("auto-claude-skills:"))
  | select((.triggers // []) | length > 0)
  | .name' "${TRIGGERS_JSON}")"

while IFS= read -r skill || [ -n "${skill}" ]; do
    [ -z "${skill}" ] && continue
    # A test "covers" the skill if it references the real skills/<name>/ path. Two kinds
    # of matches must NOT count: (1) this suite's own dynamic "skills/${skill}/"; (2) mock
    # fixtures under .claude/skills/<name>/ — registry/discovery mechanics tests (e.g.
    # test-registry.sh) build fake skill trees at ${HOME}/.claude/skills/<name>/ using the
    # real skill name, but assert nothing about the real SKILL.md. Grep lines, not just
    # filenames, so a file that has BOTH a mock ref and a real ref still counts by the real one.
    real="$(grep -rnF "skills/${skill}/" "${TESTS_DIR}" --include='*.sh' 2>/dev/null \
        | grep -v 'test-skill-content-coverage\.sh:' \
        | grep -vF '.claude/skills/' || true)"
    if [ -n "${real}" ]; then
        count="$(printf '%s\n' "${real}" | awk -F: '{print $1}' | sort -u | grep -c .)"
        _record_pass "${skill}: content-asserted by ${count} test file(s)"
    else
        _record_fail "owned skill '${skill}' has no content-assertion test (no tests/*.sh reads the real skills/${skill}/SKILL.md; mock .claude/skills paths do not count)"
    fi
done <<EOF
${owned_with_triggers}
EOF

print_summary
