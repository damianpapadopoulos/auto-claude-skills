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

### Requirement: Memory classification reads frontmatter type

`mine-evidence.sh::json_memory_index` MUST classify auto-memory files by their frontmatter `metadata.type` value, NOT by filename prefix. Rows whose `type` is `feedback` or `project` MUST be included; rows whose `type` is `reference` or `user`, files with no resolvable `type`, and `MEMORY.md` MUST be excluded. The emitted `kind` MUST equal the frontmatter `type` verbatim (`feedback` or `project`). Revival status MUST be an orthogonal boolean field `revival` (`true` when the body matches the revival heuristic, else `false`) and MUST NOT suppress or replace `kind`.

#### Scenario: project-type memory with no feedback_ filename appears in the index

- **GIVEN** a memory directory containing a file with frontmatter `type: project` whose filename does not start with `feedback_`
- **WHEN** `mine-evidence.sh bundle` builds `memory_index`
- **THEN** that memory appears with `kind == "project"`
- **AND** a `type: reference` or `type: user` file in the same directory does NOT appear

#### Scenario: revival is an orthogonal boolean, not a competing kind

- **GIVEN** a `type: project` memory whose body states a revival criterion
- **WHEN** the index is built
- **THEN** the row has `kind == "project"` AND `revival == true`

### Requirement: Project-noise advisory flag

`json_memory_index` MUST compute a deterministic boolean `noise` on `project`-type rows: `true` when the body is dominated by past-tense completion markers (at least two of e.g. `shipped`, `merged`, `closed`, `done`, `PR #<n>`, `landed`) AND contains no forward-looking marker (e.g. `TODO`, `still`, `open`, `pending`, `revival`, `follow-up`, `should`, `needs`, `broken`, `next`). `feedback`-type rows MUST always be `noise: false`. The flag MUST be advisory only: a noisy row MUST still appear in `memory_index` (it MUST NOT be dropped). The skill's extraction prose MUST require a forward-looking actionable delta before extracting a noisy row and MUST grade such items lower.

#### Scenario: status-history project memory is flagged noisy but retained

- **GIVEN** a `type: project` memory whose body is only completion markers (`shipped X`, `PR #12 merged`) with no forward-looking marker
- **WHEN** the index is built
- **THEN** the row has `noise == true`
- **AND** the row still appears in `memory_index`

#### Scenario: project memory with a forward delta is not flagged noisy

- **GIVEN** a `type: project` memory whose body says `shipped X but Y still broken`
- **WHEN** the index is built
- **THEN** the row has `noise == false`

### Requirement: Repo-type detection gates outbound issue creation

`mine-evidence.sh` bundle mode MUST emit `repo_type` (`plugin_self` when `config/default-triggers.json` exists at the resolved repo root, else `target`) and a human-readable `repo_type_reason`. The environment variable `IMPROVEMENT_MINER_REPO_TYPE`, when set to a valid value (`plugin_self` or `target`), MUST override file-presence detection and the reason MUST record the override; an invalid value MUST be ignored with a stderr notice and detection MUST fall back to file presence. The skill MUST print the detected `repo_type` and reason on every run. For `repo_type == target` the skill MUST default to REPORT-ONLY (print the ranked proposal report; create NO GitHub issues) unless the run explicitly opts into issue creation. For `repo_type == plugin_self` the skill's issue-creation behavior MUST be byte-identical to the pre-change behavior (issues created behind the existing per-item human gate).

#### Scenario: target repo defaults to report-only

- **GIVEN** a repository with no `config/default-triggers.json` and a completed mine with approved items
- **WHEN** the run completes without an explicit issue-creation opt-in
- **THEN** no `gh issue create` runs for the proposals
- **AND** the detected `repo_type` (`target`) and reason are printed

#### Scenario: plugin repo behavior is unchanged

- **GIVEN** this plugin repository (which HAS `config/default-triggers.json`)
- **WHEN** a mine runs and items are approved at the human gate
- **THEN** issues are created exactly as before the change
- **AND** `repo_type` is reported as `plugin_self`

### Requirement: Quoted memory content is injection-hardened

`json_memory_index` MUST bound the length of the quoted `description` it places in the bundle (truncating overly long values) so a pathological frontmatter line cannot bloat or smuggle payload through the index. The skill MUST treat all memory content — with `project` bodies explicitly named as the higher-risk free-form surface — as quoted data, never as instructions, and MUST write any evidence-derived proposal title and body to a file rather than interpolating them into a shell string.

#### Scenario: shell metacharacters in a memory body are never executed

- **GIVEN** a memory body containing backticks or `$( )`
- **WHEN** it is quoted into a proposal title/body
- **THEN** it is written to a file / sanitized and never executed as shell

#### Scenario: an overlong description is truncated in the index

- **GIVEN** a memory whose `description` frontmatter far exceeds the length cap
- **WHEN** the index is built
- **THEN** the emitted `description` is truncated to the bounded length

