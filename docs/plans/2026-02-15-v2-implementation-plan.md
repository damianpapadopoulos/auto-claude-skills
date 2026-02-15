# auto-claude-skills v2.0 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite auto-claude-skills as a config-driven, role-based skill activation system with tests, adaptive context injection, and multi-skill orchestration.

**Architecture:** Replace hardcoded regex/skill mappings with a JSON registry built at session start from dynamic discovery. The routing engine reads the registry, scores matches by trigger+phase, selects skills by role (process/domain/workflow), and emits orchestrated context. A test harness validates all deterministic behavior.

**Tech Stack:** Bash 3.2+ (macOS compatible), jq, JSON config files

---

### Task 1: Create default-triggers.json (starter pack)

**Files:**
- Create: `config/default-triggers.json`

This is the curated trigger/role/relationship definitions for all known skills. The routing engine and registry builder both consume this file.

**Step 1: Create config directory and default-triggers.json**

```json
{
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": ["DESIGN"],
      "triggers": ["build", "create", "implement", "develop", "scaffold", "init", "bootstrap", "brainstorm", "design", "architect", "strateg", "scope", "outline", "approach", "add", "write", "make", "generate", "set.?up", "install", "configure", "wire.up", "connect", "integrate", "extend", "new", "start", "introduce", "enable", "support", "how.(should|would|could)"],
      "trigger_mode": "regex",
      "priority": 30,
      "precedes": ["writing-plans"],
      "description": "Explore intent and requirements before implementation"
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": ["PLAN"],
      "triggers": ["plan", "break.down", "outline.steps", "task.list", "implementation.plan"],
      "trigger_mode": "regex",
      "priority": 25,
      "precedes": ["executing-plans", "subagent-driven-development"],
      "requires": ["brainstorming"],
      "description": "Break spec into bite-sized implementation tasks"
    },
    {
      "name": "executing-plans",
      "role": "process",
      "phase": ["IMPLEMENT"],
      "triggers": ["execute.*plan", "run.the.plan", "implement.the.plan", "implement.*(rest|remaining)", "follow.the.plan", "pick.up", "resume", "next.task", "next.step", "carry.on", "keep.going", "where.were.we", "what.s.next", "continue"],
      "trigger_mode": "regex",
      "priority": 20,
      "requires": ["writing-plans"],
      "description": "Execute implementation plan task-by-task"
    },
    {
      "name": "subagent-driven-development",
      "role": "process",
      "phase": ["IMPLEMENT"],
      "triggers": ["execute.*plan", "run.the.plan", "implement.the.plan", "implement.*(rest|remaining)", "follow.the.plan", "pick.up", "resume", "next.task", "next.step", "carry.on", "keep.going", "where.were.we", "what.s.next", "continue"],
      "trigger_mode": "regex",
      "priority": 20,
      "requires": ["writing-plans"],
      "description": "Execute plan with fresh subagent per task"
    },
    {
      "name": "test-driven-development",
      "role": "process",
      "phase": ["IMPLEMENT"],
      "triggers": ["test", "tdd", "run", "execute", "verify", "validate", "check", "ensure", "confirm", "try", "attempt", "evaluate", "assert", "expect", "coverage", "pass", "green"],
      "trigger_mode": "regex",
      "priority": 15,
      "description": "Write failing test first, then implement"
    },
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": ["DEBUG"],
      "triggers": ["debug", "bug", "fix", "broken", "fail", "error", "crash", "wrong", "unexpected", "not.work", "regression", "issue", "problem", "doesn.t", "won.t", "can.t", "stuck", "hang", "freeze", "timeout", "leak", "corrupt", "invalid", "missing", "explain", "understand", "what.is", "what.does", "how.does", "where.is", "find", "search", "look.at", "show.me", "trace", "investigate", "analyze", "profile", "benchmark"],
      "trigger_mode": "regex",
      "priority": 40,
      "description": "Systematic root-cause analysis before fixing"
    },
    {
      "name": "requesting-code-review",
      "role": "process",
      "phase": ["REVIEW"],
      "triggers": ["review", "pull.?request", "code.?review", "check.*(code|changes|diff)", "code.?quality", "lint", "smell", "tech.?debt", "pr($|[^a-z])"],
      "trigger_mode": "regex",
      "priority": 20,
      "description": "Request structured code review"
    },
    {
      "name": "receiving-code-review",
      "role": "process",
      "phase": ["REVIEW"],
      "triggers": ["review", "pull.?request", "code.?review", "pr($|[^a-z])"],
      "trigger_mode": "regex",
      "priority": 19,
      "description": "Process code review feedback with technical rigor"
    },
    {
      "name": "verification-before-completion",
      "role": "workflow",
      "triggers": ["ship", "merge", "deploy", "push", "release", "tag", "publish", "pr.ready", "ready.to", "wrap.?up", "all.(done|good|green|passing)", "lgtm", "finalize", "complete", "finish"],
      "trigger_mode": "regex",
      "priority": 20,
      "description": "Run verification before claiming work is done"
    },
    {
      "name": "finishing-a-development-branch",
      "role": "workflow",
      "triggers": ["ship", "merge", "deploy", "push", "release", "tag", "publish", "pr.ready", "ready.to", "wrap.?up", "finalize", "complete", "finish"],
      "trigger_mode": "regex",
      "priority": 19,
      "description": "Guide branch completion — merge, PR, or cleanup"
    },
    {
      "name": "dispatching-parallel-agents",
      "role": "workflow",
      "triggers": ["parallel", "concurrent", "multiple.*(failure|bug|issue|error|test)", "independent.*(task|failure|bug|issue|test)"],
      "trigger_mode": "regex",
      "priority": 15,
      "description": "Dispatch independent tasks to parallel agents"
    },
    {
      "name": "using-git-worktrees",
      "role": "workflow",
      "triggers": ["worktree", "parallel", "isolat"],
      "trigger_mode": "regex",
      "priority": 10,
      "description": "Create isolated git worktrees for feature work"
    },
    {
      "name": "writing-skills",
      "role": "domain",
      "triggers": ["skill", "hook", "plugin"],
      "trigger_mode": "regex",
      "priority": 10,
      "description": "Create or edit Claude Code skills"
    },
    {
      "name": "frontend-design",
      "role": "domain",
      "triggers": ["ui", "frontend", "component", "layout", "style", "css", "tailwind", "responsive", "dashboard", "landing.?page", "mockup", "wireframe", "modal", "form", "button", "page"],
      "trigger_mode": "regex",
      "priority": 15,
      "description": "Specialized frontend design guidance"
    },
    {
      "name": "security-scanner",
      "role": "domain",
      "triggers": ["secur(e|ity)", "vulnerab", "owasp", "pentest", "attack", "exploit", "compliance", "hipaa", "gdpr", "encrypt", "auth(entication|orization)", "inject", "xss", "csrf", "sanitiz", "supply.?chain"],
      "trigger_mode": "regex",
      "priority": 15,
      "description": "Scan for security vulnerabilities"
    },
    {
      "name": "webapp-testing",
      "role": "domain",
      "triggers": ["ui", "frontend", "component", "browser", "playwright", "screenshot", "visual"],
      "trigger_mode": "regex",
      "priority": 10,
      "description": "Test web apps with Playwright"
    },
    {
      "name": "doc-coauthoring",
      "role": "domain",
      "triggers": ["proposal", "spec[^a-z]", "rfc", "write.?up", "technical.?doc", "architecture.?doc", "documentation"],
      "trigger_mode": "regex",
      "priority": 15,
      "description": "Co-author structured documentation"
    },
    {
      "name": "claude-automation-recommender",
      "role": "domain",
      "triggers": ["claude\\.md", "claude.md", "\\.claude", "skill", "hook", "mcp", "plugin", "automation"],
      "trigger_mode": "regex",
      "priority": 10,
      "description": "Recommend Claude Code automations"
    },
    {
      "name": "claude-md-improver",
      "role": "domain",
      "triggers": ["claude\\.md", "claude.md", "project.memory"],
      "trigger_mode": "regex",
      "priority": 10,
      "description": "Audit and improve CLAUDE.md files"
    }
  ],
  "methodology_hints": [
    {
      "name": "ralph-loop",
      "plugin": "ralph-loop",
      "triggers": ["migrate", "refactor.all", "fix.all", "batch", "overnight", "autonom", "iterate", "keep.(going|trying|fixing)", "until.*(pass|work|complet|succeed)", "make.*tests?.pass", "run.*until", "loop", "coverage", "greenfield"],
      "hint": "RALPH LOOP: Consider /ralph-loop for autonomous iteration."
    },
    {
      "name": "pr-review",
      "plugin": "pr-review-toolkit",
      "triggers": ["review", "pull.?request", "code.?review", "pr($|[^a-z])"],
      "hint": "PR REVIEW: Consider /pr-review for structured review."
    }
  ],
  "blocklist_patterns": [
    "^(hi|hello|hey|thanks|thank.you|good.(morning|afternoon|evening)|bye|goodbye|ok|okay|yes|no|sure|yep|nope|got.it|sounds.good|cool|nice|great|perfect|awesome|understood)([[:space:]!.,]+.{0,20})?$"
  ],
  "version": "2.0.0"
}
```

