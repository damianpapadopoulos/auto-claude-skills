# Enhanced Subagent-Driven Development with Collaborative Agent Teams

**Date:** 2026-02-17
**Status:** Approved

## Problem

The current subagent-driven-development skill executes tasks sequentially with tight review loops. This creates two bottlenecks:

1. **Scale** — With 10+ tasks, the lead dispatches and reviews one at a time
2. **Coordination** — Agents cannot communicate ad-hoc (e.g., "I changed the auth interface")

Agent-team-execution offers parallelism but lacks the quality discipline (TDD, spec review, quality review) of subagent-driven.

## Solution

Enhance subagent-driven-development with a **team mode** that activates for 3+ file-disjoint tasks. The architecture uses "Single Writer, Many Readers" for shared state and message-driven coordination.

## Architecture

### Mode Selection

```
Read plan -> Count independent file-disjoint tasks

< 3 independent tasks -> Sequential mode (current subagent-driven, unchanged)
3+ independent tasks  -> Team mode (this design)
Tightly coupled tasks -> Sequential mode with dependency ordering
```

### Three Roles

| Role | Count | Owns | Communicates via |
|---|---|---|---|
| Lead | 1 | `shared-contracts.md`, TaskList | SendMessage (routing) |
| Specialist | 1-N | Assigned files only | SendMessage (to lead, reviewer, peers) |
| Reviewer | 1 | Nothing (read-only) | SendMessage (approve/reject) |

### The Artifact: `shared-contracts.md`

Read-only for specialists. Lead is sole writer. Contains only:

- Data models / types
- API signatures
- Environment config

Does NOT contain: task board (TaskList handles that), file locks (assignment handles that).

```markdown
# SHARED CONTRACTS
> **READ-ONLY for Specialists.** To change this, SendMessage to the Lead.

## 1. Data Models
- `User`: { id: string, role: 'admin'|'user' }

## 2. API Signatures
- `auth.login(email, pass)` -> Promise<Session>

## 3. Environment Config
- `API_URL`: "http://localhost:3000"
```

### Communication Protocol

```
Specialist needs contract change    -> SendMessage to Lead
Lead updates shared-contracts.md    -> SendMessage to affected specialists
Specialist completes task           -> SendMessage to Reviewer
Reviewer approves                   -> SendMessage to Lead (who marks task complete)
Reviewer rejects                    -> SendMessage to Specialist (with specific issues)
Specialist needs cross-boundary edit -> SendMessage to owning specialist
Lead detects stall (TaskList check) -> SendMessage to stuck specialist
```

### Zero Race Conditions

- Only the Lead writes to `shared-contracts.md`
- SendMessage is the atomic unit of synchronization
- "Assignment is Law" prevents file conflicts
- TaskList (built-in) handles task state reliably

## Workflow

### Phase 1: Setup (Lead)

1. Read plan, extract all tasks with file lists
2. Analyze file ownership — group tasks into file-disjoint sets
3. Create `shared-contracts.md` with initial types/interfaces extracted from plan
4. `TeamCreate` + spawn specialists (one per file-disjoint group) + spawn reviewer

### Phase 2: Execution (Parallel)

Each specialist independently:
1. Reads `shared-contracts.md`
2. Implements using TDD (write test -> fail -> implement -> pass)
3. Self-reviews before submitting
4. SendMessage to Reviewer: "Task complete. Tests passed. Ready for review."

Reviewer (event-driven):
1. Receives review request
2. Reads modified files + `shared-contracts.md`
3. Checks spec compliance + code quality + runs tests
4. If PASS: SendMessage to Lead "APPROVED. Task X merged."
5. If FAIL: SendMessage to Specialist "REJECTED. [specific issues]"

### Phase 3: Coordination (As Needed)

When a specialist needs to change a shared contract:
1. Specialist -> Lead: "Requesting contract update: Add session_token to User."
2. Lead updates `shared-contracts.md`
3. Lead -> affected specialists: "ALERT: Contract update. User now has session_token."
4. Affected specialists re-read contracts and adapt

