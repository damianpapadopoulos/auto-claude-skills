#!/usr/bin/env bash
# test-context.sh — Tests for adaptive context injection output format
# Bash 3.2 compatible. Sources test-helpers.sh for setup/teardown and assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-context.sh ==="

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

# ---------------------------------------------------------------------------
# Registry with varied skills: process, domain, workflow, superpowers invoke
# ---------------------------------------------------------------------------
install_context_registry() {
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
        "(debug|bug|fix|broken|fail|error|crash|wrong|unexpected|not.work|regression|issue|problem)"
      ],
      "trigger_mode": "regex",
      "priority": 10,
      "invoke": "Skill(superpowers:systematic-debugging)",
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
      "name": "security-scanner",
      "role": "domain",
      "triggers": [
        "(secur(e|ity)|vulnerab|owasp|pentest|attack|exploit|encrypt|inject|xss|csrf)"
      ],
      "trigger_mode": "regex",
      "priority": 102,
      "invoke": "Skill(superpowers:security-scanner)",
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
      "invoke": "Skill(superpowers:frontend-design)",
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
    }
  ],
  "methodology_hints": [],
  "phase_guide": {
    "DESIGN":    "brainstorming (ask questions, get approval)",
    "PLAN":      "writing-plans (break into tasks, confirm before execution)",
    "IMPLEMENT": "executing-plans or subagent-driven-development + TDD",
    "REVIEW":    "requesting-code-review",
    "SHIP":      "verification-before-completion + finishing-a-development-branch",
    "DEBUG":     "systematic-debugging, then return to current phase"
  },
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
# Registry with composition chain skills: brainstorming -> writing-plans -> executing-plans
# ---------------------------------------------------------------------------
install_registry() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    cat > "${cache_file}" <<'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": [
        "(build|create|implement|develop|scaffold|brainstorm|design|architect|add|write|make|generate|new|start)"
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
      "triggers": [
        "(plan|outline|break.?down|detail|spec|write.*(plan|spec))"
      ],
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
    }
  ],
  "methodology_hints": [],
  "phase_guide": {
    "DESIGN":    "brainstorming (ask questions, get approval)",
    "PLAN":      "writing-plans (break into tasks, confirm before execution)",
    "IMPLEMENT": "executing-plans or subagent-driven-development + TDD"
  },
  "warnings": []
}
REGISTRY
}

