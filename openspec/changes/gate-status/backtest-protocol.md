# Pre-registered backtest protocol: post-review staleness rule

Registered BEFORE any PR delta data was collected (see commit timestamp; this
commit is the pre-registration seal). Feeds the DEFERRED deny-vs-warn decision
on post-review edits recorded in the 2026-07-15 post-audit triage (memory:
`post-audit-recommendations-triage`, constraint (d)).

## Question

If the push gate had enforced a "review evidence is stale — HEAD moved past the
review SHA" rule, per variant below, on every historical merged PR: how often
would it have blocked a push that was in fact fine (false block), and how many
real defects introduced by post-review edits would it have caught that the
advisory line missed (missed catch under advisory = catch under deny)?

## Review-point identification (measurement instrument)

Ordered; first applicable wins. Instrument may be validated/debugged on data
(it is not an outcome), but the variants, outcome definitions, and decision
rule below are frozen before collection.

1. **Ledger ground truth** — compute `sha1("<origin-url>\x1f<headRefName>")`
   per merged PR; if `~/.claude/.skill-branch-ledger-<hash>/requesting-code-review`
   exists, its recorded SHA is the review point (exact; this covers the 5
   audit branches #107–#111 and any other ledger-era branch).
2. **Commit-message proxy** — PR commits from the GitHub PR commits API
   (survives squash-merge). First commit whose message matches
   `[Rr]eview` marks the first post-review fix; the review point is its
   **parent** (the SHA the reviewer saw). Post-review delta = that commit
   through the PR head.
3. Neither → PR excluded from the denominator (count reported).

Post-review delta = `diff(review-SHA, PR-head-SHA)`: files changed, lines
added+deleted, split **docs** vs **source**.
Docs paths (frozen): `docs/**`, `openspec/**`, any `*.md`, `CHANGELOG.md`.
Everything else (hooks/, config/, skills/ non-md, scripts/, tests/, plugin
manifests) is source.

## Rule variants (frozen)

- **V1 naive**: any non-empty post-review delta → STALE (deny).
- **V2 docs-exempt**: STALE only if the delta touches ≥1 source path.
- **V3 size-threshold**: STALE only if source lines changed (adds+dels) > 25.
  (V3 ⊇ V2 exemptions; monotonically more permissive: V1 ⊇ V2 ⊇ V3 fires.)

## Outcome definitions (frozen)

- **fire(P,V)**: variant V classifies P's final pre-merge state as STALE.
- **defect(P)**: fix-PR archaeology finds a later `fix:`-typed commit/PR whose
  diff touches lines/files introduced or modified by P's post-review delta AND
  whose stated defect is attributable to that delta (candidates found
  mechanically, attribution judged manually and quoted with evidence).
- **false block(V)**: fire ∧ ¬defect. **catch(V)**: fire ∧ defect.
  **missed catch(V)**: ¬fire ∧ defect.
- **false-block rate(V)** = false blocks / PRs with identifiable review point.
  Fire rate reported alongside.

## Decision rule (frozen)

Harden the staleness line from advisory to DENY only if some variant has:
false-block rate ≤ 5% AND ≥ 1 catch. Additionally disqualified regardless of
the above: any variant firing on > 30% of PRs (routine review-fix commits ⇒
re-arm loop, the by-design advisory rationale). Uncertain attribution counts
as ¬defect (deny-bias belongs to VERIFY, not REVIEW). If no variant qualifies:
gate-status ships the staleness line as observation only, and the deny
decision stays deferred pending live data.
