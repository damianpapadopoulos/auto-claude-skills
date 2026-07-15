# Backtest results: post-review staleness rule (2026-07-15)

Protocol: `backtest-protocol.md` (pre-registered at 835d19a before data
collection). Population: all 108 merged PRs; classifier =
`hooks/lib/staleness-delta.sh` (the same code gate-status uses live).

## Instrument notes (validated pre-outcome, per protocol)

- Bare `[Rr]eview` over-matches in this repo (we build review tooling:
  "feat: add agent-team-review skill"). Refined to review-response markers:
  `address…review`, `review findings/feedback/nits/recs/minors/follow-up`,
  `(per|after|from) X review`, `(review…)` scope tags, `final-review`,
  `(PR… nits)`. Skill-name/feature mentions verified excluded.
- Ledger ground truth matched 18 branches via
  `sha1(origin-url\x1fheadRefName)`; 16 ancestor-verified (incl. all 5 audit
  branches #108–#113-era). 2 non-ancestors (PR #103 rebase-after-conflict,
  PR #87) fell back to the message proxy as specified.
- Coverage: 16 ledger + 32 message = 48 evaluated; 60 excluded (no
  review-response marker; almost all pre-ledger).

## Results

| Variant | Fires | Fire rate | Catches | False blocks | False-block rate | Missed catches |
|---|---|---|---|---|---|---|
| V1 naive | 45/48 | 94% | 0 | 45 | **94%** | 0 |
| V2 docs-exempt | 40/48 | 83% | 0 | 40 | **83%** | 0 |
| V3 size>25 src lines | 27/48 | 56% | 0 | 27 | **56%** | 0 |

- **Defects attributable to post-review deltas: 0** across all 108 merged
  PRs. Fix-PR archaeology produced 19 candidate (PR, later-fix) pairs by
  file+content overlap; every strong candidate was refuted line-level:
  - PR 85→#97 (verdict-token deadlock): none of #97's deleted lines in
    `verdict.sh`/`openspec-guard.sh` were added in PR 85's post-review
    delta — the token-scoped design was in the reviewed body.
  - PR 50→#53 (singleton race): PR 50's head is a merge-from-main; the
    "post-review delta" was other PRs' merged-in content. Zero own-line
    overlap.
  - PR 10→fallback-registry sanitize fixes: 0 of the sanitizer's deleted
    lines appear in PR 10's post-review adds (8+/10- small delta).
  - PR 25→same-day telemetry-schema fix: schema misalignment predates the
    post-review commit (0 line overlap).
  Remaining candidates: overlap ≤2 boilerplate lines, or design-level
  gap-closing of reviewed code (#109 audit F2, #52). Per frozen rule,
  uncertain = ¬defect.
- Distribution: median post-review source delta = 29 lines (p75=124,
  max=1906 — the merge-from-main case); 8/48 PRs had zero source lines;
  only 3/48 ended with review SHA == HEAD.

## Sensitivity (frozen-rule exclusions treated as zero-delta instead)

Denominator 108: V1 42%, V2 37%, V3 25% fire. V3 alone dips under the 30%
disqualifier but still has 0 catches and 27 false blocks → fails the
"≤5% false-block AND ≥1 catch" requirement. Decision unchanged.

## Structural findings

1. **The composition chain guarantees post-review commits.** SHIP follows
   REVIEW, and SHIP writes openspec as-built docs + CHANGELOG; review-fix
   commits themselves move HEAD (the pre-registered infinite-loop
   rationale, now empirical: 45/48).
2. **Merge-from-main is a real false-block mode**: `diff(review-sha, HEAD)`
   counts content reviewed in other PRs. Any future hard rule would need
   merge-base-aware diffing — and still had 0 catches to offer here.
3. Post-review deltas are docs-heavy (SHIP artifacts) with small source
   tails that are overwhelmingly the review fixes themselves.

## Decision (per frozen rule)

No variant meets "false-block rate ≤5% AND ≥1 catch"; V1/V2 additionally
fire >30%. **The staleness line ships as observation only** (docs-vs-source
split via `staleness_delta`), the deny decision stays DEFERRED, and the
advisory-by-design rationale is now backed by data: hardening any tested
variant would have blocked 27–45 of the last 48 clean merges and caught
nothing.
