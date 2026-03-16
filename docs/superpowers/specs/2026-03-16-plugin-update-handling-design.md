# Design: Plugin Update Handling — Hybrid Discovery & Reconciliation

## Overview

Make auto-claude-skills resilient to partner plugin updates (additions, removals, renames, trigger changes) by unifying discovery, letting plugins declare their own routing metadata via SKILL.md frontmatter, and detecting/reconciling drift at session start.

## Motivation

auto-claude-skills routes prompts to skills from partner plugins (superpowers, frontend-design, etc.), but treats their routing metadata as something it owns — hardcoded in `default-triggers.json` and `session-start-hook.sh`. When a partner plugin renames, adds, or removes a skill, routing breaks silently:

- **Trigger drift:** `default-triggers.json` has triggers for a skill name that no longer exists.
- **Hardcoded official plugin map:** `session-start-hook.sh:129-131` has a 3-entry map for official plugins. New skills from those plugins are invisible without a code change.
- **Fallback registry staleness:** `fallback-registry.json` is manually regenerated and can diverge from reality.
- **Invisible updates:** When plugins update, nobody is told what changed or whether action is needed.

The router should adapt to plugins, not the other way around. Plugins are the system's primary value; auto-claude-skills is the routing layer.

## Approach: Hybrid — Discover + Merge with Plugin Hints

Works today with zero partner changes (graceful fallback). Plugins can opt-in to self-describing at their own pace. Eliminates hardcoded maps immediately. Clear migration path — as plugins add frontmatter, `default-triggers.json` entries can be removed.

## 1. SKILL.md Frontmatter Extension

### Schema

All routing fields are optional. Omitted fields fall back to `default-triggers.json`, then to generic defaults.

```yaml
---
name: skill-id                    # required (existing)
description: Human-readable text  # required (existing)
triggers:                         # regex patterns for prompt matching
  - "(pattern|one)"
  - "(pattern|two)"
role: process|domain|workflow     # routing slot
phase: DESIGN|PLAN|IMPLEMENT|REVIEW|SHIP|DEBUG
priority: 50                     # higher = evaluated first (typical: process 30-50, domain 10-25)
precedes:                        # skills that should follow
  - other-skill
requires:                        # prerequisite skills
  - prereq-skill
---
```

### Versioning

Add `frontmatter_schema_version: 1` to the registry output so we can evolve the schema without breaking older plugins. Unknown frontmatter fields are ignored (forward-compatible).

### Parsing Strategy

During discovery, extract frontmatter from all discovered SKILL.md files using a single `awk` pass over all file paths. Pipe the extracted YAML into one `jq` call for JSON conversion. For jq-less environments, skip frontmatter parsing entirely and use `default-triggers.json` as today.

### Performance

~30 skills × 1 `awk` multi-file pass ≈ 10-20ms + 1 `jq` batch parse ≈ 5ms. Well within the 200ms hook budget.

## 2. Unified Dynamic Discovery

### Current State (4 code paths)

1. **Superpowers** — scans versioned dirs, auto-selects latest semver
2. **Official plugins** — hardcoded 3-entry map (`frontend-design`, `claude-md-management`, `claude-code-setup`)
3. **Bundled skills** — scans `PLUGIN_ROOT/skills/*/SKILL.md`
4. **Unknown plugins** — scans all marketplaces, excluding known names

### New State (2 code paths)

1. **All external plugins** — single generic scanner:
   ```
   for each marketplace in ~/.claude/plugins/cache/*/
     for each plugin in marketplace/*/
       resolve version dir (semver sort if versioned, direct if not)
       scan skills/*/SKILL.md → extract name + frontmatter
       record: plugin_name, skill_name, invoke_path, frontmatter_metadata
   ```
2. **Bundled skills** — unchanged, scans `PLUGIN_ROOT/skills/*/SKILL.md`

### What This Eliminates

- Superpowers special-case code (~20 lines)
- Hardcoded official plugin map (~15 lines)
- "Exclude known names" logic in unknown plugin discovery (~25 lines)
- Adding a new official plugin requires zero code changes

### Version Resolution

All plugins use the same version resolution: if the plugin directory contains semver-named subdirectories, pick the latest via `sort -t. -k1,1n -k2,2n -k3,3n | tail -1`. If no versioned subdirectories, use the directory directly.

## 3. Three-Tier Merge Logic

### Priority Order