When a specialist needs a cross-boundary file change:
1. Specialist A -> Lead: "Need schema change in database.ts (owned by Specialist B)"
2. Lead -> Specialist B: "Specialist A needs [specific change] in database.ts"
3. Specialist B makes the change, confirms to Lead
4. Lead -> Specialist A: "Change made, proceed."

### Phase 4: Completion (Lead)

1. All tasks approved by Reviewer
2. Lead runs full test suite
3. Final integration review
4. Shutdown team (`shutdown_request` to all) + `TeamDelete`
5. Invoke `finishing-a-development-branch`

## System Prompts

### Lead (Orchestrator)

```
ROLE: LEAD ORCHESTRATOR
1. SETUP:
   - Analyze the plan
   - Break into file-disjoint task groups
   - Create shared-contracts.md with initial types
   - Spawn specialists + reviewer via TeamCreate

2. ROUTING:
   - If specialist requests contract change:
     a. Update shared-contracts.md
     b. SendMessage ALL affected agents: "Contract updated."
   - If specialist needs cross-boundary edit:
     Route request to owning specialist

3. DEADLOCK BREAKING:
   - Check TaskList. If task in_progress with no messages > extended period, ping specialist
   - If Reviewer rejects 3 times, intervene to debug

4. FINALIZE:
   - When all tasks approved, run full test suite
   - Final integration review
   - Shutdown team, delete shared-contracts.md
```

### Specialist (Collaborative Developer)

```
ROLE: COLLABORATIVE SPECIALIST

COORDINATION RULES:
1. ASSIGNMENT IS LAW:
   - Only edit files explicitly assigned to you
   - If you need changes in another agent's files, SendMessage to Lead

2. CONTRACT AWARENESS:
   - READ shared-contracts.md before writing code
   - Never overwrite shared types blindly
   - If you need to change a contract, SendMessage to Lead:
     "Requesting update to shared-contracts.md: Adding phone to User type."

3. TDD DISCIPLINE:
   - Write failing test -> implement -> verify green
   - Self-review before submitting

4. COMPLETION:
   - Do NOT mark your own task complete
   - SendMessage to Reviewer: "Task complete. Tests at [path]. Ready for review."
```

### Reviewer (Gatekeeper)

```
ROLE: INTEGRATION REVIEWER

TRIGGER: Incoming messages containing review requests.

ACTION:
1. Read modified files and shared-contracts.md
2. Verify spec compliance: does code match what was requested?
3. Verify code quality: clean, maintainable, follows patterns?
4. Run the tests

DECISION:
- FAIL: SendMessage to Specialist: "REJECTED. [specific issues]"
- PASS: SendMessage to Lead: "APPROVED. Task X complete."

ESCALATION:
- If same task rejected 3 times, SendMessage to Lead for intervention
```

## Deadlock Prevention

- Lead checks TaskList periodically
- Extended in_progress with no messages -> Lead pings specialist
- Reviewer rejects 3 times -> Lead intervenes to debug
- Cross-boundary request unanswered -> Lead routes it
- Stale specialist (crashed/stuck) -> Lead reassigns task to new specialist

## Integration with Existing Skills

- **subagent-driven-development** — This design enhances it with team mode
- **agent-team-execution** — Superseded by this design for the subagent-driven skill
- **dispatching-parallel-agents** — Used internally for grouping logic
- **writing-plans** — Creates the plan this skill executes
- **test-driven-development** — Specialists follow TDD
- **finishing-a-development-branch** — Invoked after all tasks complete
- **verification-before-completion** — Lead runs before finalizing

## Key Design Decisions

1. **Message-driven, not file-polled** — SendMessage is atomic and reliable; markdown polling is racy
2. **Single writer for contracts** — Only Lead updates shared-contracts.md, eliminating race conditions
3. **Assignment is law** — File ownership declared at spawn, not claimed dynamically
4. **Reviewer is persistent** — Lives on the team, not dispatched per-task (reduces spawn overhead)
5. **Lead routes, doesn't gate** — Lead monitors and routes messages, doesn't review every task itself
