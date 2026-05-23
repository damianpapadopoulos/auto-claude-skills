# Serena Auto-Register Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-register Serena as an MCP server (user scope) once per user, on the first session where `serena` is on PATH but unregistered, without touching user state thereafter.

**Architecture:** A new `hooks/lib/serena-autoregister.sh` library exposes a single function `serena_maybe_autoregister`. `hooks/session-start-hook.sh` sources it and invokes the function *before* the existing MCP-fallback context-capabilities block. The function is fail-open, gated on `command -v`, idempotent via a marker file at `~/.claude/.auto-claude-skills-serena-registered`. `/setup` gets a documentation update describing the marker as the recovery path.

**Tech Stack:** Bash 3.2 (macOS-compat, no associative arrays), `jq` optional (not required on this path), `claude` CLI for MCP registration, `serena` CLI as the registered server. Tests use the existing `tests/test-helpers.sh` harness with mocked `serena`/`claude` binaries on `PATH`.

**Design doc:** `docs/plans/2026-05-23-serena-auto-register-design.md`

---

## File Structure

**New files:**
- `hooks/lib/serena-autoregister.sh` — sourceable lib exposing `serena_maybe_autoregister`. ~60 lines. Single responsibility: decide whether to auto-register and do it.
- `tests/test-serena-autoregister.sh` — unit tests with mocked `serena`/`claude` binaries on `PATH`. ~200 lines.

**Modified files:**
- `hooks/session-start-hook.sh` — source the new lib (one line) and call `serena_maybe_autoregister` (one line) immediately before the `_CANONICAL_CAP_KEYS` block at line ~761.
- `commands/setup.md` — add a "Recovering / re-triggering auto-registration" subsection in the Serena block (after line ~265).
- `CHANGELOG.md` — add one entry under `[Unreleased]`.

**Why a sourceable lib instead of inlining:** The function needs unit tests with mocked binaries. Inlining inside `session-start-hook.sh` would require running the full session-start flow per test (slow, sets up unrelated state). A standalone lib is testable in isolation. Matches the existing pattern (`hooks/lib/openspec-state.sh`).

---

## Task 1: Write failing tests for `serena_maybe_autoregister`

