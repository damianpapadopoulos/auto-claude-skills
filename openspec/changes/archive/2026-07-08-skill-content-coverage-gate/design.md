# Design: skill-content-coverage-gate

## Architecture

A new deterministic test suite `tests/test-skill-content-coverage.sh`, modeled directly
on `tests/test-fixture-coverage.sh`:

1. Enumerate owned trigger-routed skills with the SAME jq query
   `test-fixture-coverage.sh` uses (invoke contains `auto-claude-skills:` AND
   `triggers | length > 0`).
2. For each, assert at least one file under `tests/` (excluding the coverage suite
   itself) references the real `skills/<name>/` path — i.e. `grep -rnF "skills/<name>/"`
   with mock-fixture lines (`.claude/skills/<name>/`) filtered out. Detection is by
   CONTENT, not filename, because content tests have no naming convention
   (`product-discovery` → `test-discovery-content.sh`, `runtime-validation` →
   `test-validation-skill-content.sh`). The `.claude/skills/` exclusion is load-bearing:
   registry/discovery mechanics tests build fake skill trees at `${HOME}/.claude/skills/
   <name>/` using real skill names, and counting them false-passes a skill that has no
   real content test (caught in review for `agent-team-execution`).
3. Use the shared `_record_pass`/`_record_fail`/`print_summary` helpers so a miss exits
   non-zero and `.verify.yml` blocks merge.

Exemptions mirror the fixture gate exactly: skills invoked via other plugins, and owned
skills with no trigger regex (composition-only, e.g. `security-scanner`), are out of the
population by the same query.

Backfill: add `tests/test-capture-knowledge-content.sh`,
`tests/test-prototype-lab-content.sh`, and `tests/test-agent-team-execution-content.sh`,
each asserting the SKILL.md exists, carries its `name:` frontmatter, and contains its
load-bearing section headings.

## Trade-offs

- **Presence, not quality.** The gate proves a test *references* the skill, not that it
  asserts anything meaningful — a deliberately empty test could satisfy it. This is the
  same pragmatic bar as `test-skill-anatomy.sh` (heading presence) and the accepted
  limitation across this repo's deterministic gates; quality stays a human-review
  concern. Documented in the suite header. Attempting to enforce assertion quality with
  more regex does not generalize (the held-out lesson) — out of scope.
- **Content-grep vs manifest vs naming convention.** Content-grep is naming-agnostic and
  needs no migration of the 11 inconsistently-named existing tests. A manifest would be
  more explicit but adds a file to keep in sync; a naming convention would force renames.
  Content-grep wins on lowest-friction correctness.
- **Backfill-then-enable vs ratchet/allowlist.** Only 3 skills are uncovered, so a
  straight backfill enables the gate green with no allowlist to maintain. A ratchet would
  be over-engineering for a 2-item gap.

## Dissenting views

- "Just make `skill-scaffold` required." Rejected in the proposal: `required` is a
  routing-surfacing flag, not a merge gate, so it enforces nothing and would misfire on
  edits of existing skills.
- "Also gate `evals.json` presence." Rejected: ~0 owned skills carry one, the
  skills/*/evals schema is unvalidated, and its consuming mechanism (description-based
  `run_loop`) mismatches this repo's regex routing. Enforcing it would fail all 19 with
  low value. Stays recommended, not gated.

## Decisions

- Extend the existing `skill-creation-gate` capability (noun-family match) rather than
  mint a new capability.
- New sibling suite, not an extension of `test-fixture-coverage.sh`, to keep each suite's
  responsibility single (fixture coverage vs content coverage).
- Deterministic verification: TDD (red: gate fails on an uncovered skill → green after
  backfill). No eval pack — no probabilistic behavior. No trifecta surface (local bash
  over repo files; no private data / untrusted input / outbound action). No autonomy
  concern.

## Out-of-scope

- Enforcing `evals.json` presence or any eval-pack schema for `skills/*/evals/`.
- Content-test QUALITY beyond presence.
- Reclassifying `skill-scaffold`'s role.
- Any change to authorial-judgment / PR #99, or to routing/hooks/push-gate.
