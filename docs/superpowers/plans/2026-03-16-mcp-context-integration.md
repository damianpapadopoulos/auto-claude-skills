# MCP Context Integration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix MCP tool detection so Serena and Forgetful are recognized, correct all tool name references, fill phase coverage gaps, and add a serena nudge guard.

**Architecture:** Augment plugin-based detection with MCP config file fallback. Fix doc references to match actual MCP tool names. Add lightweight PreToolUse hook for serena nudge.

**Tech Stack:** Bash 3.2, jq, Claude Code hooks system

**Spec:** `docs/superpowers/specs/2026-03-15-mcp-context-integration-design.md`

---

## Chunk 1: Detection and Configuration

### Task 1: Add MCP detection fallback to session-start-hook.sh

**Files:**
- Modify: `hooks/session-start-hook.sh:519` (insert after CONTEXT_CAPS computation)

- [ ] **Step 1: Add MCP fallback block after line 519**

Insert between the existing `CONTEXT_CAPS` computation (line 519) and the `unified-context-stack` override (line 521):

```bash
# MCP fallback: check ~/.claude.json for servers not detected via plugins
_CLAUDE_JSON="${HOME}/.claude.json"
if [ -f "${_CLAUDE_JSON}" ] && command -v jq >/dev/null 2>&1; then
    CONTEXT_CAPS="$(printf '%s' "${CONTEXT_CAPS}" | jq \
        --slurpfile cj "${_CLAUDE_JSON}" \
        --arg proj "${_WORKSPACE_ROOT}" \
        '# Check user-scoped mcpServers
         ($cj[0].mcpServers // {}) as $user_mcp |
         # Check project-scoped mcpServers
         (($cj[0].projects[$proj].mcpServers // {}) ) as $proj_mcp |
         # Merge: project overrides user
         ($user_mcp + $proj_mcp) as $all_mcp |
         # Augment: only upgrade false->true, never downgrade
         if .serena == false and ($all_mcp | has("serena")) then .serena = true else . end |
         if .forgetful_memory == false and ($all_mcp | has("forgetful")) then .forgetful_memory = true else . end |
         if .context7 == false and ($all_mcp | has("context7")) then .context7 = true else . end'
    )" || true
fi
```

- [ ] **Step 2: Syntax-check the hook**

Run: `bash -n hooks/session-start-hook.sh`
Expected: No output (clean parse)

- [ ] **Step 3: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "fix: add MCP config fallback for serena/forgetful detection"
```

### Task 2: Add Forgetful session-start hint

**Files:**
- Modify: `hooks/session-start-hook.sh:673` (insert after existing Serena hint block)

- [ ] **Step 1: Add Forgetful hint block after line 673**

Insert immediately after the Serena hint `fi` (line 673), before the OpenSpec capabilities block (line 675):

```bash
# Emit Forgetful usage hint when available
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.forgetful_memory == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
Forgetful: Use discover_forgetful_tools to list available memory operations, then execute_forgetful_tool to query or store architectural knowledge across sessions."
fi
```

- [ ] **Step 2: Syntax-check the hook**

Run: `bash -n hooks/session-start-hook.sh`
Expected: No output (clean parse)

- [ ] **Step 3: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: add Forgetful usage hint at session start"
```

### Task 3: Add Forgetful curated plugin entry to default-triggers.json

**Files:**
- Modify: `config/default-triggers.json:720` (insert before the closing `unified-context-stack` entry)

- [ ] **Step 1: Add Forgetful plugin entry**

Insert a new entry after the `atlassian` entry (after line 700) and before the `unified-context-stack` entry (line 702):

```json
    {
      "name": "forgetful",
      "source": "mcp-server",
      "provides": {
        "commands": [],
        "skills": [],
        "agents": [],
        "hooks": [],
        "mcp_tools": [
          "discover_forgetful_tools",
          "execute_forgetful_tool",
          "how_to_use_forgetful_tool"
        ]
      },
      "phase_fit": [
        "DESIGN",
        "PLAN",
        "IMPLEMENT",
        "DEBUG",
        "REVIEW",
        "SHIP"
      ],
      "description": "Persistent cross-session memory via Forgetful Memory MCP — stores and retrieves architectural decisions, conventions, and workarounds",
      "available": false
    },
```