```
1. User overrides     (~/.claude/skill-config.json)  — highest priority
2. SKILL.md frontmatter  (plugin-declared)           — plugin's intent
3. default-triggers.json (auto-claude-skills curated) — fallback/patches
4. Generic defaults      (role:domain, priority:200)  — unknown skills
```

### Merge Algorithm (single jq call)

For each discovered skill:
1. Look up `default-triggers.json` entry by name → base fields
2. Overlay any frontmatter fields that are present (frontmatter wins for `triggers`, `role`, `phase`, `priority`, `precedes`, `requires`)
3. For skills not in `default-triggers.json`, build entry from frontmatter + generic defaults
4. Apply `skill-config.json` overrides on top (existing behavior, unchanged)

### Key Behavior

If superpowers' `brainstorming/SKILL.md` ships `triggers: ["(brainstorm|ideate)"]` and `default-triggers.json` also has triggers for `brainstorming`, the **frontmatter wins**. When superpowers refines its routing, it takes effect automatically next session. `default-triggers.json` only provides triggers for skills that don't declare their own.

### Migration Path

Initially most skills won't have frontmatter triggers — `default-triggers.json` fills in as today. As partner plugins adopt frontmatter, their entries in `default-triggers.json` become redundant. A warning flags when both sources exist for the same skill, signaling cleanup opportunity.

## 4. Self-Healing & User-Facing Actions

### Tier 1: Auto-Healed (No User Action)

| Situation | Auto-Action |
|-----------|-------------|
| Plugin adds a new skill with frontmatter | Discovered, routed, available next session |
| Plugin renames a skill with frontmatter | Old name disappears, new name appears — frontmatter is authoritative |
| Plugin removes a skill | Entry dropped from registry, orphaned `default-triggers.json` entry marked `available: false` silently |
| `default-triggers.json` has stale triggers for a skill that now ships frontmatter | Frontmatter wins automatically, redundant entry ignored |
| Fallback registry is stale | Auto-regenerated every session-start |

### Tier 2: User-Prompted (Session Start Output)

| Situation | What the User Sees |
|-----------|-------------------|
| Plugin renamed/removed a skill that the user has overrides for in `skill-config.json` | Warning: `"Your override for 'old-skill-name' no longer matches any installed skill. Remove it or update to 'new-skill-name'?"` |
| New unrouted skill discovered with no frontmatter and no `default-triggers.json` entry | Hint: `"New skill 'foo' discovered from plugin 'bar' but has no routing triggers. It won't activate until triggers are added — run /setup to configure."` |
| Multiple plugins provide a skill with the same name | Warning: `"Skill 'design-debate' found in both auto-claude-skills and user-skills. Using auto-claude-skills version. Override in skill-config.json if needed."` |

### Tier 3: Developer-Facing (auto-claude-skills Maintainer)

| Situation | What Happens |
|-----------|-------------|
| `default-triggers.json` entries fully covered by plugin frontmatter | `SKILL_EXPLAIN=1` output shows `"redundant"` entries for maintainer to prune |

### Key Principle

The registry always produces a working result (fail-open). Warnings and prompts are informational nudges, never blockers. The user only hears from the system when something affects their routing quality.

## 5. Update Detection & Reconciliation

### Mechanism

At session-start, after discovery but before the merge, compare current discovery results against the previous session's registry (`~/.claude/.skill-registry-cache.json`):

| Change Type | Detection | Example |
|-------------|-----------|---------|
| **Skill added** | In current, not in previous | `superpowers` shipped `new-workflow` |
| **Skill removed** | In previous, not in current | `superpowers` dropped `old-skill` |
| **Skill renamed** | Removed + added in same plugin, similar description | `brainstorming` → `ideation` |
| **Triggers changed** | Frontmatter triggers differ from previous frontmatter | Plugin refined its routing |
| **Plugin version changed** | Version dir differs from previous | `superpowers/5.0.2` → `5.1.0` |
| **Plugin added/removed** | Plugin in one set but not the other | User installed `feature-dev` |

### Changeset Actions

**Auto-actioned (silent):**
- New skill with frontmatter → routed, noted in changeset log
- Triggers changed via frontmatter → new triggers take effect
- Plugin version bumped, no skill changes → noted, no action

