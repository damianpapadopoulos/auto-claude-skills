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
    cp tests/fixtures/knowledge/valid/sample-decision.md "${tmp}/"
    : > "${tmp}/index.md"   # clobber
    bash "${PROJECT_ROOT}/scripts/knowledge-rebuild-index.sh" "${tmp}"
    local out; out="$(cat "${tmp}/index.md")"
    assert_contains "index has schema_version" "schema_version: okf-0.1" "${out}"
    assert_contains "index lists the fact" "[Sample decision](sample-decision.md)" "${out}"
    rm -rf "${tmp}"
}
test_rebuild_index_regenerates_from_frontmatter
print_summary
