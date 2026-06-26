#!/usr/bin/env bash
# test-skill-anatomy.sh — readiness-claim skills carry a '## Verification' anatomy
# section (evidence-before-assertions discipline). PR-T4, change: adopt-addy-mechanics.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-skill-anatomy.sh ==="

# Owned skills that make a completion/readiness claim — each MUST carry a
# '## Verification' anatomy section. Extend this list when a new readiness-claim
# skill is added. Tool/domain/investigation skills are intentionally excluded
# (filler anatomy on them is the anti-goal).
READINESS_CLAIM_SKILLS="deploy-gate openspec-ship runtime-validation agent-team-review implementation-drift-check project-verification"

for s in ${READINESS_CLAIM_SKILLS}; do
    f="${PROJECT_ROOT}/skills/${s}/SKILL.md"
    if grep -qE '^## Verification' "${f}" 2>/dev/null; then
        _record_pass "${s}: has '## Verification' section"
    else
        _record_fail "${s}: has '## Verification' section" "no '^## Verification' heading in ${f}"
    fi
done

print_summary
