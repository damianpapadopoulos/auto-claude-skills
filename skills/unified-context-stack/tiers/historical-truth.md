# Historical Truth — Institutional Memory

Capability: Retrieve and store project-specific rules, decisions, and quirks across sessions.

## Tier 1: Forgetful Memory

**Condition:** `forgetful_memory = true`

### Reading (all phases)
- Use `discover_forgetful_tools` to list available memory operations, then `execute_forgetful_tool` to query past architectural decisions
- Browse related context by executing the exploration tool discovered above

### Writing (Phase 5: Ship & Learn)
- Use `execute_forgetful_tool` to permanently store new architectural rules discovered during this session

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