- [ ] **Step 2: Validate JSON syntax**

Run: `jq empty config/default-triggers.json && echo "Valid JSON"`
Expected: `Valid JSON`

- [ ] **Step 3: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: add forgetful to curated plugins list"
```

---

## Chunk 2: Tool Name Corrections

### Task 4: Fix Serena tool name — `cross_reference` → `find_referencing_symbols`

**Files:**
- Modify: `skills/unified-context-stack/tiers/internal-truth.md:10`
- Modify: `skills/unified-context-stack/phases/triage-and-plan.md:28`
- Modify: `skills/unified-context-stack/phases/implementation.md:9`
- Modify: `skills/unified-context-stack/phases/code-review.md:24`

- [ ] **Step 1: Replace `cross_reference` in all four files**

In each file, replace `cross_reference` with `find_referencing_symbols`:

- `tiers/internal-truth.md:10`: `Use \`cross_reference\`` → `Use \`find_referencing_symbols\``
- `phases/triage-and-plan.md:28`: `\`cross_reference\`` → `\`find_referencing_symbols\``
- `phases/implementation.md:9`: `\`cross_reference\`` → `\`find_referencing_symbols\``
- `phases/code-review.md:24`: `\`cross_reference\`` → `\`find_referencing_symbols\``

- [ ] **Step 2: Verify no remaining `cross_reference` references**

Run: `grep -r "cross_reference" skills/unified-context-stack/`
Expected: No output

- [ ] **Step 3: Commit**

```bash
git add skills/unified-context-stack/
git commit -m "fix: correct serena tool name cross_reference -> find_referencing_symbols"
```

### Task 5: Fix Forgetful tool names in tier doc

**Files:**
- Modify: `skills/unified-context-stack/tiers/historical-truth.md`

- [ ] **Step 1: Rewrite Tier 1 section**

Replace the entire Tier 1 section (lines 5-14) with:

```markdown
## Tier 1: Forgetful Memory

**Condition:** `forgetful_memory = true`

### Reading (all phases)
- Use `discover_forgetful_tools` to list available memory operations, then `execute_forgetful_tool` to query past architectural decisions
- Browse related context by executing the exploration tool discovered above

### Writing (Phase 5: Ship & Learn)
- Use `execute_forgetful_tool` to permanently store new architectural rules discovered during this session
```

- [ ] **Step 2: Verify no remaining `memory-search`, `memory-explore`, `memory-save` references in tier doc**

Run: `grep -E "memory-(search|explore|save)" skills/unified-context-stack/tiers/historical-truth.md`
Expected: No output

- [ ] **Step 3: Commit**

```bash
git add skills/unified-context-stack/tiers/historical-truth.md
git commit -m "fix: correct forgetful tool names in historical-truth tier doc"
```

### Task 6: Fix Forgetful tool names in phase docs

**Files:**
- Modify: `skills/unified-context-stack/phases/triage-and-plan.md:16`
- Modify: `skills/unified-context-stack/phases/testing-and-debug.md:9`
- Modify: `skills/unified-context-stack/phases/ship-and-learn.md:34`

- [ ] **Step 1: Fix triage-and-plan.md line 16**

Replace:
```
- **forgetful_memory=true**: Use `memory-search` to query past architectural decisions and known constraints
```
With:
```
- **forgetful_memory=true**: Query Forgetful for past architectural decisions and known constraints (see `tiers/historical-truth.md` for tool mechanics)
```

- [ ] **Step 2: Fix testing-and-debug.md line 9**

Replace:
```
- **forgetful_memory=true**: Use `memory-search` for this exact error message or pattern
```
With:
```
- **forgetful_memory=true**: Query Forgetful for this exact error message or pattern (see `tiers/historical-truth.md` for tool mechanics)
```

- [ ] **Step 3: Fix ship-and-learn.md line 34**

