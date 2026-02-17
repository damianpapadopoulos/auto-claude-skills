# Collaborative Agent Teams Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Enhance the `agent-team-execution` skill with collaborative agent teams — message-driven coordination, shared contracts artifact, persistent reviewer teammate, and smart mode selection.

**Architecture:** Replace the current agent-team-execution SKILL.md with the new collaborative design. Add prompt templates for each role (lead, specialist, reviewer). Add a shared-contracts template. The skill uses Claude Code's native primitives (TeamCreate, SendMessage, TaskList) — no custom tooling.

**Tech Stack:** Markdown skill files, Claude Code agent primitives

**Design doc:** `docs/plans/2026-02-17-collaborative-agent-teams-design.md`

---

### Task 1: Rewrite SKILL.md with Collaborative Architecture

**Files:**
- Modify: `~/.claude/skills/agent-team-execution/SKILL.md`

**Context:** This is the main skill file. It currently has a simple "spawn specialists, monitor, complete" flow. We're replacing it with the full collaborative architecture: mode selection, three roles, shared contracts, message-driven coordination, deadlock prevention.

**Step 1: Read the current SKILL.md**

Read `~/.claude/skills/agent-team-execution/SKILL.md` to understand current structure.

**Step 2: Write the new SKILL.md**

Replace the entire file with the new collaborative architecture. The skill must cover:

1. **Frontmatter** — Update description to reflect collaborative design
2. **Overview** — "Execute plans using collaborative agent teams with message-driven coordination"
3. **Mode Selection** — Decision tree: < 3 independent tasks → sequential (fall back to subagent-driven), 3+ file-disjoint → team mode
4. **Three Roles** — Table defining Lead, Specialist, Reviewer with ownership and communication
5. **The Artifact: shared-contracts.md** — Explain: read-only for specialists, lead is sole writer, contains only types/interfaces/config
6. **Communication Protocol** — All message flows (contract changes, task completion, review requests, cross-boundary edits, stall detection)
7. **Workflow Phases** — Setup → Execution → Coordination → Completion (from design doc)
8. **Lead Protocol** — Setup, routing, deadlock breaking, finalize
9. **Specialist Rules** — Assignment is law, contract awareness, TDD, completion via reviewer
10. **Reviewer Protocol** — Event-driven, spec + quality check, approve/reject, escalation
11. **Deadlock Prevention** — Stall detection, rejection escalation, reassignment
12. **Red Flags** — What NOT to do (file-based locking, polling, self-marking completion)
13. **Integration** — References to writing-plans, TDD, finishing-a-development-branch, verification-before-completion

Reference the prompt templates as `./lead-prompt.md`, `./specialist-prompt.md`, `./reviewer-prompt.md`, `./shared-contracts-template.md`.

**Step 3: Verify the SKILL.md**

Read it back and verify:
- All sections from design doc are covered
- References to prompt templates are correct
- Mode selection logic matches design
- Communication protocol is complete
- No mention of file-based locking or polling

**Step 4: Commit**

```bash
git add ~/.claude/skills/agent-team-execution/SKILL.md
git commit -m "feat: rewrite agent-team-execution with collaborative architecture"
```

---

### Task 2: Create Lead Prompt Template

**Files:**
- Create: `~/.claude/skills/agent-team-execution/lead-prompt.md`

**Context:** The lead is the orchestrator. This prompt template is used by the session that invokes the skill — it describes how the lead should behave. This is reference material, not a spawn prompt (the lead IS the current session).

**Step 1: Write the lead prompt template**

The template must cover:

1. **Role definition** — "You are the Lead Orchestrator for a collaborative agent team"
2. **Setup phase** — Read plan, analyze file ownership, create shared-contracts.md, TeamCreate, spawn specialists + reviewer
3. **Routing protocol** — How to handle: contract change requests, cross-boundary edit requests, review results, stall detection
4. **Monitoring** — Check TaskList, respond to messages, track which tasks are in-progress/complete/blocked
5. **Deadlock breaking** — When to intervene (stall timeout, 3x rejection, unanswered cross-boundary)
6. **Finalize** — All tasks approved → full test suite → integration review → shutdown team → finishing-a-development-branch
7. **Rules** — Never edit specialist-owned files directly, never skip reviewer, always route through proper channels

