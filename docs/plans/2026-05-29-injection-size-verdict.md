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

## Decision — Option 2 (ship lean directly)

The gate cleared (PROCEED-eligible), but **Phase 1 was deliberately NOT built**: 217 tokens fire only on the first prompt of a session that selects 3+ skills, and Phase 1's cost (a new injection-aware harness + cross-phase `tool_call` corpus + variance runs ≈ ~2 days + millions of model tokens) is disproportionate to that once-per-session prize. The deterministic test already proves the lean variant retains every compliance-carrying element (`MUST INVOKE`, `Skill(...)`, the eval directive), so the residual compliance risk is small and bounded to one prompt per session.

**Shipped:** the lean rendering is now the **production default** for the prompt-1 / 3+-skill tier. `SKILL_VERBOSE=1` restores the full scaffold + phase-guide table (rollback hatch / opt-in). This is a behavior change (the session-opening injection drops the Step-1/2/3 scaffold + 8-row phase guide) — guarded by updated tests in `tests/test-routing.sh` and `tests/test-context.sh`.

**Rollback:** if invocation compliance regresses in real use, set `SKILL_VERBOSE=1` (or revert the `_format_output` default-branch swap) to restore the verbose tier instantly.

## Notes

- Token estimate is bytes/4 (directional).
- Savings vary by prompt: the phase-guide table is fixed (~8 rows), but skill-line content scales with how many skills route. Prompts selecting more skills save a similar absolute amount on the scaffold/guide.
- `tests/measure-injection-size.sh` measures verbose (`SKILL_VERBOSE=1`) vs lean (default) and re-asserts the savings + gate at any time.
