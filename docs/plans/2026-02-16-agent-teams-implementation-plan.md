# Agent Teams Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add phase-aware agent team support to auto-claude-skills with cozempic auto-install, conditional heartbeats, and three new skills (design-debate, agent-team-execution, agent-team-review).

**Architecture:** Hybrid approach — sequential phases use existing skills, IMPLEMENT and REVIEW phases use agent teams for parallel work. DESIGN phase can escalate to a MAD debate team when brainstorming detects complexity. Cozempic auto-installs at SessionStart to guard team sessions.

**Tech Stack:** Bash 3.2 (hooks), Markdown (skills), JSON (registry config), jq (task inspection)

---

### Task 1: Create teammate-idle-guard.sh

**Files:**
- Create: `hooks/teammate-idle-guard.sh`
- Test: `tests/test-routing.sh` (add heartbeat test at end)

**Step 1: Write the hook script**

Create `hooks/teammate-idle-guard.sh`:

```bash
#!/bin/bash
# teammate-idle-guard.sh — Conditional heartbeat for agent team teammates
# Checks if the idle teammate has unfinished tasks before nudging.
# Exit 0 = allow idle. Exit 2 = nudge (stderr fed back to teammate).

INPUT=$(cat)
TEAMMATE=$(printf '%s' "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null)
TEAM=$(printf '%s' "$INPUT" | jq -r '.team_name // empty' 2>/dev/null)

# No teammate info = allow idle
[ -z "$TEAMMATE" ] || [ -z "$TEAM" ] && exit 0

TASKS_DIR="${HOME}/.claude/tasks/${TEAM}"

# No task directory = no team tasks = allow idle
[ ! -d "$TASKS_DIR" ] && exit 0

# Check if this teammate owns any in_progress tasks
UNFINISHED=""
for task_file in "${TASKS_DIR}"/*.json; do
    [ -f "$task_file" ] || continue
    MATCH=$(jq -r --arg owner "$TEAMMATE" \
        'select(.owner == $owner and .status == "in_progress") | .subject' \
        "$task_file" 2>/dev/null)
    if [ -n "$MATCH" ]; then
        [ -n "$UNFINISHED" ] && UNFINISHED="${UNFINISHED}, "
        UNFINISHED="${UNFINISHED}${MATCH}"
    fi
done

if [ -n "$UNFINISHED" ]; then
    echo "You have unfinished tasks: ${UNFINISHED}. Continue working or report your blocker to the lead via SendMessage." >&2
    exit 2
fi

exit 0
```

**Step 2: Make it executable**

Run: `chmod +x hooks/teammate-idle-guard.sh`

**Step 3: Write tests for the heartbeat hook**

Append to `tests/test-routing.sh` a new test function `test_teammate_idle_guard`:

```bash
test_teammate_idle_guard() {
    echo "-- test: teammate idle guard --"
    setup_test_env

    local guard="${PROJECT_ROOT}/hooks/teammate-idle-guard.sh"

    # Test 1: No tasks dir = exit 0
    local exit_code
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    exit_code=$?
    assert_equals "no tasks dir allows idle" "0" "$exit_code"

    # Test 2: Has in_progress task = exit 2
    mkdir -p "${HOME}/.claude/tasks/test-team"
    printf '{"subject":"Fix auth","status":"in_progress","owner":"worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    exit_code=$?
    assert_equals "unfinished task blocks idle" "2" "$exit_code"

    # Test 3: All tasks completed = exit 0
    printf '{"subject":"Fix auth","status":"completed","owner":"worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    exit_code=$?
    assert_equals "completed tasks allow idle" "0" "$exit_code"

    # Test 4: Different owner's in_progress task = exit 0
    printf '{"subject":"Fix auth","status":"in_progress","owner":"other-worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    exit_code=$?
    assert_equals "other owner tasks allow idle" "0" "$exit_code"

    teardown_test_env
}
```

**Step 4: Run the tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass including 4 new heartbeat tests.

**Step 5: Commit**

```bash
git add hooks/teammate-idle-guard.sh tests/test-routing.sh
git commit -m "feat: add conditional teammate-idle-guard hook"
```

---

### Task 2: Add cozempic auto-install to session-start-hook.sh

**Files:**
- Modify: `hooks/session-start-hook.sh` (add step between Step 1 and Step 2)

