# Unified Context Stack — Design Specification

**Date**: 2026-03-13
**Status**: Draft
**Author**: Damian Papadopoulos + Claude

## Problem

Coding agents suffer from "Agent Drift" — hallucinated parameters, outdated APIs, and zero institutional memory between sessions. The Superpowers SDLC provides structured phases (PLAN, IMPLEMENT, DEBUG, REVIEW, SHIP) but has no systematic mechanism for gathering trusted context or preserving learnings.

Meanwhile, four complementary tools exist that solve different facets of this problem:

| Tool | What it solves | Type |
|------|---------------|------|
| Context Hub (via Context7) | Curated, human-reviewed API docs | External Truth |
| Context7 (broad) | Live web-scraped library docs | External Truth (fallback) |
| Serena | LSP-powered dependency mapping and AST edits | Internal Truth |
| Forgetful Memory | Persistent architectural knowledge across sessions | Historical Truth |

No single tool covers all needs. The agent needs a **tiered retrieval strategy** that uses the best available tool for each capability dimension, degrades gracefully when tools are missing, and integrates into every SDLC phase without disrupting the existing skill routing architecture.

## Key Insight

Context7 already indexes Context Hub as a library (`/andrewyng/context-hub`, 6690 snippets, High reputation). This means an agent with only Context7 installed can query Context Hub's curated data by targeting `libraryId="/andrewyng/context-hub"` — no `chub` CLI required. This "Forced Prioritization Pattern" gives us high-trust documentation retrieval through the existing MCP tool with zero additional dependencies.

## Architecture: Hybrid B+A

The design separates **Detection** (deterministic, in the session-start hook) from **Orchestration** (structured decision tree, in a skill document) and **Routing** (phase compositions in the registry).

```
┌─────────────────────────────────────────────────────────┐
│                   Session Start Hook                     │
│  Probes environment → writes context_capabilities        │
│  to registry cache                                       │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Skill Registry Cache                         │
│  plugins[]: unified-context-stack (available: true/false) │
│  context_capabilities: {context7, chub, serena, ...}     │
└──────────────────────────┬──────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         PLAN phase   IMPLEMENT    DEBUG phase
         composition   phase comp   composition
              │            │            │
              └────────────┼────────────┘
                           ▼
┌─────────────────────────────────────────────────────────┐
│           Orchestrator Skill Document                     │
│  skills/unified-context-stack/SKILL.md                    │
│  Evaluates context_capabilities (injected by session-     │
│  start hook) → dispatches to tier + phase guidance        │
└─────────────────────────────────────────────────────────┘
```

### Critical Design Decision: Plugin, Not Skill

The unified-context-stack is registered as a **plugin** in the registry, NOT as a scored skill. This means:

- It **never enters the skill scoring pipeline** — no trigger matching, no role-cap competition
- It **never consumes a domain/workflow slot** — all 3 skill slots remain available for real skills (frontend-design, security-scanner, etc.)
- It appears in **phase composition entries** as a `PARALLEL` or `SEQUENCE` line alongside any selected skills
- It is **gated on capability availability**, not prompt keywords

This mirrors how `security-guidance` works: always active, infrastructure-level, composing silently with whatever skills are selected.

## Component 1: Capability Detection (Session-Start Hook)

The `session-start-hook.sh` gains a new detection block that runs after the registry is built. It probes the environment for each tool and writes a flat `context_capabilities` object into the registry cache.

### Detection Methods

| Tool | Detection Method | Key |
|------|-----------------|-----|
| Context7 | MCP tool names `resolve-library-id` / `get-library-docs` in plugin registry | `context7` |
| Context Hub CLI | `command -v chub` on `$PATH` | `context_hub_cli` |
| Context Hub (indexed) | Derived: `true` if `context7` is `true` | `context_hub_indexed` |
| Serena | MCP tool names `find_symbol` / `cross_reference` in plugin registry | `serena` |
| Forgetful Memory | Plugin name `forgetful` in plugin registry or `memory-search` skill available | `forgetful_memory` |

### Registry Cache Addition

```json
{
  "context_capabilities": {
    "context7": true,
    "context_hub_cli": false,
    "context_hub_indexed": true,
    "serena": false,
    "forgetful_memory": true
  }
}
```

