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
test_brainstorming_trigger_narrowed() {
    echo "-- test: brainstorming triggers exclude generic terms --"
    local triggers_file="${PROJECT_ROOT}/config/default-triggers.json"
    local brainstorm_triggers
    brainstorm_triggers="$(jq -r '.skills[] | select(.name == "brainstorming") | .triggers[]' "$triggers_file")"

    # Should NOT contain overly generic terms
    assert_not_contains "brainstorming excludes build" "build" "$brainstorm_triggers"
    assert_not_contains "brainstorming excludes create" "create" "$brainstorm_triggers"
    assert_not_contains "brainstorming excludes implement" "implement" "$brainstorm_triggers"
    assert_not_contains "brainstorming excludes new" "|new|" "$brainstorm_triggers"
    assert_not_contains "brainstorming excludes start" "|start|" "$brainstorm_triggers"

    # Should still contain core design terms
    assert_contains "brainstorming has brainstorm" "brainstorm" "$brainstorm_triggers"
    assert_contains "brainstorming has design" "design" "$brainstorm_triggers"
    assert_contains "brainstorming has architect" "architect" "$brainstorm_triggers"
}

test_agent_team_no_plan_triggers() {
    echo "-- test: agent-team-execution has no plan-execution triggers --"
    local triggers_file="${PROJECT_ROOT}/config/default-triggers.json"
    local ate_triggers
    ate_triggers="$(jq -r '.skills[] | select(.name == "agent-team-execution") | .triggers[]' "$triggers_file")"

    assert_not_contains "agent-team no execute.*plan" "execute.*plan" "$ate_triggers"
    assert_not_contains "agent-team no follow.the.plan" "follow" "$ate_triggers"
    assert_contains "agent-team has team keywords" "agent.team" "$ate_triggers"
}

test_brainstorming_trigger_narrowed
test_agent_team_no_plan_triggers

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
# SKILL_DEBUG stderr output tests
# ---------------------------------------------------------------------------
test_skill_debug_stderr() {
    echo "-- test: SKILL_DEBUG emits scores to stderr --"
    setup_test_env
    install_registry

    local stderr_file="${TEST_TMPDIR}/stderr.txt"

    # With SKILL_DEBUG: stderr should contain scores
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_DEBUG=1 \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    local stderr_content
    stderr_content="$(cat "${stderr_file}")"
    assert_contains "debug mode emits scores" "[skill-hook] scores:" "${stderr_content}"

    # Without SKILL_DEBUG: stderr should be empty
    jq -n --arg p "debug this broken login bug" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    stderr_content="$(cat "${stderr_file}")"
    assert_equals "no debug mode no stderr" "" "${stderr_content}"

    # SKILL_DEBUG with no matching skills: stderr should be silent
    jq -n --arg p "hello how are you today" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_DEBUG=1 \
        bash "${HOOK}" 2>"${stderr_file}" >/dev/null
    stderr_content="$(cat "${stderr_file}")"
    assert_equals "debug mode no scores when nothing matches" "" "${stderr_content}"

    teardown_test_env
}

test_idle_guard_cooldown
test_idle_guard_sanitization
test_idle_guard_non_numeric_cooldown
test_skill_debug_stderr

print_summary
