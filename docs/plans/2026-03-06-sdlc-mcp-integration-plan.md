# SDLC MCP Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make auto-claude-skills routing engine MCP-aware for SDLC servers (Atlassian, GCP Observability, GKE, Cloud Run, Firebase, Playwright) so hints and phase compositions fire when users have these MCPs configured.

**Architecture:** Add `mcp_servers[]` top-level key to `default-triggers.json` (separate from `plugins[]`). Add prompt-time MCP detection in `skill-activation-hook.sh` that reads `.mcp.json` and `~/.claude.json`. Add phase-scoped hints and `mcp_server` gate support to hint/composition evaluation.

**Tech Stack:** Bash 3.2 (macOS compatible), jq, JSON config files

**Design doc:** `docs/plans/2026-03-06-sdlc-mcp-integration-design.md`

---

### Task 1: Add `mcp_servers[]` to `default-triggers.json`

**Files:**
- Modify: `config/default-triggers.json:365` (after `plugins[]`, before `phase_compositions`)

**Step 1: Write the test**

Add test to `tests/test-registry.sh` after `test_default_triggers_has_plugins_section` (line 305):

```bash
test_default_triggers_has_mcp_servers_section() {
    echo "-- test: default-triggers has mcp_servers section --"
    setup_test_env

    local mcp_count
    mcp_count="$(jq '.mcp_servers | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"

    # Should have 6 MCP servers (atlassian, gcp-observability, gke, cloud-run, firebase, playwright)
    assert_equals "default-triggers has 6 mcp_servers" "6" "${mcp_count}"

    # Each MCP server should have required fields
    local valid_count
    valid_count="$(jq '[.mcp_servers[] | select(.name and .phase_fit and .description and .mcp_tools)] | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "all mcp_servers have required fields" "6" "${valid_count}"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "mcp_servers section"`
Expected: FAIL — `mcp_servers` key doesn't exist yet

**Step 3: Add `mcp_servers[]` to `default-triggers.json`**

Insert after the closing `]` of `plugins[]` (line 476) and before `"phase_compositions"`:

```json
  "mcp_servers": [
    {
      "name": "atlassian",
      "source": "mcp",
      "mcp_tools": ["searchJiraIssuesUsingJql", "getJiraIssue", "getConfluencePage", "searchConfluenceUsingCql", "getJiraIssueTypeMetaWithFields"],
      "phase_fit": ["DESIGN", "PLAN", "REVIEW"],
      "description": "Jira and Confluence context for requirements, acceptance criteria, and design references",
      "detect_commands": ["mcp-atlassian", "uvx mcp-atlassian"],
      "detect_names": ["atlassian", "jira", "confluence"]
    },
    {
      "name": "gcp-observability",
      "source": "mcp",
      "mcp_tools": ["list_log_entries", "list_time_series", "get_trace", "list_error_groups", "get_error_group_stats"],
      "phase_fit": ["SHIP", "DEBUG"],
      "description": "GCP runtime verification: logs, metrics, traces, and error groups",
      "detect_commands": ["gcloud-mcp"],
      "detect_args": ["observability"],
      "detect_names": ["gcp-observability", "gcloud-observability", "observability-mcp"]
    },
    {
      "name": "gke",
      "source": "mcp",
      "mcp_tools": ["list_clusters", "get_cluster", "query_logs", "get_kubeconfig"],
      "phase_fit": ["SHIP", "DEBUG"],
      "description": "GKE cluster context and log querying for Kubernetes deployments",
      "detect_commands": ["gke-mcp"],
      "detect_names": ["gke"]
    },
    {
      "name": "cloud-run",
      "source": "mcp",
      "mcp_tools": ["list_services", "get_service", "get_service_log", "get_service_revisions"],
      "phase_fit": ["SHIP", "DEBUG"],
      "description": "Cloud Run service state and logs for serverless deployments",
      "detect_commands": ["cloud-run-mcp"],
      "detect_names": ["cloud-run", "cloudrun"]
    },
    {
      "name": "firebase",
      "source": "mcp",
      "mcp_tools": ["list_projects", "get_firestore_documents", "get_auth_users", "get_rules"],
      "phase_fit": ["IMPLEMENT", "SHIP", "DEBUG"],
      "description": "Firebase read-only resource inspection: Firestore, Auth, and security rules",
      "detect_commands": ["firebase-tools"],
      "detect_args": ["mcp"],
      "detect_names": ["firebase"]
    },
    {
      "name": "playwright",
      "source": "mcp",
      "mcp_tools": ["browser_navigate", "browser_screenshot", "browser_click", "browser_type", "browser_console_logs"],
      "phase_fit": ["IMPLEMENT", "REVIEW", "DEBUG", "SHIP"],
      "description": "Visual verification and interactive browser testing via Playwright",
      "detect_commands": ["playwright", "@playwright/mcp"],
      "detect_names": ["playwright"]
    }
  ],
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "mcp_servers section"`
Expected: PASS

**Step 5: Commit**

```bash
git add config/default-triggers.json tests/test-registry.sh
git commit -m "feat: add mcp_servers[] to default-triggers.json for SDLC MCPs"
```

---

### Task 2: Add `mcp_servers[]` to `fallback-registry.json`

**Files:**
- Modify: `config/fallback-registry.json:306` (after `"plugins": []`)

**Step 1: Add empty `mcp_servers` key**

After `"plugins": [],` (line 306) add:

```json
  "mcp_servers": [],
```

**Step 2: Verify fallback registry is still valid JSON**

Run: `jq empty config/fallback-registry.json && echo "valid" || echo "invalid"`
Expected: `valid`

**Step 3: Commit**

```bash
git add config/fallback-registry.json
git commit -m "feat: add empty mcp_servers[] to fallback registry"
```

---

### Task 3: Update GitHub plugin `phase_fit`

**Files:**
- Modify: `config/default-triggers.json:473`

**Step 1: Write the test**

Add to `tests/test-registry.sh`:

```bash
test_github_plugin_has_design_plan_phases() {
    echo "-- test: github plugin includes DESIGN and PLAN phases --"
    setup_test_env

    local phases
    phases="$(jq -r '.plugins[] | select(.name == "github") | .phase_fit | join(",")' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_contains "github has DESIGN" "DESIGN" "${phases}"
    assert_contains "github has PLAN" "PLAN" "${phases}"
    assert_contains "github has REVIEW" "REVIEW" "${phases}"
    assert_contains "github has SHIP" "SHIP" "${phases}"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "github plugin"`
Expected: FAIL — current phase_fit is `["REVIEW", "SHIP"]`

**Step 3: Update GitHub plugin phase_fit**

Change line 473 from:
```json
      "phase_fit": ["REVIEW", "SHIP"],
```
to:
```json
      "phase_fit": ["DESIGN", "PLAN", "REVIEW", "SHIP"],
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "github plugin"`
Expected: PASS

**Step 5: Commit**

```bash
git add config/default-triggers.json tests/test-registry.sh
git commit -m "feat: expand GitHub plugin phase_fit to include DESIGN and PLAN"
```

---

### Task 4: Add phase-scoped hint support to `skill-activation-hook.sh`

**Files:**
- Modify: `hooks/skill-activation-hook.sh:887-896` (HINTS_DATA jq call)
- Modify: `hooks/skill-activation-hook.sh:898-927` (hint evaluation loop)

**Step 1: Write the test**

Add to `tests/test-routing.sh`:

```bash
test_phase_scoped_hints() {
    echo "-- test: phase-scoped hints respect phases filter --"
    setup_test_env

    # Install registry with a phase-scoped hint
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"

    # Start from v4 registry and add a phase-scoped hint
    install_registry_v4
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.methodology_hints += [{
        "name": "test-design-only-hint",
        "triggers": ["(build|create|design)"],
        "trigger_mode": "regex",
        "hint": "TEST-DESIGN-HINT: This should only appear during DESIGN phase.",
        "phases": ["DESIGN"]
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # "build" triggers brainstorming (DESIGN phase) — hint should appear
    local output context
    output="$(run_hook "build a new service")"
    context="$(extract_context "$output")"
    assert_contains "phase-scoped hint appears in matching phase" "TEST-DESIGN-HINT" "$context"

    # "debug this crash" triggers systematic-debugging (DEBUG phase) — hint should NOT appear
    # even though "crash" doesn't match the hint trigger, we need a prompt that DOES match the trigger but is DEBUG phase
    # Use a hint that triggers on "error" (matches DEBUG prompts) but is scoped to DESIGN
    jq '.methodology_hints += [{
        "name": "test-design-error-hint",
        "triggers": ["(error|bug)"],
        "trigger_mode": "regex",
        "hint": "TEST-DESIGN-ERROR-HINT: Should not appear during DEBUG.",
        "phases": ["DESIGN"]
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    output="$(run_hook "debug this error in the auth module")"
    context="$(extract_context "$output")"
    assert_not_contains "phase-scoped hint suppressed in non-matching phase" "TEST-DESIGN-ERROR-HINT" "$context"

    teardown_test_env
}

test_hints_without_phases_fire_unconditionally() {
    echo "-- test: hints without phases field fire unconditionally --"
    setup_test_env
    install_registry_v4

    # Ralph-loop hint has no phases field — should fire regardless of phase
    local output context
    output="$(run_hook "migrate all the legacy modules to the new framework and iterate until done")"
    context="$(extract_context "$output")"
    assert_contains "hint without phases fires" "RALPH LOOP" "$context"

    teardown_test_env
}
```

**Step 2: Run tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "phase-scoped"`
Expected: FAIL — phase filtering not implemented yet

**Step 3: Modify the HINTS_DATA jq extraction**

In `hooks/skill-activation-hook.sh` line 887, update the jq call to also extract the `phases` array:

Replace lines 887-896 with:

```bash
HINTS_DATA="$(printf '%s' "$REGISTRY" | jq -r '
  (.plugins // []) as $plugins |
  (.mcp_servers // []) as $mcps |
  .methodology_hints // [] | .[] |
  # Gate plugin-scoped hints on plugin availability
  (if .plugin then
    (.plugin as $p | [$plugins[] | select(.name == $p and .available == true)] | length > 0)
  elif .mcp_server then
    (.mcp_server as $m | [$mcps[] | select(.name == $m and .available == true)] | length > 0)
  else true end) as $available |
  select($available) |
  ((.skill // "") + "\u001f" + .hint + "\u001f" + ((.triggers // []) | join("\u0001")) + "\u001f" + ((.phases // []) | join("\u0001")))
' 2>/dev/null)"
```

**Step 4: Modify the hint evaluation loop to check phases**

Replace the hint loop (lines 898-927) with:

```bash
while IFS="$FS" read -r hint_skill hint_text hint_triggers_joined hint_phases_joined; do
  [[ -z "$hint_text" ]] && continue

  # Suppress hint if its associated skill is already selected
  if [[ -n "$hint_skill" ]] && printf '%s' "$SELECTED" | grep -q "|${hint_skill}|"; then
    continue
  fi

  # Phase-scope check: if hint has phases, PRIMARY_PHASE must match one
  if [[ -n "$hint_phases_joined" ]] && [[ -n "$PRIMARY_PHASE" ]]; then
    _phase_match=0
    _hp_remaining="$hint_phases_joined"
    while [[ -n "$_hp_remaining" ]]; do
      if [[ "$_hp_remaining" == *"${DELIM}"* ]]; then
        _hp="${_hp_remaining%%${DELIM}*}"
        _hp_remaining="${_hp_remaining#*${DELIM}}"
      else
        _hp="$_hp_remaining"
        _hp_remaining=""
      fi
      [[ -z "$_hp" ]] && continue
      if [[ "$_hp" == "$PRIMARY_PHASE" ]]; then
        _phase_match=1
        break
      fi
    done
    [[ "$_phase_match" -eq 0 ]] && continue
  fi

  # Test hint triggers against prompt
  if [[ -n "$hint_triggers_joined" ]]; then
    _remaining="$hint_triggers_joined"
    while [[ -n "$_remaining" ]]; do
      if [[ "$_remaining" == *"${DELIM}"* ]]; then
        htrigger="${_remaining%%${DELIM}*}"
        _remaining="${_remaining#*${DELIM}}"
      else
        htrigger="$_remaining"
        _remaining=""
      fi
      [[ -z "$htrigger" ]] && continue
      if [[ "$P" =~ $htrigger ]]; then
        HINTS="${HINTS}
- ${hint_text}"
        break
      fi
    done
  fi
done <<EOF
${HINTS_DATA}
EOF
```

**Step 5: Run tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "phase-scoped\|without phases"`
Expected: PASS for both

**Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: add phase-scoped hint evaluation and mcp_server gate"
```

---

### Task 5: Add `mcp_server` gate to phase composition evaluation

**Files:**
- Modify: `hooks/skill-activation-hook.sh:938-958` (composition jq call)

**Step 1: Write the test**

Add to `tests/test-routing.sh`:

```bash
test_mcp_server_gated_composition() {
    echo "-- test: mcp_server-gated compositions render when available --"
    setup_test_env

    # Build a registry with an MCP-gated DESIGN composition
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    install_registry_v4
    local tmp_file
    tmp_file="$(mktemp)"

    # Add mcp_servers array and a composition entry gated on it
    jq '
      .mcp_servers = [{"name": "test-mcp", "available": true, "phase_fit": ["DESIGN"], "mcp_tools": ["tool1"], "description": "test"}] |
      .phase_compositions.DESIGN.parallel += [{"mcp_server": "test-mcp", "use": "mcp:tool1", "when": "installed", "purpose": "Test MCP composition"}]
    ' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    local output context
    output="$(run_hook "design a new service architecture")"
    context="$(extract_context "$output")"
    assert_contains "MCP composition renders" "Test MCP composition" "$context"

    # Now set available to false — composition should NOT render
    jq '.mcp_servers[0].available = false' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    output="$(run_hook "design a new service architecture")"
    context="$(extract_context "$output")"
    assert_not_contains "MCP composition hidden when unavailable" "Test MCP composition" "$context"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "mcp_server-gated"`
Expected: FAIL — composition jq doesn't know about `mcp_server` gate

**Step 3: Update the composition jq call**

Replace lines 940-958 in `hooks/skill-activation-hook.sh` with:

```bash
  _comp_output="$(printf '%s' "$REGISTRY" | jq -r --arg ph "$CURRENT_PHASE" '
    [.plugins // [] | .[] | select(.available == true) | .name] as $avail_plugins |
    [.mcp_servers // [] | .[] | select(.available == true) | .name] as $avail_mcps |
    .phase_compositions[$ph] // empty |
    (
      (.parallel // [] | .[] |
        if .mcp_server then
          select(.mcp_server as $m | $avail_mcps | any(. == $m))
        else
          select(.plugin as $p | $avail_plugins | any(. == $p))
        end |
        "LINE:  PARALLEL: \(.use) -> \(.purpose) [\(.mcp_server // .plugin)]"),
      (.sequence // [] | .[] |
        if .mcp_server then
          select(.mcp_server as $m | $avail_mcps | any(. == $m)) |
          "LINE:  SEQUENCE: \(.use // .step) -> \(.purpose) [\(.mcp_server)]"
        elif .plugin then
          select(.plugin as $p | $avail_plugins | any(. == $p)) |
          "LINE:  SEQUENCE: \(.use // .step) -> \(.purpose) [\(.plugin)]"
        else
          "LINE:  SEQUENCE: \(.step) -> \(.purpose)"
        end),
      (.hints // [] | .[] |
        if .mcp_server then
          select(.mcp_server as $m | $avail_mcps | any(. == $m))
        else
          select(.plugin as $p | $avail_plugins | any(. == $p))
        end |
        "HINT:\(.text)")
    )
  ' 2>/dev/null)"
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "mcp_server-gated"`
Expected: PASS

**Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: add mcp_server gate to phase composition evaluation"
```

---

### Task 6: Add prompt-time MCP detection to `skill-activation-hook.sh`

**Files:**
- Modify: `hooks/skill-activation-hook.sh` (insert after LOAD REGISTRY section, ~line 72, before LOAD USER SETTINGS)

**Step 1: Write the test**

Add to `tests/test-routing.sh`:

```bash
test_mcp_detection_from_mcp_json() {
    echo "-- test: MCP detection reads .mcp.json and sets availability --"
    setup_test_env
    install_registry_v4

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"

    # Add mcp_servers to registry (unavailable by default)
    jq '.mcp_servers = [
        {"name": "atlassian", "available": false, "phase_fit": ["DESIGN","PLAN"], "mcp_tools": ["getJiraIssue"], "description": "Jira", "detect_commands": ["mcp-atlassian", "uvx mcp-atlassian"], "detect_names": ["atlassian", "jira"]},
        {"name": "playwright", "available": false, "phase_fit": ["IMPLEMENT"], "mcp_tools": ["browser_navigate"], "description": "Playwright", "detect_commands": ["playwright", "@playwright/mcp"], "detect_names": ["playwright"]}
    ]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # Add MCP-gated hint for atlassian
    jq '.methodology_hints += [{"name": "test-jira", "triggers": ["(jira|ticket)"], "trigger_mode": "regex", "hint": "TEST-JIRA-HINT: Use Jira MCP.", "mcp_server": "atlassian"}]' \
        "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # Create .mcp.json in the working directory
    printf '{"mcpServers": {"my-jira-server": {"command": "uvx", "args": ["mcp-atlassian"]}}}\n' > "${PWD}/.mcp.json"

    # The hint should now fire because MCP detection should find atlassian via command matching
    local output context
    output="$(run_hook "check the jira ticket for acceptance criteria")"
    context="$(extract_context "$output")"
    assert_contains "MCP detection enables atlassian hint" "TEST-JIRA-HINT" "$context"

    # Clean up
    rm -f "${PWD}/.mcp.json"

    teardown_test_env
}

test_mcp_detection_user_override() {
    echo "-- test: MCP detection respects user mcp_mappings override --"
    setup_test_env
    install_registry_v4

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"

    # Add mcp_servers to registry
    jq '.mcp_servers = [
        {"name": "atlassian", "available": false, "phase_fit": ["DESIGN"], "mcp_tools": ["getJiraIssue"], "description": "Jira", "detect_commands": ["mcp-atlassian"], "detect_names": ["atlassian", "jira"]}
    ]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    jq '.methodology_hints += [{"name": "test-jira2", "triggers": ["(jira|ticket)"], "trigger_mode": "regex", "hint": "TEST-JIRA2-HINT: User override works.", "mcp_server": "atlassian"}]' \
        "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # Create .mcp.json with a non-standard name
    printf '{"mcpServers": {"company-issue-tracker": {"command": "node", "args": ["custom-server.js"]}}}\n' > "${PWD}/.mcp.json"

    # Create user config with mcp_mappings override
    printf '{"mcp_mappings": {"company-issue-tracker": "atlassian"}}\n' > "${HOME}/.claude/skill-config.json"

    local output context
    output="$(run_hook "check the jira ticket for acceptance criteria")"
    context="$(extract_context "$output")"
    assert_contains "user override enables atlassian" "TEST-JIRA2-HINT" "$context"

    # Clean up
    rm -f "${PWD}/.mcp.json"

    teardown_test_env
}

test_no_mcp_no_noise() {
    echo "-- test: no MCP config produces no MCP noise --"
    setup_test_env
    install_registry_v4

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"

    # Add mcp_servers to registry (unavailable)
    jq '.mcp_servers = [
        {"name": "atlassian", "available": false, "phase_fit": ["DESIGN"], "mcp_tools": ["getJiraIssue"], "description": "Jira", "detect_commands": ["mcp-atlassian"], "detect_names": ["atlassian"]}
    ]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    jq '.methodology_hints += [{"name": "test-jira3", "triggers": ["(jira|ticket)"], "trigger_mode": "regex", "hint": "TEST-JIRA3-HINT: Should not appear.", "mcp_server": "atlassian"}]' \
        "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # No .mcp.json, no MCP config — hint should NOT fire
    rm -f "${PWD}/.mcp.json"

    local output context
    output="$(run_hook "check the jira ticket")"
    context="$(extract_context "$output")"
    assert_not_contains "no MCP means no MCP hints" "TEST-JIRA3-HINT" "$context"

    teardown_test_env
}
```

**Step 2: Run tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "MCP detection"`
Expected: FAIL — MCP detection not implemented

**Step 3: Add MCP detection function**

Insert after the LOAD REGISTRY section (~line 72, after `REGISTRY="$(cat...)"`) and before LOAD USER SETTINGS:

```bash
# =================================================================
# MCP SERVER DETECTION (prompt-time)
# =================================================================
# Detect configured MCP servers from .mcp.json and ~/.claude.json,
# then override mcp_servers[].available in REGISTRY (in memory only).
# Three-tier identification: user override > command match > name match.

_detect_mcp_servers() {
  # Skip if no mcp_servers in registry
  local _has_mcps
  _has_mcps="$(printf '%s' "$REGISTRY" | jq -r '.mcp_servers // [] | length' 2>/dev/null)"
  [[ "$_has_mcps" == "0" ]] && return

  # --- Collect all configured MCP server entries ---
  # Format: name<TAB>command_string (one per line)
  local _mcp_entries=""

  # 1. Project scope: walk up from PWD to find .mcp.json
  local _proj_mcp=""
  local _walk="$PWD"
  while [[ "$_walk" != "/" ]]; do
    if [[ -f "${_walk}/.mcp.json" ]]; then
      _proj_mcp="${_walk}/.mcp.json"
      break
    fi
    _walk="$(dirname "$_walk")"
  done

  if [[ -n "$_proj_mcp" ]] && jq empty "$_proj_mcp" >/dev/null 2>&1; then
    _mcp_entries="$(jq -r '.mcpServers // {} | to_entries[] | "\(.key)\t\((.value.command // "") + " " + ((.value.args // []) | join(" ")))"' "$_proj_mcp" 2>/dev/null)"
  fi

  # 2. User scope: ~/.claude.json top-level mcpServers
  local _user_claude="${HOME}/.claude.json"
  if [[ -f "$_user_claude" ]] && jq empty "$_user_claude" >/dev/null 2>&1; then
    local _user_entries
    _user_entries="$(jq -r '.mcpServers // {} | to_entries[] | "\(.key)\t\((.value.command // "") + " " + ((.value.args // []) | join(" ")))"' "$_user_claude" 2>/dev/null)"
    if [[ -n "$_user_entries" ]]; then
      _mcp_entries="${_mcp_entries}${_mcp_entries:+
}${_user_entries}"
    fi
  fi

  # 3. Local scope: ~/.claude.json projects[<project-path>].mcpServers
  if [[ -f "$_user_claude" ]] && [[ -n "$_proj_mcp" || -n "$_walk" ]]; then
    # Use the project root we found (or PWD if no .mcp.json)
    local _proj_root="${_walk}"
    [[ -z "$_proj_root" ]] && _proj_root="$PWD"
    local _local_entries
    _local_entries="$(jq -r --arg p "$_proj_root" '(.projects[$p].mcpServers // {}) | to_entries[] | "\(.key)\t\((.value.command // "") + " " + ((.value.args // []) | join(" ")))"' "$_user_claude" 2>/dev/null)"
    if [[ -n "$_local_entries" ]]; then
      # Local scope takes precedence — prepend
      _mcp_entries="${_local_entries}${_mcp_entries:+
}${_mcp_entries}"
    fi
  fi

  [[ -z "$_mcp_entries" ]] && return

  # --- Load user override map ---
  local _user_mappings="{}"
  if [[ -f "$USER_CONFIG" ]] && jq empty "$USER_CONFIG" >/dev/null 2>&1; then
    _user_mappings="$(jq '.mcp_mappings // {}' "$USER_CONFIG" 2>/dev/null)"
  fi

  # --- Load detection rules from registry ---
  local _detect_rules
  _detect_rules="$(printf '%s' "$REGISTRY" | jq -r '.mcp_servers // [] | .[] | .name + "\u001f" + ((.detect_commands // []) | join("\u0001")) + "\u001f" + ((.detect_names // []) | join("\u0001")) + "\u001f" + ((.detect_args // []) | join("\u0001"))' 2>/dev/null)"

  # --- Match each configured server against detection rules ---
  local _matched_mcps=""

  while IFS=$'\t' read -r _srv_name _srv_cmd; do
    [[ -z "$_srv_name" ]] && continue
    local _srv_name_lower
    _srv_name_lower="$(printf '%s' "$_srv_name" | tr '[:upper:]' '[:lower:]')"
    _srv_cmd="$(printf '%s' "$_srv_cmd" | tr '[:upper:]' '[:lower:]')"

    local _mapped=""

    # Tier 1: User override map
    _mapped="$(printf '%s' "$_user_mappings" | jq -r --arg k "$_srv_name" '.[$k] // empty' 2>/dev/null)"
    if [[ -n "$_mapped" ]]; then
      _matched_mcps="${_matched_mcps}${_mapped}
"
      continue
    fi

    # Tier 2 + 3: Command/arg and name matching against registry rules
    while IFS="$FS" read -r _rule_name _rule_cmds _rule_names _rule_args; do
      [[ -z "$_rule_name" ]] && continue

      # Tier 2: Command matching
      if [[ -n "$_rule_cmds" ]]; then
        local _rc_remaining="$_rule_cmds"
        while [[ -n "$_rc_remaining" ]]; do
          if [[ "$_rc_remaining" == *"${DELIM}"* ]]; then
            _rc="${_rc_remaining%%${DELIM}*}"
            _rc_remaining="${_rc_remaining#*${DELIM}}"
          else
            _rc="$_rc_remaining"
            _rc_remaining=""
          fi
          [[ -z "$_rc" ]] && continue
          if [[ "$_srv_cmd" == *"$_rc"* ]]; then
            # If rule has detect_args, also check those
            if [[ -n "$_rule_args" ]]; then
              local _ra_remaining="$_rule_args"
              while [[ -n "$_ra_remaining" ]]; do
                if [[ "$_ra_remaining" == *"${DELIM}"* ]]; then
                  _ra="${_ra_remaining%%${DELIM}*}"
                  _ra_remaining="${_ra_remaining#*${DELIM}}"
                else
                  _ra="$_ra_remaining"
                  _ra_remaining=""
                fi
                [[ -z "$_ra" ]] && continue
                if [[ "$_srv_cmd" == *"$_ra"* ]]; then
                  _mapped="$_rule_name"
                  break 2
                fi
              done
            else
              _mapped="$_rule_name"
              break
            fi
          fi
        done
      fi

      # Tier 3: Name pattern matching
      if [[ -z "$_mapped" ]] && [[ -n "$_rule_names" ]]; then
        local _rn_remaining="$_rule_names"
        while [[ -n "$_rn_remaining" ]]; do
          if [[ "$_rn_remaining" == *"${DELIM}"* ]]; then
            _rn="${_rn_remaining%%${DELIM}*}"
            _rn_remaining="${_rn_remaining#*${DELIM}}"
          else
            _rn="$_rn_remaining"
            _rn_remaining=""
          fi
          [[ -z "$_rn" ]] && continue
          if [[ "$_srv_name_lower" == *"$_rn"* ]]; then
            _mapped="$_rule_name"
            break
          fi
        done
      fi

      [[ -n "$_mapped" ]] && break
    done <<RULES
${_detect_rules}
RULES

    if [[ -n "$_mapped" ]]; then
      _matched_mcps="${_matched_mcps}${_mapped}
"
    fi
  done <<ENTRIES
${_mcp_entries}
ENTRIES

  # --- Override availability in REGISTRY (in memory) ---
  if [[ -n "$_matched_mcps" ]]; then
    # Deduplicate
    _matched_mcps="$(printf '%s' "$_matched_mcps" | sort -u | grep -v '^$')"
    # Build jq array from matched names
    local _jq_arr
    _jq_arr="$(printf '%s' "$_matched_mcps" | jq -R -s 'split("\n") | map(select(. != ""))')"
    REGISTRY="$(printf '%s' "$REGISTRY" | jq --argjson matched "$_jq_arr" '
      .mcp_servers = [.mcp_servers // [] | .[] | if (.name as $n | $matched | any(. == $n)) then .available = true else . end]
    ')"
  fi
}

_detect_mcp_servers
```

**Step 4: Run tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "MCP detection\|no MCP"`
Expected: PASS for all three

**Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: add prompt-time MCP server detection with three-tier identification"
```

---

### Task 7: Add methodology hints for SDLC MCPs

**Files:**
- Modify: `config/default-triggers.json:328-363` (methodology_hints array)

**Step 1: Write the test**

Add to `tests/test-routing.sh`:

```bash
test_mcp_methodology_hints_in_config() {
    echo "-- test: SDLC MCP methodology hints exist in config --"
    setup_test_env

    local hint_count
    hint_count="$(jq '[.methodology_hints[] | select(.mcp_server)] | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"

    # Should have 7 mcp_server-gated hints
    assert_equals "7 mcp_server-gated hints in config" "7" "${hint_count}"

    # Atlassian Jira hint exists
    local jira_hint
    jira_hint="$(jq -r '[.methodology_hints[] | select(.name == "atlassian-jira")] | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "atlassian-jira hint exists" "1" "${jira_hint}"

    # GCP observability hint exists
    local gcp_hint
    gcp_hint="$(jq -r '[.methodology_hints[] | select(.name == "gcp-observability")] | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "gcp-observability hint exists" "1" "${gcp_hint}"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — no mcp_server-gated hints yet

**Step 3: Add 7 new hints and update the GitHub hint**

Add to `methodology_hints[]` in `config/default-triggers.json` after the existing github-mcp hint (line 363):

```json
    {
      "name": "atlassian-jira",
      "triggers": [
        "(ticket|story|epic|acceptance.criter|definition.of.done|requirement|user.story|jira|sprint|backlog)"
      ],
      "trigger_mode": "regex",
      "hint": "ATLASSIAN MCP: Use Jira MCP tools (searchJiraIssuesUsingJql, getJiraIssue) to pull acceptance criteria and linked context before planning. Prefer targeted issue lookups over broad searches.",
      "mcp_server": "atlassian",
      "phases": ["DESIGN", "PLAN"]
    },
    {
      "name": "atlassian-confluence",
      "triggers": [
        "(confluence|wiki|knowledge.base|design.doc|architecture.doc|adr|decision.record)"
      ],
      "trigger_mode": "regex",
      "hint": "ATLASSIAN MCP: Use Confluence MCP tools (getConfluencePage, searchConfluenceUsingCql) for design references. Keep searches narrow -- broad page search adds noise.",
      "mcp_server": "atlassian",
      "phases": ["DESIGN", "PLAN"]
    },
    {
      "name": "gcp-observability",
      "triggers": [
        "(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search)"
      ],
      "trigger_mode": "regex",
      "hint": "GCP OBSERVABILITY: Use observability MCP tools (list_log_entries, list_time_series, list_error_groups) to verify runtime state. Scope queries to service + environment + bounded time window (30-60 min).",
      "mcp_server": "gcp-observability",
      "phases": ["SHIP", "DEBUG"]
    },
    {
      "name": "gke",
      "triggers": [
        "(cluster|kubernetes|k8s|pod|node|namespace|workload|gke)"
      ],
      "trigger_mode": "regex",
      "hint": "GKE MCP: Use GKE MCP tools (query_logs, list_clusters) for cluster context and log queries. Prefer LQL log queries over broad log dumps.",
      "mcp_server": "gke",
      "phases": ["SHIP", "DEBUG"]
    },
    {
      "name": "cloud-run",
      "triggers": [
        "(cloud.?run|serverless.deploy|revision|service.log|cloud.?run.service)"
      ],
      "trigger_mode": "regex",
      "hint": "CLOUD RUN MCP: Use Cloud Run MCP tools (get_service, get_service_log) to check service state and logs after deployment.",
      "mcp_server": "cloud-run",
      "phases": ["SHIP", "DEBUG"]
    },
    {
      "name": "firebase",
      "triggers": [
        "(firebase|firestore|auth.user|security.rules|realtime.db|cloud.function|hosting)"
      ],
      "trigger_mode": "regex",
      "hint": "FIREBASE MCP: Use Firebase MCP tools for read-only resource inspection (documents, auth, rules). Use CLI for deployment and mutations.",
      "mcp_server": "firebase",
      "phases": ["IMPLEMENT", "SHIP", "DEBUG"]
    },
    {
      "name": "playwright-mcp",
      "triggers": [
        "(screenshot|visual.test|browser.test|layout.regress|lighthouse|a11y|smoke.test|e2e|playwright)"
      ],
      "trigger_mode": "regex",
      "hint": "PLAYWRIGHT MCP: Use Playwright MCP tools (browser_navigate, browser_screenshot) for visual verification and interactive debugging. Captures what CLI test runners can't show.",
      "mcp_server": "playwright",
      "phases": ["IMPLEMENT", "REVIEW", "DEBUG", "SHIP"]
    }
```

Also update the existing `github-mcp` hint (line 356-363) — expand triggers and add phases:

```json
    {
      "name": "github-mcp",
      "triggers": [
        "(pull.?request|issue|github|merge|branch|repo|related.pr|similar.change|previous.attempt|what.was.tried|prior.art|code.history)"
      ],
      "trigger_mode": "regex",
      "hint": "GITHUB MCP: Use GitHub MCP tools for PR/issue context, workflow run status, and code history. During brainstorming/planning, search for related PRs and issues to ground decisions in engineering history.",
      "plugin": "github",
      "phases": ["DESIGN", "PLAN", "REVIEW", "SHIP"]
    }
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "MCP methodology"`
Expected: PASS

**Step 5: Commit**

```bash
git add config/default-triggers.json tests/test-registry.sh
git commit -m "feat: add 7 SDLC MCP methodology hints with phase scoping"
```

---

### Task 8: Add phase composition entries

**Files:**
- Modify: `config/default-triggers.json:477-610` (phase_compositions)

**Step 1: Write the test**

Add to `tests/test-registry.sh`:

```bash
test_phase_compositions_include_mcp_entries() {
    echo "-- test: phase compositions include MCP entries --"
    setup_test_env

    # DESIGN should have atlassian and github parallel entries
    local design_parallel
    design_parallel="$(jq '.phase_compositions.DESIGN.parallel | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    # Original 2 (feature-dev, context7) + 2 new (atlassian, github)
    assert_equals "DESIGN has 4 parallel entries" "4" "${design_parallel}"

    # PLAN should have 2 parallel entries
    local plan_parallel
    plan_parallel="$(jq '.phase_compositions.PLAN.parallel | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "PLAN has 2 parallel entries" "2" "${plan_parallel}"

    # SHIP should have 6 sequence entries (3 new gcp-observability + 3 existing)
    local ship_sequence
    ship_sequence="$(jq '.phase_compositions.SHIP.sequence | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "SHIP has 6 sequence entries" "6" "${ship_sequence}"

    # SHIP gcp-observability entries should be first (before commit-commands)
    local first_ship_entry
    first_ship_entry="$(jq -r '.phase_compositions.SHIP.sequence[0].mcp_server // .phase_compositions.SHIP.sequence[0].plugin // empty' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "first SHIP sequence is gcp-observability" "gcp-observability" "${first_ship_entry}"

    # REVIEW should have atlassian parallel entry
    local review_parallel
    review_parallel="$(jq '.phase_compositions.REVIEW.parallel | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    # Original 3 + 1 new (atlassian)
    assert_equals "REVIEW has 4 parallel entries" "4" "${review_parallel}"

    # DEBUG should have gcp-observability parallel entry
    local debug_parallel
    debug_parallel="$(jq '.phase_compositions.DEBUG.parallel | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    # Original 1 (context7) + 1 new (gcp-observability)
    assert_equals "DEBUG has 2 parallel entries" "2" "${debug_parallel}"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — no MCP composition entries yet

**Step 3: Add composition entries**

Modify `phase_compositions` in `config/default-triggers.json`:

**DESIGN** — add to `parallel[]` after existing entries:
```json
        {
          "mcp_server": "atlassian",
          "use": "mcp:searchJiraIssuesUsingJql + getJiraIssue",
          "when": "installed",
          "purpose": "Pull acceptance criteria and constraints while brainstorming clarifies intent"
        },
        {
          "plugin": "github",
          "use": "mcp:list_issues + search_repositories",
          "when": "installed",
          "purpose": "Inspect known related issues and search repo for prior approaches"
        }
```

Add to DESIGN `hints[]`:
```json
        {
          "mcp_server": "atlassian",
          "text": "Use Jira MCP to ground brainstorming in real requirements, not assumed ones",
          "when": "installed"
        }
```

**PLAN** — add to `parallel[]`:
```json
        {
          "mcp_server": "atlassian",
          "use": "mcp:getJiraIssue",
          "when": "installed",
          "purpose": "Re-read Jira AC to validate plan steps map to acceptance criteria"
        },
        {
          "plugin": "github",
          "use": "mcp:get_pull_request",
          "when": "installed",
          "purpose": "Inspect known related PRs for implementation patterns and pitfalls"
        }
```

Add to PLAN `hints[]`:
```json
        {
          "mcp_server": "atlassian",
          "text": "Verify each plan step traces to a Jira acceptance criterion",
          "when": "installed"
        }
```

**REVIEW** — add to `parallel[]`:
```json
        {
          "mcp_server": "atlassian",
          "use": "mcp:getJiraIssue",
          "when": "installed",
          "purpose": "Cross-check PR changes against Jira AC during review"
        }
```

**SHIP** — prepend 3 entries to `sequence[]` (before existing commit-commands entry):
```json
        {
          "mcp_server": "gcp-observability",
          "use": "mcp:list_log_entries",
          "when": "installed",
          "purpose": "Check logs for deployment window errors"
        },
        {
          "mcp_server": "gcp-observability",
          "use": "mcp:list_error_groups",
          "when": "installed",
          "purpose": "Verify no new error groups"
        },
        {
          "mcp_server": "gcp-observability",
          "use": "mcp:list_time_series",
          "when": "installed",
          "purpose": "Confirm metrics didn't regress"
        },
```

Add to SHIP `hints[]`:
```json
        {
          "mcp_server": "gcp-observability",
          "text": "Include runtime verification evidence in PR: log window, error delta, metric delta",
          "when": "installed"
        }
```

**DEBUG** — add to `parallel[]`:
```json
        {
          "mcp_server": "gcp-observability",
          "use": "mcp:list_log_entries + list_error_groups",
          "when": "installed",
          "purpose": "Runtime signals for the error window to ground debugging hypotheses"
        }
```

Add to DEBUG `hints[]`:
```json
        {
          "mcp_server": "gcp-observability",
          "text": "Scope debug queries to service + environment + narrow time window. Avoid broad log dumps.",
          "when": "installed"
        }
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "MCP entries"`
Expected: PASS

**Step 5: Also update existing test counts**

In `tests/test-registry.sh`, update `test_default_triggers_has_plugins_section` — plugin count stays at 9 (no new plugins added).

Update `test_default_triggers_has_phase_compositions`:
- Line 329: REVIEW parallel from 3 to 4
- Line 334: SHIP sequence from 3 to 6

**Step 6: Commit**

```bash
git add config/default-triggers.json tests/test-registry.sh
git commit -m "feat: add SDLC MCP phase composition entries for DESIGN/PLAN/REVIEW/SHIP/DEBUG"
```

---

### Task 9: Update test fixtures in `test-routing.sh`

**Files:**
- Modify: `tests/test-routing.sh:309-525` (`install_registry_v4` fixture)

**Step 1: Update `install_registry_v4` to include `mcp_servers`**

Add `"mcp_servers": []` after `"plugins": [...]` in the v4 fixture. This ensures tests that use `install_registry_v4` have the key present even if empty.

In the `install_registry_v4` function, after the `plugins` array closing `]` (around line 506), add:

```json
  "mcp_servers": [],
```

**Step 2: Run all existing routing tests**

Run: `bash tests/test-routing.sh 2>&1`
Expected: All existing tests PASS (no regressions)

**Step 3: Run all registry tests**

Run: `bash tests/test-registry.sh 2>&1`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add tests/test-routing.sh
git commit -m "test: add mcp_servers[] to test fixtures for forward compat"
```

---

### Task 10: Run full test suite and verify

**Step 1: Run all tests**

Run: `bash tests/test-registry.sh 2>&1 && bash tests/test-routing.sh 2>&1`
Expected: All tests PASS, no regressions

**Step 2: Run session-start hook to verify registry builds correctly**

Run: `CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh 2>&1`
Expected: JSON output with health message, no errors

**Step 3: Verify registry cache has mcp_servers key**

Run: `jq '.mcp_servers | length' ~/.claude/.skill-registry-cache.json`
Expected: `6`

**Step 4: Verify all mcp_servers default to available: false**

Run: `jq '[.mcp_servers[] | select(.available == true)] | length' ~/.claude/.skill-registry-cache.json`
Expected: `0` (no MCP servers detected without .mcp.json)

**Step 5: Final commit if any fixups needed**

```bash
git add -A
git commit -m "fix: test suite fixups for SDLC MCP integration"
```