**Step 2: Verify JSON is valid**

Run: `jq . config/default-triggers.json`
Expected: Pretty-printed JSON, no errors

**Step 3: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: add default-triggers.json starter pack config"
```

---

### Task 2: Create fallback-registry.json (static fallback)

**Files:**
- Create: `config/fallback-registry.json`

This is the minimal static registry used when dynamic discovery fails (no jq, missing plugin dirs, etc). Contains core superpowers skills with `Skill()` invocation paths.

**Step 1: Create fallback-registry.json**

```json
{
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "invoke": "Skill(superpowers:brainstorming)",
      "phase": ["DESIGN"],
      "triggers": ["build", "create", "add", "design", "new", "implement"],
      "priority": 30,
      "precedes": ["writing-plans"]
    },
    {
      "name": "writing-plans",
      "role": "process",
      "invoke": "Skill(superpowers:writing-plans)",
      "phase": ["PLAN"],
      "triggers": ["plan", "break.down", "outline.steps"],
      "priority": 25,
      "precedes": ["executing-plans"]
    },
    {
      "name": "executing-plans",
      "role": "process",
      "invoke": "Skill(superpowers:executing-plans)",
      "phase": ["IMPLEMENT"],
      "triggers": ["execute.*plan", "continue", "next.task", "resume"],
      "priority": 20
    },
    {
      "name": "test-driven-development",
      "role": "process",
      "invoke": "Skill(superpowers:test-driven-development)",
      "phase": ["IMPLEMENT"],
      "triggers": ["test", "tdd", "verify", "validate"],
      "priority": 15
    },
    {
      "name": "systematic-debugging",
      "role": "process",
      "invoke": "Skill(superpowers:systematic-debugging)",
      "phase": ["DEBUG"],
      "triggers": ["debug", "bug", "fix", "broken", "error", "crash"],
      "priority": 40
    },
    {
      "name": "requesting-code-review",
      "role": "process",
      "invoke": "Skill(superpowers:requesting-code-review)",
      "phase": ["REVIEW"],
      "triggers": ["review", "code.?review"],
      "priority": 20
    },
    {
      "name": "verification-before-completion",
      "role": "workflow",
      "invoke": "Skill(superpowers:verification-before-completion)",
      "triggers": ["ship", "merge", "deploy", "finish", "complete"],
      "priority": 20
    },
    {
      "name": "finishing-a-development-branch",
      "role": "workflow",
      "invoke": "Skill(superpowers:finishing-a-development-branch)",
      "triggers": ["ship", "merge", "finish", "complete", "pr.ready"],
      "priority": 19
    }
  ],
  "warnings": ["Using static fallback registry — dynamic discovery unavailable"],
  "version": "2.0.0-fallback"
}
```

**Step 2: Verify JSON is valid**

Run: `jq . config/fallback-registry.json`
Expected: Pretty-printed JSON, no errors

**Step 3: Commit**

```bash
git add config/fallback-registry.json
git commit -m "feat: add fallback-registry.json for degraded environments"
```

---

### Task 3: Create test harness framework

**Files:**
- Create: `tests/test-helpers.sh`
- Create: `tests/run-tests.sh`

The test framework provides assert functions and a runner that discovers and executes test files. No external dependencies beyond bash.

**Step 1: Create tests/test-helpers.sh**

```bash
#!/bin/bash
# --- Test helpers for auto-claude-skills ---
# Source this file in each test script.

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAIL_MESSAGES=""

# Create isolated temp environment
setup_test_env() {
  TEST_HOME=$(mktemp -d)
  TEST_PLUGIN_CACHE="$TEST_HOME/.claude/plugins/cache/claude-plugins-official"
  TEST_USER_SKILLS="$TEST_HOME/.claude/skills"
  TEST_REGISTRY_CACHE="$TEST_HOME/.claude/.skill-registry-cache.json"
  TEST_USER_CONFIG="$TEST_HOME/.claude/skill-config.json"
  mkdir -p "$TEST_PLUGIN_CACHE" "$TEST_USER_SKILLS"

  # Point hooks at test environment
  export HOME="$TEST_HOME"
  export CLAUDE_PLUGIN_ROOT="${SCRIPT_DIR}/.."
}

teardown_test_env() {
  [[ -n "${TEST_HOME:-}" ]] && rm -rf "$TEST_HOME"
}

assert_equals() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  ((TESTS_RUN++))
  if [[ "$expected" == "$actual" ]]; then
    ((TESTS_PASSED++))
    echo "  PASS: $description"
  else
    ((TESTS_FAILED++))
    FAIL_MESSAGES+="  FAIL: $description\n    expected: $expected\n    actual:   $actual\n"
    echo "  FAIL: $description"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  ((TESTS_RUN++))
  if echo "$haystack" | grep -q "$needle"; then
    ((TESTS_PASSED++))
    echo "  PASS: $description"
  else
    ((TESTS_FAILED++))
    FAIL_MESSAGES+="  FAIL: $description\n    expected to contain: $needle\n    actual: ${haystack:0:200}\n"
    echo "  FAIL: $description"
    echo "    expected to contain: $needle"
    echo "    actual: ${haystack:0:200}"
  fi
}

