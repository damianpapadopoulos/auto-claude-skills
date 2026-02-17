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
    printf '{"prompt":"%s"}' "${prompt}" | \
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
  "version": "3.0.0",
  "skills": [
    {
      "name": "systematic-debugging",
      "role": "process",
      "phase": "DEBUG",
      "triggers": [
        "(debug|bug|fix|broken|fail|error|crash|wrong|unexpected|not.work|regression|issue|problem)"
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
        "(build|create|implement|develop|scaffold|brainstorm|design|architect|add|write|make|generate|new|start)"
      ],
      "trigger_mode": "regex",
      "priority": 30,
      "invoke": "Skill(superpowers:brainstorming)",
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
      "priority": 50,
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
      "priority": 51,
      "invoke": "Skill(superpowers:receiving-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "verification-before-completion",
      "role": "workflow",
      "triggers": [
        "(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"
      ],
      "trigger_mode": "regex",
      "priority": 60,
      "invoke": "Skill(superpowers:verification-before-completion)",
      "available": true,
      "enabled": true
    },
    {
      "name": "finishing-a-development-branch",
      "role": "workflow",
      "triggers": [
        "(ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|finalize|complete|finish)"
      ],
      "trigger_mode": "regex",
      "priority": 61,
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
        "(ui|frontend|component|layout|style|css|tailwind|responsive|dashboard)"
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
        "(agent.team|team.execute|parallel.team|swarm|execute.*plan|run.the.plan|implement.the.plan|implement.*(rest|remaining)|continue|follow.the.plan|pick.up|resume|next.task|next.step|carry.on|keep.going|where.were.we|what.s.next)"
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
        "(build|create|implement|develop|scaffold|brainstorm|design|architect|strateg|scope|outline|approach|add|write|make|generate|set.?up|install|configure|integrate|extend|new|start)"
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
      "hint": "PR REVIEW: Consider /pr-review for structured review."
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
# 6. Domain skill appears alongside process skill with INFORMED BY
# ---------------------------------------------------------------------------
test_domain_informed_by() {
    echo "-- test: domain skill shows INFORMED BY --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    local context
    context="$(extract_context "${output}")"

    # Should have a process skill (brainstorming for "build")
    assert_contains "has process skill" "Process:" "${context}"
    # Should have domain skill as INFORMED BY
    assert_contains "has INFORMED BY" "INFORMED BY:" "${context}"
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
    echo "-- test: methodology hints appended when matched --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "review this pull request for code quality issues")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "PR review hint present" "PR REVIEW" "${context}"

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
# 16. Design-debate appears as INFORMED BY domain skill
# ---------------------------------------------------------------------------
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
test_teammate_idle_guard

print_summary
