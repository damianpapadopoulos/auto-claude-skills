# Design: OpenSpec Context Tier Integration (Spec B)

## Overview

Add "Intent Truth" as a fourth context tier to the unified-context-stack, alongside External Truth (API docs), Internal Truth (code dependencies), and Historical Truth (institutional memory). Intent Truth answers "what should this feature do?" and "why was it built this way?" using OpenSpec artifacts and Superpowers specs as fallback.

## Motivation

The current context stack helps the model understand APIs (External), code structure (Internal), and past learnings (Historical). But none of these answer the normative question: "what is this feature supposed to do?" Without intent context, the model relies on the user's prompt or its own inference — both error-prone for complex features with acceptance criteria, design decisions, and rejected alternatives already documented in spec artifacts.

## Hard Boundary

- Only **consumes** what Spec A standardized (`openspec_capabilities`, `OpenSpec:` capability line)
- Does **NOT** invent new detection, session state, or hook logic
- Does **NOT** modify `session-start-hook.sh`, `skill-activation-hook.sh`, or any bash code
- Does **NOT** modify `config/default-triggers.json` or `config/fallback-registry.json`

## Design Debate Summary

A three-agent design debate (architect, critic, pragmatist) refined this design. Key outcomes:

- **"Source" labels instead of "Tier" labels** — Intent Truth is artifact priority ordering, not trust degradation like External Truth
- **Active change first, not canonical first** — active changes are the strongest recency signal; no timestamp comparison needed
- **Three phase edits, not four** — Testing & Debug dropped (debugging is about current state, not intended state)
- **No viability thresholds** — models handle stub content gracefully; file existence is sufficient gate
- **Explicit normative framing** — the tier doc acknowledges Intent Truth defines intended state, not current state

## 1. Intent Truth Tier Document

### File

`skills/unified-context-stack/tiers/intent-truth.md`

### Content

