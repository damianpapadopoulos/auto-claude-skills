# Context Stack Tool Installation via /setup — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `/setup` to install context stack tools (uv, Serena, Forgetful Memory, chub, OpenSpec) and improve session-start detection to nudge users toward `/setup` when tools are missing.

**Architecture:** Three files change. `commands/setup.md` gets two new steps (prerequisites + context stack tools). `hooks/session-start-hook.sh` gets openspec detection and missing-context-count in the SETUP_CTA condition. `config/fallback-registry.json` gets the new `openspec` field.

**Tech Stack:** Bash 3.2, jq, Claude Code MCP, npm, uv/uvx

**Spec:** `docs/superpowers/specs/2026-03-14-setup-context-stack-tools-design.md`

---

## Chunk 1: All tasks

### Task 1: Add openspec detection to session-start hook (Step 8d)

**Files:**
- Modify: `hooks/session-start-hook.sh:465-482`

- [ ] **Step 1: Add `_has_openspec` check alongside existing `_has_chub_cli`**

After line 469 (`fi` closing the chub check), add the openspec PATH check:

```bash
# OpenSpec CLI: check PATH
_has_openspec=false
if command -v openspec >/dev/null 2>&1; then
    _has_openspec=true
fi
```

- [ ] **Step 2: Thread `_has_openspec` into the jq call that builds CONTEXT_CAPS**

Replace the jq call at lines 475-482 to add the `--argjson openspec` parameter and include `openspec` in the output object:

```bash
CONTEXT_CAPS="$(printf '%s' "${PLUGINS_JSON}" | jq \
    --argjson chub "${_has_chub_cli}" \
    --argjson openspec "${_has_openspec}" \
    '[.[] | select(.available == true) | .name] as $avail |
    ($avail | index("context7") != null) as $c7 |
    ($avail | index("serena") != null) as $ser |
    ($avail | index("forgetful") != null) as $fm |
    {context7:$c7, context_hub_cli:$chub, context_hub_available:$c7, serena:$ser, forgetful_memory:$fm, openspec:$openspec}'
)"
```

- [ ] **Step 3: Syntax-check the hook**

Run: `bash -n hooks/session-start-hook.sh`
Expected: no output (clean parse)

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: detect openspec CLI in session-start hook"
```

### Task 2: Add missing context stack count to SETUP_CTA condition (Steps 11-12)

**Files:**
- Modify: `hooks/session-start-hook.sh` (end of Step 11 and SETUP_CTA condition in Step 12)

**Note:** Line numbers below are from the *original* file. Task 1 added ~6 lines earlier in the file, so actual line numbers will be shifted by ~6 when implementing this task. Use the code-content anchors below to locate the correct insertion points.

- [ ] **Step 1: Add MISSING_CONTEXT_COUNT after `INSTALLED_COMPANIONS=...` line**

Find the line:
```bash
INSTALLED_COMPANIONS=$((TOTAL_COMPANIONS - MISSING_COMPANION_COUNT))
```

Insert immediately after it:

```bash
# Count missing context stack tools
MISSING_CONTEXT_COUNT=$(printf '%s' "${CONTEXT_CAPS}" | jq '[to_entries[] | select(.value == false)] | length')
```

- [ ] **Step 2: Extend the SETUP_CTA condition**

Find the line:
```bash
if [ "${MISSING_COMPANION_COUNT}" -gt 0 ] || [ "${MISSING_SKILLS_COUNT}" -gt 0 ] || [ "${AGENT_TEAMS_MISSING}" -eq 1 ]; then
```

Replace with:
```bash
if [ "${MISSING_COMPANION_COUNT}" -gt 0 ] || [ "${MISSING_SKILLS_COUNT}" -gt 0 ] || \
   [ "${AGENT_TEAMS_MISSING}" -eq 1 ] || [ "${MISSING_CONTEXT_COUNT}" -gt 0 ]; then
```

- [ ] **Step 3: Syntax-check the hook**

Run: `bash -n hooks/session-start-hook.sh`
Expected: no output (clean parse)

- [ ] **Step 4: Run existing tests to verify no regressions**

Run: `bash tests/run-tests.sh`
Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: include context stack tools in /setup nudge condition"
```

### Task 3: Update test fixture for context_capabilities

**Files:**
- Modify: `tests/test-context.sh:546`

- [ ] **Step 1: Add `openspec` to the test fixture's context_capabilities**

Find the line in `tests/test-context.sh`:
```bash
        .context_capabilities = {context7:true,context_hub_cli:false,context_hub_available:true,serena:false,forgetful_memory:false} |
```

Replace with:
```bash
        .context_capabilities = {context7:true,context_hub_cli:false,context_hub_available:true,serena:false,forgetful_memory:false,openspec:false} |
```

- [ ] **Step 2: Run tests to verify**

Run: `bash tests/test-context.sh`
Expected: all context tests pass

- [ ] **Step 3: Commit**

```bash
git add tests/test-context.sh
git commit -m "test: add openspec to context_capabilities test fixture"
```

### Task 4: Add openspec to fallback-registry.json

**Files:**
- Modify: `config/fallback-registry.json:627-633`

- [ ] **Step 1: Add `"openspec": false` to context_capabilities**

