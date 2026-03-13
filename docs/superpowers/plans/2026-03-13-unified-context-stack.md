# Unified Context Stack Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate a tiered context retrieval system (Context Hub, Context7, Serena, Forgetful Memory) into all Superpowers SDLC phases as infrastructure that composes alongside skills without consuming role-cap slots.

**Architecture:** Three components — (1) capability detection in session-start hook writes `context_capabilities` to registry and injects flags into model context, (2) orchestrator skill documents with tiered decision trees, (3) phase composition entries in `default-triggers.json` that route to the stack per SDLC phase. Registered as a plugin (not a scored skill) to avoid role-cap competition.

**Tech Stack:** Bash 3.2, jq, Markdown skill files

**Spec:** `docs/superpowers/specs/2026-03-13-unified-context-stack-design.md`

---

## Chunk 1: Registry Data Changes

### Task 1: Add unified-context-stack plugin entry to default-triggers.json

**Files:**
- Modify: `config/default-triggers.json:509-675` (plugins array)

- [ ] **Step 1: Add the plugin entry**

Add to the `plugins` array after the `atlassian` entry:

```json
{
  "name": "unified-context-stack",
  "source": "auto-claude-skills",
  "provides": {
    "commands": [],
    "skills": [],
    "agents": [],
    "hooks": [],
    "mcp_tools": []
  },
  "phase_fit": ["DESIGN", "PLAN", "IMPLEMENT", "DEBUG", "REVIEW", "SHIP"],
  "description": "Tiered context retrieval — curated docs (Context Hub via Context7), blast-radius mapping (Serena), institutional memory (Forgetful) with graceful degradation."
}
```

- [ ] **Step 2: Validate JSON syntax**

Run: `jq empty config/default-triggers.json`
Expected: no output (valid JSON)

- [ ] **Step 3: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: add unified-context-stack plugin entry to registry"
```

### Task 2: Replace Context7 composition entries with unified-context-stack entries

**Files:**
- Modify: `config/default-triggers.json:677-804` (phase_compositions)

- [ ] **Step 1: Replace DESIGN phase Context7 parallel entry**

In `phase_compositions.DESIGN.parallel`, replace the Context7 entry:
```json
{
  "plugin": "context7",
  "use": "mcp:resolve-library-id + get-library-docs",
  "when": "installed AND prompt mentions libraries/frameworks",
  "purpose": "Fetch current library docs during design to inform technology choices"
}
```
with:
```json
{
  "plugin": "unified-context-stack",
  "use": "tiered context retrieval (external docs, blast-radius, memory)",
  "when": "installed AND any context_capability is true",
  "purpose": "Gather curated API docs, map dependencies, check institutional memory during design"
}
```

- [ ] **Step 2: Replace IMPLEMENT phase Context7 parallel entry**

In `phase_compositions.IMPLEMENT.parallel`, replace the Context7 entry with:
```json
{
  "plugin": "unified-context-stack",
  "use": "tiered context retrieval (mid-flight library lookups)",
  "when": "installed AND any context_capability is true",
  "purpose": "Look up current API signatures and usage patterns during implementation"
}
```

- [ ] **Step 3: Add PLAN phase unified-context-stack parallel entry**

In `phase_compositions.PLAN.parallel` (currently empty `[]`), add:
```json
{
  "plugin": "unified-context-stack",
  "use": "tiered context retrieval (external docs, blast-radius, memory)",
  "when": "installed AND any context_capability is true",
  "purpose": "Gather curated API docs, map dependencies, check institutional memory before planning"
}
```

- [ ] **Step 4: Replace DEBUG phase Context7 parallel entry**

In `phase_compositions.DEBUG.parallel`, replace the Context7 entry with:
```json
{
  "plugin": "unified-context-stack",
  "use": "tiered context retrieval (past solutions, live issue discovery)",
  "when": "installed AND any context_capability is true",
  "purpose": "Check past solutions via memory, and live library issues via curated docs"
}
```

- [ ] **Step 5: Add REVIEW phase unified-context-stack parallel entry**

In `phase_compositions.REVIEW.parallel`, add alongside existing entries:
```json
{
  "plugin": "unified-context-stack",
  "use": "tiered context retrieval (claim verification, dependency checks)",
  "when": "installed AND any context_capability is true",
  "purpose": "Verify reviewer claims against curated docs, check dependency impact"
}
```

- [ ] **Step 6: Add SHIP phase unified-context-stack sequence entry**

In `phase_compositions.SHIP.sequence`, add as the FIRST entry (before commit-commands):
```json
{
  "plugin": "unified-context-stack",
  "use": "memory consolidation (annotate + memory-save)",
  "when": "installed AND any context_capability is true",
  "purpose": "Consolidate learnings via chub annotate and/or memory-save before session close"
}
```

- [ ] **Step 7: Validate JSON syntax**

Run: `jq empty config/default-triggers.json`
Expected: no output (valid JSON)

- [ ] **Step 8: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: replace Context7 compositions with unified-context-stack entries"
```

