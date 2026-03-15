# Design: Required Role + SDLC Chain Bridging

## Overview

Add a `required` role to the skill routing engine that bypasses the 1-process / 2-domain / 1-workflow caps, and bridge the IMPLEMENT-to-REVIEW and REVIEW-to-SHIP gaps to create a single end-to-end SDLC composition chain.

## Motivation

The current role-cap system (max 1 process, 2 domain, 1 workflow, total 3) treats all skills within a role as competing alternatives. This is correct for genuine alternatives (e.g., `agent-team-execution` vs `batch-scripting`) but incorrect for skills that are complementary overlays, mandatory gates, or infrastructure enablers:

1. **TDD vs executing-plans** — TDD is a methodology overlay on implementation, not an alternative execution driver. When both trigger during IMPLEMENT, executing-plans wins (priority 35) and TDD gets capped.
2. **security-scanner at REVIEW** — Security analysis should be mandatory during every review, not a keyword-triggered optional domain skill that only activates when the user mentions "security."
3. **using-git-worktrees at IMPLEMENT** — Worktrees provide isolation infrastructure for parallel agent work. They enable `agent-team-execution` and `dispatching-parallel-agents`, they don't compete with them.
4. **agent-team-review at REVIEW** — Multi-perspective specialist review should be invoked when the change warrants it (3+ files, cross-module, security-sensitive), not dropped because the total cap was reached.

Additionally, the SDLC composition chain has two gaps:

```
brainstorming -> writing-plans -> executing-plans    (stops)
                     requesting-code-review           (isolated)
verification-before-completion -> openspec-ship -> finishing-a-development-branch
```

The model has no chain-based guidance to transition from IMPLEMENT to REVIEW or from REVIEW to SHIP. These transitions happen only when the user's next prompt triggers different keywords.

## 1. The `required` Role

### Schema

A skill with `"role": "required"` in `default-triggers.json`:
- Does **not** count against the 1-process / 2-domain / 1-workflow caps
- Does **not** count against `MAX_SUGGESTIONS` (total cap)
- Is collected in a separate **pass 0** before the existing process reservation (pass 1)
- Has no per-role cap (but practically limited to 3-4 skills total)
- Activation depends on gating mode (see below)

### Gating Modes

Required skills have two activation modes, determined by whether they have triggers:

**Phase-gated** (`"triggers": []`): Activates whenever the tentative phase matches the skill's phase. No trigger match needed. Use for skills that must always be present at their phase.

**Trigger-gated** (`"triggers": [...]`): Activates when the tentative phase matches AND at least one trigger matches the prompt. Use for skills that should bypass caps when relevant but aren't needed on every prompt.

Additionally, required skills can be **condition-gated** via the `required_when` field:

- Skills without `required_when` are always invoked once activated (phase-gated or trigger-gated).
- Skills with `required_when` are presented to the model for evaluation — the model decides whether the condition is met. The condition string is displayed in the output.

```json
{
  "name": "agent-team-review",
  "role": "required",
  "phase": "REVIEW",
  "required_when": "PR touches 3+ files, crosses module boundaries, or includes security-sensitive changes",
  "triggers": ["(review|pull.?request|code.?review|...)"],
  ...
}
```

### Tentative Phase Computation

Pass 0 needs to know the current phase to filter required skills, but `PRIMARY_PHASE` is computed from `SELECTED` (which pass 0 is building). To break this circularity:

Compute a **tentative phase** from `SORTED` (pre-selection) by reading the phase of the highest-scoring process skill. If no process skill scored, use the highest-scoring skill regardless of role. This tentative phase is used only for pass 0 gating. The authoritative `PRIMARY_PHASE` is still computed from `SELECTED` in `_determine_label_phase()` after all passes complete.

```bash
# Tentative phase: top process skill in SORTED, else top skill overall
_TENTATIVE_PHASE=""
while IFS='|' read -r score name role invoke phase; do
  [[ -z "$name" ]] && continue
  if [[ "$role" == "process" ]]; then
    _TENTATIVE_PHASE="$phase"
    break
  fi
  [[ -z "$_TENTATIVE_PHASE" ]] && _TENTATIVE_PHASE="$phase"
done <<EOF
${SORTED}
EOF
```

