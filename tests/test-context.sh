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
    printf '{"prompt":"%s"}' "${prompt}" | \
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
  "version": "2.0.0",
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
# 1. 0 skills -> minimal output (phase checkpoint, no Step 2)
# ---------------------------------------------------------------------------
test_zero_skills_minimal_output() {
    echo "-- test: 0 skills -> minimal output --"
    setup_test_env
    install_context_registry

    local output
    output="$(run_hook "tell me about the weather forecast for tomorrow please")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "0 skills has phase checkpoint" "phase checkpoint" "$(printf '%s' "${context}" | tr '[:upper:]' '[:lower:]')"
    assert_not_contains "0 skills does NOT have Step 2" "Step 2" "${context}"
    assert_contains "0 skills mentions 0 skills" "0 skills" "${context}"

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
# 3. Process + domain -> INFORMED BY
# ---------------------------------------------------------------------------
test_process_domain_informed_by() {
    echo "-- test: process + domain -> INFORMED BY --"
    setup_test_env
    install_context_registry

    # "build a secure" triggers brainstorming (process) + security-scanner (domain)
    local output
    output="$(run_hook "build a secure authentication service with encryption")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "process+domain has INFORMED BY" "INFORMED BY" "${context}"
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
    echo "-- test: 0-match output is valid JSON --"
    setup_test_env
    install_context_registry

    local output
    output="$(run_hook "tell me about the weather forecast for tomorrow please")"
    local tmpfile="${TEST_TMPDIR}/output-zero.json"
    printf '%s' "${output}" > "${tmpfile}"
    assert_json_valid "0-match output is valid JSON" "${tmpfile}"

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

print_summary
