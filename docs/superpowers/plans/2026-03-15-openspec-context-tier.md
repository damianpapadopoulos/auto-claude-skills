# OpenSpec Context Tier Integration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-03-15-openspec-context-tier-design.md`

**Goal:** Add Intent Truth as a fourth context tier to the unified-context-stack with conditional gates in phase documents.

**Architecture:** Documentation-only changes — 1 new markdown file (tier doc), 3 phase doc edits, 1 SKILL.md update, and lightweight content assertion tests. No bash code, no hooks, no registry changes.

**Tech Stack:** Markdown, Bash (tests only)

---

## File Structure

| File | Responsibility |
|------|---------------|
| `skills/unified-context-stack/tiers/intent-truth.md` | New: Intent Truth tier document (source priority, fallback chain) |
| `skills/unified-context-stack/SKILL.md` | Updated: frontmatter description, capability flag row, tier doc link, artifact note |
| `skills/unified-context-stack/phases/triage-and-plan.md` | Updated: add Step 0 Intent Truth gate |
| `skills/unified-context-stack/phases/implementation.md` | Updated: add Step 3 Intent Truth on-demand gate |
| `skills/unified-context-stack/phases/code-review.md` | Updated: add Step 0 Intent Truth gate |
| `tests/test-context.sh` | Updated: 4 content assertion tests |

---

## Chunk 1: Tier Document and SKILL.md

### Task 1: Create tiers/intent-truth.md

**Files:**
- Create: `skills/unified-context-stack/tiers/intent-truth.md`

- [ ] **Step 1: Write the tier document**

Create `skills/unified-context-stack/tiers/intent-truth.md` with the exact content from the spec (Section 1, "Content" block). The file should contain:

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

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/tiers/intent-truth.md
git commit -m "feat: add Intent Truth tier document for OpenSpec context integration"
```

### Task 2: Update SKILL.md

**Files:**
- Modify: `skills/unified-context-stack/SKILL.md`

- [ ] **Step 1: Update frontmatter description (line 3)**

Change:
```yaml
description: Tiered context retrieval across External Truth (docs), Internal Truth (dependencies), and Historical Truth (memory) with graceful degradation based on installed tools.
```
To:
```yaml
description: Tiered context retrieval across External Truth (docs), Internal Truth (dependencies), Historical Truth (memory), and Intent Truth (feature specs) with graceful degradation based on installed tools.
```

- [ ] **Step 2: Add capability flag row to the table (after the `forgetful_memory` row, around line 26)**

Add this row:
```markdown
| `openspec` | OpenSpec CLI | Whether the `openspec` binary is available. See the separate `OpenSpec:` capability line for detailed surface/command info. Intent Truth retrieval does NOT require this flag — it checks artifact presence directly. |
```

- [ ] **Step 3: Add Intent Truth to the tier documents list (after line 32)**

Add:
```markdown
- [Intent Truth](tiers/intent-truth.md) — Feature specification and design rationale retrieval
```

- [ ] **Step 4: Add artifact note after the tier documents list**

Add after the new Intent Truth link:
```markdown

**Note:** Intent Truth checks for artifact presence in the workspace (`openspec/specs/`, `openspec/changes/`, `docs/superpowers/specs/`). The `OpenSpec:` capability line from session-start indicates CLI availability for write operations (used by `openspec-ship`), but Intent Truth retrieval works regardless of CLI installation — it reads local files.
```

- [ ] **Step 5: Update the intro line (line 3 of content, after frontmatter)**

Change the line "Before completing the session..." — actually, the intro line is:
```
Before completing the session, consolidate what was learned.
```
Wait, that's ship-and-learn. The SKILL.md intro is line 8:
```
An infrastructure-level skill that provides tiered context retrieval for every SDLC phase.
```
No change needed to this line — the frontmatter description update (Step 1) is sufficient.

- [ ] **Step 6: Commit**

```bash
git add skills/unified-context-stack/SKILL.md
git commit -m "feat: add Intent Truth to unified-context-stack capability flags and tier list"
```

## Chunk 2: Phase Document Gates

### Task 3: Add Intent Truth gate to triage-and-plan.md

**Files:**
- Modify: `skills/unified-context-stack/phases/triage-and-plan.md`

- [ ] **Step 1: Update the intro line (line 3)**

Change:
```markdown
Before writing the implementation plan, gather context across all three dimensions.
```
To:
```markdown
Before writing the implementation plan, gather context across all four dimensions.
```

- [ ] **Step 2: Insert Step 0 before existing Step 1 (before line 7)**

Insert between `## Steps` (line 5) and `### 1. Historical Truth` (line 7):

```markdown

### 0. Intent Truth
IF the task references a known feature or capability, check for specification context before planning:
- **IF `openspec/changes/<feature>/` exists:** Read `proposal.md`, `design.md`, and `specs/` for active change context. These represent the most current intent for this feature. Carry forward existing requirements and acceptance scenarios into the plan.
- **ELSE IF `openspec/specs/<capability>/spec.md` exists:** Read the canonical spec for authoritative requirements. The plan must satisfy all specified scenarios unless the user explicitly says otherwise.
- **ELSE IF `docs/superpowers/specs/` has a matching design spec:** Read it for design intent, but cross-reference with the current codebase — SP specs may be stale.
- **IF no artifacts found:** Proceed without spec context. If the task scope is ambiguous, ask the user to clarify requirements.

```

