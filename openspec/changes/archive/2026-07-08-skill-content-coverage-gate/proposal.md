# Proposal: skill-content-coverage-gate

## Why

The enforceable skill-authoring floor currently gates exactly one artifact: the
routing fixture (`test-fixture-coverage.sh`). Content-assertion tests — which guard a
skill's load-bearing SKILL.md sections against silent erosion by later edits — exist
for most owned skills but are enforced by nothing, so a new skill (or an edit that
deletes a test) can ship with zero content coverage.

This was surfaced while deciding whether to make `skill-scaffold` `role: required`.
That would not work: `required` only changes routing surfacing, not merge-blocking, so
it enforces nothing (even `writing-skills`, which is `required`, is explicitly not a
merge precondition). The correct mechanism — consistent with the repo's "enforceable
done-gate is OWNED and deterministic" principle — is a CI-blocking coverage check, not
a role flag.

Measured reality: of 19 owned trigger-routed skills, 16 have a test asserting on their
real SKILL.md; 3 lack one — `capture-knowledge`, `prototype-lab`, and `agent-team-execution`
(the last was found in review to be false-passing a naive check purely via a mock-fixture
path in `test-registry.sh`; the gate now ignores `.claude/skills/` mock paths). So the gate
enables green after a 3-skill backfill — no grandfather/allowlist machinery.

## What Changes

- **Added** `tests/test-skill-content-coverage.sh` — for each owned trigger-routed skill
  (same population query as `test-fixture-coverage.sh`), assert that at least one
  `tests/*.sh` file references the real `skills/<name>/SKILL.md` (content-based,
  naming-agnostic; mock `.claude/skills/<name>/` paths excluded).
  CI-blocking via `.verify.yml` (the suite already fails the build on any test failure).
- **Added** content-assertion tests for the 3 uncovered skills: `capture-knowledge`,
  `prototype-lab`, `agent-team-execution`, so the gate is green on enable.
- **Docs:** note the new gate in `CLAUDE.md`'s skill-creation section and CHANGELOG.

## Capabilities

### Modified
- `skill-creation-gate` — the deterministic owned-skill done-gate gains a second required
  artifact (content-assertion coverage) alongside the existing routing-fixture requirement.

## Impact

- One new test suite + three new content tests. No hooks, routing, or push-gate changes.
- All 19 owned skills pass on merge (16 already covered + 3 backfilled).
- Naming-agnostic detection means the many existing non-uniformly-named content tests
  (`test-discovery-content.sh`, `test-validation-skill-content.sh`, …) all count without
  renaming.
