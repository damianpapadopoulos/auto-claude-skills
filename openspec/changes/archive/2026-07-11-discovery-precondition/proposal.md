## Why

PR #102 shipped a `discovery-audit-companion` DESIGN **hint** that routes ledger-less
new-feature asks to `product-discovery` before design. A 25-rep uptake eval in the #102
LEARN phase measured that hint at **0/5 uptake and 0/5 acknowledgment**; a hint-removed
control was identical, so its causal contribution was **zero**. Root cause: an advisory
"consider X" line cannot compete with the composition context's mandatory language
("brainstorming MUST INVOKE / [CURRENT] Step 1") — and the hint argues *against* the
current step ("do product-discovery FIRST"), so the mandatory channel wins categorically.

The validated fix (also eval'd in #102 LEARN: 5/5 uptake, 5/5 no-over-fire) is to move the
conditional **into** the channel the model already obeys — the composition step text — as
a PRECONDITION attached to the CURRENT step, rather than a competing side hint.

## What Changes

- Add an optional `precondition` field to a skill's registry entry
  (`config/default-triggers.json` + `config/fallback-registry.json`, in lockstep).
- `hooks/skill-activation-hook.sh` renders that field **only on the CURRENT composition
  step**, as one indented line directly under the step line. LATER/DONE steps and skills
  without the field render unchanged.
- Set `precondition` on `brainstorming` with the discovery-check text (the conditional is
  model-evaluated: "if a new feature/initiative and no discovery brief exists … invoke
  product-discovery FIRST, then return; skip for bugfixes/small changes or when a brief
  exists").
- Remove the dead `discovery-audit-companion` hint from both configs.

## Capabilities

### Modified Capabilities
- `pdlc-closed-loop`: the DISCOVER→DESIGN gate (route ledger-less new-feature asks to
  discovery) is now carried in the mandatory composition step text instead of an advisory
  hint. Mechanism cross-cuts `skill-routing` (composition rendering gains an optional
  per-step precondition line).

## Impact

- `config/default-triggers.json`, `config/fallback-registry.json` — new `precondition` on
  `brainstorming`; remove `discovery-audit-companion` hint entry.
- `hooks/skill-activation-hook.sh` — extend the composition batch-lookup + CURRENT-step
  rendering.
- Tests: deterministic routing render test (precondition present on CURRENT, absent
  elsewhere / when unset) + an uptake eval arm (the real acceptance bar, not presence).
- `CHANGELOG.md`.
- Out-of-scope (deferred with revival triggers): deterministic session-state suppression
  when `discovery_path` is set; `design-debate` scope; rung-2 walker-level chain re-anchor.
