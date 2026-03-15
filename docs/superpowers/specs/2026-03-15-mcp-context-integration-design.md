# MCP Context Integration — Detection, Tool Names, Phase Coverage, Enforcement

**Date:** 2026-03-15
**Status:** Approved
**Scope:** Fix MCP tool detection, correct tool name references, fill phase coverage gaps, add serena nudge guard

## Problem

Three MCP-based context tools (Serena, Forgetful, OpenSpec) are installed and functional, but the auto-claude-skills plugin under-utilizes two of them:

1. **Detection bug:** Serena and Forgetful are registered as MCP servers (`claude mcp add`), not as marketplace plugins. The session-start hook only checks the plugins array, so both report `false` despite being connected.
2. **Tool name mismatches:** Phase and tier docs reference non-existent tool names (`cross_reference`, `memory-search`, `memory-save`, `memory-explore`).
3. **Phase coverage gaps:** Implementation and Code Review phases lack Forgetful (Historical Truth) guidance.
4. **No active enforcement:** Serena availability is passively hinted but never reinforced when the model falls back to Grep for symbol lookups.
5. **Forgetful not curated:** Missing from `config/default-triggers.json` plugins array — no phase_fit metadata even when detected.

## Design

### Section 1: MCP Detection Fallback (`session-start-hook.sh`)

After the existing `CONTEXT_CAPS` computation (line 519), add a fallback that reads `~/.claude.json` for MCP server registrations:

- Read `~/.claude.json` with a single `jq --slurpfile` call
- Check user-scoped `mcpServers` (top-level key) for forgetful, serena, context7
- Check project-scoped `projects.<project-path>.mcpServers` for the same
- Merge: project-scoped overrides user-scoped
- Only upgrade `false` → `true`, never downgrade (additive to plugin detection)
- Silent fallback if `~/.claude.json` missing or jq unavailable

**Config locations confirmed:**
- User-scoped: `~/.claude.json` → `mcpServers.forgetful`
- Project-scoped: `~/.claude.json` → `projects./path/to/project.mcpServers.serena`

### Section 2: Tool Name Corrections

**Serena — rename `cross_reference` → `find_referencing_symbols`:**

| File | Line | Change |
|------|------|--------|
| `tiers/internal-truth.md` | 10 | `cross_reference` → `find_referencing_symbols` |
| `phases/triage-and-plan.md` | 28 | `cross_reference` → `find_referencing_symbols` |
| `phases/implementation.md` | 9 | `cross_reference` → `find_referencing_symbols` |
| `phases/code-review.md` | 24 | `cross_reference` → `find_referencing_symbols` |

**Forgetful — replace fictional tool names with actual MCP tool names:**

| File | Change |
|------|--------|
| `tiers/historical-truth.md` | Replace `memory-search`, `memory-explore`, `memory-save` with `discover_forgetful_tools` + `execute_forgetful_tool` pattern |
| `phases/triage-and-plan.md:16` | Replace `memory-search` with Forgetful query intent |
| `phases/testing-and-debug.md:9` | Replace `memory-search` with Forgetful query intent |
| `phases/ship-and-learn.md:34` | Replace `memory-save` with Forgetful store intent |

**Forgetful tier doc rewrite (`historical-truth.md`):**

```markdown
## Tier 1: Forgetful Memory

**Condition:** `forgetful_memory = true`

### Reading (all phases)
- Use `discover_forgetful_tools` to list available memory operations, then `execute_forgetful_tool` to query past architectural decisions
- Browse related context by executing the exploration tool discovered above

### Writing (Phase 5: Ship & Learn)
- Use `execute_forgetful_tool` to permanently store new architectural rules discovered during this session
```

**Phase doc approach:** Reference the short intent (e.g., "query Forgetful for past decisions") rather than spelling out the two-step dance every time. The tier doc is the canonical reference for actual mechanics.

### Section 3: Phase Coverage Gaps

**Implementation phase (`implementation.md`) — new step 0:**

```markdown
### 0. Historical Truth (Workaround Check)
Before implementing each file, check for known patterns:
- **forgetful_memory=true**: Query Forgetful for known workarounds, gotchas, or implementation patterns related to the current file or module
- **forgetful_memory=false**: Check CLAUDE.md and docs/learnings.md for relevant notes
- If a known workaround exists, apply it directly rather than rediscovering it
```

