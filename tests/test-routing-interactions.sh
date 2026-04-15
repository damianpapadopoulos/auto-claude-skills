#!/usr/bin/env bash
# test-routing-interactions.sh — Collision detection for overlapping trigger patterns
# Validates that prompts route to the INTENDED skill, not a higher-priority collision
# Uses the same harness as test-routing.sh: JSON input, hookSpecificOutput extraction

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-routing-interactions.sh ==="

# ---------------------------------------------------------------------------
# Helpers (same contract as test-routing.sh)
# ---------------------------------------------------------------------------
run_hook() {
    local prompt="$1"
    jq -n --arg p "${prompt}" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>/dev/null
}

extract_context() {
    local output="$1"
    printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

section() {
    echo ""
    echo "--- $1 ---"
}

# Helper: assert skill name appears in activation context
assert_activates() {
    local desc="$1" prompt="$2" expected="$3"
    setup_test_env
    install_registry
    local output context
    output="$(run_hook "${prompt}")"
    context="$(extract_context "${output}")"
    assert_contains "${desc}" "${expected}" "${context}"
    teardown_test_env
}

# Helper: assert skill name does NOT appear in activation context
assert_does_not_activate() {
    local desc="$1" prompt="$2" excluded="$3"
    setup_test_env
    install_registry
    local output context
    output="$(run_hook "${prompt}")"
    context="$(extract_context "${output}")"
    assert_not_contains "${desc}" "${excluded}" "${context}"
    teardown_test_env
}

# ---------------------------------------------------------------------------
# Registry: base skills from test-routing.sh + collision-test extensions
# ---------------------------------------------------------------------------
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
      "priority": 50,
      "invoke": "Skill(superpowers:systematic-debugging)",
      "available": true,
      "enabled": true
    },
    {
      "name": "brainstorming",
      "role": "process",
      "phase": "DESIGN",
      "triggers": [
        "(brainstorm|design|architect|strateg|scope|outline|approach|set.?up|wire.up|how.(should|would|could))",
        "(^|[^a-z])(build|create|implement|develop|scaffold|init|bootstrap|introduce|enable|add|make|new|start)($|[^a-z])"
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
      "triggers": ["(plan|outline|break.?down|spec)"],
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
        "(execute.*plan|run.the.plan|implement.the.plan|implement.*(rest|remaining)|continue|follow.the.plan|pick.up|resume|next.task|next.step|carry.on|keep.going|where.were.we|what.s.next)"
      ],
      "trigger_mode": "regex",
      "priority": 35,
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
        "(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|smell|tech.?debt|(^|[^a-z])pr($|[^a-z]))"
      ],
      "trigger_mode": "regex",
      "priority": 25,
      "invoke": "Skill(superpowers:requesting-code-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "receiving-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": [
        "(review comments|pr comments|feedback|nits?|changes requested|address (the )?(review|comments|feedback)|respond to review|follow.?up review|re.?request review)"
      ],
      "trigger_mode": "regex",
      "priority": 33,
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
      "precedes": ["openspec-ship"],
      "requires": [],
      "invoke": "Skill(superpowers:verification-before-completion)",
      "available": true,
      "enabled": true
    },
    {
      "name": "openspec-ship",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [
        "(document.*built|as.?built|openspec|archive.*feature|shipping.*protocol)"
      ],
      "trigger_mode": "regex",
      "priority": 58,
      "precedes": ["finishing-a-development-branch"],
      "requires": ["verification-before-completion"],
      "invoke": "Skill(auto-claude-skills:openspec-ship)",
      "available": true,
      "enabled": true
    },
    {
      "name": "finishing-a-development-branch",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [],
      "trigger_mode": "regex",
      "priority": 19,
      "precedes": [],
      "requires": ["openspec-ship"],
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
      "invoke": "Skill(auto-claude-skills:security-scanner)",
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
      "invoke": "Skill(frontend-design:frontend-design)",
      "available": true,
      "enabled": true
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
      "role": "required",
      "phase": "REVIEW",
      "required_when": "PR touches 3+ files, crosses module boundaries, or includes security-sensitive changes",
      "triggers": [
        "(team.review|multi.*(perspective|reviewer|agent).*(review|check)|thorough.*review|comprehensive.*review|full.*review)",
        "(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|(^|[^a-z])pr($|[^a-z]))"
      ],
      "trigger_mode": "regex",
      "priority": 20,
      "invoke": "Skill(auto-claude-skills:agent-team-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "design-debate",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": [
        "(trade.?off|debate|compare.*(option|approach|design)|weigh.*(option|approach)|pro.?con|alternative|architecture)"
      ],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(design-debate)",
      "available": true,
      "enabled": true
    },
    {
      "name": "product-discovery",
      "role": "process",
      "phase": "DISCOVER",
      "triggers": [
        "(discovery|discover(y|.session|.brief)|user.problem|pain.point|what.to.build|what.should.we|which.issue)",
        "(backlog|sprint.plan|prioriti|triage|next.sprint|roadmap)"
      ],
      "trigger_mode": "regex",
      "priority": 35,
      "precedes": ["brainstorming"],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:product-discovery)",
      "available": true,
      "enabled": true
    },
    {
      "name": "outcome-review",
      "role": "process",
      "phase": "LEARN",
      "triggers": [
        "(how.did.*(perform|do|go|work)|outcome|adoption|funnel|cohort|experiment.result|feature.impact|post.launch|post.ship|measur(e|ing).*(impact|outcome|metric|adoption|success|result)|did.it.work)"
      ],
      "trigger_mode": "regex",
      "priority": 30,
      "precedes": ["product-discovery"],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:outcome-review)",
      "available": true,
      "enabled": true
    },
    {
      "name": "dispatching-parallel-agents",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": [
        "(parallel|concurrent|multiple.*(failure|bug|issue|error|test)|independent.*(task|failure|bug|issue|test)|worktree)"
      ],
      "trigger_mode": "regex",
      "priority": 15,
      "invoke": "Skill(superpowers:dispatching-parallel-agents)",
      "available": true,
      "enabled": true
    },
    {
      "name": "using-git-worktrees",
      "role": "required",
      "phase": "IMPLEMENT",
      "triggers": [
        "(parallel|concurrent|worktree|isolat|branch.*(work|switch))"
      ],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(superpowers:using-git-worktrees)",
      "available": true,
      "enabled": true
    },
    {
      "name": "incident-analysis",
      "role": "domain",
      "phase": "DEBUG",
      "triggers": [
        "(incident.*(investig|analys|review|report|timeline|summary|response|triage|debug|diagnos|resolv)|postmortem|outage|root.cause|error.spike|log.analysis|production.error|staging.error)",
        "(connection.*(fail|refus|timeout|pool|exhaust|acquir)|oom.?kill|memory.pressure|cpu.*(throttl|saturat)|crash.?loop|liveness.probe|node.not.ready|upstream.*(fail|error|timeout)|image.?pull.?(back.?off|fail|error)|err.?image.?pull|config.?(error|missing)|create.?container.?config|failed.?(mount|attach)|pvc.*(pending|fail))",
        "(sigterm|sigkill|shutdown.*(error|fail|grace)|active.connection|cloud.?sql|proxy.*(restart|error|fail|crash)|pod.*(restart|crash|evict)|latency.*(spike|p99)|p99.*(latency|spike|degrad)|request.timeout|circuit.break|deploy.*(fail|rollback))",
        "(slo.*(burn|alert|breach|budget)|burn.?rate|error.budget)"
      ],
      "trigger_mode": "regex",
      "priority": 20,
      "invoke": "Skill(auto-claude-skills:incident-analysis)",
      "available": true,
      "enabled": true
    },
    {
      "name": "incident-trend-analyzer",
      "role": "domain",
      "phase": "DEBUG",
      "triggers": [
        "(incident.trend|postmortem.trend|what.keeps.breaking|recurring.incident|failure.pattern|incident.pattern|analyze.postmortems)"
      ],
      "trigger_mode": "regex",
      "priority": 20,
      "invoke": "Skill(auto-claude-skills:incident-trend-analyzer)",
      "available": true,
      "enabled": true
    },
    {
      "name": "alert-hygiene",
      "role": "domain",
      "phase": "LEARN",
      "triggers": [
        "(alert.*(hygiene|noise|flap|tune|suppress|fatigue|toil))",
        "(alert.*(review|audit|cleanup|health|analysis))",
        "(incident.*(volume|frequency|noise|dedup))",
        "(notification.*(noise|fatigue|channel|routing))",
        "(threshold.*(tune|adjust|raise|lower|calibrat))"
      ],
      "trigger_mode": "regex",
      "priority": 20,
      "invoke": "Skill(auto-claude-skills:alert-hygiene)",
      "available": true,
      "enabled": true
    },
    {
      "name": "batch-scripting",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": [
        "(batch|bulk|mass|across.*files|every.*file|all.*files|migrate.*all|transform.*all|refactor.*all|sweep|codemod|claude.?-p|headless|each.*file)"
      ],
      "trigger_mode": "regex",
      "priority": 15,
      "invoke": "Skill(auto-claude-skills:batch-scripting)",
      "available": true,
      "enabled": true
    },
    {
      "name": "test-driven-development",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": [
        "(tdd|test.driven|write.test|test.first|failing.test|red.green)"
      ],
      "trigger_mode": "regex",
      "priority": 15,
      "invoke": "Skill(superpowers:test-driven-development)",
      "available": true,
      "enabled": true
    }
  ],
  "phase_guide": {
    "DISCOVER": "product-discovery",
    "DESIGN": "brainstorming",
    "PLAN": "writing-plans",
    "IMPLEMENT": "executing-plans or subagent-driven-development",
    "REVIEW": "requesting-code-review",
    "SHIP": "verification-before-completion + openspec-ship + finishing-a-development-branch",
    "DEBUG": "systematic-debugging",
    "LEARN": "outcome-review"
  },
  "phase_compositions": {
    "DISCOVER": {"driver": "product-discovery", "parallel": [], "hints": []},
    "DESIGN": {"driver": "brainstorming", "parallel": [], "hints": []},
    "PLAN": {"driver": "writing-plans", "parallel": [], "hints": []},
    "IMPLEMENT": {"driver": "executing-plans", "parallel": [], "hints": []},
    "REVIEW": {"driver": "requesting-code-review", "parallel": [], "hints": []},
    "SHIP": {"driver": "verification-before-completion", "parallel": [], "hints": []},
    "DEBUG": {"driver": "systematic-debugging", "parallel": [], "hints": []},
    "LEARN": {"driver": "outcome-review", "parallel": [], "hints": []}
  },
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

