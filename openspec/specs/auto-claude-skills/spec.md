## Purpose

Plugin-level safety and observability infrastructure. Shared preflight scripts, composition-state guards, and cross-cutting checks that keep every phase's tooling honest — fail-open, bash 3.2 compatible, and consistent across all hooks.

## Requirements

### Requirement: On-Demand Observability Preflight
The plugin MUST provide a shared observability preflight script at `scripts/obs-preflight.sh` that checks gcloud authentication status, kubectl cluster connectivity, and GCP Observability MCP configuration.

The script MUST output JSON with keys `gcloud`, `kubectl`, `observability_mcp`, and `summary`.

The script MUST exit 0 always (fail-open). On internal error, it MUST emit a valid JSON error object and exit 0.

#### Scenario: All tools missing
- **WHEN** gcloud, kubectl are not on PATH and ~/.claude.json has no observability MCP configured
- **THEN** output MUST contain `{"gcloud":"missing","kubectl":"missing","observability_mcp":"unavailable",...}`

#### Scenario: gcloud unauthenticated
- **WHEN** gcloud is installed but has no active credentials
- **THEN** output MUST contain `{"gcloud":"unauthenticated",...}` with summary suggesting `gcloud auth login`

### Requirement: Preflight Integration in Observability Skills
The incident-analysis skill, alert-hygiene skill, and /investigate command MUST invoke `obs-preflight.sh` before performing data collection or tier selection.

#### Scenario: Skill activation with missing auth
- **WHEN** a user invokes incident-analysis and gcloud is unauthenticated
- **THEN** the skill MUST report the preflight issue before attempting any log queries

### Requirement: REVIEW-Before-SHIP Guard
The openspec-guard hook MUST warn when `requesting-code-review` is present in the composition chain but absent from the completed list during the SHIP phase.

The guard MUST NOT warn when no composition state file exists, when the phase is not SHIP, or when requesting-code-review is not in the chain.

The guard MUST remain fail-open (exit 0 always).

#### Scenario: REVIEW skipped during SHIP
- **WHEN** a git commit is attempted during SHIP phase with requesting-code-review in chain but not completed
- **THEN** the hook MUST emit a warning containing "REVIEW GUARD"

#### Scenario: No composition state
- **WHEN** a git commit is attempted during SHIP phase with no composition state file
- **THEN** the hook MUST NOT emit a REVIEW GUARD warning
