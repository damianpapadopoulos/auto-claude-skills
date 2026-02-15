# auto-claude-skills v2.0 Architecture Design

**Date**: 2026-02-15
**Status**: Approved
**Scope**: Full rethink — config-driven core with smart defaults
**Audience**: Broad developer audience

## Philosophy

"Claude IS the classifier" — the hook is a fast pre-filter that narrows possibilities, then Claude makes the final routing decision with full conversation context. No separate LLM calls, no external APIs.

## 1. Skill Registry & Dynamic Discovery

Replace the hardcoded `skill_path()` case statement with an auto-generated `skills-registry.json`.

### SessionStart scan sources

1. `~/.claude/plugins/cache/*/` — all installed plugins with skills
2. `~/.claude/skills/*/SKILL.md` — user-installed standalone skills
3. Built-in defaults shipped with auto-claude-skills

### Registry entry format

```json
{
  "name": "brainstorming",
  "source": "superpowers",
  "role": "process",
  "invoke": "Skill(superpowers:brainstorming)",
  "phase": ["DESIGN"],
  "triggers": ["build", "create", "add", "design", "new"],
  "precedes": ["writing-plans"],
  "description": "Explore requirements before implementation"
}
```

### Trigger definitions

Ship as `config/default-triggers.json` — the curated starter pack. Users can override with `~/.claude/skill-config.json`.

### Caching

Registry cached to `~/.claude/.skill-registry-cache.json` so UserPromptSubmit reads a file, not re-scans.

## 2. Routing Engine Redesign

Replace 8 hardcoded regex blocks with a generic matcher that reads trigger patterns from the registry.

### Matching

1. Iterate registry entries, test each skill's triggers against the lowercased prompt.
2. Collect all matches with priority scores.

### Scoring

- Exact keyword match: score 3
- Partial/substring match: score 1
- Phase-aligned: +2 bonus
- Result: ranked list, not first-match-wins

### Skill roles & category caps

| Role | Behavior | Cap | Examples |
|------|----------|-----|---------|
| **Process** | Drives the current phase. Sequenced by phase order. | 1 | brainstorming, writing-plans, TDD, debugging |
| **Domain** | Specialized knowledge. Active alongside any process skill. Phase-independent. | 2 | frontend-design, security-scanner, doc-coauthoring |
| **Workflow** | Lifecycle actions. Triggered by specific moments. | 1 | finishing-branch, dispatching-parallel-agents |

Maximum 3 skills suggested per prompt (configurable).

### Blocklist stays

Greeting/chat detection short-circuits before any matching. Simple, fast, proven.

## 3. Context Injection

Adaptive output scaled to match confidence and count.

### Three injection tiers

**Zero skills matched** (dev prompt, no triggers):
```
SKILL ACTIVATION (0 skills | phase checkpoint only)

Phase: assess current phase (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)
and consider whether any installed skill applies.
```

**1-2 skills, strong match**:
```
SKILL ACTIVATION (2 skills | Fix Bug)

Strong: systematic-debugging -> Skill(superpowers:systematic-debugging)
Weak: test-driven-development -> Skill(superpowers:test-driven-development)

Evaluate each: **Phase: [PHASE]** | skill1 YES/NO, skill2 YES/NO
```

**3 skills or mixed confidence**: Full format with skills grouped by confidence tier.

### Phase map at session start

Inject the DESIGN->PLAN->IMPLEMENT->REVIEW->SHIP->DEBUG map once at SessionStart. Per-prompt injection only references "assess current phase."

### Invocation hints inline

Include the exact `Skill(...)` or `Read ...` call in the context. Claude doesn't have to figure out how to invoke.

### Visible evaluation line stays mandatory

`**Phase: X** | skill1 YES/NO` format from v1.2.0 is retained.

## 4. Test Harness

Lightweight bash test framework validating all deterministic parts of the system.

### Test runner

`tests/run-tests.sh` — no dependencies beyond bash and jq. Target: <5 seconds.

### Test categories

**Registry tests** (`tests/test-registry.sh`):
- Scan finds skills from all three sources
- Cache file is valid JSON
- Missing plugin dirs don't cause errors
- Duplicate skills handled

**Routing tests** (`tests/test-routing.sh`):
- Feed prompts, assert expected skill selections:
  ```bash
  assert_matches "fix the login bug"        "systematic-debugging"
  assert_matches "build a new API endpoint"  "brainstorming"
  assert_matches "hey how are you"           ""
  ```
- Test scoring: "build a React component" ranks frontend-design higher
- Test category caps: never more than 3 skills

**Context injection tests** (`tests/test-context.sh`):
- 0 skills -> minimal output
- 1-2 strong matches -> compact format
- 3+ matches -> full format
- Invocation hints syntactically correct

**Install/uninstall tests** (`tests/test-install.sh`):
- Install into temp dir, verify files
- Uninstall, verify clean removal
- Idempotent install

### Test isolation

Each test creates a temp directory with mock plugin caches. No dependency on actual installed skills.

