# Insights Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt four improvements from the Claude Code Insights analysis — two CLAUDE.md additions, an on-demand observability preflight script, and a REVIEW-before-SHIP guard in openspec-guard.sh.

**Architecture:** Two one-liner CLAUDE.md additions (no code). A shared bash script `scripts/obs-preflight.sh` that checks gcloud auth, observability MCP, and kubectl reachability — invoked on-demand by incident-analysis/alert-hygiene/investigate, not at session start (respects 200ms budget). An extension to `hooks/openspec-guard.sh` that reads composition state to warn when REVIEW was skipped before SHIP.

**Tech Stack:** Bash 3.2 (macOS), jq, existing test-helpers.sh assertion framework

---

### Task 1: CLAUDE.md Additions

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add "proceed means continue" instruction**

Add to the `## Gotchas` section of `CLAUDE.md`:

```markdown
- When user says "proceed", continue with the next logical step. Do not ask "what would you like to proceed with?" — infer from context.
```

- [ ] **Step 2: Add "no full-file rewrites" instruction**

Add to the `## Style` section of `CLAUDE.md`:

```markdown
- When editing files, never replace full content if only a section needs changing. Preserve existing data in YAML/JSON files. Use targeted edits, not full-file rewrites.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add proceed-inference and no-full-rewrite rules to CLAUDE.md"
```

---

### Task 2: Observability Preflight Script

