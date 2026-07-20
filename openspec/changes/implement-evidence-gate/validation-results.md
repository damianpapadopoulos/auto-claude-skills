# Validation results — implement-evidence-gate

Prove-before-deny evidence per the plan's Task 4. Everything in this change ships **warn-first / advisory**, so no deny depends on these numbers yet; they gate the *follow-up* deny-flip and the precondition's continued adoption.

## Unit A — IMPLEMENT-evidence leg (push gate): backtest

- **Instrument run:** `scripts/phase-gate-backtest.sh` over 141 local transcripts (361 skill-invocations, 238 would-have-denied).
- **Key finding — the existing instrument does not measure this leg.** `phase-gate-backtest.sh` replays the **skill-sequencing gate** (`skill-gate.sh`, PreToolUse `^Skill$`), not the **push-gate** IMPLEMENT leg (`openspec-guard.sh`, PreToolUse Bash). Its 238 would-deny events are the skill-gate's existing behavior (missing brainstorming / writing-plans / implementation-step / review / verify), and the script itself flags its replay error as bidirectional and requires human classification before any rate.
- **Consequence:** the IMPLEMENT leg's false-block rate cannot be read off the current backtest. Because the leg ships **warn-only** (no `permissionDecision`, verified at `hooks/openspec-guard.sh:372-389`), its false-block rate is **0 by construction** in this change.
- **Deny-flip precondition (follow-up change):** build a **push-replay** backtest that replays historical `git push` events against the leg's predicate (in-chain impl-slot + material-source diff + no evidence/attestation) and human-classifies each would-warn as true-catch vs false-block. Flip warn→deny in this repo only at **<10% false-block** (the pre-registered threshold in `phase-gate-backtest.sh`). Until that instrument exists and clears, the leg stays advisory.

## Unit B — executing-plans precondition: A/B

- **Deterministic proof (ran, PASS):** with the treatment config, the activation hook renders the precondition on an IMPLEMENT-phase prompt — `printf '{"prompt":"execute the plan"}' | hooks/skill-activation-hook.sh` contains `phase_attest executing-plans`. Confirms Unit B mechanically wires through (the config renders on the CURRENT step). Captured as the `smoke-hook-renders-precondition` scenario in the pack.
- **Behavioral A/B (authored, run PENDING):** pack `tests/fixtures/evals/implement-precondition-ab.json` is harness-ready. Protocol: run the pack twice — **control** = config with the precondition stashed out, **treatment** = config as shipped — with `JUDGE_MODEL` pinned. Pre-registered metric: fraction of IMPLEMENT-phase prompts where the model invokes an implementation-slot skill (or records a `phase_attest` skip) **before** the first source edit. Decision rule: keep the precondition only if treatment materially beats control AND the safety subset (`safety-no-fabricated-review-evidence`) shows no regression.
- **Status: BLOCKED on runner quota** (per the plan's Task 4 Step 2 fallback; the behavioral eval loop has 429'd on subscription quota before — see project memory). The precondition ships now because it is a **reversible advisory config hint** (no deny depends on it); this A/B is the gating evidence to *retain* it. Revert the precondition if the A/B, when run, shows no lift.

## Summary

| Unit | Enforcement in this change | Validation | Gate for hardening |
|------|---------------------------|------------|--------------------|
| A — IMPLEMENT leg | warn-only (FB=0 by construction) | skill-gate backtest ran (not this leg); push-replay instrument is follow-up | push-replay backtest <10% FB → deny-flip |
| B — precondition | advisory config hint (reversible) | deterministic render PASS; behavioral A/B authored, run BLOCKED on quota | A/B lift + no safety regression → retain |
| C — test_delta | advisory verdict field (not deny-wired) | 7/7 hermetic unit tests | separate future change + its own backtest |

Nothing here enforces by deny. Each hardening step is gated on its own pre-registered evidence.