**Step 1: Add cozempic check after fix-plugin-manifests**

Insert after line 24 (after the fix-plugin-manifests block, before the jq check):

```bash
# -----------------------------------------------------------------
# Step 1b: Ensure cozempic is available (context protection)
# -----------------------------------------------------------------
if ! command -v cozempic >/dev/null 2>&1; then
    pip install cozempic >/dev/null 2>&1 && \
        cozempic init >/dev/null 2>&1 || true
fi
```

**Step 2: Add TeammateIdle hook wiring after cozempic check**

Insert after the cozempic block:

```bash
# -----------------------------------------------------------------
# Step 1c: Wire TeammateIdle hook if not already present
# -----------------------------------------------------------------
GUARD_SCRIPT="${PLUGIN_ROOT}/hooks/teammate-idle-guard.sh"
PROJECT_SETTINGS="${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json"
if [ -f "${GUARD_SCRIPT}" ] && [ -f "${PROJECT_SETTINGS}" ]; then
    HAS_IDLE_HOOK=$(jq '.hooks.TeammateIdle // empty' "${PROJECT_SETTINGS}" 2>/dev/null)
    if [ -z "${HAS_IDLE_HOOK}" ] || [ "${HAS_IDLE_HOOK}" = "null" ]; then
        jq --arg cmd "${GUARD_SCRIPT}" \
            '.hooks.TeammateIdle = [{"matcher":"","hooks":[{"type":"command","command":$cmd}]}]' \
            "${PROJECT_SETTINGS}" > "${PROJECT_SETTINGS}.tmp" && \
            mv "${PROJECT_SETTINGS}.tmp" "${PROJECT_SETTINGS}" 2>/dev/null || true
    fi
fi
```

**Step 3: Run existing tests to verify no regressions**

Run: `bash tests/run-tests.sh`
Expected: All 82+ existing tests pass.

**Step 4: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: auto-install cozempic and wire TeammateIdle hook at SessionStart"
```

---

### Task 3: Add new skill entries to default-triggers.json

**Files:**
- Modify: `config/default-triggers.json`

**Step 1: Update existing agent-team-execution stub**

Change `"enabled": false` to `"enabled": true` and update triggers for the agent-team-execution entry (currently at ~line 242).

Replace triggers with:
```json
"triggers": [
    "(agent.team|team.execute|parallel.team|swarm|execute.*plan|run.the.plan|implement.the.plan|implement.*(rest|remaining)|continue|follow.the.plan|pick.up|resume|next.task|next.step|carry.on|keep.going|where.were.we|what.s.next)"
]
```

Set `"enabled": true` and remove the `_deferred` field.

**Step 2: Add agent-team-review entry**

Add after agent-team-execution:

```json
{
    "name": "agent-team-review",
    "role": "workflow",
    "phase": "REVIEW",
    "triggers": [
        "(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|tech.?debt|(^|[^a-z])pr($|[^a-z]))"
    ],
    "trigger_mode": "regex",
    "priority": 17,
    "precedes": [],
    "requires": [],
    "description": "Multi-perspective parallel code review with specialist reviewers (security, quality, spec compliance)."
}
```

**Step 3: Add design-debate entry**

Add after agent-team-review:

```json
{
    "name": "design-debate",
    "role": "domain",
    "phase": "DESIGN",
    "triggers": [
        "(build|create|implement|develop|scaffold|brainstorm|design|architect|strateg|scope|outline|approach|add|write|make|generate|set.?up|install|configure|integrate|extend|new|start)"
    ],
    "trigger_mode": "regex",
    "priority": 14,
    "precedes": [],
    "requires": [],
    "description": "Multi-Agent Debate for complex designs. Spawns architect, critic, and pragmatist for collaborative design exploration."
}
```

**Step 4: Validate JSON**

Run: `jq empty config/default-triggers.json && echo "valid"`
Expected: `valid`

**Step 5: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: add agent-team-review and design-debate trigger entries"
```

---

### Task 4: Create design-debate skill

**Files:**
- Create: `~/.claude/skills/design-debate/SKILL.md`

**Step 1: Write the skill file**

