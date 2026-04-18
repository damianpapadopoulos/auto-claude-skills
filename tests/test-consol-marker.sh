#!/usr/bin/env bash
# test-consol-marker.sh — Tests for the consolidation marker helper.
# Proves two sibling worktrees/clones of the same repo produce the SAME marker
# path, and two different repos produce DIFFERENT marker paths.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"
. "${PROJECT_ROOT}/hooks/lib/consol-marker.sh"

echo "=== test-consol-marker.sh ==="

# Build a temp git repo with a fixed remote URL. Returns the repo path.
mkrepo_with_origin() {
    local dir="$1"
    local origin="$2"
    mkdir -p "$dir"
    cd "$dir"
    git init -q
    git remote add origin "$origin" 2>/dev/null || git remote set-url origin "$origin"
}

test_marker_stable_across_worktrees_of_same_remote() {
    echo "-- test: two checkouts of the same remote yield the same marker --"
    setup_test_env

    # Two separate local clones pointing at the same fictitious remote
    (mkrepo_with_origin "${TEST_TMPDIR}/clone_a" "git@example.com:org/repo.git")
    (mkrepo_with_origin "${TEST_TMPDIR}/clone_b" "git@example.com:org/repo.git")

    local marker_a marker_b
    marker_a="$(consol_marker_path "${TEST_TMPDIR}/clone_a")"
    marker_b="$(consol_marker_path "${TEST_TMPDIR}/clone_b")"

    assert_not_empty "marker_a non-empty" "$marker_a"
    assert_equals "marker matches across sibling worktrees" "$marker_a" "$marker_b"

    teardown_test_env
}
test_marker_stable_across_worktrees_of_same_remote

test_marker_differs_between_repos() {
    echo "-- test: different remotes yield different markers --"
    setup_test_env

    (mkrepo_with_origin "${TEST_TMPDIR}/repo_one" "git@example.com:org/repo-one.git")
    (mkrepo_with_origin "${TEST_TMPDIR}/repo_two" "git@example.com:org/repo-two.git")

    local marker_one marker_two
    marker_one="$(consol_marker_path "${TEST_TMPDIR}/repo_one")"
    marker_two="$(consol_marker_path "${TEST_TMPDIR}/repo_two")"

    if [ "$marker_one" != "$marker_two" ]; then
        _record_pass "distinct remotes produce distinct markers"
    else
        _record_fail "distinct remotes produce distinct markers" \
            "both collapsed to '$marker_one'"
    fi

    teardown_test_env
}
test_marker_differs_between_repos

test_marker_falls_back_to_path_without_remote() {
    echo "-- test: no remote → marker derived from absolute path --"
    setup_test_env

    local bare="${TEST_TMPDIR}/no-remote"
    mkdir -p "$bare"
    (cd "$bare" && git init -q)

    local marker
    marker="$(consol_marker_path "$bare")"
    assert_not_empty "marker_non_remote non-empty" "$marker"

    # Recompute using the path directly and verify the helper matches
    local expected_hash
    expected_hash="$(printf '%s' "$bare" | shasum | cut -d' ' -f1)"
    local expected="${HOME}/.claude/.context-stack-consolidated-${expected_hash}"
    assert_equals "marker falls back to path-based hash" "$expected" "$marker"

    teardown_test_env
}
test_marker_falls_back_to_path_without_remote

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary
