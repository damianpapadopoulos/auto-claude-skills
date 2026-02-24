# Comprehensive Plugin Orchestration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Evolve auto-claude-skills from a skill-only router into a comprehensive ecosystem orchestrator that discovers all installed plugins and composes them with superpowers skills via phase-specific rules.

**Architecture:** Extend `default-triggers.json` with `plugins` and `phase_compositions` sections. Extend `session-start-hook.sh` to auto-discover all installed plugins. Extend `skill-activation-hook.sh` to emit PARALLEL/SEQUENCE/hint lines from composition rules.

**Tech Stack:** Bash 3.2 (macOS compatible), jq, POSIX regex

---

### Task 1: Add plugins section to default-triggers.json

**Files:**
- Modify: `config/default-triggers.json`

**Step 1: Write the failing test**

Add to `tests/test-registry.sh` a test that verifies the default-triggers.json has a `plugins` array:

```bash
test_default_triggers_has_plugins_section() {
    echo "-- test: default-triggers has plugins section --"
    setup_test_env

    local plugin_count
    plugin_count="$(jq '.plugins | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"

    # Should have 7 curated plugins
    assert_equals "default-triggers has 7 plugins" "7" "${plugin_count}"

    # Each plugin should have required fields
    local valid_count
    valid_count="$(jq '[.plugins[] | select(.name and .source and .provides and .phase_fit and .description)] | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "all plugins have required fields" "7" "${valid_count}"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: FAIL — `.plugins` doesn't exist yet

**Step 3: Add the plugins section to default-triggers.json**

Add after the `methodology_hints` array closing bracket, before the final `}`:

```json
  "plugins": [
    {
      "name": "commit-commands",
      "source": "claude-plugins-official",
      "provides": {
        "commands": ["/commit", "/commit-push-pr", "/clean_gone"],
        "skills": [],
        "agents": [],
        "hooks": []
      },
      "phase_fit": ["SHIP"],
      "description": "Structured commit workflows and branch-to-PR automation"
    },
    {
      "name": "security-guidance",
      "source": "claude-plugins-official",
      "provides": {
        "commands": [],
        "skills": [],
        "agents": [],
        "hooks": ["PreToolUse:security-patterns"]
      },
      "phase_fit": ["*"],
      "description": "Write-time security blocker for XSS, injection, unsafe deserialization"
    },
    {
      "name": "hookify",
      "source": "claude-plugins-official",
      "provides": {
        "commands": ["/hookify", "/hookify:list", "/hookify:configure"],
        "skills": ["writing-rules"],
        "agents": ["conversation-analyzer"],
        "hooks": []
      },
      "phase_fit": ["DESIGN"],
      "description": "Custom rule authoring for Claude behavior guards"
    },
    {
      "name": "feature-dev",
      "source": "claude-plugins-official",
      "provides": {
        "commands": ["/feature-dev"],
        "skills": [],
        "agents": ["code-explorer", "code-architect", "code-reviewer"],
        "hooks": []
      },
      "phase_fit": ["DESIGN", "IMPLEMENT", "REVIEW"],
      "description": "Full feature pipeline with parallel exploration and architecture agents"
    },
    {
      "name": "code-review",
      "source": "claude-plugins-official",
      "provides": {
        "commands": ["/code-review"],
        "skills": [],
        "agents": [],
        "hooks": []
      },
      "phase_fit": ["REVIEW"],
      "description": "5 parallel review agents with confidence scoring, posts to GitHub"
    },
    {
      "name": "code-simplifier",
      "source": "claude-plugins-official",
      "provides": {
        "commands": [],
        "skills": [],
        "agents": ["code-simplifier"],
        "hooks": []
      },
      "phase_fit": ["REVIEW"],
      "description": "Post-review code clarity and simplification pass"
    },
    {
      "name": "skill-creator",
      "source": "claude-plugins-official",
      "provides": {
        "commands": [],
        "skills": ["skill-creator"],
        "agents": ["executor", "grader", "comparator", "analyzer"],
        "hooks": []
      },
      "phase_fit": ["DESIGN"],
      "description": "Skill eval/improvement loop with benchmarking"
    }
  ]
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add config/default-triggers.json tests/test-registry.sh
git commit -m "feat: add plugins section to default-triggers.json"
```

---

### Task 2: Add phase_compositions section to default-triggers.json

**Files:**
- Modify: `config/default-triggers.json`

**Step 1: Write the failing test**

Add to `tests/test-registry.sh`:

```bash
test_default_triggers_has_phase_compositions() {
    echo "-- test: default-triggers has phase_compositions --"
    setup_test_env

    local phases
    phases="$(jq '.phase_compositions | keys[]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null | sort)"

    assert_contains "has DESIGN phase" "DESIGN" "${phases}"
    assert_contains "has PLAN phase" "PLAN" "${phases}"
    assert_contains "has IMPLEMENT phase" "IMPLEMENT" "${phases}"
    assert_contains "has REVIEW phase" "REVIEW" "${phases}"
    assert_contains "has SHIP phase" "SHIP" "${phases}"
    assert_contains "has DEBUG phase" "DEBUG" "${phases}"

    # Each phase must have a driver field
    local driver_count
    driver_count="$(jq '[.phase_compositions | to_entries[] | select(.value.driver)] | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "all 6 phases have drivers" "6" "${driver_count}"

    # REVIEW should have parallel entries
    local review_parallel
    review_parallel="$(jq '.phase_compositions.REVIEW.parallel | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "REVIEW has 2 parallel entries" "2" "${review_parallel}"

    # SHIP should have sequence entries
    local ship_sequence
    ship_sequence="$(jq '.phase_compositions.SHIP.sequence | length' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "SHIP has 3 sequence entries" "3" "${ship_sequence}"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: FAIL — `.phase_compositions` doesn't exist yet

**Step 3: Add the phase_compositions section to default-triggers.json**

Add after the `plugins` array, before the final `}`:

```json
  "phase_compositions": {
    "DESIGN": {
      "driver": "brainstorming",
      "parallel": [
        {
          "plugin": "feature-dev",
          "use": "agents:code-explorer",
          "when": "installed",
          "purpose": "Parallel codebase exploration while brainstorming clarifies intent"
        }
      ],
      "hints": [
        {
          "plugin": "feature-dev",
          "text": "Consider /feature-dev for agent-parallel feature development",
          "when": "installed"
        },
        {
          "plugin": "skill-creator",
          "text": "Consider Skill(skill-creator) to eval/benchmark skill quality",
          "when": "installed AND prompt matches skill"
        },
        {
          "plugin": "hookify",
          "text": "Consider /hookify to create behavior rules",
          "when": "installed AND prompt matches (prevent|block|guard|rule)"
        }
      ]
    },
    "PLAN": {
      "driver": "writing-plans",
      "parallel": [],
      "hints": []
    },
    "IMPLEMENT": {
      "driver": "executing-plans",
      "parallel": [
        {
          "plugin": "security-guidance",
          "use": "hooks:PreToolUse",
          "when": "installed",
          "purpose": "Passive write-time security guard (always active, no explicit invocation)"
        }
      ],
      "hints": []
    },
    "REVIEW": {
      "driver": "requesting-code-review",
      "parallel": [
        {
          "plugin": "code-review",
          "use": "commands:/code-review",
          "when": "installed",
          "purpose": "Run 5 parallel review agents and post findings to GitHub PR"
        },
        {
          "plugin": "code-simplifier",
          "use": "agents:code-simplifier",
          "when": "installed",
          "purpose": "Post-review simplification pass for clarity"
        }
      ],
      "hints": [
        {
          "plugin": "code-review",
          "text": "Consider /code-review for automated multi-agent PR review",
          "when": "installed"
        }
      ]
    },
    "SHIP": {
      "driver": "verification-before-completion",
      "sequence": [
        {
          "plugin": "commit-commands",
          "use": "commands:/commit",
          "when": "installed",
          "purpose": "Execute structured commit after verification passes"
        },
        {
          "step": "finishing-a-development-branch",
          "purpose": "Branch cleanup, merge, or PR creation"
        },
        {
          "plugin": "commit-commands",
          "use": "commands:/commit-push-pr",
          "when": "installed AND user chooses PR option",
          "purpose": "Automated branch-to-PR flow"
        }
      ],
      "hints": [
        {
          "plugin": "commit-commands",
          "text": "Consider /commit-push-pr for automated branch-to-PR workflow",
          "when": "installed"
        }
      ]
    },
    "DEBUG": {
      "driver": "systematic-debugging",
      "parallel": [],
      "hints": []
    }
  }
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add config/default-triggers.json tests/test-registry.sh
git commit -m "feat: add phase_compositions to default-triggers.json"
```

---

### Task 3: Extend session-start-hook.sh to discover curated plugins

**Files:**
- Modify: `hooks/session-start-hook.sh`

**Step 1: Write the failing test**

Add to `tests/test-registry.sh`:

```bash
test_discovers_curated_plugins() {
    echo "-- test: discovers curated plugins --"
    setup_test_env

    # Create mock plugin directories for curated plugins
    local plugin_base="${HOME}/.claude/plugins/cache/claude-plugins-official"
    mkdir -p "${plugin_base}/commit-commands"
    mkdir -p "${plugin_base}/feature-dev"
    mkdir -p "${plugin_base}/code-review"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "${cache_file}"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # commit-commands should be in plugins array and marked available
    local cc_available
    cc_available="$(jq -r '.plugins[] | select(.name == "commit-commands") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "commit-commands is available" "true" "${cc_available}"

    # feature-dev should be available
    local fd_available
    fd_available="$(jq -r '.plugins[] | select(.name == "feature-dev") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "feature-dev is available" "true" "${fd_available}"

    # security-guidance should exist but be unavailable (not installed)
    local sg_available
    sg_available="$(jq -r '.plugins[] | select(.name == "security-guidance") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "security-guidance is unavailable" "false" "${sg_available}"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: FAIL — registry cache has no `plugins` array

**Step 3: Add plugin discovery to session-start-hook.sh**

After Step 8 (methodology hints) and before Step 9 (build final registry), add:

```bash
# -----------------------------------------------------------------
# Step 8b: Discover curated plugins from default-triggers.json
# -----------------------------------------------------------------
PLUGINS_JSON="[]"
if [ -f "${DEFAULT_TRIGGERS}" ]; then
    CURATED_COUNT="$(jq '.plugins // [] | length' "${DEFAULT_TRIGGERS}" 2>/dev/null)" || CURATED_COUNT=0
    pi=0
    while [ "${pi}" -lt "${CURATED_COUNT}" ]; do
        plugin_name="$(jq -r ".plugins[${pi}].name" "${DEFAULT_TRIGGERS}")"
        plugin_source="$(jq -r ".plugins[${pi}].source" "${DEFAULT_TRIGGERS}")"
        plugin_json="$(jq ".plugins[${pi}]" "${DEFAULT_TRIGGERS}")"

        # Check if installed
        _installed=false
        if [ -d "${HOME}/.claude/plugins/cache/claude-plugins-official/${plugin_name}" ]; then
            _installed=true
        fi
        # Also check all marketplace dirs
        if [ "${_installed}" = "false" ]; then
            for _mkt_dir in "${HOME}/.claude/plugins/cache"/*/; do
                [ -d "${_mkt_dir}${plugin_name}" ] && _installed=true && break
            done
        fi

        plugin_json="$(printf '%s' "${plugin_json}" | jq --argjson avail "${_installed}" '. + {available: $avail}')"
        PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq --argjson p "${plugin_json}" '. + [$p]')"

        pi=$((pi + 1))
    done
fi
```

Then modify Step 9 to include plugins in the registry:

```bash
REGISTRY="$(jq -n \
    --arg version "4.0.0" \
    --argjson skills "${SKILLS_JSON}" \
    --argjson plugins "${PLUGINS_JSON}" \
    --argjson methodology_hints "${METHODOLOGY_HINTS}" \
    --argjson warnings "${WARNINGS}" \
    '{
        version: $version,
        skills: $skills,
        plugins: $plugins,
        methodology_hints: $methodology_hints,
        warnings: $warnings
    }'
)"
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "feat: discover curated plugins in session-start hook"
```

---

### Task 4: Add auto-discovery of unknown plugins

**Files:**
- Modify: `hooks/session-start-hook.sh`

**Step 1: Write the failing test**

Add to `tests/test-registry.sh`:

```bash
test_auto_discovers_unknown_plugins() {
    echo "-- test: auto-discovers unknown plugins --"
    setup_test_env

    # Create a mock unknown plugin with skills and commands
    local unknown_dir="${HOME}/.claude/plugins/cache/community-marketplace/my-unknown-plugin"
    mkdir -p "${unknown_dir}/skills/custom-lint"
    printf '---\nname: custom-lint\ndescription: Custom lint rules\n---\n# Custom Lint\n' > \
        "${unknown_dir}/skills/custom-lint/SKILL.md"
    mkdir -p "${unknown_dir}/commands"
    printf '# Run Lint\n' > "${unknown_dir}/commands/lint.md"
    mkdir -p "${unknown_dir}/.claude-plugin"
    printf '{"name":"my-unknown-plugin","version":"1.0.0"}\n' > "${unknown_dir}/.claude-plugin/plugin.json"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # Unknown plugin should appear in plugins array
    local up_name
    up_name="$(jq -r '.plugins[] | select(.name == "my-unknown-plugin") | .name' "${cache_file}" 2>/dev/null)"
    assert_equals "unknown plugin discovered" "my-unknown-plugin" "${up_name}"

    local up_available
    up_available="$(jq -r '.plugins[] | select(.name == "my-unknown-plugin") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "unknown plugin is available" "true" "${up_available}"

    # Should detect the skill
    local up_skills
    up_skills="$(jq -r '.plugins[] | select(.name == "my-unknown-plugin") | .provides.skills[0]' "${cache_file}" 2>/dev/null)"
    assert_equals "unknown plugin skill detected" "custom-lint" "${up_skills}"

    # Should detect the command
    local up_commands
    up_commands="$(jq -r '.plugins[] | select(.name == "my-unknown-plugin") | .provides.commands[0]' "${cache_file}" 2>/dev/null)"
    assert_equals "unknown plugin command detected" "/lint" "${up_commands}"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: FAIL

**Step 3: Add auto-discovery after curated plugin discovery**

After Step 8b in `session-start-hook.sh`, add:

```bash
# -----------------------------------------------------------------
# Step 8c: Auto-discover unknown plugins from all marketplaces
# -----------------------------------------------------------------
# Build list of curated plugin names for exclusion
CURATED_NAMES="$(printf '%s' "${PLUGINS_JSON}" | jq -r '.[].name' 2>/dev/null)"
# Also exclude plugins we already handle as skill sources
KNOWN_NAMES="${CURATED_NAMES}
superpowers
frontend-design
claude-md-management
claude-code-setup
pr-review-toolkit
ralph-loop
auto-claude-skills"

for _mkt_dir in "${HOME}/.claude/plugins/cache"/*/; do
    [ -d "${_mkt_dir}" ] || continue
    for _plugin_dir in "${_mkt_dir}"*/; do
        [ -d "${_plugin_dir}" ] || continue
        _pname="$(basename "${_plugin_dir}")"

        # Skip known/curated plugins
        _skip=0
        printf '%s\n' "${KNOWN_NAMES}" | while IFS= read -r _kn; do
            [ "${_kn}" = "${_pname}" ] && exit 1
        done || _skip=1
        [ "${_skip}" -eq 1 ] && continue

        # Must have a plugin.json to be a valid plugin
        _pjson=""
        for _vdir in "${_plugin_dir}" "${_plugin_dir}"*/; do
            if [ -f "${_vdir}.claude-plugin/plugin.json" ]; then
                _pjson="${_vdir}.claude-plugin/plugin.json"
                _plugin_root="${_vdir}"
                break
            fi
        done
        [ -z "${_pjson}" ] && continue

        # Scan for skills
        _skills="[]"
        if [ -d "${_plugin_root}skills" ]; then
            for _smd in "${_plugin_root}skills"/*/SKILL.md; do
                [ -f "${_smd}" ] || continue
                _sname="$(basename "$(dirname "${_smd}")")"
                _skills="$(printf '%s' "${_skills}" | jq --arg s "${_sname}" '. + [$s]')"
            done
        fi

        # Scan for commands
        _commands="[]"
        if [ -d "${_plugin_root}commands" ]; then
            for _cmd in "${_plugin_root}commands"/*.md; do
                [ -f "${_cmd}" ] || continue
                _cname="/$(basename "${_cmd}" .md)"
                _commands="$(printf '%s' "${_commands}" | jq --arg c "${_cname}" '. + [$c]')"
            done
        fi

        # Scan for agents
        _agents="[]"
        if [ -d "${_plugin_root}agents" ]; then
            for _agent in "${_plugin_root}agents"/*.md; do
                [ -f "${_agent}" ] || continue
                _aname="$(basename "${_agent}" .md)"
                _agents="$(printf '%s' "${_agents}" | jq --arg a "${_aname}" '. + [$a]')"
            done
        fi

        # Build plugin entry
        _entry="$(jq -n \
            --arg name "${_pname}" \
            --arg source "auto-discovered" \
            --argjson skills "${_skills}" \
            --argjson commands "${_commands}" \
            --argjson agents "${_agents}" \
            '{
                name: $name,
                source: $source,
                provides: {commands: $commands, skills: $skills, agents: $agents, hooks: []},
                phase_fit: ["*"],
                description: "Auto-discovered plugin",
                available: true
            }')"
        PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq --argjson p "${_entry}" '. + [$p]')"
    done
done
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "feat: auto-discover unknown plugins from all marketplaces"
```

---

### Task 5: Add phase_compositions to registry cache

**Files:**
- Modify: `hooks/session-start-hook.sh`

**Step 1: Write the failing test**

Add to `tests/test-registry.sh`:

```bash
test_registry_includes_phase_compositions() {
    echo "-- test: registry cache includes phase_compositions --"
    setup_test_env

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    local pc_keys
    pc_keys="$(jq '.phase_compositions | keys | length' "${cache_file}" 2>/dev/null)"
    assert_equals "phase_compositions has 6 phases" "6" "${pc_keys}"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: FAIL — no `phase_compositions` in cache

**Step 3: Add phase_compositions to the registry build in Step 9**

```bash
# Extract phase_compositions from default-triggers.json
PHASE_COMPOSITIONS="{}"
if [ -f "${DEFAULT_TRIGGERS}" ]; then
    PHASE_COMPOSITIONS="$(jq '.phase_compositions // {}' "${DEFAULT_TRIGGERS}" 2>/dev/null)" || PHASE_COMPOSITIONS="{}"
fi

REGISTRY="$(jq -n \
    --arg version "4.0.0" \
    --argjson skills "${SKILLS_JSON}" \
    --argjson plugins "${PLUGINS_JSON}" \
    --argjson phase_compositions "${PHASE_COMPOSITIONS}" \
    --argjson methodology_hints "${METHODOLOGY_HINTS}" \
    --argjson warnings "${WARNINGS}" \
    '{
        version: $version,
        skills: $skills,
        plugins: $plugins,
        phase_compositions: $phase_compositions,
        methodology_hints: $methodology_hints,
        warnings: $warnings
    }'
)"
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "feat: include phase_compositions in registry cache"
```

---

### Task 6: Extend session-start-hook.sh companion plugin check

**Files:**
- Modify: `hooks/session-start-hook.sh:368`

**Step 1: Write the failing test**

Add to `tests/test-registry.sh`:

```bash
test_health_check_reports_new_plugins() {
    echo "-- test: health check reports plugin count --"
    setup_test_env

    # Install one curated plugin
    mkdir -p "${HOME}/.claude/plugins/cache/claude-plugins-official/commit-commands"

    local output
    output="$(run_hook)"

    # Health check should mention plugins
    assert_contains "health check mentions plugins" "plugin" "$(printf '%s' "${output}" | tr '[:upper:]' '[:lower:]')"

    teardown_test_env
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: FAIL

**Step 3: Update the companion plugin list and health check**

In `session-start-hook.sh` line 368, extend the list:

```bash
for _plugin in superpowers frontend-design claude-md-management pr-review-toolkit claude-code-setup commit-commands security-guidance hookify feature-dev code-review code-simplifier skill-creator; do
```

Update the health check message in Step 12 to include plugin counts:

```bash
PLUGIN_COUNT="$(printf '%s' "${PLUGINS_JSON}" | jq 'length' 2>/dev/null)" || PLUGIN_COUNT=0
PLUGIN_AVAILABLE="$(printf '%s' "${PLUGINS_JSON}" | jq '[.[] | select(.available == true)] | length' 2>/dev/null)" || PLUGIN_AVAILABLE=0

MSG="SessionStart: skill registry built (${SKILL_COUNT} skills from ${SOURCE_COUNT} sources, ${PLUGIN_COUNT} plugins (${PLUGIN_AVAILABLE} available), ${WARNING_COUNT} warnings)${SETUP_HINTS}"
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "feat: extend companion plugin checks and health reporting"
```

---

### Task 7: Extend routing engine to emit PARALLEL/SEQUENCE lines

**Files:**
- Modify: `hooks/skill-activation-hook.sh`

**Step 1: Write the failing test**

Add to `tests/test-routing.sh`:

```bash
test_review_emits_parallel_lines() {
    echo "-- test: review phase emits PARALLEL lines --"
    setup_test_env
    install_registry_v4

    local output context
    output="$(run_hook "please review the code changes in this pull request")"
    context="$(extract_context "${output}")"

    assert_contains "review has PARALLEL line" "PARALLEL:" "${context}"
    assert_contains "review mentions code-review" "code-review" "${context}"

    teardown_test_env
}

test_ship_emits_sequence_lines() {
    echo "-- test: ship phase emits SEQUENCE lines --"
    setup_test_env
    install_registry_v4

    local output context
    output="$(run_hook "let's ship this and merge the branch to main")"
    context="$(extract_context "${output}")"

    assert_contains "ship has SEQUENCE line" "SEQUENCE:" "${context}"
    assert_contains "ship mentions commit" "commit" "$(printf '%s' "${context}" | tr '[:upper:]' '[:lower:]')"

    teardown_test_env
}

test_no_parallel_when_plugin_unavailable() {
    echo "-- test: no PARALLEL when plugin unavailable --"
    setup_test_env
    install_registry  # v3 registry, no plugins

    local output context
    output="$(run_hook "please review the code changes in this pull request")"
    context="$(extract_context "${output}")"

    assert_not_contains "no PARALLEL without plugins" "PARALLEL:" "${context}"

    teardown_test_env
}
```

Also add an `install_registry_v4` helper that includes the `plugins` and `phase_compositions` sections in the test registry, with `code-review` and `commit-commands` marked as `available: true`.

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | tail -10`
Expected: FAIL — no PARALLEL/SEQUENCE lines in output

**Step 3: Add composition output to skill-activation-hook.sh**

After the methodology hints section (around line 287) and before the output build section, add:

```bash
# =================================================================
# PHASE COMPOSITION: PARALLEL / SEQUENCE / HINTS
# =================================================================
COMPOSITION_LINES=""
COMPOSITION_HINTS=""

# Determine the current phase from selected skills
CURRENT_PHASE=""
while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    if [[ -n "$phase" ]]; then
        CURRENT_PHASE="$phase"
        break
    fi
done <<EOF
${SELECTED}
EOF

# Look up phase composition if registry has it and a phase was determined
if [[ -n "$CURRENT_PHASE" ]]; then
    _pc="$(printf '%s' "$REGISTRY" | jq -c --arg ph "$CURRENT_PHASE" '.phase_compositions[$ph] // empty' 2>/dev/null)"
    if [[ -n "$_pc" ]]; then
        # Emit PARALLEL lines for available plugins
        _par_count="$(printf '%s' "$_pc" | jq '.parallel // [] | length' 2>/dev/null)" || _par_count=0
        _pi=0
        while [[ "$_pi" -lt "$_par_count" ]]; do
            _plugin="$(printf '%s' "$_pc" | jq -r ".parallel[${_pi}].plugin" 2>/dev/null)"
            _use="$(printf '%s' "$_pc" | jq -r ".parallel[${_pi}].use" 2>/dev/null)"
            _purpose="$(printf '%s' "$_pc" | jq -r ".parallel[${_pi}].purpose" 2>/dev/null)"

            # Check if plugin is available
            _pavail="$(printf '%s' "$REGISTRY" | jq -r --arg pn "$_plugin" '.plugins // [] | .[] | select(.name == $pn) | .available' 2>/dev/null)"
            if [[ "$_pavail" == "true" ]]; then
                COMPOSITION_LINES="${COMPOSITION_LINES}
  PARALLEL: ${_use} -> ${_purpose} [${_plugin}]"
            fi
            _pi=$((_pi + 1))
        done

        # Emit SEQUENCE lines (SHIP phase)
        _seq_count="$(printf '%s' "$_pc" | jq '.sequence // [] | length' 2>/dev/null)" || _seq_count=0
        _si=0
        while [[ "$_si" -lt "$_seq_count" ]]; do
            _plugin="$(printf '%s' "$_pc" | jq -r ".sequence[${_si}].plugin // empty" 2>/dev/null)"
            _step="$(printf '%s' "$_pc" | jq -r ".sequence[${_si}].step // empty" 2>/dev/null)"
            _use="$(printf '%s' "$_pc" | jq -r ".sequence[${_si}].use // empty" 2>/dev/null)"
            _purpose="$(printf '%s' "$_pc" | jq -r ".sequence[${_si}].purpose" 2>/dev/null)"

            if [[ -n "$_plugin" ]]; then
                _pavail="$(printf '%s' "$REGISTRY" | jq -r --arg pn "$_plugin" '.plugins // [] | .[] | select(.name == $pn) | .available' 2>/dev/null)"
                if [[ "$_pavail" == "true" ]]; then
                    COMPOSITION_LINES="${COMPOSITION_LINES}
  SEQUENCE: ${_use} -> ${_purpose} [${_plugin}]"
                fi
            elif [[ -n "$_step" ]]; then
                COMPOSITION_LINES="${COMPOSITION_LINES}
  SEQUENCE: ${_step} -> ${_purpose}"
            fi
            _si=$((_si + 1))
        done

        # Collect composition hints for available plugins
        _hint_count="$(printf '%s' "$_pc" | jq '.hints // [] | length' 2>/dev/null)" || _hint_count=0
        _hi=0
        while [[ "$_hi" -lt "$_hint_count" ]]; do
            _plugin="$(printf '%s' "$_pc" | jq -r ".hints[${_hi}].plugin" 2>/dev/null)"
            _text="$(printf '%s' "$_pc" | jq -r ".hints[${_hi}].text" 2>/dev/null)"

            _pavail="$(printf '%s' "$REGISTRY" | jq -r --arg pn "$_plugin" '.plugins // [] | .[] | select(.name == $pn) | .available' 2>/dev/null)"
            if [[ "$_pavail" == "true" ]]; then
                COMPOSITION_HINTS="${COMPOSITION_HINTS}
- ${_text}"
            fi
            _hi=$((_hi + 1))
        done
    fi
fi
```

Then in the output build section, inject `COMPOSITION_LINES` after the skill lines (process/domain/workflow) and append `COMPOSITION_HINTS` alongside methodology hints.

For the 1-2 skills format, insert after `${WORKFLOW_LINES}${STANDALONE_LINES}`:
```bash
OUT+="${PROCESS_LINE}${DOMAIN_LINES}${WORKFLOW_LINES}${STANDALONE_LINES}${COMPOSITION_LINES}"
```

For the 3+ skills format, insert after the skill loop and before the evaluation instruction.

Append composition hints alongside methodology hints at the end:
```bash
if [[ -n "$HINTS" ]] || [[ -n "$COMPOSITION_HINTS" ]]; then
  OUT+="
${HINTS}${COMPOSITION_HINTS}"
fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-routing.sh 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: emit PARALLEL/SEQUENCE lines from phase compositions"
```

---

### Task 8: Update fallback-registry.json

**Files:**
- Modify: `config/fallback-registry.json`

**Step 1: Write the failing test**

Add to `tests/test-install.sh`:

```bash
test_fallback_has_plugins() {
    echo "-- test: fallback registry has plugins section --"

    local fallback="${PROJECT_ROOT}/config/fallback-registry.json"
    assert_file_exists "fallback registry exists" "${fallback}"
    assert_json_valid "fallback registry is valid JSON" "${fallback}"

    local has_plugins
    has_plugins="$(jq 'has("plugins")' "${fallback}" 2>/dev/null)"
    assert_equals "fallback has plugins key" "true" "${has_plugins}"

    local has_pc
    has_pc="$(jq 'has("phase_compositions")' "${fallback}" 2>/dev/null)"
    assert_equals "fallback has phase_compositions key" "true" "${has_pc}"
}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-install.sh 2>&1 | tail -10`
Expected: FAIL — no plugins/phase_compositions in fallback

**Step 3: Update fallback-registry.json**

Add `plugins` (empty array — no plugins can be confirmed available in fallback mode) and a minimal `phase_compositions` section:

```json
{
  "version": "4.0.0-fallback",
  "description": "Static fallback registry for degraded environments (no jq, missing plugin dirs)",
  "warnings": ["Using static fallback registry — dynamic discovery unavailable"],
  "skills": [ /* existing 8 entries unchanged */ ],
  "plugins": [],
  "phase_compositions": {
    "DESIGN": {"driver": "brainstorming", "parallel": [], "hints": []},
    "PLAN": {"driver": "writing-plans", "parallel": [], "hints": []},
    "IMPLEMENT": {"driver": "executing-plans", "parallel": [], "hints": []},
    "REVIEW": {"driver": "requesting-code-review", "parallel": [], "hints": []},
    "SHIP": {"driver": "verification-before-completion", "sequence": [], "hints": []},
    "DEBUG": {"driver": "systematic-debugging", "parallel": [], "hints": []}
  }
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-install.sh 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add config/fallback-registry.json tests/test-install.sh
git commit -m "feat: add plugins and phase_compositions to fallback registry"
```

---

### Task 9: Update default-triggers.json version and update existing tests

**Files:**
- Modify: `config/default-triggers.json:2` (version bump)
- Modify: `tests/test-registry.sh` (update version assertions)

**Step 1: Bump version in default-triggers.json**

Change `"version": "3.1.0"` to `"version": "4.0.0"`.

**Step 2: Update any version-checking tests**

Search test files for `3.1` version checks and update to `4.0`.

**Step 3: Run all tests**

Run: `bash tests/run-tests.sh 2>&1`
Expected: ALL PASS

**Step 4: Commit**

```bash
git add config/default-triggers.json tests/
git commit -m "feat: bump version to 4.0.0"
```

---

### Task 10: Run full test suite and fix any regressions

**Files:**
- All test files under `tests/`

**Step 1: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1`

**Step 2: Fix any failing tests**

Identify failures, fix root causes. Common issues:
- The `install_registry` helper in test-routing.sh needs a v4 variant with plugins/phase_compositions
- Health check assertions may need updating for new message format
- Version string assertions may need updating

**Step 3: Run full test suite again**

Run: `bash tests/run-tests.sh 2>&1`
Expected: ALL PASS

**Step 4: Commit**

```bash
git add tests/
git commit -m "fix: update tests for v4.0.0 compatibility"
```