```markdown
# Intent Truth — Feature Specification & Design Rationale

Retrieve canonical feature specifications, active change context, and design rationale.

Unlike other tiers that describe current state (what IS), Intent Truth defines intended
state (what SHOULD BE). When intent conflicts with code, the resolution depends on the
current SDLC phase — see phase documents.

**Artifact presence determines retrieval.** Check whether spec files exist in the
workspace — this is independent of CLI installation. The `OpenSpec:` capability line
from session-start indicates CLI availability for write operations, but Intent Truth
retrieval works with or without the CLI.

## Source 1 (In-Progress): OpenSpec Active Changes

**Condition:** `openspec/changes/<feature>/` exists in the workspace

Read active change artifacts for the feature being worked on:
- `proposal.md` for the change proposal (what and why)
- `design.md` for design decisions in flight (how)
- `specs/<capability>/spec.md` for delta requirements (acceptance criteria)

Active changes represent approved-but-unfinished work. They are the most current
intent source during development. Cross-reference with Internal Truth (current code
state) when ambiguity exists.

## Source 2 (Authoritative): OpenSpec Canonical Specs

**Condition:** Source 1 has no matching active change AND `openspec/specs/<capability>/spec.md` exists

Read the canonical spec for the capability being worked on. Canonical specs are the
single source of truth for feature requirements after a change has been archived.

If canonical spec conflicts with code behavior, the spec defines intended behavior —
the code may have drifted.

## Source 3 (Historical): Superpowers Specs

**Condition:** Sources 1+2 returned no matching artifacts AND Superpowers spec files
exist in `docs/superpowers/specs/`

Search for matching design specs:
- `docs/superpowers/specs/*-<keyword>-design.md` for the design specification

Superpowers specs are point-in-time design documents. They may be stale if the code
evolved after the spec was written. Always cross-reference with Internal Truth (actual
code) before treating as authoritative.

## Source 4: No Artifacts — Skip

No intent context is available. Do NOT hallucinate feature requirements. If the task
requires understanding feature intent and no specs exist, ask the user.
```

### Key design choices

- **Active changes before canonical** — During development, the active change folder is the most current intent source. After archival, canonical specs become authoritative. This ordering naturally handles the v2-rewrite scenario without timestamp comparisons.
- **No timestamp/recency checks** — Active change presence IS the recency signal. If someone is rewriting a capability, they should have an active change folder. The tier doc doesn't paper over process gaps with fragile heuristics.
- **"Source" not "Tier" labels** — Honest about the ordering principle (artifact priority, not trust degradation).
- **OpenSpec wins over SP specs** — When OpenSpec artifacts exist (either active or canonical), SP specs are not consulted. SP specs are fallback only when no OpenSpec artifacts are present.

## 2. Phase Document Conditional Gates

### Triage & Plan (`triage-and-plan.md`) — Full Gate (Step 0)

Insert as the first numbered step, before existing content:

```markdown
### 0. Intent Truth

IF the task references a known feature or capability, check for specification context before planning:

- **IF `openspec/changes/<feature>/` exists:** Read `proposal.md`, `design.md`, and `specs/` for active change context. These represent the most current intent for this feature. Carry forward existing requirements and acceptance scenarios into the plan.
- **ELSE IF `openspec/specs/<capability>/spec.md` exists:** Read the canonical spec for authoritative requirements. The plan must satisfy all specified scenarios unless the user explicitly says otherwise.
- **ELSE IF `docs/superpowers/specs/` has a matching design spec:** Read it for design intent, but cross-reference with the current codebase — SP specs may be stale.
- **IF no artifacts found:** Proceed without spec context. If the task scope is ambiguous, ask the user to clarify requirements.
```

**Why Step 0:** Intent context shapes the entire plan. Knowing "what should this feature do" is more foundational than "what APIs does it use" or "have we seen this before." The spec sets the target; the other tiers inform the path.

### Implementation (`implementation.md`) — Minimal On-Demand Gate

Insert as a new numbered step in the existing "On-Demand" section (parallel to how External Truth already has an on-demand lookup pattern):

```markdown
### N. Intent Truth (On-Demand)

IF you encounter a design ambiguity not covered in the plan:
- **IF `openspec/specs/<capability>/spec.md` or `openspec/changes/<feature>/` exists:** Check for the specific edge case or requirement. Do NOT re-read the full spec — query only for the specific ambiguity.
- **IF no artifacts found:** Rely on the plan from Phase 1, or ask the user.
```

**Why minimal:** The plan already carries intent forward from Triage. The on-demand gate is a safety net for mid-implementation ambiguities that the plan didn't anticipate. Cost: ~5 lines added to an existing section.

### Code Review (`code-review.md`) — Full Gate (Step 0)

Insert as the first numbered step:

```markdown
### 0. Intent Truth (Requirement Verification)

IF reviewing changes to a specified capability:

- **IF `openspec/specs/<capability>/spec.md` exists:** Read it. Verify the implementation satisfies all acceptance scenarios. Flag any specified requirement that is missing from the implementation or tests.
- **ELSE IF `openspec/changes/<feature>/specs/` exists:** Read delta specs for the active change. Verify the implementation matches the specified scenarios.
- **ELSE IF `docs/superpowers/specs/` has a matching design spec:** Reference it for design intent verification, but note that SP specs may have diverged from implementation.
- **IF no artifacts found:** Review based on code quality and internal consistency only.
- **IF the PR intentionally diverges from spec:** Note this as a spec update candidate — the spec should be revised to match the new intent after shipping.
```

**Why Step 0:** "Does this implementation match what was specified?" is a core review question. Checking intent before reviewing code catches missing requirements early.

### Testing & Debug — No Change

Debugging is about current state (what IS broken), not intended state (what SHOULD happen). Internal Truth (trace dependencies), External Truth (library docs), and Historical Truth (past errors) cover this phase completely.

### Ship & Learn — No Change

Already has OpenSpec documentation tier from Spec A's `openspec-ship` integration. No additional gates needed.

## 3. SKILL.md Updates

### Capability Flags Table

Add a new row to the table in `skills/unified-context-stack/SKILL.md`:

```markdown
| `openspec_surface` | OpenSpec bootstrap | Intent retrieval source selection — `none` means no OpenSpec CLI, but artifacts may still exist in the workspace. Check artifact presence for retrieval. |
```

### Tier Documents List

Add to the tier documents list:

```markdown
- [Intent Truth](tiers/intent-truth.md) — Feature specification and design rationale retrieval
```

### Note on Artifact vs CLI

Add a brief note after the tier documents list:

```markdown
**Note:** Intent Truth checks for artifact presence in the workspace (`openspec/specs/`, `openspec/changes/`, `docs/superpowers/specs/`). The `OpenSpec:` capability line from session-start indicates CLI availability for write operations (used by `openspec-ship`), but Intent Truth retrieval works regardless of CLI installation — it reads local files.
```

## 4. Files to Modify

| File | Change |
|------|--------|
| `skills/unified-context-stack/tiers/intent-truth.md` | New file: Intent Truth tier document (~40 lines) |
| `skills/unified-context-stack/SKILL.md` | Add capability flag row + tier doc link + artifact note |
| `skills/unified-context-stack/phases/triage-and-plan.md` | Add Step 0: Intent Truth (full gate) |
| `skills/unified-context-stack/phases/implementation.md` | Add on-demand Intent Truth step (~5 lines) |
| `skills/unified-context-stack/phases/code-review.md` | Add Step 0: Intent Truth (full gate) |
| `tests/test-context.sh` | Content assertion tests |

## 5. Tests

Lightweight content assertions in `tests/test-context.sh`:

1. **intent-truth.md exists** — Assert `skills/unified-context-stack/tiers/intent-truth.md` is present.
2. **SKILL.md references intent-truth** — Assert `skills/unified-context-stack/SKILL.md` contains `intent-truth.md`.
3. **Triage-and-plan has openspec gate** — Assert `phases/triage-and-plan.md` contains `openspec`.
4. **Code-review has openspec gate** — Assert `phases/code-review.md` contains `openspec`.
5. **Existing conditional fallback test still passes** — The existing test "phase docs contain capability-conditional instructions" should continue to pass.

## Non-Goals

- Does NOT change unified-context-stack hook behavior or routing logic (Spec A's domain).
- Does NOT add new capability detection — consumes Spec A's `openspec_capabilities` and `OpenSpec:` line.
- Does NOT use timestamp comparison or recency heuristics for artifact selection.
- Does NOT add viability thresholds for artifact content quality.
- Does NOT modify Testing & Debug phase — intent truth doesn't help debug current-state failures.