### Task 3: Replace context7-docs methodology hint

**Files:**
- Modify: `config/default-triggers.json:354-380` (methodology_hints)

- [ ] **Step 1: Replace the context7-docs hint**

Replace:
```json
{
  "name": "context7-docs",
  "triggers": [
    "(library|package|module|sdk|api|docs|documentation|reference|version|latest|upgrade|deprecat|migrat)"
  ],
  "trigger_mode": "regex",
  "hint": "CONTEXT7: If Context7 MCP tools are available, fetch up-to-date library documentation instead of relying on training data.",
  "plugin": "context7"
}
```
with:
```json
{
  "name": "unified-context-stack-hint",
  "triggers": [
    "(library|package|module|sdk|api|docs|documentation|reference|version|latest|upgrade|deprecat|migrat)"
  ],
  "trigger_mode": "regex",
  "hint": "CONTEXT STACK: Use the unified-context-stack for tiered documentation retrieval. Query Context Hub via Context7 (libraryId=/andrewyng/context-hub) first for curated docs, then fall back to broad Context7, then chub CLI, then web search.",
  "plugin": "unified-context-stack"
}
```

- [ ] **Step 2: Validate JSON and run existing tests**

Run: `jq empty config/default-triggers.json && bash tests/run-tests.sh`
Expected: JSON valid. Some tests may need count updates (plugin count changes from 8 to 9).

- [ ] **Step 3: Update all test assertions for new counts**

In `tests/test-registry.sh`, update these assertions to reflect ALL registry changes (Tasks 1-3):

- `test_default_triggers_has_plugins_section`: plugin count 8 → 9, valid_count 8 → 9
- `test_default_triggers_has_phase_compositions`: REVIEW parallel 2 → 3, SHIP sequence 3 → 4