**Files:**
- Create: `tests/test-serena-autoregister.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# test-serena-autoregister.sh — Tests for hooks/lib/serena-autoregister.sh
# Bash 3.2 compatible. Uses mocked `serena` and `claude` binaries on PATH.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

LIB="${PROJECT_ROOT}/hooks/lib/serena-autoregister.sh"

# ---------------------------------------------------------------------------
# Mock helpers: create fake `serena` and `claude` binaries on a temp PATH.
# Each mock records its invocations to ${MOCK_LOG} so tests can assert calls.
# ---------------------------------------------------------------------------
_setup_mocks() {
    MOCK_BIN="${TEST_TMPDIR}/bin"
    MOCK_LOG="${TEST_TMPDIR}/mock-calls.log"
    mkdir -p "${MOCK_BIN}"
    : >"${MOCK_LOG}"

    # Mock `serena` — just needs to exist on PATH so `command -v serena` succeeds.
    cat >"${MOCK_BIN}/serena" <<'EOF'
#!/usr/bin/env bash
echo "serena $*" >>"${MOCK_LOG}"
exit 0
EOF
    chmod +x "${MOCK_BIN}/serena"

    # Mock `claude` — supports `mcp list` and `mcp add` subcommands.
    # Behavior controlled by env vars:
    #   MOCK_CLAUDE_LIST_HAS_SERENA=1 → `mcp list` includes a serena entry
    #   MOCK_CLAUDE_ADD_FAILS=1 → `mcp add` exits 1
    cat >"${MOCK_BIN}/claude" <<'EOF'
#!/usr/bin/env bash
echo "claude $*" >>"${MOCK_LOG}"
if [ "$1" = "mcp" ] && [ "$2" = "list" ]; then
    if [ "${MOCK_CLAUDE_LIST_HAS_SERENA:-0}" = "1" ]; then
        echo "serena: serena start-mcp-server --context claude-code"
    fi
    echo "other-server: foo"
    exit 0
fi
if [ "$1" = "mcp" ] && [ "$2" = "add" ]; then
    if [ "${MOCK_CLAUDE_ADD_FAILS:-0}" = "1" ]; then
        echo "Error: failed to add" >&2
        exit 1
    fi
    exit 0
fi
exit 0
EOF
    chmod +x "${MOCK_BIN}/claude"

    export MOCK_LOG
    export PATH="${MOCK_BIN}:${PATH}"
}

_teardown_mocks() {
    unset MOCK_CLAUDE_LIST_HAS_SERENA MOCK_CLAUDE_ADD_FAILS
}

_marker_path() {
    printf '%s/.claude/.auto-claude-skills-serena-registered' "${HOME}"
}

_error_path() {
    printf '%s/.claude/.auto-claude-skills-serena-register-error' "${HOME}"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_eligible_and_not_registered_runs_mcp_add_and_writes_marker() {
    echo "-- test: eligible + not registered → mcp add + marker written --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"

    # shellcheck source=hooks/lib/serena-autoregister.sh
    . "${LIB}"
    serena_maybe_autoregister

    assert_file_exists "marker file written" "$(_marker_path)"
    if grep -qF 'claude mcp add --scope user serena' "${MOCK_LOG}"; then
        echo "  PASS: claude mcp add invoked with --scope user"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: expected 'claude mcp add --scope user serena' in mock log"
        echo "  log: $(cat "${MOCK_LOG}")"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    _teardown_mocks
    teardown_test_env
}

test_already_registered_skips_add_but_writes_marker() {
    echo "-- test: already registered → skip add, still write marker --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"
    export MOCK_CLAUDE_LIST_HAS_SERENA=1

    . "${LIB}"
    serena_maybe_autoregister

    assert_file_exists "marker file written" "$(_marker_path)"
    if grep -qF 'claude mcp add' "${MOCK_LOG}"; then
        echo "  FAIL: should NOT have invoked 'claude mcp add' (already registered)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "  PASS: 'claude mcp add' skipped because serena already in mcp list"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    _teardown_mocks
    teardown_test_env
}

test_marker_exists_is_noop() {
    echo "-- test: marker file already exists → fully no-op --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"
    : >"$(_marker_path)"

    . "${LIB}"
    serena_maybe_autoregister

    if [ -s "${MOCK_LOG}" ]; then
        echo "  FAIL: expected mock log to be empty when marker exists"
        echo "  log: $(cat "${MOCK_LOG}")"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "  PASS: no mock binaries invoked when marker present"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    _teardown_mocks
    teardown_test_env
}

test_no_serena_on_path_is_noop() {
    echo "-- test: serena not on PATH → no-op, no marker --"
    setup_test_env
    # Deliberately skip _setup_mocks → no `serena`/`claude` on PATH.
    # Sanitize PATH to ensure no system serena leaks in.
    export PATH="/usr/bin:/bin"
    mkdir -p "${HOME}/.claude"

    . "${LIB}"
    serena_maybe_autoregister

    if [ -e "$(_marker_path)" ]; then
        echo "  FAIL: marker should NOT be written when serena absent"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "  PASS: no marker written when serena absent"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    teardown_test_env
}

test_no_claude_cli_is_noop() {
    echo "-- test: claude CLI missing → no-op, no marker --"
    setup_test_env
    MOCK_BIN="${TEST_TMPDIR}/bin"
    MOCK_LOG="${TEST_TMPDIR}/mock-calls.log"
    mkdir -p "${MOCK_BIN}"
    : >"${MOCK_LOG}"
    # Provide only serena, NOT claude
    cat >"${MOCK_BIN}/serena" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${MOCK_BIN}/serena"
    export PATH="${MOCK_BIN}:/usr/bin:/bin"
    export MOCK_LOG
    mkdir -p "${HOME}/.claude"

    . "${LIB}"
    serena_maybe_autoregister

    if [ -e "$(_marker_path)" ]; then
        echo "  FAIL: marker should NOT be written when claude CLI absent"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "  PASS: no marker written when claude CLI absent"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    teardown_test_env
}

test_mcp_add_failure_writes_marker_and_error_breadcrumb() {
    echo "-- test: mcp add fails → marker still written + error breadcrumb --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"
    export MOCK_CLAUDE_ADD_FAILS=1

    . "${LIB}"
    serena_maybe_autoregister

    assert_file_exists "marker written even on failure" "$(_marker_path)"
    assert_file_exists "error breadcrumb written" "$(_error_path)"

    _teardown_mocks
    teardown_test_env
}

test_function_exit_code_is_always_zero() {
    echo "-- test: function never propagates non-zero exit (fail-open) --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"
    export MOCK_CLAUDE_ADD_FAILS=1

    . "${LIB}"
    set +e
    serena_maybe_autoregister
    local rc=$?
    set -e
    assert_equals "exit code is 0 on add failure" "0" "${rc}"

    _teardown_mocks
    teardown_test_env
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
echo "=== test-serena-autoregister.sh ==="
test_eligible_and_not_registered_runs_mcp_add_and_writes_marker
test_already_registered_skips_add_but_writes_marker
test_marker_exists_is_noop
test_no_serena_on_path_is_noop
test_no_claude_cli_is_noop
test_mcp_add_failure_writes_marker_and_error_breadcrumb
test_function_exit_code_is_always_zero

print_test_summary
exit $((TESTS_FAILED == 0 ? 0 : 1))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/test-serena-autoregister.sh
```

