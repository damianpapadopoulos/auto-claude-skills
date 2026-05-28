## Why

The activation hook's "full" injection tier (prompt 1, 3+ skills) prepended a Step-1/2/3 scaffold plus an 8-row phase-guide table in front of the user's request. A deterministic measurement (`tests/measure-injection-size.sh`) showed this costs ~828 tokens, of which ~217 (26%) is removable scaffold/guide boilerplate. Beyond the token cost, the boilerplate dilutes signal-to-noise on the most important prompt of a session (the opener), competing with the user's actual request for the model's attention.

## What Changes

The lean rendering becomes the production DEFAULT for the prompt-1 / 3+-skill tier: the Step-1/2/3 scaffold and phase-guide table are dropped, while every compliance-carrying element is retained (skill lines, `MUST INVOKE` markers, `Skill(...)` invocations, the "You MUST print a brief evaluation" directive). `SKILL_VERBOSE=1` restores the full verbose tier as an opt-in / rollback hatch. Routing decisions are unchanged — the trim is purely in the display layer downstream of scoring/selection.

## Capabilities

### Modified Capabilities
- `skill-routing`: the prompt-1/3+-skill injection tier renders lean by default; verbose is opt-in via `SKILL_VERBOSE`.

## Impact

- `hooks/skill-activation-hook.sh` — `_format_output()` prompt-1/3+-skill branch (default-branch swap + `SKILL_VERBOSE` gate).
- `tests/test-routing.sh`, `tests/test-context.sh` — assertions re-pointed to the lean default + verbose-hatch behavior.
- `tests/measure-injection-size.sh` — new deterministic measurement script.
- No change to routing scores, skill selection, role caps, or composition-chain advancement. Default production behavior under `SKILL_VERBOSE=1` is byte-identical to the prior full tier.
