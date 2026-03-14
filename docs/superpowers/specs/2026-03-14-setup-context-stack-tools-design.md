# Design: Context Stack Tool Installation via /setup

**Date:** 2026-03-14
**Status:** Approved
**Scope:** Extend `/setup` to install context stack tools (uv, Serena, Forgetful Memory, chub, OpenSpec) and improve session-start detection.

## Problem

The session-start hook detects context stack tool availability and emits capability flags (`context7=true, serena=false, ...`), but `/setup` has no steps for installing these tools. Users must manually discover and run the install commands, which is error-prone and undocumented.

## Approach

**Approach B: Two new steps — prerequisites + context stack.**

Add Step 5 (prerequisites) and Step 6 (context stack tools) to `commands/setup.md`. Extend the session-start hook to detect all tools and include missing context stack tools in the `/setup` nudge condition.

### Decision Log

- **Grouped consent (C)** over per-tool questions or silent install — context stack tools form a cohesive tier, one question suffices, but users should consent since installs pull from PyPI/npm/GitHub.
- **Hook nudges toward /setup (B)** rather than emitting install commands — keeps hook output clean, `/setup` is the single installation path.
- **Serena stays project-scoped** — config lives in `~/.claude.json` per-user, not shareable via repo. Each user runs `/setup` per project.
- **uv installation requires consent (C)** — piping curl to shell is a trust decision the user should make consciously.

## Design

### 1. commands/setup.md — Two new steps

#### Step 5: Prerequisites (uv package manager)

- Check if `uv`/`uvx` is on PATH (including `~/.local/bin` and `~/.cargo/bin`)
- If missing, ask: "Serena and Forgetful Memory require the `uv` package manager. Would you like to install it? (`curl -LsSf https://astral.sh/uv/install.sh | sh`)"
- If installed, verify by running `uv --version` to confirm PATH resolution
- If user declines, note that Serena + Forgetful Memory will be unavailable, proceed to Step 6 (npm-based tools will still be offered)

#### Step 6: Context Stack tools

Check `npm` availability first. If `npm` is missing, warn that chub and OpenSpec can't be installed and only offer the MCP-based tools (if uv is available).

Note: Context7 is already installed via Step 0 (marketplace plugin). It is not duplicated here.

Present missing tools as one grouped question: "Would you like to install the Context Stack tools? These enhance context retrieval with library docs, code navigation, persistent memory, and post-execution documentation."

| Tool | Type | Install command | Scope | Prerequisite |
|------|------|----------------|-------|-------------|
| Context Hub CLI (`chub`) | npm global | `npm install -g @aisuite/chub` | Global | npm |
| OpenSpec | npm global | `npm install -g @fission-ai/openspec@latest` | Global | npm |
| Serena | MCP server | `claude mcp add serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context claude-code --project "$(pwd)"` | Project | uv |
| Forgetful Memory | MCP server | `claude mcp add forgetful --scope user -- uvx forgetful-ai` | User (global) | uv |

Note: The Serena command captures `$(pwd)` at install time, making it project-scoped. Re-running `/setup` from a different project directory registers a separate Serena instance for that project. Check for an existing registration before adding a duplicate.

**Detection logic per tool:**
- `chub`: `command -v chub`
- `openspec`: `command -v openspec`
- `serena`: run `claude mcp list` and check for a `serena` entry in the output
- `forgetful`: run `claude mcp list` and check for a `forgetful` entry in the output

This aligns `/setup` detection with what `claude mcp list` reports, which is the same source of truth the session-start hook uses (the hook detects Serena/Forgetful via plugin availability in `PLUGINS_JSON`, which reflects MCP server registrations).

Skip already-installed tools. If uv was declined in Step 5, skip Serena and Forgetful Memory with a note.

After installation, verify with `claude mcp list` for MCP servers (look for "Connected" status next to serena/forgetful) and `command -v` for CLIs.

**Updated verification summary** at the end of setup adds:
- `uv`/`uvx` available or skipped
- `chub` available or skipped
- `openspec` available or skipped
- Serena MCP: connected or skipped
- Forgetful Memory MCP: connected or skipped

### 2. hooks/session-start-hook.sh — Detection and nudge

#### 2a. Extend Step 8d: Add OpenSpec detection

Add `command -v openspec` check alongside the existing `command -v chub` check. Feed into `CONTEXT_CAPS`:

```json
{
  "context7": true,
  "context_hub_cli": false,
  "context_hub_available": true,
  "serena": false,
  "forgetful_memory": false,
  "openspec": false
}
```

The `Context Stack:` line emitted to the model grows to include `openspec=true/false`.

#### 2b. Extend Steps 11-12: Include context stack in missing-tools condition

Step 11 (line 526) detects missing plugins/skills/features. Step 12 (line 600) uses those counts to build the `SETUP_CTA`.

Add a new count variable in Step 11:
```bash
# Count missing context stack tools from CONTEXT_CAPS
MISSING_CONTEXT_COUNT=$(printf '%s' "${CONTEXT_CAPS}" | jq '[to_entries[] | select(.value == false)] | length')
```

Extend the condition in Step 12 (line 603) to include it:
```bash
if [ "${MISSING_COMPANION_COUNT}" -gt 0 ] || [ "${MISSING_SKILLS_COUNT}" -gt 0 ] || \
   [ "${AGENT_TEAMS_MISSING}" -eq 1 ] || [ "${MISSING_CONTEXT_COUNT}" -gt 0 ]; then
```

No new message format — context stack tools simply contribute to the existing "something is missing" check that already triggers the `/setup` nudge.

### 3. config/fallback-registry.json — Add openspec field

Add `"openspec": false` to the `context_capabilities` object so the jq-unavailable fallback path stays consistent with the jq-available path. This matters because the fallback path (Step 2, line 74) copies fallback-registry.json wholesale and exits before any detection logic runs.

### 4. commands/setup.md — Update Execution section

The existing "Execution" section (line 97) says "For steps 2-4, if a skill directory already exists at the target path, skip it." Update to cover the new steps: "For steps 2-6, skip components that are already installed."

Update the verification summary to include the new tools.

## Files Changed

| File | Change |
|------|--------|
| `commands/setup.md` | Add Step 5 (uv prerequisite) and Step 6 (context stack tools) |
| `hooks/session-start-hook.sh` | Add openspec detection to Step 8d, include context stack in missing-tools condition at Step 11 |
| `config/fallback-registry.json` | Add `"openspec": false` to `context_capabilities` |

## What Does NOT Change

- `skills/unified-context-stack/SKILL.md` — reads capability flags from session, doesn't care how tools were installed
- `skills/openspec-ship/SKILL.md` — already handles its own OpenSpec detection and fallback
- `config/default-triggers.json` — `context_capabilities` is built dynamically by the hook, not stored here
- Phase documents and tier documents — no changes needed

## Testing

- `bash tests/run-tests.sh` — all existing tests pass
- `bash -n hooks/session-start-hook.sh` — syntax check
- `SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh` — verify context stack line includes openspec
- Manual: run `/setup` on a clean machine, verify all tools install correctly
- Manual: run `/setup` on a fully-configured machine, verify all tools are detected and skipped