Replace:
```
Execute `memory-save` to permanently store:
```
With:
```
Use Forgetful to permanently store (see `tiers/historical-truth.md` for tool mechanics):
```

- [ ] **Step 4: Verify no remaining fictional tool names across all phase docs**

Run: `grep -rE "memory-(search|explore|save)" skills/unified-context-stack/phases/`
Expected: No output

- [ ] **Step 5: Commit**

```bash
git add skills/unified-context-stack/phases/
git commit -m "fix: correct forgetful tool names in all phase docs"
```

---

## Chunk 3: Phase Coverage Gaps and Serena Nudge

### Task 7: Add Historical Truth to Implementation phase

**Files:**
- Modify: `skills/unified-context-stack/phases/implementation.md`

- [ ] **Step 1: Insert new step 0 before existing step 1**

Insert at line 6 (before `### 1. Internal Truth`):

```markdown
### 0. Historical Truth (Workaround Check)
Before implementing each file, check for known patterns:
- **forgetful_memory=true**: Query Forgetful for known workarounds, gotchas, or implementation patterns related to the current file or module
- **forgetful_memory=false**: Check CLAUDE.md and docs/learnings.md for relevant notes
- If a known workaround exists, apply it directly rather than rediscovering it

```

- [ ] **Step 2: Renumber existing steps**

Renumber `### 1.` → `### 1.`, `### 2.` → `### 2.`, `### 3.` → `### 3.` — no changes needed since the new step is `### 0.`

- [ ] **Step 3: Commit**

```bash
git add skills/unified-context-stack/phases/implementation.md
git commit -m "feat: add Historical Truth step to Implementation phase"
```

### Task 8: Add Historical Truth to Code Review phase

**Files:**
- Modify: `skills/unified-context-stack/phases/code-review.md`

- [ ] **Step 1: Append new step 3 after existing step 2**

Append at the end of the file (after line 26):

```markdown

### 3. Historical Truth (Convention Check)
Before accepting architectural changes:
- **forgetful_memory=true**: Query Forgetful for prior architectural conventions or decisions related to the affected area
- **forgetful_memory=false**: Check CLAUDE.md for documented conventions
- If a reviewer's suggestion contradicts a documented convention, flag the conflict rather than silently applying the change
```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/phases/code-review.md
git commit -m "feat: add Historical Truth step to Code Review phase"
```

### Task 9: Create serena-nudge.sh PreToolUse hook

**Files:**
- Create: `hooks/serena-nudge.sh`

- [ ] **Step 1: Write the hook script**

```bash
#!/bin/bash
# Serena nudge — hints when Grep is used for symbol lookups while serena=true
# PreToolUse hook. Bash 3.2 compatible. Exits 0 always (hint only, fail-open).
trap 'exit 0' ERR

_INPUT="$(cat)"

# Fast path: only care about Grep (matcher should handle this, but double-check)
_TOOL_NAME=""
if command -v jq >/dev/null 2>&1; then
    _TOOL_NAME="$(printf '%s' "${_INPUT}" | jq -r '.tool_name // empty' 2>/dev/null)" || true
fi
[ "${_TOOL_NAME}" = "Grep" ] || exit 0

# Check serena availability from cached registry
_CACHE="${HOME}/.claude/.skill-registry-cache.json"
[ -f "${_CACHE}" ] || exit 0
_SERENA="$(jq -r '.context_capabilities.serena // false' "${_CACHE}" 2>/dev/null)" || true
[ "${_SERENA}" = "true" ] || exit 0

# Check if pattern looks like a symbol lookup
_PATTERN="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.pattern // empty' 2>/dev/null)" || true
[ -n "${_PATTERN}" ] || exit 0

case "${_PATTERN}" in
    *class\ *|*def\ *|*function\ *|*func\ *|*interface\ *|*struct\ *|*import\ *)
        ;; # likely symbol lookup
    *)
        # Check for bare CamelCase or snake_case identifiers (no regex operators)
        if printf '%s' "${_PATTERN}" | grep -qE '^[A-Z][a-zA-Z0-9]+$' 2>/dev/null; then
            : # CamelCase — likely a class/type name
        elif printf '%s' "${_PATTERN}" | grep -qE '^[a-z_][a-z0-9_]+$' 2>/dev/null; then
            : # snake_case — likely a function name
        else
            exit 0 # regex pattern or complex search — not a symbol lookup
        fi
        ;;
