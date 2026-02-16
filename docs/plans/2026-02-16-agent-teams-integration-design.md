# Agent Teams Integration Design

**Date**: 2026-02-16
**Status**: Approved
**Approach**: Hybrid Phase-Aware Teams (Approach A)
**Dependencies**: Cozempic v0.5.1+, Claude Code agent teams (experimental)

## Philosophy

Teams are temporary and phase-scoped. They spin up for a phase, do their work, and shut down. The sequential flow between phases is maintained — each team's output (design doc, implemented code, review report) is the input for the next phase.

The routing engine decides single-agent vs team execution based on phase + complexity. Cozempic guards all team sessions automatically.

## 1. Overall Architecture

```
User prompt
  │
  ├─ Routing engine (skill-activation-hook.sh)
  │   Selects skills by phase + triggers as today
  │
  ├─ DESIGN phase
  │   brainstorming skill (sequential, single agent)
  │     │
  │     └─ Complexity escalation?
  │         YES → spawn MAD debate team (3 agents)
  │              → debate converges on design doc
  │              → team shuts down, returns to sequential
  │         NO  → continue single-agent brainstorming as today
  │
  ├─ PLAN phase
  │   writing-plans skill (sequential, single agent)
  │   Outputs: docs/plans/*.md with task list
  │
  ├─ IMPLEMENT phase
  │   agent-team-execution skill (team, lead + specialist teammates)
  │     Lead reads plan → file ownership analysis → assigns to specialists
  │     Specialists work in parallel on file-disjoint task groups
  │     Cozempic guards session throughout
  │
  ├─ REVIEW phase
  │   agent-team-review skill (team, lead + reviewer teammates)
  │     Lead spawns 2-3 reviewers with different lenses
  │     Reviewers investigate in parallel, share structured findings
  │     Lead synthesizes into review report
  │
  └─ SHIP phase
      verification + finishing-branch skills (sequential, single agent)
```

### Key principles

- **Teams only where parallelism pays off**: IMPLEMENT and REVIEW phases use teams. DESIGN/PLAN/SHIP stay sequential (with opt-in debate for complex DESIGN).
- **Context-centric decomposition**: Following Anthropic's guidance — group work that shares necessary understanding, not by role.
- **File-disjoint assignment**: The lead assigns tasks to specialists ensuring no two teammates edit the same file. Prevents data loss from concurrent overwrites.
- **Structured communication contracts**: All agent-to-agent messages use JSON schemas defined in each skill's SKILL.md.
- **Conditional heartbeats**: TeammateIdle hook only nudges agents with unfinished tasks, not legitimately idle ones.

## 2. MAD Debate (DESIGN Phase Escalation)

### When it triggers

The brainstorming skill detects complexity signals during conversation and asks the user before escalating:

| Signal | Example |
|--------|---------|
| Multiple competing architectures | "We could use microservices or a monolith" |
| Cross-cutting concerns | Auth + data + API all affected |
| High-stakes decisions | "This will be hard to change later" |
| User explicitly requests debate | "I want different perspectives on this" |
| Ambiguity after 3+ questions | Still unclear on approach after extended exploration |

### Team composition (3 agents, temporary)

| Teammate | Role | Lens |
|----------|------|------|
| `architect` | Lead designer | Proposes architecture, defends trade-offs |
| `critic` | Devil's advocate | Attacks assumptions, finds blind spots, proposes alternatives |
| `pragmatist` | Implementation realist | Evaluates feasibility, YAGNI, timeline, complexity cost |

### Debate flow

```
Brainstorming skill detects complexity
  │
  ├─ Asks user: "This has competing approaches. Want me to
  │   run a design debate with multiple perspectives?"
  │
  ├─ User approves → TeamCreate("design-debate")
  │   Lead shares: problem statement, constraints, options explored so far
  │   Each teammate gets spawn prompt with their persona + the context
  │
  ├─ Round 1: Each teammate proposes/critiques (parallel)
  │   architect: proposes approach with reasoning
  │   critic: identifies blind spots and alternatives
  │   pragmatist: evaluates feasibility and complexity cost
  │
  ├─ Round 2: Teammates respond to each other via SendMessage
  │   Converge toward consensus or clearly articulated trade-offs
  │
  ├─ Lead synthesizes into design recommendation
  │   Presents to user with dissenting views noted
  │
  ├─ User approves → TeamDelete, write design doc
  │   Sequential flow resumes → writing-plans
  │
  └─ User rejects → another debate round or manual override
```

### Constraints

- Debate is **opt-in** — brainstorming skill asks user before escalating
- Team is **ephemeral** — created and destroyed within the DESIGN phase
- **2 rounds max** — prevents runaway token burn. After 2 rounds, lead presents trade-offs and user decides
- Output is a **design doc** (`docs/plans/YYYY-MM-DD-*-design.md`) — same artifact as regular brainstorming