Expected: ALL tests FAIL because `hooks/lib/serena-autoregister.sh` does not yet exist. The `. "${LIB}"` source line will error with "No such file or directory."

- [ ] **Step 3: Verify `tests/test-helpers.sh` exposes the helpers used**

```bash
grep -E "^(assert_file_exists|assert_equals|print_test_summary)\(\)" tests/test-helpers.sh
```

Expected output: all three helpers listed. If any are missing, add minimal stubs to `tests/test-helpers.sh` matching the existing style (e.g., `assert_file_exists() { [ -e "$2" ] && ... }`). The existing helpers file already has `assert_equals` and `print_test_summary` per the codebase scan; verify `assert_file_exists` is present too.

If `assert_file_exists` is missing, add this above the `print_test_summary` function in `tests/test-helpers.sh`:

```bash
assert_file_exists() {
    local label="$1" path="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -e "${path}" ]; then
        echo "  PASS: ${label}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: ${label} (path missing: ${path})"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAIL_MESSAGES="${FAIL_MESSAGES}
  - ${label}: missing ${path}"
    fi
}
```

- [ ] **Step 4: Commit the failing test (and helper stub if added)**

```bash
git add tests/test-serena-autoregister.sh
git add tests/test-helpers.sh 2>/dev/null || true  # only if you modified it
git commit -m "test: add failing tests for serena auto-register library"
```

---

## Task 2: Implement `hooks/lib/serena-autoregister.sh`

**Files:**
- Create: `hooks/lib/serena-autoregister.sh`
- Test: `tests/test-serena-autoregister.sh`

- [ ] **Step 1: Write the library**

```bash
#!/usr/bin/env bash
# serena-autoregister.sh — First-time auto-registration of Serena MCP server.
#
# Sourceable lib. Exposes one function: serena_maybe_autoregister.
#
# Behavior (all checks fail-open; function NEVER propagates non-zero):
#   1. Skip if marker file exists at ~/.claude/.auto-claude-skills-serena-registered
#   2. Skip if `serena` is not on PATH
#   3. Skip if `claude` CLI is not on PATH
#   4. If `claude mcp list` already contains a `serena:` entry → skip add, write marker
#   5. Otherwise: run `claude mcp add --scope user serena -- serena start-mcp-server
#      --context claude-code --project-from-cwd`. Write marker on either outcome
#      (success or failure). On failure also write an error breadcrumb that
#      /setup can surface.
#
# Bash 3.2 compatible. jq NOT required on this path.
# Design: docs/plans/2026-05-23-serena-auto-register-design.md