**User-surfaced (session-start output, only when changes detected):**
```
Plugin updates detected:
  superpowers 5.0.2 → 5.1.0:
    + new-skill (auto-routed via frontmatter)
    ~ brainstorming triggers updated (frontmatter overrides default-triggers)
    - old-skill removed (your skill-config.json override is now orphaned)
  feature-dev installed:
    + code-explorer, code-architect (auto-routed)
```

**Actionable prompts (only when user input needed):**
- Orphaned user overrides
- Skill name collisions after update

### Storage

The changeset is ephemeral — computed at session-start, surfaced, then discarded. The comparison baseline is the existing cache file from the previous session. No new persistent files needed.

### Performance

Single `jq` call comparing two JSON arrays by skill name. Both objects already in memory. Negligible within 200ms budget.

## 6. Phase Composition Resilience

### Problem

`phase_compositions` and `methodology_hints` in `default-triggers.json` reference skill names as strings. If a plugin renames a skill, these references break silently.

### Solution

Apply the reconciliation pattern from Section 5:

- During the diff step, after detecting renames/removals, scan `phase_compositions` and `methodology_hints` for references to removed skill names
- If a rename is detected (removed + added in same plugin), auto-patch the reference in the in-memory registry
- If a removal with no replacement, warn: `"Phase composition DESIGN references 'old-skill' which was removed from superpowers"`

### Why Not Plugin-Declared

Phase compositions orchestrate *across* plugins — they are inherently an auto-claude-skills concern. A plugin should not dictate the SDLC flow. Compositions stay in `default-triggers.json`, but become resilient to upstream name changes via reconciliation.

Methodology hints get the same treatment — stale references detected and warned, but hints remain centrally managed.

## 7. Fallback Registry Auto-Regeneration

### Current State

`fallback-registry.json` is committed to git, manually regenerated via `chore: regenerate fallback registry` commits.

### New Behavior

At the end of a successful session-start, write the merged registry to `config/fallback-registry.json` **only if** it differs from the existing file. This makes the fallback always reflect the last successful build.

### Git Handling

The file stays committed and tracked. Changes show up in `git status` as a modified file. The maintainer decides when to commit — this is intentional. It surfaces drift as a visible diff rather than hiding it. No auto-commit.

### Jq-Less Environments

Continue to use whatever `fallback-registry.json` is on disk. Since it is now regularly refreshed by jq-capable sessions, it stays reasonably current.

## 8. Frontmatter Schema Documentation

Ship `docs/skill-frontmatter-schema.md` as a contract for partner plugin authors. Contains:
- Field definitions, types, and defaults
- Examples (minimal, partial, and full frontmatter)
- Migration guide for existing plugins
- Version compatibility notes

## 9. CLAUDE.md Budget Fix

Update `CLAUDE.md` line 26 from `50ms hook budget` to `200ms hook budget` to match the actual relaxed budget from the changelog.

## Files Modified

| File | Change |
|------|--------|
| `hooks/session-start-hook.sh` | Unified discovery, frontmatter parsing, merge logic, reconciliation, fallback auto-regen |
| `config/default-triggers.json` | Add `frontmatter_schema_version` to registry output |
| `config/fallback-registry.json` | Auto-regenerated (content change, not structural) |
| `docs/skill-frontmatter-schema.md` | New — partner plugin contract |
| `CLAUDE.md` | Budget fix: 50ms → 200ms |
| `tests/test-registry.sh` | Tests for frontmatter merge, reconciliation, orphan detection |
| `tests/test-routing.sh` | Tests for frontmatter-sourced triggers taking precedence |

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Frontmatter parsing adds latency | Single `awk` + `jq` batch; measured within 200ms budget |
| Partner plugins ship bad triggers | `default-triggers.json` can override via `skill-config.json` pattern; user overrides always win |
| Rename detection false positives | Only flag renames when removed + added happen in the same plugin with matching description similarity; conservative matching |
| Breaking change in frontmatter schema | `frontmatter_schema_version` field enables migration logic; unknown fields ignored |
| Fallback registry diverges from default-triggers structure | Existing test `test_fallback_registry_skill_coverage` catches this; auto-regen reduces window |

## Success Criteria

1. A new superpowers skill with frontmatter triggers is routable next session with zero changes to auto-claude-skills
2. Removing a skill from superpowers produces a user-visible warning (not a silent failure)
3. The hardcoded official plugin map is eliminated
4. `fallback-registry.json` stays current without manual regeneration
5. All existing tests continue to pass
6. No regression in hook execution time (stays under 200ms)
