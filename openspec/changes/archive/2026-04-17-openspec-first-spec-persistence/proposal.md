## Why
In multi-user repos, `docs/plans/*-design.md` is gitignored, making in-progress design intent invisible to teammates until PR landing. Decision records are retrospective only (created at SHIP time by openspec-ship), providing no durable "why did we pick X" trail. No CI-enforceable spec contract exists during development.

## What Changes
Introduce a `spec-driven` preset that redirects DESIGN/PLAN artifact creation from gitignored `docs/plans/` to committed `openspec/changes/<feature>/` folders. The session-start hook mutates phase composition hints when the preset's `openspec_first` flag is active. `openspec-ship` becomes idempotent: validates and syncs an existing change folder at SHIP time, or creates retrospectively if no upfront change exists. Default mode (no preset) is unchanged.

## Capabilities

### Modified Capabilities
- `skill-routing`: New preset schema field `openspec_first`. Session-start hook rewrites DESIGN and PLAN phase composition hints when active.
- `auto-claude-skills`: New `spec-driven` preset file with `openspec_first: true`. CLAUDE.md documents both modes.

## Impact
- `config/presets/spec-driven.json`: New preset file
- `hooks/session-start-hook.sh`: Step 6c (30 lines) mutates DEFAULT_JSON's phase_compositions before Step 8 extraction
- `skills/openspec-ship/SKILL.md`: Step 3 pre-flight check, new-capability warning
- `skills/design-debate/SKILL.md`: Dual-mode output template (Spec-driven + Solo)
- `CLAUDE.md`: New "Spec Persistence Modes" section
- Tests: 6 preset assertions, 4 registry mutation assertions, 8 design-debate content assertions, 5 openspec-ship content assertions, 12 e2e flow assertions (35 new assertions total)
- Backward compatibility: default mode (no preset) is byte-identical to prior behavior; existing `docs/plans/` artifacts are not migrated