- [ ] **Step 3: Commit**

```bash
git add skills/unified-context-stack/phases/triage-and-plan.md
git commit -m "feat: add Intent Truth gate to triage-and-plan phase document"
```

### Task 4: Add Intent Truth gate to implementation.md

**Files:**
- Modify: `skills/unified-context-stack/phases/implementation.md`

- [ ] **Step 1: Add Step 3 after the existing Step 2 (after line 17)**

Append after the `### 2. External Truth (On-Demand)` section:

```markdown

### 3. Intent Truth (On-Demand)
IF you encounter a design ambiguity not covered in the plan:
- **IF `openspec/specs/<capability>/spec.md` or `openspec/changes/<feature>/` exists:** Check for the specific edge case or requirement. Do NOT re-read the full spec — query only for the specific ambiguity.
- **IF no artifacts found:** Rely on the plan from Phase 1, or ask the user.
```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/phases/implementation.md
git commit -m "feat: add Intent Truth on-demand gate to implementation phase document"
```

### Task 5: Add Intent Truth gate to code-review.md

**Files:**
- Modify: `skills/unified-context-stack/phases/code-review.md`

- [ ] **Step 1: Insert Step 0 before existing Step 1 (before line 7)**

Insert between `## Steps` (line 5) and `### 1. External Truth` (line 7):

```markdown

### 0. Intent Truth (Requirement Verification)
IF reviewing changes to a specified capability:
- **IF `openspec/changes/<feature>/specs/` exists:** Read delta specs for the active change. These are the most current intent during development. Verify the implementation matches the specified scenarios.
- **ELSE IF `openspec/specs/<capability>/spec.md` exists:** Read the canonical spec. Verify the implementation satisfies all acceptance scenarios. Flag any specified requirement that is missing from the implementation or tests.
- **ELSE IF `docs/superpowers/specs/` has a matching design spec:** Reference it for design intent verification, but note that SP specs may have diverged from implementation.
- **IF no artifacts found:** Review based on code quality and internal consistency only.
- **IF the PR intentionally diverges from spec:** Note this as a spec update candidate — the spec should be revised to match the new intent after shipping.

```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/phases/code-review.md
git commit -m "feat: add Intent Truth gate to code-review phase document"
```

## Chunk 3: Tests and Verification

### Task 6: Add content assertion tests to test-context.sh

**Files:**
- Modify: `tests/test-context.sh`

- [ ] **Step 1: Add Intent Truth content assertion test**

Insert a new test function before the summary section (before `print_summary` at line 696). Add both the function definition and its invocation:

```bash
# ---------------------------------------------------------------------------
# Intent Truth tier integration tests
# ---------------------------------------------------------------------------
test_intent_truth_tier_exists() {
    echo "-- test: Intent Truth tier document and phase gates --"

    local tier_doc="${PROJECT_ROOT}/skills/unified-context-stack/tiers/intent-truth.md"
    assert_equals "intent-truth.md exists" "true" "$([ -f "$tier_doc" ] && echo true || echo false)"

    local skill_md
    skill_md="$(cat "${PROJECT_ROOT}/skills/unified-context-stack/SKILL.md")"
    assert_contains "SKILL.md references intent-truth" "intent-truth.md" "$skill_md"

    local triage
    triage="$(cat "${PROJECT_ROOT}/skills/unified-context-stack/phases/triage-and-plan.md")"
    assert_contains "triage-and-plan has openspec gate" "openspec" "$triage"

    local review
    review="$(cat "${PROJECT_ROOT}/skills/unified-context-stack/phases/code-review.md")"
    assert_contains "code-review has openspec gate" "openspec" "$review"

    local impl
    impl="$(cat "${PROJECT_ROOT}/skills/unified-context-stack/phases/implementation.md")"
    assert_contains "implementation has openspec gate" "openspec" "$impl"
}
test_intent_truth_tier_exists
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-context.sh 2>&1 | grep -E "(PASS|FAIL).*(intent|openspec)"`
Expected: All 5 new assertions pass.

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -15`
Expected: All existing tests still pass. No regressions.

- [ ] **Step 4: Commit**

```bash
git add tests/test-context.sh
git commit -m "test: add Intent Truth content assertion tests"
```

### Task 7: Final verification

**Files:** (verification only, no changes)

- [ ] **Step 1: Verify all 4 tier docs exist**

Run: `ls skills/unified-context-stack/tiers/`
Expected: `external-truth.md  historical-truth.md  intent-truth.md  internal-truth.md`

- [ ] **Step 2: Verify SKILL.md references all 4 tiers**

Run: `grep "truth.md" skills/unified-context-stack/SKILL.md`
Expected: 4 lines, one for each tier doc.

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All suites pass (pre-existing registry failures unchanged).
