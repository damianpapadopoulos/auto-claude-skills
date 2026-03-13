# Context Stack Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the unified-context-stack by fixing honest capability signaling, linking phase docs, adding conditional fallbacks, enforcing memory consolidation, and strengthening hints.

**Architecture:** Five targeted changes to existing files. No new hooks, no activation hook changes. Session-start gets richer output, phase docs get conditional guidance, memory consolidation gets a two-layer advisory system.

**Tech Stack:** Bash 3.2, jq, Markdown

**Spec:** `docs/superpowers/specs/2026-03-13-context-stack-improvements-design.md`

---

## Chunk 1: Honest Capability Signaling (Change 1)

Rename `context_hub_indexed` → `context_hub_available` across all source files.

### Task 1: Rename flag in session-start hook

**Files:**
- Modify: `hooks/session-start-hook.sh:481` (jq output field name)

- [ ] **Step 1: Update the jq field name**

Change line 481 from:
```
    {context7:$c7, context_hub_cli:$chub, context_hub_indexed:$c7, serena:$ser, forgetful_memory:$fm}'
```
to:
```
    {context7:$c7, context_hub_cli:$chub, context_hub_available:$c7, serena:$ser, forgetful_memory:$fm}'
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n hooks/session-start-hook.sh`
Expected: No output (valid).

- [ ] **Step 3: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "refactor: rename context_hub_indexed to context_hub_available in session-start"
```

### Task 2: Update SKILL.md capability table

**Files:**
- Modify: `skills/unified-context-stack/SKILL.md:23`

- [ ] **Step 1: Update the flag name and description**

Change line 23 from:
```
| `context_hub_indexed` | Context Hub via Context7 | High-trust curated docs (query `/andrewyng/context-hub`) |
```
to:
```
| `context_hub_available` | Context Hub via Context7 | High-trust curated docs — flag means Hub is *reachable*, not that it has docs for your library (query `/andrewyng/context-hub`) |
```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/SKILL.md
git commit -m "refactor: rename context_hub_indexed to context_hub_available in SKILL.md"
```

### Task 3: Update external-truth.md tier condition and add fallthrough note

**Files:**
- Modify: `skills/unified-context-stack/tiers/external-truth.md:7`

- [ ] **Step 1: Update the condition and add note**

Change line 7 from:
```
**Condition:** `context_hub_indexed = true`
```
to:
```
**Condition:** `context_hub_available = true`

**Note:** This flag indicates Context Hub is reachable via Context7, not that it has docs for your specific library. If `resolve-library-id` returns no match, fall through to Tier 2 immediately.
```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/tiers/external-truth.md
git commit -m "refactor: rename context_hub_indexed to context_hub_available in external-truth"
```

### Task 4: Update test files

**Files:**
- Modify: `tests/test-context.sh:530`
- Modify: `tests/test-registry.sh:515-518`

- [ ] **Step 1: Update test-context.sh**

Change line 530 from:
```
        .context_capabilities = {context7:true,context_hub_cli:false,context_hub_indexed:true,serena:false,forgetful_memory:false} |
```
to:
```
        .context_capabilities = {context7:true,context_hub_cli:false,context_hub_available:true,serena:false,forgetful_memory:false} |
```

- [ ] **Step 2: Update test-registry.sh**

Change lines 515-518 from:
```bash
    # context_hub_indexed should derive from context7
    local hub_idx
    hub_idx="$(jq -r '.context_capabilities.context_hub_indexed' "${cache_file}" 2>/dev/null)"
    assert_equals "context_hub_indexed derived from context7" "true" "${hub_idx}"
```
to:
```bash
    # context_hub_available should derive from context7
    local hub_avail
    hub_avail="$(jq -r '.context_capabilities.context_hub_available' "${cache_file}" 2>/dev/null)"
    assert_equals "context_hub_available derived from context7" "true" "${hub_avail}"
```

- [ ] **Step 3: Run tests**

Run: `bash tests/test-registry.sh && bash tests/test-context.sh`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/test-context.sh tests/test-registry.sh
git commit -m "test: update assertions for context_hub_available rename"
```