Create `~/.claude/skills/design-debate/SKILL.md` with:
- Frontmatter: name, description
- Escalation triggers (complexity signals)
- Team composition (architect, critic, pragmatist)
- Debate protocol (2 rounds max, opt-in)
- JSON communication contract for design_position messages
- Convergence rules and design doc output format
- User approval gate before TeamDelete

The skill must:
- Ask user before escalating ("Want me to run a design debate?")
- Use TeamCreate("design-debate")
- Spawn 3 teammates with persona prompts
- Cap at 2 debate rounds
- Synthesize into design doc at `docs/plans/YYYY-MM-DD-*-design.md`
- TeamDelete when done, return to sequential flow

**Step 2: Verify skill is discoverable**

Start a new Claude Code session and check the registry:
Run: `jq '.skills[] | select(.name == "design-debate")' ~/.claude/.skill-registry-cache.json`
Expected: Entry with `available: true`, `enabled: true`

**Step 3: Commit**

```bash
git add ~/.claude/skills/design-debate/SKILL.md
git commit -m "feat: add design-debate skill for MAD pattern"
```

---

### Task 5: Create agent-team-execution skill

**Files:**
- Create: `~/.claude/skills/agent-team-execution/SKILL.md`

**Step 1: Write the skill file**

Create `~/.claude/skills/agent-team-execution/SKILL.md` with:
- Frontmatter: name, description
- Prerequisites: plan must exist, 3+ independent tasks
- File ownership analysis protocol
- File-disjoint grouping algorithm
- Specialist spawn template (context per specialist)
- Lead assigns tasks explicitly (no self-claim)
- JSON communication contract for task_status messages
- Monitoring protocol (TaskList polling, SendMessage for blockers)
- Completion criteria and TeamDelete
- Sizing rule: <3 tasks → fall back to single-agent executing-plans

The skill must:
- Read the plan from `docs/plans/*.md`
- Analyze tasks for file ownership overlap
- Group overlapping tasks under one specialist
- TeamCreate with descriptive name
- Spawn specialists with file boundaries in prompt
- Use delegate mode for the lead
- Monitor and reassign if blocked

**Step 2: Verify skill is discoverable**

Start a new session and check:
Run: `jq '.skills[] | select(.name == "agent-team-execution")' ~/.claude/.skill-registry-cache.json`
Expected: Entry with `available: true`, `enabled: true`

**Step 3: Commit**

```bash
git add ~/.claude/skills/agent-team-execution/SKILL.md
git commit -m "feat: add agent-team-execution skill for specialist delegation"
```

---

### Task 6: Create agent-team-review skill

**Files:**
- Create: `~/.claude/skills/agent-team-review/SKILL.md`

**Step 1: Write the skill file**

Create `~/.claude/skills/agent-team-review/SKILL.md` with:
- Frontmatter: name, description
- Prerequisites: implementation complete, 5+ files changed
- Reviewer team composition (security, quality, spec)
- Spawn template with review lens and context (diff, design doc)
- JSON communication contract for review_finding messages
- Lead synthesis protocol (group by severity, deduplicate)
- Review summary output schema
- Verdict routing: blocking → back to IMPLEMENT, clean → SHIP
- Sizing rule: <5 files → fall back to single-agent requesting-code-review

**Step 2: Verify skill is discoverable**

Start a new session and check:
Run: `jq '.skills[] | select(.name == "agent-team-review")' ~/.claude/.skill-registry-cache.json`
Expected: Entry with `available: true`, `enabled: true`

**Step 3: Commit**

```bash
git add ~/.claude/skills/agent-team-review/SKILL.md
git commit -m "feat: add agent-team-review skill for parallel review"
```

---

### Task 7: Add routing tests for new skills

**Files:**
- Modify: `tests/test-routing.sh` (add new skill entries to test registry, add test functions)

**Step 1: Add new skills to test registry**

In the `install_registry()` function, add entries for `agent-team-execution`, `agent-team-review`, and `design-debate` to the skills array. Follow existing pattern (name, role, phase, triggers, priority, invoke, available, enabled).

**Step 2: Write test functions**

