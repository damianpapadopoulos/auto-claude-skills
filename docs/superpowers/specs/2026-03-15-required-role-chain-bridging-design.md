# Design: Composition Parallels + Required Role + SDLC Chain Bridging

## Overview

Three complementary mechanisms to eliminate skill competition where skills should cooperate, not compete:

1. **Composition parallels** (already proven) — for always-on skills at a phase, using the existing plugin-less parallel entry pattern from the TDD promotion on `feat/tdd-parallel-promotion`
2. **`required` role** (new) — for trigger-gated and condition-gated skills that should bypass caps when activated but aren't needed on every prompt
3. **SDLC chain bridging** — connect IMPLEMENT → REVIEW → SHIP via `precedes`/`requires` links for end-to-end composition chain visibility

## Motivation

The current role-cap system (max 1 process, 2 domain, 1 workflow, total 3) treats all skills within a role as competing alternatives. This is correct for genuine alternatives (e.g., `agent-team-execution` vs `batch-scripting`) but incorrect for skills that are complementary overlays, mandatory gates, or infrastructure enablers:

1. **TDD vs executing-plans** — TDD is a methodology overlay on implementation, not an alternative execution driver. **Already solved** on `feat/tdd-parallel-promotion` via composition parallels.
2. **security-scanner at REVIEW** — Security analysis should be mandatory during every review, not a keyword-triggered optional domain skill.
3. **using-git-worktrees at IMPLEMENT** — Worktrees provide isolation infrastructure for parallel agent work. They enable `agent-team-execution`, they don't compete with it.
4. **agent-team-review at REVIEW** — Multi-perspective specialist review should be invoked when the change warrants it, not dropped because the total cap was reached.

Additionally, the SDLC composition chain has two gaps:

```
brainstorming -> writing-plans -> executing-plans    (stops)
                     requesting-code-review           (isolated)
verification-before-completion -> openspec-ship -> finishing-a-development-branch
```

## 1. Composition Parallels (always-on skills)

### Pattern (already proven)

The `feat/tdd-parallel-promotion` branch demonstrated that always-on skills can be handled via plugin-less `parallel` entries in `phase_compositions`. TDD was:
- Removed from the `skills[]` array (no longer scored/selected)
- Added as a parallel entry with `"when": "always"` in IMPLEMENT and DEBUG compositions
- The hook's jq filter was extended to handle entries without a `.plugin` field

This requires **zero engine changes** — just registry entries.

### Apply to: security-scanner

Add `security-scanner` as a plugin-less parallel entry in the REVIEW phase composition, mirroring the TDD pattern:

```json
"REVIEW": {
  "driver": "requesting-code-review",
  "parallel": [
    {
      "use": "security-scanner -> Skill(security-scanner)",
      "when": "always",
      "purpose": "Scan for vulnerabilities, OWASP risks, compliance issues. INVOKE during every review"
    },
    ...existing pr-review-toolkit entries...
  ]
}
```

Also remove `security-scanner` from the `skills[]` array (it no longer competes for domain slots). Cross-phase security coverage continues via the `security-guidance` PreToolUse hook (always-on during writes). The scanner is the REVIEW gate; the hook is the continuous guard.

### What this covers

| Skill | Phase | Mechanism | Status |
|-------|-------|-----------|--------|
| `test-driven-development` | IMPLEMENT, DEBUG | composition parallel | **Already done** on branch |
| `security-scanner` | REVIEW | composition parallel | **New — this spec** |

## 2. The `required` Role (conditional skills)

### Why compositions aren't enough

Composition parallels are always-on — they fire on every prompt at their phase. This is wrong for:
- **`using-git-worktrees`** — only relevant when parallel/isolation keywords match; showing it on every IMPLEMENT prompt adds noise
- **`agent-team-review`** — only appropriate for substantial changes (3+ files, cross-module, security-sensitive); a quick diff check doesn't need 6 specialist agents

These need **trigger-gating** (match keywords first) and/or **condition-gating** (model evaluates whether to invoke). The `required` role provides this.

### Schema

A skill with `"role": "required"` in `default-triggers.json`:
- Activates when its **phase matches** the tentative phase AND at least one trigger matches the prompt
- Does **not** count against the 1-process / 2-domain / 1-workflow caps
- Does **not** count against `MAX_SUGGESTIONS` (total cap)
- Is collected in a separate **pass 0** before the existing process reservation (pass 1)

Skills with `required_when` are **condition-gated** — the model evaluates whether the condition is met. Skills without `required_when` are invoked whenever they activate.

### Tentative Phase Computation

Pass 0 needs to know the current phase, but `PRIMARY_PHASE` is computed from `SELECTED` (which pass 0 is building). To break this circularity:

Compute a **tentative phase** from `SORTED` (pre-selection) by reading the phase of the highest-scoring process skill. If no process skill scored, use the highest-scoring skill regardless of role.