### Task 5: (Deferred — fallback registry regenerated once in Task 14 after all changes)

No action. Regenerating here would be wasted work since Chunks 2-4 make further changes to session-start-hook.sh.

---

## Chunk 2: Phase Document Linking (Change 2)

Add a phase guidance line to session-start output.

### Task 6: Add phase guidance line to session-start hook

**Files:**
- Modify: `hooks/session-start-hook.sh:621-624` (after the Context Stack line)

- [ ] **Step 1: Write the test first**

Add to `tests/test-context.sh` before the `# Run all tests` section (before line 576):

```bash
# ---------------------------------------------------------------------------
# 13. Phase document path emission
# ---------------------------------------------------------------------------
test_phase_doc_path_emission() {
    echo "-- test: session-start emits phase document paths --"
    setup_test_env
    install_registry_with_context_stack

    # Run session-start hook to get the output with phase paths
    local output
    output="$(CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null)"
    local ctx
    ctx="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

    assert_contains "phase guidance line present" "Context guidance per phase:" "${ctx}"
    assert_contains "implementation.md referenced" "implementation.md" "${ctx}"
    assert_contains "ship-and-learn.md referenced" "ship-and-learn.md" "${ctx}"

    teardown_test_env
}
```

Also add `test_phase_doc_path_emission` to the test runner list at the end of the file.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh 2>&1 | tail -5`
Expected: FAIL — no "Context guidance per phase:" line yet.

- [ ] **Step 3: Add phase guidance line to session-start output**

In `hooks/session-start-hook.sh`, after line 624 (`fi` closing the `_CAP_LINE` block), insert:

```bash
# Append phase document pointers for model navigation
CONTEXT="${CONTEXT}
Context guidance per phase: triage-and-plan.md | implementation.md | testing-and-debug.md | code-review.md | ship-and-learn.md (in skills/unified-context-stack/phases/)"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-context.sh 2>&1 | grep -A2 "phase_doc_path"`
Expected: PASS.

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-context.sh
git commit -m "feat: emit phase document paths in session-start output"
```

---

## Chunk 3: Conditional Fallbacks in Phase Documents (Change 3)

Add inline capability-aware instructions to each phase document.

### Task 7: Update triage-and-plan.md

**Files:**
- Modify: `skills/unified-context-stack/phases/triage-and-plan.md`

- [ ] **Step 1: Add conditional instructions**

Replace the entire content with:

```markdown
# Phase 1: Triage & Plan

Before writing the implementation plan, gather context across all three dimensions.

## Steps

### 1. Historical Truth
Query institutional memory for past constraints in this area:
- **forgetful_memory=true**: Use `memory-search` to query past architectural decisions and known constraints
- **forgetful_memory=false**: Read CLAUDE.md, docs/architecture.md, and .cursorrules for project context

### 2. External Truth
If the task involves third-party services or libraries:
- **context_hub_available=true**: Query Context Hub via Context7 for curated API docs for the specific version
- **context7=true** (no Hub match): Use broad Context7 query, verify signatures before including in plan
- **neither available**: Use WebSearch for official docs, cross-reference multiple sources
- Include relevant API signatures and usage examples in the written plan

### 3. Internal Truth
Map the blast radius before committing to a plan:
- **serena=true**: Use `find_symbol` / `cross_reference` to map all dependent files
- **serena=false**: Use Grep to find references across the codebase, Read to verify context
- List these files in the plan so the implementer knows the full scope
```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/phases/triage-and-plan.md
git commit -m "feat: add conditional fallbacks to triage-and-plan phase doc"
```

### Task 8: Update implementation.md

**Files:**
- Modify: `skills/unified-context-stack/phases/implementation.md`

- [ ] **Step 1: Add conditional instructions**

Replace the entire content with:

```markdown
# Phase 2: Implementation

During file-by-file plan execution, use context as needed.

## Steps

### 1. Internal Truth (Primary)
For each file modification, verify current symbol locations:
- **serena=true**: Use `find_symbol` / `cross_reference` for dependency mapping, `insert_after_symbol` for safe AST edits
- **serena=false**: Use Grep to find references, Read to verify context. Extra caution on large files (>500 lines) and symbol renames — grep may miss dynamic references. Always verify changes compile after editing.

### 2. External Truth (On-Demand)
If you encounter a library or API not covered in the original plan:
- **context_hub_available=true**: Query Context Hub via Context7 first for curated docs
- **context7=true** (no Hub match): Use broad Context7, verify method signatures before implementing
- **neither available**: Use WebSearch, treat with high skepticism
- Do not guess API signatures — look them up
```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/phases/implementation.md
git commit -m "feat: add conditional fallbacks to implementation phase doc"
```

### Task 9: Update testing-and-debug.md

**Files:**
- Modify: `skills/unified-context-stack/phases/testing-and-debug.md`

- [ ] **Step 1: Add conditional instructions**

Replace the entire content with:

```markdown
# Phase 3: Testing & Debug

When tests fail or errors occur, use context to resolve efficiently.

## Steps

### 1. Historical Truth (First Check)
Before investigating from scratch:
- **forgetful_memory=true**: Use `memory-search` for this exact error message or pattern
- **forgetful_memory=false**: Check CLAUDE.md and docs/learnings.md for known environmental quirks
- Check if this is a known workaround with a documented fix

### 2. External Truth (Library Issues)
If the error involves a third-party library:
- **context_hub_available=true**: Check Context Hub via Context7 for known issues or breaking changes
- **context7=true** (no Hub match): Use broad Context7 for library-specific error documentation
- **neither available**: Use WebSearch for the specific error message in the library's docs
- For API errors (4xx/5xx), check for known outages or recently discovered bugs
```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/phases/testing-and-debug.md
git commit -m "feat: add conditional fallbacks to testing-and-debug phase doc"
```

### Task 10: Update code-review.md

**Files:**
- Modify: `skills/unified-context-stack/phases/code-review.md`

- [ ] **Step 1: Add conditional instructions**

Replace the entire content with:

```markdown
# Phase 4: Code Review

When processing reviewer feedback, verify claims before accepting changes.

## Steps

### 1. External Truth (Claim Verification)
If a reviewer claims incorrect API usage:
- **context_hub_available=true**: Look up the specific parameter/method in Context Hub curated docs
- **context7=true** (no Hub match): Use broad Context7, verify against web-scraped docs
- **neither available**: Use WebSearch for official API reference
- If the reviewer is wrong, cite the documentation source in your response

### 2. Internal Truth (Dependency Safety)
If a reviewer suggests an architectural change:
- **serena=true**: Use `cross_reference` to map all downstream dependencies before implementing
- **serena=false**: Use Grep to find all references, Read to verify each usage. Extra caution on complex hierarchies.
- Flag any files that would break silently from the proposed change
```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/phases/code-review.md
git commit -m "feat: add conditional fallbacks to code-review phase doc"
```

### Task 11: Update ship-and-learn.md with consolidation gate

**Files:**
- Modify: `skills/unified-context-stack/phases/ship-and-learn.md`

- [ ] **Step 1: Add consolidation requirement and marker instruction**

Replace the entire content with:

```markdown
# Phase 5: Ship & Learn

Before completing the session, consolidate what was learned.

**REQUIRED before completing session:** If you discovered any architectural rules, API quirks, or project conventions during this session, you MUST consolidate them using the highest available tier below before claiming the work is done. After consolidation, write the marker:

```bash
touch ~/.claude/.context-stack-consolidated-$(printf '%s' "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" | shasum | cut -d' ' -f1)
```

## Memory Consolidation

Evaluate your available tools and execute the highest available tier:

### IF forgetful_memory = true
Execute `memory-save` to permanently store:
- New architectural rules or conventions discovered
- Project-specific quirks that would be useful in future sessions
- Decisions made and their rationale

### IF context_hub_cli = true
Execute `chub annotate <library-id> "<note>"` to record:
- API workarounds or undocumented behaviors discovered
- Version-specific gotchas (e.g., "React Router v7 requires X wrapper in our setup")

### IF NEITHER are available
Append findings to `docs/learnings.md` using standard file editing:

```
## YYYY-MM-DD: [Brief Title]

**Context:** [What task was being performed]
**Learning:** [The specific insight or workaround]
**Applies to:** [Which part of the codebase]
```
```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/phases/ship-and-learn.md
git commit -m "feat: add consolidation gate and conditional fallbacks to ship-and-learn"
```

### Task 11b: Verify phase docs have conditional fallbacks

**Files:**
- Test: `tests/test-context.sh`

- [ ] **Step 1: Add content verification test**

Add to `tests/test-context.sh` before the `# Run all tests` section:

```bash
# ---------------------------------------------------------------------------
# 13b. Phase document conditional fallback content
# ---------------------------------------------------------------------------
test_phase_docs_have_conditional_fallbacks() {
    echo "-- test: phase docs contain capability-conditional instructions --"
    local phase_dir="${PROJECT_ROOT}/skills/unified-context-stack/phases"
    local fail_count=0

    for doc in triage-and-plan implementation testing-and-debug code-review; do
        local content
        content="$(cat "${phase_dir}/${doc}.md")"
        if ! printf '%s' "${content}" | grep -q '=true\*\*:'; then
            echo "  FAIL: ${doc}.md missing conditional fallback format"
            fail_count=$((fail_count + 1))
        fi
    done

    # ship-and-learn uses IF format instead of inline
    local ship_content
    ship_content="$(cat "${phase_dir}/ship-and-learn.md")"
    if ! printf '%s' "${ship_content}" | grep -q 'REQUIRED before completing session'; then
        echo "  FAIL: ship-and-learn.md missing consolidation gate"
        fail_count=$((fail_count + 1))
    fi

    if [ "${fail_count}" -eq 0 ]; then
        echo "  PASS: all phase docs have conditional fallbacks"
    else
        echo "  FAIL: ${fail_count} phase docs missing conditionals"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}
```

Also add `test_phase_docs_have_conditional_fallbacks` to the test runner list.

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/test-context.sh 2>&1 | grep -A2 "phase_docs"`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/test-context.sh
git commit -m "test: verify phase docs have conditional fallback format"
```

---

## Chunk 4: Memory Consolidation Check + Hint Strengthening (Changes 4 & 5)

### Task 12: Add pull-based consolidation check to session-start

**Files:**
- Modify: `hooks/session-start-hook.sh:621-624` (after Context Stack line, before phase guidance line)

- [ ] **Step 1: Write the test**

Add to `tests/test-context.sh` before the `# Run all tests` section:

```bash
# ---------------------------------------------------------------------------
# 14. Memory consolidation marker check
# ---------------------------------------------------------------------------
test_consolidation_marker_stale() {
    echo "-- test: session-start warns when consolidation marker is stale --"
    setup_test_env
    install_registry_with_context_stack

    # Initialize a git repo with 2+ commits so consolidation check fires
    (cd "${HOME}" && git init -q && git commit --allow-empty -m "init" -q && git commit --allow-empty -m "second" -q)

    # No marker file exists — should warn
    local output ctx
    output="$(cd "${HOME}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null)"
    ctx="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

    assert_contains "stale marker warning" "unconsolidated learnings" "${ctx}"

    teardown_test_env
}

test_consolidation_marker_fresh() {
    echo "-- test: session-start no warning when marker is fresh --"
    setup_test_env
    install_registry_with_context_stack

    # Initialize git repo with 2+ commits
    (cd "${HOME}" && git init -q && git commit --allow-empty -m "init" -q && git commit --allow-empty -m "second" -q)

    # Create a fresh marker (newer than last commit)
    local proj_hash
    proj_hash="$(printf '%s' "${HOME}" | shasum | cut -d' ' -f1)"
    touch "${HOME}/.claude/.context-stack-consolidated-${proj_hash}"

    local output ctx
    output="$(cd "${HOME}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null)"
    ctx="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

    assert_not_contains "no stale warning with fresh marker" "unconsolidated learnings" "${ctx}"

    teardown_test_env
}
```