- [ ] **Step 4: Run full test suite to verify**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add config/default-triggers.json tests/test-registry.sh
git commit -m "feat: replace context7-docs hint with unified-context-stack-hint"
```

---

## Chunk 2: Session-Start Hook — Capability Detection

### Task 4: Add capability detection block to session-start-hook.sh

**Files:**
- Modify: `hooks/session-start-hook.sh:457-470` (after step 8c, before step 9)

- [ ] **Step 1: Write the test first**

Add to `tests/test-registry.sh`:

```bash
test_context_capabilities_detection() {
    echo "-- test: context_capabilities detected in registry cache --"
    setup_test_env

    # Install context7 plugin (to simulate it being available)
    mkdir -p "${HOME}/.claude/plugins/cache/claude-plugins-official/context7"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_json_valid "cache file is valid JSON" "${cache_file}"

    # context_capabilities should exist in registry
    local has_caps
    has_caps="$(jq 'has("context_capabilities")' "${cache_file}" 2>/dev/null)"
    assert_equals "registry has context_capabilities" "true" "${has_caps}"

    # context7 should be true (plugin installed)
    local ctx7
    ctx7="$(jq -r '.context_capabilities.context7' "${cache_file}" 2>/dev/null)"
    assert_equals "context7 detected as true" "true" "${ctx7}"

    # context_hub_indexed should derive from context7
    local hub_idx
    hub_idx="$(jq -r '.context_capabilities.context_hub_indexed' "${cache_file}" 2>/dev/null)"
    assert_equals "context_hub_indexed derived from context7" "true" "${hub_idx}"

    # chub CLI not on PATH in test env
    local chub_cli
    chub_cli="$(jq -r '.context_capabilities.context_hub_cli' "${cache_file}" 2>/dev/null)"
    assert_equals "context_hub_cli is false (not on PATH)" "false" "${chub_cli}"

    # serena not installed
    local serena
    serena="$(jq -r '.context_capabilities.serena' "${cache_file}" 2>/dev/null)"
    assert_equals "serena is false (not installed)" "false" "${serena}"

    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "context_capabilities"`
Expected: FAIL — `context_capabilities` key doesn't exist yet.

- [ ] **Step 3: Implement capability detection in session-start-hook.sh**

Insert after step 8c (after line 457, the `fi` that closes the auto-discover block), before step 9:

```bash
# -----------------------------------------------------------------
# Step 8d: Detect context stack capabilities
# -----------------------------------------------------------------
# Check which tools in the Unified Context Stack are available.
# Results written to registry as context_capabilities object.

_has_context7=false
_has_chub_cli=false
_has_serena=false
_has_forgetful=false

# Context7: check if plugin is available in PLUGINS_JSON
# (Simplification: checks plugin name, not MCP tool names. Covers the standard
# install path via claude-plugins-official. If Context7 were ever provided by a
# differently-named plugin, this would need MCP tool detection instead.)
if printf '%s' "${PLUGINS_JSON}" | jq -e '.[] | select(.name == "context7" and .available == true)' >/dev/null 2>&1; then
    _has_context7=true
fi

# Context Hub CLI: check PATH
if command -v chub >/dev/null 2>&1; then
    _has_chub_cli=true
fi

# Context Hub indexed: derived from context7
_has_hub_indexed="${_has_context7}"

# Serena: check for serena plugin in PLUGINS_JSON or auto-discovered
if printf '%s' "${PLUGINS_JSON}" | jq -e '.[] | select(.name == "serena" and .available == true)' >/dev/null 2>&1; then
    _has_serena=true
fi

# Forgetful Memory: check for forgetful plugin (auto-discovered or curated)
if printf '%s' "${PLUGINS_JSON}" | jq -e '.[] | select(.name == "forgetful" and .available == true)' >/dev/null 2>&1; then
    _has_forgetful=true
fi

# Build context_capabilities JSON
CONTEXT_CAPS="$(jq -n \
    --argjson c7 "${_has_context7}" \
    --argjson chub "${_has_chub_cli}" \
    --argjson idx "${_has_hub_indexed}" \
    --argjson ser "${_has_serena}" \
    --argjson fm "${_has_forgetful}" \
    '{context7:$c7, context_hub_cli:$chub, context_hub_indexed:$idx, serena:$ser, forgetful_memory:$fm}'
)"

# Override unified-context-stack plugin available flag
_any_cap=false
if [ "${_has_context7}" = true ] || [ "${_has_chub_cli}" = true ] || [ "${_has_serena}" = true ] || [ "${_has_forgetful}" = true ]; then
    _any_cap=true
fi
if [ "${_any_cap}" = true ]; then
    PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq '
        map(if .name == "unified-context-stack" then .available = true else . end)
    ')"