**Code Review phase (`code-review.md`) — new step 3:**

```markdown
### 3. Historical Truth (Convention Check)
Before accepting architectural changes:
- **forgetful_memory=true**: Query Forgetful for prior architectural conventions or decisions related to the affected area
- **forgetful_memory=false**: Check CLAUDE.md for documented conventions
- If a reviewer's suggestion contradicts a documented convention, flag the conflict rather than silently applying the change
```

### Section 4: Serena PreToolUse Nudge Guard

**New file:** `hooks/serena-nudge.sh`

**Behavior:**
- Triggers on PreToolUse for `Grep` tool calls
- Checks `serena=true` in cached registry (`~/.claude/.skill-registry-cache.json`)
- Checks if the Grep pattern looks like a symbol lookup:
  - Keyword prefixes: `class `, `def `, `function `, `func `, `interface `, `struct `, `import `
  - Bare CamelCase identifiers (e.g., `MyClassName`)
  - Bare snake_case identifiers (e.g., `my_function_name`)
  - Complex regex patterns or multi-word searches are NOT flagged
- Emits advisory hint: `"Serena is available. Consider find_symbol or get_symbols_overview for symbol lookups instead of Grep."`
- Always exits 0 (fail-open, never blocking)

**Registration:** Added to `.claude-plugin/plugin.json` hooks array as a PreToolUse hook.

### Section 5: Forgetful Curated Plugin Entry

**Add to `config/default-triggers.json` plugins array:**

```json
{
  "name": "forgetful",
  "source": "mcp-server",
  "provides": {
    "commands": [],
    "skills": [],
    "agents": [],
    "hooks": [],
    "mcp_tools": ["discover_forgetful_tools", "execute_forgetful_tool", "how_to_use_forgetful_tool"]
  },
  "phase_fit": ["DESIGN", "PLAN", "IMPLEMENT", "DEBUG", "REVIEW", "SHIP"],
  "description": "Persistent cross-session memory via Forgetful Memory MCP — stores and retrieves architectural decisions, conventions, and workarounds",
  "available": false
}
```

**Add session-start hint** (parallel to existing Serena hint at line 670):

```bash
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.forgetful_memory == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
Forgetful: Use discover_forgetful_tools to list available memory operations, then execute_forgetful_tool to query or store architectural knowledge across sessions."
fi
```

## Files Modified

| File | Change Type |
|------|-------------|
| `hooks/session-start-hook.sh` | MCP fallback detection + Forgetful hint |
| `hooks/serena-nudge.sh` | **New** — PreToolUse nudge guard |
| `.claude-plugin/plugin.json` | Register serena-nudge hook |
| `config/default-triggers.json` | Add forgetful curated plugin entry |
| `skills/unified-context-stack/tiers/internal-truth.md` | Fix `cross_reference` → `find_referencing_symbols` |
| `skills/unified-context-stack/tiers/historical-truth.md` | Fix tool names to actual Forgetful MCP tools |
| `skills/unified-context-stack/phases/triage-and-plan.md` | Fix both tool names |
| `skills/unified-context-stack/phases/implementation.md` | Fix tool name + add Historical Truth step |
| `skills/unified-context-stack/phases/testing-and-debug.md` | Fix tool name |
| `skills/unified-context-stack/phases/code-review.md` | Fix tool name + add Historical Truth step |
| `skills/unified-context-stack/phases/ship-and-learn.md` | Fix tool name |

## Non-Goals

- No changes to OpenSpec integration (already fully functional)
- No PreToolUse guard for Forgetful (meta-tool API makes pattern matching impractical)
- No changes to the skill-activation-hook routing logic
- No MCP health-check verification (`claude mcp list` is 3.7s — too slow for any hook)

## Testing

- `bash tests/test-context.sh` — update existing test for new capability detection path
- Manual verification: start a new session and confirm `serena=true, forgetful_memory=true` in Context Stack line
- Manual verification: Grep for a CamelCase symbol and confirm serena nudge appears