**Binding rule**: `context_hub_indexed` is derived from `context7`. If Context7 is unavailable, the agent cannot access the Context Hub index, so both must be `false`.

```bash
if [ "$has_context7" = true ]; then
  context_hub_indexed=true
else
  context_hub_indexed=false
fi
```

### Plugin Available Flag

The `unified-context-stack` plugin's `available` flag is set to `true` if ANY capability in the stack is present. If all are `false`, the plugin is marked unavailable and all composition entries referencing it are suppressed.

**Insertion point in session-start-hook.sh**: The capability detection block runs AFTER the plugin discovery step (step 8b/8c, which sets `available` flags on all plugins based on directory existence in `~/.claude/plugins/cache/`). Since `unified-context-stack` is a virtual plugin (no cache directory), the standard discovery would set `available: false`. The detection block explicitly overrides this by mutating the plugin's `available` field in `PLUGINS_JSON` after discovery completes:

```bash
# After step 8c (plugin discovery), override for virtual plugins
if [ "$any_capability_present" = true ]; then
  PLUGINS_JSON="$(printf '%s' "$PLUGINS_JSON" | jq '
    map(if .name == "unified-context-stack" then .available = true else . end)
  ')"
fi
```

## Component 2: Orchestrator Skill Document

### File Structure

```
skills/unified-context-stack/
├── SKILL.md                    # Main skill — capability reader + phase dispatch
├── tiers/
│   ├── external-truth.md       # Curated docs retrieval decision tree
│   ├── internal-truth.md       # Blast-radius mapping decision tree
│   └── historical-truth.md     # Institutional memory decision tree
└── phases/
    ├── triage-and-plan.md      # Phase 1: Context gathering before planning
    ├── implementation.md       # Phase 2: Mid-implementation lookups
    ├── testing-and-debug.md    # Phase 3: Error resolution + live issue discovery
    ├── code-review.md          # Phase 4: Claim verification + dependency checks
    └── ship-and-learn.md       # Phase 5: Memory consolidation + annotations
```

### Tier Documents

Each tier defines a capability dimension with a strict order of operations.

#### External Truth (`tiers/external-truth.md`)

Capability: Fetch accurate API documentation.

```
Tier 1 (High Trust): IF context_hub_indexed = true
  → Use Context7 MCP: resolve-library-id first to confirm availability,
    then get-library-docs with libraryId="/andrewyng/context-hub"
  → IMPORTANT: Your query parameter should describe the specific API/library
    you need (e.g., "Stripe payment intents API" or "React Router v7 route
    configuration"), NOT "Context Hub." The libraryId handles targeting;
    the query handles specificity.
  → Curated, human-reviewed. Trust fully.

Tier 2 (Medium Trust): IF context7 = true AND Tier 1 returned no results
  → Use Context7 MCP with broad query (no library constraint)
  → Web-scraped. Verify method signatures before implementing.

Tier 3 (Low Trust): IF context_hub_cli = true AND Tiers 1+2 unavailable/empty
  → Execute: chub get <library> --lang <lang>
  → CLI fallback. Curated but requires shell access.

Tier 4 (Base): IF none of the above
  → Use WebSearch / WebFetch for documentation
  → Treat with high skepticism. Cross-reference multiple sources.
```

#### Internal Truth (`tiers/internal-truth.md`)

Capability: Understand local file dependencies and inject code safely.

```
Tier 1: IF serena = true
  → Use find_symbol / cross_reference for dependency mapping
  → Use insert_after_symbol for safe AST-level edits

Tier 2: IF serena = false
  → Degrade to Grep + Read for symbol reference discovery
  → WARNING: "Serena unavailable — proceed with caution on large file edits"
```

#### Historical Truth (`tiers/historical-truth.md`)

Capability: Retrieve and store project-specific rules and quirks.

```
Tier 1: IF forgetful_memory = true
  → Use memory-search to query past architectural decisions
  → Use memory-save to persist new learnings

Tier 2: IF forgetful_memory = false
  → Read CLAUDE.md, docs/architecture.md, .cursorrules
  → For Phase 5 (write path): append to docs/learnings.md as flat-file fallback
```

### Phase Documents