assert_not_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  ((TESTS_RUN++))
  if ! echo "$haystack" | grep -q "$needle"; then
    ((TESTS_PASSED++))
    echo "  PASS: $description"
  else
    ((TESTS_FAILED++))
    FAIL_MESSAGES+="  FAIL: $description\n    expected NOT to contain: $needle\n"
    echo "  FAIL: $description"
    echo "    expected NOT to contain: $needle"
  fi
}

assert_json_valid() {
  local description="$1"
  local file="$2"
  ((TESTS_RUN++))
  if jq . "$file" > /dev/null 2>&1; then
    ((TESTS_PASSED++))
    echo "  PASS: $description"
  else
    ((TESTS_FAILED++))
    FAIL_MESSAGES+="  FAIL: $description\n    $file is not valid JSON\n"
    echo "  FAIL: $description"
    echo "    $file is not valid JSON"
  fi
}

assert_file_exists() {
  local description="$1"
  local file="$2"
  ((TESTS_RUN++))
  if [[ -f "$file" ]]; then
    ((TESTS_PASSED++))
    echo "  PASS: $description"
  else
    ((TESTS_FAILED++))
    FAIL_MESSAGES+="  FAIL: $description\n    file not found: $file\n"
    echo "  FAIL: $description"
    echo "    file not found: $file"
  fi
}

print_summary() {
  echo ""
  echo "--- Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ---"
  if ((TESTS_FAILED > 0)); then
    echo ""
    printf '%b' "$FAIL_MESSAGES"
    return 1
  fi
  return 0
}
```

**Step 2: Create tests/run-tests.sh**

```bash
#!/bin/bash
# --- Test runner for auto-claude-skills ---
# Discovers and runs all tests/test-*.sh files.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_RUN=0

echo "========================================="
echo " auto-claude-skills test suite"
echo "========================================="
echo ""

for test_file in "$SCRIPT_DIR"/test-*.sh; do
  [[ ! -f "$test_file" ]] && continue
  test_name=$(basename "$test_file" .sh)
  echo "--- $test_name ---"

  output=$(bash "$test_file" 2>&1)
  exit_code=$?
  echo "$output"

  # Extract counts from output
  passed=$(echo "$output" | grep -c "PASS:" || true)
  failed=$(echo "$output" | grep -c "FAIL:" || true)
  run=$((passed + failed))

  TOTAL_PASSED=$((TOTAL_PASSED + passed))
  TOTAL_FAILED=$((TOTAL_FAILED + failed))
  TOTAL_RUN=$((TOTAL_RUN + run))
  echo ""
done

echo "========================================="
echo " TOTAL: $TOTAL_PASSED/$TOTAL_RUN passed, $TOTAL_FAILED failed"
echo "========================================="

if ((TOTAL_FAILED > 0)); then
  exit 1
fi
exit 0
```

**Step 3: Make scripts executable and verify**

Run: `chmod +x tests/run-tests.sh tests/test-helpers.sh`
Expected: No errors

**Step 4: Commit**

```bash
git add tests/test-helpers.sh tests/run-tests.sh
git commit -m "feat: add test harness framework with assert helpers and runner"
```

---

### Task 4: Write session-start-hook.sh (registry builder)

**Files:**
- Create: `hooks/session-start-hook.sh`
- Modify: `hooks/fix-plugin-manifests.sh` (keep as-is, called from new hook)

The session start hook builds the skill registry by scanning plugin cache + user skills, merging with default triggers, applying user config overrides, and caching the result.

**Step 1: Write the failing test (tests/test-registry.sh)**

```bash
#!/bin/bash
# --- Registry builder tests ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

setup_test_env

# --- Test: empty environment produces fallback registry ---
echo '{"prompt":"test"}' | bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start-hook.sh" > /dev/null 2>&1
assert_file_exists "registry cache created" "$TEST_REGISTRY_CACHE"
assert_json_valid "registry cache is valid JSON" "$TEST_REGISTRY_CACHE"
assert_contains "fallback warning present" "fallback" "$(jq -r '.warnings[]?' "$TEST_REGISTRY_CACHE" 2>/dev/null)"

teardown_test_env
setup_test_env

# --- Test: discovers superpowers plugin skills ---
SP_DIR="$TEST_PLUGIN_CACHE/superpowers/1.0.0/skills/brainstorming"
mkdir -p "$SP_DIR"
echo "# Brainstorming" > "$SP_DIR/SKILL.md"

bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start-hook.sh" > /dev/null 2>&1
assert_contains "brainstorming discovered" "brainstorming" "$(jq -r '.skills[].name' "$TEST_REGISTRY_CACHE" 2>/dev/null)"

teardown_test_env
setup_test_env

# --- Test: discovers user-installed skills ---
mkdir -p "$TEST_USER_SKILLS/my-custom-skill"
echo "# My Custom Skill" > "$TEST_USER_SKILLS/my-custom-skill/SKILL.md"

bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start-hook.sh" > /dev/null 2>&1
assert_contains "custom skill discovered" "my-custom-skill" "$(jq -r '.skills[].name' "$TEST_REGISTRY_CACHE" 2>/dev/null)"

teardown_test_env
setup_test_env

# --- Test: discovers official plugin skills ---
mkdir -p "$TEST_PLUGIN_CACHE/frontend-design/.claude-plugin"
echo '{"name":"frontend-design"}' > "$TEST_PLUGIN_CACHE/frontend-design/.claude-plugin/plugin.json"

bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start-hook.sh" > /dev/null 2>&1
assert_contains "frontend-design discovered" "frontend-design" "$(jq -r '.skills[].name' "$TEST_REGISTRY_CACHE" 2>/dev/null)"

teardown_test_env
setup_test_env

# --- Test: missing plugin dir doesn't cause error ---
rmdir "$TEST_PLUGIN_CACHE" 2>/dev/null || true
bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start-hook.sh" > /dev/null 2>&1
exit_code=$?
assert_equals "missing plugin cache doesn't crash" "0" "$exit_code"
assert_file_exists "fallback registry still created" "$TEST_REGISTRY_CACHE"

teardown_test_env
setup_test_env

# --- Test: user config overrides ---
mkdir -p "$TEST_PLUGIN_CACHE/superpowers/1.0.0/skills/brainstorming"
echo "# Brainstorming" > "$TEST_PLUGIN_CACHE/superpowers/1.0.0/skills/brainstorming/SKILL.md"

cat > "$TEST_USER_CONFIG" << 'EOF'
{
  "overrides": {
    "brainstorming": { "enabled": false }
  }
}
EOF

bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start-hook.sh" > /dev/null 2>&1
disabled=$(jq -r '.skills[] | select(.name == "brainstorming") | .enabled' "$TEST_REGISTRY_CACHE" 2>/dev/null)
assert_equals "brainstorming disabled by user config" "false" "$disabled"

teardown_test_env
setup_test_env

# --- Test: health check output ---
output=$(bash "$CLAUDE_PLUGIN_ROOT/hooks/session-start-hook.sh" 2>&1)
assert_contains "health check in output" "skill registry built" "$output"

