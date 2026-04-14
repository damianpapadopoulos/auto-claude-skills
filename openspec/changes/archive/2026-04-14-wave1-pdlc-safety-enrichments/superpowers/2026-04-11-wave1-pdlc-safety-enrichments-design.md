# Wave 1: PDLC Acceleration and Agent-Safety Enrichments

**Date:** 2026-04-11
**Status:** Draft
**Phase:** DESIGN
**Origin:** Simon Willison podcast analysis — transcript-derived practices mapped against current plugin capabilities

## Problem Statement

The auto-claude-skills SDLC backbone (TDD, routing, review, phase composition) is mature. The gaps are upstream and cross-cutting:

1. **No runnable prototyping in DESIGN.** Brainstorming explores options conversationally. Design-debate argues about approaches. Neither produces comparable artifacts a user can evaluate side-by-side. Simon Willison's strongest practice: "I'll prototype three different ways it could work, because that takes very little time."

2. **No safety analysis for autonomous agent designs.** The repo has deterministic scanning (Semgrep/Trivy/Gitleaks via security-scanner) but zero architectural risk assessment for designs involving private data, untrusted input, and outbound actions. Willison's "lethal trifecta" pattern — when all three are present, the design is high-risk regardless of detection scores.

3. **No skill skeleton for new additions.** Every new SKILL.md is written from scratch by studying existing examples. Willison's key insight: "agents are phenomenally good at sticking to existing patterns. A single well-structured file sets the style for everything after it."

4. **No suite-level scenario evaluation.** Existing tests validate routing mechanics (regex matches, phase composition). They don't validate judgment — can the suite intercept "skip tests and ship" or "let the agent run overnight unsupervised"? The quality signal for the plugin as a whole is missing.

## Architecture Rule: Superpowers Contract

The superpowers plugin owns the canonical workflow backbone. These driver invariants are locked:

| Phase | Driver | Owner |
|-------|--------|-------|
| DESIGN | brainstorming | superpowers |
| PLAN | writing-plans | superpowers |
| IMPLEMENT | executing-plans | superpowers |
| REVIEW | requesting-code-review | superpowers |
| SHIP | verification-before-completion | superpowers |
| DEBUG | systematic-debugging | superpowers |

**Rules:**
- Do not add process skills that compete with these drivers
- Do not alter `phase_compositions.*.driver` or `phase_guide` for superpowers-owned phases
- DISCOVER and LEARN are repo-local edge overlays, not precedent for adding mid-pipeline phases
- All Wave 1 additions are domain skills or test infrastructure — no new phases, no new process skills

Superpowers skills chain internally (brainstorming → writing-plans → executing-plans → etc.) via HARD-GATEs in their SKILL.md files. The hook fires on user prompts, not skill-to-skill transitions. New skills cannot intercept the internal chain — they enrich it from the side.

## Wave 1 Skills

### 1. starter-template (Domain Skill)

**Purpose:** Emit repo-native seed files when creating new skills, commands, plugins, hooks, or modules. Ensures future agent work follows existing patterns from the first file.

**Phase anchor:** DESIGN (single scalar — the registry treats phase as one value)
**Role:** domain
**Activation:** Narrow triggers — `new skill`, `new plugin`, `new command`, `scaffold`, `skeleton`, `template`. Co-selects with `writing-skills` when that skill is active. Cross-phase usage: the skill's output (skeleton snippets) is naturally consumed during PLAN and IMPLEMENT, but the routing entry lives in DESIGN so it co-selects cleanly with writing-skills during the design conversation.

**Output contract:**
- One SKILL.md skeleton following repo conventions (frontmatter, steps, tiered detection, contracts)
- One routing entry snippet for `default-triggers.json` (name, role, phase, triggers, priority, precedes, requires, invoke)
- One routing test snippet for `tests/test-routing.sh`
- One content/behavior assertion snippet for test coverage

**Design decisions:**
- Produces snippets, not complete files. The user or agent integrates them into the actual config/test files.
- Does not auto-register skills — registration is a deliberate step reviewed during REVIEW phase.
- Skeleton adapts to skill type: domain skeleton includes tiered detection pattern; workflow skeleton includes composition pattern. Process skeletons are limited to repo-local edge overlays (DISCOVER, LEARN) since the architecture rule forbids competing with superpowers-owned phase drivers. The template must include a warning comment if the user requests a process skeleton for a superpowers-owned phase.

### 2. prototype-lab (Domain Skill)

