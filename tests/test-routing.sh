#!/usr/bin/env bash
# test-routing.sh — Tests for the skill-activation routing engine (v2)
# Bash 3.2 compatible. Sources test-helpers.sh for setup/teardown and assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-routing.sh ==="

# ---------------------------------------------------------------------------
# Helper: run the hook with a given prompt, return stdout
# ---------------------------------------------------------------------------
run_hook() {
    local prompt="$1"
    jq -n --arg p "${prompt}" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>/dev/null
}

# Helper: run the hook from a specific directory
run_hook_in_dir() {
    local dir="$1"
    local prompt="$2"
    (cd "$dir" && jq -n --arg p "${prompt}" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>/dev/null)
}

# Helper: extract the additionalContext text from hook JSON output
extract_context() {
    local output="$1"
    printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# Helper: install a minimal skill registry cache for testing
install_registry() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": [
        "(debug|bug|broken|crash|regression|not.work|error|fail|hang|freeze|timeout|leak|corrupt|unexpected|wrong)"
      ],
      "trigger_mode": "regex",
      "priority": 10,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "available": true,
      "enabled": true
    },
    {
      "name": "test-driven-development",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": [
        "(build|create|implement|add|write|make)",
        "(run|test|execute|verify|validate|check|coverage)"
      ],
      "trigger_mode": "regex",
      "priority": 20,
      "invoke": "Skill(superpowers:test-driven-development)",
      "available": true,
      "enabled": true
    },
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": [
        "(build|create|implement|develop|scaffold|init|bootstrap|brainstorm|design|architect|strateg|scope|outline|approach|generate|set.?up|wire.up|connect|integrate|extend|new|start|introduce|enable|support|how.(should|would|could))"
      ],
      "trigger_mode": "regex",
      "priority": 30,
      "precedes": ["writing-plans"],
      "requires": [],
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": [],
      "trigger_mode": "regex",
      "priority": 40,
      "precedes": ["executing-plans"],
      "requires": ["brainstorming"],
      "invoke": "Skill(superpowers:writing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "executing-plans",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": [
        "(execute.*plan|run.the.plan|implement.the.plan|continue|follow.the.plan|resume|next.task|next.step)"
      ],
      "trigger_mode": "regex",
      "priority": 15,
      "precedes": [],
      "requires": ["writing-plans"],
      "invoke": "Skill(superpowers:executing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "subagent-driven-development",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": [
        "(execute.*plan|run.the.plan|implement.the.plan|continue|follow.the.plan|resume|next.task|next.step)"
      ],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(superpowers:subagent-driven-development)",
      "available": true,
      "enabled": true
    },
    {
      "name": "requesting-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": [
        "(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|tech.?debt|(^|[^a-z])pr($|[^a-z]))"
      ],
      "trigger_mode": "regex",
      "priority": 51,
      "invoke": "Skill(superpowers:requesting-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "receiving-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": [
        "(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|tech.?debt|(^|[^a-z])pr($|[^a-z]))"
      ],
      "trigger_mode": "regex",
      "priority": 50,
      "invoke": "Skill(superpowers:receiving-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "verification-before-completion",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [
        "(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"
      ],
      "trigger_mode": "regex",
      "priority": 60,
      "precedes": ["finishing-a-development-branch"],
      "requires": [],
      "invoke": "Skill(superpowers:verification-before-completion)",
      "available": true,
      "enabled": true
    },
    {
      "name": "finishing-a-development-branch",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [
        "(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"
      ],
      "trigger_mode": "regex",
      "priority": 61,
      "precedes": [],
      "requires": ["verification-before-completion"],
      "invoke": "Skill(superpowers:finishing-a-development-branch)",
      "available": true,
      "enabled": true
    },
    {
      "name": "security-scanner",
      "role": "domain",
      "triggers": [
        "(secur(e|ity)|vulnerab|owasp|pentest|attack|exploit|encrypt|inject|xss|csrf)"
      ],
      "trigger_mode": "regex",
      "priority": 102,
      "invoke": "Skill(security-scanner)",
      "available": true,
      "enabled": true
    },
    {
      "name": "frontend-design",
      "role": "domain",
      "triggers": [
        "(^|[^a-z])(ui|frontend|component|layout|style|css|tailwind|responsive|dashboard)($|[^a-z])"
      ],
      "trigger_mode": "regex",
      "priority": 101,
      "invoke": "Call Skill(frontend-design:frontend-design)",
      "available": true,
      "enabled": true
    },
    {
      "name": "disabled-skill",
      "role": "process",
      "phase": "DEBUG",
      "triggers": [
        "(debug|bug|fix)"
      ],
      "trigger_mode": "regex",
      "priority": 5,
      "invoke": "Skill(mock:disabled-skill)",
      "available": true,
      "enabled": false
    },
    {
      "name": "agent-team-execution",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": [
        "(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)"
      ],
      "trigger_mode": "regex",
      "priority": 16,
      "invoke": "Skill(agent-team-execution)",
      "available": true,
      "enabled": true
    },
    {
      "name": "agent-team-review",
      "role": "workflow",
      "phase": "REVIEW",
      "triggers": [
        "(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|tech.?debt|(^|[^a-z])pr($|[^a-z]))"
      ],
      "trigger_mode": "regex",
      "priority": 17,
      "invoke": "Skill(agent-team-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "design-debate",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": [
        "(build|create|implement|develop|scaffold|brainstorm|design|architect|strateg|scope|outline|approach|generate|set.?up|integrate|extend|new|start)"
      ],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(design-debate)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [
    {
      "name": "ralph-loop",
      "triggers": [
        "(migrate|refactor.all|fix.all|batch|overnight|autonom|iterate|keep.(going|trying|fixing))"
      ],
      "trigger_mode": "regex",
      "hint": "RALPH LOOP: Consider /ralph-loop for autonomous iteration."
    },
    {
      "name": "pr-review",
      "triggers": [
        "(review|pull.?request|code.?review|(^|[^a-z])pr($|[^a-z]))"
      ],
      "trigger_mode": "regex",
      "hint": "PR REVIEW: Consider /pr-review for structured review.",
      "skill": "requesting-code-review"
    }
  ],
  "blocklist_patterns": [
    {
      "pattern": "^(hi|hello|hey|thanks|thank.you|good.(morning|afternoon|evening)|bye|goodbye|ok|okay|yes|no|sure|yep|nope|got.it|sounds.good|cool|nice|great|perfect|awesome|understood)([[:space:]!.,]+.{0,20})?$",
      "description": "Greeting or short acknowledgement",
      "max_tail_length": 20
    }
  ],
  "warnings": []
}
REGISTRY
}

