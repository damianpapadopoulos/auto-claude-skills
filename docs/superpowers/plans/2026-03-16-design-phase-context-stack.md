# Design Phase Context Stack Integration Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a unified-context-stack phase doc for DESIGN and narrow the activation hook's DESIGN-phase hint to Intent Truth + Historical Truth only.

**Architecture:** New `phases/design.md` mirrors the structure of existing phase docs (heading, intro line, Steps section with numbered subsections). The `default-triggers.json` and `fallback-registry.json` DESIGN composition entries get narrowed `use`/`purpose` fields. SKILL.md gets a new line in the Phase Documents list.

**Tech Stack:** Bash tests, JSON config, Markdown

**Spec:** `docs/superpowers/specs/2026-03-16-design-phase-context-stack-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `skills/unified-context-stack/phases/design.md` | Phase doc: Intent Truth + Historical Truth steps for DESIGN phase |
| Modify | `skills/unified-context-stack/SKILL.md:40` | Add design.md to Phase Documents list |
| Modify | `config/default-triggers.json:759-761` | Narrow DESIGN composition `use`/`purpose` |
| Modify | `config/fallback-registry.json:729-731` | Mirror the same narrowing |

---

## Chunk 1: Phase doc and SKILL.md

### Task 1: Create `phases/design.md`

**Files:**
- Create: `skills/unified-context-stack/phases/design.md`

- [ ] **Step 1: Write the test**

Add a test to `tests/test-context.sh` that verifies `design.md` exists and contains the expected tier headings.

```bash
# In test_phase_docs_exist (or new test function)
test_design_phase_doc() {
    setup_test_env
    local phase_doc="${PLUGIN_ROOT}/skills/unified-context-stack/phases/design.md"
    assert_file_exists "${phase_doc}"
    assert_contains "Intent Truth" "$(cat "${phase_doc}")" "design.md contains Intent Truth"
    assert_contains "Historical Truth" "$(cat "${phase_doc}")" "design.md contains Historical Truth"
    # External Truth and Internal Truth should NOT be steps — verify they're deferred
    if grep -q "^###.*External Truth" "${phase_doc}"; then
        fail "design.md should not have External Truth as a step heading"
    fi
    if grep -q "^###.*Internal Truth" "${phase_doc}"; then
        fail "design.md should not have Internal Truth as a step heading"
    fi
    pass "design.md defers External/Internal Truth"
    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh`
Expected: FAIL — `design.md` does not exist yet

- [ ] **Step 3: Create `phases/design.md`**

```markdown
# Phase 0: Design

Before proposing approaches, check what's already been decided.

## Steps

### 0. Intent Truth
IF the task involves a known feature or capability, check for existing specifications:
- **IF `openspec/changes/<feature>/` exists:** Read `proposal.md`, `design.md`, and `specs/` for active change context. These represent the most current intent — proposed approaches must account for them.
- **ELSE IF `openspec/specs/<capability>/spec.md` exists:** Read the canonical spec. Proposed approaches should satisfy existing requirements unless the user explicitly wants to change direction.
- **ELSE IF `docs/superpowers/specs/` has a matching design spec:** Read it for design intent, but note it may be stale.
- **IF no artifacts found:** Proceed without spec context.

### 1. Historical Truth
Query institutional memory for past decisions and constraints in this area:
- **forgetful_memory=true**: Query Forgetful for past architectural decisions, failed approaches, and known constraints
- **forgetful_memory=false**: Read CLAUDE.md, docs/architecture.md, and .cursorrules for project context

**Note:** External Truth (API docs) and Internal Truth (blast-radius mapping) are deferred to the Plan phase — you don't know which libraries or files will be involved until an approach is chosen.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-context.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add skills/unified-context-stack/phases/design.md tests/test-context.sh
git commit -m "feat: add design phase doc for unified-context-stack"
```

---

### Task 2: Update SKILL.md phase documents list

**Files:**
- Modify: `skills/unified-context-stack/SKILL.md:40`

- [ ] **Step 1: Write the test**

Add assertion to `tests/test-context.sh` that SKILL.md references `design.md`:

```bash
test_skill_md_references_design() {
    setup_test_env
    local skill_md="${PLUGIN_ROOT}/skills/unified-context-stack/SKILL.md"
    assert_contains "phases/design.md" "$(cat "${skill_md}")" "SKILL.md references design.md"
    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh`
Expected: FAIL — SKILL.md doesn't reference design.md yet

- [ ] **Step 3: Add design.md to SKILL.md**

In `skills/unified-context-stack/SKILL.md`, line 40, insert before the Triage & Plan line:

```markdown
- [Design](phases/design.md) — Intent and historical context before proposing approaches
```

The Phase Documents section should read:
```markdown
## Phase Documents

- [Design](phases/design.md) — Intent and historical context before proposing approaches
- [Triage & Plan](phases/triage-and-plan.md) — Context gathering before writing plans
- [Implementation](phases/implementation.md) — Mid-flight lookups during execution
- [Testing & Debug](phases/testing-and-debug.md) — Error resolution and live issue discovery
- [Code Review](phases/code-review.md) — Claim verification and dependency checks
- [Ship & Learn](phases/ship-and-learn.md) — Memory consolidation before session close
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-context.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add skills/unified-context-stack/SKILL.md tests/test-context.sh
git commit -m "feat: add design phase to SKILL.md phase documents list"
```

---

## Chunk 2: Config narrowing

### Task 3: Narrow DESIGN composition in `default-triggers.json`

**Files:**
- Modify: `config/default-triggers.json:758-761`

- [ ] **Step 1: Write the test**

Add assertion to `tests/test-context.sh` or `tests/test-registry.sh` that the DESIGN phase composition uses the narrowed text:

```bash
test_design_composition_narrowed() {
    setup_test_env
    local triggers="${PLUGIN_ROOT}/config/default-triggers.json"
    local use_field
    use_field="$(jq -r '.phase_compositions.DESIGN.parallel[] | select(.plugin == "unified-context-stack") | .use' "${triggers}")"
    assert_equals "DESIGN use field narrowed" "tiered context retrieval (Intent Truth, Historical Truth)" "${use_field}"
    local purpose_field
    purpose_field="$(jq -r '.phase_compositions.DESIGN.parallel[] | select(.plugin == "unified-context-stack") | .purpose' "${triggers}")"
    assert_equals "DESIGN purpose field narrowed" "Check existing specs and past decisions before proposing approaches" "${purpose_field}"
    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh`
Expected: FAIL — current text is "tiered context retrieval (external docs, blast-radius, memory)"

- [ ] **Step 3: Update `default-triggers.json`**

In `config/default-triggers.json`, change lines 759-761:

From:
```json
          "use": "tiered context retrieval (external docs, blast-radius, memory)",
          "when": "installed AND any context_capability is true",
          "purpose": "Gather curated API docs, map dependencies, check institutional memory during design"
```

To:
```json
          "use": "tiered context retrieval (Intent Truth, Historical Truth)",
          "when": "installed AND any context_capability is true",
          "purpose": "Check existing specs and past decisions before proposing approaches"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-context.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add config/default-triggers.json tests/test-context.sh
git commit -m "feat: narrow DESIGN phase composition to Intent + Historical Truth"
```

---

### Task 4: Mirror narrowing in `fallback-registry.json`

**Files:**
- Modify: `config/fallback-registry.json:729-731`

- [ ] **Step 1: Write the test**

Add assertion that fallback registry matches default-triggers for DESIGN composition:

```bash
test_fallback_design_matches_default() {
    setup_test_env
    local fallback="${PLUGIN_ROOT}/config/fallback-registry.json"
    local use_field
    use_field="$(jq -r '.phase_compositions.DESIGN.parallel[] | select(.plugin == "unified-context-stack") | .use' "${fallback}")"
    assert_equals "fallback DESIGN use field" "tiered context retrieval (Intent Truth, Historical Truth)" "${use_field}"
    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh`
Expected: FAIL — fallback still has old text

- [ ] **Step 3: Update `fallback-registry.json`**

In `config/fallback-registry.json`, change lines 729-731:

From:
```json
          "use": "tiered context retrieval (external docs, blast-radius, memory)",
          "when": "installed AND any context_capability is true",
          "purpose": "Gather curated API docs, map dependencies, check institutional memory during design"
```

To:
```json
          "use": "tiered context retrieval (Intent Truth, Historical Truth)",
          "when": "installed AND any context_capability is true",
          "purpose": "Check existing specs and past decisions before proposing approaches"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-context.sh`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (routing, registry, context)

- [ ] **Step 6: Commit**

```bash
git add config/fallback-registry.json tests/test-context.sh
git commit -m "feat: mirror DESIGN composition narrowing in fallback registry"
```