### Output Format

Required skills appear before the process skill, with appropriate eval tags:

```
Required: test-driven-development -> Skill(superpowers:test-driven-development)
Required: security-scanner -> Skill(security-scanner)
Process: executing-plans -> Skill(superpowers:executing-plans)
  Domain: frontend-design -> Call Skill(frontend-design:frontend-design)
Workflow: agent-team-execution -> Skill(auto-claude-skills:agent-team-execution)
Required when multi-file/cross-module/security-sensitive: agent-team-review -> Skill(auto-claude-skills:agent-team-review)
```

Eval line:

```
Evaluate: **Phase: [IMPLEMENT]** | test-driven-development REQUIRED, security-scanner REQUIRED,
  executing-plans MUST INVOKE, frontend-design YES/NO, agent-team-execution YES/NO,
  agent-team-review INVOKE WHEN: PR touches 3+ files, crosses module boundaries, or includes security-sensitive changes
```

Unconditional required skills use the tag `REQUIRED`. Conditional required skills use `INVOKE WHEN: <condition>`.

## 2. Skills to Reclassify

### Phase-Gated Required (always present at their phase)

| Skill | From | To | Phase | Gating | Triggers | Rationale |
|-------|------|----|-------|--------|----------|-----------|
| `test-driven-development` | *not in default-triggers.json* (auto-discovered at runtime as domain, priority 200) | **required** (IMPLEMENT) | IMPLEMENT | phase-gated | `[]` (empty — always active at IMPLEMENT) | Methodology overlay — disciplines HOW you implement, doesn't compete with WHAT drives execution. Adding as explicit entry overrides the auto-discovery path; explicit entries take precedence. |
| `security-scanner` | domain (REVIEW, priority 15) | **required** (REVIEW) | REVIEW | phase-gated | `[]` (empty — always active at REVIEW) | Mandatory gate — security analysis on every review, mirroring how `security-guidance` (PreToolUse hook) is always-on during writes. Cross-phase security coverage continues via the PreToolUse hook. |

### Trigger-Gated Required (bypass caps when relevant)

| Skill | From | To | Phase | Gating | Triggers | Rationale |
|-------|------|----|-------|--------|----------|-----------|
| `using-git-worktrees` | workflow (IMPLEMENT, priority 14, triggers `[]`) | **required** (IMPLEMENT) | IMPLEMENT | trigger-gated | `["(parallel\|concurrent\|worktree\|isolat\|branch.*(work\|switch))"]` (NEW — currently has empty triggers) | Infrastructure enabler — provides isolation for parallel agent work, foundation for agent-team-execution. Only relevant when parallel/isolation keywords are present. |

### Trigger-Gated + Condition-Gated Required

| Skill | From | To | Phase | Gating | Condition | Rationale |
|-------|------|----|-------|--------|-----------|-----------|
| `agent-team-review` | workflow (REVIEW, priority 20) | **required** (REVIEW) | REVIEW | trigger-gated + condition-gated | PR touches 3+ files, crosses module boundaries, or includes security-sensitive changes | Multi-perspective specialist review should be invoked when the change warrants it, not dropped because the total cap was reached. |

### What Stays As-Is

All other process/domain/workflow skills keep their current roles — they represent genuine alternatives that should compete for slots. The SHIP workflow sequence (verification -> openspec -> finish) stays as-is since the composition chain display already handles sequencing correctly.

## 3. SDLC Chain Bridging

### New Links

| Skill | Field | Add Value | Creates Link |
|-------|-------|-----------|--------------|
| `executing-plans` | `precedes` | `["requesting-code-review"]` | IMPLEMENT -> REVIEW |
| `requesting-code-review` | `requires` | `["executing-plans"]` | REVIEW backward-links to IMPLEMENT |
| `requesting-code-review` | `precedes` | `["verification-before-completion"]` | REVIEW -> SHIP |
| `verification-before-completion` | `requires` | `["requesting-code-review"]` | SHIP backward-links to REVIEW |

### Resulting End-to-End Chain

```
brainstorming -> writing-plans -> executing-plans -> requesting-code-review -> verification-before-completion -> openspec-ship -> finishing-a-development-branch
   DESIGN          PLAN           IMPLEMENT            REVIEW                        SHIP --------------------------------------------------------
```

