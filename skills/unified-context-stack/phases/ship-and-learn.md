# Phase 5: Ship & Learn

Before completing the session, consolidate what was learned.

## REQUIRED Before Memory Consolidation: As-Built Documentation

If the session produced working code from a Superpowers plan, generate permanent "as-built" documentation before consolidating learnings:

**Tier 1: OpenSpec CLI** (`command -v openspec` succeeds)
- Execute the `openspec-ship` skill to create a retrospective change folder under `openspec/changes/<feature>/`
- Use `/opsx:propose` (default profile) to scaffold and populate with schema-native templates
- Run `openspec validate <feature>` to verify the change folder
- Update `CHANGELOG.md` under `[Unreleased]`
- Use `/opsx:archive` with delta-spec sync prompt: sync deltas to canonical `openspec/specs/<capability>/spec.md`, then move to archive

**Tier 2: Claude-Native Fallback** (OpenSpec CLI not available)
- Generate the same artifact contract using the templates in the `openspec-ship` skill
- Same change-folder structure, same filenames, same required section headings, compatible content
- Manually move change folder to `openspec/changes/archive/`. Create canonical spec only if none exists; skip canonical update with warning if one already exists

**Skip Condition:** If the session was debugging, reviewing, or performing non-feature work (no Superpowers plan was executed), skip this step entirely.

**REQUIRED before completing session:** If you discovered any architectural rules, API quirks, or project conventions during this session, you MUST consolidate them using the highest available tier below before claiming the work is done. After consolidation, write the marker:

```bash
touch ~/.claude/.context-stack-consolidated-$(printf '%s' "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" | shasum | cut -d' ' -f1)
```

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
