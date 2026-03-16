# MCP Context Integration — Detection, Tool Names, Phase Coverage, Enforcement

**Date:** 2026-03-15
**Status:** Approved
**Scope:** Fix MCP tool detection, correct tool name references, fill phase coverage gaps, add serena nudge guard, enforce memory consolidation, enforce delta spec sync

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
- Check project-scoped `projects.<project-path>.mcpServers` for the same (use `_WORKSPACE_ROOT` variable, available at line 480)
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

**Registration:** Added to `hooks/hooks.json` under the `PreToolUse` key with `"matcher": "Grep"`, alongside the existing `openspec-guard.sh` entry.

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

### Section 6: Memory Consolidation Enforcement

Two enforcement points ensure learnings are not lost when a session ends.

#### 6a: Consolidation check in openspec-guard.sh

Extend the existing `hooks/openspec-guard.sh` (which already fires on `git commit/push` in SHIP phase) with a second check after the openspec-ship check:

- Compute project hash: `_PROJ_HASH="$(printf '%s' "${_proj_root}" | shasum | cut -d' ' -f1)"`
- Check for consolidation marker: `~/.claude/.context-stack-consolidated-${_PROJ_HASH}`
- If marker exists, compare its mtime with the latest git commit time
- If marker is fresh (mtime >= last commit time), pass silently
- If marker is stale or missing, emit: `"CONSOLIDATION GUARD: Memory consolidation has not been performed this session. Learnings may be lost. Run the memory consolidation step from ship-and-learn before committing."`
- Both the openspec-ship check and consolidation check run independently — both warnings can fire on the same commit
- Remains fail-open (exit 0 always)

#### 6b: New `consolidation-stop.sh` Stop hook

**New file:** `hooks/consolidation-stop.sh`

Fires when the session ends. Logic:
1. Read session token from `~/.claude/.skill-session-token`
2. Compute project hash and check consolidation marker freshness (same logic as 6a)
3. If marker is fresh, exit silently
4. If stale/missing, read `~/.claude/.skill-registry-cache.json` for available capabilities
5. Emit tier-specific guidance based on available tools:
   - `forgetful_memory=true`: `"Use discover_forgetful_tools → execute_forgetful_tool to store architectural learnings from this session."`
   - `context_hub_cli=true`: `"Use chub annotate to record API workarounds discovered."`
   - Neither: `"Append findings to docs/learnings.md before ending the session."`
6. Always exit 0 (advisory, never blocking)

**Registration:** Add to `hooks/hooks.json` Stop array alongside existing cozempic checkpoint entry.

### Section 7: Delta Spec Sync Check in openspec-guard.sh

Extend `hooks/openspec-guard.sh` with a third check: after the openspec-ship check and consolidation check, verify that archived delta specs have been synced to canonical specs.

**Logic:**
- Iterate through `openspec/changes/archive/*/specs/*/spec.md` (delta specs in archived change folders)
- For each delta spec, extract the capability name from the path structure
- Check if `openspec/specs/<capability>/spec.md` (canonical) exists
- If canonical exists, compare mtimes: if canonical is older than the archive folder, the delta was not synced
- If no canonical exists at all, the delta was never synced
- If any unsynced delta is found, emit: `"OPENSPEC GUARD: Archived delta specs may not be synced to canonical specs at openspec/specs/. Consider running openspec validate or manually merging delta changes before committing."`

**Key properties:**
- Only checks `openspec/changes/archive/` (not in-progress changes — those are caught by the existing openspec-ship check)
- Runs inside the existing `openspec-guard.sh`, same SHIP-phase gate, same fail-open behavior
- No new hook file needed for this check
- Uses file mtime comparison (no git history needed, fast)

## Files Modified

| File | Change Type |
|------|-------------|
| `hooks/session-start-hook.sh` | MCP fallback detection + Forgetful hint |
| `hooks/serena-nudge.sh` | **New** — PreToolUse nudge guard |
| `hooks/consolidation-stop.sh` | **New** — Stop hook for session-end consolidation reminder |
| `hooks/openspec-guard.sh` | Add consolidation check + delta spec sync check |
| `hooks/hooks.json` | Register serena-nudge PreToolUse hook + consolidation-stop Stop hook |
| `config/default-triggers.json` | Add forgetful curated plugin entry |
| `skills/unified-context-stack/tiers/internal-truth.md` | Fix `cross_reference` → `find_referencing_symbols` |
| `skills/unified-context-stack/tiers/historical-truth.md` | Fix tool names to actual Forgetful MCP tools |
| `skills/unified-context-stack/phases/triage-and-plan.md` | Fix both tool names |
| `skills/unified-context-stack/phases/implementation.md` | Fix tool name + add Historical Truth step |
| `skills/unified-context-stack/phases/testing-and-debug.md` | Fix tool name |
| `skills/unified-context-stack/phases/code-review.md` | Fix tool name + add Historical Truth step |
| `skills/unified-context-stack/phases/ship-and-learn.md` | Fix tool name |

## Non-Goals

- No PreToolUse guard for Forgetful (meta-tool API makes pattern matching impractical)
- No changes to the skill-activation-hook routing logic
- No MCP health-check verification (`claude mcp list` is 3.7s — too slow for any hook)
- No changes to the openspec-ship skill itself (enforcement is via guards, not skill changes)
- No CI-level OpenSpec validation (out of scope — this is session-level enforcement only)

## Testing

- `bash tests/test-context.sh` — update existing test for new capability detection path
- Manual verification: start a new session and confirm `serena=true, forgetful_memory=true` in Context Stack line
- Manual verification: Grep for a CamelCase symbol and confirm serena nudge appears
- Manual verification: git commit in SHIP phase without consolidation marker — confirm consolidation warning
- Manual verification: end session without consolidation — confirm Stop hook tier-specific guidance
- Manual verification: git commit with unsynced archived delta specs — confirm delta spec sync warning