```bash
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

Required skills appear before the process skill:

```
Required: using-git-worktrees -> Skill(superpowers:using-git-worktrees)
Required when multi-file/cross-module/security-sensitive: agent-team-review -> Skill(auto-claude-skills:agent-team-review)
Process: executing-plans -> Skill(superpowers:executing-plans)
  Domain: frontend-design -> Call Skill(frontend-design:frontend-design)
Workflow: agent-team-execution -> Skill(auto-claude-skills:agent-team-execution)
```

Eval tags: `REQUIRED` for unconditional, `INVOKE WHEN: <condition>` for condition-gated.

### Skills to reclassify

| Skill | From | To | Phase | Gating | Rationale |
|-------|------|----|-------|--------|-----------|
| `using-git-worktrees` | workflow (IMPLEMENT, priority 14, triggers `[]`) | **required** (IMPLEMENT) | IMPLEMENT | trigger-gated: `["(parallel\|concurrent\|worktree\|isolat\|branch.*(work\|switch))"]` (NEW triggers) | Infrastructure enabler — provides isolation for parallel agent work. Only relevant when parallel/isolation keywords match. |
| `agent-team-review` | workflow (REVIEW, priority 20) | **required** (REVIEW) | REVIEW | trigger-gated + condition-gated: `required_when: "PR touches 3+ files, crosses module boundaries, or includes security-sensitive changes"` | Multi-perspective review should be invoked when warranted, not dropped by cap squeeze. |

## 3. SDLC Chain Bridging

### New Links

| Skill | Field | Add Value | Creates Link |
|-------|-------|-----------|--------------|
| `executing-plans` | `precedes` | `["requesting-code-review"]` | IMPLEMENT → REVIEW |
| `requesting-code-review` | `requires` | `["executing-plans"]` | REVIEW backward-links to IMPLEMENT |
| `requesting-code-review` | `precedes` | `["verification-before-completion"]` | REVIEW → SHIP |
| `verification-before-completion` | `requires` | `["requesting-code-review"]` | SHIP backward-links to REVIEW |

### Resulting End-to-End Chain

```
brainstorming → writing-plans → executing-plans → requesting-code-review → verification-before-completion → openspec-ship → finishing-a-development-branch
   DESIGN          PLAN           IMPLEMENT            REVIEW                        SHIP ────────────────────────────────────────────────
```

### Chain Display Example (mid-implementation)

```
Composition: DESIGN -> PLAN -> IMPLEMENT -> REVIEW -> SHIP
  [DONE] Step 1: Skill(superpowers:brainstorming)
  [DONE] Step 2: Skill(superpowers:writing-plans)
  [CURRENT] Step 3: Skill(superpowers:executing-plans)
  [NEXT] Step 4: Skill(superpowers:requesting-code-review)
  [LATER] Step 5: Skill(superpowers:verification-before-completion)
  [LATER] Step 6: Skill(auto-claude-skills:openspec-ship)
  [LATER] Step 7: Skill(superpowers:finishing-a-development-branch)