### Chain Display Example (mid-implementation)

```
Composition: DESIGN -> PLAN -> IMPLEMENT -> REVIEW -> SHIP
  [DONE] Step 1: Skill(superpowers:brainstorming) -- Ask clarifying questions, explore options, and get user approval before planning
  [DONE] Step 2: Skill(superpowers:writing-plans) -- Break work into discrete tasks and confirm before execution
  [CURRENT] Step 3: Skill(superpowers:executing-plans) -- Step-by-step execution of an approved plan
  [NEXT] Step 4: Skill(superpowers:requesting-code-review) -- Prepare and request a code review
  [LATER] Step 5: Skill(superpowers:verification-before-completion) -- Final verification checklist before shipping
  [LATER] Step 6: Skill(auto-claude-skills:openspec-ship) -- Create retrospective OpenSpec change
  [LATER] Step 7: Skill(superpowers:finishing-a-development-branch) -- Branch cleanup and merge
```

### Safety Properties

- `precedes`/`requires` are **guidance, not gates** — they create chain display and +20 context bonus, but don't block independent activation
- DEBUG remains a side-loop that enters/exits at any point, not part of the linear chain
- A user saying "ship this quick fix" still activates `verification-before-completion` directly — skipped steps show `[DONE?]` markers, informing the model that review was expected but may have been skipped
- Backward chain walk (`requires`) shows predecessors; forward chain walk (`precedes`) shows successors; neither blocks

## 4. REVIEW Phase Sequencing

With the new required skills, the REVIEW phase has internal ordering:

1. **`requesting-code-review`** (process driver) — summarize changes, identify scope and risks
2. **`agent-team-review`** (condition-gated required) — dispatch parallel specialist reviewers from pr-review-toolkit (code-reviewer, silent-failure-hunter, code-simplifier, comment-analyzer, pr-test-analyzer, type-design-analyzer)
3. **`security-scanner`** (phase-gated required) — mandatory security gate

This ordering is conveyed through the pass 0 output: required skills appear before process/domain/workflow in the output, with phase-gated skills listed first (always present), then trigger-gated skills. No new `required_sequence` field is needed in `phase_compositions` — the existing `parallel` entries for pr-review-toolkit remain as-is since they describe execution tools dispatched within `agent-team-review`, not competing skills.

## 5. Routing Engine Changes

### `_select_by_role_caps()` in `skill-activation-hook.sh`

Add **tentative phase computation** and **pass 0** before the existing process reservation (pass 1):

```
Tentative phase: Scan SORTED for top process skill's phase (else top skill's phase).

Pass 0: Scan SORTED for required-role skills.
         Phase-gated (triggers empty): include if phase matches tentative phase.
         Trigger-gated (triggers present): include if phase matches AND already scored > 0.
         These go into REQUIRED_SELECTED, do not increment role counters,
         do not count against MAX_SUGGESTIONS.
         Track count in REQUIRED_COUNT (for display).

Pass 1: (existing) Reserve top process skill.

Pass 2: (existing) Fill remaining domain/workflow slots using CAPPED_COUNT
         (excludes REQUIRED_COUNT) for the MAX_SUGGESTIONS check.
```

Required skills are stored in `REQUIRED_SELECTED` and prepended to `SELECTED` for output formatting. `TOTAL_COUNT` includes required skills (for accurate display in the header). `CAPPED_COUNT` excludes them (for cap enforcement).

### `_build_skill_lines()` in `skill-activation-hook.sh`

Add a `_SL_REQUIRED` accumulator for required-role display lines. Required lines appear before process lines in the output.

For conditional required skills (`required_when` is non-empty), the display line includes the condition:
```
Required when <condition>: <name> -> <invoke>
```

### `_determine_label_phase()` in `skill-activation-hook.sh`

Required skills do not set the primary label (`PLABEL`). The label continues to be driven by process > workflow > domain priority. Required skills are acknowledged with a `+ Required` suffix if any are present.

### Eval line generation in `_format_output()`