**Purpose:** Produce exactly 3 thin, comparable variants of a proposed design so the user can evaluate concrete alternatives before committing to a direction.

**Phase anchor:** DESIGN
**Role:** domain
**Activation:** Narrow trigger-based co-selection during DESIGN phase. Triggers: `prototype`, `compare options`, `build variants`, `which approach`, `try both`, `try all`. When triggered, fires as a domain skill alongside brainstorming (which remains the process driver). The user or the DESIGN phase guidance in `phases/design.md` may suggest prototyping when competing approaches are identified, but prototype-lab does not depend on brainstorming internally escalating to it — superpowers owns brainstorming and we do not modify its behavior.

**Relationship to design-debate:**
- design-debate **reasons** about options (3 agents argue)
- prototype-lab **builds** comparable artifacts (3 thin variants)
- They are complementary. design-debate can precede prototype-lab (debate narrows to 3 candidates, lab builds them). They do not compete for the same routing slot.

**Output contract:**
- Exactly 3 variants, each containing the minimum artifacts to evaluate the approach. For skills: SKILL.md draft + routing entry + one behavioral test. For hooks: script draft + config entry + one test. For features: implementation sketch + one test.
- Comparison artifact at `docs/plans/YYYY-MM-DD-<topic>-prototype-lab.md` with:
  - Option A / B / C descriptions with trade-offs
  - Recommended option and reasoning
  - **Human Validation Plan** (required) — how the user will test the chosen option with real usage, not AI-simulated validation
  - Success signals — what to measure after shipping to confirm the choice was right
- Variants are disposable. Only the chosen variant proceeds to writing-plans. The other two are archived in the comparison artifact.

**Design decisions:**
- AI-simulated user testing may inform the draft (e.g., "I tested each variant against 5 sample prompts and variant B handled edge cases better") but never replaces human validation. The Human Validation Plan section is mandatory and must describe real-user or real-usage testing.
- For this repo specifically, "prototype" means repo-native artifacts (SKILL.md, bash scripts, routing config, tests), not web applications or UI mockups.
- 3 variants is the default. User can request fewer ("just compare these 2") or more, but the skill defaults to 3.

### 3. agent-safety-review (Cross-Cutting Domain Skill)

**Purpose:** Evaluate designs and implementations that involve autonomous agent behavior for the lethal trifecta pattern: private data access + untrusted input exposure + outbound action capability.

**Phase anchor:** DESIGN (primary). Co-selects during REVIEW when requesting-code-review is the process skill and autonomy-related triggers match.
**Role:** domain
**Activation:** Narrow triggers on repo-relevant autonomy language:
- `autonomous loop`, `ralph-loop`, `overnight`, `unattended`
- `background agent`, `browser agent`, `email agent`, `inbox agent`
- `YOLO`, `skip permissions`, `dangerously`, `permissionless`
- `auto reply`, `auto respond`, `send on behalf`

**Risk model:**

| Field | Question | Examples |
|-------|----------|----------|
| `private_data` | Does the agent access information that should not be shared with all parties? | User email, credentials, internal logs, PII, private repos |
| `untrusted_input` | Can an external party inject instructions the agent will process? | Email content, web pages, user-uploaded files, API responses from third parties |
| `outbound_action` | Can the agent send data or take actions visible outside its sandbox? | Sending emails, posting to Slack, pushing to git, making API calls, writing to shared filesystems |

**Decision logic:**
- If all 3 present → **Lethal trifecta.** Classify as high risk. Require mitigation: cut at least one leg, or introduce a quarantine boundary with narrowly scoped human-in-the-loop on high-risk actions only.
- If 2 of 3 present → **Elevated risk.** Note which leg is missing and why. Recommend not adding the third without mitigation.
- If 0-1 present → **Standard risk.** No special action required.

**Design decisions:**
- Separate from security-scanner. security-scanner runs deterministic static analysis (Semgrep/Trivy/Gitleaks). agent-safety-review is architectural risk assessment. Different tools, different timing, different failure modes.
- Does not claim that improved detection scores solve the problem. The skill must explicitly state that blast-radius controls (cutting a leg of the trifecta) are the primary mitigation, not better filtering.
- Produces a structured risk assessment, not a pass/fail gate. The user decides whether to accept the risk, but the skill ensures the decision is informed.

### 4. scenario-evals (Test Infrastructure)

**Purpose:** Suite-level behavioral evaluation that tests the plugin's judgment, not just its routing mechanics. Validates that the right skills fire for the right prompts and that guardrails actually intercept unsafe patterns.

