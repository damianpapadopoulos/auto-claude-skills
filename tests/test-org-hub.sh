#!/usr/bin/env bash
# test-org-hub.sh — org-hub connector: builder + injection + fail-open
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILDER="${REPO_ROOT}/scripts/org-hub-build-index.sh"
FIXTURE_HUB_SRC="${SCRIPT_DIR}/fixtures/org-hub/mini-hub"

make_hub_clone() {  # copies fixture into tmp and git-inits it; echoes path
    local dest="${TEST_TMPDIR}/hub-clone"
    cp -R "${FIXTURE_HUB_SRC}" "${dest}"
    (cd "${dest}" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
    printf '%s' "${dest}"
}

make_consumer_repo() {  # git repo with descriptor pointing at $1; echoes path
    local hub="$1" dest="${TEST_TMPDIR}/consumer"
    mkdir -p "${dest}/.claude"
    (cd "${dest}" && git init -q)
    jq -n --arg hub "${hub}" '{
        schema_version: 1, name: "Mini Hub", hub_path: $hub,
        scope: {org: true, tribes: ["alpha"], domains: []},
        context_roots: ["context/"],
        glossaries: ["context/org/glossary.md"], spec_roots: ["specs/"],
        usage_note: "Glossary-first: use canonical terms.",
        index_path: ".claude/org-hub-index.md", index_built_at_sha: ""
    }' > "${dest}/.claude/org-hub.json"
    printf '%s' "${dest}"
}

# ---------------------------------------------------------------------------
# Builder (scripts/org-hub-build-index.sh)
# ---------------------------------------------------------------------------

test_builder_scope_filter() {
    echo "-- test: builder scope filter + overdue marker + SHA recording --"
    setup_test_env
    local hub consumer
    hub="$(make_hub_clone)"; consumer="$(make_consumer_repo "${hub}")"
    (cd "${consumer}" && /bin/bash "${BUILDER}" --hub "${hub}" --descriptor .claude/org-hub.json >/dev/null)
    local idx="${consumer}/.claude/org-hub-index.md"
    assert_file_exists "index file written" "${idx}"
    assert_contains "org artifact included" "deploy-rules.md" "$(cat "${idx}")"
    assert_contains "alpha tribe included" "protocols.md" "$(cat "${idx}")"
    assert_not_contains "beta tribe excluded by scope" "payments/rules.md" "$(cat "${idx}")"
    assert_contains "overdue marker on stale artifact" "(overdue)" "$(cat "${idx}")"
    assert_not_contains "untyped glossary not indexed" "glossary.md" "$(cat "${idx}")"
    # SHA recorded
    local sha; sha="$(jq -r '.index_built_at_sha' "${consumer}/.claude/org-hub.json")"
    local head; head="$(git -C "${hub}" log -1 --format=%H)"
    assert_equals "descriptor records hub HEAD" "${head}" "${sha}"
    teardown_test_env
}

test_builder_symlink_escape_blocked() {
    echo "-- test: builder blocks symlink escape --"
    setup_test_env
    local hub consumer
    hub="$(make_hub_clone)"
    ln -s /etc "${hub}/context/org/evil"
    consumer="$(make_consumer_repo "${hub}")"
    (cd "${consumer}" && /bin/bash "${BUILDER}" --hub "${hub}" --descriptor .claude/org-hub.json >/dev/null)
    assert_not_contains "symlink escape excluded (evil)" "evil" "$(cat "${consumer}/.claude/org-hub-index.md")"
    assert_not_contains "symlink escape excluded (/etc)" "(/etc" "$(cat "${consumer}/.claude/org-hub-index.md")"
    teardown_test_env
}

echo "=== test-org-hub.sh ==="
test_builder_scope_filter
test_builder_symlink_escape_blocked

print_summary