Also add `test_consolidation_marker_stale` and `test_consolidation_marker_fresh` to the test runner list.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-context.sh 2>&1 | grep -A2 "consolidation"`
Expected: FAIL — no consolidation check yet.

- [ ] **Step 3: Add consolidation marker check to session-start**

In `hooks/session-start-hook.sh`, insert immediately BEFORE the line `# Append phase document pointers for model navigation` (added in Task 6). This places it after the `_CAP_LINE` block but before the phase guidance line:

```bash
# Check for stale/missing memory consolidation marker
_PROJ_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_PROJ_HASH="$(printf '%s' "${_PROJ_ROOT}" | shasum | cut -d' ' -f1)"
_CONSOL_MARKER="${HOME}/.claude/.context-stack-consolidated-${_PROJ_HASH}"
if [ -f "${_CONSOL_MARKER}" ]; then
    # Compare marker mtime with last git commit time
    _MARKER_TIME="$(stat -f %m "${_CONSOL_MARKER}" 2>/dev/null || stat -c %Y "${_CONSOL_MARKER}" 2>/dev/null || echo 0)"
    _LAST_COMMIT="$(git -C "${_PROJ_ROOT}" log -1 --format=%ct 2>/dev/null || echo 0)"
    if [ "${_MARKER_TIME}" -lt "${_LAST_COMMIT}" ]; then
        CONTEXT="${CONTEXT}
Context Stack: Previous session may have unconsolidated learnings. Consider reviewing recent changes."
    fi
else
    # No marker at all — only warn if there are git commits (not a brand-new repo)
    _COMMIT_COUNT="$(git -C "${_PROJ_ROOT}" rev-list --count HEAD 2>/dev/null || echo 0)"
    if [ "${_COMMIT_COUNT}" -gt 1 ]; then
        CONTEXT="${CONTEXT}
Context Stack: Previous session may have unconsolidated learnings. Consider reviewing recent changes."
    fi
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-context.sh 2>&1 | grep -A2 "consolidation"`
Expected: PASS for both stale and fresh marker tests.

- [ ] **Step 5: Syntax-check**

Run: `bash -n hooks/session-start-hook.sh`
Expected: No output (valid).

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-context.sh
git commit -m "feat: add pull-based memory consolidation check to session-start"
```

### Task 13: Strengthen methodology hint text

**Files:**
- Modify: `config/default-triggers.json:378`

- [ ] **Step 1: Update hint text**

Change line 378 from:
```json
      "hint": "CONTEXT STACK: Use the unified-context-stack for tiered documentation retrieval. Query Context Hub via Context7 (libraryId=/andrewyng/context-hub) first for curated docs, then fall back to broad Context7, then chub CLI, then web search.",
```
to:
```json
      "hint": "CONTEXT STACK: Use the unified-context-stack for tiered documentation retrieval. Query Context Hub via Context7 (libraryId=/andrewyng/context-hub) first for curated docs, then fall back to broad Context7, then chub CLI, then web search. Read the phase document for your current SDLC phase from the unified-context-stack skill (paths listed in the Context Stack session-start output).",
```

- [ ] **Step 2: Validate JSON**

Run: `jq empty config/default-triggers.json`
Expected: No output (valid JSON).

- [ ] **Step 3: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: strengthen unified-context-stack methodology hint with phase doc pointer"
```

### Task 14: Regenerate fallback registry and run full suite

**Files:**
- Modify: `config/fallback-registry.json`

- [ ] **Step 1: Regenerate fallback registry**

```bash
HOME_BAK="$HOME"
export HOME="$(mktemp -d)"
mkdir -p "$HOME/.claude"
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh >/dev/null 2>&1
cp "$HOME/.claude/.skill-registry-cache.json" config/fallback-registry.json
export HOME="$HOME_BAK"
```

- [ ] **Step 2: Verify**

Run: `jq '.context_capabilities' config/fallback-registry.json`
Expected: Shows `context_hub_available` (not `context_hub_indexed`), all values `false`.

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass across all test files.

- [ ] **Step 4: Manual smoke test**

Run: `SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh <<< '{"prompt":"build a stripe payment integration"}'`
Expected: Shows `unified-context-stack` in PARALLEL composition line.

- [ ] **Step 5: Commit**

```bash
git add config/fallback-registry.json
git commit -m "chore: regenerate fallback registry with all context stack improvements"
```
