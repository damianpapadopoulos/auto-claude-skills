# Historical Truth — Institutional Memory

Capability: Retrieve and store project-specific rules, decisions, and quirks across sessions.

## Tier 1: Forgetful Memory

**Condition:** `forgetful_memory = true`

### Bootstrap (once per session, before first use)
- Call `mcp__forgetful__discover_forgetful_tools` (no arguments) to retrieve the concrete operation list available in this session — this is the entry point, not `how_to_use_forgetful_tool`
- Call `mcp__forgetful__how_to_use_forgetful_tool(tool_name=<operation>)` only when you need detailed docs on a specific operation discovered in the previous step — it takes a required `tool_name` argument and returns documentation for that one operation

### Reading (DESIGN, PLAN, IMPLEMENT, DEBUG, REVIEW)
- Call `mcp__forgetful__execute_forgetful_tool` with a recall/query operation, keyed by current repo basename + active topic, to surface prior architectural decisions, known constraints, or workaround notes
- Use the returned context before proposing approaches (DESIGN), writing plans (PLAN), modifying code (IMPLEMENT), debugging (DEBUG), or reviewing diffs (REVIEW)

### Writing (Phase 5: Ship & Learn)
- Call `mcp__forgetful__execute_forgetful_tool` with a store/write operation to permanently persist new architectural rules, conventions, or workarounds discovered during this session
- Store only insights that are cross-session valuable — per-conversation context belongs in Claude Code auto-memory (see "Memory backend boundary" below), not here

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

## Memory backend boundary

Forgetful and Claude Code auto-memory are orthogonal, not redundant:

- **Forgetful** = cross-session architectural memory (opt-in MCP). Use for: rules that apply across many sessions, decisions with rationale, named constraints, workarounds tied to specific libraries/APIs.
- **Claude Code auto-memory** at `~/.claude/projects/<project>/memory/` = per-project conversation memory (built-in, slug-indexed with typed frontmatter). Use for: user preferences, feedback corrections, project-specific facts, reference pointers.

Do not dual-write. Pick one per learning based on scope: cross-project → Forgetful; project-local → auto-memory.

### Three storage scopes (no dual-write within a scope)

| Scope | Location | Visibility | Gate |
|-------|----------|------------|------|
| machine | `~/.claude/projects/<project>/memory/` (Claude Code auto-memory) | private, per-machine | built-in |
| repo canonical | `.claude/knowledge/` (committed OKF files) | shared via git, PR-gated | human + PR review |
| repo derived-optional | each user's LOCAL Forgetful instance, synced from `.claude/knowledge/` | local only, rebuildable | opt-in |
| org read-only | org-hub frozen index + `.claude/org-hub.json` (committed descriptor; bodies via hash-pinned REVIEW lens) | org-wide via hub repo | hub codeowner review + onboarding HITL + sha256 pin |

**Retrieval tiers:**
- **Base tier (zero dependencies):** `session-start-hook.sh` injects `index.md` at session start (capped at 8192 bytes, fail-open, framed as untrusted reference data). Works with no MCP, no Forgetful.
- **Accelerator tier (semantic retrieval):** where a user has Forgetful connected locally, `scripts/knowledge-forgetful-map.sh` mirrors committed facts into it for `query_memory`-style lookup. Never required — absent Forgetful, the base tier works unchanged.

**Serena boundary:** Serena indexes **code symbols** (functions, classes, variables) — it does not provide semantic retrieval over prose in `.claude/knowledge/`. Semantic-at-scale comes from local Forgetful, not Serena.

**Org-hub boundary:** the org hub is the read-only upstream of this lineage — org-curated knowledge enters sessions only as the frozen index (session start) or hash-pinned bodies (REVIEW lens), never as instructions and never writable from a consumer session. Same trust ceiling as `.claude/knowledge/` injection.
