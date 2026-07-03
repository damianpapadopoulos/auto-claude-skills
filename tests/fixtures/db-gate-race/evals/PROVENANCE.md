# Provenance: db-gate-race defect corpus

`corpus.json` was authored by the Codex (GPT) CLI, cross-model and BLIND to
`tests/fixtures/db-gate-race/arms/B2-owned-checklist.md`, to serve as the
anti-overfit held-out control for the DB-gate decision race: Codex was given
only `TAXONOMY.md`, `review-base.md`, and the behavioral-pack schema, and
never saw the B1/B2 arm directives, so its detection-assertion vocabulary
reflects independent general DB knowledge rather than either arm's wording.
The regex validity fixes applied in this commit (removing literal-SQL-echo
alternates from 12 defect assertions and hardening the version-ambiguous
MySQL migration in `defect-unsafe-migration-02`) were likewise made without
reading or referencing the `arms/` directory, preserving the corpus's
blindness for the race.