fi
```

- [ ] **Step 4: Inject context_capabilities into the registry cache**

Modify step 9+10 (the `RESULT` jq call at line 462-481). Add `--argjson caps "${CONTEXT_CAPS}"` to the jq arguments and insert `context_capabilities:$caps` into the registry object.

Change this line inside the jq expression (line 471):
```
registry: {version:$version, skills:$skills, plugins:$plugins,
```
to:
```
registry: {version:$version, skills:$skills, plugins:$plugins, context_capabilities:$caps,
```

And add the new argument to the `jq -n` call (line 462-469):
```bash
RESULT="$(jq -n \
    --arg version "4.0.0" \
    --argjson skills "${SKILLS_JSON}" \
    --argjson plugins "${PLUGINS_JSON}" \
    --argjson caps "${CONTEXT_CAPS}" \
    --argjson pc "${PHASE_COMPOSITIONS}" \
    ...
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "context_capabilities"`
Expected: All new assertions PASS.

- [ ] **Step 6: Add degradation test (all capabilities false)**

Add to `tests/test-registry.sh`:

```bash
test_context_capabilities_all_false() {
    echo "-- test: context_capabilities all false when nothing installed --"
    setup_test_env

    # No plugins installed at all
    rm -rf "${HOME}/.claude/plugins"

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"

    # All capabilities should be false
    local all_false
    all_false="$(jq '[.context_capabilities | to_entries[] | .value] | all(. == false)' "${cache_file}" 2>/dev/null)"
    assert_equals "all capabilities false when nothing installed" "true" "${all_false}"

    # unified-context-stack plugin should be unavailable
    local ucs_avail
    ucs_avail="$(jq -r '.plugins[] | select(.name == "unified-context-stack") | .available' "${cache_file}" 2>/dev/null)"
    assert_equals "unified-context-stack unavailable when no caps" "false" "${ucs_avail}"

    teardown_test_env
}
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "all false"`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "feat: add context stack capability detection to session-start hook"
```

### Task 5: Inject context_capabilities into session-start additionalContext

**Files:**
- Modify: `hooks/session-start-hook.sh:580-591` (step 12, CONTEXT variable)

- [ ] **Step 1: Write the test**

Add to `tests/test-registry.sh`:

```bash
test_context_capabilities_in_health_output() {
    echo "-- test: context_capabilities in session-start output --"
    setup_test_env

    # Install context7 plugin
    mkdir -p "${HOME}/.claude/plugins/cache/claude-plugins-official/context7"

    local output
    output="$(run_hook)"

    # additionalContext should contain the Context Stack line
    local context
    context="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
    assert_contains "output has Context Stack line" "Context Stack:" "${context}"
    assert_contains "output has context7=true" "context7=true" "${context}"

    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "Context Stack"`
Expected: FAIL — no Context Stack line in output yet.

- [ ] **Step 3: Append context capabilities to the CONTEXT output**

In step 12 (around line 582), after the STATUS line, add:

```bash
# Build context capabilities summary for model consumption
_CAP_LINE=""
if [ -n "${CONTEXT_CAPS:-}" ]; then
    _CAP_LINE="$(printf '%s' "${CONTEXT_CAPS}" | jq -r 'to_entries | map("\(.key)=\(.value)") | "Context Stack: " + join(", ")')"
fi
```

Then after line 583, append `_CAP_LINE` to `CONTEXT`:

```bash
if [ -n "${_CAP_LINE}" ]; then
    CONTEXT="${CONTEXT}
${_CAP_LINE}"
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "Context Stack"`
Expected: PASS.

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "feat: inject context_capabilities into session-start output"
```

---

## Chunk 3: Orchestrator Skill Documents

### Task 6: Create SKILL.md (main orchestrator)

**Files:**
- Create: `skills/unified-context-stack/SKILL.md`

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p skills/unified-context-stack/tiers skills/unified-context-stack/phases
```

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: unified-context-stack
description: Tiered context retrieval across External Truth (docs), Internal Truth (dependencies), and Historical Truth (memory) with graceful degradation based on installed tools.
---

# Unified Context Stack

An infrastructure-level skill that provides tiered context retrieval for every SDLC phase. Reads your session's `Context Stack:` capabilities line to determine which tools are available, then follows strict fallback tiers.

## How to Use

1. Check the `Context Stack:` line from your session start for capability flags
2. Read the relevant **phase document** for your current SDLC phase
3. For each capability dimension needed, follow the **tier document** in strict order

## Capability Flags

These are injected by the session-start hook as: `Context Stack: context7=true, context_hub_cli=false, ...`

| Flag | Tool | What it enables |
|------|------|----------------|
| `context7` | Context7 MCP | Broad library doc retrieval |
| `context_hub_indexed` | Context Hub via Context7 | High-trust curated docs (query `/andrewyng/context-hub`) |
| `context_hub_cli` | `chub` CLI | Local curated doc retrieval and annotations |
| `serena` | Serena MCP | LSP-powered dependency mapping and AST edits |
| `forgetful_memory` | Forgetful Memory | Persistent cross-session architectural knowledge |

## Tier Documents

- [External Truth](tiers/external-truth.md) — API documentation retrieval
- [Internal Truth](tiers/internal-truth.md) — Blast-radius mapping and safe code edits
- [Historical Truth](tiers/historical-truth.md) — Institutional memory retrieval and storage

## Phase Documents

- [Triage & Plan](phases/triage-and-plan.md) — Context gathering before writing plans
- [Implementation](phases/implementation.md) — Mid-flight lookups during execution
- [Testing & Debug](phases/testing-and-debug.md) — Error resolution and live issue discovery
- [Code Review](phases/code-review.md) — Claim verification and dependency checks
- [Ship & Learn](phases/ship-and-learn.md) — Memory consolidation before session close
```

- [ ] **Step 3: Commit**

```bash
git add skills/unified-context-stack/SKILL.md
git commit -m "feat: add unified-context-stack SKILL.md"
```

### Task 7: Create tier documents

**Files:**
- Create: `skills/unified-context-stack/tiers/external-truth.md`
- Create: `skills/unified-context-stack/tiers/internal-truth.md`
- Create: `skills/unified-context-stack/tiers/historical-truth.md`

- [ ] **Step 1: Write external-truth.md**

```markdown
# External Truth — API Documentation Retrieval

Capability: Fetch accurate, up-to-date API documentation for third-party libraries.

## Tier 1 (High Trust): Context Hub via Context7

**Condition:** `context_hub_indexed = true`

Use the Context7 MCP tools with the curated Context Hub repository:

1. Call `resolve-library-id` to confirm the library exists in Context Hub
2. Call `get-library-docs` with `libraryId="/andrewyng/context-hub"`

**Query guidance:** Your `query` parameter should describe the specific API you need (e.g., "Stripe payment intents API", "React Router v7 route configuration"). Do NOT query for "Context Hub" — the `libraryId` handles targeting; the `query` handles specificity.

**Trust level:** Curated, human-reviewed. Trust fully.

## Tier 2 (Medium Trust): Broad Context7

**Condition:** `context7 = true` AND Tier 1 returned no results

Use Context7 MCP with a broad query — no library constraint. Let `resolve-library-id` find the best match.

**Trust level:** Web-scraped. Verify method signatures and parameter names before implementing.

## Tier 3 (Low Trust): chub CLI

**Condition:** `context_hub_cli = true` AND Tiers 1+2 unavailable or empty

Execute in terminal:
```
chub search "<library>" --json
chub get <id> --lang <lang>
```

**Trust level:** Curated but requires shell access. Verify version matches project.

## Tier 4 (Base): Web Search

**Condition:** None of the above are available

Use WebSearch / WebFetch to find official documentation.

**Trust level:** High skepticism. Cross-reference multiple sources. Verify all API signatures.
```

- [ ] **Step 2: Write internal-truth.md**

```markdown
# Internal Truth — Blast-Radius Mapping & Safe Edits

Capability: Understand local file dependencies and inject code safely.

## Tier 1: Serena LSP

**Condition:** `serena = true`

- Use `find_symbol` to locate definitions and references
- Use `cross_reference` to map which files depend on a symbol
- Use `insert_after_symbol` for safe AST-level code injection without breaking formatting

## Tier 2: Standard Tools (Fallback)

**Condition:** `serena = false`

- Use `Grep` to find symbol references across the codebase
- Use `Read` to examine file contents and understand context
- Use `Edit` for modifications

**WARNING:** Without Serena's AST awareness, proceed with extra caution on:
- Large files (>500 lines) — higher risk of formatting/indentation errors
- Complex class hierarchies — manual dependency tracing may miss references
- Refactors that rename symbols — grep may miss dynamic references

Always verify changes compile/pass after editing without Serena.
```

- [ ] **Step 3: Write historical-truth.md**

```markdown
# Historical Truth — Institutional Memory

Capability: Retrieve and store project-specific rules, decisions, and quirks across sessions.

## Tier 1: Forgetful Memory

**Condition:** `forgetful_memory = true`

### Reading (all phases)
- Use `memory-search` to query past architectural decisions
- Use `memory-explore` to browse the knowledge graph for related context

### Writing (Phase 5: Ship & Learn)
- Use `memory-save` to permanently store new architectural rules discovered during this session

## Tier 2: Flat Files (Fallback)

**Condition:** `forgetful_memory = false`

### Reading (all phases)
Check these files in order for project context:
1. `CLAUDE.md` — project instructions and conventions
2. `docs/architecture.md` — architectural decisions (if exists)
3. `.cursorrules` / `.clauderules` — additional project rules (if exist)

### Writing (Phase 5: Ship & Learn)
- Append findings to `docs/learnings.md` (create if it doesn't exist)
- Format: date, context, and the specific learning or workaround
```

- [ ] **Step 4: Commit**

```bash
git add skills/unified-context-stack/tiers/
git commit -m "feat: add unified-context-stack tier documents"
```

### Task 8: Create phase documents

**Files:**
- Create: `skills/unified-context-stack/phases/triage-and-plan.md`
- Create: `skills/unified-context-stack/phases/implementation.md`
- Create: `skills/unified-context-stack/phases/testing-and-debug.md`
- Create: `skills/unified-context-stack/phases/code-review.md`
- Create: `skills/unified-context-stack/phases/ship-and-learn.md`

- [ ] **Step 1: Write triage-and-plan.md**

```markdown
# Phase 1: Triage & Plan

Before writing the implementation plan, gather context across all three dimensions.

## Steps

### 1. Historical Truth
Query institutional memory for past constraints in this area:
- "Do we have a standard way we handle [relevant pattern] in this project?"
- "Are there known architectural constraints for [affected module]?"

### 2. External Truth
If the task involves third-party services or libraries:
- Fetch curated API docs for the specific version used in this project
- Include relevant API signatures and usage examples in the written plan

### 3. Internal Truth
Map the blast radius before committing to a plan:
- Identify all files that depend on the modules being changed
- List these files in the plan so the implementer knows the full scope
```

- [ ] **Step 2: Write implementation.md**

```markdown
# Phase 2: Implementation

During file-by-file plan execution, use context as needed.

## Steps

### 1. Internal Truth (Primary)
For each file modification:
- Use Serena (Tier 1) or Grep (Tier 2) to verify current symbol locations
- Ensure insertions don't break existing references

### 2. External Truth (On-Demand)
If you encounter a library or API not covered in the original plan:
- Trigger the External Truth tier cascade for a mid-flight lookup
- Do not guess API signatures — look them up
```

- [ ] **Step 3: Write testing-and-debug.md**

```markdown
# Phase 3: Testing & Debug

When tests fail or errors occur, use context to resolve efficiently.

## Steps

### 1. Historical Truth (First Check)
Before investigating from scratch:
- Query memory for this exact error message or pattern
- Check if this is a known environmental quirk with a documented workaround

### 2. External Truth (Library Issues)
If the error involves a third-party library:
- Check Context Hub / Context7 for known issues or breaking changes
- Search for the specific error message in the library's documentation
- For API errors (4xx/5xx), check if there are known outages or recently discovered bugs
```

- [ ] **Step 4: Write code-review.md**

```markdown
# Phase 4: Code Review

When processing reviewer feedback, verify claims before accepting changes.

## Steps

### 1. External Truth (Claim Verification)
If a reviewer claims incorrect API usage:
- Look up the specific parameter/method in curated docs before accepting the change
- If the reviewer is wrong, cite the documentation source in your response

### 2. Internal Truth (Dependency Safety)
If a reviewer suggests an architectural change:
- Map downstream dependencies before implementing the suggestion
- Flag any files that would break silently from the proposed change
```

- [ ] **Step 5: Write ship-and-learn.md**

```markdown
# Phase 5: Ship & Learn

Before completing the session, consolidate what was learned.

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

- [ ] **Step 6: Commit**

```bash
git add skills/unified-context-stack/phases/
git commit -m "feat: add unified-context-stack phase documents"
```

---

## Chunk 4: Tests, Fallback Registry, Documentation

### Task 9: Add composition emission tests

**Files:**
- Modify: `tests/test-context.sh`

- [ ] **Step 1: Write test for unified-context-stack PARALLEL line emission**

Add to `tests/test-context.sh` a new registry installer and test:

```bash
install_registry_with_context_stack() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    # Use the actual default-triggers.json but inject available flags
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null >/dev/null
    # Mark unified-context-stack as available in the cache
    local tmp="${cache_file}.tmp"
    jq '.plugins |= map(if .name == "unified-context-stack" then .available = true else . end) |
        .context_capabilities = {context7:true,context_hub_cli:false,context_hub_indexed:true,serena:false,forgetful_memory:false}' \
        "${cache_file}" > "${tmp}" && mv "${tmp}" "${cache_file}"
}

test_context_stack_parallel_emission() {
    echo "-- test: unified-context-stack emits PARALLEL line --"
    setup_test_env
    install_registry_with_context_stack

    # "build a new stripe integration" should trigger DESIGN phase
    local output ctx
    output="$(run_hook "build a new stripe payment integration for our app")"
    ctx="$(extract_context "${output}")"

    assert_contains "context stack PARALLEL emitted" "unified-context-stack" "${ctx}"

    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/test-context.sh 2>&1 | grep -A2 "context_stack"`
Expected: PASS (composition entries are plugin-gated and the plugin is marked available).

- [ ] **Step 3: Write test for methodology hint emission**

```bash
test_context_stack_hint_emission() {
    echo "-- test: unified-context-stack-hint fires on library keywords --"
    setup_test_env
    install_registry_with_context_stack

    # "upgrade the stripe library" has library keyword but context-stack is not a skill
    # so it should appear as a methodology hint
    local output ctx
    output="$(run_hook "upgrade the stripe library to the latest version")"
    ctx="$(extract_context "${output}")"

    assert_contains "context stack hint emitted" "CONTEXT STACK" "${ctx}"

    teardown_test_env
}
```

- [ ] **Step 4: Run test**

Run: `bash tests/test-context.sh 2>&1 | grep -A2 "context_stack_hint"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/test-context.sh
git commit -m "test: add unified-context-stack composition and hint emission tests"
```

### Task 10: Update fallback registry

**Files:**
- Modify: `config/fallback-registry.json`

- [ ] **Step 1: Regenerate fallback registry**

The fallback registry should mirror the cache structure. Run the session-start hook in a clean env to generate a fresh cache, then copy relevant sections:

```bash
# Generate a fresh registry with no plugins installed
HOME_BAK="$HOME"
export HOME="$(mktemp -d)"
mkdir -p "$HOME/.claude"
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh >/dev/null 2>&1
cp "$HOME/.claude/.skill-registry-cache.json" config/fallback-registry.json
export HOME="$HOME_BAK"
```

- [ ] **Step 2: Verify fallback is valid and includes context_capabilities**

Run: `jq '.context_capabilities' config/fallback-registry.json`
Expected: Should show all capabilities as `false` (nothing installed in clean env).

Run: `jq '.plugins[] | select(.name == "unified-context-stack")' config/fallback-registry.json`
Expected: Should show the plugin entry with `available: false`.

- [ ] **Step 3: Run drift detection test**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 "fallback"`
Expected: All fallback tests pass.

- [ ] **Step 4: Commit**

```bash
git add config/fallback-registry.json
git commit -m "chore: regenerate fallback registry with unified-context-stack"
```

### Task 11: Syntax-check all new files and run full suite

**Files:** (verification only, no changes)

- [ ] **Step 1: Syntax-check the hook**

Run: `bash -n hooks/session-start-hook.sh`
Expected: No errors.

- [ ] **Step 2: Validate all JSON**

Run: `jq empty config/default-triggers.json && jq empty config/fallback-registry.json`
Expected: No output (valid).

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass across all three test files.

- [ ] **Step 4: Manual smoke test**

Run: `SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh <<< '{"prompt":"build a stripe payment integration"}'`
Expected: Should show `unified-context-stack` in PARALLEL composition line output.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete unified context stack implementation"
```
