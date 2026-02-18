---
name: design-debate
description: Multi-Agent Debate (MAD) for complex designs. Spawns architect, critic, and pragmatist for collaborative design exploration with structured convergence.
---

# Design Debate (MAD Pattern)

## Overview

Escalation skill for the DESIGN phase. When brainstorming detects competing architectures, cross-cutting concerns, or high-stakes decisions, this skill orchestrates a Multi-Agent Debate with three perspectives to avoid echo-chamber thinking.

**This skill is opt-in.** It only activates when brainstorming explicitly escalates after user approval.

## When to Escalate

The brainstorming skill should consider escalating when it detects:

| Signal | Example |
|--------|---------|
| Multiple competing architectures | "We could use microservices or a monolith" |
| Cross-cutting concerns | Auth + data + API all affected |
| High-stakes decisions | "This will be hard to change later" |
| User explicitly requests debate | "I want different perspectives on this" |
| Ambiguity after 3+ questions | Still unclear on approach after extended exploration |

**Always ask the user first:** "This has competing approaches. Want me to run a design debate with multiple perspectives?"

## Team Composition

| Teammate | Role | Lens |
|----------|------|------|
| `architect` | Lead designer | Proposes architecture, defends trade-offs |
| `critic` | Devil's advocate | Attacks assumptions, finds blind spots, proposes alternatives |
| `pragmatist` | Implementation realist | Evaluates feasibility, YAGNI, timeline, complexity cost |

## Debate Protocol

```
1. TeamCreate("design-debate")

2. Share context with all teammates:
   - Problem statement
   - Constraints identified during brainstorming
   - Options explored so far
   - User preferences expressed

3. Round 1 (parallel):
   - architect: Proposes approach with reasoning
   - critic: Identifies blind spots and alternatives
   - pragmatist: Evaluates feasibility and complexity cost

4. Round 2 (parallel):
   - Each responds to the others' positions
   - Converge toward consensus or clearly articulated trade-offs

5. Lead synthesizes:
   - Present recommendation with dissenting views noted
   - Highlight unresolved trade-offs

6. User decides:
   - Approve → TeamDelete, write design doc
   - Reject → another round or manual override
```

### Constraints

- **2 rounds maximum** — prevents runaway token burn
- **Opt-in only** — brainstorming asks user before escalating
- **Ephemeral team** — created and destroyed within DESIGN phase
- **Output is a design doc** — `docs/plans/YYYY-MM-DD-*-design.md`

## Communication Contract

All inter-agent messages MUST use this JSON schema in SendMessage content:

```json
{
  "type": "design_position",
  "stance": "propose | critique | evaluate",
  "position": "Use event sourcing for audit trail",
  "reasoning": "Provides immutable history, enables replay, fits compliance requirements",
  "risks": ["complexity", "learning curve", "storage growth"],
  "confidence": "high | medium | low"
}
```

## Spawn Prompts

### Architect
```
You are the architect in a design debate. Your job is to propose the best architecture for the problem and defend your trade-offs.

Context: {problem_statement}
Constraints: {constraints}
Options explored: {options}

Propose your recommended architecture using the design_position JSON schema. Be specific about components, data flow, and integration points.
```

### Critic
```
You are the critic in a design debate. Your job is to attack assumptions, find blind spots, and propose alternatives the architect may have missed.

Context: {problem_statement}
Architect's proposal: {architect_position}

Challenge the proposal using the design_position JSON schema. Focus on: hidden assumptions, failure modes, scaling issues, maintenance burden, and alternative approaches.
```

### Pragmatist
```
You are the pragmatist in a design debate. Your job is to evaluate feasibility, complexity cost, and whether the proposed approach is the simplest thing that could work.

Context: {problem_statement}
Architect's proposal: {architect_position}
Critic's challenges: {critic_position}

Evaluate using the design_position JSON schema. Focus on: implementation timeline, team skill requirements, YAGNI violations, incremental delivery options, and operational complexity.
```

## Output

After the debate, synthesize into a design document at `docs/plans/YYYY-MM-DD-{topic}-design.md` containing:

1. **Problem statement** — what we're solving
2. **Recommended approach** — the consensus or lead's recommendation
3. **Dissenting views** — what the critic and pragmatist flagged
4. **Trade-offs** — what we're accepting
5. **Decision** — what the user approved

Then return to the brainstorming skill's sequential flow → writing-plans.