### Communication contract

```json
{
  "type": "design_position",
  "stance": "propose | critique | evaluate",
  "position": "Use event sourcing for audit trail",
  "reasoning": "...",
  "risks": ["complexity", "learning curve"],
  "confidence": "high | medium | low"
}
```

## 3. Specialist Implementation Team (IMPLEMENT Phase)

### When it triggers

When a plan exists (writing-plans completed) and the user initiates implementation. The agent-team-execution skill replaces or complements the existing executing-plans and subagent-driven-development skills.

### Team formation

```
Lead reads plan tasks
  │
  ├─ File ownership analysis
  │   Scan each task for likely file touches (paths mentioned in plan)
  │   Group tasks that share files under one specialist
  │   Result: file-disjoint task groups
  │
  ├─ Spawn specialists per task group
  │   Lead ASSIGNS tasks explicitly (no self-claim)
  │   Each specialist owns a disjoint file set
  │   Specialist gets: task description, file boundaries, design doc context
  │
  ├─ Specialists work in parallel
  │   Each stays within their file boundaries
  │   Communicate via SendMessage if cross-boundary changes needed
  │   Use TDD within their scope
  │
  └─ Lead monitors via TaskList, reassigns if blocked
```

### Specialist assignment strategy

The lead groups tasks by file ownership, not by role. This follows Anthropic's "context-centric decomposition" principle:

```
Plan tasks:
  Task 1: Add auth middleware (touches: src/middleware/auth.ts, src/types/auth.ts)
  Task 2: Add auth routes (touches: src/routes/auth.ts, src/routes/index.ts)
  Task 3: Add user model (touches: src/models/user.ts, src/db/migrations/001.ts)
  Task 4: Add auth tests (touches: tests/auth.test.ts, tests/fixtures/users.ts)

File-disjoint groups:
  Specialist A: Tasks 1+2 (middleware + routes — share auth domain context)
  Specialist B: Task 3 (data layer — independent file set)
  Specialist C: Task 4 (tests — independent file set, runs after A+B via dependency)
```

### Communication contract

```json
{
  "type": "task_status",
  "task_id": "3",
  "status": "completed | blocked | needs_cross_boundary",
  "files_modified": ["src/models/user.ts"],
  "summary": "User model with email/password fields, bcrypt hashing",
  "blocker": null
}
```

### Sizing rule

- **< 3 independent tasks**: Use single-agent executing-plans (no team overhead)
- **3+ independent tasks**: Spawn specialist team
- **Tasks with heavy dependencies**: Use single-agent sequential execution

## 4. Multi-Perspective Review Team (REVIEW Phase)

### When it triggers

After implementation completes (all tasks marked done). Activates for larger implementations (5+ files changed). Smaller changes use the existing requesting-code-review skill.

### Team composition (2-3 reviewers)

| Teammate | Lens | Focus |
|----------|------|-------|
| `security-reviewer` | Security | Auth flows, input validation, secrets, OWASP risks |
| `quality-reviewer` | Code quality | Patterns, maintainability, test coverage, edge cases |
| `spec-reviewer` | Spec compliance | Does implementation match the design doc and plan? |

### Review flow

```
Review phase triggered
  │
  ├─ TeamCreate("code-review")
  │   Lead reads: design doc + plan + git diff
  │
  ├─ Spawn reviewers with context
  │   Each gets: the diff, the design doc, their specific review lens
  │   Each reviewer works independently (Read, Grep, analysis)
  │
  ├─ Reviewers report structured findings via SendMessage
  │
  ├─ Lead synthesizes into unified review report
  │   Groups by severity (blocking → suggestion)
  │   Deduplicates overlapping findings
  │   Presents to user
  │
  ├─ Blocking issues found:
  │   TeamDelete → return to IMPLEMENT → fix → re-review
  │
  └─ Clean or suggestions only:
      TeamDelete → proceed to SHIP
```

### Communication contract

```json
{
  "type": "review_finding",
  "severity": "blocking | warning | suggestion",
  "file": "src/auth.ts",
  "line": 42,
  "category": "security | quality | spec",
  "description": "SQL injection via unsanitized input",
  "suggestion": "Use parameterized queries"
}
```

### Review synthesis output

```json
{
  "type": "review_summary",
  "blocking": [],
  "warnings": [],
  "suggestions": [],
  "verdict": "blocking_issues | clean | suggestions_only"
}
```

## 5. Cozempic Integration

### Auto-install at SessionStart

```
session-start-hook.sh:
  1. fix-plugin-manifests.sh              (existing)
  2. Build skill registry                  (existing)
  3. Check cozempic installation           (NEW)
     │
     ├─ `command -v cozempic` succeeds?
     │   YES → skip
     │   NO  → `pip install cozempic 2>/dev/null`
     │         `cozempic init 2>/dev/null`
     │         Log: "Cozempic installed for context protection"
     │
     └─ Failed? Continue without it (non-blocking warning)
```

