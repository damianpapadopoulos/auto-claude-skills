# OpenSpec Bootstrap + Session State Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-03-14-openspec-bootstrap-state-design.md`

**Goal:** Make OpenSpec a first-class bootstrap capability with session-scoped state persistence and provenance metadata.

**Architecture:** Extend session-start-hook.sh with workspace OPSX command discovery and `openspec_capabilities` object. Add a persistence helper library at `hooks/lib/openspec-state.sh` for state file operations. Update openspec-ship SKILL.md to consume bootstrap capabilities and session state instead of ad-hoc detection.

**Tech Stack:** Bash 3.2, jq, JSON

**Important codebase note:** The session-start hook already detects `openspec` binary (line 472-475) and wires it into `CONTEXT_CAPS` as `openspec: true/false` (line 483). This plan builds on that existing detection — it does NOT duplicate it.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `hooks/session-start-hook.sh` | Bootstrap: workspace OPSX command probe, `OPENSPEC_CAPS` construction, registry wiring, capability line emission |
| `hooks/lib/openspec-state.sh` | New: persistence helper functions for session state and provenance |
| `skills/openspec-ship/SKILL.md` | Updated: consume bootstrap capabilities + session state instead of ad-hoc `command -v` |
| `config/fallback-registry.json` | Updated: include `openspec_capabilities` defaults |
| `tests/test-registry.sh` | Updated: 8 bootstrap detection tests |
| `tests/test-openspec-state.sh` | New: 4 state persistence + provenance tests |

---

## Chunk 1: Persistence Helper

### Task 1: Create hooks/lib/openspec-state.sh

**Files:**
- Create: `hooks/lib/openspec-state.sh`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p hooks/lib
```

- [ ] **Step 2: Write the persistence helper**

Create `hooks/lib/openspec-state.sh` with all four functions. The file must be Bash 3.2 compatible and use jq for JSON manipulation.

```bash
#!/usr/bin/env bash
# openspec-state.sh — Persistence helper for OpenSpec session state
# Sourced by skills/hooks that need state file access.
# Bash 3.2 compatible. Requires jq.

# State file path: ~/.claude/.skill-openspec-state-<session_token>

