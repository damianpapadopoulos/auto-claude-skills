# Proposal: Local-Adjustability Hint

## Why

Users can already tune routing locally (`~/.claude/skill-config.json` per-skill overrides, presets, enable/disable), but nothing surfaces this at the moment it matters. The plugin already measures the relevant friction — the zero-match counter and log — and session-start already computes the previous session's zero-match count and total prompts. Silent routing friction currently converts to nothing; it should convert to discoverability of the existing override mechanism.

## What Changes

One evidence-gated advisory line in the session-start banner, emitted only when the *previous* session showed real routing friction:

- Fire condition: previous session had ≥5 zero-matches AND ≥8 total prompts AND a zero-match rate ≥30% — rate-based, so long conversational sessions (legitimately unrouted prompts) do not false-fire.
- Suppressors: a 7-day cooldown marker (`~/.claude/.skill-adjustability-hint-last`), and any existing per-skill overrides in `skill-config.json` (the user has already found the mechanism; jq absent → treated as no overrides, hint still eligible).
- Content: one line naming the miss rate, pointing to `~/.claude/skill-config.json`, the zero-match log path, and `SKILL_EXPLAIN=1`.
- Fail-open: any read/parse/arithmetic failure suppresses the hint and never disturbs the banner.

## Capabilities

### Modified
- `skill-routing` — adds routing-friction discoverability (evidence-gated local-override hint) to the session-start surface.

### Added
- none

## Impact

- `hooks/session-start-hook.sh` (one guarded block after the existing `_PREV_ZM`/`_PREV_TOTAL` computation; new cooldown marker file)
- Session-start test suite (new deterministic cases)
- `CHANGELOG.md`
- Not: `hooks/skill-activation-hook.sh` (zero-match path stays silent), `config/` (no trigger changes), push gates, upstream-contribution flows (parked pending a second user)
