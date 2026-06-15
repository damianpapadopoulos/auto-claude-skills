# Design: Phase-Reconciliation Advisory (Gap 3)

## Architecture

A single advisory block appended to `hooks/skill-activation-hook.sh` immediately after the `[design-guard]` block (~L1563), gated to `PRIMARY_PHASE == SHIP`. It mirrors the design-guard idiom exactly: read cheap local state, emit an advisory line into `SKILL_LINES` on contradiction, emit a `SKILL_EXPLAIN` breadcrumb to stderr, and stay **silent on the happy path**. Two independent rules; either, both, or neither may fire.

### Why SHIP-only, why advisory, why these two rules

The phase label is a *display artifact* on a `UserPromptSubmit` hook that has no `permissionDecision: deny` authority over anything but `additionalContext`. The model reads it and self-corrects (observed repeatedly this session). So the honest surface is advisory, not enforcing. The real enforcement boundary already exists: `openspec-guard.sh:44-77` denies `git push` on incomplete REVIEW/VERIFY in an active chain — forgery-resistant, gating the irreversible action. A phase hard-block adds only false-positives (and is a literal no-op when 0 commits ahead + clean tree).

The two rules cover **disjoint** failure classes and each is silent where the other fires:

| Rule | Fires when | Misses (covered by the other) | Cost |
|---|---|---|---|
| **A** chain-skip | active chain has `requesting-code-review` but `.completed` lacks it | no chain exists at all | one jq `-e` (jq already in use) |
| **B** no-work | `rev-list --count origin/main..HEAD == 0` AND clean tree | work exists but chain skipped REVIEW | 2 local git forks (`rev-list`, `status`) |

Rule A needs an active chain (silent in the no-chain API-key scenario). Rule B fires precisely there. Verified: composition state is only written for chains of ≥2 skills (`skill-activation-hook.sh:1051` guard `[[ "${_full_chain}" == *"|"* ]]`), so `.completed` is absent in the single/zero-skill case.

### Rule A — exact shape

```bash
# SHIP-only. Reuses the jq membership idiom from openspec-guard.sh:60-62.
_COMP_FILE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN:-default}"
if [[ "$PRIMARY_PHASE" == "SHIP" ]] && [[ -f "$_COMP_FILE" ]]; then
  if jq -e '((.chain // []) | index("requesting-code-review")) != null
            and ((.completed // []) | index("requesting-code-review")) == null' \
       "$_COMP_FILE" >/dev/null 2>&1; then
    _PR_MSG="${_PR_MSG}
  [i]  Chain has not completed REVIEW (requesting-code-review not in .completed) — run it before SHIP."
  fi
fi
```

Self-scoping: it checks `.chain` membership too, so chains that legitimately have no review step never fire. Token-rotation-safe: a stale/foreign/empty state file → `.chain` lacks the member or the file is absent → silent (this matters — the repo has documented session-token-rotation flakiness, so Rule A must never *rely* on `.completed` being authoritative; it only speaks on a clear positive divergence).

### Rule B — exact shape

```bash
if [[ "$PRIMARY_PHASE" == "SHIP" ]]; then
  _AHEAD="$(git -C "$_PROJECT_ROOT" rev-list --count origin/main..HEAD 2>/dev/null)"
  [[ "$_AHEAD" =~ ^[0-9]+$ ]] || _AHEAD=-1     # detached / no origin / error => silent
  _DIRTY="$(git -C "$_PROJECT_ROOT" status --porcelain 2>/dev/null)"
  if [[ "$_AHEAD" -eq 0 ]] && [[ -z "$_DIRTY" ]]; then
    _PR_MSG="${_PR_MSG}
  [i]  No committed work on this branch (0 commits ahead of origin/main, clean tree) — SHIP phase may be premature."
  fi
fi
```

