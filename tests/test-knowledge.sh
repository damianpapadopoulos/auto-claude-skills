#!/usr/bin/env bash
# test-knowledge.sh — Tests for knowledge rebuild index
# Bash 3.2 compatible. Sources test-helpers.sh for setup/teardown and assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-knowledge.sh ==="

test_rebuild_index_regenerates_from_frontmatter() {
    local tmp; tmp="$(mktemp -d)"
    cp "${PROJECT_ROOT}/tests/fixtures/knowledge/valid/sample-decision.md" "${tmp}/"
    : > "${tmp}/index.md"   # clobber
    bash "${PROJECT_ROOT}/scripts/knowledge-rebuild-index.sh" "${tmp}"
    local out; out="$(cat "${tmp}/index.md")"
    assert_contains "index has schema_version" "schema_version: okf-0.1" "${out}"
    assert_contains "index lists the fact" "[Sample decision](sample-decision.md)" "${out}"
    rm -rf "${tmp}"
}
test_rebuild_index_regenerates_from_frontmatter

test_rebuild_index_sorts_by_slug_not_title() {
    local tmp; tmp="$(mktemp -d)"
    # a-zebra.md has title "Zebra" — slug-first but title-last
    cat > "${tmp}/a-zebra.md" <<'EOF'
---
type: decision
title: Zebra
description: Fact with slug-first but title-last ordering.
source: tests/fixtures/knowledge/valid/a-zebra.md
timestamp: 2026-06-18T00:00:00Z
---
Body.
EOF
    # z-alpha.md has title "Alpha" — slug-last but title-first
    cat > "${tmp}/z-alpha.md" <<'EOF'
---
type: decision
title: Alpha
description: Fact with slug-last but title-first ordering.
source: tests/fixtures/knowledge/valid/z-alpha.md
timestamp: 2026-06-18T00:00:00Z
---
Body.
EOF
    bash "${PROJECT_ROOT}/scripts/knowledge-rebuild-index.sh" "${tmp}"
    local out; out="$(cat "${tmp}/index.md")"
    # Confirm both entries appear
    assert_contains "index lists a-zebra.md" "(a-zebra.md)" "${out}"
    assert_contains "index lists z-alpha.md" "(z-alpha.md)" "${out}"
    # Slug order: a-zebra.md line must come before z-alpha.md line
    local line_zebra line_alpha
    line_zebra="$(printf '%s\n' "${out}" | grep -n '(a-zebra\.md)' | head -1 | cut -d: -f1)"
    line_alpha="$(printf '%s\n' "${out}" | grep -n '(z-alpha\.md)' | head -1 | cut -d: -f1)"
    if [ -n "${line_zebra}" ] && [ -n "${line_alpha}" ] && [ "${line_zebra}" -lt "${line_alpha}" ]; then
        _record_pass "index is ordered by slug (a-zebra before z-alpha)"
    else
        _record_fail "index is ordered by slug (a-zebra before z-alpha)" \
            "a-zebra on line ${line_zebra:-?}, z-alpha on line ${line_alpha:-?}"
    fi
    rm -rf "${tmp}"
}
test_rebuild_index_sorts_by_slug_not_title

print_summary
