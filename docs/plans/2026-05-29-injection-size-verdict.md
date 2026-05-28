# Injection-Size Measurement — Verdict (Phase 0)

**Date:** 2026-05-29
**Method:** `tests/measure-injection-size.sh` — deterministic byte/token diff of full vs lean activation-hook injection on a depth-1, 3+-skill prompt, against the **real** registry built from repo config in a temp HOME. No model invoked. Result reproduced identically across 3 runs.

## Measured

- Prompt: `build a secure frontend component and review it for security`
- Full tier: **3314 bytes (~828 tokens)**
- Lean tier: **2443 bytes (~610 tokens)**
- Savings: **871 bytes (~217 tokens, 26%)**

The 871-byte delta is the 8-row phase-guide table + the Step-1/2/3 scaffold. The lean variant retains the skill lines, `MUST INVOKE` markers, `Skill(...)` invocations, composition chain, and the mandatory eval-format line (verified by `test_lean_tier_env_override` in `tests/test-routing.sh`).

## Gate

Pre-committed threshold (set before running): proceed to Phase 1 only if savings ≥ 200 tokens.

**Verdict: PROCEED** (217 ≥ 200).

This contradicts the design-debate's prediction (~130–170 tokens, estimated from source). The real registry's full tier is larger than agents estimated, so the trim clears the gate.

## Decision

The pre-committed gate cleared, so Phase 1 (model-in-loop A/B to confirm the lean tier does not hurt skill-invocation compliance) is **justified on size grounds** and is the honest next step IF pursued.

**However — absolute-impact caveat for the human decision:** 217 tokens fire only on the *first* prompt of a session that selects 3+ skills, once per session. That is a small absolute saving. Phase 1's cost (per the pragmatist: a new injection-aware harness + cross-phase `tool_call` corpus + variance runs ≈ ~2 days build + millions of model tokens) is large relative to a 217-token-per-session prize. The gate measured *whether the prize is non-trivial*; it did not measure *whether Phase 1's cost is worth that prize*. That ROI call is the user's.

Three honest options now on the table:
1. **Build Phase 1** — the gate cleared; confirm compliance holds before shipping the trim.
2. **Ship the lean tier directly behind the existing depth-graded safety net** — the deterministic test already proves the lean variant retains all compliance-carrying text (`MUST INVOKE`, `Skill(`, eval format); accept the small risk without the expensive behavioral experiment, since the full tier is only one prompt per session.
3. **Stop here** — record that the prize (217 tokens/session-opening) is real but too small to justify either Phase 1's cost or a behavior change; keep `SKILL_LEAN_TIER` as a default-OFF measurement artifact.

## Notes

- Token estimate is bytes/4 (directional).
- Savings vary by prompt: the phase-guide table is fixed (~8 rows), but skill-line content scales with how many skills route. Prompts selecting more skills will save a similar absolute amount on the scaffold/guide.
- The lean tier is shipped as an env-gated (`SKILL_LEAN_TIER=1`) branch, **default-OFF** — current production behavior is byte-identical to before (regression-guarded by the unchanged `test_depth_full_format_first_prompt`).