# ---------------------------------------------------------------------------
# 1. 0 skills -> silent (no output at all)
# ---------------------------------------------------------------------------
test_zero_skills_minimal_output() {
    echo "-- test: 0 skills -> silent (no output) --"
    setup_test_env
    install_context_registry

    local output
    output="$(run_hook "tell me about the weather forecast for tomorrow please")"

    if [[ -z "$output" ]]; then
        _record_pass "0 skills produces empty output"
    else
        _record_fail "0 skills produces empty output" "got: ${output}"
    fi

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 2. 1 skill -> compact format (Process: and Evaluate:, no Step 1)
# ---------------------------------------------------------------------------
test_single_skill_compact_format() {
    echo "-- test: 1 skill -> compact format --"
    setup_test_env
    install_context_registry

    # "debug" triggers systematic-debugging only (1 process skill)
    local output
    output="$(run_hook "I need to debug this crash in the auth module")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "1 skill has Process:" "Process:" "${context}"
    assert_contains "1 skill has Evaluate:" "Evaluate:" "${context}"
    assert_not_contains "1 skill does NOT have Step 1" "Step 1" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 3. Process + domain -> Domain:
# ---------------------------------------------------------------------------
test_process_domain_informed_by() {
    echo "-- test: process + domain -> Domain: --"
    setup_test_env
    install_context_registry

    # "build a secure" triggers brainstorming (process) + security-scanner (domain)
    local output
    output="$(run_hook "build a secure authentication service with encryption")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "process+domain has Domain:" "Domain:" "${context}"
    assert_contains "process+domain has Process:" "Process:" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 4. 3+ skills -> full format with phase map
# ---------------------------------------------------------------------------
test_many_skills_full_format() {
    echo "-- test: 3+ skills -> full format with phase map --"
    setup_test_env
    install_context_registry

    # "build a secure frontend dashboard" triggers:
    #   brainstorming (process, prio 30), test-driven-development (process, prio 20),
    #   security-scanner (domain, prio 102), frontend-design (domain, prio 101)
    # After role caps: 1 process + 2 domain = 3 selected -> full format
    local output
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "3+ skills has Step 1" "Step 1" "${context}"
    assert_contains "3+ skills has MANDATORY" "MANDATORY" "${context}"
    assert_contains "3+ skills has DESIGN phase" "DESIGN" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 5. Invocation hints contain Skill(superpowers:
# ---------------------------------------------------------------------------
test_invocation_hints_present() {
    echo "-- test: invocation hints contain Skill(superpowers: --"
    setup_test_env
    install_context_registry

    local output
    output="$(run_hook "I need to debug this crash in the auth module")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "invocation hint present" "Skill(superpowers:" "${context}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 6. Output is valid hook JSON
# ---------------------------------------------------------------------------
test_output_valid_json_zero_match() {
    echo "-- test: 0-match output is empty (no JSON emitted) --"
    setup_test_env
    install_context_registry

    local output
    output="$(run_hook "tell me about the weather forecast for tomorrow please")"

    if [[ -z "$output" ]]; then
        _record_pass "0-match output is empty (no JSON emitted)"
    else
        _record_fail "0-match output is empty (no JSON emitted)" "got: ${output}"
    fi

    teardown_test_env
}

test_output_valid_json_single_match() {
    echo "-- test: single-match output is valid JSON --"
    setup_test_env
    install_context_registry

    local output
    output="$(run_hook "I need to debug this crash in the auth module")"
    local tmpfile="${TEST_TMPDIR}/output-single.json"
    printf '%s' "${output}" > "${tmpfile}"
    assert_json_valid "single-match output is valid JSON" "${tmpfile}"

    teardown_test_env
}

test_output_valid_json_multi_match() {
    echo "-- test: multi-match output is valid JSON --"
    setup_test_env
    install_context_registry

    local output
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    local tmpfile="${TEST_TMPDIR}/output-multi.json"
    printf '%s' "${output}" > "${tmpfile}"
    assert_json_valid "multi-match output is valid JSON" "${tmpfile}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 7. Full format lists Process: before Domain:
# ---------------------------------------------------------------------------
test_full_format_process_first() {
    echo "-- test: full format lists Process before Domain --"
    setup_test_env
    install_context_registry

    local output context
    output="$(run_hook "build a secure frontend dashboard component with csrf protection")"
    context="$(extract_context "${output}")"

    # Process: line should appear before any Domain: line
    local process_pos domain_pos
    process_pos="$(printf '%s' "${context}" | grep -n 'Process:' | head -1 | cut -d: -f1)"
    domain_pos="$(printf '%s' "${context}" | grep -n 'Domain:' | head -1 | cut -d: -f1)"

    if [[ -n "$process_pos" ]] && [[ -n "$domain_pos" ]]; then
        if [[ "$process_pos" -lt "$domain_pos" ]]; then
            _record_pass "Process: appears before Domain:"
        else
            _record_fail "Process: appears before Domain:" "Process at line ${process_pos}, Domain at line ${domain_pos}"
        fi
    else
        _record_fail "Process: appears before Domain:" "Missing Process: or Domain: line"
    fi

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 8. Composition state written to file
# ---------------------------------------------------------------------------
test_composition_state_written() {
    echo "-- test: composition state written to file --"
    setup_test_env
    install_registry

    printf 'comp-test-session' > "${HOME}/.claude/.skill-session-token"
    # Simulate brainstorming was invoked last
    printf '{"skill":"brainstorming","phase":"DESIGN"}' > "${HOME}/.claude/.skill-last-invoked-comp-test-session"

    # Trigger writing-plans (next in chain)
    run_hook "let's plan this out and write a detailed plan" >/dev/null

    local state_file="${HOME}/.claude/.skill-composition-state-comp-test-session"
    assert_file_exists "composition state file should be created" "$state_file"

    # Verify JSON structure
    local chain_len
    chain_len="$(jq '.chain | length' "$state_file" 2>/dev/null)"
    if [[ "$chain_len" -ge 2 ]]; then
        _record_pass "composition state should have chain with 2+ skills"
    else
        _record_fail "composition state should have chain with 2+ skills" "got chain length: ${chain_len}"
    fi

    # Verify completed array exists
    local has_completed
    has_completed="$(jq 'has("completed")' "$state_file" 2>/dev/null)"
    assert_equals "state should have completed field" "true" "$has_completed"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 9. Composition recovery after compaction
# ---------------------------------------------------------------------------
test_composition_recovery_after_compaction() {
    echo "-- test: composition recovery after compaction --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    printf 'recovery-test-session' > "${HOME}/.claude/.skill-session-token"

    # Create a composition state file
    cat > "${HOME}/.claude/.skill-composition-state-recovery-test-session" <<'COMP'
{"chain":["brainstorming","writing-plans","executing-plans"],"current_index":1,"completed":["brainstorming"],"updated_at":"2026-03-09T14:30:00Z"}
COMP

    # Run the compact-recovery hook (pipe empty JSON as stdin)
    local output
    output="$(echo '{}' | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/compact-recovery-hook.sh" 2>/dev/null)"

    assert_contains "recovery should show composition header" "Composition Recovery" "$output"
    assert_contains "recovery should show chain" "brainstorming -> writing-plans -> executing-plans" "$output"
    assert_contains "recovery should show completed" "brainstorming" "$output"
    assert_contains "recovery should show current step" "writing-plans" "$output"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 10. Composition DONE vs DONE? uses persisted state
# ---------------------------------------------------------------------------
test_composition_done_not_done_question() {
    echo "-- test: composition DONE uses persisted state --"
    setup_test_env
    install_registry

    printf 'done-test-session' > "${HOME}/.claude/.skill-session-token"

    # Create composition state showing brainstorming is confirmed complete
    cat > "${HOME}/.claude/.skill-composition-state-done-test-session" <<'COMP'
{"chain":["brainstorming","writing-plans","executing-plans"],"current_index":1,"completed":["brainstorming"],"updated_at":"2026-03-09T14:30:00Z"}
COMP

    # Simulate brainstorming was last invoked
    printf '{"skill":"brainstorming","phase":"DESIGN"}' > "${HOME}/.claude/.skill-last-invoked-done-test-session"

    # Trigger writing-plans (next in chain after brainstorming)
    local output ctx
    output="$(run_hook "let's write the implementation plan now")"
    ctx="$(extract_context "$output")"

    # Should show [DONE] not [DONE?] for brainstorming
    assert_contains "brainstorming should be marked DONE" "[DONE]" "$ctx"
    assert_not_contains "should not show DONE?" "[DONE?]" "$ctx"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 11. Unified context stack PARALLEL emission
# ---------------------------------------------------------------------------
install_registry_with_context_stack() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    # Use the actual default-triggers.json but inject available flags
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null >/dev/null
    # Mark unified-context-stack as available and key process skills as available
    # so the routing hook emits output (TOTAL_COUNT>0 is required for hints to appear)
    local tmp="${cache_file}.tmp"
    jq '.plugins |= map(if .name == "unified-context-stack" then .available = true else . end) |
        .context_capabilities = {context7:true,context_hub_cli:false,context_hub_available:true,serena:false,forgetful_memory:false} |
        .skills |= map(
            if .name == "brainstorming" then . + {available:true, enabled:true, invoke:"Skill(superpowers:brainstorming)"}
            elif .name == "test-driven-development" then . + {available:true, enabled:true, invoke:"Skill(superpowers:test-driven-development)"}
            elif .name == "systematic-debugging" then . + {available:true, enabled:true, invoke:"Skill(superpowers:systematic-debugging)"}
            else . end
        )' \
        "${cache_file}" > "${tmp}" && mv "${tmp}" "${cache_file}"
}

test_context_stack_parallel_emission() {
    echo "-- test: unified-context-stack emits PARALLEL line --"
    setup_test_env
    install_registry_with_context_stack

    # "build a new stripe integration" should trigger DESIGN phase
    local output ctx
    output="$(run_hook "build a new stripe payment integration for our app")"
    ctx="$(extract_context "${output}")"

    assert_contains "context stack PARALLEL emitted" "unified-context-stack" "${ctx}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# 12. Unified context stack hint emission
# ---------------------------------------------------------------------------
test_context_stack_hint_emission() {
    echo "-- test: unified-context-stack-hint fires on library keywords --"
    setup_test_env
    install_registry_with_context_stack

    # "upgrade the stripe library" has library keyword
    local output ctx
    output="$(run_hook "upgrade the stripe library to the latest version")"
    ctx="$(extract_context "${output}")"

    assert_contains "context stack hint emitted" "CONTEXT STACK" "${ctx}"

    teardown_test_env
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
test_zero_skills_minimal_output
test_single_skill_compact_format
test_process_domain_informed_by
test_many_skills_full_format
test_invocation_hints_present
test_output_valid_json_zero_match
test_output_valid_json_single_match
test_output_valid_json_multi_match
test_full_format_process_first
test_composition_state_written
test_composition_recovery_after_compaction
test_composition_done_not_done_question
test_context_stack_parallel_emission
test_context_stack_hint_emission

print_summary