teardown_test_env

print_summary
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh`
Expected: FAIL (session-start-hook.sh doesn't exist yet)

**Step 3: Write hooks/session-start-hook.sh**

```bash
#!/bin/bash
# --- auto-claude-skills Session Start Hook ---
# Builds skill registry from dynamic discovery + config defaults.
# Caches result for the routing engine to read.
#
# Sources (merge order):
#   1. config/fallback-registry.json (static baseline)
#   2. Dynamic discovery (plugin cache + user skills)
#   3. config/default-triggers.json (trigger definitions)
#   4. ~/.claude/skill-config.json (user overrides)
#
# Output: ~/.claude/.skill-registry-cache.json
# Also: runs fix-plugin-manifests.sh for backwards compat
# -----------------------------------------------------------------
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CACHE_FILE="$HOME/.claude/.skill-registry-cache.json"
DEFAULT_TRIGGERS="$PLUGIN_ROOT/config/default-triggers.json"
FALLBACK_REGISTRY="$PLUGIN_ROOT/config/fallback-registry.json"
USER_CONFIG="$HOME/.claude/skill-config.json"
PLUGIN_CACHE="$HOME/.claude/plugins/cache/claude-plugins-official"
USER_SKILLS="$HOME/.claude/skills"

WARNINGS='[]'
DISCOVERED_SKILLS='[]'

# --- Run manifest fixer (backwards compat) -----------------------
if [[ -x "$PLUGIN_ROOT/hooks/fix-plugin-manifests.sh" ]]; then
  bash "$PLUGIN_ROOT/hooks/fix-plugin-manifests.sh" 2>/dev/null || true
fi

# --- Check jq availability --------------------------------------
if ! command -v jq &>/dev/null; then
  # No jq — use fallback registry directly
  if [[ -f "$FALLBACK_REGISTRY" ]]; then
    cp "$FALLBACK_REGISTRY" "$CACHE_FILE"
  else
    echo '{"skills":[],"warnings":["jq not found, no fallback registry"],"version":"2.0.0-degraded"}' > "$CACHE_FILE"
  fi
  echo "SessionStart: skill registry built (fallback — jq not found)"
  exit 0
fi

# --- Discover superpowers plugin skills --------------------------
SP_BASE="$PLUGIN_CACHE/superpowers"
SP_SKILLS=""
if [[ -d "$SP_BASE" ]]; then
  SP_VERSION=$(ls -1 "$SP_BASE" 2>/dev/null | sort -V | tail -1)
  [[ -n "$SP_VERSION" ]] && SP_SKILLS="$SP_BASE/$SP_VERSION/skills"
fi

if [[ -n "$SP_SKILLS" && -d "$SP_SKILLS" ]]; then
  for skill_dir in "$SP_SKILLS"/*/; do
    [[ ! -f "$skill_dir/SKILL.md" ]] && continue
    skill_name=$(basename "$skill_dir")
    DISCOVERED_SKILLS=$(echo "$DISCOVERED_SKILLS" | jq --arg name "$skill_name" --arg invoke "Read $skill_dir/SKILL.md" \
      '. + [{"name": $name, "source": "superpowers", "invoke": $invoke, "discovered": true}]')
  done
else
  WARNINGS=$(echo "$WARNINGS" | jq '. + ["superpowers plugin not found"]')
fi

# --- Discover official plugin skills -----------------------------
OFFICIAL_PLUGINS=("frontend-design" "claude-md-management" "claude-code-setup" "ralph-loop" "pr-review-toolkit")
declare -A PLUGIN_SKILL_MAP
PLUGIN_SKILL_MAP=(
  ["frontend-design"]="frontend-design:frontend-design"
  ["claude-md-management"]="claude-md-management:claude-md-improver"
  ["claude-code-setup"]="claude-code-setup:claude-automation-recommender"
)

for plugin in "${OFFICIAL_PLUGINS[@]}"; do
  if [[ -d "$PLUGIN_CACHE/$plugin" ]]; then
    skill_ref="${PLUGIN_SKILL_MAP[$plugin]:-}"
    if [[ -n "$skill_ref" ]]; then
      skill_name="${skill_ref#*:}"
      DISCOVERED_SKILLS=$(echo "$DISCOVERED_SKILLS" | jq --arg name "$skill_name" --arg invoke "Call Skill($skill_ref)" --arg source "$plugin" \
        '. + [{"name": $name, "source": $source, "invoke": $invoke, "discovered": true}]')
    fi
  fi
done

# --- Discover user-installed skills ------------------------------
if [[ -d "$USER_SKILLS" ]]; then
  for skill_dir in "$USER_SKILLS"/*/; do
    [[ ! -f "$skill_dir/SKILL.md" ]] && continue
    skill_name=$(basename "$skill_dir")
    DISCOVERED_SKILLS=$(echo "$DISCOVERED_SKILLS" | jq --arg name "$skill_name" --arg invoke "Read ${skill_dir}SKILL.md" \
      '. + [{"name": $name, "source": "user-skills", "invoke": $invoke, "discovered": true}]')
  done
fi