Include a concrete example workflow showing the message flow for a 5-task plan.

**Step 2: Verify**

Read it back. Verify it covers all lead responsibilities from the design doc.

**Step 3: Commit**

```bash
git add ~/.claude/skills/agent-team-execution/lead-prompt.md
git commit -m "feat: add lead orchestrator prompt template"
```

---

### Task 3: Create Specialist Prompt Template

**Files:**
- Create: `~/.claude/skills/agent-team-execution/specialist-prompt.md`

**Context:** This is the spawn prompt template for specialist teammates. The lead fills in the placeholders when spawning each specialist.

**Step 1: Write the specialist prompt template**

The template must include:

1. **Placeholders** — `{specialist_name}`, `{feature_name}`, `{task_text}`, `{assigned_files}`, `{design_context}`, `{contracts_path}`
2. **Coordination rules:**
   - Assignment is law — only edit assigned files
   - Read shared-contracts.md before writing code
   - To change a contract → SendMessage to Lead with specific request
   - To edit a file you don't own → SendMessage to Lead
3. **TDD discipline** — Write failing test → implement → verify green → self-review
4. **Self-review checklist** — Completeness, quality, discipline, testing (reuse from existing implementer-prompt.md)
5. **Completion protocol** — Do NOT mark own task complete. SendMessage to Reviewer: "Task T-{id} complete. Tests at {path}. Ready for review."
6. **Question protocol** — If unclear on requirements, SendMessage to Lead BEFORE starting work
7. **Report format** — What to include when messaging Reviewer

Model this on the existing `subagent-driven-development/implementer-prompt.md` but adapted for team context (SendMessage instead of return, reviewer instead of lead for completion).

**Step 2: Verify**

Read it back. Verify:
- All placeholders are clearly marked
- "Assignment is law" is prominent
- Completion goes to Reviewer, not Lead
- Contract changes go through Lead
- TDD is required

**Step 3: Commit**

```bash
git add ~/.claude/skills/agent-team-execution/specialist-prompt.md
git commit -m "feat: add specialist spawn prompt template"
```

---

### Task 4: Create Reviewer Prompt Template

**Files:**
- Create: `~/.claude/skills/agent-team-execution/reviewer-prompt.md`

**Context:** This is the spawn prompt for the persistent reviewer teammate. The reviewer lives on the team and processes review requests as they arrive via SendMessage.

**Step 1: Write the reviewer prompt template**

The template must include:

1. **Placeholders** — `{feature_name}`, `{design_doc_path}`, `{plan_path}`, `{contracts_path}`
2. **Trigger** — Wait for incoming SendMessage containing review requests from specialists
3. **Review process (per request):**
   a. Read the modified files mentioned in the specialist's message
   b. Read shared-contracts.md for interface compliance
   c. **Spec compliance check** — Does code match the task requirements? Missing features? Extra features?
   d. **Code quality check** — Clean, maintainable, follows patterns? Tests comprehensive?
   e. Run the tests: `{test_command}`
4. **Decision:**
   - PASS → SendMessage to Lead: "APPROVED. Task T-{id} complete. [brief summary]"
   - FAIL → SendMessage to Specialist: "REJECTED. [specific issues with file:line references]"
