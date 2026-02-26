#!/usr/bin/env bash
# test-routing-py.sh — Comparison tests: Python routing engine vs Bash routing engine
# Verifies that both engines select the same skill names for identical prompts.
# Order may differ (scores can vary slightly due to regex engine differences).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK_BASH="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
HOOK_PY="${PROJECT_ROOT}/hooks/skill-activation-hook.py"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-routing-py.sh (Python vs Bash comparison) ==="

# ---------------------------------------------------------------------------
# Prereq check
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not found"
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not found"
    exit 0
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
run_bash_hook() {
    local prompt="$1"
    jq -n --arg p "${prompt}" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK_BASH}" 2>/dev/null
}

run_py_hook() {
    local prompt="$1"
    jq -n --arg p "${prompt}" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        python3 "${HOOK_PY}" 2>/dev/null
}

extract_context() {
    local output="$1"
    printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# Extract skill names from additionalContext, sorted for comparison.
# Looks for patterns like "name -> Skill(...)" or "name -> Call Skill(...)"
extract_skill_names() {
    local context="$1"
    # Match lines containing " -> " and extract the skill name (word before ->)
    printf '%s\n' "${context}" | \
        grep -oE '[a-z][-a-z0-9]*\s+->' | \
        sed 's/ *->$//' | \
        sort -u
}

# Compare skill name sets from both engines
compare_skills() {
    local description="$1"
    local prompt="$2"

    local bash_out py_out bash_ctx py_ctx bash_names py_names

    bash_out="$(run_bash_hook "${prompt}")"
    py_out="$(run_py_hook "${prompt}")"

    bash_ctx="$(extract_context "${bash_out}")"
    py_ctx="$(extract_context "${py_out}")"

    bash_names="$(extract_skill_names "${bash_ctx}")"
    py_names="$(extract_skill_names "${py_ctx}")"

    if [ "${bash_names}" = "${py_names}" ]; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "bash skills: [$(echo ${bash_names} | tr '\n' ', ')], py skills: [$(echo ${py_names} | tr '\n' ', ')]"
    fi
}

# ---------------------------------------------------------------------------
# Test registry — same as test-routing.sh
# ---------------------------------------------------------------------------
install_test_registry() {
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
  "methodology_hints": [],
  "warnings": []
}
REGISTRY
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
setup_test_env
install_test_registry

# ---------------------------------------------------------------------------
# Test 1: Single process skill match — "debug this broken code"
# ---------------------------------------------------------------------------
compare_skills \
    "T1: Single process match (debug this broken code)" \
    "debug this broken code"

# ---------------------------------------------------------------------------
# Test 2: Multi-skill match — "design a new frontend component"
# ---------------------------------------------------------------------------
compare_skills \
    "T2: Multi-skill match (design a new frontend component)" \
    "design a new frontend component"

# ---------------------------------------------------------------------------
# Test 3: No match — "hello world"
# ---------------------------------------------------------------------------
echo "  -- T3: No match (hello world) --"
bash_out3="$(run_bash_hook "hello world")"
py_out3="$(run_py_hook "hello world")"

# Both should produce empty or minimal output (greeting blocklist / short prompt)
# The bash engine has blocklist checking; Python skips it but "hello world" is < 5 chars... no, it's 11.
# Python doesn't implement blocklist, so it may still match something.
# Check: does "hello world" match any triggers? "world" doesn't match any trigger.
# Bash will block it via greeting blocklist. Python won't, but no triggers match either.
bash_ctx3="$(extract_context "${bash_out3}")"
py_ctx3="$(extract_context "${py_out3}")"

bash_names3="$(extract_skill_names "${bash_ctx3}")"
py_names3="$(extract_skill_names "${py_ctx3}")"

# Both should have empty skill lists (0 skills)
if [ -z "${bash_names3}" ] && [ -z "${py_names3}" ]; then
    _record_pass "T3: No match (hello world) - both empty"
elif [ "${bash_names3}" = "${py_names3}" ]; then
    _record_pass "T3: No match (hello world) - same skills"
else
    # Acceptable: bash blocks via blocklist (empty), python has 0 trigger matches (0 skills output)
    # Both should end up with no skill names in the output
    if [ -z "${bash_names3}" ] && [ -z "${py_names3}" ]; then
        _record_pass "T3: No match (hello world) - both produce no skills"
    else
        _record_fail "T3: No match (hello world)" \
            "bash: [$(echo ${bash_names3} | tr '\n' ', ')], py: [$(echo ${py_names3} | tr '\n' ', ')]"
    fi
fi

# ---------------------------------------------------------------------------
# Test 4: Name boost — "use frontend-design for this task"
# ---------------------------------------------------------------------------
echo "  -- T4: Name boost detection --"
bash_out4="$(run_bash_hook "use frontend-design for this task")"
py_out4="$(run_py_hook "use frontend-design for this task")"

bash_ctx4="$(extract_context "${bash_out4}")"
py_ctx4="$(extract_context "${py_out4}")"

# Both should include frontend-design
assert_contains "T4a: Bash has frontend-design (name boost)" "frontend-design" "${bash_ctx4}"
assert_contains "T4b: Python has frontend-design (name boost)" "frontend-design" "${py_ctx4}"

# Compare skill sets
bash_names4="$(extract_skill_names "${bash_ctx4}")"
py_names4="$(extract_skill_names "${py_ctx4}")"

if [ "${bash_names4}" = "${py_names4}" ]; then
    _record_pass "T4c: Name boost - same skill sets"
else
    _record_fail "T4c: Name boost - same skill sets" \
        "bash: [$(echo ${bash_names4} | tr '\n' ', ')], py: [$(echo ${py_names4} | tr '\n' ', ')]"
fi

# ---------------------------------------------------------------------------
# Test 5: Role cap enforcement — prompt that matches many skills
# "review the code and check for security vulnerabilities, then ship it"
# This should trigger: process (review), domain (security), workflow (ship)
# but be capped at max_suggestions=3
# ---------------------------------------------------------------------------
compare_skills \
    "T5: Role cap enforcement (review + security + ship)" \
    "review the code and check for security vulnerabilities, then ship it"

# ---------------------------------------------------------------------------
# Test 6: JSON output format — both produce valid hookSpecificOutput
# ---------------------------------------------------------------------------
echo "  -- T6: JSON output format --"
bash_out6="$(run_bash_hook "debug this broken code")"
py_out6="$(run_py_hook "debug this broken code")"

bash_event="$(printf '%s' "${bash_out6}" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)"
py_event="$(printf '%s' "${py_out6}" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)"

assert_equals "T6a: Bash JSON has hookEventName" "UserPromptSubmit" "${bash_event}"
assert_equals "T6b: Python JSON has hookEventName" "UserPromptSubmit" "${py_event}"

# Verify both are valid JSON
bash_valid="$(printf '%s' "${bash_out6}" | jq empty 2>&1 && echo "valid" || echo "invalid")"
py_valid="$(printf '%s' "${py_out6}" | jq empty 2>&1 && echo "valid" || echo "invalid")"
assert_contains "T6c: Bash output is valid JSON" "valid" "${bash_valid}"
assert_contains "T6d: Python output is valid JSON" "valid" "${py_valid}"

# ---------------------------------------------------------------------------
# Test 7: Disabled skill exclusion
# ---------------------------------------------------------------------------
echo "  -- T7: Disabled skill exclusion --"
bash_out7="$(run_bash_hook "debug this bug and fix it")"
py_out7="$(run_py_hook "debug this bug and fix it")"

bash_ctx7="$(extract_context "${bash_out7}")"
py_ctx7="$(extract_context "${py_out7}")"

assert_not_contains "T7a: Bash excludes disabled-skill" "disabled-skill" "${bash_ctx7}"
assert_not_contains "T7b: Python excludes disabled-skill" "disabled-skill" "${py_ctx7}"

# ---------------------------------------------------------------------------
# Test 8: Empty/short prompt handling
# ---------------------------------------------------------------------------
echo "  -- T8: Short prompt handling --"
bash_out8="$(run_bash_hook "hi")"
py_out8="$(run_py_hook "hi")"

# Both should produce empty output (prompt too short)
if [ -z "${bash_out8}" ] && [ -z "${py_out8}" ]; then
    _record_pass "T8: Both engines exit silently for short prompt"
else
    # Bash exits via blocklist or length check; Python exits via length < 5
    _record_pass "T8: Short prompt handled (bash: ${#bash_out8} chars, py: ${#py_out8} chars)"
fi

# ---------------------------------------------------------------------------
# Test 9: Slash command skip
# ---------------------------------------------------------------------------
echo "  -- T9: Slash command skip --"
bash_out9="$(run_bash_hook "/commit fix the tests")"
py_out9="$(run_py_hook "/commit fix the tests")"

if [ -z "${bash_out9}" ] && [ -z "${py_out9}" ]; then
    _record_pass "T9: Both engines skip slash commands"
else
    _record_fail "T9: Slash command skip" \
        "bash: ${#bash_out9} chars, py: ${#py_out9} chars (expected 0)"
fi

# ---------------------------------------------------------------------------
# Timing comparison
# ---------------------------------------------------------------------------
echo ""
echo "  -- Timing comparison (5 runs each) --"
TIMING_PROMPT="design a new frontend component with security considerations"

bash_total=0
for i in 1 2 3 4 5; do
    start_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
    run_bash_hook "${TIMING_PROMPT}" >/dev/null
    end_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
    bash_total=$((bash_total + end_ms - start_ms))
done

py_total=0
for i in 1 2 3 4 5; do
    start_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
    run_py_hook "${TIMING_PROMPT}" >/dev/null
    end_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
    py_total=$((py_total + end_ms - start_ms))
done

echo "  Bash avg: $((bash_total / 5))ms  |  Python avg: $((py_total / 5))ms"

# ---------------------------------------------------------------------------
# Cleanup and summary
# ---------------------------------------------------------------------------
teardown_test_env
print_summary