**Files:**
- Create: `scripts/obs-preflight.sh`
- Test: `tests/test-obs-preflight.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# test-obs-preflight.sh — Tests for on-demand observability preflight
# Bash 3.2 compatible. Sources test-helpers.sh for assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

. "${SCRIPT_DIR}/test-helpers.sh"

PREFLIGHT="${PROJECT_ROOT}/scripts/obs-preflight.sh"

echo "=== test-obs-preflight.sh ==="

# ---------------------------------------------------------------------------
# 1. Script exits 0 and produces valid JSON even when tools are missing
# ---------------------------------------------------------------------------
test_missing_tools_produce_valid_json() {
    echo "-- test: missing tools produce valid JSON --"
    setup_test_env

    # Override PATH to ensure gcloud/kubectl are not found
    local output
    output="$(PATH=/usr/bin:/bin bash "${PREFLIGHT}" 2>/dev/null)"

    assert_not_empty "output is non-empty" "${output}"

    local tmpfile="${TEST_TMPDIR}/preflight.json"
    printf '%s' "${output}" > "${tmpfile}"
    assert_json_valid "output is valid JSON" "${tmpfile}"

    local gcloud_status
    gcloud_status="$(printf '%s' "${output}" | jq -r '.gcloud' 2>/dev/null)"
    assert_equals "gcloud is missing" "missing" "${gcloud_status}"

    local kubectl_status
    kubectl_status="$(printf '%s' "${output}" | jq -r '.kubectl' 2>/dev/null)"
    assert_equals "kubectl is missing" "missing" "${kubectl_status}"

    local obs_mcp_status
    obs_mcp_status="$(printf '%s' "${output}" | jq -r '.observability_mcp' 2>/dev/null)"
    assert_equals "observability_mcp is unavailable" "unavailable" "${obs_mcp_status}"

    teardown_test_env
}
test_missing_tools_produce_valid_json

# ---------------------------------------------------------------------------
# 2. MCP detection reads from ~/.claude.json
# ---------------------------------------------------------------------------
test_mcp_detection_from_claude_json() {
    echo "-- test: MCP detection reads ~/.claude.json --"
    setup_test_env

    # Create a fake ~/.claude.json with gcp-observability configured
    cat > "${HOME}/.claude.json" << 'MCPEOF'
{"mcpServers":{"gcp-observability":{"command":"npx","args":["@anthropic/gcp-observability-mcp"]}}}
MCPEOF

    local output
    output="$(PATH=/usr/bin:/bin bash "${PREFLIGHT}" 2>/dev/null)"

    local obs_mcp_status
    obs_mcp_status="$(printf '%s' "${output}" | jq -r '.observability_mcp' 2>/dev/null)"
    assert_equals "observability_mcp is configured" "configured" "${obs_mcp_status}"

    teardown_test_env
}
test_mcp_detection_from_claude_json

# ---------------------------------------------------------------------------
# 3. gcloud present but unauthenticated
# ---------------------------------------------------------------------------
test_gcloud_unauthenticated() {
    echo "-- test: gcloud present but unauthenticated --"
    setup_test_env

    # Create a fake gcloud that exits 1 on auth check
    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/gcloud" << 'GCEOF'
#!/bin/bash
if [[ "$*" == *"auth list"* ]]; then
    echo "No credentialed accounts."
    exit 1
fi
exit 0
GCEOF
    chmod +x "${TEST_TMPDIR}/bin/gcloud"

    local output
    output="$(PATH="${TEST_TMPDIR}/bin:/usr/bin:/bin" bash "${PREFLIGHT}" 2>/dev/null)"

    local gcloud_status
    gcloud_status="$(printf '%s' "${output}" | jq -r '.gcloud' 2>/dev/null)"
    assert_equals "gcloud is unauthenticated" "unauthenticated" "${gcloud_status}"

    teardown_test_env
}
test_gcloud_unauthenticated

# ---------------------------------------------------------------------------
# 4. gcloud present and authenticated
# ---------------------------------------------------------------------------
test_gcloud_authenticated() {
    echo "-- test: gcloud present and authenticated --"
    setup_test_env

    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/gcloud" << 'GCEOF'
#!/bin/bash
if [[ "$*" == *"auth list"* ]]; then
    echo "       ACTIVE  ACCOUNT"
    echo "*      user@example.com"
    exit 0
fi
exit 0
GCEOF
    chmod +x "${TEST_TMPDIR}/bin/gcloud"

    local output
    output="$(PATH="${TEST_TMPDIR}/bin:/usr/bin:/bin" bash "${PREFLIGHT}" 2>/dev/null)"

    local gcloud_status
    gcloud_status="$(printf '%s' "${output}" | jq -r '.gcloud' 2>/dev/null)"
    assert_equals "gcloud is ready" "ready" "${gcloud_status}"

    teardown_test_env
}
test_gcloud_authenticated

# ---------------------------------------------------------------------------
# 5. kubectl present but unreachable
# ---------------------------------------------------------------------------
test_kubectl_unreachable() {
    echo "-- test: kubectl present but unreachable --"
    setup_test_env

    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/kubectl" << 'KEOF'
#!/bin/bash
exit 1
KEOF
    chmod +x "${TEST_TMPDIR}/bin/kubectl"

    local output
    output="$(PATH="${TEST_TMPDIR}/bin:/usr/bin:/bin" bash "${PREFLIGHT}" 2>/dev/null)"

    local kubectl_status
    kubectl_status="$(printf '%s' "${output}" | jq -r '.kubectl' 2>/dev/null)"
    assert_equals "kubectl is unreachable" "unreachable" "${kubectl_status}"

    teardown_test_env
}
test_kubectl_unreachable

# ---------------------------------------------------------------------------
# 6. Summary line present
# ---------------------------------------------------------------------------
test_summary_line() {
    echo "-- test: summary line present --"
    setup_test_env

    local output
    output="$(PATH=/usr/bin:/bin bash "${PREFLIGHT}" 2>/dev/null)"

    local summary
    summary="$(printf '%s' "${output}" | jq -r '.summary' 2>/dev/null)"
    assert_not_empty "summary is non-empty" "${summary}"

    teardown_test_env
}
test_summary_line

# ---------------------------------------------------------------------------
# 7. Exit code is always 0 (fail-open)
# ---------------------------------------------------------------------------
test_exit_code_always_zero() {
    echo "-- test: exit code is always 0 --"
    setup_test_env

    PATH=/usr/bin:/bin bash "${PREFLIGHT}" >/dev/null 2>&1
    local rc=$?
    assert_equals "exit code is 0" "0" "${rc}"

    teardown_test_env
}
test_exit_code_always_zero

# ---------------------------------------------------------------------------
print_summary
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bash tests/test-obs-preflight.sh
```

Expected: All tests FAIL (script does not exist yet).

- [ ] **Step 3: Write the preflight script**