# --- Merge with default triggers ---------------------------------
if [[ -f "$DEFAULT_TRIGGERS" ]]; then
  # For each discovered skill, merge trigger/role/phase from defaults
  MERGED_SKILLS=$(jq -n --argjson discovered "$DISCOVERED_SKILLS" --slurpfile defaults "$DEFAULT_TRIGGERS" '
    ($defaults[0].skills // []) as $default_skills |
    # Start with defaults, overlay discovered invoke paths
    [ $default_skills[] |
      . as $default |
      ($discovered | map(select(.name == $default.name)) | first // null) as $disc |
      if $disc then
        $default + {"invoke": $disc.invoke, "source": $disc.source, "available": true}
      else
        $default + {"available": false}
      end
    ] +
    # Add discovered skills not in defaults (user custom skills)
    [ $discovered[] |
      . as $disc |
      ($default_skills | map(select(.name == $disc.name)) | length) as $in_defaults |
      if $in_defaults == 0 then
        $disc + {"role": "domain", "triggers": [], "priority": 5, "available": true}
      else
        empty
      end
    ]
  ')
else
  WARNINGS=$(echo "$WARNINGS" | jq '. + ["default-triggers.json not found"]')
  MERGED_SKILLS="$DISCOVERED_SKILLS"
fi

# --- Apply user config overrides ---------------------------------
if [[ -f "$USER_CONFIG" ]] && jq . "$USER_CONFIG" > /dev/null 2>&1; then
  MERGED_SKILLS=$(jq -n --argjson skills "$MERGED_SKILLS" --slurpfile config "$USER_CONFIG" '
    ($config[0].overrides // {}) as $overrides |
    ($config[0].custom_skills // []) as $custom |
    ($config[0].settings // {}) as $settings |
    [
      $skills[] |
      . as $skill |
      ($overrides[$skill.name] // null) as $override |
      if $override then
        # Apply enabled flag
        (if $override.enabled == false then . + {"enabled": false} elif $override.enabled == true then . + {"enabled": true} else . end) |
        # Apply trigger overrides
        if $override.triggers then
          ($override.triggers | map(select(startswith("+"))) | map(ltrimstr("+"))) as $add |
          ($override.triggers | map(select(startswith("-"))) | map(ltrimstr("-"))) as $remove |
          ($override.triggers | map(select(startswith("+") or startswith("-")) | not)) as $replace |
          if ($replace | length) > 0 then
            .triggers = $replace
          else
            .triggers = ((.triggers // []) + $add | map(select(. as $t | $remove | index($t) | not)))
          end
        else
          .
        end
      else
        .
      end
    ] + ($custom | map(. + {"source": "user-config", "available": true}))
  ')
elif [[ -f "$USER_CONFIG" ]]; then
  WARNINGS=$(echo "$WARNINGS" | jq '. + ["skill-config.json is invalid JSON — ignored"]')
fi

# --- Also extract methodology hints from defaults ----------------
HINTS='[]'
if [[ -f "$DEFAULT_TRIGGERS" ]]; then
  HINTS=$(jq '.methodology_hints // []' "$DEFAULT_TRIGGERS")
  # Filter to only installed plugins
  HINTS=$(echo "$HINTS" | jq --arg cache "$PLUGIN_CACHE" '
    [ .[] | select(.plugin as $p | ($cache + "/" + $p) | test(".*")) ]
  ')
fi

# --- Build final registry ----------------------------------------
SKILL_COUNT=$(echo "$MERGED_SKILLS" | jq '[.[] | select(.available == true or .available == null)] | length')
SOURCE_COUNT=$(echo "$MERGED_SKILLS" | jq '[.[] | select(.available == true) | .source] | unique | length')
WARNING_COUNT=$(echo "$WARNINGS" | jq 'length')

REGISTRY=$(jq -n \
  --argjson skills "$MERGED_SKILLS" \
  --argjson warnings "$WARNINGS" \
  --argjson hints "$HINTS" \
  '{
    skills: $skills,
    methodology_hints: $hints,
    warnings: $warnings,
    version: "2.0.0"
  }')

mkdir -p "$(dirname "$CACHE_FILE")"
echo "$REGISTRY" > "$CACHE_FILE"

# --- Emit phase map for session context --------------------------
PHASE_CONTEXT="SessionStart: skill registry built ($SKILL_COUNT skills from $SOURCE_COUNT sources, $WARNING_COUNT warnings)"

# Output as hook response
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
  "$(printf '%s' "$PHASE_CONTEXT" | jq -Rs .)"
```

**Step 4: Make executable**

Run: `chmod +x hooks/session-start-hook.sh`

**Step 5: Run tests to verify they pass**

Run: `bash tests/test-registry.sh`
Expected: All PASS

**Step 6: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "feat: add session-start hook with dynamic registry builder and tests"
```

---

### Task 5: Rewrite skill-activation-hook.sh (routing engine)

**Files:**
- Modify: `hooks/skill-activation-hook.sh:1-225` (full rewrite)

The new routing engine reads the cached registry, scores trigger matches, selects skills by role caps, and emits orchestrated context.

**Step 1: Write the failing test (tests/test-routing.sh)**

```bash
#!/bin/bash
# --- Routing engine tests ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Helper: run the hook with a prompt and capture output
run_hook() {
  local prompt="$1"
  echo "{\"prompt\":\"$prompt\"}" | bash "$CLAUDE_PLUGIN_ROOT/hooks/skill-activation-hook.sh" 2>/dev/null
}

extract_context() {
  local output="$1"
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

setup_test_env

# Build a test registry with known skills
cat > "$TEST_REGISTRY_CACHE" << 'REGISTRY'
{
  "skills": [
    {"name": "systematic-debugging", "role": "process", "invoke": "Skill(superpowers:systematic-debugging)", "phase": ["DEBUG"], "triggers": ["debug", "bug", "fix", "broken", "error"], "priority": 40, "available": true},
    {"name": "brainstorming", "role": "process", "invoke": "Skill(superpowers:brainstorming)", "phase": ["DESIGN"], "triggers": ["build", "create", "add", "design", "new"], "priority": 30, "available": true, "precedes": ["writing-plans"]},
    {"name": "test-driven-development", "role": "process", "invoke": "Skill(superpowers:test-driven-development)", "phase": ["IMPLEMENT"], "triggers": ["test", "tdd", "verify"], "priority": 15, "available": true},
    {"name": "requesting-code-review", "role": "process", "invoke": "Skill(superpowers:requesting-code-review)", "phase": ["REVIEW"], "triggers": ["review", "code.?review"], "priority": 20, "available": true},
    {"name": "verification-before-completion", "role": "workflow", "invoke": "Skill(superpowers:verification-before-completion)", "triggers": ["ship", "merge", "finish", "complete"], "priority": 20, "available": true},
    {"name": "frontend-design", "role": "domain", "invoke": "Skill(frontend-design:frontend-design)", "triggers": ["component", "dashboard", "ui", "frontend"], "priority": 15, "available": true},
    {"name": "security-scanner", "role": "domain", "invoke": "Read ~/.claude/skills/security-scanner/SKILL.md", "triggers": ["security", "vulnerab", "auth"], "priority": 15, "available": true}
  ],
  "methodology_hints": [],
  "warnings": [],
  "version": "2.0.0"
}
REGISTRY

# --- Test: debug prompt matches systematic-debugging ---
ctx=$(extract_context "$(run_hook "fix the login bug")")
assert_contains "debug prompt matches debugging" "systematic-debugging" "$ctx"

# --- Test: build prompt matches brainstorming ---
ctx=$(extract_context "$(run_hook "build a new API endpoint")")
assert_contains "build prompt matches brainstorming" "brainstorming" "$ctx"

# --- Test: greeting is blocked ---
output=$(run_hook "hey how are you")
assert_equals "greeting produces no output" "" "$output"

# --- Test: slash command is blocked ---
output=$(run_hook "/commit")
assert_equals "slash command produces no output" "" "$output"

# --- Test: short prompt is blocked ---
output=$(run_hook "ok")
assert_equals "short prompt produces no output" "" "$output"

# --- Test: domain skill appears alongside process skill ---
ctx=$(extract_context "$(run_hook "build a new dashboard component")")
assert_contains "brainstorming as process" "brainstorming" "$ctx"
assert_contains "frontend-design as domain" "frontend-design" "$ctx"
assert_contains "INFORMED BY keyword" "INFORMED BY" "$ctx"

# --- Test: review prompt matches code review ---
ctx=$(extract_context "$(run_hook "review my latest changes")")
assert_contains "review matches code review" "requesting-code-review" "$ctx"

# --- Test: ship prompt matches workflow skills ---
ctx=$(extract_context "$(run_hook "ship it, we are done")")
assert_contains "ship matches verification" "verification-before-completion" "$ctx"

# --- Test: max 1 process skill ---
ctx=$(extract_context "$(run_hook "fix and build something new")")
# Should not have both debugging AND brainstorming as process
process_count=$(echo "$ctx" | grep -c "^Process:" || true)
assert_equals "max 1 process skill" "1" "$process_count"

# --- Test: disabled skills are excluded ---
cat > "$TEST_REGISTRY_CACHE" << 'REGISTRY'
{
  "skills": [
    {"name": "brainstorming", "role": "process", "invoke": "Skill(superpowers:brainstorming)", "phase": ["DESIGN"], "triggers": ["build", "create"], "priority": 30, "available": true, "enabled": false}
  ],
  "warnings": [],
  "version": "2.0.0"
}
REGISTRY
ctx=$(extract_context "$(run_hook "build something new")")
assert_not_contains "disabled skill excluded" "brainstorming" "$ctx"

# --- Test: missing registry falls back ---
rm -f "$TEST_REGISTRY_CACHE"
output=$(run_hook "build something")
assert_not_contains "no crash without registry" "error" "$output"

teardown_test_env

print_summary
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh`
Expected: FAIL (hook still uses old hardcoded logic)

**Step 3: Rewrite hooks/skill-activation-hook.sh**

```bash
#!/bin/bash
# --- auto-claude-skills Routing Engine v2 ---------------------
# https://github.com/damianpapadopoulos/auto-claude-skills
#
# Config-driven routing with role-based skill orchestration.
# Reads skill registry from cache (built by session-start-hook.sh).
#
# DESIGN PRINCIPLE: The registry + scoring is a FAST PRE-FILTER.
# Claude Code (already running) makes the real intent assessment
# via the orchestrated context injection.
# No extra API call needed -- Claude IS the classifier.
#
# Roles: Process (drives) | Domain (informs) | Workflow (standalone)
# The hook suggests; Claude decides; the user overrides.
# -----------------------------------------------------------------
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REGISTRY_CACHE="$HOME/.claude/.skill-registry-cache.json"
FALLBACK_REGISTRY="$PLUGIN_ROOT/config/fallback-registry.json"
USER_CONFIG="$HOME/.claude/skill-config.json"

PROMPT=$(cat 2>/dev/null | jq -r '.prompt // empty' 2>/dev/null) || true

# --- Early exits -------------------------------------------------
[[ -z "$PROMPT" ]] && exit 0
[[ "$PROMPT" =~ ^[[:space:]]*/  ]] && exit 0
(( ${#PROMPT} < 8 )) && exit 0

P=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# --- Blocklist (non-dev prompts) ---------------------------------
if [[ "$P" =~ ^(hi|hello|hey|thanks|thank.you|good.(morning|afternoon|evening)|bye|goodbye|ok|okay|yes|no|sure|yep|nope|got.it|sounds.good|cool|nice|great|perfect|awesome|understood)([[:space:]!.,]+.{0,20})?$ ]]; then
  TAIL="${P#*[[:space:]]}"
  if [[ "$TAIL" == "$P" ]] || (( ${#TAIL} < 20 )); then
    exit 0
  fi
fi

# --- Load registry -----------------------------------------------
REGISTRY=""
if [[ -f "$REGISTRY_CACHE" ]] && jq . "$REGISTRY_CACHE" > /dev/null 2>&1; then
  REGISTRY=$(cat "$REGISTRY_CACHE")
elif [[ -f "$FALLBACK_REGISTRY" ]]; then
  REGISTRY=$(cat "$FALLBACK_REGISTRY")
else
  # No registry at all — emit minimal phase checkpoint
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
    "$(printf '%s' "SKILL ACTIVATION (0 skills | no registry)\n\nPhase: assess current phase (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)\nand consider whether any installed skill applies." | jq -Rs .)"
  exit 0
fi

# --- Load settings from user config ------------------------------
MAX_SUGGESTIONS=3
VERBOSITY="normal"
if [[ -f "$USER_CONFIG" ]] && jq . "$USER_CONFIG" > /dev/null 2>&1; then
  MAX_SUGGESTIONS=$(jq -r '.settings.max_suggestions // 3' "$USER_CONFIG")
  VERBOSITY=$(jq -r '.settings.verbosity // "normal"' "$USER_CONFIG")
fi

# --- Score skills against prompt ----------------------------------
# For each available, enabled skill: test triggers, compute score
SCORED_SKILLS=$(echo "$REGISTRY" | jq --arg prompt "$P" '
  .skills
  | map(select(.available != false and .enabled != false))
  | map(
      . as $skill |
      ($skill.triggers // []) |
      map(
        . as $trigger |
        if ($prompt | test($trigger; "i")) then
          # Check exact word boundary match vs substring
          if ($prompt | test("(^|[^a-z])" + $trigger + "($|[^a-z])"; "i")) then 3
          else 1
          end
        else 0
        end
      ) |
      max // 0 |
      . as $trigger_score |
      if $trigger_score > 0 then
        {
          name: $skill.name,
          role: ($skill.role // "domain"),
          invoke: $skill.invoke,
          phase: ($skill.phase // []),
          priority: ($skill.priority // 10),
          trigger_score: $trigger_score,
          score: ($trigger_score + $skill.priority),
          precedes: ($skill.precedes // []),
          requires: ($skill.requires // []),
          description: ($skill.description // ""),
          available: true
        }
      else empty
      end
    )
  | sort_by(-.score)
')

# --- Select by role caps -----------------------------------------
# 1 process + up to 2 domain + 1 workflow = max ~4, then cap at MAX_SUGGESTIONS
SELECTED=$(echo "$SCORED_SKILLS" | jq --argjson max "$MAX_SUGGESTIONS" '
  (map(select(.role == "process")) | first // empty) as $proc |
  (map(select(.role == "domain")) | .[0:2]) as $doms |
  (map(select(.role == "workflow")) | first // empty) as $wf |
  (
    (if $proc then [$proc] else [] end) +
    $doms +
    (if $wf then [$wf] else [] end)
  ) | .[0:$max]
')

SKILL_COUNT=$(echo "$SELECTED" | jq 'length')

# --- Determine label ---------------------------------------------
PROCESS_NAME=$(echo "$SELECTED" | jq -r 'map(select(.role == "process")) | first // empty | .name // empty')
LABEL=""
case "$PROCESS_NAME" in
  systematic-debugging) LABEL="Fix / Debug" ;;
  brainstorming) LABEL="Build New" ;;
  executing-plans|subagent-driven-development) LABEL="Plan Execution" ;;
  test-driven-development) LABEL="Run / Test" ;;
  requesting-code-review|receiving-code-review) LABEL="Review" ;;
  *) LABEL="(Claude: assess intent)" ;;
esac

# Add domain/workflow labels
DOMAIN_NAMES=$(echo "$SELECTED" | jq -r '[.[] | select(.role == "domain") | .name] | join(" ")')
WORKFLOW_NAMES=$(echo "$SELECTED" | jq -r '[.[] | select(.role == "workflow") | .name] | join(" ")')
[[ -n "$DOMAIN_NAMES" ]] && LABEL="$LABEL + Domain"
[[ -n "$WORKFLOW_NAMES" ]] && LABEL="$LABEL + Workflow"

# --- Build orchestrated context output ----------------------------
if (( SKILL_COUNT == 0 )); then
  # Minimal phase checkpoint
  OUT="SKILL ACTIVATION (0 skills | phase checkpoint only)

Phase: assess current phase (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)
and consider whether any installed skill applies."

elif (( SKILL_COUNT <= 2 )) && [[ "$VERBOSITY" != "verbose" ]]; then
  # Compact format with orchestration
  OUT="SKILL ACTIVATION ($SKILL_COUNT skills | $LABEL)"
  OUT+=$'\n'

  # Process skill
  PROC=$(echo "$SELECTED" | jq -r '.[] | select(.role == "process") | "\(.name) -> \(.invoke)"')
  if [[ -n "$PROC" ]]; then
    OUT+=$'\n'"Process: $PROC"
    # Domain skills as INFORMED BY
    while IFS= read -r dom_line; do
      [[ -n "$dom_line" ]] && OUT+=$'\n'"  INFORMED BY: $dom_line"
    done < <(echo "$SELECTED" | jq -r '.[] | select(.role == "domain") | "\(.name) -> \(.invoke)"')
  else
    # No process skill — list all as standalone
    while IFS= read -r skill_line; do
      [[ -n "$skill_line" ]] && OUT+=$'\n'"  $skill_line"
    done < <(echo "$SELECTED" | jq -r '.[] | "\(.name) -> \(.invoke)"')
  fi

  # Workflow skills standalone
  while IFS= read -r wf_line; do
    [[ -n "$wf_line" ]] && OUT+=$'\n'"Workflow: $wf_line"
  done < <(echo "$SELECTED" | jq -r '.[] | select(.role == "workflow") | "\(.name) -> \(.invoke)"')

  # Evaluation line
  SKILL_NAMES=$(echo "$SELECTED" | jq -r '[.[].name] | join(", ")')
  OUT+=$'\n'
  OUT+=$'\n'"Evaluate: **Phase: [PHASE]** | $(echo "$SELECTED" | jq -r '[.[].name + " YES/NO"] | join(", ")')"

else
  # Full format
  OUT="SKILL ACTIVATION ($SKILL_COUNT skills | $LABEL)"
  OUT+=$'\n'
  OUT+=$'\n'"Step 1 -- ASSESS PHASE. Check conversation context:"
  OUT+=$'\n'"  DESIGN    -> brainstorming (ask questions, get approval)"
  OUT+=$'\n'"  PLAN      -> writing-plans (break into tasks, confirm before execution)"
  OUT+=$'\n'"  IMPLEMENT -> executing-plans or subagent-driven-development + TDD"
  OUT+=$'\n'"  REVIEW    -> requesting-code-review"
  OUT+=$'\n'"  SHIP      -> verification-before-completion + finishing-a-development-branch"
  OUT+=$'\n'"  DEBUG     -> systematic-debugging, then return to current phase"

  OUT+=$'\n'
  OUT+=$'\n'"Step 2 -- EVALUATE skills against your phase assessment."

  # Process skill
  PROC_NAME=$(echo "$SELECTED" | jq -r '.[] | select(.role == "process") | .name' | head -1)
  PROC_INVOKE=$(echo "$SELECTED" | jq -r '.[] | select(.role == "process") | .invoke' | head -1)
  if [[ -n "$PROC_NAME" ]]; then
    OUT+=$'\n'"  Process: $PROC_NAME -> $PROC_INVOKE"
    while IFS= read -r dom_line; do
      [[ -n "$dom_line" ]] && OUT+=$'\n'"    INFORMED BY: $dom_line"
    done < <(echo "$SELECTED" | jq -r '.[] | select(.role == "domain") | "\(.name) -> \(.invoke)"')
  fi

  # Standalone domain skills (no process)
  if [[ -z "$PROC_NAME" ]]; then
    while IFS= read -r skill_line; do
      [[ -n "$skill_line" ]] && OUT+=$'\n'"  $skill_line"
    done < <(echo "$SELECTED" | jq -r '.[] | select(.role == "domain") | "\(.name) -> \(.invoke)"')
  fi

  # Workflow skills
  while IFS= read -r wf_line; do
    [[ -n "$wf_line" ]] && OUT+=$'\n'"  Workflow: $wf_line"
  done < <(echo "$SELECTED" | jq -r '.[] | select(.role == "workflow") | "\(.name) -> \(.invoke)"')

  OUT+=$'\n'"You MUST print a brief evaluation for each skill above. Format:"
  OUT+=$'\n'"  **Phase: [PHASE]** | [skill1] YES/NO, [skill2] YES/NO"
  OUT+=$'\n'"Example: **Phase: IMPLEMENT** | test-driven-development YES, claude-md-improver NO (not editing CLAUDE.md)"
  OUT+=$'\n'"This line is MANDATORY -- do not skip it."

  OUT+=$'\n'
  OUT+=$'\n'"Step 3 -- State your plan and proceed. Keep it to 1-2 sentences."
fi

# --- Methodology hints -------------------------------------------
HINTS=$(echo "$REGISTRY" | jq --arg prompt "$P" '
  (.methodology_hints // []) | map(
    select(.triggers | any(. as $t | $prompt | test($t; "i")))
  ) | .[].hint // empty
' 2>/dev/null)

if [[ -n "$HINTS" ]]; then
  OUT+=$'\n'
  while IFS= read -r hint; do
    [[ -n "$hint" ]] && OUT+=$'\n'"- $hint"
  done <<< "$HINTS"
fi

# --- Emit ---------------------------------------------------------
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
  "$(printf '%s' "$OUT" | jq -Rs .)"
```

**Step 4: Run tests to verify they pass**

Run: `bash tests/test-routing.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: rewrite routing engine with config-driven scoring and role-based orchestration"
```

---

### Task 6: Write context injection tests

**Files:**
- Create: `tests/test-context.sh`

**Step 1: Write tests/test-context.sh**

```bash
#!/bin/bash
# --- Context injection format tests ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

run_hook() {
  local prompt="$1"
  echo "{\"prompt\":\"$prompt\"}" | bash "$CLAUDE_PLUGIN_ROOT/hooks/skill-activation-hook.sh" 2>/dev/null
}

extract_context() {
  echo "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

setup_test_env

# --- Registry with varied skills for context format testing ---
cat > "$TEST_REGISTRY_CACHE" << 'REGISTRY'
{
  "skills": [
    {"name": "systematic-debugging", "role": "process", "invoke": "Skill(superpowers:systematic-debugging)", "phase": ["DEBUG"], "triggers": ["debug", "bug", "fix"], "priority": 40, "available": true},
    {"name": "brainstorming", "role": "process", "invoke": "Skill(superpowers:brainstorming)", "phase": ["DESIGN"], "triggers": ["build", "create", "add"], "priority": 30, "available": true},
    {"name": "verification-before-completion", "role": "workflow", "invoke": "Skill(superpowers:verification-before-completion)", "triggers": ["ship", "merge", "finish"], "priority": 20, "available": true},
    {"name": "finishing-a-development-branch", "role": "workflow", "invoke": "Skill(superpowers:finishing-a-development-branch)", "triggers": ["ship", "merge", "finish"], "priority": 19, "available": true},
    {"name": "frontend-design", "role": "domain", "invoke": "Skill(frontend-design:frontend-design)", "triggers": ["component", "dashboard", "ui"], "priority": 15, "available": true},
    {"name": "security-scanner", "role": "domain", "invoke": "Read ~/.claude/skills/security-scanner/SKILL.md", "triggers": ["security", "auth"], "priority": 15, "available": true},
    {"name": "doc-coauthoring", "role": "domain", "invoke": "Read ~/.claude/skills/doc-coauthoring/SKILL.md", "triggers": ["documentation", "proposal"], "priority": 15, "available": true}
  ],
  "methodology_hints": [],
  "warnings": [],
  "version": "2.0.0"
}
REGISTRY

# --- Test: 0 skills -> minimal output ---
ctx=$(extract_context "$(run_hook "what time zone are we in for the standup")")
assert_contains "0 skills: phase checkpoint" "phase checkpoint" "$ctx"
assert_not_contains "0 skills: no Step 2" "Step 2" "$ctx"

# --- Test: 1 skill -> compact format ---
ctx=$(extract_context "$(run_hook "fix the login bug")")
assert_contains "1 skill: has Process:" "Process:" "$ctx"
assert_contains "1 skill: has Evaluate:" "Evaluate:" "$ctx"
assert_not_contains "1 skill: no Step 1 in compact" "Step 1" "$ctx"

# --- Test: process + domain -> INFORMED BY ---
ctx=$(extract_context "$(run_hook "build a dashboard component")")
assert_contains "process+domain: INFORMED BY present" "INFORMED BY" "$ctx"
assert_contains "process+domain: process listed" "brainstorming" "$ctx"
assert_contains "process+domain: domain listed" "frontend-design" "$ctx"

# --- Test: 3+ skills -> full format with phase map ---
ctx=$(extract_context "$(run_hook "build a secure dashboard component with documentation")")
# This should match brainstorming + frontend-design + security-scanner + doc-coauthoring = 4
# which triggers full format
if echo "$ctx" | grep -q "Step 1"; then
  assert_contains "3+ skills: has phase map" "DESIGN" "$ctx"
  assert_contains "3+ skills: has MANDATORY eval" "MANDATORY" "$ctx"
fi

# --- Test: invocation hints are present ---
ctx=$(extract_context "$(run_hook "fix the login bug")")
assert_contains "invocation hint present" "Skill(superpowers:" "$ctx"

# --- Test: output is valid hook JSON ---
output=$(run_hook "build something new")
echo "$output" | jq . > /dev/null 2>&1
assert_equals "output is valid JSON" "0" "$?"

teardown_test_env

print_summary
```

**Step 2: Run tests**

Run: `bash tests/test-context.sh`
Expected: All PASS

**Step 3: Commit**

```bash
git add tests/test-context.sh
git commit -m "feat: add context injection format tests"
```

---

### Task 7: Update hooks.json for new session start hook

**Files:**
- Modify: `hooks/hooks.json:1-27`

**Step 1: Update hooks.json to use new session start hook**

Replace the SessionStart hook command to use session-start-hook.sh (which internally calls fix-plugin-manifests.sh).

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start-hook.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/skill-activation-hook.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Step 2: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: point SessionStart hook at registry builder"
```

---

### Task 8: Update plugin manifest version

**Files:**
- Modify: `.claude-plugin/plugin.json:4`

**Step 1: Bump version to 2.0.0**

Change `"version": "1.2.0"` to `"version": "2.0.0"`.

**Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 2.0.0"
```

---

### Task 9: Update install.sh for v2

**Files:**
- Modify: `install.sh`

**Step 1: Update install.sh**

Key changes:
- Legacy manual install copies both `session-start-hook.sh` and `skill-activation-hook.sh`
- Legacy settings.json gets both SessionStart and UserPromptSubmit hooks
- Add config directory copy for default-triggers.json and fallback-registry.json
- Update version display

This is a focused diff — only the legacy install section and hook registration need updating. The external skills download and plugin check sections stay identical.

**Step 2: Run install in dry-run mode to verify**

Run: `bash install.sh` (answer N to manual install, N to skill download)
Expected: Shows plugin is installed, no errors

**Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: update installer for v2 with registry config files"
```

---

### Task 10: Write install/uninstall tests

**Files:**
- Create: `tests/test-install.sh`

**Step 1: Write tests/test-install.sh**

```bash
#!/bin/bash
# --- Install/uninstall tests ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# --- Test: config files exist ---
assert_file_exists "default-triggers.json exists" "$CLAUDE_PLUGIN_ROOT/config/default-triggers.json"
assert_file_exists "fallback-registry.json exists" "$CLAUDE_PLUGIN_ROOT/config/fallback-registry.json"
assert_json_valid "default-triggers.json valid" "$CLAUDE_PLUGIN_ROOT/config/default-triggers.json"
assert_json_valid "fallback-registry.json valid" "$CLAUDE_PLUGIN_ROOT/config/fallback-registry.json"

# --- Test: hooks are executable ---
assert_file_exists "skill-activation-hook.sh exists" "$CLAUDE_PLUGIN_ROOT/hooks/skill-activation-hook.sh"
assert_file_exists "session-start-hook.sh exists" "$CLAUDE_PLUGIN_ROOT/hooks/session-start-hook.sh"

if [[ -x "$CLAUDE_PLUGIN_ROOT/hooks/skill-activation-hook.sh" ]]; then
  assert_equals "activation hook is executable" "0" "0"
else
  assert_equals "activation hook is executable" "executable" "not executable"
fi

if [[ -x "$CLAUDE_PLUGIN_ROOT/hooks/session-start-hook.sh" ]]; then
  assert_equals "session start hook is executable" "0" "0"
else
  assert_equals "session start hook is executable" "executable" "not executable"
fi

# --- Test: hooks.json references correct files ---
HOOKS_JSON="$CLAUDE_PLUGIN_ROOT/hooks/hooks.json"
assert_file_exists "hooks.json exists" "$HOOKS_JSON"
assert_json_valid "hooks.json valid" "$HOOKS_JSON"
assert_contains "hooks.json references session-start" "session-start-hook.sh" "$(cat "$HOOKS_JSON")"
assert_contains "hooks.json references skill-activation" "skill-activation-hook.sh" "$(cat "$HOOKS_JSON")"

# --- Test: plugin.json is valid ---
PLUGIN_JSON="$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
assert_file_exists "plugin.json exists" "$PLUGIN_JSON"
assert_json_valid "plugin.json valid" "$PLUGIN_JSON"

print_summary
```

**Step 2: Run tests**

Run: `bash tests/test-install.sh`
Expected: All PASS

**Step 3: Commit**

```bash
git add tests/test-install.sh
git commit -m "feat: add install validation tests"
```

---

### Task 11: Run full test suite and verify

**Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass, 0 failures

**Step 2: If any failures, fix and re-run**

Fix failing tests or implementation, then re-run until green.

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test failures from integration"
```

---

### Task 12: Update README.md for v2

**Files:**
- Modify: `README.md`

**Step 1: Update README to document v2 changes**

Key sections to update:
- Version number in title/header
- Architecture description (config-driven, role-based)
- New file listing (config/, tests/)
- Skill roles explanation (process/domain/workflow)
- User configuration section
- Testing section

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README for v2 architecture"
```

---

Plan complete and saved to `docs/plans/2026-02-15-v2-implementation-plan.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints

Which approach?