```bash
test_agent_team_execution_matches() {
    echo "-- test: agent team execution matches plan prompts --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "let's use agent teams to execute the plan")"
    context="$(extract_context "$output")"
    assert_contains "agent team matches" "agent-team-execution" "$context"

    teardown_test_env
}

test_design_debate_as_domain() {
    echo "-- test: design-debate appears as INFORMED BY --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a new authentication system")"
    context="$(extract_context "$output")"
    # brainstorming is process (higher priority), design-debate is domain
    assert_contains "has brainstorming" "brainstorming" "$context"
    assert_contains "has INFORMED BY design-debate" "design-debate" "$context"

    teardown_test_env
}

test_agent_team_review_matches() {
    echo "-- test: agent team review matches review prompts --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "review the code changes for this PR")"
    context="$(extract_context "$output")"
    assert_contains "agent-team-review matches" "agent-team-review" "$context"

    teardown_test_env
}
```

**Step 3: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass including new routing tests.

**Step 4: Commit**

```bash
git add tests/test-routing.sh
git commit -m "test: add routing tests for agent team skills"
```

---

### Task 8: Add registry tests for new skill discovery

**Files:**
- Modify: `tests/test-registry.sh`

**Step 1: Write test for user skill discovery of agent team skills**

```bash
test_discovers_agent_team_skills() {
    echo "-- test: discovers agent team user skills --"
    setup_test_env

    # Create mock user skills
    mkdir -p "${HOME}/.claude/skills/agent-team-execution"
    echo "---\nname: agent-team-execution\n---" > \
        "${HOME}/.claude/skills/agent-team-execution/SKILL.md"
    mkdir -p "${HOME}/.claude/skills/agent-team-review"
    echo "---\nname: agent-team-review\n---" > \
        "${HOME}/.claude/skills/agent-team-review/SKILL.md"
    mkdir -p "${HOME}/.claude/skills/design-debate"
    echo "---\nname: design-debate\n---" > \
        "${HOME}/.claude/skills/design-debate/SKILL.md"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "$cache_file"
    assert_json_valid "cache file is valid JSON" "$cache_file"

    local ate_available
    ate_available=$(jq -r '.skills[] | select(.name == "agent-team-execution") | .available' "$cache_file")
    assert_equals "agent-team-execution available" "true" "$ate_available"

    local atr_available
    atr_available=$(jq -r '.skills[] | select(.name == "agent-team-review") | .available' "$cache_file")
    assert_equals "agent-team-review available" "true" "$atr_available"

    local dd_available
    dd_available=$(jq -r '.skills[] | select(.name == "design-debate") | .available' "$cache_file")
    assert_equals "design-debate available" "true" "$dd_available"

    teardown_test_env
}
```

**Step 2: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add tests/test-registry.sh
git commit -m "test: add registry discovery tests for agent team skills"
```

---

### Task 9: Update setup command and documentation

**Files:**
- Modify: `commands/setup.md`
- Modify: `docs/integrations/agent-teams-and-cozempic.md`
- Modify: `README.md`

**Step 1: Add cozempic to setup.md**

Add a new section at the top of setup.md (before external skills):

```markdown
### 0. Cozempic (context protection)

```bash
pip install cozempic
cozempic init
```

If pip is not available, skip this step. Cozempic provides optional context protection for long sessions and agent team workflows.
```

**Step 2: Update integration doc**

Update `docs/integrations/agent-teams-and-cozempic.md`:
- Change Path B status from "deferred" to "active"
- Add references to the three new skills
- Update the activation checklist (mark items as done)
- Add the TeammateIdle hook documentation

**Step 3: Update README companion tools section**

Update the "Agent teams (future)" section to "Agent teams (experimental)" and list the three new skills.

**Step 4: Commit**

```bash
git add commands/setup.md docs/integrations/agent-teams-and-cozempic.md README.md
git commit -m "docs: update setup, integration guide, and README for agent teams"
```

---

### Task 10: Final verification and push

**Files:**
- None (verification only)

**Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (original 82 + new tests).

**Step 2: Verify JSON validity**

Run: `jq empty config/default-triggers.json && echo "valid"`
Expected: `valid`

**Step 3: Verify skill files exist**

Run:
```bash
ls -la ~/.claude/skills/design-debate/SKILL.md
ls -la ~/.claude/skills/agent-team-execution/SKILL.md
ls -la ~/.claude/skills/agent-team-review/SKILL.md
```
Expected: All three files exist.

**Step 4: Verify cozempic is functional**

Run: `cozempic --version`
Expected: `cozempic 0.5.1` or later.

**Step 5: Push all commits**

Run: `git push origin main`