```bash
#!/usr/bin/env bash
# obs-preflight.sh — On-demand observability environment check
# Called by incident-analysis, alert-hygiene, and /investigate before data pulls.
# Outputs JSON to stdout. Exits 0 always (fail-open).
# Bash 3.2 compatible.

trap 'printf "{\"gcloud\":\"error\",\"kubectl\":\"error\",\"observability_mcp\":\"error\",\"summary\":\"preflight errored — proceeding without checks\"}\n"; exit 0' ERR

# --- gcloud ---
_GCLOUD="missing"
if command -v gcloud >/dev/null 2>&1; then
    if gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | grep -q '@'; then
        _GCLOUD="ready"
    else
        _GCLOUD="unauthenticated"
    fi
fi

# --- kubectl ---
_KUBECTL="missing"
if command -v kubectl >/dev/null 2>&1; then
    if kubectl cluster-info --request-timeout=3s >/dev/null 2>&1; then
        _KUBECTL="ready"
    else
        _KUBECTL="unreachable"
    fi
fi

# --- observability MCP ---
_OBS_MCP="unavailable"
if [ -f "${HOME}/.claude.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq -e '.mcpServers["gcp-observability"] // .mcpServers["observability"]' "${HOME}/.claude.json" >/dev/null 2>&1 && _OBS_MCP="configured"
    else
        grep -q '"gcp-observability"\|"observability"' "${HOME}/.claude.json" 2>/dev/null && _OBS_MCP="configured"
    fi
fi

# --- Build summary ---
_ISSUES=""
case "${_GCLOUD}" in
    missing)         _ISSUES="gcloud not installed" ;;
    unauthenticated) _ISSUES="gcloud not authenticated — run: gcloud auth login" ;;
esac
case "${_KUBECTL}" in
    missing)     [ -n "${_ISSUES}" ] && _ISSUES="${_ISSUES}; "; _ISSUES="${_ISSUES}kubectl not installed" ;;
    unreachable) [ -n "${_ISSUES}" ] && _ISSUES="${_ISSUES}; "; _ISSUES="${_ISSUES}kubectl unreachable — check cluster context" ;;
esac
case "${_OBS_MCP}" in
    unavailable) [ -n "${_ISSUES}" ] && _ISSUES="${_ISSUES}; "; _ISSUES="${_ISSUES}observability MCP not configured — run /setup for Tier 1" ;;
esac

_SUMMARY="all checks passed"
[ -n "${_ISSUES}" ] && _SUMMARY="${_ISSUES}"

# --- Output JSON ---
if command -v jq >/dev/null 2>&1; then
    jq -n \
        --arg g "${_GCLOUD}" \
        --arg k "${_KUBECTL}" \
        --arg m "${_OBS_MCP}" \
        --arg s "${_SUMMARY}" \
        '{gcloud:$g, kubectl:$k, observability_mcp:$m, summary:$s}'
else
    printf '{"gcloud":"%s","kubectl":"%s","observability_mcp":"%s","summary":"%s"}\n' \
        "${_GCLOUD}" "${_KUBECTL}" "${_OBS_MCP}" "${_SUMMARY}"
fi
exit 0
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bash tests/test-obs-preflight.sh
```

Expected: 7/7 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/obs-preflight.sh tests/test-obs-preflight.sh
git commit -m "feat: add on-demand observability preflight script with tests"
```

---

### Task 3: Wire Preflight Into Skills

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` (Step 1: Detect Available Tools section, ~line 57)
- Modify: `skills/alert-hygiene/SKILL.md` (Tier Detection section, ~line 39)
- Modify: `commands/investigate.md`
- Test: `tests/test-skill-content.sh` (add content assertions)

- [ ] **Step 1: Write content test for preflight references**

