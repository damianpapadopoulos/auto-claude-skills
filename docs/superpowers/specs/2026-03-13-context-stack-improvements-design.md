# Unified Context Stack Improvements — Design Specification

**Date**: 2026-03-13
**Status**: Draft
**Author**: Damian Papadopoulos + Claude
**Predecessor**: `2026-03-13-unified-context-stack-design.md` (original implementation)

## Problem

The unified-context-stack was implemented as a plugin with tier/phase documents, capability detection at session-start, composition hints per SDLC phase, and a methodology hint on library keywords. Five gaps reduce its effectiveness in practice:

| # | Gap | Impact |
|---|-----|--------|
| 1 | `context_hub_indexed` is always derived from `context7` (identical value), suggesting curated docs are indexed when only broad web-scraped docs are guaranteed | Model attempts Tier 1 (curated) when only Tier 2 (web-scraped) may be available |
| 2 | Phase docs not linked from hook output | Model must discover phase guidance independently — often doesn't |
| 3 | No conditional fallback in phase docs | Docs say "Use Serena" with no guidance when Serena is unavailable |
| 4 | Memory consolidation not enforced | Learnings lost between sessions |
| 5 | Advisory-only composition hints | Model may ignore hints under context window pressure |

## Design Decisions & Alternatives Considered

### Plugin-only, no skill registration

The unified-context-stack remains a **plugin** — it never enters the skill scoring pipeline, never consumes a role-cap slot (max 1 process, 2 domain, 1 workflow). Gap 5 (advisory-only) is addressed by making the advisory output more actionable, not by adding routing infrastructure.

**Alternative rejected — infrastructure role**: Adding a new `role: "infrastructure"` that bypasses role caps would require auditing ~300 lines of scoring logic across `_select_by_role_caps`, `_score_skills`, and `_walk_composition_chain`. The benefit is marginal because composition PARALLEL lines and methodology hints already fire reliably (proven by tests).

### No Serena lifecycle detection

Binary `serena=true/false` is sufficient. No staleness signals, no index age metadata.

**Why**: (a) Can't call MCP tools from bash — would require fragile filesystem probing of `.serena/index`. (b) Index age without change-delta is meaningless — 2h-old index is fine if nothing changed. (c) The model cannot re-index Serena, so the signal creates "learned helplessness" — hedging without actionable recourse. (d) The Internal Truth tier cascade already handles stale results implicitly (wrong Serena results → fall through to Grep).

### No PreToolUse commit hook for memory consolidation

Memory consolidation uses advisory red flags + pull-based next-session checking, not a PreToolUse hook.

**Why**: A PreToolUse hook on `git commit` misses: terminal commits, `/commit` skill invocations, sessions that end without committing. Net enforcement rate estimated at ~15%. The pull-based approach (session-start checks for a consolidation marker) is more robust because session-start always runs.

### Activation hook must not grow

All new logic goes in session-start output or static content. The activation hook (`skill-activation-hook.sh`) is already near the 50ms budget with ~10 jq forks. No code changes to the activation hook. No exceptions.

### 50ms budget defense

The activation hook is explicitly not modified. All capability detection runs in session-start (no time budget). The activation hook only reads cached values from the registry. This is a hard architectural constraint.

## Change 1: Honest Capability Signaling

**Rename `context_hub_indexed` → `context_hub_available`** in session-start hook and output.

The flag means "Context7 is installed, so Context Hub is *reachable*" — not "Context Hub has indexed docs for your specific library." The tier cascade handles miss cases (Tier 1 returns no results → fall to Tier 2).

Add a note to `external-truth.md` Tier 1: "This flag indicates Context Hub is reachable, not that it has docs for your specific library. If `resolve-library-id` returns no match, fall through to Tier 2 immediately."

**Files**: `hooks/session-start-hook.sh` (~2 lines), `skills/unified-context-stack/tiers/external-truth.md` (~2 lines), `skills/unified-context-stack/SKILL.md` (update capability table), `config/fallback-registry.json` (regenerate), `tests/test-context.sh` (update assertions), `tests/test-registry.sh` (update assertions)

## Change 2: Phase Document Linking

**Add a phase guidance line to session-start output.**

Current output:
```
Context Stack: context7=true, context_hub_cli=false, context_hub_indexed=true, serena=false, forgetful_memory=false
```

New output:
```
Context Stack: context7=true, context_hub_cli=false, context_hub_available=true, serena=false, forgetful_memory=false
Context guidance per phase: triage-and-plan.md | implementation.md | testing-and-debug.md | code-review.md | ship-and-learn.md (in skills/unified-context-stack/phases/)
```

The model gets a concrete path to navigate when the PARALLEL composition hint fires. No activation hook changes.

**Files**: `hooks/session-start-hook.sh` (~5 lines), `tests/test-context.sh` (assert new line)

