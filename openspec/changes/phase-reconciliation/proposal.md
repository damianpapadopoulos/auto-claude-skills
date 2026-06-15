# Proposal: Phase-Reconciliation Advisory (Gap 3)

## Why

Deferred from issue #58 (Gap 3), and motivated live during the PR #59 session: the SDLC phase shown to the model is asserted **100% from prompt text**. `PRIMARY_PHASE` (`hooks/skill-activation-hook.sh:609-641`) is just the `.phase` field of the highest-priority triggered skill — **git/PR state is never consulted, and the composition `.completed` progress the hook already loads is never compared against it.** So a prompt mentioning ship/review/merge asserts that phase even when no branch, diff, commit, or completed REVIEW exists. This session demonstrated it repeatedly: the tracker asserted DEBUG/DISCOVER/REVIEW/SHIP while implementation was mid-flight, and once while the actual work was debugging an external API key with no code and no composition chain at all.

A four-perspective design debate (architect/critic/pragmatist + Codex cross-model) converged on the scope below. Two premises were corrected during the debate — recorded here so the design stays honest:
- **`gh pr view` is categorically off-budget** for a per-prompt hook: measured at 0.46s (in-house) and 6.66s cold (Codex), vs the ~50ms activation budget (CLAUDE.md). PR-state reconciliation cannot live in the activation path. Deferred.
- **The "this repo ships docs not code, so a code-diff rule is invalid" framing was wrong** (Codex: the last merges all ship `.sh` hooks/tests/scripts). It does not change the design, because the git rule keys on the **empty state** ("0 commits ahead AND clean tree" = no work *at all*), not on a code-vs-config distinction.

## What Changes

Add an **advisory-only** `PHASE REALITY:` block to the activation hook, gated to `PRIMARY_PHASE == SHIP`, mirroring the existing fail-open `[design-guard]` idiom (`skill-activation-hook.sh:1481-1562`). It emits a soft `[i]` nudge — never blocks — when the claimed SHIP phase contradicts repo reality, via two complementary checks:

- **Rule A — chain-skip reconciliation** (no git, reuses already-loaded state): when an active composition chain contains `requesting-code-review` but `.completed` does not, nudge that REVIEW hasn't completed before SHIP. Catches the *chain-skipped-a-gate* class. Silent when no chain exists.
- **Rule B — no-work-under-SHIP** (local git only): when `git rev-list --count origin/main..HEAD == 0` AND `git status --porcelain` is empty, nudge that there is no committed work to ship. Catches the *no-work / no-chain* class (the API-key scenario Rule A misses). Numeric-guarded; fail-open and silent on detached HEAD, no origin, or any git error.

Both rules are **SHIP-only** (Codex tightening): at REVIEW, `requesting-code-review` is legitimately the *current* step (so Rule A would always false-fire), and a clean-tree REVIEW is most often a benign "recap what we just merged" (so Rule B would generate banner-blindness). SHIP-only makes both rules symmetric and high-precision.

**No teeth.** The existing `openspec-guard.sh:44-77` push gate already hard-denies pushes when REVIEW/VERIFY are incomplete in an active chain — forgery-resistant, gating the irreversible `git push`. A phase hard-block is a no-op dominated by it (when 0 commits ahead + clean tree, `git push` pushes nothing anyway). Advisory is the honest ceiling here, consistent with the PR #59 verification-debate conclusion that hooks can't enforce on model-driven/forgeable signals.

## Capabilities

### Modified
- **`skill-routing`** — the activation hook gains a SHIP-phase advisory that reconciles the prompt-derived phase against composition `.completed` and local git work-state. Advisory-only, fail-open, silent on the happy path. (Same home as the `[design-guard]` advisory requirements.)

## Impact

**Files modified:**
- `hooks/skill-activation-hook.sh` — ~28-line `PHASE REALITY` block after the design-guard block (~L1563), gated to `PRIMARY_PHASE == SHIP`. Reuses `_PROJECT_ROOT` (already resolved L107), `_SESSION_TOKEN`, the `SKILL_LINES` append channel, and the `[design-guard]`-style `SKILL_EXPLAIN` breadcrumb.
- `tests/test-routing.sh` — 4 sibling tests (git-fixture-based, set `SKILL_PROJECT_ROOT` to a temp repo): Rule B fires on SHIP + 0-ahead + clean; Rule B silent when commits exist; Rule A fires on SHIP + chain-has-but-completed-lacks review; block silent on non-SHIP phases.
- `CHANGELOG.md` — `[Unreleased]` accumulator entry.

**No config changes** (`config/default-triggers.json` / `fallback-registry.json` untouched — routing-orthogonal, no new skill/trigger/field).

**Out of scope:** any hard-block / push-gate teeth (deferred — revival: an advisory ignored → bad push, ≥2 logged); `gh`/PR-state (deferred — off-budget); a tests-ran-this-session marker (deferred — the forgeable `.skill-project-verified-<token>` is not consumed here); IMPLEMENT/REVIEW-phase checks; rewriting the composition state machine; anything requiring an LLM in the hook.
