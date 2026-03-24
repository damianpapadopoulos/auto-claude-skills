#!/usr/bin/env bash
# test-openspec.sh — OpenSpec v1.3 change set validation.
# NOTE: The change set does not exist until Task 8 is complete.
# This test will fail until then — that is expected.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-openspec.sh ==="

CHANGE_DIR="${PROJECT_ROOT}/openspec/changes/2026-03-23-incident-analysis-v1.3"
CANONICAL_SPEC="${PROJECT_ROOT}/openspec/specs/incident-analysis/spec.md"

# ---------------------------------------------------------------------------
# Primary check: use openspec CLI if available
# ---------------------------------------------------------------------------
if command -v openspec >/dev/null 2>&1; then
    if openspec validate 2026-03-23-incident-analysis-v1.3 2>/dev/null; then
        _record_pass "openspec CLI validates change set"
        print_summary
        exit $?
    else
        _record_fail "openspec CLI validates change set" "openspec validate failed"
        print_summary
        exit $?
    fi
fi

# ---------------------------------------------------------------------------
# Fallback: structural checks (CLI not available)
# ---------------------------------------------------------------------------

# Change set directory exists
if [ -d "${CHANGE_DIR}" ]; then
    _record_pass "change set directory exists"
else
    _record_fail "change set directory exists" "${CHANGE_DIR} not found"
    # Cannot continue without the directory
    print_summary
    exit $?
fi

# proposal.md exists with correct headers
PROPOSAL="${CHANGE_DIR}/proposal.md"
assert_file_exists "proposal.md exists" "${PROPOSAL}"
if [ -f "${PROPOSAL}" ]; then
    proposal_content="$(cat "${PROPOSAL}")"
    assert_contains "proposal has ## Why header" "## Why" "${proposal_content}"
    assert_contains "proposal has ## What Changes header" "## What Changes" "${proposal_content}"
fi

# design.md exists
assert_file_exists "design.md exists" "${CHANGE_DIR}/design.md"

# tasks.md exists
assert_file_exists "tasks.md exists" "${CHANGE_DIR}/tasks.md"

# Delta spec exists
DELTA_SPEC="${CHANGE_DIR}/specs/incident-analysis/spec.md"
assert_file_exists "delta spec exists" "${DELTA_SPEC}"
if [ -f "${DELTA_SPEC}" ]; then
    delta_content="$(cat "${DELTA_SPEC}")"
    # Delta spec contains v1.3 requirement headings
    if printf '%s' "${delta_content}" | grep -qi "Playbook\|Confidence\|Classification"; then
        _record_pass "delta spec references v1.3 concepts"
    else
        _record_fail "delta spec references v1.3 concepts" "no Playbook/Confidence/Classification heading found"
    fi
fi

# Canonical spec contains v1.3 requirements
assert_file_exists "canonical spec exists" "${CANONICAL_SPEC}"
if [ -f "${CANONICAL_SPEC}" ]; then
    canonical_content="$(cat "${CANONICAL_SPEC}")"
    if printf '%s' "${canonical_content}" | grep -qi "Playbook\|Confidence\|Classification"; then
        _record_pass "canonical spec references v1.3 requirements"
    else
        _record_fail "canonical spec references v1.3 requirements" "no v1.3 requirement headings found"
    fi
fi

print_summary