5. **Escalation** — If same task rejected 3 times, SendMessage to Lead for intervention
6. **Rules:**
   - Read-only: do NOT modify any files
   - Do NOT trust specialist's claim of "tests passing" — run them yourself
   - Verify code against shared-contracts.md interfaces
   - Be specific in rejections (file, line, what's wrong, what to do)

Model the review checks on the existing `spec-reviewer-prompt.md` and `code-quality-reviewer-prompt.md` — combine both into one reviewer role.

**Step 2: Verify**

Read it back. Verify:
- Both spec compliance AND code quality are covered
- PASS goes to Lead, FAIL goes to Specialist
- Escalation after 3 rejections
- Read-only is enforced
- Tests are actually run, not trusted

**Step 3: Commit**

```bash
git add ~/.claude/skills/agent-team-execution/reviewer-prompt.md
git commit -m "feat: add persistent reviewer prompt template"
```

---

### Task 5: Create Shared Contracts Template

**Files:**
- Create: `~/.claude/skills/agent-team-execution/shared-contracts-template.md`

**Context:** This is the template the lead uses to create the initial `shared-contracts.md` file in the workspace. The lead populates it from the plan's types and interfaces.

**Step 1: Write the template**

```markdown
# SHARED CONTRACTS

> **READ-ONLY for Specialists.** To request changes, SendMessage to the Lead.
> **Last updated by:** Lead
> **Last update reason:** Initial creation from plan

## 1. Data Models

{extracted types and interfaces from plan}

## 2. API Signatures

{function signatures, endpoint definitions, return types}

## 3. Environment & Config

{environment variables, configuration values, paths}

## 4. Change Log

| Timestamp | Changed By | What Changed | Reason |
|-----------|-----------|--------------|--------|
| {now} | Lead | Initial creation | Plan analysis |
```

Include instructions for the lead on:
- How to extract types from the plan
- When to add new sections
- How to notify specialists after updates

**Step 2: Verify**

Read it back. Verify the template is clear and the "READ-ONLY" warning is prominent.

**Step 3: Commit**

```bash
git add ~/.claude/skills/agent-team-execution/shared-contracts-template.md
git commit -m "feat: add shared contracts template"
```

---

### Task 6: End-to-End Walkthrough in SKILL.md

**Files:**
- Modify: `~/.claude/skills/agent-team-execution/SKILL.md`

**Context:** Add a concrete example walkthrough to the SKILL.md showing the full flow for a realistic scenario. This helps Claude understand how to actually use the skill.

**Step 1: Add example section**

Add an `## Example Workflow` section to SKILL.md with a scenario like "Adding user authentication with login, registration, and session management." Show:

1. Lead reads plan, identifies 4 tasks across 3 file-disjoint groups
2. Lead creates shared-contracts.md with User type, Session type, API signatures
3. Lead spawns 3 specialists + 1 reviewer
4. Specialist A implements auth middleware, needs to add `session_token` to User type
5. Specialist A → Lead: "Requesting contract update: Add session_token to User"
6. Lead updates contracts → messages Specialist B: "Contract updated, User has session_token"
7. Specialist A completes → Reviewer: "Ready for review"
8. Reviewer checks, finds missing validation → Specialist A: "REJECTED. Missing email format validation"
9. Specialist A fixes → Reviewer: "Ready for re-review"
10. Reviewer approves → Lead: "APPROVED. Task T-101"
11. All tasks approved → Lead runs full suite → shutdown → finishing-a-development-branch

**Step 2: Verify**

Read the full SKILL.md. Verify the example is realistic and covers: contract changes, cross-boundary coordination, review rejection, and completion.

**Step 3: Commit**

```bash
git add ~/.claude/skills/agent-team-execution/SKILL.md
git commit -m "feat: add end-to-end example walkthrough"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | Rewrite SKILL.md with collaborative architecture | SKILL.md |
| 2 | Lead prompt template | lead-prompt.md |
| 3 | Specialist prompt template | specialist-prompt.md |
| 4 | Reviewer prompt template | reviewer-prompt.md |
| 5 | Shared contracts template | shared-contracts-template.md |
| 6 | End-to-end example walkthrough | SKILL.md |

All files in `~/.claude/skills/agent-team-execution/`.

Tasks 1-5 are independent (different files). Task 6 depends on Task 1.