# ============================================================
# GROUP 1: requesting-code-review vs agent-team-review
# Both share: review|pull.?request|code.?review|check.*(code|changes|diff)
# requesting-code-review priority=25 should win for generic review
# agent-team-review should only win for team/multi-perspective keywords
# ============================================================

section "Code Review Routing Collisions"

assert_activates "generic 'review the code' -> requesting-code-review" \
  "review the code changes" \
  "requesting-code-review"

assert_activates "generic 'PR review' -> requesting-code-review" \
  "can you review this PR" \
  "requesting-code-review"

assert_activates "'team review' -> agent-team-review" \
  "run a team review with multiple perspectives" \
  "agent-team-review"

assert_activates "'comprehensive review' -> agent-team-review" \
  "do a comprehensive review of this feature" \
  "agent-team-review"

assert_activates "'thorough review' -> agent-team-review" \
  "I need a thorough review before merging" \
  "agent-team-review"

assert_activates "explicit name 'agent-team-review' -> agent-team-review" \
  "run agent-team-review on this branch" \
  "agent-team-review"

assert_activates "'check the diff' -> requesting-code-review" \
  "check the diff before I push" \
  "requesting-code-review"

assert_activates "'multi-agent review' -> agent-team-review" \
  "do a multi-agent review of these changes" \
  "agent-team-review"