## Change 3: Conditional Fallbacks in Phase Documents

**Add inline capability-aware instructions to each phase document.**

Compact format — one line per capability state, no IF/ELSE nesting:

```markdown
### 1. Internal Truth (Primary)
For each file modification, verify current symbol locations:
- **serena=true**: Use find_symbol / cross_reference for dependency mapping
- **serena=false**: Use Grep to find references, Read to verify context. Extra caution on large files and renames.
```

The model matches directly against the `Context Stack:` flags in context. Same pattern for External Truth and Historical Truth across all 5 phase docs.

Phase documents map to Superpowers SDLC phases:

| Phase Doc | Superpowers Phase | Relevant when active |
|-----------|-------------------|---------------------|
| `triage-and-plan.md` | DESIGN, PLAN | brainstorming (DESIGN), writing-plans (PLAN) — spans two phases |
| `implementation.md` | IMPLEMENT | executing-plans, subagent-driven-development |
| `testing-and-debug.md` | DEBUG | systematic-debugging |
| `code-review.md` | REVIEW | requesting-code-review, receiving-code-review |
| `ship-and-learn.md` | SHIP | verification-before-completion, finishing-a-development-branch |

**Files**: All 5 phase docs (~30 lines total across all truth dimensions)

## Change 4: Memory Consolidation Enforcement

**Two advisory layers:**

### Layer 1: SHIP phase gate in phase document

Add a bold requirement block to `ship-and-learn.md`:

```markdown
**REQUIRED before completing session:** If you discovered any architectural rules, API quirks,
or project conventions during this session, you MUST consolidate them using the highest
available tier below before claiming the work is done. After consolidation, write the marker:
`touch ~/.claude/.context-stack-consolidated-{project-hash}`
```

This is static content in the phase document — read by the model when the SHIP composition fires. No activation hook changes needed. The instruction lives alongside the existing tier guidance in the same file.

Note: The red flag list in `skill-activation-hook.sh` is hard-coded, not registry-driven. Adding to it would require an activation hook code change, which violates our architectural constraint. The phase document approach achieves the same effect through the existing composition PARALLEL/SEQUENCE mechanism.

### Layer 2: Pull-based next-session check

At session-start, check for a consolidation marker file (`~/.claude/.context-stack-consolidated-{project-hash}`). The project hash is computed as `$(printf '%s' "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" | md5)` — using the git root for repos or the working directory for non-repos.

If the marker is missing or older than the last git commit (compared via `stat` epoch timestamps — using `stat -f %m` on macOS with `stat -c %Y` fallback for Linux):

```
Context Stack: Previous session may have unconsolidated learnings. Consider reviewing recent changes.
```

The model writes the marker during SHIP phase consolidation (`touch` command). Session-start reads it (`stat`). Cheap, robust, catches skipped consolidation.

**Files**: `hooks/session-start-hook.sh` (~10 lines), `skills/unified-context-stack/phases/ship-and-learn.md` (~4 lines), `tests/test-context.sh` (test marker)

## Change 5: Strengthened Methodology Hint

**Append phase doc pointer to the existing hint text** in `default-triggers.json`:

```
"hint": "CONTEXT STACK: Use the unified-context-stack for tiered documentation retrieval. Query Context Hub via Context7 (libraryId=/andrewyng/context-hub) first for curated docs, then fall back to broad Context7, then chub CLI, then web search. Read the phase document for your current SDLC phase from the unified-context-stack skill (paths listed in the Context Stack session-start output)."
```

**Files**: `config/default-triggers.json` (~1 line)

## Known Limitations

1. `context_hub_available` may report `true` when Context Hub has no docs for the user's specific library — the tier cascade handles this, but the first query is wasted
2. Memory consolidation depends on the model following advisory guidance — no hard enforcement mechanism
3. Phase documents show both capability states (available/unavailable) — the model must match against the `Context Stack:` flags, adding minor cognitive load
4. The hook cannot verify whether Serena's index is current for the active project — binary presence detection only
5. Consolidation marker is per-project (hashed path) — correct project must be detected at session-start

## Summary

| Change | Lines | Files |
|--------|-------|-------|
| Honest capability signaling | ~8 | 6 (`session-start-hook.sh`, `external-truth.md`, `SKILL.md`, `fallback-registry.json`, `test-context.sh`, `test-registry.sh`) |
| Phase document linking | ~5 | 2 (`session-start-hook.sh`, `test-context.sh`) |
| Conditional fallbacks in phase docs | ~30 | 5 (all phase docs) |
| Memory consolidation enforcement | ~14 | 2 (`session-start-hook.sh`, `ship-and-learn.md`) + tests |
| Strengthened hint text | ~1 | 1 (`default-triggers.json`) |
| **Total** | **~58** | **11 unique** |

No new hooks. No new role types. No activation hook code changes. All improvements are to session-start output, static content, and registry data.