esac

_MSG="Serena is available. Consider find_symbol or get_symbols_overview for symbol lookups instead of Grep."
jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
exit 0
```

- [ ] **Step 2: Make executable**

Run: `chmod +x hooks/serena-nudge.sh`

- [ ] **Step 3: Syntax-check**

Run: `bash -n hooks/serena-nudge.sh`
Expected: No output (clean parse)

- [ ] **Step 4: Commit**

```bash
git add hooks/serena-nudge.sh
git commit -m "feat: add serena PreToolUse nudge guard for Grep symbol lookups"
```

### Task 10: Register serena-nudge in hooks.json

**Files:**
- Modify: `hooks/hooks.json:48` (insert after existing PreToolUse entry)

- [ ] **Step 1: Add Grep matcher entry to PreToolUse array**

Add a new entry to the `PreToolUse` array (after the existing `Bash` matcher entry, before `PostToolUse`):

```json
      {
        "matcher": "Grep",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/serena-nudge.sh"
          }
        ]
      }
```

- [ ] **Step 2: Validate JSON syntax**

Run: `jq empty hooks/hooks.json && echo "Valid JSON"`
Expected: `Valid JSON`

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: register serena-nudge in hooks.json PreToolUse"
```

---

## Chunk 4: Test Updates

### Task 11: Update test-context.sh for MCP detection

**Files:**
- Modify: `tests/test-context.sh`

- [ ] **Step 1: Add a test case for MCP fallback detection**

Add a new test function before `print_summary` at the end of `test-context.sh`. The test should:

1. Create `~/.claude.json` in the temp HOME with mock `mcpServers` containing `"serena"` and `"forgetful"`
2. Run the session-start hook
3. Verify the cached registry has `serena: true` and `forgetful_memory: true`

```bash
test_mcp_fallback_detection() {
    echo "-- test: MCP fallback detects serena and forgetful from ~/.claude.json --"
    setup_test_env
    # HOME is now a temp dir (set by setup_test_env) — safe to write ~/.claude.json

    # Write test config with MCP servers
    local proj_root
    proj_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    python3 -c "
import json, sys
d = {}
try:
    d = json.load(open('${HOME}/.claude.json'))
except: pass
d.setdefault('mcpServers', {})['forgetful'] = {'type':'stdio','command':'echo'}
d.setdefault('projects', {}).setdefault('${proj_root}', {}).setdefault('mcpServers', {})['serena'] = {'type':'stdio','command':'echo'}
json.dump(d, open('${HOME}/.claude.json', 'w'))
"

    # Run session-start hook
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null >/dev/null

    # Check cached registry
    local cache="${HOME}/.claude/.skill-registry-cache.json"
    local ser fm
    ser="$(jq -r '.context_capabilities.serena // false' "${cache}" 2>/dev/null)"
    fm="$(jq -r '.context_capabilities.forgetful_memory // false' "${cache}" 2>/dev/null)"

    assert_equals "serena should be true via MCP fallback" "true" "${ser}"
    assert_equals "forgetful_memory should be true via MCP fallback" "true" "${fm}"
    echo "   PASS"
}
```

- [ ] **Step 2: Register the new test in the test runner**

Add `test_mcp_fallback_detection` call immediately before the `print_summary` line at the end of `test-context.sh`.

- [ ] **Step 3: Run the test**

Run: `bash tests/test-context.sh`
Expected: All tests pass, including the new MCP fallback test

- [ ] **Step 4: Commit**

```bash
git add tests/test-context.sh
git commit -m "test: add MCP fallback detection test"
```

### Task 12: Run full test suite

- [ ] **Step 1: Run all tests**

Run: `bash tests/run-tests.sh`
Expected: All test suites pass

- [ ] **Step 2: Fix any regressions**

If tests fail, identify and fix the issue before proceeding.

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address test regressions from MCP integration changes"
```