# ============================================================
# GROUP 2: dispatching-parallel-agents vs using-git-worktrees
# Both match: parallel|concurrent|worktree
# dispatching-parallel-agents priority=15 vs using-git-worktrees priority=14
# ============================================================

section "Parallel Work Routing Collisions"

assert_activates "'parallel tasks' -> dispatching-parallel-agents" \
  "I have three parallel tasks to run" \
  "dispatching-parallel-agents"

assert_activates "'worktree' keyword -> dispatching-parallel-agents (higher priority workflow)" \
  "need a worktree for this feature" \
  "dispatching-parallel-agents"

assert_activates "'isolate in worktree' -> using-git-worktrees (required role, IMPLEMENT phase)" \
  "isolate this work in a worktree" \
  "using-git-worktrees"

assert_activates "'concurrent bugs to fix' -> dispatching-parallel-agents" \
  "I have multiple independent bugs to fix concurrently" \
  "dispatching-parallel-agents"

assert_activates "'worktree' with brainstorming -> dispatching-parallel-agents (required excluded by DESIGN phase)" \
  "set up a git worktree for feature-x" \
  "dispatching-parallel-agents"

assert_activates "'parallel agents' -> dispatching-parallel-agents" \
  "dispatch parallel agents for these independent tasks" \
  "dispatching-parallel-agents"