Required skills get the `REQUIRED` tag (unconditional) or `INVOKE WHEN: <condition>` tag (conditional) instead of `MUST INVOKE` or `YES/NO`.

## 6. Registry Schema Changes

### `default-triggers.json` skill entries

New field: `required_when` (string, optional). Present only on conditional required skills. Absence means unconditional.

Role value `"required"` is now valid alongside `"process"`, `"domain"`, `"workflow"`.

### Updated skill entries

**test-driven-development** (NEW entry — not currently in default-triggers.json):

This skill is currently auto-discovered at runtime by `session-start-hook.sh` (lines 245-258) from the superpowers plugin filesystem, where it gets assigned `role: "domain"` and `priority: 200`. Adding an explicit entry in `default-triggers.json` overrides the auto-discovery path — explicit entries take precedence over runtime discovery.

```json
{
  "name": "test-driven-development",
  "role": "required",
  "phase": "IMPLEMENT",
  "triggers": [],
  "keywords": [],
  "trigger_mode": "regex",
  "priority": 20,
  "precedes": [],
  "requires": [],
  "description": "Write failing test first, then implement until green. Phase-gated: always active during IMPLEMENT."
}
```

**security-scanner** (role change from `domain` to `required`, triggers cleared):
```json
{
  "name": "security-scanner",
  "role": "required",
  "phase": "REVIEW",
  "triggers": [],
  "keywords": [],
  "trigger_mode": "regex",
  "priority": 15,
  "precedes": [],
  "requires": [],
  "description": "Security analysis overlay: scan for vulnerabilities, OWASP risks, compliance issues. Phase-gated: always active during REVIEW."
}
```

Both TDD and security-scanner have empty triggers (phase-gated): they activate on every prompt at their designated phase. For cross-phase security concerns (e.g., security keywords during IMPLEMENT), the `security-guidance` PreToolUse hook provides continuous write-time coverage. The scanner is the REVIEW gate; the hook is the continuous guard.

**using-git-worktrees** (role change from `workflow` to `required`, triggers ADDED — currently empty):
```json
{
  "name": "using-git-worktrees",
  "role": "required",
  "phase": "IMPLEMENT",
  "triggers": ["(parallel|concurrent|worktree|isolat|branch.*(work|switch))"],
  "keywords": [],
  "trigger_mode": "regex",
  "priority": 14,
  "precedes": [],
  "requires": [],
  "description": "Use git worktrees to enable parallel work on multiple branches without stashing. Trigger-gated: activates when parallel/isolation keywords are present."
}
```

**agent-team-review** (role change from `workflow` to `required`, `required_when` ADDED):
```json
{
  "name": "agent-team-review",
  "role": "required",
  "phase": "REVIEW",
  "required_when": "PR touches 3+ files, crosses module boundaries, or includes security-sensitive changes",
  "triggers": ["(team.review|multi.*(perspective|reviewer|agent).*(review|check)|thorough.*review|comprehensive.*review|full.*review)", "(review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|(^|[^a-z])pr($|[^a-z]))"],
  "keywords": [],
  "trigger_mode": "regex",
  "priority": 20,
  "precedes": [],
  "requires": [],
  "description": "Multi-perspective parallel code review with specialist reviewers (security, quality, spec compliance). Trigger-gated + condition-gated."
}
```

### Updated chain links

**executing-plans** — add `"precedes": ["requesting-code-review"]`:
```json
{
  "name": "executing-plans",
  "precedes": ["requesting-code-review"],
  "requires": ["writing-plans"],
  ...
}
```

**requesting-code-review** — add `"precedes"` and `"requires"`:
```json
{
  "name": "requesting-code-review",
  "precedes": ["verification-before-completion"],
  "requires": ["executing-plans"],
  ...
}
```

**verification-before-completion** — add `"requires"`:
```json
{
  "name": "verification-before-completion",
  "requires": ["requesting-code-review"],
  "precedes": ["openspec-ship"],
  ...
}
```

## 7. Files to Modify