```

### Safety Properties

- `precedes`/`requires` are **guidance, not gates** — they create chain display and +20 context bonus, but don't block independent activation
- DEBUG remains a side-loop, not part of the linear chain
- Skipped steps show `[DONE?]` markers — the model sees what was expected but potentially skipped
- The `requires` link gives review a +20 bonus after plan execution, making the full SDLC flow the path of least resistance. This is intentional.

## 4. Routing Engine Changes

### Composition parallels (security-scanner)

**No engine changes needed.** The jq filter for plugin-less parallels already exists from the TDD promotion. Only registry changes:
- Remove `security-scanner` from `skills[]` array
- Add parallel entry to `REVIEW.parallel[]`

### `required` role (git-worktrees, agent-team-review)

#### SKILL_DATA extraction

Extend the jq extraction (lines 914-919) to include `required_when` as a 9th field:

```jq
(.name + "\u001f" + (.name | ascii_downcase) + "\u001f" + .role + "\u001f" +
 (.priority // 0 | tostring) + "\u001f" + (.invoke // "SKIP") + "\u001f" +
 (.phase // "") + "\u001f" + ((.triggers // []) | join("\u0001")) + "\u001f" +
 ((.keywords // []) | join("\u0001")) + "\u001f" + (.required_when // ""))
```

#### `_select_by_role_caps()`

Add tentative phase computation and pass 0:

```
Tentative phase: top process skill's phase from SORTED.

Pass 0: Scan SORTED for required-role skills where phase matches tentative phase
         AND score > 0. Add to REQUIRED_SELECTED. Do not increment role counters
         or count against MAX_SUGGESTIONS. Track in REQUIRED_COUNT.

Pass 1: (existing) Reserve top process skill. Skip REQUIRED_SELECTED members.

Pass 2: (existing) Fill domain/workflow slots. Use CAPPED_COUNT (excludes
         REQUIRED_COUNT) for MAX_SUGGESTIONS check. Skip REQUIRED_SELECTED members.
```

Note: since both required skills are trigger-gated (non-empty triggers), they WILL be in SORTED when they match. No separate REGISTRY scan is needed (unlike the previous spec version which also handled phase-gated required skills).

#### `_build_skill_lines()`

Add `_SL_REQUIRED` accumulator. For condition-gated skills, display:
```
Required when <condition>: <name> -> <invoke>
```

#### `_determine_label_phase()`

Required skills do not set PLABEL. Add `+ Required` suffix when any are present.

#### `_format_output()`

Required skills get `REQUIRED` or `INVOKE WHEN: <condition>` eval tags.

## 5. Registry Schema Changes

### Updated skill entries

**using-git-worktrees** (role change + triggers added):
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
  "description": "Use git worktrees for parallel branch work. Trigger-gated required: activates when parallel/isolation keywords match."
}
```

**agent-team-review** (role change + required_when added):
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
  "description": "Multi-perspective parallel code review with specialist reviewers. Trigger-gated + condition-gated required."
}
```

**security-scanner** — REMOVED from `skills[]` array, added as composition parallel (see Section 1).

### Updated chain links

**executing-plans**: `"precedes": ["requesting-code-review"]`
**requesting-code-review**: `"precedes": ["verification-before-completion"]`, `"requires": ["executing-plans"]`
**verification-before-completion**: `"requires": ["requesting-code-review"]`

New field: `required_when` (string, optional). Role value `"required"` now valid.

## 6. Files to Modify

| File | Change |
|------|--------|
| `config/default-triggers.json` | Remove `security-scanner` from `skills[]`; add security-scanner as parallel in `REVIEW` composition; reclassify `using-git-worktrees` (role→required, ADD triggers); reclassify `agent-team-review` (role→required, ADD required_when); add chain links to `executing-plans`, `requesting-code-review`, `verification-before-completion` |
| `config/fallback-registry.json` | Regenerate |
| `hooks/skill-activation-hook.sh` | Extend SKILL_DATA with `required_when` 9th field; add tentative phase + pass 0 to `_select_by_role_caps()`; add `_SL_REQUIRED` to `_build_skill_lines()`; update eval tags in `_format_output()`; update `_determine_label_phase()` for `+ Required` suffix |
| `tests/test-routing.sh` | Add 9 new tests (6 required role + 3 chain bridging) |
| `tests/test-context.sh` | Add 2 tests for security-scanner composition parallel |

## 7. Tests

### Security-scanner composition parallel (`tests/test-context.sh`)

1. **Security-scanner appears in REVIEW composition** — Assert REVIEW phase output contains `PARALLEL:.*security-scanner`.
2. **Security-scanner not scored as domain** — Assert `security-scanner` does NOT appear as `Domain:` in skill lines.

### Required role routing (`tests/test-routing.sh`)

3. **Required skill bypasses workflow cap** — Prompt triggers `using-git-worktrees` (required) and `agent-team-execution` (workflow). Assert both appear.
4. **Required skill bypasses total cap** — Prompt triggers 1 process + 2 domains + 1 workflow + 1 required. Assert total output is 5 skills.
5. **Conditional required shows INVOKE WHEN** — Prompt triggers `agent-team-review`. Assert eval line contains `INVOKE WHEN:` with the condition text.
6. **Required skill phase-gated to correct phase** — Prompt during DESIGN phase that matches worktree keywords. Assert `using-git-worktrees` does NOT appear (wrong phase).
7. **Required skills don't set PLABEL** — Minimal registry with only required skills. Assert PLABEL falls back to `(Claude: assess intent)`.
8. **REQUIRED eval tag present** — Prompt triggers `using-git-worktrees`. Assert eval line contains `using-git-worktrees REQUIRED`.

### Chain bridging (`tests/test-routing.sh`)

9. **End-to-end chain** — Chain walk from `brainstorming`. Assert 7 steps spanning DESIGN → PLAN → IMPLEMENT → REVIEW → SHIP.
10. **Mid-chain entry at REVIEW** — Trigger `requesting-code-review` with last-invoked `executing-plans`. Assert [DONE] for steps 1-3, [CURRENT] for step 4.
11. **Skipped-step markers** — Trigger `verification-before-completion` without prior review. Assert step 4 shows `[DONE?]`.

## Non-Goals

- Does NOT change superpowers skill content (SKILL.md files are immutable).
- Does NOT modify the composition chain mechanism — only extends `precedes`/`requires` links.
- Does NOT change `security-guidance` PreToolUse hook — that remains the always-on write-time guard.
- Does NOT re-implement TDD promotion — that is already done on `feat/tdd-parallel-promotion`.