serena_maybe_autoregister() {
    local marker="${HOME}/.claude/.auto-claude-skills-serena-registered"
    local err_breadcrumb="${HOME}/.claude/.auto-claude-skills-serena-register-error"

    # 1. Idempotency: marker exists → fully no-op
    [ -e "${marker}" ] && return 0

    # 2. Eligibility: serena binary on PATH
    command -v serena >/dev/null 2>&1 || return 0

    # 3. Eligibility: claude CLI on PATH
    command -v claude >/dev/null 2>&1 || return 0

    # 4. Already-registered short-circuit. Match the line-prefix pattern used
    #    by hooks/session-start-hook.sh:812 for SERENA_CONNECTION_CHECK so the
    #    detection contract stays consistent.
    if claude mcp list 2>/dev/null | grep -q '^serena: '; then
        printf '%s\t%s\talready-registered\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$$" >"${marker}" 2>/dev/null || true
        [ "${SKILL_EXPLAIN:-0}" = "1" ] && echo "[serena-autoregister] already-registered, marker written" >&2
        return 0
    fi

    # 5. Auto-register. Project-from-cwd lets Serena pick the active project
    #    per-session without binding the user-scoped registration to one path.
    local add_output add_rc
    add_output="$(claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false 2>&1)"
    add_rc=$?

    if [ "${add_rc}" -eq 0 ]; then
        printf '%s\t%s\tregistered\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$$" >"${marker}" 2>/dev/null || true
        [ "${SKILL_EXPLAIN:-0}" = "1" ] && echo "[serena-autoregister] registered successfully, marker written" >&2
    else
        # Failure path: write marker so we don't spam retries every session.
        # Also write an error breadcrumb /setup can surface.
        printf '%s\t%s\tregister-failed\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$$" >"${marker}" 2>/dev/null || true
        printf '%s\trc=%s\noutput:\n%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "${add_rc}" "${add_output}" >"${err_breadcrumb}" 2>/dev/null || true
        [ "${SKILL_EXPLAIN:-0}" = "1" ] && echo "[serena-autoregister] claude mcp add failed (rc=${add_rc}); marker + error breadcrumb written" >&2
    fi

    return 0
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bash tests/test-serena-autoregister.sh
```

Expected output: every `-- test: ... --` followed by `PASS` lines, and a final summary `Tests run: 7, passed: 7, failed: 0`.

If any test fails, read the FAIL line carefully and fix the implementation — do NOT modify the tests to make them pass.

- [ ] **Step 3: Lint the new library with bash -n**

```bash
bash -n hooks/lib/serena-autoregister.sh
```

Expected: silent success (exit 0).

- [ ] **Step 4: Commit**

```bash
git add hooks/lib/serena-autoregister.sh
git commit -m "feat: add hooks/lib/serena-autoregister.sh — first-time MCP registration"
```

---

## Task 3: Wire the library into `session-start-hook.sh`

**Files:**
- Modify: `hooks/session-start-hook.sh` (insert at ~line 760, before `_CANONICAL_CAP_KEYS`)
- Modify: `tests/test-registry.sh` (add one integration test)

- [ ] **Step 1: Write the failing integration test**

Append to `tests/test-registry.sh` just before the final runner block. Find the existing `test_serena_capability_*` cluster (around line 540) and add this test next to it:

```bash
test_serena_auto_registration_runs_on_first_session() {
    echo "-- test: session-start auto-registers serena when eligible, marker absent --"
    setup_test_env

    # Set up mock binaries on PATH (serena + claude that records calls).
    local mock_bin="${TEST_TMPDIR}/bin"
    local mock_log="${TEST_TMPDIR}/mock-calls.log"
    mkdir -p "${mock_bin}"
    : >"${mock_log}"

    cat >"${mock_bin}/serena" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${mock_bin}/serena"

    cat >"${mock_bin}/claude" <<EOF
#!/usr/bin/env bash
echo "claude \$*" >>"${mock_log}"
if [ "\$1" = "mcp" ] && [ "\$2" = "list" ]; then
    echo "other: foo"
    exit 0
fi
exit 0
EOF
    chmod +x "${mock_bin}/claude"

    PATH="${mock_bin}:${PATH}" _SKILL_TEST_MODE=1 CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" >/dev/null 2>&1 < /dev/null

    local marker="${HOME}/.claude/.auto-claude-skills-serena-registered"
    if [ -e "${marker}" ]; then
        echo "  PASS: marker written by session-start hook"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: expected marker at ${marker}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    if grep -qF 'claude mcp add --scope user serena' "${mock_log}"; then
        echo "  PASS: session-start invoked claude mcp add --scope user serena"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: session-start did not invoke claude mcp add"
        echo "  log: $(cat "${mock_log}")"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    teardown_test_env
}
```

Then add the function name to the runner block at the bottom of `tests/test-registry.sh` (find where other `test_serena_*` functions are called and append):

```bash
test_serena_auto_registration_runs_on_first_session
```

- [ ] **Step 2: Run the new test to verify it fails**

```bash
bash tests/test-registry.sh 2>&1 | grep -A2 "auto-register"
```

Expected: FAIL — session-start does not yet source the lib.

- [ ] **Step 3: Add the source + call to `session-start-hook.sh`**

Open `hooks/session-start-hook.sh` and find the line immediately before the `_CANONICAL_CAP_KEYS` comment block (currently line ~761, the comment starts with `# Canonical context_capabilities keys.`). Insert these lines directly above it:

```bash
# Serena first-time auto-register: if `serena` is on PATH and no `serena` MCP
# entry exists yet (and the per-user marker isn't already set), register it
# silently with --scope user. Idempotent and fail-open. See
# hooks/lib/serena-autoregister.sh for the full contract and
# docs/plans/2026-05-23-serena-auto-register-design.md for the design rationale.
# shellcheck source=lib/serena-autoregister.sh
. "$(dirname "$0")/lib/serena-autoregister.sh" 2>/dev/null && serena_maybe_autoregister || true
```

Use Edit, not Write — the existing file is large and full-rewrite risks breaking unrelated state (per CLAUDE.md guidance: "When editing files, never replace full content if only a section needs changing").

- [ ] **Step 4: Verify the existing session-start tests still pass**

```bash
bash tests/test-registry.sh
```

Expected: all tests including the new `auto-register` test pass. The pre-existing `test serena is false (not installed)` test (around line 540) MUST still pass — it asserts `serena=false` when `serena` is not on PATH, which is the no-op branch in our function.

- [ ] **Step 5: Verify full test suite still green**

```bash
bash tests/run-tests.sh 2>&1 | tail -20
```

Expected: 0 failures across all test files. Any pre-existing failures are unrelated to this change — if you see new failures, they almost certainly mean the `. "$(dirname "$0")/lib/serena-autoregister.sh"` line is in the wrong place or breaking sourcing.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "feat(session-start): wire serena auto-register lib into session-start hook"
```

---

## Task 4: Document the recovery path in `commands/setup.md`

**Files:**
- Modify: `commands/setup.md` (Serena section, around line 265 after the canonical `claude mcp add` block)

- [ ] **Step 1: Read the Serena section to find insertion point**

```bash
sed -n '255,290p' commands/setup.md
```

Note the line that ends with `claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false` (currently line ~264). Insert the new subsection AFTER that block but BEFORE the upgrade instructions ("If the user already has Serena registered via the old `uvx --from git+` method...").

- [ ] **Step 2: Insert the new subsection**

Use Edit with `old_string` matching the line immediately before the upgrade-instructions paragraph, and `new_string` that adds the new subsection plus the original line. Example:

```
old_string: (the paragraph that begins "If the user already has Serena registered via the old `uvx --from git+`")

new_string:
**Recovering / re-triggering auto-registration**

The plugin auto-registers Serena on the first session where `serena` is on PATH and no MCP registration exists. The registered command includes `--open-web-dashboard false` so Serena does NOT open a browser tab on each Claude Code session start. The dashboard itself remains enabled and is reachable at http://localhost:24282/dashboard/ for users who want it.

After auto-registration, the plugin writes `~/.claude/.auto-claude-skills-serena-registered` and never touches your MCP config again. **If you WANT the browser tab back:** edit `~/.claude.json` and remove `--open-web-dashboard false` from the `mcpServers.serena.args` array (or change it to `true`). This is a per-MCP-server override; the plugin does NOT modify your global `~/.serena/serena_config.yml`.

If you want the plugin to re-attempt auto-registration (e.g., because you manually removed Serena to fix a broken venv and want it re-added on the next session):

```bash
rm -f ~/.claude/.auto-claude-skills-serena-registered
```

If a previous auto-registration attempt failed, the error is preserved at `~/.claude/.auto-claude-skills-serena-register-error`. Inspect it before re-attempting:

```bash
cat ~/.claude/.auto-claude-skills-serena-register-error
```

(the original "If the user already has Serena registered via..." paragraph here)
```

- [ ] **Step 3: Verify the doc reads cleanly**

```bash
sed -n '255,310p' commands/setup.md
```

Expected: new subsection appears between the user-scope `claude mcp add` command and the legacy-upgrade instructions, with no broken markdown.

- [ ] **Step 4: Commit**

```bash
git add commands/setup.md
git commit -m "docs(setup): document serena auto-register marker as recovery path"
```

---

## Task 5: Update CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Read the current `[Unreleased]` section**

```bash
sed -n '1,40p' CHANGELOG.md
```

- [ ] **Step 2: Add the entry**

Per the project's CHANGELOG convention (`reference_changelog_and_version_convention` in user memory: "`[Unreleased]` is an accumulator"), append to the existing `[Unreleased]` block. If `[Unreleased]` has subsection headers like `### Added` / `### Changed`, add under `### Added`. Otherwise prepend a bullet to the section.

```markdown
- `hooks/lib/serena-autoregister.sh` + session-start integration: first-time auto-registration of Serena as a user-scoped MCP server when `serena` is on PATH and no existing registration is found. The registered command includes `--open-web-dashboard false` so Serena does NOT open a browser tab on each Claude Code session start (the dashboard remains accessible at `http://localhost:24282/dashboard/`). Writes `~/.claude/.auto-claude-skills-serena-registered` to prevent retries; failures are captured to `~/.claude/.auto-claude-skills-serena-register-error` for `/setup` to surface. Recovery: `rm -f ~/.claude/.auto-claude-skills-serena-registered`. Fail-open: function never propagates non-zero exit, and the session-start hook continues on source/call failure. Does NOT modify `~/.serena/serena_config.yml`. Capability: `skill-routing`.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): record serena auto-register feature"
```

---

## Task 6: Manual smoke test

**Files:** none modified — verification only

- [ ] **Step 1: Clear any existing marker (your machine)**

```bash
rm -f ~/.claude/.auto-claude-skills-serena-registered
rm -f ~/.claude/.auto-claude-skills-serena-register-error
```

- [ ] **Step 2: Confirm pre-conditions**

```bash
command -v serena && echo "serena on PATH: OK"
command -v claude && echo "claude on PATH: OK"
claude mcp list | grep '^serena: ' && echo "serena already registered — auto-register will be a no-op + marker write" || echo "serena NOT registered — auto-register will run mcp add"
```

- [ ] **Step 3: Trigger session-start manually**

```bash
SKILL_EXPLAIN=1 bash hooks/session-start-hook.sh < /dev/null 2>&1 | grep -i 'serena' || true
```

Expected (when not already registered): you see a `[serena-autoregister] registered successfully, marker written` line on stderr (captured by `2>&1`).

Expected (when already registered): you see `[serena-autoregister] already-registered, marker written`.

- [ ] **Step 4: Verify marker exists and inspect it**

```bash
ls -la ~/.claude/.auto-claude-skills-serena-registered
cat ~/.claude/.auto-claude-skills-serena-registered
```

Expected: file exists, contains a TSV line `<ISO timestamp>\t<PID>\t<registered|already-registered|register-failed>`.

- [ ] **Step 5: Confirm idempotency**

```bash
SKILL_EXPLAIN=1 bash hooks/session-start-hook.sh < /dev/null 2>&1 | grep -i 'serena' || echo "(no serena line — marker prevented re-run, as expected)"
```

Expected: no `[serena-autoregister]` breadcrumb on the second run.

- [ ] **Step 6: Confirm `claude mcp list` now shows serena**

```bash
claude mcp list | grep '^serena: '
```

Expected (only meaningful on the "fresh registration" path): one line beginning with `serena: serena start-mcp-server --context claude-code --project-from-cwd`.

- [ ] **Step 7: Run the full test suite one final time**

```bash
bash tests/run-tests.sh 2>&1 | tail -10
```

Expected: 0 failures.

---

## Self-Review (done before handing off to executing agent)

**1. Spec coverage** — All four design-doc Acceptance Scenarios are exercised:
- Scenario 1 (fresh + eligible) → Task 1's `test_eligible_and_not_registered_runs_mcp_add_and_writes_marker` + Task 3's integration test + Task 6 smoke step 3.
- Scenario 2 (already registered) → Task 1's `test_already_registered_skips_add_but_writes_marker`.
- Scenario 3 (intentional removal) → Task 1's `test_marker_exists_is_noop` (marker present → no-op even if registration would otherwise be eligible).
- Scenario 4 (no serena binary) → Task 1's `test_no_serena_on_path_is_noop`.

**2. Placeholder scan** — No `TBD` / `TODO` / "implement later". Every step has either runnable commands or complete code.

**3. Type/name consistency** — The function is `serena_maybe_autoregister` in every reference (lib, source line, tests). Marker path is `~/.claude/.auto-claude-skills-serena-registered` everywhere. Error breadcrumb is `~/.claude/.auto-claude-skills-serena-register-error` everywhere.

**4. Out-of-scope respected** — Plan does not touch `.serena/project.yml`, language detection, serena-hooks installation, old-uvx upgrade flow, or other MCPs.
