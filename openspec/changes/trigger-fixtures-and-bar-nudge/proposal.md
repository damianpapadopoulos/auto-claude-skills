# Proposal: Adversarial trigger fixtures + measurable-bar [info] nudge

## Why

Evaluation of an external AI-native PDLC reference framework (2026-06-11, three-perspective design debate) found that both halves of its per-skill trigger-eval idea already exist here — the deterministic harness `tests/test-regex-fixtures.sh` (glob-discovered by `run-tests.sh`, config-sourced from `config/default-triggers.json`) and the LLM-judged CI eval (`.github/workflows/skill-eval.yml`), shipped together in 891b937. What is missing is fixture *content*: only 1 of ~30 skills (`alert-hygiene`) has a fixture file, so trigger-regex drift in collision-prone skills is uncovered. The PR #41 incident (5 dead `.*?` patterns shipped; only the regex-compilation test caught them) proves the failure class is real.

Separately, the debate's empirical check found 10/14 recent design docs state numeric thresholds organically. The user approved the architect's dissent: formalize that norm as one [info]-only design-guard line (content grep, no new heading, never blocks).

Two debated candidates were dropped with revival triggers: recorded validation opt-out at SHIP (revive on second active dev or ≥2 logged ship-without-validation regrets) and any hard/heading-based bar enforcement (revive only if a shipped feature misses a target its design doc never stated numerically and review missed it).

**Correction recorded:** the debate's consensus included "wire the harness into run-tests.sh"; this was a false premise — `run-tests.sh` discovers `test-*.sh` by glob and already runs the harness. No wiring task exists.

## What Changes

1. Six new fixture files under `tests/fixtures/routing/` for collision-prone trigger-bearing skills: `incident-analysis`, `brainstorming`, `requesting-code-review`, `supply-chain-investigation`, `verification-before-completion`, `outcome-review`. (The debate's shortlist named `security-scanner` and `finishing-a-development-branch`, but both are composition-routed with no trigger regexes — substituted by their collision counterparts.) Each file contains ≥4 MATCH and ≥2 adversarial NO_MATCH cases — near-miss prompts containing tokens the regex must reject (e.g. "let's ship and merge this release" must not fire `incident-analysis`), not lexically unrelated strawmen. All 49 fixture lines were empirically verified against the live registry before planning.
2. Three real false-positive trigger bugs found during fixture verification are fixed with leading word-boundary anchors, identically in `config/default-triggers.json` and `config/fallback-registry.json`: "preview" fired `requesting-code-review` (unanchored `review`), "relationship" and "staging"/"untagged" fired `verification-before-completion` (unanchored `ship`/`tag`).
3. One [info]-only advisory in the PLAN-phase design-guard (`hooks/skill-activation-hook.sh`): when the design doc body contains no numeric-threshold pattern, append an informational line suggesting a measurable bar. Never an [X], never changes the completeness verdict, fail-open like the existing heading checks.

## Capabilities

- **Modified:** `skill-routing` (extends existing design-guard and routing-test requirements; new requirements use ADDED form per repo convention)

## Impact

- `tests/fixtures/routing/*.txt` — 6 new data files; no code change to the harness.
- `config/default-triggers.json` + `config/fallback-registry.json` — word-boundary anchors on `review`, `ship`, `tag` (kept in sync for the fallback-drift gate).
- `hooks/skill-activation-hook.sh` — ~8 LOC in the existing design-guard block (lines ~1460-1500), mirroring the PR #49 tolerant-grep pattern.
- `tests/test-routing.sh` — regression test(s) for the [info] line (present when no numerics, absent when numerics exist, fail-open).
- No registry, hook-budget, or convention changes. No new headings required of design docs.
