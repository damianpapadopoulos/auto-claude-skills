#!/usr/bin/env bash
# test-migrate-docs-plans.sh — Tests for scripts/migrate-docs-plans-to-openspec.sh
#
# The script helps users adopting spec-driven mode migrate existing
# docs/plans/*-design.md artifacts into openspec/changes/<feature>/design.md
# committed structure.
#
# Bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MIGRATE_SCRIPT="${PROJECT_ROOT}/scripts/migrate-docs-plans-to-openspec.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-migrate-docs-plans.sh ==="

# ---------------------------------------------------------------------------
# Existence and syntax
# ---------------------------------------------------------------------------
echo "-- Script structure --"
assert_file_exists "migrate script exists" "${MIGRATE_SCRIPT}"
if [ -f "${MIGRATE_SCRIPT}" ]; then
    bash -n "${MIGRATE_SCRIPT}" 2>/dev/null \
        && _record_pass "script has valid bash syntax" \
        || _record_fail "script has valid bash syntax" "bash -n failed"
    [ -x "${MIGRATE_SCRIPT}" ] \
        && _record_pass "script is executable" \
        || _record_fail "script is executable" "missing +x"
fi

# ---------------------------------------------------------------------------
# Dry-run: inventory only
# ---------------------------------------------------------------------------
echo "-- Dry-run inventory --"
if [ -x "${MIGRATE_SCRIPT}" ]; then
    _tmp="$(mktemp -d)"
    mkdir -p "${_tmp}/docs/plans"
    printf '# Design: Feature A\n\nproblem statement\n' > "${_tmp}/docs/plans/2026-04-01-feature-a-design.md"
    printf '# Design: Feature B\n\nproblem statement\n' > "${_tmp}/docs/plans/2026-04-02-feature-b-design.md"
    # Non-design artifact should be ignored
    printf '# Plan\n' > "${_tmp}/docs/plans/2026-04-01-feature-a-plan.md"

    output="$(cd "${_tmp}" && bash "${MIGRATE_SCRIPT}" --dry-run 2>&1)"

    # Should list both design files
    assert_contains "dry-run lists feature-a" "feature-a" "${output}"
    assert_contains "dry-run lists feature-b" "feature-b" "${output}"
    assert_not_contains "dry-run ignores plan.md files" "feature-a-plan" "${output}"

    # Dry-run should NOT create openspec/changes/
    if [ -d "${_tmp}/openspec/changes" ]; then
        _record_fail "dry-run does not mutate filesystem" "openspec/changes/ was created"
    else
        _record_pass "dry-run does not mutate filesystem"
    fi

    rm -rf "${_tmp}"
fi

# ---------------------------------------------------------------------------
# Migration: copies design files into openspec/changes/<slug>/design.md
# ---------------------------------------------------------------------------
echo "-- Migration --"
if [ -x "${MIGRATE_SCRIPT}" ]; then
    _tmp="$(mktemp -d)"
    mkdir -p "${_tmp}/docs/plans"
    printf '# Design: Feature A\n\ntest content\n' > "${_tmp}/docs/plans/2026-04-01-feature-a-design.md"

    (cd "${_tmp}" && bash "${MIGRATE_SCRIPT}" --apply 2>&1) >/dev/null

    # Should create openspec/changes/feature-a/design.md
    assert_file_exists "migrated design file exists" "${_tmp}/openspec/changes/feature-a/design.md"

    # Content should be preserved
    if [ -f "${_tmp}/openspec/changes/feature-a/design.md" ]; then
        assert_contains "migrated content preserved" "test content" "$(cat "${_tmp}/openspec/changes/feature-a/design.md")"
    fi

    # Should NOT delete the original (migration, not move)
    assert_file_exists "original design file preserved" "${_tmp}/docs/plans/2026-04-01-feature-a-design.md"

    rm -rf "${_tmp}"
fi

# ---------------------------------------------------------------------------
# Idempotent: re-running does not overwrite existing target
# ---------------------------------------------------------------------------
echo "-- Idempotency --"
if [ -x "${MIGRATE_SCRIPT}" ]; then
    _tmp="$(mktemp -d)"
    mkdir -p "${_tmp}/docs/plans" "${_tmp}/openspec/changes/feature-c"
    printf '# Design: Feature C\n\noriginal from docs/plans\n' > "${_tmp}/docs/plans/2026-04-01-feature-c-design.md"
    # Pre-existing openspec/changes/feature-c/design.md — migration must NOT clobber
    printf '# Existing upfront design\n\ndo not clobber\n' > "${_tmp}/openspec/changes/feature-c/design.md"

    (cd "${_tmp}" && bash "${MIGRATE_SCRIPT}" --apply 2>&1) >/dev/null

    # The pre-existing content must still be there (not overwritten)
    assert_contains "does not clobber existing design.md" "do not clobber" "$(cat "${_tmp}/openspec/changes/feature-c/design.md")"

    rm -rf "${_tmp}"
fi

# ---------------------------------------------------------------------------
# Empty state: no docs/plans/ → exit 0, no-op
# ---------------------------------------------------------------------------
echo "-- Empty state --"
if [ -x "${MIGRATE_SCRIPT}" ]; then
    _tmp="$(mktemp -d)"
    if (cd "${_tmp}" && bash "${MIGRATE_SCRIPT}" --dry-run 2>&1 | grep -q "No docs/plans"); then
        _record_pass "handles missing docs/plans gracefully"
    else
        _record_fail "handles missing docs/plans gracefully" "expected no-op message"
    fi
    rm -rf "${_tmp}"
fi

# ---------------------------------------------------------------------------
# /setup command documents the migration step
# ---------------------------------------------------------------------------
echo "-- /setup integration --"
SETUP_CMD="${PROJECT_ROOT}/commands/setup.md"
SETUP_CONTENT="$(cat "${SETUP_CMD}")"

assert_contains "/setup references migration script" "migrate-docs-plans-to-openspec.sh" "$SETUP_CONTENT"
assert_contains "/setup offers migration in team-mode step" "--dry-run" "$SETUP_CONTENT"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary
exit $?