Each phase document composes the tiers for its SDLC moment.

#### Phase 1: Triage & Plan (`phases/triage-and-plan.md`)

Before writing the implementation plan:

1. **Historical Truth** → "Any past architectural constraints for this area?"
2. **External Truth** → "Fetch curated API docs for third-party services mentioned in the task"
3. **Internal Truth** → "Map blast radius of files the plan will touch"

#### Phase 2: Implementation (`phases/implementation.md`)

During file-by-file execution:

1. **Internal Truth** → Use Serena for safe AST-level code injection (or cautious Grep fallback)
2. **External Truth** → If the agent encounters an undocumented library not in the original plan, trigger tiered lookup mid-implementation

#### Phase 3: Testing & Debug (`phases/testing-and-debug.md`)

When errors occur:

1. **Historical Truth** → "Have we seen this exact error in a previous session?"
2. **External Truth** → If a third-party API throws unexpected errors, check Context Hub/Context7 for known issues, breaking changes, or recently discovered bugs

#### Phase 4: Code Review (`phases/code-review.md`)

When processing reviewer feedback:

1. **External Truth** → If a reviewer claims "wrong API parameter," verify against curated docs before accepting
2. **Internal Truth** → Check that a reviewer's suggested architectural change won't break downstream dependencies

#### Phase 5: Ship & Learn (`phases/ship-and-learn.md`)

Memory consolidation before session close:

```
Evaluate your available tools and execute the highest available tier:

IF forgetful_memory = true:
  → Execute memory-save to permanently store new architectural rules

IF context_hub_cli = true:
  → Execute chub annotate to record any third-party API quirks discovered

IF NEITHER are available:
  → Append findings to docs/learnings.md using standard file editing tools
```

## Component 3: The Bridge (Phase Compositions)

### Plugin Registration

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
  "phase_fit": ["PLAN", "IMPLEMENT", "DEBUG", "REVIEW", "SHIP"],
  "description": "Tiered context retrieval — curated docs (Context Hub via Context7), blast-radius mapping (Serena), institutional memory (Forgetful) with graceful degradation."
}
```

### Phase Composition Entries

These replace the individual Context7 composition entries in DESIGN, IMPLEMENT, and DEBUG, and add new entries for REVIEW and SHIP phases. Context7 is now one tier within the stack, not a standalone entry.

**PLAN phase:**
```json
{
  "plugin": "unified-context-stack",
  "use": "tiered context retrieval (external docs, blast-radius, memory)",
  "when": "installed AND any context_capability is true",
  "purpose": "Gather curated API docs, map dependencies, check institutional memory before planning"
}
```

**IMPLEMENT phase:**
```json
{
  "plugin": "unified-context-stack",
  "use": "tiered context retrieval (mid-flight library lookups)",
  "when": "installed AND any context_capability is true",
  "purpose": "Look up current API signatures and usage patterns during implementation"
}
```

**DEBUG phase:**
```json
{
  "plugin": "unified-context-stack",
  "use": "tiered context retrieval (past solutions, live issue discovery)",
  "when": "installed AND any context_capability is true",
  "purpose": "Check past solutions via memory, and live library issues via curated docs"
}
```

**REVIEW phase:**
```json
{
  "plugin": "unified-context-stack",
  "use": "tiered context retrieval (claim verification, dependency checks)",
  "when": "installed AND any context_capability is true",
  "purpose": "Verify reviewer claims against curated docs, check dependency impact"
}
```

**SHIP phase** (sequence, not parallel — must run before session closes):
```json
{
  "plugin": "unified-context-stack",
  "use": "memory consolidation (annotate + memory-save)",
  "when": "installed AND any context_capability is true",
  "purpose": "Consolidate learnings via chub annotate and/or memory-save before session close"
}
```

### Methodology Hint (Reinforcement)

A single methodology hint reinforces the context stack when the composition line alone may not be enough context for the model:

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

This replaces the existing `context7-docs` hint. The `plugin` field gates it on the stack being available.

### Emitted Output Example

Full 3-skill selection with context stack composing alongside:

```
SKILL ACTIVATION (3 skills | Build New + Domain + Workflow)

Process: brainstorming -> Skill(superpowers:brainstorming)
  Domain: frontend-design -> Skill(frontend-design:frontend-design)