The current block at lines 627-633:
```json
  "context_capabilities": {
    "context7": false,
    "context_hub_cli": false,
    "context_hub_available": false,
    "serena": false,
    "forgetful_memory": false
  },
```

Replace with:
```json
  "context_capabilities": {
    "context7": false,
    "context_hub_cli": false,
    "context_hub_available": false,
    "serena": false,
    "forgetful_memory": false,
    "openspec": false
  },
```

- [ ] **Step 2: Validate JSON**

Run: `jq empty config/fallback-registry.json && echo "valid"`
Expected: `valid`

- [ ] **Step 3: Run existing tests**

Run: `bash tests/run-tests.sh`
Expected: all tests pass

- [ ] **Step 4: Commit**

```bash
git add config/fallback-registry.json
git commit -m "feat: add openspec to fallback registry context_capabilities"
```

### Task 5: Add Step 5 and Step 6 to commands/setup.md

**Files:**
- Modify: `commands/setup.md:93-106`

- [ ] **Step 1: Add Step 5 (uv prerequisite) and Step 6 (context stack tools) before the Execution section**

Insert before the `## Execution` section (after Step 4's closing code block):

````markdown
### 5. Prerequisites (uv package manager)

Serena and Forgetful Memory require the `uv` package manager (Python package installer).

Check if `uv` is available:
```bash
command -v uv || command -v "$HOME/.local/bin/uv" || command -v "$HOME/.cargo/bin/uv"
```

If not found, **ask the user:** "Serena and Forgetful Memory require the `uv` package manager. Would you like to install it? (`curl -LsSf https://astral.sh/uv/install.sh | sh`)"

If the user agrees:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

After installation, verify with `uv --version` (may need to add `~/.local/bin` to PATH for the current session).

If the user declines, note that Serena and Forgetful Memory will be unavailable and proceed to Step 6.

### 6. Context Stack tools

These tools enhance context retrieval with library docs, code navigation, persistent memory, and post-execution documentation.

Note: Context7 is already installed via Step 0 (marketplace plugin) and is not duplicated here.

**Detection:** Before presenting the table, check which tools are already installed:
- `chub`: `command -v chub`
- `openspec`: `command -v openspec`
- `serena`: run `claude mcp list` and check for a `serena` entry
- `forgetful`: run `claude mcp list` and check for a `forgetful` entry

Check `npm` availability. If `npm` is missing, note that chub and OpenSpec can't be installed.

Present only the missing tools. If none are missing, skip this step.

**Ask the user:** "Would you like to install the Context Stack tools? These enhance context retrieval with library docs, code navigation, persistent memory, and post-execution documentation."

| Tool | Type | Install command | Scope | Prerequisite |
|------|------|----------------|-------|-------------|
| Context Hub CLI (`chub`) | npm global | `npm install -g @aisuite/chub` | Global | npm |
| OpenSpec | npm global | `npm install -g @fission-ai/openspec@latest` | Global | npm |
| Serena | MCP server | `claude mcp add serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context claude-code --project "$(pwd)"` | Project-scoped | uv |
| Forgetful Memory | MCP server | `claude mcp add forgetful --scope user -- uvx forgetful-ai` | User (global) | uv |

If uv was not installed in Step 5, skip Serena and Forgetful Memory with a note.

The Serena command captures the current working directory at install time, making it project-scoped. Check for an existing serena MCP registration before adding a duplicate.

After installation, verify MCP servers with `claude mcp list` (look for "Connected" status) and CLIs with `command -v`.
````

- [ ] **Step 2: Update the Execution section**

Replace the current Execution section (lines 95-106):

```markdown
## Execution

Run each step in order. For steps 0 and 1, use AskUserQuestion to get the user's preference before taking action. For steps 2-4, if a skill directory already exists at the target path, skip it. For steps 5 and 6, use AskUserQuestion to get the user's preference before installing, and skip tools that are already installed.

After setup, confirm what was configured:
- Companion plugins: which were installed or skipped
- Agent teams: enabled or skipped
- Cozempic: installed or skipped
- `~/.claude/skills/doc-coauthoring/SKILL.md` exists
- `~/.claude/skills/webapp-testing/SKILL.md` exists
- `~/.claude/skills/security-scanner/SKILL.md` exists
- `uv`/`uvx`: available or skipped
- `chub`: available or skipped
- `openspec`: available or skipped
- Serena MCP: connected or skipped
- Forgetful Memory MCP: connected or skipped
```

- [ ] **Step 3: Commit**

```bash
git add commands/setup.md
git commit -m "feat: add context stack tool installation to /setup"
```

### Task 6: Run full test suite and verify

**Files:** (none modified — verification only)

- [ ] **Step 1: Syntax-check the hook**

Run: `bash -n hooks/session-start-hook.sh`
Expected: no output

- [ ] **Step 2: Run all tests**

Run: `bash tests/run-tests.sh`
Expected: all tests pass

- [ ] **Step 3: Test hook output includes openspec in Context Stack line**

Run: `bash hooks/session-start-hook.sh 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' | grep 'openspec='`
Expected: line containing `openspec=true` or `openspec=false`

- [ ] **Step 4: Validate fallback-registry.json has openspec**

Run: `jq '.context_capabilities.openspec' config/fallback-registry.json`
Expected: `false`