Add to `tests/test-skill-content.sh` (or create a new targeted test if that file doesn't cover skill content):

```bash
# --- Observability preflight wiring ---
test_incident_analysis_references_preflight() {
    echo "-- test: incident-analysis references obs-preflight --"
    local skill="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md"
    local content
    content="$(cat "${skill}")"
    assert_contains "incident-analysis references obs-preflight" "obs-preflight.sh" "${content}"
}
test_incident_analysis_references_preflight

test_alert_hygiene_references_preflight() {
    echo "-- test: alert-hygiene references obs-preflight --"
    local skill="${PROJECT_ROOT}/skills/alert-hygiene/SKILL.md"
    local content
    content="$(cat "${skill}")"
    assert_contains "alert-hygiene references obs-preflight" "obs-preflight.sh" "${content}"
}
test_alert_hygiene_references_preflight

test_investigate_references_preflight() {
    echo "-- test: investigate references obs-preflight --"
    local cmd="${PROJECT_ROOT}/commands/investigate.md"
    local content
    content="$(cat "${cmd}")"
    assert_contains "investigate references obs-preflight" "obs-preflight.sh" "${content}"
}
test_investigate_references_preflight
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bash tests/test-skill-content.sh
```

Expected: The 3 new assertions FAIL (skills don't reference preflight yet).

- [ ] **Step 3: Add preflight to incident-analysis Step 1**

In `skills/incident-analysis/SKILL.md`, replace the current "Step 1: Detect Available Tools" section (lines 57-77) with:

```markdown
### Step 1: Detect Available Tools

Run the shared observability preflight to determine the execution tier:

```bash
bash "$(dirname "$0")/../scripts/obs-preflight.sh"
```

Parse the JSON output to select the tier:

| `gcloud` | `observability_mcp` | Tier |
|-----------|---------------------|------|
| any | configured + tools available in session | **Tier 1 — MCP** |
| ready | any | **Tier 2 — gcloud CLI** |
| missing or unauthenticated | unavailable | **Tier 3 — Guidance-only** |

**Tier 1 — MCP (`@google-cloud/observability-mcp`):**
If you have access to `list_log_entries`, `search_traces`, `get_trace`, `list_time_series`, or `list_alert_policies` as MCP tools in this session, use Tier 1.

**Tier 2 — gcloud CLI via Bash:**
If gcloud is `ready` but MCP tools are not available in session, use Tier 2.
If gcloud is `unauthenticated`, guide through `gcloud auth login` and `gcloud auth application-default login`.

**Tier 3 — Guidance-only:**
If neither MCP tools nor gcloud are available, provide manual Cloud Console instructions (Logs Explorer URL patterns, filter syntax).

**Tier upgrade nudge:** If using Tier 2 (gcloud CLI) and Tier 1 MCP tools are not available, include a one-line note after reporting the tier:

> "Using gcloud CLI (Tier 2). For faster queries with autonomous trace correlation, run `/setup` to configure GCP Observability MCP (Tier 1)."

Do not repeat this nudge after the first mention.
```

- [ ] **Step 4: Add preflight to alert-hygiene Tier Detection**

In `skills/alert-hygiene/SKILL.md`, add before the existing "Tier 1" heading in the "Tier Detection" section (~line 41):

```markdown
Run the shared observability preflight before data access:

```bash
bash "$(dirname "$0")/../scripts/obs-preflight.sh"
```

If `gcloud` is `unauthenticated`, run `gcloud auth login` before proceeding. If `gcloud` is `missing`, fall to Tier 3.
```

- [ ] **Step 5: Add preflight to /investigate command**

In `commands/investigate.md`, add a preflight step before entering Stage 1:

```markdown
**Preflight:** Before entering Stage 1, run the observability preflight:
```bash
bash "$(dirname "$0")/../scripts/obs-preflight.sh"
```
Report any issues from the `summary` field. If `gcloud` is `unauthenticated`, resolve auth before proceeding.
```

- [ ] **Step 6: Run the content tests to verify they pass**

```bash
bash tests/test-skill-content.sh
```

Expected: All assertions PASS.

- [ ] **Step 7: Commit**

```bash
git add skills/incident-analysis/SKILL.md skills/alert-hygiene/SKILL.md commands/investigate.md tests/test-skill-content.sh
git commit -m "feat: wire obs-preflight into incident-analysis, alert-hygiene, and investigate"
```

---

### Task 4: REVIEW-Before-SHIP Guard

**Files:**
- Modify: `hooks/openspec-guard.sh` (add Check 4 after line 103)
- Test: `tests/test-openspec-state.sh` (add guard tests)

- [ ] **Step 1: Write the failing tests**

Add to `tests/test-openspec-state.sh`:

```bash
# ---------------------------------------------------------------------------
# REVIEW-before-SHIP guard tests
# ---------------------------------------------------------------------------

GUARD_HOOK="${PROJECT_ROOT}/hooks/openspec-guard.sh"

# Helper: run the guard hook with a git commit command and given state files
run_guard() {
    local session_token="$1"
    local phase="$2"
    local comp_state="$3"  # JSON string for composition state, or empty

    # Create session token
    printf '%s' "${session_token}" > "${HOME}/.claude/.skill-session-token"

    # Create signal file with phase
    jq -n --arg p "${phase}" '{skill:"test",phase:$p}' \
        > "${HOME}/.claude/.skill-last-invoked-${session_token}"

    # Create composition state if provided
    if [ -n "${comp_state}" ]; then
        printf '%s' "${comp_state}" > "${HOME}/.claude/.skill-composition-state-${session_token}"
    fi

    # Feed a git commit command to the hook
    printf '{"tool_input":{"command":"git commit -m test"}}' | \
        bash "${GUARD_HOOK}" 2>/dev/null
}

test_review_completed_no_warning() {
    echo "-- test: REVIEW completed — no review warning --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    # Fake a git repo so openspec check doesn't error
    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    local comp='{"chain":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion","openspec-ship","finishing-a-development-branch"],"current_index":6,"completed":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion","openspec-ship"],"updated_at":"2026-03-30T10:00:00Z"}'

    local output
    output="$(run_guard "test-review-ok-$$" "SHIP" "${comp}")"

    assert_not_contains "no REVIEW warning" "REVIEW GUARD" "${output}"

    teardown_test_env
}
test_review_completed_no_warning

test_review_skipped_emits_warning() {
    echo "-- test: REVIEW skipped — emits warning --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    # completed list is missing requesting-code-review
    local comp='{"chain":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion"],"current_index":4,"completed":["brainstorming","writing-plans","executing-plans"],"updated_at":"2026-03-30T10:00:00Z"}'

    local output
    output="$(run_guard "test-review-skip-$$" "SHIP" "${comp}")"

    assert_contains "REVIEW warning present" "REVIEW GUARD" "${output}"

    teardown_test_env
}
test_review_skipped_emits_warning

test_no_composition_state_no_warning() {
    echo "-- test: no composition state — no review warning --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    local output
    output="$(run_guard "test-no-comp-$$" "SHIP" "")"

    assert_not_contains "no REVIEW warning without comp state" "REVIEW GUARD" "${output}"

    teardown_test_env
}
test_no_composition_state_no_warning

test_non_ship_phase_skips_guard() {
    echo "-- test: non-SHIP phase — guard exits early --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    local comp='{"chain":["brainstorming","writing-plans"],"current_index":1,"completed":["brainstorming"],"updated_at":"2026-03-30T10:00:00Z"}'

    local output
    output="$(run_guard "test-non-ship-$$" "IMPLEMENT" "${comp}")"

    assert_not_contains "no warning on non-SHIP phase" "REVIEW GUARD" "${output}"

    teardown_test_env
}
test_non_ship_phase_skips_guard
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bash tests/test-openspec-state.sh
```

Expected: The 4 new REVIEW guard tests FAIL (guard check doesn't exist yet). Existing tests still PASS.

- [ ] **Step 3: Add Check 4 to openspec-guard.sh**

Insert after line 103 (after Check 3's warning block, before the "Emit combined warnings" section):

```bash
# --- Check 4: Has REVIEW (requesting-code-review) been completed? ---
_review_ok=true
_COMP_STATE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
if [ -f "${_COMP_STATE}" ] && command -v jq >/dev/null 2>&1; then
    # Only warn if requesting-code-review is in the chain but not in completed
    _in_chain=false
    _in_completed=false
    jq -e '.chain | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _in_chain=true
    jq -e '.completed | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _in_completed=true
    if [ "${_in_chain}" = "true" ] && [ "${_in_completed}" = "false" ]; then
        _review_ok=false
    fi
fi
if [ "${_review_ok}" = "false" ]; then
    [ -n "${_WARNINGS}" ] && _WARNINGS="${_WARNINGS}
"
    _WARNINGS="${_WARNINGS}REVIEW GUARD: requesting-code-review is in the composition chain but was not completed. Invoke Skill(superpowers:requesting-code-review) before shipping, or proceed if review is not needed for this change."
fi
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bash tests/test-openspec-state.sh
```

Expected: All tests PASS (existing + 4 new).

- [ ] **Step 5: Run the full test suite**

```bash
bash tests/run-tests.sh
```

Expected: All tests PASS. No regressions.

- [ ] **Step 6: Commit**

```bash
git add hooks/openspec-guard.sh tests/test-openspec-state.sh
git commit -m "feat: add REVIEW-before-SHIP guard to openspec-guard using composition state"
```

---

### Task 5: Integration Verification

- [ ] **Step 1: Run full test suite**

```bash
bash tests/run-tests.sh
```

Expected: All tests PASS.

- [ ] **Step 2: Syntax-check modified hooks**

```bash
bash -n hooks/openspec-guard.sh
bash -n scripts/obs-preflight.sh
```

Expected: No errors.

- [ ] **Step 3: Verify CLAUDE.md additions are present**

```bash
grep -c "proceed" CLAUDE.md
grep -c "full content" CLAUDE.md
```

Expected: At least 1 match each.