Workflow: agent-team-execution -> Skill(auto-claude-skills:agent-team-execution)
Composition: DESIGN -> PLAN -> IMPLEMENT
  [CURRENT] Step 1: Skill(superpowers:brainstorming) -- Ask questions...
  PARALLEL: tiered context retrieval (external docs, blast-radius, memory)
    -> Gather curated API docs... [unified-context-stack]
  PARALLEL: agents:code-explorer -> Parallel codebase exploration [feature-dev]

Evaluate: **Phase: [DESIGN]** | brainstorming MUST INVOKE, frontend-design YES/NO
- CONTEXT STACK: Use the unified-context-stack for tiered documentation retrieval...
```

## Session-Start Hook Changes

### New Detection Block

Added after the registry merge step in `session-start-hook.sh`:

1. Check for Context7 MCP tools in plugin registry → set `context7`
2. Check `command -v chub` → set `context_hub_cli`
3. Derive `context_hub_indexed` from `context7`
4. Check for Serena MCP tools → set `serena`
5. Check for Forgetful Memory plugin → set `forgetful_memory`
6. Write `context_capabilities` object to registry cache
7. Set `unified-context-stack` plugin `available` flag to `true` if any capability is present

### Skill-Activation Hook Changes

**No code changes required to `skill-activation-hook.sh`.** The existing composition processing loop already handles plugin-based entries. The unified-context-stack composition entries use the standard `plugin` field and are gated by the plugin's `available` flag, which session-start set based on capabilities.

Registry data changes (replacing Context7 composition entries with unified-context-stack entries, and replacing the `context7-docs` methodology hint) are in `default-triggers.json` only.

### Delivering context_capabilities to the Model

The orchestrator skill document (SKILL.md) uses conditional logic (`IF context7 = true`, `IF serena = false`) that the model must evaluate at runtime. Since skill documents are loaded as static markdown, the model cannot read `~/.claude/.skill-registry-cache.json` directly.

**Solution**: The session-start hook injects a `CONTEXT_CAPABILITIES` summary into its `additionalContext` output, which persists in the model's conversation context for the entire session:

```
Context Stack: context7=true, context_hub_cli=false, context_hub_indexed=true, serena=false, forgetful_memory=true
```

This is a single line appended to the session-start greeting output. The SKILL.md tier documents reference these flags by name, and the model matches them against the injected summary to evaluate each tier's conditional.

## Graceful Degradation Matrix

| Installed Tools | External Truth | Internal Truth | Historical Truth |
|----------------|---------------|---------------|-----------------|
| All four | Context Hub via Context7 (Tier 1) | Serena AST (Tier 1) | Forgetful Memory (Tier 1) |
| Context7 only | Context Hub index → broad Context7 | Grep + Read (Tier 2) | CLAUDE.md / flat files (Tier 2) |
| chub CLI only | chub get (Tier 3) | Grep + Read (Tier 2) | CLAUDE.md / flat files (Tier 2) |
| Serena + Forgetful | WebSearch (Tier 4) | Serena AST (Tier 1) | Forgetful Memory (Tier 1) |
| None | WebSearch (Tier 4) | Grep + Read (Tier 2) | CLAUDE.md / flat files (Tier 2) |

## What This Design Does NOT Do

- Does not modify any upstream Superpowers skill files
- Does not change the skill scoring algorithm or role-cap system
- Does not require all four tools to be installed
- Does not add new hook event types
- Does not change the composition output format

## Testing Strategy

1. **Registry tests**: Verify `context_capabilities` detection for all tool combinations
2. **Composition tests**: Verify PARALLEL lines emit correctly per phase when plugin is available/unavailable
3. **Hint tests**: Verify methodology hint fires when triggers match and suppresses when skill-related
4. **Degradation tests**: Verify each tier falls through correctly when higher tiers are unavailable
5. **Integration test**: Full SDLC walkthrough with partial stack installed

## Implementation Order

1. Session-start hook: capability detection + registry cache update
2. Registry: plugin entry + phase composition entries + methodology hint
3. Skill document: SKILL.md + tier documents + phase documents
4. Tests: registry, composition, hint, degradation
5. Documentation: README update, setup command update