**Location:** `tests/test-scenario-evals.sh` + `tests/fixtures/scenarios/`
**Activation:** `bash tests/test-scenario-evals.sh` (not a routed skill)

**Scenario categories (12 initial scenarios):**

**PDLC scenarios (3):**
1. Multi-variant feature design prompt → prototype-lab co-selects with brainstorming
2. "Which approach should we take?" → prototype-lab triggers, not just brainstorming alone
3. New skill creation prompt → starter-template co-selects with writing-skills

**Safety scenarios (3):**
4. Lethal-trifecta prompt (email agent with auto-reply) → agent-safety-review fires
5. "Run this overnight unattended" → agent-safety-review fires
6. "Skip permissions, YOLO mode" → agent-safety-review fires

**Guardrail scenarios (3):**
7. "Skip tests and ship it" → verification-before-completion still required in composition
8. "Just ship it, no review needed" → requesting-code-review still required in composition
9. "Let the agent keep trying overnight" → agent-safety-review fires (overnight autonomous loop matches trigger set)

**Driver-invariant scenarios (3):**
10. DESIGN prompt → brainstorming is process skill (not prototype-lab, not agent-safety-review)
11. IMPLEMENT prompt → executing-plans is process skill
12. REVIEW prompt → requesting-code-review is process skill

**Design decisions:**
- Scenarios are fixture-based: each is a JSON file with `prompt`, `expected_skills`, `expected_phase`, `must_not_match` fields.
- Tests run the hook against each fixture and assert the output matches expectations.
- Driver-invariant tests specifically verify that the superpowers contract hasn't been violated by new additions.
- Scenario 9 (overnight loop) validates that agent-safety-review triggers on autonomous-loop language. Wave 2 attention-budget may add a methodology hint on top, but the safety trigger is the Wave 1 coverage.

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `skills/starter-template/SKILL.md` | Create | Skill definition |
| `skills/prototype-lab/SKILL.md` | Create | Skill definition |
| `skills/agent-safety-review/SKILL.md` | Create | Skill definition |
| `config/default-triggers.json` | Modify | Add routing entries for 3 new skills |
| `config/fallback-registry.json` | Modify | Add fallback entries for 3 new skills |
| `skills/unified-context-stack/phases/design.md` | Modify | Add prototype-lab and agent-safety-review awareness |
| `tests/test-scenario-evals.sh` | Create | Scenario evaluation test runner |
| `tests/fixtures/scenarios/` | Create | 12 scenario fixture files |
| `tests/test-routing.sh` | Modify | Add routing assertions for new skills |

## Files NOT to Modify

- Superpowers skill files under `~/.claude/plugins/cache/`
- `phase_guide` or `phase_compositions.*.driver` entries in registry files
- Process skill definitions for superpowers-owned phases
- `hooks/skill-activation-hook.sh` (routing logic stays unchanged — new skills work via config, not hook modifications)

## What This Design Does NOT Do

- Does not create a new PROTOTYPE or SAFETY phase
- Does not insert prototype-lab as a mandatory step between brainstorming and writing-plans
- Does not make agent-safety-review a process skill
- Does not use always-on phase-composition parallels for Wave 1 skills
- Does not merge agent-safety-review into security-scanner
- Does not modify the superpowers internal chaining (HARD-GATEs)
- Does not change the hook scoring engine — new skills work entirely via config additions

## Wave 2 (Deferred)

These items are designed but deferred until Wave 1 is stable:

- **research-capture:** `docs/experiments/` convention with Question/Setup/What Ran/Evidence/Verdict/Reusable Pattern schema. LEARN-first skill with DESIGN/PLAN retrieval via Historical Truth.
- **usage-verification:** SHIP soft gate between verification-before-completion and openspec-ship. Warn-not-block until environment detection is reliable.
- **feasibility-probe:** PLAN methodology enhancement to writing-plans. Evidence-based scope calibration before estimation.
- **attention-budget:** Methodology hint folded into dispatching-parallel-agents and agent-team-execution. Warns on >2 active parallel workstreams or overnight autonomous loop prompts.
- **LEARN baseline extension:** Add optional `chosen_variant`, `success_signals`, `decision_rationale` fields to the learn baseline contract in `outcome-review/SKILL.md`. prototype-lab writes these fields in its comparison artifact; outcome-review consumes them when reviewing prototype-lab features. Deferred because outcome-review consumption won't happen until Wave 1 skills have shipped and been used in practice.
