# Capability: skill-routing

## ADDED Requirements

### Requirement: Atlassian MCP availability detection

The session-start hook MUST set the `atlassian` plugin's `.available` flag to `true` when an `atlassian` MCP server is present in either the user-scoped `mcpServers` or the current-project-scoped `projects[<workspace>].mcpServers` of `~/.claude.json`. The detection MUST NOT add `atlassian` to the context-capability set (`_CANONICAL_CAP_KEYS`) — it is a plugin-availability flag, not a context capability. The detection MUST fail open: a missing `~/.claude.json`, missing jq, or any jq error MUST leave `atlassian.available` unchanged (false) and MUST NOT abort the hook.

#### Scenario: Atlassian MCP server present
- **GIVEN** a `~/.claude.json` whose `mcpServers` (or current-project `mcpServers`) contains an `atlassian` key
- **WHEN** the session-start hook builds the registry
- **THEN** the registry cache `.plugins[]` entry named `atlassian` MUST have `available == true`

#### Scenario: No Atlassian MCP server
- **GIVEN** a `~/.claude.json` with no `atlassian` entry in any `mcpServers` scope
- **WHEN** the session-start hook builds the registry
- **THEN** the `atlassian` plugin's `available` MUST remain `false`

#### Scenario: Fail-open on unreadable config
- **GIVEN** a missing or unreadable `~/.claude.json`, or jq unavailable
- **WHEN** the session-start hook builds the registry
- **THEN** the `atlassian` plugin's `available` MUST remain `false` and the hook MUST complete normally

### Requirement: Jira branch-naming advisory hint

When the `atlassian` plugin is available AND the lowercased prompt contains a Jira-ID-shaped token matching `(^|[^a-z0-9])[a-z][a-z0-9]+-[0-9]+($|[^a-z0-9])`, the activation hook MUST emit an advisory hint instructing that the working branch be named `<type>/<JIRA-ID>` using the ticket's exact uppercase ID. The hint MUST be advisory (it MUST NOT block) and MUST be suppressed entirely when the `atlassian` plugin is unavailable. The trigger MUST self-anchor (it MUST NOT rely on `\b`, which is unavailable under Bash 3.2 ERE), because methodology-hint triggers bypass the scorer word-boundary post-filter.

#### Scenario: Jira ID mentioned with Atlassian available
- **GIVEN** the `atlassian` plugin is available
- **WHEN** a prompt contains a Jira-ID-shaped token (e.g. `PROJ-123`)
- **THEN** the activation output MUST contain the branch-naming advisory

#### Scenario: Suppressed without Atlassian
- **GIVEN** the `atlassian` plugin is unavailable
- **WHEN** a prompt contains a Jira-ID-shaped token
- **THEN** the branch-naming advisory MUST NOT be emitted

### Requirement: Jira PR-title advisory hint at SHIP

When the `atlassian` plugin is available AND `PRIMARY_PHASE == SHIP`, the activation hook MUST emit an advisory hint instructing that the Jira ID be derived from the branch name and the PR be titled `<JIRA-ID>: <exact ticket subject>`, with the subject fetched via the Atlassian MCP, and that the step be skipped (no fabricated ID) when no Jira ID is present. The hint MUST be advisory (it MUST NOT block) and MUST be suppressed when the `atlassian` plugin is unavailable.

#### Scenario: SHIP phase with Atlassian available
- **GIVEN** the `atlassian` plugin is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the activation output MUST contain the PR-title advisory (text including `JIRA PR TITLE`)

#### Scenario: Suppressed without Atlassian at SHIP
- **GIVEN** the `atlassian` plugin is unavailable
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the PR-title advisory MUST NOT be emitted
