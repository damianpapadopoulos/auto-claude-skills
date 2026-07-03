# Design: DB phase-gate decision race

## Architecture

Three components, run in sequence, producing one committed decision artifact.

```
Codex (cross-model author) ──► corpus/            ~20 defect + ~8 clean fixtures
                                  │                 (blind to B2 checklist)
                                  ▼
        ┌────────── behavioral-evaluation runner (--variance ≥5) ──────────┐
        │  A0: bare REVIEW    B1: hint→external    B2: owned checklist       │
        └──────────────────────────────┬───────────────────────────────────┘
                                        ▼
              scoring (detection, false_positive per arm)
                                        ▼
              pre-registered decision rule ──► DECISION.md (ship-B2 | ship-B1 | park)
```

### Corpus (`corpus/`)
- `defects/NN-<taxon>.md` — one realistic DB change (migration/query/schema) + exactly one
  planted defect, with a sibling `NN-<taxon>.label.json` ground truth (taxon, defect line,
  expected-flag phrase family).
- `clean/NN.md` — realistic clean DB change (negative). Drives the false-positive metric.
- Taxonomy (fixed up front): `unsafe-migration`, `missing-index`, `n-plus-one`,
  `offset-pagination`, `lock-risk`. Even coverage so no single taxon dominates the score.
- Authored by Codex from the taxonomy, **not** shown the B2 checklist — the anti-overfit
  control. A short reality-check pass confirms synthetic difficulty isn't trivially easy.

### Arms
- **A0** — the prompt runs current REVIEW (general code-reviewer) with no DB gate injected.
- **B1** — same, plus a thin activation-style hint pointing at the installed external
  `planetscale/database-skills` (mysql/postgres). Tests "point, don't own."
- **B2** — same, plus an owned, de-vendored DB-review checklist injected at REVIEW. Tests
  "own the content." Checklist is authored from the taxonomy independently of the corpus.

### Runner + assertions
- `behavioral-evaluation`, `--variance ≥5` per (fixture × arm).
- Per run, two independent assertions:
  - **detection** — output names the planted defect (label phrase family match).
  - **specificity** — on clean fixtures, output does NOT raise a DB-defect flag.
- Detection rate and false-positive rate computed per arm across the corpus.

### Scoring + decision (frozen before first run)
- Score = `detection_rate − false_positive_rate` per arm.
- **Ship** the best variant only if it beats A0 by **≥20pp detection at ≤10pp FP**.
- **Park** if no variant clears the bar (proven redundant — a valid, logged outcome).
- **Point-don't-own** if `|score(B1) − score(B2)| < 10pp` and both beat A0 → adopt B1.
- **Safety-stop** — if per-arm 95% ranges overlap across the 5 variance runs, halt; expand
  n rather than declare a winner. The user or I may call this stop.

## Trade-offs

- **Cost ≈ building the gate.** Accepted: the payoff is a generalizable, reusable eval
  method + a decision that can't be relitigated on vibes. Flagged to the user; approved.
- **Synthetic corpus may be easier than real defects.** Mitigated by a reality-check pass;
  a real-history mined subset is a documented follow-up if synthetic difficulty is suspect.
- **Judge/assertion brittleness.** Label phrase-families (not exact match) + variance runs
  reduce single-run luck; ERE assertion needles must self-anchor (word-boundary) per our
  routing scar tissue.

## Dissenting views

- *"Just ship B2 and iterate."* Legitimate — the race costs as much as the gate. Rejected
  because an unmeasured gate injects context into every DB interaction with no evidence it
  beats bare REVIEW, and we cannot later prove it earned its keep. Surfaced to user; user
  chose the race.
- *"Park without measuring."* The prior recommendation. Overridden: measurement pre-empts
  the pain instead of waiting for it, which is the user's stated goal.

## Decisions

- Corpus source: **cross-model synthetic** (Codex), blind to checklist. (User-confirmed.)
- Arms: **all three** A0/B1/B2 in the first race. (User-confirmed.)
- Decision rule is **pre-registered and frozen** in this design before any run; changing it
  post-hoc invalidates the race.
- No routing/config change ships in this change; a "ship" verdict opens a *separate* change
  to build the gate, carrying this evidence.