### Role per phase

| Phase | Cozempic role |
|-------|---------------|
| DESIGN (MAD debate) | Checkpoints 3-agent debate state |
| IMPLEMENT (specialist team) | Checkpoints task assignments, specialist progress |
| REVIEW (reviewer team) | Checkpoints reviewer findings |
| All phases | Guard daemon monitors session size, auto-prunes non-team messages |

### Recovery scenario

```
Session grows large during IMPLEMENT with 4 specialists
  → Cozempic detects approaching compaction threshold
  → PreCompact hook fires → checkpoints full team state
  → Compaction runs → team messages may be lost
  → Guard daemon detects post-compaction state
  → Injects synthetic recovery message with full team roster + task status
  → Lead "remembers" all teammates and continues
```

### Failure mode

If cozempic isn't installed (pip fails, Python not available), everything still works — just without compaction protection. The routing engine, skill activation, and agent teams all function independently.

## 6. Conditional Heartbeat (TeammateIdle Hook)

### Problem

TeammateIdle fires on every idle event, including legitimate ones (teammate finished all work). Always nudging wastes tokens and delays shutdown.

### Solution

A shell script that cross-references teammate state with the shared task list:

```bash
#!/bin/bash
# teammate-idle-guard.sh
INPUT=$(cat)
TEAMMATE=$(echo "$INPUT" | jq -r '.teammate_name')
TEAM=$(echo "$INPUT" | jq -r '.team_name')
TASKS_DIR="${HOME}/.claude/tasks/${TEAM}"

# No task directory = allow idle
[ ! -d "$TASKS_DIR" ] && exit 0

# Check for in_progress tasks owned by this teammate
UNFINISHED=$(find "$TASKS_DIR" -name '*.json' -exec \
  jq -r --arg owner "$TEAMMATE" \
  'select(.owner == $owner and .status == "in_progress") | .subject' {} + \
  2>/dev/null)

if [ -n "$UNFINISHED" ]; then
  echo "You have unfinished tasks: ${UNFINISHED}. Continue working or report your blocker via SendMessage." >&2
  exit 2  # Block idle
fi

exit 0  # Allow idle
```

### Three outcomes

| Condition | Exit code | Effect |
|-----------|-----------|--------|
| No team/no tasks | 0 | Idle allowed |
| All owned tasks completed | 0 | Idle allowed, lead can send shutdown |
| Has in_progress tasks | 2 | Nudge with task names, keep working |

## 7. Changes Required

| Component | Change | Type |
|-----------|--------|------|
| `hooks/session-start-hook.sh` | Add cozempic auto-install + TeammateIdle hook wiring | Modify |
| `hooks/teammate-idle-guard.sh` | Conditional heartbeat script | New |
| `config/default-triggers.json` | Enable `agent-team-execution`, add `agent-team-review`, add `design-debate` | Modify |
| `~/.claude/skills/agent-team-execution/SKILL.md` | Lead delegates to specialists, file-disjoint assignment, JSON contracts | New |
| `~/.claude/skills/agent-team-review/SKILL.md` | Multi-perspective review, structured finding schemas | New |
| `~/.claude/skills/design-debate/SKILL.md` | MAD debate, structured position schemas, 2-round cap | New |
| `commands/setup.md` | Add cozempic to setup instructions | Modify |
| `docs/integrations/agent-teams-and-cozempic.md` | Update with final architecture | Modify |
| `README.md` | Update companion tools section | Modify |
| `tests/test-routing.sh` | Tests for new skill triggers | Modify |
| `tests/test-registry.sh` | Tests for new skill discovery | Modify |

### What we don't change

- **Superpowers skills** (brainstorming, writing-plans, etc.) — we don't own them
- **Routing engine architecture** — already handles new skills via registry
- **Hook event model** — cozempic and auto-claude-skills already coexist cleanly
- **Existing skills** — all current functionality preserved

### How skills discover each other

The design-debate skill is registered as a domain skill. When brainstorming activates (process) and design-debate matches triggers (domain), the routing engine emits:

```
Process: brainstorming -> Skill(superpowers:brainstorming)
  INFORMED BY: design-debate -> Skill(design-debate)
```

Claude reads both, brainstorming drives the conversation, and escalates to design-debate when complexity signals appear.

## 8. References

- [Claude Code Agent Teams docs](https://code.claude.com/docs/en/agent-teams)
- [Building Multi-Agent Systems](https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them)
- [Cozempic](https://github.com/Ruya-AI/cozempic) — context protection for agent teams
- [Compaction bug #23620](https://github.com/anthropics/claude-code/issues/23620)
- [Superpowers team support #429](https://github.com/obra/superpowers/issues/429)