| File | Change |
|------|--------|
| `config/default-triggers.json` | Add `test-driven-development` as NEW entry (role=required, triggers=[], phase=IMPLEMENT); reclassify `security-scanner` (role→required, triggers→[]); reclassify `using-git-worktrees` (role→required, ADD triggers); reclassify `agent-team-review` (role→required, ADD required_when); add chain links (precedes/requires) to `executing-plans`, `requesting-code-review`, `verification-before-completion` |
| `config/fallback-registry.json` | Regenerate to reflect updated registry |
| `hooks/skill-activation-hook.sh` | Add tentative phase computation before `_select_by_role_caps()`; add pass 0 for required skills (phase-gated and trigger-gated); add `REQUIRED_SELECTED`, `REQUIRED_COUNT`, `CAPPED_COUNT` variables; add `_SL_REQUIRED` to `_build_skill_lines()`; update eval tag generation in `_format_output()` for `REQUIRED` and `INVOKE WHEN:` tags; update `_determine_label_phase()` for `+ Required` suffix |
| `tests/test-routing.sh` | Add 10 new tests (7 required role + 3 chain bridging); update existing `test_tdd_not_scored_as_process` to verify TDD appears as `Required:` instead |

## 8. Tests

### Required role routing (`tests/test-routing.sh`)

1. **Required skill bypasses process cap** — Prompt triggers both `test-driven-development` (required) and `executing-plans` (process). Assert both appear in output; TDD as `REQUIRED`, executing-plans as `MUST INVOKE`.
2. **Required skill bypasses domain cap** — Prompt triggers `security-scanner` (required) plus 2 domain skills. Assert all 3 appear (scanner + 2 domains); scanner doesn't consume a domain slot.
3. **Required skill bypasses workflow cap** — Prompt triggers `using-git-worktrees` (required) and `agent-team-execution` (workflow). Assert both appear; worktrees as `REQUIRED`, agent-team-execution with its workflow slot.
4. **Required skill bypasses total cap** — Prompt triggers 1 process + 2 domains + 1 workflow + 1 required. Assert total output is 5 skills (required not counted against MAX_SUGGESTIONS=3).
5. **Conditional required shows INVOKE WHEN** — Prompt triggers `agent-team-review` (conditional required). Assert eval line contains `INVOKE WHEN:` with the condition text, not `REQUIRED` or `YES/NO`.
6. **Phase-gated required activates without trigger** — Prompt "review my changes" during REVIEW phase (no security keywords). Assert `security-scanner` appears as `REQUIRED` (phase-gated, no trigger needed).
7. **Phase-gated required does NOT activate at wrong phase** — Prompt during IMPLEMENT phase. Assert `security-scanner` does NOT appear (phase mismatch — it's phase-gated to REVIEW).
8. **Required skills don't set PLABEL** — Use a minimal test registry containing only required skills (no process/domain/workflow). Assert PLABEL falls back to `(Claude: assess intent)`.

### Chain bridging (`tests/test-routing.sh`)

9. **End-to-end chain from brainstorming** — Simulate chain walk from `brainstorming`. Assert chain includes all 7 steps: brainstorming -> writing-plans -> executing-plans -> requesting-code-review -> verification-before-completion -> openspec-ship -> finishing-a-development-branch.
10. **Mid-chain entry at REVIEW** — Simulate prompt triggering `requesting-code-review` with last-invoked `executing-plans`. Assert chain shows [DONE] for steps 1-3, [CURRENT] for step 4, [NEXT] for step 5.
11. **Skipped-step markers** — Simulate prompt triggering `verification-before-completion` without prior `requesting-code-review`. Assert step 4 shows `[DONE?]` (not `[DONE]`).

### Chain bonus behavior (documented, not tested)

The `requires` link from `requesting-code-review` to `executing-plans` gives review a +20 context bonus after plan execution completes. This means plan-driven work gets a smoother REVIEW transition than ad-hoc work. This is acceptable and intentional — the full SDLC flow should be the path of least resistance.

## Non-Goals

- Does NOT change superpowers skill content (SKILL.md files are immutable in the external plugin).
- Does NOT modify the composition chain mechanism — only extends existing `precedes`/`requires` links.
- Does NOT add a new hook type — the required role is handled within the existing `skill-activation-hook.sh` scoring and selection flow.
- Does NOT change `security-guidance` (PreToolUse hook) — that remains always-on. The `security-scanner` required role is the review-time gate; the hook is the continuous write-time guard.