# --- openspec_state_mark_verified <session_token> <surface> -------
# Create or update state file with verification fields.
# Idempotent merge: preserves existing 'changes' map.
openspec_state_mark_verified() {
    local token="${1:-}"
    local surface="${2:-none}"
    [ -z "$token" ] && echo "[openspec-state] WARN: no session token, skipping state write" >&2 && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [ -f "$state_file" ]; then
        # Merge into existing file
        local tmp
        tmp="$(jq --arg surface "$surface" --arg now "$now" '
            .verification_seen = true |
            .verification_at = $now |
            .openspec_surface = (.openspec_surface // $surface)
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        # Create new file
        jq -n --arg surface "$surface" --arg now "$now" '{
            openspec_surface: $surface,
            verification_seen: true,
            verification_at: $now,
            changes: {}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_upsert_change <token> <slug> <plan_path> <spec_path> <capability> ---
# Add or update a change entry in the changes map.
# Idempotent: existing entries for other slugs are preserved.
openspec_state_upsert_change() {
    local token="${1:-}"
    local slug="${2:-}"
    local plan_path="${3:-}"
    local spec_path="${4:-}"
    local capability="${5:-}"
    [ -z "$token" ] && echo "[openspec-state] WARN: no session token, skipping state write" >&2 && return 0
    [ -z "$slug" ] && echo "[openspec-state] WARN: no change slug, skipping state write" >&2 && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    if [ -f "$state_file" ]; then
        local tmp
        tmp="$(jq --arg slug "$slug" --arg pp "$plan_path" --arg sp "$spec_path" --arg cap "$capability" '
            .changes[$slug] = {
                sp_plan_path: $pp,
                sp_spec_path: $sp,
                capability_slug: $cap,
                archived_at: null
            }
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        # Create new file with just the change entry
        jq -n --arg slug "$slug" --arg pp "$plan_path" --arg sp "$spec_path" --arg cap "$capability" '{
            openspec_surface: "none",
            verification_seen: false,
            verification_at: null,
            changes: {($slug): {
                sp_plan_path: $pp,
                sp_spec_path: $sp,
                capability_slug: $cap,
                archived_at: null
            }}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_read <session_token> --------------------------
# Read and output current state file as JSON.
# Returns empty {} if file doesn't exist or is malformed.
openspec_state_read() {
    local token="${1:-}"
    [ -z "$token" ] && echo '{}' && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    if [ -f "$state_file" ]; then
        jq '.' "$state_file" 2>/dev/null || echo '{}'
    else
        echo '{}'
    fi
}

# --- openspec_write_provenance <archive_path> <session_token> <slug> ---
# Write source.json to <archive_path>/superpowers/source.json.
# Creates the superpowers/ directory if needed.
openspec_write_provenance() {
    local archive_path="${1:-}"
    local token="${2:-}"
    local slug="${3:-}"
    [ -z "$archive_path" ] && echo "[openspec-state] WARN: no archive path, skipping provenance" >&2 && return 0
    [ -z "$token" ] && echo "[openspec-state] WARN: no session token, skipping provenance" >&2 && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
    local commit
    commit="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    mkdir -p "${archive_path}/superpowers"

    if [ -f "$state_file" ] && [ -n "$slug" ]; then
        jq --arg slug "$slug" --arg branch "$branch" --arg commit "$commit" --arg now "$now" '
            {
                schema_version: 1,
                sp_plan_path: (.changes[$slug].sp_plan_path // null),
                sp_spec_path: (.changes[$slug].sp_spec_path // null),
                change_slug: $slug,
                capability_slug: (.changes[$slug].capability_slug // null),
                source_branch: $branch,
                base_commit: $commit,
                openspec_surface: (.openspec_surface // "none"),
                archived_at: $now
            }
        ' "$state_file" > "${archive_path}/superpowers/source.json" 2>/dev/null || {
            echo "[openspec-state] WARN: provenance write failed" >&2
            return 0
        }
    else
        # No state file — write minimal provenance
        jq -n --arg slug "$slug" --arg branch "$branch" --arg commit "$commit" --arg now "$now" '{
            schema_version: 1,
            sp_plan_path: null,
            sp_spec_path: null,
            change_slug: $slug,
            capability_slug: null,
            source_branch: $branch,
            base_commit: $commit,
            openspec_surface: "none",
            archived_at: $now
        }' > "${archive_path}/superpowers/source.json" 2>/dev/null || {
            echo "[openspec-state] WARN: provenance write failed" >&2
            return 0
        }
    fi
}
```

- [ ] **Step 3: Make it sourceable (not executable)**

The file should NOT be `chmod +x` — it's a library, not a script. Verify:

```bash
[ ! -x hooks/lib/openspec-state.sh ] && echo "OK: not executable"
```

- [ ] **Step 4: Syntax check**

Run: `bash -n hooks/lib/openspec-state.sh`
Expected: No output.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/openspec-state.sh
git commit -m "feat: add OpenSpec session state persistence helper library"
```

### Task 2: Write state persistence tests

**Files:**
- Create: `tests/test-openspec-state.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# test-openspec-state.sh — Tests for OpenSpec session state persistence
# Bash 3.2 compatible. Sources test-helpers.sh for assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

# Source the helper under test
. "${PROJECT_ROOT}/hooks/lib/openspec-state.sh"

echo "=== test-openspec-state.sh ==="

# ---------------------------------------------------------------------------
# 1. Hooks alone do not create state file
# ---------------------------------------------------------------------------
test_hooks_do_not_create_state() {
    echo "-- test: hooks alone do not create OpenSpec state file --"
    setup_test_env

    # Run session-start hook
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" >/dev/null 2>&1

    # Run routing hook with a prompt
    printf '{"userMessage":"ship this"}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" >/dev/null 2>&1

    # Assert no openspec state file was created
    local state_files
    state_files="$(ls "${HOME}/.claude/.skill-openspec-state-"* 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "no openspec state file created by hooks" "0" "${state_files}"

    teardown_test_env
}
test_hooks_do_not_create_state

# ---------------------------------------------------------------------------
# 2. mark_verified creates state file
# ---------------------------------------------------------------------------
test_mark_verified_creates_state() {
    echo "-- test: mark_verified creates state file --"
    setup_test_env

    local token="test-$$"
    openspec_state_mark_verified "$token" "opsx-core"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    assert_equals "state file exists" "true" "$([ -f "$state_file" ] && echo true || echo false)"

    local verified
    verified="$(jq -r '.verification_seen' "$state_file" 2>/dev/null)"
    assert_equals "verification_seen is true" "true" "$verified"

    local surface
    surface="$(jq -r '.openspec_surface' "$state_file" 2>/dev/null)"
    assert_equals "openspec_surface is opsx-core" "opsx-core" "$surface"

    local changes_count
    changes_count="$(jq '.changes | length' "$state_file" 2>/dev/null)"
    assert_equals "changes map is empty" "0" "$changes_count"

    teardown_test_env
}
test_mark_verified_creates_state

# ---------------------------------------------------------------------------
# 3. upsert_change adds to changes map without overwriting
# ---------------------------------------------------------------------------
test_upsert_change_preserves_entries() {
    echo "-- test: upsert_change adds multiple entries --"
    setup_test_env

    local token="test-$$"
    # First: create state with verification
    openspec_state_mark_verified "$token" "opsx-core"

    # Add first change
    openspec_state_upsert_change "$token" "feature-a" "plans/a.md" "specs/a.md" "billing"

    # Add second change
    openspec_state_upsert_change "$token" "feature-b" "plans/b.md" "specs/b.md" "auth"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    # Both entries should exist
    local count
    count="$(jq '.changes | length' "$state_file" 2>/dev/null)"
    assert_equals "two entries in changes map" "2" "$count"

    local a_plan
    a_plan="$(jq -r '.changes["feature-a"].sp_plan_path' "$state_file" 2>/dev/null)"
    assert_equals "feature-a plan preserved" "plans/a.md" "$a_plan"

    local b_cap
    b_cap="$(jq -r '.changes["feature-b"].capability_slug' "$state_file" 2>/dev/null)"
    assert_equals "feature-b capability preserved" "auth" "$b_cap"

    # Verification fields should still be intact
    local verified
    verified="$(jq -r '.verification_seen' "$state_file" 2>/dev/null)"
    assert_equals "verification still intact" "true" "$verified"

    teardown_test_env
}
test_upsert_change_preserves_entries

# ---------------------------------------------------------------------------
# 4. write_provenance produces valid source.json
# ---------------------------------------------------------------------------
test_write_provenance_produces_source_json() {
    echo "-- test: write_provenance produces valid source.json --"
    setup_test_env

    local token="test-$$"
    openspec_state_mark_verified "$token" "opsx-core"
    openspec_state_upsert_change "$token" "my-feature" "plans/my.md" "specs/my.md" "my-cap"

    local archive_dir="${HOME}/test-archive"
    mkdir -p "$archive_dir"

    openspec_write_provenance "$archive_dir" "$token" "my-feature"

    local source_json="${archive_dir}/superpowers/source.json"
    assert_equals "source.json exists" "true" "$([ -f "$source_json" ] && echo true || echo false)"

    # Validate schema
    local schema_version
    schema_version="$(jq -r '.schema_version' "$source_json" 2>/dev/null)"
    assert_equals "schema_version is 1" "1" "$schema_version"

    local plan
    plan="$(jq -r '.sp_plan_path' "$source_json" 2>/dev/null)"
    assert_equals "sp_plan_path populated" "plans/my.md" "$plan"

    local cap
    cap="$(jq -r '.capability_slug' "$source_json" 2>/dev/null)"
    assert_equals "capability_slug populated" "my-cap" "$cap"

    local surface
    surface="$(jq -r '.openspec_surface' "$source_json" 2>/dev/null)"
    assert_equals "openspec_surface from state" "opsx-core" "$surface"

    # base_commit should be non-null (we're in a git repo)
    local commit
    commit="$(jq -r '.base_commit' "$source_json" 2>/dev/null)"
    assert_not_contains "base_commit not null" "null" "$commit"

    teardown_test_env
}
test_write_provenance_produces_source_json

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "=============================="
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '%s' "${FAILURE_DETAILS}"
    exit 1
else
    echo "All tests passed."
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x tests/test-openspec-state.sh
```

- [ ] **Step 3: Run tests**

Run: `bash tests/test-openspec-state.sh`
Expected: All 4 tests pass.

- [ ] **Step 4: Register in test runner**

Add `test-openspec-state.sh` to `tests/run-tests.sh` alongside the other test files.

- [ ] **Step 5: Commit**

```bash
git add tests/test-openspec-state.sh tests/run-tests.sh
git commit -m "test: add OpenSpec session state persistence tests"
```

## Chunk 2: Bootstrap Detection

### Task 3: Add workspace OPSX command discovery and openspec_capabilities to session-start-hook.sh

**Files:**
- Modify: `hooks/session-start-hook.sh:460-520` (detection block + RESULT jq)
- Modify: `hooks/session-start-hook.sh:629-635` (capability line emission)

- [ ] **Step 1: Add workspace OPSX command probe after existing binary detection (line ~475)**

Insert after the existing `_has_openspec` detection (line 475), before the `CONTEXT_CAPS` jq call (line 481):

```bash
# -----------------------------------------------------------------
# Step 8e: Detect OpenSpec capabilities (workspace commands + surface)
# -----------------------------------------------------------------
_WORKSPACE_ROOT="${_OPENSPEC_WORKSPACE_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_opsx_cmds=""
if [ -d "${_WORKSPACE_ROOT}/.claude/commands/opsx" ]; then
    for _cmd in "${_WORKSPACE_ROOT}/.claude/commands/opsx"/*.md; do
        [ -f "${_cmd}" ] || continue
        _opsx_cmds="${_opsx_cmds}${_opsx_cmds:+,}/opsx:$(basename "${_cmd}" .md)"
    done
fi

# Build OPENSPEC_CAPS JSON: binary + commands + surface + warnings
# Single jq call derives surface from command set
OPENSPEC_CAPS="$(jq -n \
    --argjson binary "${_has_openspec}" \
    --arg cmds "${_opsx_cmds}" \
    '($cmds | split(",") | map(select(. != ""))) as $commands |
    ($commands | map(split(":")[1]) | map(select(. != null))) as $names |
    (($names | index("propose") != null) and ($names | index("apply") != null) and ($names | index("archive") != null)) as $has_core |
    (($names | index("new") != null) or ($names | index("ff") != null) or ($names | index("continue") != null) or ($names | index("verify") != null) or ($names | index("sync") != null)) as $has_expanded |
    (if $binary and $has_core and $has_expanded then "opsx-expanded"
     elif $binary and $has_core then "opsx-core"
     elif $binary then "openspec-core"
     else "none" end) as $surface |
    (if ($binary | not) and ($commands | length) > 0 then ["OPSX command files found but openspec binary missing"]
     else [] end) as $warnings |
    {binary: $binary, commands: $commands, surface: $surface, warnings: $warnings}'
)"
```

- [ ] **Step 2: Wire OPENSPEC_CAPS into the RESULT jq call (line ~501)**

Add `--argjson openspec_caps "${OPENSPEC_CAPS}"` to the jq arguments and `openspec_capabilities:$openspec_caps` to the registry object:

Change line 501-513 from:
```bash
RESULT="$(jq -n \
    --arg version "4.0.0" \
    --argjson skills "${SKILLS_JSON}" \
    --argjson plugins "${PLUGINS_JSON}" \
    --argjson caps "${CONTEXT_CAPS}" \
    --argjson pc "${PHASE_COMPOSITIONS}" \
    --argjson pg "${PHASE_GUIDE}" \
    --argjson mh "${METHODOLOGY_HINTS}" \
    --argjson warnings "${WARNINGS}" \
    '{
        registry: {version:$version, skills:$skills, plugins:$plugins, context_capabilities:$caps,
                   phase_compositions:$pc, phase_guide:$pg,
                   methodology_hints:$mh, warnings:$warnings},
```
To:
```bash
RESULT="$(jq -n \
    --arg version "4.0.0" \
    --argjson skills "${SKILLS_JSON}" \
    --argjson plugins "${PLUGINS_JSON}" \
    --argjson caps "${CONTEXT_CAPS}" \
    --argjson openspec_caps "${OPENSPEC_CAPS}" \
    --argjson pc "${PHASE_COMPOSITIONS}" \
    --argjson pg "${PHASE_GUIDE}" \
    --argjson mh "${METHODOLOGY_HINTS}" \
    --argjson warnings "${WARNINGS}" \
    '{
        registry: {version:$version, skills:$skills, plugins:$plugins, context_capabilities:$caps,
                   openspec_capabilities:$openspec_caps,
                   phase_compositions:$pc, phase_guide:$pg,
                   methodology_hints:$mh, warnings:$warnings},
```

- [ ] **Step 3: Add OpenSpec capability line emission (after line ~635)**

After the existing `_CAP_LINE` block, add:

```bash
# Append OpenSpec capabilities summary
_OPENSPEC_LINE="$(printf '%s' "${OPENSPEC_CAPS}" | jq -r '
    "OpenSpec: binary=\(.binary), surface=\(.surface), commands=\(.commands | join(","))"
')"
if [ -n "${_OPENSPEC_LINE}" ]; then
    CONTEXT="${CONTEXT}
${_OPENSPEC_LINE}"
fi
```

- [ ] **Step 4: Syntax check**

Run: `bash -n hooks/session-start-hook.sh`
Expected: No output.

- [ ] **Step 5: Quick smoke test**

Run: `CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' | grep "OpenSpec:"`
Expected: A line like `OpenSpec: binary=false, surface=none, commands=` (or with actual values if openspec is installed).

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: add OpenSpec bootstrap detection with workspace command discovery"
```

### Task 4: Add bootstrap detection tests to test-registry.sh

**Files:**
- Modify: `tests/test-registry.sh`

- [ ] **Step 1: Add 8 bootstrap detection tests**

Append the following test functions before the summary section in `tests/test-registry.sh`. All tests use `_OPENSPEC_WORKSPACE_OVERRIDE` to point at temp fixture directories:

```bash
# ---------------------------------------------------------------------------
# OpenSpec bootstrap detection tests
# ---------------------------------------------------------------------------
test_openspec_binary_detected() {
    echo "-- test: openspec binary detection --"
    setup_test_env

    # Create a fake openspec binary in PATH
    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local binary
    binary="$(jq -r '.openspec_capabilities.binary' "$cache" 2>/dev/null)"
    assert_equals "openspec binary detected" "true" "$binary"

    teardown_test_env
}
test_openspec_binary_detected

test_openspec_binary_absent() {
    echo "-- test: openspec binary absent --"
    setup_test_env

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local binary
    binary="$(jq -r '.openspec_capabilities.binary' "$cache" 2>/dev/null)"
    assert_equals "openspec binary absent" "false" "$binary"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is none" "none" "$surface"

    teardown_test_env
}
test_openspec_binary_absent

test_openspec_opsx_core_detection() {
    echo "-- test: OPSX core surface detection --"
    setup_test_env

    # Create fake binary + core commands
    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    local ws_dir="${HOME}/workspace"
    mkdir -p "${ws_dir}/.claude/commands/opsx"
    touch "${ws_dir}/.claude/commands/opsx/propose.md"
    touch "${ws_dir}/.claude/commands/opsx/apply.md"
    touch "${ws_dir}/.claude/commands/opsx/archive.md"
    touch "${ws_dir}/.claude/commands/opsx/explore.md"
    export _OPENSPEC_WORKSPACE_OVERRIDE="${ws_dir}"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is opsx-core" "opsx-core" "$surface"

    local cmd_count
    cmd_count="$(jq '.openspec_capabilities.commands | length' "$cache" 2>/dev/null)"
    assert_equals "4 commands detected" "4" "$cmd_count"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}
test_openspec_opsx_core_detection

test_openspec_opsx_expanded_detection() {
    echo "-- test: OPSX expanded surface detection --"
    setup_test_env

    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    local ws_dir="${HOME}/workspace"
    mkdir -p "${ws_dir}/.claude/commands/opsx"
    touch "${ws_dir}/.claude/commands/opsx/propose.md"
    touch "${ws_dir}/.claude/commands/opsx/apply.md"
    touch "${ws_dir}/.claude/commands/opsx/archive.md"
    touch "${ws_dir}/.claude/commands/opsx/new.md"
    touch "${ws_dir}/.claude/commands/opsx/ff.md"
    export _OPENSPEC_WORKSPACE_OVERRIDE="${ws_dir}"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is opsx-expanded" "opsx-expanded" "$surface"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}
test_openspec_opsx_expanded_detection

test_openspec_binary_only() {
    echo "-- test: binary only, no OPSX commands --"
    setup_test_env

    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    # No workspace commands
    export _OPENSPEC_WORKSPACE_OVERRIDE="${HOME}/empty-workspace"
    mkdir -p "${HOME}/empty-workspace"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is openspec-core" "openspec-core" "$surface"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}
test_openspec_binary_only

test_openspec_commands_without_binary() {
    echo "-- test: commands without binary (mismatch warning) --"
    setup_test_env

    # No binary, but create commands
    local ws_dir="${HOME}/workspace"
    mkdir -p "${ws_dir}/.claude/commands/opsx"
    touch "${ws_dir}/.claude/commands/opsx/propose.md"
    touch "${ws_dir}/.claude/commands/opsx/archive.md"
    export _OPENSPEC_WORKSPACE_OVERRIDE="${ws_dir}"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local surface
    surface="$(jq -r '.openspec_capabilities.surface' "$cache" 2>/dev/null)"
    assert_equals "surface is none (no binary)" "none" "$surface"

    local warnings
    warnings="$(jq -r '.openspec_capabilities.warnings[0] // ""' "$cache" 2>/dev/null)"
    assert_contains "mismatch warning" "binary missing" "$warnings"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}
test_openspec_commands_without_binary

test_openspec_capability_line_emission() {
    echo "-- test: OpenSpec capability line in session-start output --"
    setup_test_env

    local output
    output="$(run_hook)"
    local ctx
    ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

    assert_contains "OpenSpec capability line emitted" "OpenSpec:" "$ctx"
    assert_contains "has binary field" "binary=" "$ctx"
    assert_contains "has surface field" "surface=" "$ctx"

    teardown_test_env
}
test_openspec_capability_line_emission

test_openspec_workspace_only_discovery() {
    echo "-- test: workspace-only command discovery --"
    setup_test_env

    # Binary present, commands only in workspace (not in any plugin root)
    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho openspec' > "${HOME}/bin/openspec"
    chmod +x "${HOME}/bin/openspec"
    export PATH="${HOME}/bin:${PATH}"

    local ws_dir="${HOME}/workspace"
    mkdir -p "${ws_dir}/.claude/commands/opsx"
    touch "${ws_dir}/.claude/commands/opsx/propose.md"
    touch "${ws_dir}/.claude/commands/opsx/apply.md"
    touch "${ws_dir}/.claude/commands/opsx/archive.md"
    export _OPENSPEC_WORKSPACE_OVERRIDE="${ws_dir}"

    local output
    output="$(run_hook)"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    local cmd_count
    cmd_count="$(jq '.openspec_capabilities.commands | length' "$cache" 2>/dev/null)"
    assert_equals "3 commands from workspace probe" "3" "$cmd_count"

    assert_contains "propose discovered" "/opsx:propose" "$(jq -r '.openspec_capabilities.commands | join(",")' "$cache" 2>/dev/null)"

    unset _OPENSPEC_WORKSPACE_OVERRIDE
    teardown_test_env
}
test_openspec_workspace_only_discovery
```

- [ ] **Step 2: Register the new test functions in the runner section at the bottom**

Add the function names to where tests are called (they're already called inline above, so just verify they're in the right place).

- [ ] **Step 3: Run tests**

Run: `bash tests/test-registry.sh 2>&1 | grep -E "(PASS|FAIL).*openspec"`
Expected: All 8 openspec tests PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/test-registry.sh
git commit -m "test: add OpenSpec bootstrap detection tests"
```

## Chunk 3: SKILL.md Update + Fallback Registry

### Task 5: Update openspec-ship SKILL.md to consume bootstrap capabilities

**Files:**
- Modify: `skills/openspec-ship/SKILL.md`

- [ ] **Step 1: Replace Step 1 (Detect Environment) with bootstrap consumption**

Replace the current Step 1 content with:

```markdown
### Step 1: Detect Environment

**Primary:** Read the session's `OpenSpec:` capability line from the session-start output (already in conversation context). Parse `surface=` to determine the OPSX surface level.

**Fallback (if capability line not found):** Read `~/.claude/.skill-registry-cache.json` and extract `openspec_capabilities.surface`.

**Last resort (backwards compatibility):** Run `command -v openspec` to check for CLI availability.

Based on the detected surface:
- `opsx-core` or `opsx-expanded`: Use OPSX commands in later steps.
- `openspec-core`: Use CLI commands directly (no OPSX slash commands available).
- `none`: Use Claude-native fallback templates.
```

- [ ] **Step 2: Add session state consumption to Step 2 (Derive Slugs)**

Add at the beginning of Step 2:

```markdown
**Session state (primary):** Read `~/.claude/.skill-session-token` to get the session token. Then read `~/.claude/.skill-openspec-state-<token>` for pre-populated linkage:
- `changes.<slug>.sp_plan_path` → use as `plan_path`
- `changes.<slug>.sp_spec_path` → use as `spec_path`
- `changes.<slug>.capability_slug` → use as capability

If the state file exists and has the relevant change entry, use those values. Skip user prompts for fields that are already populated.

**Fallback (no state file):** Use the existing user-input flow (unchanged from current behavior).
```

- [ ] **Step 3: Add provenance write to Step 6 (Archive & Cleanup)**

Add after the "Enrich archive with Superpowers artifacts" section:

```markdown
**Write provenance metadata:**

After the archive path exists and SP artifacts (if any) have been moved:
1. Read `~/.claude/.skill-session-token` for the session token.
2. Run the `openspec_write_provenance` helper (source `hooks/lib/openspec-state.sh` from the auto-claude-skills plugin root, then call `openspec_write_provenance "<archive_path>" "<token>" "<change_slug>"`).
3. This creates `<archive_path>/superpowers/source.json` with schema_version, paths, branch, commit, surface, and timestamp.
4. If the write fails, log a warning but do not fail the archive.
```

- [ ] **Step 4: Add session state write at the start of the skill**

Add a new section after "Hard Precondition" and before "Input":

```markdown
## Session State

When this skill starts, populate the session state file with linkage information:
1. Read `~/.claude/.skill-session-token` for the session token.
2. Source `hooks/lib/openspec-state.sh` from the auto-claude-skills plugin root.
3. Call `openspec_state_upsert_change "<token>" "<change_slug>" "<plan_path>" "<spec_path>" "<capability_slug>"`.
4. If the state file doesn't exist yet (verification-before-completion hasn't run), the helper creates it with `verification_seen: false`.
```

- [ ] **Step 5: Commit**

```bash
git add skills/openspec-ship/SKILL.md
git commit -m "feat: update openspec-ship to consume bootstrap capabilities and session state"
```

### Task 6: Regenerate fallback registry

**Files:**
- Modify: `config/fallback-registry.json`

- [ ] **Step 1: Regenerate**

```bash
HOME_BAK="$HOME"
export HOME="$(mktemp -d)"
mkdir -p "$HOME/.claude"
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh >/dev/null 2>&1
cp "$HOME/.claude/.skill-registry-cache.json" config/fallback-registry.json
export HOME="$HOME_BAK"
```

- [ ] **Step 2: Verify openspec_capabilities present**

Run: `jq '.openspec_capabilities' config/fallback-registry.json`
Expected: `{"binary": false, "commands": [], "surface": "none", "warnings": []}`

- [ ] **Step 3: Validate JSON**

Run: `jq empty config/fallback-registry.json`
Expected: No output.

- [ ] **Step 4: Commit**

```bash
git add config/fallback-registry.json
git commit -m "chore: regenerate fallback registry with openspec_capabilities"
```

### Task 7: Run full test suite

**Files:** (verification only)

- [ ] **Step 1: Syntax-check all hooks**

Run: `bash -n hooks/session-start-hook.sh && bash -n hooks/skill-activation-hook.sh && bash -n hooks/lib/openspec-state.sh`
Expected: No output.

- [ ] **Step 2: Validate JSON**

Run: `jq empty config/default-triggers.json && jq empty config/fallback-registry.json`
Expected: No output.

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All new tests pass. Pre-existing registry failures (3) unchanged.

- [ ] **Step 4: Verify bootstrap with explain mode**

Run: `CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' | grep "OpenSpec:"`
Expected: `OpenSpec: binary=false, surface=none, commands=` (or actual values).
