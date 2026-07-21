# Delta: improvement-mining — repo-agnostic classifier, noise flag, repo-type gate, injection hardening

## ADDED Requirements

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
