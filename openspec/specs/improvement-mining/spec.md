# improvement-mining Specification

## Purpose
TBD - created by archiving change improvement-miner. Update Purpose after archive.
## Requirements
### Requirement: Evidence intake is deterministic and trust-bounded

The evidence bundle SHALL be produced by
`skills/improvement-miner/scripts/mine-evidence.sh` from: committed
baseline files, structured GitHub issue bodies authored by
`github-actions[bot]`, live `scripts/gate-status.sh` output when present,
auto-memory frontmatter index lines, and owner-authored
`improvement-miner-run` ledger issues. The script SHALL enforce the author
allowlist and SHALL never request issue comments, raw workflow-artifact
fields, or `tests/fixtures/*/evals/` content. Expectation provenance:
discovery brief conditions 2 and 6 (F2 public repo, F7 raw-artifact
adversarial text), assumption A6.

#### Scenario: non-allowlisted author is excluded

- GIVEN a GitHub issue whose title matches the eval-regression pattern but
  whose author is not `github-actions[bot]`
- WHEN `mine-evidence.sh bundle` runs
- THEN that issue's content does not appear anywhere in the bundle

#### Scenario: comments are never requested

- GIVEN any bundle or ledger read
- WHEN the script calls `gh`
- THEN the requested JSON field list contains no comment fields

### Requirement: Kill-criterion arithmetic is computed by code and gates the miner

The script SHALL compute cumulative presented/approved counts from the
run-ledger issues and print the kill state (`alive` or `tripped`, threshold:
fewer than 1 approved of the first 5 presented). The skill SHALL print this
verbatim in every report and SHALL refuse to mine when `tripped` unless the
user explicitly overrides. Expectation provenance: discovery H1 and
condition 1 (I2: unmeasurable without a durable record).

#### Scenario: tripped criterion stops the miner

- GIVEN ledger issues recording 5 presented proposals and 0 approvals
- WHEN the skill is invoked
- THEN it reports "decommission recommended" and performs no extraction,
  ranking, or issue creation without an explicit user override

#### Scenario: zero-delta run does not advance the denominator

- GIVEN a run that presents 0 proposals
- WHEN its ledger issue is written and a later bundle is built
- THEN cumulative presented count is unchanged by that run

### Requirement: Previously presented proposals never re-present

Each candidate SHALL carry a fingerprint derived from its source class and
canonical source identifier (not proposal wording). The script's dedup mode
SHALL identify candidates matching ANY previously presented fingerprint and
report its prior decision; the skill SHALL exclude them from presentation —
rejected duplicates are listed as dead, approved duplicates as already
queued with their issue number. Expectation provenance: assumption A8
(merge precondition), inference I1.

#### Scenario: reworded proposal from the same evidence is deduplicated

- GIVEN a run-1 ledger recording fingerprint F as rejected
- WHEN a later run derives a differently-worded candidate from the same
  source identifier
- THEN the candidate's fingerprint equals F and it is not presented

### Requirement: Presentation gate — complete A/B contract or no presentation

Every presented proposal SHALL carry a complete A/B evidence contract:
pre-registered metric, sha-bound baseline and candidate measurement plans, a
pinned never-delete eval set, and a hard no-regression clause on safety
dimensions. Candidates lacking any element SHALL NOT be presented or become
issues; they are listed with their missing fields. Expectation provenance:
assumption A9, discovery condition 5.

#### Scenario: incomplete contract is withheld

- GIVEN a candidate whose draft contract lacks a pinned eval set
- WHEN the report is assembled
- THEN the candidate appears only in the not-presented appendix with the
  missing field named, and no GitHub issue is created for it

### Requirement: Anti-treadmill guard

A single report SHALL present at most 5 proposals, of which at most 2 may be
meta-proposals (primary artifact is gate/loop/plugin-internals machinery);
when more meta candidates qualify, the lowest-graded are dropped first. Each
report SHALL contain at least one proposal citing end-user-facing evidence
or an explicit statement of why none qualified. Expectation provenance:
discovery H2, the staged plan's anti-treadmill design requirement.

#### Scenario: meta overflow is trimmed by grade

- GIVEN 3 meta candidates graded B, C, and D and 2 end-user-facing
  candidates
- WHEN the report is assembled
- THEN the D-graded meta candidate is not presented

### Requirement: Approved items become labeled issues; the run ends with a ledger issue

On approval the skill SHALL create one GitHub issue per approved item
labeled `improvement-miner`, carrying grade, provenance (run id, source sha,
observed-at), and the A/B contract. Every run SHALL end by writing one
owner-authored issue labeled `improvement-miner-run` recording each
presented item's fingerprint, rank, decision, and reason, plus cumulative
counters and ranking-instrumentation stats. The miner SHALL perform no git
mutations and no pushes. Expectation provenance: discovery conditions 1 and
4 (A4 kill-shot needs recorded ranks), assumption A10.

#### Scenario: approval produces a durable, contract-bearing issue

- GIVEN a presented proposal the user approves in-session
- WHEN the approval is processed
- THEN a GitHub issue exists with label `improvement-miner`, the proposal's
  grade, provenance fields, and contract, and no repository file was
  modified

#### Scenario: ranks are recorded for the A4 kill-shot

- GIVEN a completed run with 3 presented items
- WHEN the ledger issue is written
- THEN each item's rank and decision are recorded such that the top-2
  concentration statistic is computable from ledger issues alone