## 5. Multi-Skill Orchestration

Skills declare relationships. Context injection includes a sequenced execution plan, not a flat list.

### Composition model

**Process skills drive.** One active at a time. Selected by phase + trigger match.

**Domain skills inform.** Active alongside whatever process skill is running. Phase-independent. Multiple can be co-active.

**Workflow skills are standalone.** Fire on specific trigger conditions.

### Orchestrated context output

```
SKILL ACTIVATION (3 skills | Build Dashboard)

Process: brainstorming -> Skill(superpowers:brainstorming)
  INFORMED BY: frontend-design -> Skill(frontend-design:frontend-design)
  INFORMED BY: security-scanner -> Read ~/.claude/skills/security-scanner/SKILL.md

Invoke brainstorming as the driving skill.
Invoke frontend-design and security-scanner to provide domain guidance.

Evaluate: **Phase: [PHASE]** | brainstorming YES/NO, frontend-design YES/NO, security-scanner YES/NO
```

### Composition keywords

- `INFORMED BY` — domain skill provides context within the process skill's workflow
- `THEN` — sequential process skill handoff (e.g., brainstorming THEN writing-plans)
- `WITH` — co-active skills in the same phase

### Relationship metadata

```json
{
  "precedes": ["writing-plans"],
  "requires": ["writing-plans"],
  "alongside": ["frontend-design"]
}
```

- `precedes` — invoke me before these
- `requires` — these should have run earlier in the session
- `alongside` — can run in parallel/same phase

### Phase-skip detection

Applies to process skills only. If session is past DESIGN phase, brainstorming gets skipped. Domain skills are never skipped by phase.

## 6. Error Handling & Graceful Degradation

Principle: never silently swallow a problem, but never block the user either.

### Registry build failures (SessionStart)

| Failure | Behavior |
|---------|----------|
| Plugin cache dir missing | Skip source, log warning in registry |
| jq not installed | Fall back to bundled static registry |
| Malformed plugin manifest | Skip that plugin, include warning |
| Timeout (>10s) | Use stale cache or static fallback |

Registry includes `"warnings": []` array. Empty = clean.

### Routing failures (UserPromptSubmit)

| Failure | Behavior |
|---------|----------|
| Registry cache missing | Rebuild on the fly (~200ms), or static fallback |
| Invalid JSON cache | Delete, rebuild, or static fallback |
| Hook timeout approaching | Emit matches found so far |

### Missing skills surfaced

```
INFORMED BY: security-scanner -> Read ~/.claude/skills/security-scanner/SKILL.md
  (not installed — run /setup to install, or skip)
```

### Startup health check

```
SessionStart: skill registry built (14 skills from 3 sources, 0 warnings)
```

### Static fallback registry

`config/fallback-registry.json` — hardcoded minimal registry with core skills. Used when dynamic discovery completely fails.

## 7. User Configuration

Single optional config file: `~/.claude/skill-config.json`.

### Format

```json
{
  "overrides": {
    "brainstorming": {
      "triggers": ["+prototype", "+spike", "-design"],
      "enabled": true
    },
    "security-scanner": {
      "enabled": false
    }
  },
  "custom_skills": [
    {
      "name": "my-team-conventions",
      "role": "domain",
      "invoke": "Read ~/.claude/skills/team-conventions/SKILL.md",
      "triggers": ["review", "refactor", "new file"],
      "description": "Team-specific coding standards"
    }
  ],
  "settings": {
    "max_suggestions": 3,
    "verbosity": "normal"
  }
}
```

### Trigger override syntax

- `"+keyword"` — add to existing defaults
- `"-keyword"` — remove from defaults
- `"keyword"` (no prefix) — replace all defaults

### Settings

- `max_suggestions` — cap on total skills per prompt (default 3)
- `verbosity` — `"minimal"` | `"normal"` | `"verbose"`

### Merge order

static fallback -> dynamic discovery -> starter pack triggers -> user config overrides

### Zero-config by default

The entire config file is optional. No config = full curated experience.

## Key Files in v2.0

| File | Purpose |
|------|---------|
| `hooks/skill-activation-hook.sh` | Generic routing engine (reads registry) |
| `hooks/session-start-hook.sh` | Registry builder + health check |
| `config/default-triggers.json` | Starter pack trigger definitions |
| `config/fallback-registry.json` | Static fallback for degraded environments |
| `tests/run-tests.sh` | Test runner |
| `tests/test-registry.sh` | Registry build tests |
| `tests/test-routing.sh` | Prompt->skill matching tests |
| `tests/test-context.sh` | Context injection format tests |
| `tests/test-install.sh` | Install/uninstall tests |
| `~/.claude/skill-config.json` | Optional user overrides (not shipped) |
| `~/.claude/.skill-registry-cache.json` | Generated at session start |

## Backwards Compatibility

v1.x users get the new behavior automatically on update. No migration needed — the registry builder discovers the same skills the hardcoded paths did.