# ============================================================
# GROUP 3: systematic-debugging vs incident-analysis
# Both match: debug|crash|error|fail|timeout
# systematic-debugging priority=50 vs incident-analysis priority=20
# incident-analysis should win for production/infrastructure keywords
# ============================================================

section "Debug vs Incident Routing Collisions"

assert_activates "'debug this crash' -> systematic-debugging" \
  "debug this crash in the auth module" \
  "systematic-debugging"

assert_activates "'production incident' -> incident-analysis" \
  "investigate the production incident with connection failures" \
  "incident-analysis"

assert_activates "'pod crashloop' -> incident-analysis" \
  "pods are in crashloop backoff on the staging cluster" \
  "incident-analysis"

assert_activates "'OOM kill' -> incident-analysis" \
  "the service got OOM killed in production" \
  "incident-analysis"

assert_activates "'bug in my code' -> systematic-debugging" \
  "there's a bug in my code, the tests are failing" \
  "systematic-debugging"

assert_activates "'latency spike' -> incident-analysis" \
  "we're seeing a latency spike on the API gateway p99" \
  "incident-analysis"

assert_activates "'Cloud SQL proxy restart' -> incident-analysis" \
  "cloud sql proxy keeps restarting with connection errors" \
  "incident-analysis"

assert_activates "'SLO burn rate' -> incident-analysis" \
  "the SLO burn rate alert fired for checkout service" \
  "incident-analysis"

assert_activates "'error in function' -> systematic-debugging" \
  "I'm getting an error in the parseConfig function" \
  "systematic-debugging"

assert_activates "'node NotReady' -> incident-analysis" \
  "kubernetes node is NotReady and pods are being evicted" \
  "incident-analysis"

assert_activates "'ImagePullBackOff' -> incident-analysis" \
  "deployment failing with ImagePullBackOff on new image tag" \
  "incident-analysis"

assert_activates "'timeout in test' -> systematic-debugging" \
  "my integration test hits a timeout after the refactor" \
  "systematic-debugging"

# ============================================================
# GROUP 4: Cross-phase ambiguity -- prompts that could match multiple phases
# ============================================================

section "Cross-Phase Routing"

assert_activates "'ship and deploy' -> verification-before-completion" \
  "let's ship this and deploy to production" \
  "verification-before-completion"

assert_activates "'plan the feature' -> brainstorming" \
  "let's plan the new authentication feature" \
  "brainstorming"

assert_activates "'write tests for this' -> test-driven-development" \
  "write tests for the user service" \
  "test-driven-development"

assert_activates "'review before shipping' -> requesting-code-review" \
  "review the code before we ship" \
  "requesting-code-review"

assert_activates "'investigate alert noise' -> alert-hygiene" \
  "the alerts are too noisy, investigate the alert hygiene" \
  "alert-hygiene"

assert_activates "'postmortem trends' -> incident-trend-analyzer" \
  "analyze our postmortem trends for recurring issues" \
  "incident-trend-analyzer"

assert_activates "'security scan' -> security-scanner" \
  "run a security scan on the codebase" \
  "security-scanner"

assert_activates "'build a frontend' -> frontend-design" \
  "build a frontend component for the dashboard" \
  "frontend-design"

assert_activates "'batch rename files' -> batch-scripting" \
  "batch rename all the migration files" \
  "batch-scripting"

# ============================================================
# GROUP 5: Negative tests -- verify non-activation
# ============================================================

section "Negative Routing Tests"

assert_does_not_activate "greeting does not activate skills" \
  "hello how are you" \
  "brainstorming"

assert_does_not_activate "generic question does not trigger incident-analysis" \
  "what does this function do" \
  "incident-analysis"

assert_does_not_activate "simple code question does not trigger design-debate" \
  "explain this regex pattern" \
  "design-debate"

assert_does_not_activate "'deploy' alone does not trigger incident-analysis" \
  "deploy this to staging" \
  "incident-analysis"

# ============================================================
# Summary
# ============================================================

print_summary
exit $?
