# SKILL.md Frontmatter Schema (v1)

## Overview

Skills can declare routing metadata in their SKILL.md frontmatter. This allows plugins to control how their skills are routed without requiring changes to auto-claude-skills' `default-triggers.json`.

All routing fields are optional. Omitted fields fall back to `default-triggers.json` if the skill is listed there, then to generic defaults.

## Schema

```yaml
---
name: skill-id                    # REQUIRED — unique skill identifier
description: Human-readable text  # REQUIRED — used for display and rename detection
triggers:                         # Optional — regex patterns for prompt matching
  - "(pattern|one)"
  - "(pattern|two)"
role: process                     # Optional — routing slot: process, domain, or workflow
phase: DESIGN                     # Optional — SDLC phase: DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG
priority: 50                      # Optional — higher = evaluated first (default: 200)
precedes:                         # Optional — skills that should follow this one
  - other-skill
requires:                         # Optional — prerequisite skills
  - prereq-skill
---
```

## Priority Order

When multiple sources define routing metadata for a skill:

1. **User overrides** (`~/.claude/skill-config.json`) — highest priority
2. **SKILL.md frontmatter** — plugin's declared intent
3. **default-triggers.json** — auto-claude-skills curated fallback
4. **Generic defaults** — role: domain, priority: 200, empty triggers

## Examples

### Minimal (no routing — uses defaults)

```yaml
---
name: my-skill
description: Does something useful
---
```

### Partial (triggers only)

```yaml
---
name: my-skill
description: Does something useful
triggers:
  - "(my-keyword|my-pattern)"
---
```

### Full (all routing fields)

```yaml
---
name: my-skill
description: Does something useful
triggers:
  - "(my-keyword|my-pattern)"
  - "(another|pattern)"
role: domain
phase: IMPLEMENT
priority: 25
precedes:
  - verification-before-completion
requires:
  - writing-plans
---
```

## Constraints

- Frontmatter must use flat key-value pairs and simple YAML lists only. No nested objects.
- Unknown fields are silently ignored (forward-compatible).
- The `name` and `description` fields are not used for routing — they are metadata only.
- If frontmatter is malformed (missing closing `---`, invalid syntax), the parser falls back to `default-triggers.json` for that skill.

## Compatibility

- Schema version: 1 (tracked in registry as `frontmatter_schema_version`)
- Backward compatible: skills without routing frontmatter continue to work exactly as before
- Forward compatible: unknown fields are ignored, so newer schemas work with older parsers