`origin/main` is used literally (matches `openspec-guard.sh` and the repo's mainline convention) rather than `@{upstream}` (which can be unset on a freshly-created branch). The clean-tree AND-clause is load-bearing: `rev-list --count origin/main..HEAD` returns 0 on clean post-merge main (verified), so without `-z "$_DIRTY"` it would mislabel a clean main. `_AHEAD=-1` sentinel handles detached HEAD / no remote / fresh clone fail-open. Numeric guard before the `-eq` comparison per the Bash 3.2 gotcha; no quoted `$(( ))`; the hook has no `set -e` (verified), so a non-matching `[[ ]]` is harmless.

### Emission

```bash
if [[ -n "$_PR_MSG" ]]; then
  SKILL_LINES="${SKILL_LINES}
PHASE REALITY:${_PR_MSG}"
fi
[[ -n "${SKILL_EXPLAIN:-}" ]] && \
  echo "[skill-hook]   [phase-reality] ahead=${_AHEAD:-na} dirty=${_DIRTY:+1} phase=${PRIMARY_PHASE}" >&2
```

`[i]` (advisory), not the design-guard `[X]` (which implies a required-section failure) — this is a softer nudge, addressing the critic's "soften the wording" point. **Nothing is emitted on the happy path or on any non-SHIP phase** — the entire block is skipped unless `PRIMARY_PHASE == SHIP`, keeping the common path free of git/jq cost.

## Trade-offs

- **Accepting:** Rule B's residual false-positive — "let's recap what we just shipped" on clean main at a SHIP-classified prompt. Advisory-only makes this cheap (the model reads `[i] … may be premature` and overrides in one token). SHIP-only restriction already removes the larger REVIEW-phase version of this class.
- **Accepting:** Rule A is silent in the no-chain case **by design** (Rule B covers it). An implementation comment MUST state this so a future editor doesn't "fix" it.
- **Accepting:** advisory has no teeth; a determined/forgetful model can ignore it. The push gate remains the real boundary — this is the deliberate ceiling, not a gap.

## Dissenting views

- **Critic:** initially argued "phase is wrong" is cosmetic and the fix is to soften the always-on label + reconcile `.completed` only, skipping git entirely. Conceded in Round 2 that `.completed`-only is silent in the exact motivating no-chain scenario, and that git-state is token-rotation-independent — so git (Rule B) is essential. Residual dissent: holds git should be framed as the *primary* signal and `.completed` secondary; resolved as moot since both are SHIP-only and independent.
- **Architect:** initially proposed a push-gate hard-block on `commits-ahead==0`. Conceded fully: it's a no-op (nothing to push) dominated by the existing chain-state gate.
- **Pragmatist:** had Rule B at REVIEW+SHIP; **Codex tightened to SHIP-only** to kill the post-merge-recap false-positive — adopted.

## Decisions & Trade-offs (rejected / deferred alternatives)

- **Any hard-block / push-gate teeth** — rejected for v1. Dominated by `openspec-guard.sh`'s existing chain-state push gate; blocking on a prompt-derived (unreliable) phase inverts the logic. Revival: an advisory is logged ignored → resulting bad push/merge, ≥2 instances (same evidence bar the repo uses for openspec-guard escalations); then promote Rule A to a deny in the push gate, not the activation hook.
- **`gh pr view` / PR-state reconciliation** — deferred. Measured 0.46s–6.66s, ~9–133× the ~50ms budget; `gh` also hangs under SAML SSO (documented). Network has no valid home in the per-prompt path. Revival: a named case where local git state false-negatives (work on a PR branch not compared to origin/main) AND it caused real harm.
- **tests-ran-this-session signal** (`.skill-project-verified-<token>`) — deferred. Forgeable (model-written), and `.completed` + git already cover the two real classes. Revival: paired with v2 push-gate teeth.
- **REVIEW / IMPLEMENT-phase checks** — rejected. REVIEW: `requesting-code-review` is the current step (Rule A always false-fires) and clean-tree REVIEW is usually benign recap (Rule B noisy). IMPLEMENT: no sharp contradiction signal.
- **Softening the always-on `PRIMARY_PHASE` label** — not adopted as a separate change. A constant disclaimer trains banner-blindness; the *conditional* `[i]` note carries the signal (its presence is the information). The `[i]` style already reads as advisory.
- **New hook file / new state schema / config changes** — rejected. Purely additive to one hook function, reusing `_PROJECT_ROOT`, `_SESSION_TOKEN`, the `SKILL_LINES` channel, the breadcrumb idiom, and the existing `.skill-*-<token>` namespace.

## Out-of-scope

- Hard enforcement of any kind (push gate stays the boundary).
- PR-state / any network call in the activation path.
- Rewriting the composition state machine or how `PRIMARY_PHASE` is derived.
- Any check at phases other than SHIP.