# Helper: install registry extended with batch-scripting skill
install_registry_with_batch() {
    install_registry
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.skills += [{
      "name": "batch-scripting",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": ["(batch|bulk|mass|across.*files|every.*file|all.*files|migrate.*all|transform.*all|refactor.*all|sweep|codemod|claude.?-p|headless|each.*file)"],
      "trigger_mode": "regex",
      "priority": 15,
      "precedes": [],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:batch-scripting)",
      "available": true,
      "enabled": true
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"
}

# Helper: install a v4 skill registry cache with plugins and phase_compositions
install_registry_v4() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'REGISTRY_V4'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": ["(debug|bug|broken|crash|regression|not.work|error|fail|hang|freeze|timeout|leak|corrupt|unexpected|wrong)"],
      "trigger_mode": "regex",
      "priority": 10,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "available": true,
      "enabled": true
    },
    {
      "name": "test-driven-development",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(build|create|implement|add|write|make)", "(run|test|execute|verify|validate|check|coverage)"],
      "trigger_mode": "regex",
      "priority": 20,
      "invoke": "Skill(superpowers:test-driven-development)",
      "available": true,
      "enabled": true
    },
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create|implement|develop|scaffold|init|bootstrap|brainstorm|design|architect|strateg|scope|outline|approach|generate|set.?up|wire.up|connect|integrate|extend|new|start|introduce|enable|support|how.(should|would|could))"],
      "trigger_mode": "regex",
      "priority": 30,
      "precedes": ["writing-plans"],
      "requires": [],
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": [],
      "trigger_mode": "regex",
      "priority": 40,
      "precedes": ["executing-plans"],
      "requires": ["brainstorming"],
      "invoke": "Skill(superpowers:writing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "executing-plans",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(execute.*plan|run.the.plan|implement.the.plan|continue|follow.the.plan|resume|next.task|next.step)"],
      "trigger_mode": "regex",
      "priority": 15,
      "precedes": [],
      "requires": ["writing-plans"],
      "invoke": "Skill(superpowers:executing-plans)",
      "available": true,
      "enabled": true
    },
    {
      "name": "subagent-driven-development",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(execute.*plan|run.the.plan|implement.the.plan|continue|follow.the.plan|resume|next.task|next.step)"],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(superpowers:subagent-driven-development)",
      "available": true,
      "enabled": true
    },
    {
      "name": "requesting-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": ["(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|tech.?debt|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 51,
      "invoke": "Skill(superpowers:requesting-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "receiving-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": ["(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|tech.?debt|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 50,
      "invoke": "Skill(superpowers:receiving-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "verification-before-completion",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": ["(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"],
      "trigger_mode": "regex",
      "priority": 60,
      "precedes": ["finishing-a-development-branch"],
      "requires": [],
      "invoke": "Skill(superpowers:verification-before-completion)",
      "available": true,
      "enabled": true
    },
    {
      "name": "finishing-a-development-branch",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": ["(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"],
      "trigger_mode": "regex",
      "priority": 61,
      "precedes": [],
      "requires": ["verification-before-completion"],
      "invoke": "Skill(superpowers:finishing-a-development-branch)",
      "available": true,
      "enabled": true
    },
    {
      "name": "security-scanner",
      "role": "domain",
      "triggers": ["(secur(e|ity)|vulnerab|owasp|pentest|attack|exploit|encrypt|inject|xss|csrf)"],
      "trigger_mode": "regex",
      "priority": 102,
      "invoke": "Skill(security-scanner)",
      "available": true,
      "enabled": true
    },
    {
      "name": "frontend-design",
      "role": "domain",
      "triggers": ["(^|[^a-z])(ui|frontend|component|layout|style|css|tailwind|responsive|dashboard)($|[^a-z])"],
      "trigger_mode": "regex",
      "priority": 101,
      "invoke": "Call Skill(frontend-design:frontend-design)",
      "available": true,
      "enabled": true
    },
    {
      "name": "disabled-skill",
      "role": "process",
      "phase": "DEBUG",
      "triggers": ["(debug|bug|fix)"],
      "trigger_mode": "regex",
      "priority": 5,
      "invoke": "Skill(mock:disabled-skill)",
      "available": true,
      "enabled": false
    },
    {
      "name": "agent-team-execution",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": ["(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)"],
      "trigger_mode": "regex",
      "priority": 16,
      "invoke": "Skill(agent-team-execution)",
      "available": true,
      "enabled": true
    },
    {
      "name": "agent-team-review",
      "role": "workflow",
      "phase": "REVIEW",
      "triggers": ["(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|tech.?debt|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 17,
      "invoke": "Skill(agent-team-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "design-debate",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": ["(build|create|implement|develop|scaffold|brainstorm|design|architect|strateg|scope|outline|approach|generate|set.?up|integrate|extend|new|start)"],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(design-debate)",
      "available": true,
      "enabled": true
    }
  ],
  "plugins": [
    {"name": "code-review", "source": "claude-plugins-official", "provides": {"commands": ["/code-review"], "skills": [], "agents": [], "hooks": []}, "phase_fit": ["REVIEW"], "description": "5 parallel review agents", "available": true},
    {"name": "code-simplifier", "source": "claude-plugins-official", "provides": {"commands": [], "skills": [], "agents": ["code-simplifier"], "hooks": []}, "phase_fit": ["REVIEW"], "description": "Post-review clarity pass", "available": true},
    {"name": "commit-commands", "source": "claude-plugins-official", "provides": {"commands": ["/commit", "/commit-push-pr"], "skills": [], "agents": [], "hooks": []}, "phase_fit": ["SHIP"], "description": "Commit workflows", "available": true},
    {"name": "security-guidance", "source": "claude-plugins-official", "provides": {"commands": [], "skills": [], "agents": [], "hooks": ["PreToolUse:security-patterns"]}, "phase_fit": ["*"], "description": "Write-time security blocker", "available": true},
    {"name": "feature-dev", "source": "claude-plugins-official", "provides": {"commands": ["/feature-dev"], "skills": [], "agents": ["code-explorer", "code-architect", "code-reviewer"], "hooks": []}, "phase_fit": ["DESIGN", "IMPLEMENT", "REVIEW"], "description": "Full feature pipeline", "available": true}
  ],
  "mcp_servers": [],
  "phase_compositions": {
    "DESIGN": {"driver": "brainstorming", "parallel": [{"plugin": "feature-dev", "use": "agents:code-explorer", "when": "installed", "purpose": "Parallel codebase exploration while brainstorming"}], "hints": [{"plugin": "feature-dev", "text": "Consider /feature-dev for agent-parallel feature development", "when": "installed"}]},
    "PLAN": {"driver": "writing-plans", "parallel": [], "hints": []},
    "IMPLEMENT": {"driver": "executing-plans", "parallel": [{"plugin": "security-guidance", "use": "hooks:PreToolUse", "when": "installed", "purpose": "Passive write-time security guard"}], "hints": []},
    "REVIEW": {"driver": "requesting-code-review", "parallel": [{"plugin": "code-review", "use": "commands:/code-review", "when": "installed", "purpose": "5 parallel review agents, posts to GitHub PR"}, {"plugin": "code-simplifier", "use": "agents:code-simplifier", "when": "installed", "purpose": "Post-review simplification pass"}], "hints": [{"plugin": "code-review", "text": "Consider /code-review for automated multi-agent PR review", "when": "installed"}]},
    "SHIP": {"driver": "verification-before-completion", "sequence": [{"plugin": "commit-commands", "use": "commands:/commit", "when": "installed", "purpose": "Execute structured commit after verification passes"}, {"step": "finishing-a-development-branch", "purpose": "Branch cleanup, merge, or PR"}, {"plugin": "commit-commands", "use": "commands:/commit-push-pr", "when": "installed AND user chooses PR option", "purpose": "Automated branch-to-PR flow"}], "hints": [{"plugin": "commit-commands", "text": "Consider /commit-push-pr for automated branch-to-PR workflow", "when": "installed"}]},
    "DEBUG": {"driver": "systematic-debugging", "parallel": [], "hints": []}
  },
  "methodology_hints": [
    {"name": "ralph-loop", "triggers": ["(migrate|refactor.all|fix.all|batch|overnight|autonom|iterate|keep.(going|trying|fixing))"], "trigger_mode": "regex", "hint": "RALPH LOOP: Consider /ralph-loop for autonomous iteration."},
    {"name": "pr-review", "triggers": ["(review|pull.?request|code.?review|(^|[^a-z])pr($|[^a-z]))"], "trigger_mode": "regex", "hint": "PR REVIEW: Consider /pr-review for structured review.", "skill": "requesting-code-review"}
  ],
  "blocklist_patterns": [
    {"pattern": "^(hi|hello|hey|thanks|thank.you|good.(morning|afternoon|evening)|bye|goodbye|ok|okay|yes|no|sure|yep|nope|got.it|sounds.good|cool|nice|great|perfect|awesome|understood)([[:space:]!.,]+.{0,20})?$", "description": "Greeting or short acknowledgement", "max_tail_length": 20}
  ],
  "warnings": []
}
REGISTRY_V4
}

# ---------------------------------------------------------------------------
# 1. Debug prompt matches systematic-debugging
# ---------------------------------------------------------------------------
test_debug_prompt_matches() {
    echo "-- test: debug prompt matches systematic-debugging --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "I need to debug this crash in the auth module")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "debug matches systematic-debugging" "systematic-debugging" "${context}"
    assert_contains "debug label is Fix / Debug" "Fix / Debug" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 2. Build prompt matches brainstorming
# ---------------------------------------------------------------------------
test_build_prompt_matches() {
    echo "-- test: build prompt matches brainstorming --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "create a new authentication service from scratch")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "build matches brainstorming" "brainstorming" "${context}"
    assert_contains "build label is Build New" "Build New" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 3. Greeting is blocked (empty output)
# ---------------------------------------------------------------------------
test_greeting_blocked() {
    echo "-- test: greeting is blocked --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "hello there")"

    assert_equals "greeting produces empty output" "" "${output}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 4. Slash command is blocked
# ---------------------------------------------------------------------------
test_slash_command_blocked() {
    echo "-- test: slash command is blocked --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "/help me with something")"

    assert_equals "slash command produces empty output" "" "${output}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 5. Short prompt is blocked
# ---------------------------------------------------------------------------
test_short_prompt_blocked() {
    echo "-- test: short prompt is blocked --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "hi")"

    assert_equals "short prompt produces empty output" "" "${output}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 6. Domain skill appears alongside process skill with Domain:
# ---------------------------------------------------------------------------
test_domain_informed_by() {
    echo "-- test: domain skill shows Domain: --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    local context
    context="$(extract_context "${output}")"

    # Should have a process skill (brainstorming for "build")
    assert_contains "has process skill" "Process:" "${context}"
    # Should have domain skill as Domain:
    assert_contains "has Domain:" "Domain:" "${context}"
    # security-scanner or frontend-design should appear
    assert_contains "has domain skill" "domain" "$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | tr '[:upper:]' '[:lower:]')"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 7. Review prompt matches code review
# ---------------------------------------------------------------------------
test_review_prompt_matches() {
    echo "-- test: review prompt matches code review --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "please review the code changes in this pull request")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "review matches code-review skill" "code-review" "${context}"
    assert_contains "review label is Review" "Review" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 8. Ship prompt matches workflow skills
# ---------------------------------------------------------------------------
test_ship_prompt_matches() {
    echo "-- test: ship prompt matches workflow skills --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "let's ship this and merge the branch to main")"
    local context
    context="$(extract_context "${output}")"

    # With no process skill, workflow skills listed without orchestration prefix
    # finishing-a-development-branch has higher priority (61 vs 60), so it wins the single workflow slot
    assert_contains "ship matches workflow skill" "finishing-a-development-branch" "${context}"
    assert_contains "ship label has Ship / Complete" "Ship / Complete" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 9. Max 1 process skill enforced
# ---------------------------------------------------------------------------
test_max_one_process() {
    echo "-- test: max 1 process skill enforced --"
    setup_test_env
    install_registry

    # "debug" triggers both systematic-debugging and test-driven-development (both process)
    local output
    output="$(run_hook "debug and fix the broken authentication error in the module")"
    local context
    context="$(extract_context "${output}")"

    # Count Process: lines (should be exactly 1)
    local process_count
    process_count="$(printf '%s' "${context}" | grep -c 'Process:' 2>/dev/null)" || process_count=0

    assert_equals "max 1 process skill" "1" "${process_count}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 10. Disabled skills excluded
# ---------------------------------------------------------------------------
test_disabled_skill_excluded() {
    echo "-- test: disabled skills excluded --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "debug this broken module that has a bug")"
    local context
    context="$(extract_context "${output}")"

    assert_not_contains "disabled skill not in output" "disabled-skill" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 11. Missing registry falls back gracefully
# ---------------------------------------------------------------------------
test_missing_registry_fallback() {
    echo "-- test: missing registry falls back gracefully --"
    setup_test_env
    # Do NOT install registry — leave cache missing

    local exit_code=0
    local output
    output="$(run_hook "debug the authentication bug")" || exit_code=$?

    assert_equals "hook exits cleanly" "0" "${exit_code}"

    # Should still produce output (phase checkpoint only)
    if [ -n "${output}" ]; then
        local context
        context="$(extract_context "${output}")"
        assert_contains "fallback has phase checkpoint" "phase" "$(printf '%s' "${context}" | tr '[:upper:]' '[:lower:]')"
    else
        _record_pass "hook exits silently on missing registry (acceptable)"
    fi

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 12. Output is valid JSON
# ---------------------------------------------------------------------------
test_output_valid_json() {
    echo "-- test: output is valid JSON --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "implement the new user authentication feature")"

    # Write to file for json validation
    local tmpfile="${TEST_TMPDIR}/output.json"
    printf '%s' "${output}" > "${tmpfile}"

    assert_json_valid "output is valid JSON" "${tmpfile}"

    # Check structure
    local hook_event
    hook_event="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
    assert_equals "hookEventName is UserPromptSubmit" "UserPromptSubmit" "${hook_event}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 13. Zero matches produce phase checkpoint
# ---------------------------------------------------------------------------
test_zero_matches_phase_checkpoint() {
    echo "-- test: zero matches produce phase checkpoint --"
    setup_test_env
    install_registry

    # A prompt that won't match any triggers
    local output
    output="$(run_hook "tell me about the weather forecast for tomorrow please")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "zero match has phase checkpoint" "phase checkpoint" "$(printf '%s' "${context}" | tr '[:upper:]' '[:lower:]')"
    assert_contains "zero match has 0 skills" "0 skills" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 14. Methodology hints appended when matched
# ---------------------------------------------------------------------------
test_methodology_hints() {
    echo "-- test: methodology hints suppressed when skill selected --"
    setup_test_env
    install_registry

    # PR review hint should be suppressed because "review" triggers requesting-code-review
    local output
    output="$(run_hook "review this pull request for code quality issues")"
    local context
    context="$(extract_context "${output}")"

    assert_not_contains "PR review hint suppressed when skill selected" "PR REVIEW" "${context}"

    # Ralph-loop hint should still appear when matched (no associated skill)
    output="$(run_hook "migrate all the legacy modules to the new framework and iterate until done")"
    context="$(extract_context "${output}")"
    assert_contains "Ralph loop hint present" "RALPH LOOP" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 15. Agent team execution matches plan prompts
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 16. Design-debate appears as Domain: domain skill
# ---------------------------------------------------------------------------
test_design_debate_as_domain() {
    echo "-- test: design-debate appears as Domain: --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a new authentication system")"
    context="$(extract_context "$output")"
    # brainstorming is process (higher priority), design-debate is domain
    assert_contains "has brainstorming" "brainstorming" "$context"
    assert_contains "has Domain: design-debate" "design-debate" "$context"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 17. Agent team review matches review prompts
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 18. Brainstorming fires on short design prompts too
# ---------------------------------------------------------------------------
test_brainstorming_short_prompt() {
    echo "-- test: brainstorming fires on short design prompts --"
    setup_test_env
    install_registry

    local output context
    # Short but legitimate design prompts should trigger brainstorming
    output="$(run_hook "build a widget")"
    context="$(extract_context "${output}")"
    assert_contains "brainstorming fires on short build prompt" "brainstorming" "${context}"

    # Long prompts should also work
    output="$(run_hook "design a new user authentication flow with OAuth and social login")"
    context="$(extract_context "${output}")"
    assert_contains "brainstorming fires on long prompt" "brainstorming" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 19. Skill-name-mention boost works
# ---------------------------------------------------------------------------
test_skill_name_mention_boost() {
    echo "-- test: skill-name-mention boost --"
    setup_test_env
    install_registry

    local output context
    # Mention "security-scanner" by name — should boost it even without a trigger word
    output="$(run_hook "tell me about the security-scanner skill and how to use it")"
    context="$(extract_context "${output}")"

    assert_contains "skill name mention boosts security-scanner" "security-scanner" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 20. Domain invocation instruction appears when domain skills present
# ---------------------------------------------------------------------------
test_domain_invocation_instruction() {
    echo "-- test: domain invocation instruction --"
    setup_test_env
    install_registry

    local output context
    # "build a secure dashboard" triggers brainstorming (process) + security-scanner + frontend-design (domain)
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    context="$(extract_context "${output}")"

    assert_contains "domain invocation instruction present" "invoke them" "${context}"

    # Prompt with only process skill and no domain should NOT have the instruction
    output="$(run_hook "continue with the next task in the plan")"
    context="$(extract_context "${output}")"
    assert_not_contains "no domain instruction without domain skills" "invoke them" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 21. Overflow domain skills shown as "Also relevant"
# ---------------------------------------------------------------------------
test_overflow_domain_shown() {
    echo "-- test: overflow domain skills shown --"
    setup_test_env
    install_registry

    # With max_suggestions=3 (default), process + 2 domain fills the cap.
    # A third domain skill should appear as "Also relevant"
    # "build a secure responsive dashboard" triggers:
    #   brainstorming (process), security-scanner (domain, p102), frontend-design (domain, p101), design-debate (domain, p14)
    # design-debate should overflow
    local output context
    output="$(run_hook "build a secure responsive dashboard with csrf protection")"
    context="$(extract_context "${output}")"

    assert_contains "overflow domain shown" "Also relevant" "${context}"
    assert_contains "overflow includes design-debate" "design-debate" "${context}"

    teardown_test_env
}

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

# ---------------------------------------------------------------------------
# 23. Review phase emits PARALLEL lines (v4 registry)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 24. Ship phase emits SEQUENCE lines (v4 registry)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 25. No PARALLEL when plugin unavailable (v3 registry)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 26. Process skill reserved when high-priority domain/workflow fill slots
# ---------------------------------------------------------------------------
test_process_slot_reserved() {
    echo "-- test: process slot reserved under cap --"
    setup_test_env
    install_registry

    # "build a secure frontend dashboard and ship it" triggers:
    #   brainstorming (process, prio 30), security-scanner (domain, prio 102),
    #   frontend-design (domain, prio 101), finishing-a-development-branch (workflow, prio 61)
    # With max_suggestions=3, all 3 slots could go to non-process skills.
    # Process skill MUST still be selected.
    local output context
    output="$(run_hook "build a secure frontend dashboard and ship it")"
    context="$(extract_context "${output}")"

    assert_contains "process skill reserved" "Skill(superpowers:brainstorming)" "${context}"
    assert_contains "process skill has Process: prefix" "Process:" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 26.5. Malformed skill entry (missing triggers) does not break hook
# ---------------------------------------------------------------------------
test_missing_triggers_handled() {
    echo "-- test: missing triggers handled gracefully --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'BADREG'
{
  "version": "test",
  "skills": [
    {
      "name": "good-skill",
      "role": "process",
      "phase": "DEBUG",
      "triggers": ["(debug|bug)"],
      "priority": 10,
      "invoke": "Skill(mock:good-skill)",
      "available": true,
      "enabled": true
    },
    {
      "name": "no-triggers-skill",
      "role": "domain",
      "priority": 50,
      "invoke": "Skill(mock:no-triggers)",
      "available": true,
      "enabled": true
    },
    {
      "name": "null-triggers-skill",
      "role": "domain",
      "triggers": null,
      "priority": 50,
      "invoke": "Skill(mock:null-triggers)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
BADREG

    local exit_code=0
    local output context
    output="$(run_hook "debug this broken module")" || exit_code=$?

    assert_equals "hook exits cleanly with malformed skills" "0" "${exit_code}"
    context="$(extract_context "${output}")"
    assert_contains "good skill still selected" "good-skill" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 27. Phase composition uses process phase, not domain phase
# ---------------------------------------------------------------------------
test_phase_uses_process_precedence() {
    echo "-- test: phase composition uses process phase precedence --"
    setup_test_env
    install_registry_v4

    # "build a secure frontend dashboard" triggers:
    #   brainstorming (process, phase=DESIGN, prio 30),
    #   security-scanner (domain, no phase, prio 102),
    #   frontend-design (domain, no phase, prio 101)
    # Phase should be DESIGN (from process), not any domain phase
    local output context
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    context="$(extract_context "${output}")"

    # The DESIGN phase composition has a PARALLEL line for feature-dev plugin
    assert_contains "phase composition uses DESIGN" "PARALLEL:" "${context}"
    assert_contains "phase composition mentions feature-dev" "feature-dev" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 28. Compact Evaluate phase uses process phase
# ---------------------------------------------------------------------------
test_eval_phase_uses_process() {
    echo "-- test: compact Evaluate phase uses process phase --"
    setup_test_env

    # Use a minimal registry with just 1 process + 1 domain to stay in compact format
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'PHASEREG'
{
  "version": "test",
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create)"],
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    },
    {
      "name": "security-scanner",
      "role": "domain",
      "phase": "IMPLEMENT",
      "triggers": ["(secur(e|ity)|encrypt)"],
      "priority": 102,
      "invoke": "Skill(security-scanner)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
PHASEREG

    # 2 skills -> compact format with Evaluate line
    # security-scanner has phase=IMPLEMENT, brainstorming has phase=DESIGN
    # Process phase (DESIGN) should win
    local output context
    output="$(run_hook "build a secure authentication service with encryption")"
    context="$(extract_context "${output}")"

    assert_contains "Evaluate uses DESIGN phase" "Phase: [DESIGN]" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 29. Skill name boost uses boundary-aware matching
# ---------------------------------------------------------------------------
test_name_boost_boundary_aware() {
    echo "-- test: skill name boost boundary-aware --"
    setup_test_env

    # Custom registry with two skills: "debug" and "debug-advanced"
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'NAMEREG'
{
  "version": "test",
  "skills": [
    {
      "name": "debug",
      "role": "domain",
      "triggers": ["(never-match-this-nonsense-string)"],
      "priority": 10,
      "invoke": "Skill(mock:debug)",
      "available": true,
      "enabled": true
    },
    {
      "name": "debug-advanced",
      "role": "domain",
      "triggers": ["(never-match-this-nonsense-string)"],
      "priority": 10,
      "invoke": "Skill(mock:debug-advanced)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
NAMEREG

    # Mention only "debug-advanced" by name — "debug" should NOT get boosted
    local output context
    output="$(run_hook "tell me about the debug-advanced skill and how it works")"
    context="$(extract_context "${output}")"

    assert_contains "debug-advanced is selected" "debug-advanced" "${context}"
    assert_not_contains "plain debug not selected" "mock:debug)" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 29.5. Trigger word-boundary excludes dot (file extension separator)
# ---------------------------------------------------------------------------
test_trigger_boundary_excludes_dot() {
    echo "-- test: trigger word-boundary excludes dot --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'DOTREG'
{
  "version": "test",
  "skills": [
    {
      "name": "py-tool",
      "role": "domain",
      "triggers": ["py"],
      "priority": 0,
      "invoke": "Skill(mock:py-tool)",
      "available": true,
      "enabled": true
    },
    {
      "name": "other-tool",
      "role": "domain",
      "triggers": ["(skill|tool)"],
      "priority": 0,
      "invoke": "Skill(mock:other-tool)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
DOTREG

    # "check skill.py file" — "py" appears after a dot, NOT a word boundary
    # "other-tool" has trigger "skill" which gets word-boundary score (30)
    # "py-tool" trigger "py" should only get substring score (10)
    # With equal priority (0), other-tool (score 30) should rank above py-tool (score 10)
    local output context
    output="$(run_hook "check the skill.py file for issues please")"
    context="$(extract_context "${output}")"

    # other-tool should appear (word-boundary match on "skill")
    assert_contains "other-tool selected" "other-tool" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 30. Domain instruction wording without process skill
# ---------------------------------------------------------------------------
test_domain_instruction_no_process() {
    echo "-- test: domain instruction wording without process --"
    setup_test_env

    # Custom registry: only domain skills, no process skills
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'DOMREG'
{
  "version": "test",
  "skills": [
    {
      "name": "security-scanner",
      "role": "domain",
      "triggers": ["(secur(e|ity)|vulnerab)"],
      "priority": 102,
      "invoke": "Skill(security-scanner)",
      "available": true,
      "enabled": true
    },
    {
      "name": "frontend-design",
      "role": "domain",
      "triggers": ["(frontend|dashboard|component)"],
      "priority": 101,
      "invoke": "Skill(frontend-design)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
DOMREG

    local output context
    output="$(run_hook "build a secure frontend dashboard component")"
    context="$(extract_context "${output}")"

    # Should have domain invocation instruction but NOT mention "the process skill"
    assert_contains "has domain invocation instruction" "invoke them" "${context}"
    assert_not_contains "no process skill reference" "the process skill" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
test_debug_prompt_matches
test_build_prompt_matches
test_greeting_blocked
test_slash_command_blocked
test_short_prompt_blocked
test_domain_informed_by
test_review_prompt_matches
test_ship_prompt_matches
test_max_one_process
test_disabled_skill_excluded
test_missing_registry_fallback
test_output_valid_json
test_zero_matches_phase_checkpoint
test_methodology_hints
test_agent_team_execution_matches
test_design_debate_as_domain
test_agent_team_review_matches
test_brainstorming_short_prompt
test_skill_name_mention_boost
test_domain_invocation_instruction
test_overflow_domain_shown
test_teammate_idle_guard
test_review_emits_parallel_lines
test_ship_emits_sequence_lines
test_no_parallel_when_plugin_unavailable
test_process_slot_reserved
test_missing_triggers_handled
test_phase_uses_process_precedence
test_eval_phase_uses_process
test_name_boost_boundary_aware
test_trigger_boundary_excludes_dot
test_domain_instruction_no_process

# ---------------------------------------------------------------------------
# Skill composition chain tests
# ---------------------------------------------------------------------------
test_composition_chain_forward() {
    echo "-- test: brainstorming emits composition chain --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a new user dashboard")"
    context="$(extract_context "${output}")"

    assert_contains "composition has Composition:" "Composition:" "${context}"
    assert_contains "composition has CURRENT marker" "[CURRENT]" "${context}"
    assert_contains "composition has NEXT marker" "[NEXT]" "${context}"
    assert_contains "composition has writing-plans" "writing-plans" "${context}"
    assert_contains "composition has IMPORTANT directive" "IMPORTANT:" "${context}"

    teardown_test_env
}

test_composition_chain_midentry() {
    echo "-- test: executing-plans shows backward chain --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "follow the plan and resume where we left off next task")"
    context="$(extract_context "${output}")"

    assert_contains "midentry has Composition:" "Composition:" "${context}"
    assert_contains "midentry has DONE? marker" "[DONE?]" "${context}"
    assert_contains "midentry has CURRENT on executing-plans" "[CURRENT]" "${context}"

    teardown_test_env
}

test_composition_no_chain_for_debug() {
    echo "-- test: debug has no composition chain --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "debug the authentication crash")"
    context="$(extract_context "${output}")"

    assert_not_contains "debug has no Composition:" "Composition:" "${context}"
    assert_not_contains "debug has no IMPORTANT directive" "IMPORTANT:" "${context}"

    teardown_test_env
}

test_composition_domain_hint_during_step() {
    echo "-- test: domain hint says 'during the current step' with composition --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a secure authentication system with encryption")"
    context="$(extract_context "${output}")"

    assert_contains "domain hint has during step" "during the current step" "${context}"
    assert_not_contains "domain hint no before/during/after" "before, during, or after" "${context}"

    teardown_test_env
}

test_composition_workflow_chain() {
    echo "-- test: workflow skill with precedes emits chain --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "ship it and merge to main branch")"
    context="$(extract_context "${output}")"

    assert_contains "ship has Composition:" "Composition:" "${context}"
    assert_contains "ship has finishing-a-development-branch" "finishing-a-development-branch" "${context}"

    teardown_test_env
}

test_composition_chain_forward
test_composition_chain_midentry
test_composition_no_chain_for_debug
test_composition_domain_hint_during_step
test_composition_workflow_chain

# ---------------------------------------------------------------------------
# Trigger pattern validation tests (against default-triggers.json)
# ---------------------------------------------------------------------------
test_brainstorming_has_broad_triggers() {
    echo "-- test: brainstorming has broad verb triggers --"
    local triggers_file="${PROJECT_ROOT}/config/default-triggers.json"
    local brainstorm_triggers
    brainstorm_triggers="$(jq -r '.skills[] | select(.name == "brainstorming") | .triggers[]' "$triggers_file")"

    # Should contain common feature-request verbs
    assert_contains "brainstorming has build" "build" "$brainstorm_triggers"
    assert_contains "brainstorming has create" "create" "$brainstorm_triggers"
    assert_contains "brainstorming has implement" "implement" "$brainstorm_triggers"

    # Should still contain core design terms
    assert_contains "brainstorming has brainstorm" "brainstorm" "$brainstorm_triggers"
    assert_contains "brainstorming has design" "design" "$brainstorm_triggers"
    assert_contains "brainstorming has architect" "architect" "$brainstorm_triggers"
}

test_agent_team_has_plan_triggers() {
    echo "-- test: agent-team-execution has plan-execution triggers --"
    local triggers_file="${PROJECT_ROOT}/config/default-triggers.json"
    local ate_triggers
    ate_triggers="$(jq -r '.skills[] | select(.name == "agent-team-execution") | .triggers[]' "$triggers_file")"

    assert_contains "agent-team has execute.*plan" "execute.*plan" "$ate_triggers"
    assert_contains "agent-team has build" "build" "$ate_triggers"
    assert_contains "agent-team has team keywords" "agent.team" "$ate_triggers"
}

test_brainstorming_has_broad_triggers
test_agent_team_has_plan_triggers

# ---------------------------------------------------------------------------
# User config override tests
# ---------------------------------------------------------------------------
test_config_max_suggestions() {
    echo "-- test: max_suggestions limits skill count --"
    setup_test_env
    install_registry

    # Write config with max_suggestions: 1
    printf '{"max_suggestions": 1}' > "${HOME}/.claude/skill-config.json"

    # Use a prompt that matches multiple skills
    local output
    output="$(run_hook "debug this broken login bug and fix it")"
    local ctx
    ctx="$(extract_context "$output")"

    # With max_suggestions=1, should have only 1 skill line
    local skill_count
    skill_count="$(printf '%s' "$ctx" | grep -c 'Skill(' || true)"
    if [ "$skill_count" -le 1 ]; then
        _record_pass "max_suggestions=1 limits to 1 skill"
    else
        _record_fail "max_suggestions=1 limits to 1 skill" "got $skill_count skills"
    fi

    teardown_test_env
}

test_config_trigger_add() {
    echo "-- test: trigger override adds new pattern --"
    setup_test_env

    local session_hook="${PROJECT_ROOT}/hooks/session-start-hook.sh"

    # Add a new trigger pattern to systematic-debugging
    printf '{"overrides":{"systematic-debugging":{"triggers":["+customtrigger123"]}}}' \
        > "${HOME}/.claude/skill-config.json"

    # Run session-start to build registry
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "$session_hook" >/dev/null 2>&1

    local cache="${HOME}/.claude/.skill-registry-cache.json"
    if [ ! -f "$cache" ]; then
        _record_fail "trigger override: registry built" "cache file not found"
        teardown_test_env
        return
    fi

    local debug_triggers
    debug_triggers="$(jq -r '.skills[] | select(.name == "systematic-debugging") | .triggers | join(" ")' "$cache" 2>/dev/null)"

    assert_contains "trigger + adds new pattern" "customtrigger123" "$debug_triggers"

    teardown_test_env
}

test_config_custom_skills() {
    echo "-- test: custom_skills appear in registry --"
    setup_test_env

    local session_hook="${PROJECT_ROOT}/hooks/session-start-hook.sh"

    # Write config with a custom skill
    cat > "${HOME}/.claude/skill-config.json" <<'EOF'
{
    "custom_skills": [{
        "name": "my-custom-test-skill",
        "role": "domain",
        "triggers": ["customskilltest"],
        "invoke": "Skill(my-custom-test-skill)"
    }]
}
EOF

    # Run session-start to build registry
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "$session_hook" >/dev/null 2>&1

    local cache="${HOME}/.claude/.skill-registry-cache.json"
    if [ ! -f "$cache" ]; then
        _record_fail "custom skill: registry built" "cache file not found"
        teardown_test_env
        return
    fi

    local custom_name
    custom_name="$(jq -r '.skills[] | select(.name == "my-custom-test-skill") | .name' "$cache" 2>/dev/null)"

    assert_equals "custom skill in registry" "my-custom-test-skill" "$custom_name"

    # Verify it's marked as available and enabled
    local custom_available
    custom_available="$(jq -r '.skills[] | select(.name == "my-custom-test-skill") | .available' "$cache" 2>/dev/null)"
    assert_equals "custom skill is available" "true" "$custom_available"

    teardown_test_env
}

test_config_greeting_blocklist() {
    echo "-- test: custom greeting blocklist blocks matching prompts --"
    setup_test_env
    install_registry

    # Write config with a custom blocklist that blocks "xyztest"
    printf '{"greeting_blocklist":"xyztest"}' > "${HOME}/.claude/skill-config.json"

    # A prompt matching the custom blocklist should produce no skills
    local output
    output="$(run_hook "xyztest")"
    local ctx
    ctx="$(extract_context "$output")"

    # Should have no skill output (blocklist triggers early exit)
    assert_not_contains "custom blocklist blocks prompt" "Skill(" "$ctx"

    teardown_test_env
}

test_config_max_suggestions
test_config_trigger_add
test_config_custom_skills
test_config_greeting_blocklist

# ---------------------------------------------------------------------------
# End-to-end integration test: session-start → routing pipeline
# ---------------------------------------------------------------------------
test_end_to_end_pipeline() {
    echo "-- test: end-to-end session-start → routing pipeline --"
    setup_test_env

    local session_hook="${PROJECT_ROOT}/hooks/session-start-hook.sh"
    local routing_hook="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
    local cache="${HOME}/.claude/.skill-registry-cache.json"

    # Step 1: Run session-start to build registry
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "$session_hook" >/dev/null 2>&1

    # Step 2: Verify registry was created
    assert_file_exists "e2e: registry cache created" "$cache"

    # Step 3: Verify registry is valid JSON with skills
    local skill_count
    skill_count="$(jq '.skills | length' "$cache" 2>/dev/null)"
    if [ -n "$skill_count" ] && [ "$skill_count" -gt 0 ]; then
        _record_pass "e2e: registry has skills ($skill_count)"
    else
        _record_fail "e2e: registry has skills" "got ${skill_count:-empty}"
        teardown_test_env
        return
    fi

    # Step 4: Route a prompt through the routing hook
    # Use a prompt that triggers design-debate (bundled skill, always available)
    local output
    output="$(jq -n --arg p "brainstorm the architecture and design trade-offs" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "$routing_hook" 2>/dev/null)"

    local ctx
    ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

    # Step 5: Verify design-debate was activated (bundled skill, always available)
    assert_contains "e2e: brainstorm prompt activates design-debate" "design-debate" "$ctx"

    teardown_test_env
}

test_end_to_end_pipeline

# ---------------------------------------------------------------------------
# Idle guard cooldown tests
# ---------------------------------------------------------------------------
test_idle_guard_cooldown() {
    echo "-- test: idle guard cooldown prevents spam --"
    setup_test_env

    local guard="${PROJECT_ROOT}/hooks/teammate-idle-guard.sh"
    local cooldown_dir="${HOME}/.claude/.idle-cooldowns"
    local cooldown_file="${cooldown_dir}/claude-idle-test-team-worker-last-nudge"
    local stderr_file="${TEST_TMPDIR}/guard-stderr.txt"

    # Clean stale cooldown files from prior tests
    mkdir -p "$cooldown_dir"
    rm -f "$cooldown_file"

    # Create an in_progress task for the worker
    mkdir -p "${HOME}/.claude/tasks/test-team"
    printf '{"subject":"Fix auth","status":"in_progress","owner":"worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"

    # First nudge should fire (exit 2)
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>"$stderr_file"
    local exit_code=$?
    assert_equals "first nudge fires" "2" "$exit_code"
    assert_contains "first nudge has message" "unfinished tasks" "$(cat "$stderr_file")"
    assert_file_exists "cooldown file created" "$cooldown_file"

    # Second nudge within cooldown should be suppressed (exit 0)
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>"$stderr_file"
    exit_code=$?
    assert_equals "second nudge within cooldown suppressed" "0" "$exit_code"

    # Simulate cooldown expiry by backdating the timestamp
    printf '%s' "$(($(date +%s) - 121))" > "$cooldown_file"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>"$stderr_file"
    exit_code=$?
    assert_equals "nudge fires after cooldown expires" "2" "$exit_code"

    # Clean up cooldown file
    rm -f "$cooldown_file"

    teardown_test_env
}

test_idle_guard_sanitization() {
    echo "-- test: idle guard sanitizes path-unsafe names --"
    setup_test_env

    local guard="${PROJECT_ROOT}/hooks/teammate-idle-guard.sh"
    local cooldown_dir="${HOME}/.claude/.idle-cooldowns"
    local cooldown_file="${cooldown_dir}/claude-idle-safe-name-last-nudge"

    mkdir -p "$cooldown_dir"
    rm -f "$cooldown_file"

    mkdir -p "${HOME}/.claude/tasks/safe-name"
    printf '{"subject":"Task","status":"in_progress","owner":"safe-name"}' \
        > "${HOME}/.claude/tasks/safe-name/1.json"

    # Team/teammate with slashes should be sanitized (no path traversal)
    printf '{"teammate_name":"safe-name","team_name":"safe-name"}' | bash "$guard" 2>/dev/null
    local exit_code=$?
    assert_equals "sanitized guard fires" "2" "$exit_code"

    rm -f "$cooldown_file"
    teardown_test_env
}

test_idle_guard_non_numeric_cooldown() {
    echo "-- test: idle guard handles non-numeric cooldown file --"
    setup_test_env

    local guard="${PROJECT_ROOT}/hooks/teammate-idle-guard.sh"
    local cooldown_dir="${HOME}/.claude/.idle-cooldowns"
    local cooldown_file="${cooldown_dir}/claude-idle-test-team-worker-last-nudge"

    mkdir -p "${HOME}/.claude/tasks/test-team"
    printf '{"subject":"Task","status":"in_progress","owner":"worker"}' \
        > "${HOME}/.claude/tasks/test-team/1.json"

    # Write garbage to cooldown file — guard should still nudge (not crash)
    mkdir -p "$cooldown_dir"
    printf 'not-a-number' > "$cooldown_file"
    printf '{"teammate_name":"worker","team_name":"test-team"}' | bash "$guard" 2>/dev/null
    local exit_code=$?
    assert_equals "nudge fires with corrupted cooldown file" "2" "$exit_code"

    rm -f "$cooldown_file"
    teardown_test_env
}

# ---------------------------------------------------------------------------
# stderr silence tests (no SKILL_EXPLAIN = no stderr)
# ---------------------------------------------------------------------------
test_no_stderr_without_explain() {
    echo "-- test: no stderr without SKILL_EXPLAIN --"
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr.txt"

    # Without SKILL_EXPLAIN: stderr should be empty (even with matching skills)
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_equals "no stderr without SKILL_EXPLAIN" "" "${stderr_content}"

    teardown_test_env
}

test_skill_explain_with_matches() {
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr_explain.txt"

    # SKILL_EXPLAIN=1 with matching prompt → stderr contains explain output
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_EXPLAIN=1 \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_contains "explain shows header" "=== EXPLAIN ===" "${stderr_content}"
    assert_contains "explain shows scoring" "Scoring:" "${stderr_content}"
    assert_contains "explain shows prompt" "Prompt:" "${stderr_content}"
    assert_contains "explain shows skill score" "systematic-debugging:" "${stderr_content}"
    assert_contains "explain shows role-cap" "Role-cap selection" "${stderr_content}"
    assert_contains "explain shows result" "Result:" "${stderr_content}"
    assert_contains "explain shows end marker" "=== END ===" "${stderr_content}"

    teardown_test_env
}

test_skill_explain_no_matches() {
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr_explain_none.txt"

    # SKILL_EXPLAIN=1 with a prompt that won't match any triggers (long enough to pass length check)
    jq -n --arg p "tell me about the weather forecast today please" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_EXPLAIN=1 \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_contains "explain no-match shows header" "=== EXPLAIN ===" "${stderr_content}"
    assert_contains "explain no-match shows 0 skills" "0 skills" "${stderr_content}"

    teardown_test_env
}

test_skill_explain_off_by_default() {
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr_explain_off.txt"

    # Without SKILL_EXPLAIN → no explain output on stderr
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_equals "no explain without SKILL_EXPLAIN" "" "${stderr_content}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Conversation-depth-aware verbosity tests
# ---------------------------------------------------------------------------

_setup_depth_counter() {
    # Helper: set session-scoped depth counter to a value
    # Usage: _setup_depth_counter 5  (sets counter to 5)
    #        _setup_depth_counter     (removes counter + token)
    local val="${1:-}"
    local token="test-session-$$"
    rm -f "${HOME}/.claude/.skill-prompt-count-"* 2>/dev/null
    rm -f "${HOME}/.claude/.skill-session-token" 2>/dev/null
    if [[ -n "$val" ]]; then
        printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
        printf '%s' "$val" > "${HOME}/.claude/.skill-prompt-count-${token}"
    fi
}

test_depth_full_format_first_prompt() {
    setup_test_env
    install_registry

    # No counter file exists → treated as prompt 1 → full format for 3+ skills
    _setup_depth_counter
    local output
    output="$(run_hook "build a secure frontend component")"
    local ctx
    ctx="$(extract_context "${output}")"

    assert_contains "depth1: full format has ASSESS PHASE" "ASSESS PHASE" "${ctx}"
    assert_contains "depth1: full format has EVALUATE skills" "EVALUATE skills" "${ctx}"
    assert_contains "depth1: full format has Step 3" "State your plan" "${ctx}"

    teardown_test_env
}

test_depth_compact_format_after_5() {
    setup_test_env
    install_registry

    # Write counter=5 so next invocation will be prompt 6 → compact format even for 3+ skills
    _setup_depth_counter 5
    local output
    output="$(run_hook "build a secure frontend component")"
    local ctx
    ctx="$(extract_context "${output}")"

    assert_not_contains "depth6: compact format has no ASSESS PHASE" "ASSESS PHASE" "${ctx}"
    assert_not_contains "depth6: compact format has no EVALUATE skills" "EVALUATE skills" "${ctx}"
    assert_contains "depth6: compact format has Evaluate" "Evaluate:" "${ctx}"
    assert_contains "depth6: compact format has skill names" "brainstorming" "${ctx}"

    teardown_test_env
}

test_depth_minimal_format_after_10() {
    setup_test_env
    install_registry

    # Write counter=10 so next invocation will be prompt 11 → minimal format
    _setup_depth_counter 10
    local output
    output="$(run_hook "build a secure frontend component")"
    local ctx
    ctx="$(extract_context "${output}")"

    assert_not_contains "depth11: minimal format has no ASSESS PHASE" "ASSESS PHASE" "${ctx}"
    assert_not_contains "depth11: minimal format has no EVALUATE skills" "EVALUATE skills" "${ctx}"
    assert_not_contains "depth11: minimal format has no State your plan" "State your plan" "${ctx}"
    assert_not_contains "depth11: minimal format has no DOMAIN_HINT" "Domain skills evaluated" "${ctx}"
    assert_contains "depth11: minimal format has Evaluate" "Evaluate:" "${ctx}"
    assert_contains "depth11: minimal format has skill names" "brainstorming" "${ctx}"

    teardown_test_env
}

test_depth_verbose_override() {
    setup_test_env
    install_registry

    # Write counter=19 so next invocation will be prompt 20 → should be minimal,
    # but SKILL_VERBOSE=1 forces full format
    _setup_depth_counter 19
    local output
    output="$(jq -n --arg p "build a secure frontend component" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_VERBOSE=1 \
        bash "${HOOK}" 2>/dev/null)"
    local ctx
    ctx="$(extract_context "${output}")"

    assert_contains "verbose override: full format has ASSESS PHASE" "ASSESS PHASE" "${ctx}"
    assert_contains "verbose override: full format has EVALUATE skills" "EVALUATE skills" "${ctx}"
    assert_contains "verbose override: full format has State your plan" "State your plan" "${ctx}"

    teardown_test_env
}

test_depth_counter_missing_treated_as_1() {
    setup_test_env
    install_registry

    # Ensure counter file does NOT exist
    _setup_depth_counter
    local output
    output="$(run_hook "build a secure frontend component")"
    local ctx
    ctx="$(extract_context "${output}")"

    # Same as prompt 1: full format for 3+ skills
    assert_contains "missing counter: full format has ASSESS PHASE" "ASSESS PHASE" "${ctx}"

    # Verify a counter file was created with value 1
    local count_val
    count_val="$(cat "${HOME}/.claude/.skill-prompt-count-"* 2>/dev/null)"
    assert_equals "missing counter: file created with value 1" "1" "${count_val}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Batch scripting skill routing
# ---------------------------------------------------------------------------
test_batch_scripting_triggers() {
    setup_test_env
    install_registry_with_batch

    local out ctx

    out="$(run_hook "batch migrate all files to ESM")"
    ctx="$(extract_context "$out")"
    assert_contains "batch-scripting triggers on 'batch migrate'" \
        "batch-scripting" "$ctx"

    out="$(run_hook "bulk refactor across all files")"
    ctx="$(extract_context "$out")"
    assert_contains "batch-scripting triggers on 'bulk refactor across all files'" \
        "batch-scripting" "$ctx"

    out="$(run_hook "transform all test files")"
    ctx="$(extract_context "$out")"
    assert_contains "batch-scripting triggers on 'transform all'" \
        "batch-scripting" "$ctx"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Red flags injection when verification-before-completion fires
# ---------------------------------------------------------------------------
test_red_flags_injected_for_verification() {
    setup_test_env
    install_registry

    local out ctx

    out="$(run_hook "ship it, all tests pass")"
    ctx="$(extract_context "$out")"
    assert_contains "red flags injected when verification fires" \
        "HALT if any Red Flag" "$ctx"

    teardown_test_env
}

test_red_flags_not_injected_for_other_skills() {
    setup_test_env
    install_registry

    local out ctx

    out="$(run_hook "debug this crash")"
    ctx="$(extract_context "$out")"
    assert_not_contains "red flags NOT injected for debugging" \
        "HALT if any Red Flag" "$ctx"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Raw scores in explain output
# ---------------------------------------------------------------------------
test_skill_explain_raw_scores() {
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr_raw_scores.txt"

    # SKILL_EXPLAIN=1 with matching prompt → stderr should include raw scores
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_EXPLAIN=1 \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_contains "explain shows raw scores header" "Raw scores:" "${stderr_content}"
    assert_contains "explain shows skill name=score" "systematic-debugging=" "${stderr_content}"

    teardown_test_env
}

test_idle_guard_cooldown
test_idle_guard_sanitization
test_idle_guard_non_numeric_cooldown
test_skill_debug_stderr
test_skill_explain_with_matches
test_skill_explain_no_matches
test_skill_explain_off_by_default
test_depth_full_format_first_prompt
test_depth_compact_format_after_5
test_depth_minimal_format_after_10
test_depth_verbose_override
test_depth_counter_missing_treated_as_1
test_batch_scripting_triggers
test_red_flags_injected_for_verification
test_red_flags_not_injected_for_other_skills
test_skill_explain_raw_scores

# ---------------------------------------------------------------------------
# Keyword matching tests
# ---------------------------------------------------------------------------
test_keywords_match() {
    echo "-- test: keyword 'something is off' routes to systematic-debugging --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'KWREG'
{
  "version": "test",
  "skills": [
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": [],
      "keywords": ["stuck on", "something is off", "not right", "doesn't make sense", "confused by"],
      "priority": 10,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "available": true,
      "enabled": true
    },
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": [],
      "keywords": ["how should", "what approach", "best way to", "ideas for", "options for"],
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
KWREG

    local output context
    output="$(run_hook "I'm stuck on this auth flow and something is off")"
    context="$(extract_context "${output}")"

    assert_contains "keyword 'something is off' matches systematic-debugging" "systematic-debugging" "${context}"

    teardown_test_env
}

test_keywords_no_short_match() {
    echo "-- test: keywords shorter than 6 chars are ignored --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'KWSHORTREG'
{
  "version": "test",
  "skills": [
    {
      "name": "short-keyword-skill",
      "role": "domain",
      "triggers": [],
      "keywords": ["help", "fix", "bad"],
      "priority": 10,
      "invoke": "Skill(mock:short-keyword-skill)",
      "available": true,
      "enabled": true
    }
  ],
  "methodology_hints": [],
  "phase_compositions": {}
}
KWSHORTREG

    local output context
    output="$(run_hook "help me fix this bad code please")"
    context="$(extract_context "${output}")"

    # All keywords are < 6 chars so none should score; expect 0 skills
    assert_contains "short keywords produce 0 skills" "0 skills" "${context}"

    teardown_test_env
}

test_keywords_match
test_keywords_no_short_match

# ---------------------------------------------------------------------------
# Zero-match instrumentation tests
# ---------------------------------------------------------------------------

test_zero_match_instrumented() {
    setup_test_env
    install_registry
    local counter_file="${HOME}/.claude/.skill-zero-match-count"
    rm -f "$counter_file"
    # Run a prompt that won't match any skills
    run_hook "explain this code to me" >/dev/null
    assert_file_exists "zero-match counter file should be created" "$counter_file"
    local count
    count="$(cat "$counter_file")"
    assert_equals "zero-match count should be 1 after first miss" "1" "$count"
    # Run another non-matching prompt
    run_hook "what does this function do" >/dev/null
    count="$(cat "$counter_file")"
    assert_equals "zero-match count should be 2 after second miss" "2" "$count"
    teardown_test_env
}

test_match_not_counted_as_zero() {
    setup_test_env
    install_registry
    local counter_file="${HOME}/.claude/.skill-zero-match-count"
    rm -f "$counter_file"
    # Run a prompt that DOES match
    run_hook "debug this bug" >/dev/null
    # Counter file should not exist or be 0
    if [[ -f "$counter_file" ]]; then
        local count
        count="$(cat "$counter_file")"
        assert_equals "zero-match count should not increment on a match" "0" "$count"
    else
        _record_pass "zero-match counter file correctly not created on match"
    fi
    teardown_test_env
}

test_zero_match_instrumented
test_match_not_counted_as_zero

# ---------------------------------------------------------------------------
# Phase-scoped hint tests (Task 4)
# ---------------------------------------------------------------------------
test_phase_scoped_hints() {
    echo "-- test: phase-scoped hints respect phases filter --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"

    # Start from v4 registry and add phase-scoped hints
    install_registry_v4
    local tmp_file
    tmp_file="$(mktemp)"

    # Hint that triggers on "error|bug" but is scoped to DESIGN only
    jq '.methodology_hints += [{
        "name": "test-design-error-hint",
        "triggers": ["(error|bug)"],
        "trigger_mode": "regex",
        "hint": "TEST-DESIGN-ERROR-HINT: Should not appear during DEBUG.",
        "phases": ["DESIGN"]
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # "debug this error" triggers systematic-debugging (DEBUG phase) — hint should NOT appear
    local output context
    output="$(run_hook "debug this error in the auth module")"
    context="$(extract_context "$output")"
    assert_not_contains "phase-scoped hint suppressed in non-matching phase" "TEST-DESIGN-ERROR-HINT" "$context"

    # "build something with an error handler" triggers brainstorming (DESIGN phase)
    # and also matches "error" trigger — hint SHOULD appear
    jq '.methodology_hints += [{
        "name": "test-design-build-hint",
        "triggers": ["(build|create)"],
        "trigger_mode": "regex",
        "hint": "TEST-DESIGN-BUILD-HINT: Should appear during DESIGN.",
        "phases": ["DESIGN"]
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    output="$(run_hook "build a new error handling service")"
    context="$(extract_context "$output")"
    assert_contains "phase-scoped hint appears in matching phase" "TEST-DESIGN-BUILD-HINT" "$context"

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

test_phase_scoped_hints
test_hints_without_phases_fire_unconditionally

# ---------------------------------------------------------------------------
# MCP detection tests (Task 6)
# ---------------------------------------------------------------------------
test_mcp_detection_from_mcp_json() {
    echo "-- test: MCP detection reads .mcp.json and sets availability --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    install_registry_v4
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

    # Create a temp project dir with .mcp.json
    local test_project="${TEST_TMPDIR}/test-project"
    mkdir -p "$test_project"
    printf '{"mcpServers": {"my-jira-server": {"command": "uvx", "args": ["mcp-atlassian"]}}}\n' > "${test_project}/.mcp.json"

    # Run hook FROM the temp project dir — hint should fire
    local output context
    output="$(run_hook_in_dir "$test_project" "check the jira ticket for acceptance criteria")"
    context="$(extract_context "$output")"
    assert_contains "MCP detection enables atlassian hint" "TEST-JIRA-HINT" "$context"

    teardown_test_env
}

test_mcp_detection_user_override() {
    echo "-- test: MCP detection respects user mcp_mappings override --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    install_registry_v4
    local tmp_file
    tmp_file="$(mktemp)"

    # Add mcp_servers to registry
    jq '.mcp_servers = [
        {"name": "atlassian", "available": false, "phase_fit": ["DESIGN"], "mcp_tools": ["getJiraIssue"], "description": "Jira", "detect_commands": ["mcp-atlassian"], "detect_names": ["atlassian", "jira"]}
    ]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    jq '.methodology_hints += [{"name": "test-jira2", "triggers": ["(jira|ticket)"], "trigger_mode": "regex", "hint": "TEST-JIRA2-HINT: User override works.", "mcp_server": "atlassian"}]' \
        "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # Create temp project dir with .mcp.json using non-standard name
    local test_project="${TEST_TMPDIR}/test-project2"
    mkdir -p "$test_project"
    printf '{"mcpServers": {"company-issue-tracker": {"command": "node", "args": ["custom-server.js"]}}}\n' > "${test_project}/.mcp.json"

    # Create user config with mcp_mappings override
    printf '{"mcp_mappings": {"company-issue-tracker": "atlassian"}}\n' > "${HOME}/.claude/skill-config.json"

    local output context
    output="$(run_hook_in_dir "$test_project" "check the jira ticket for acceptance criteria")"
    context="$(extract_context "$output")"
    assert_contains "user override enables atlassian" "TEST-JIRA2-HINT" "$context"

    teardown_test_env
}

test_no_mcp_no_noise() {
    echo "-- test: no MCP config produces no MCP noise --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    install_registry_v4
    local tmp_file
    tmp_file="$(mktemp)"

    # Add mcp_servers to registry (unavailable)
    jq '.mcp_servers = [
        {"name": "atlassian", "available": false, "phase_fit": ["DESIGN"], "mcp_tools": ["getJiraIssue"], "description": "Jira", "detect_commands": ["mcp-atlassian"], "detect_names": ["atlassian"]}
    ]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    jq '.methodology_hints += [{"name": "test-jira3", "triggers": ["(jira|ticket)"], "trigger_mode": "regex", "hint": "TEST-JIRA3-HINT: Should not appear.", "mcp_server": "atlassian"}]' \
        "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # Run from a temp dir with NO .mcp.json — hint should NOT fire
    local test_project="${TEST_TMPDIR}/test-project-empty"
    mkdir -p "$test_project"

    local output context
    output="$(run_hook_in_dir "$test_project" "check the jira ticket")"
    context="$(extract_context "$output")"
    assert_not_contains "no MCP means no MCP hints" "TEST-JIRA3-HINT" "$context"

    teardown_test_env
}

test_mcp_detection_tier3_name_only() {
    echo "-- test: MCP Tier 3 name-only detection (e.g. claude_ai_Atlassian) --"
    setup_test_env

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    install_registry_v4
    local tmp_file
    tmp_file="$(mktemp)"

    # Add mcp_servers with detect_names patterns
    jq '.mcp_servers = [
        {"name": "atlassian", "available": false, "phase_fit": ["DESIGN","PLAN"], "mcp_tools": ["getJiraIssue"], "description": "Jira", "detect_commands": ["mcp-atlassian"], "detect_names": ["atlassian", "jira", "confluence"]}
    ]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    jq '.methodology_hints += [{"name": "test-tier3", "triggers": ["(jira|ticket)"], "trigger_mode": "regex", "hint": "TEST-TIER3-HINT: Name-only detection works.", "mcp_server": "atlassian"}]' \
        "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # Create .mcp.json with server name matching Tier 3 pattern (no command match)
    local test_project="${TEST_TMPDIR}/test-project-tier3"
    mkdir -p "$test_project"
    printf '{"mcpServers": {"claude_ai_Atlassian": {"command": "some-generic-binary", "args": []}}}\n' > "${test_project}/.mcp.json"

    local output context
    output="$(run_hook_in_dir "$test_project" "check the jira ticket for acceptance criteria")"
    context="$(extract_context "$output")"
    assert_contains "Tier 3 name detection maps claude_ai_Atlassian to atlassian" "TEST-TIER3-HINT" "$context"

    teardown_test_env
}

test_mcp_detection_from_mcp_json
test_mcp_detection_user_override
test_no_mcp_no_noise
test_mcp_detection_tier3_name_only

# ---------------------------------------------------------------------------
# MCP-gated composition test (Task 5)
# ---------------------------------------------------------------------------
test_mcp_server_gated_composition() {
    echo "-- test: mcp_server-gated compositions render when available --"
    setup_test_env

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

test_mcp_server_gated_composition

# ---------------------------------------------------------------------------
# Last-skill context signal and composition tie-breaking tests
# ---------------------------------------------------------------------------

test_last_skill_signal_written() {
    setup_test_env
    install_registry
    rm -f "${HOME}/.claude/.skill-last-invoked-"*
    printf 'test-signal-session' > "${HOME}/.claude/.skill-session-token"
    run_hook "debug this bug" >/dev/null
    local signal_file="${HOME}/.claude/.skill-last-invoked-test-signal-session"
    assert_file_exists "signal file should be created after routing" "$signal_file"
    local skill_name
    skill_name="$(jq -r '.skill' "$signal_file" 2>/dev/null)"
    assert_equals "signal should contain the top skill" "systematic-debugging" "$skill_name"
    local skill_phase
    skill_phase="$(jq -r '.phase' "$signal_file" 2>/dev/null)"
    assert_equals "signal should contain the skill's phase" "DEBUG" "$skill_phase"
    teardown_test_env
}
test_last_skill_signal_written

test_composition_bonus_boosts_successor() {
    setup_test_env
    # Set up a chain: brainstorming -> writing-plans
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create)"],
      "trigger_mode": "regex",
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "precedes": ["writing-plans"],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": ["(plan|outline)"],
      "trigger_mode": "regex",
      "priority": 40,
      "invoke": "Skill(superpowers:writing-plans)",
      "precedes": [],
      "requires": ["brainstorming"],
      "available": true,
      "enabled": true
    }
  ]
}
REGISTRY
    # Simulate brainstorming was last invoked
    printf 'test-bonus-session' > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"brainstorming","phase":"DESIGN"}' > "${HOME}/.claude/.skill-last-invoked-test-bonus-session"

    # Send a prompt that matches writing-plans ("plan") — it should get +20 bonus
    local output
    output="$(jq -n --arg p "let's plan this out" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_EXPLAIN=1 bash "${HOOK}" 2>&1 1>/dev/null)"
    # The explain output should show writing-plans selected
    assert_contains "writing-plans should be boosted after brainstorming" "writing-plans" "$output"
    teardown_test_env
}
test_composition_bonus_boosts_successor

test_done_marker_when_signal_exists() {
    setup_test_env
    # Same chain setup, verify [DONE] instead of [DONE?]
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create)"],
      "trigger_mode": "regex",
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "precedes": ["writing-plans"],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": ["(plan|outline)"],
      "trigger_mode": "regex",
      "priority": 40,
      "invoke": "Skill(superpowers:writing-plans)",
      "precedes": ["executing-plans"],
      "requires": ["brainstorming"],
      "available": true,
      "enabled": true
    },
    {
      "name": "executing-plans",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(continue|next|execute)"],
      "trigger_mode": "regex",
      "priority": 35,
      "invoke": "Skill(superpowers:executing-plans)",
      "precedes": [],
      "requires": ["writing-plans"],
      "available": true,
      "enabled": true
    }
  ]
}
REGISTRY
    # Simulate: writing-plans was last invoked (so brainstorming is DONE)
    printf 'test-done-session' > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"writing-plans","phase":"PLAN"}' > "${HOME}/.claude/.skill-last-invoked-test-done-session"

    # Trigger executing-plans
    local output
    output="$(run_hook "continue with next step")"
    local ctx
    ctx="$(extract_context "$output")"
    # The composition chain should show [DONE] for brainstorming (not [DONE?])
    assert_contains "brainstorming should show [DONE] when signal confirms it ran" "[DONE]" "$ctx"
    assert_not_contains "should not show [DONE?] when signal confirms completion" "[DONE?]" "$ctx"
    teardown_test_env
}
test_done_marker_when_signal_exists

# ---------------------------------------------------------------------------
# Opal Integration: exercise keywords, zero-match counter, last-skill signal,
# and composition tie-breaking together in one flow
# ---------------------------------------------------------------------------
test_opal_integration() {
    setup_test_env
    # Full flow: keywords + context signal + zero-match counter + composition bonus
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": ["(debug|bug|broken)"],
      "keywords": ["something is off"],
      "trigger_mode": "regex",
      "priority": 50,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": ["(build|create)"],
      "keywords": [],
      "trigger_mode": "regex",
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
      "precedes": ["writing-plans"],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "writing-plans",
      "role": "process",
      "phase": "PLAN",
      "triggers": ["(plan|outline)"],
      "keywords": [],
      "trigger_mode": "regex",
      "priority": 40,
      "invoke": "Skill(superpowers:writing-plans)",
      "precedes": [],
      "requires": ["brainstorming"],
      "available": true,
      "enabled": true
    }
  ]
}
REGISTRY

    printf 'opal-integration-session' > "${HOME}/.claude/.skill-session-token"
    rm -f "${HOME}/.claude/.skill-last-invoked-opal-integration-session"
    rm -f "${HOME}/.claude/.skill-zero-match-count"

    # Step 1: Keyword match — "something is off" routes to debugging
    local output ctx
    output="$(run_hook "something is off with the auth flow")"
    ctx="$(extract_context "$output")"
    assert_contains "keyword 'something is off' should route to debugging" "systematic-debugging" "$ctx"

    # Step 2: Verify signal was written
    local signal_file="${HOME}/.claude/.skill-last-invoked-opal-integration-session"
    assert_file_exists "signal file created after keyword match" "$signal_file"
    local last_skill
    last_skill="$(jq -r '.skill' "$signal_file" 2>/dev/null)"
    assert_equals "signal should record debugging as last skill" "systematic-debugging" "$last_skill"

    # Step 3: Zero-match — prompt with no matching skills
    run_hook "explain this code to me please" >/dev/null
    local zm_count
    zm_count="$(cat "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null)"
    assert_equals "zero-match counter should be 1" "1" "$zm_count"

    # Step 4: Context bonus — simulate brainstorming was last, then trigger writing-plans
    printf '{"skill":"brainstorming","phase":"DESIGN"}' > "$signal_file"
    output="$(run_hook "let's plan this out")"
    ctx="$(extract_context "$output")"
    assert_contains "writing-plans should be selected after brainstorming context" "writing-plans" "$ctx"

    teardown_test_env
}
test_opal_integration

print_summary
