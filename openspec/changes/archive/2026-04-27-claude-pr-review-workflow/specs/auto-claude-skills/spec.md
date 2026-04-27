## ADDED Requirements

### Requirement: CI-Time PR Review Backstop
The plugin MUST provide a GitHub Actions workflow at `.github/workflows/claude-code-review.yml` that runs `anthropics/claude-code-action` against every pull request touching plugin code (`skills/`, `commands/`, `hooks/`, `config/`, `scripts/`, `.claude-plugin/`, `.github/workflows/`, `CLAUDE.md`, `AGENTS.md`, `docs/eval-pack-schema.md`).

The workflow MUST be a **backstop**, not a replacement, for the in-session `requesting-code-review` step. The composition chain's in-session review remains the primary SDLC gate; the CI workflow catches PRs created without an active session.

The review prompt MUST encode the plugin's CLAUDE.md conventions: bash 3.2 compatibility, fail-open routing hooks, jq-optional fallback, US/SOH field separators, the 11,500-word `incident-analysis` ceiling, the `disable-model-invocation` rule for action-only skills, scope-duplication detection across existing skills, grep-`-F` for literal regex characters in runtime-output parsers, and a GitHub Actions security checklist (full peeled-SHA pinning for third-party actions, lockstep across workflows, env-block pattern for user inputs, fork-PR refusal, permission API gate, allowlist over denylist for tool restrictions).

#### Scenario: PR opened against plugin paths
- **WHEN** a pull request is opened or synchronized against a path matching `skills/**`, `hooks/**`, `config/**`, `.claude-plugin/**`, `.github/workflows/**`, or other listed plugin paths
- **THEN** the `claude-code-review.yml` workflow MUST trigger
- **AND** post exactly one structured review comment per push (deleting any prior review comment from the same workflow)

#### Scenario: PR with no plugin paths touched
- **WHEN** a pull request changes only documentation outside the listed paths (e.g., `README.md`, top-level `LICENSE`)
- **THEN** the workflow MUST NOT trigger

#### Scenario: Workflow paths touched without skill changes
- **WHEN** a pull request changes only `.github/workflows/*.yml`
- **THEN** the workflow MUST trigger
- **AND** the review prompt MUST receive `touched_workflows == true` so the GitHub Actions security checklist activates

### Requirement: Fork-PR Review Refusal
Workflows that access repository secrets and run against PR-derived code MUST include a fork-PR refusal step that compares `github.event.pull_request.head.repo.full_name` against `github.repository` and aborts before any subsequent step that touches secrets when the values differ.

The trigger MUST be `pull_request`, NOT `pull_request_target`. The `pull_request_target` event combined with checking out `pull_request.head.sha` is the classic exfiltration pattern and is forbidden.

#### Scenario: Fork PR opened
- **WHEN** an external contributor opens a PR from a fork
- **THEN** the workflow MUST emit a `::notice::` explaining the refusal
- **AND** MUST NOT execute any step that handles `CLAUDE_CODE_OAUTH_TOKEN` or other secrets

### Requirement: Action-Layer Tool Allowlist
The `claude-code-review.yml` workflow MUST restrict the action's tool surface via `claude_args --allowed-tools '<list>'` rather than `--disallowed-tools`. The allowlist MUST be the minimum set required for read-only review (`Read`, `Grep`, `Glob`, plus exact read-only Bash patterns such as `Bash(wc:*)`, `Bash(git diff:*)`, `Bash(git log:*)`, `Bash(git status:*)`, `Bash(git rev-parse:*)`).

Allowlist enforcement MUST be at the action layer, not relied upon as prompt-only guidance. Prompt text MAY explain the boundary for clarity but MUST NOT be the boundary itself.

#### Scenario: Adversarial PR attempts to invoke disallowed tool
- **WHEN** the review action is run against a PR whose contents instruct Claude to fetch a URL via `WebFetch` or run `gh api` to exfiltrate
- **THEN** the action layer MUST reject the tool invocation
- **AND** the model's attempt MUST NOT reach the GitHub or external network

### Requirement: Peeled Commit SHA Pinning
Third-party GitHub Actions that receive secrets or execute code from PR diffs (i.e., publishers other than `actions/` and `github/` orgs) MUST pin to a full 40-character peeled commit SHA, NOT the tag-object SHA, NOT a branch, NOT a short SHA.

The bump procedure MUST be a two-step peel: `gh api repos/<owner>/<repo>/git/refs/tags/<tag>` returns the annotated tag object SHA; `gh api repos/<owner>/<repo>/git/tags/<obj>` returns `.object.sha` which is the actual commit. Workflow comments MUST document this procedure.

GitHub-published actions (`actions/`, `github/` org publishers) on major-version tags are acceptable; SHA-pinning them is good hygiene but not required by this requirement.

#### Scenario: Bumping `claude-code-action`
- **WHEN** a contributor wants to bump the `anthropics/claude-code-action` pin
- **THEN** they MUST follow the peel procedure documented in `claude-code-review.yml`
- **AND** update all three workflows (`claude-code-review.yml`, `claude.yml`, `skill-eval.yml`) in the same change so SHAs remain in lockstep

### Requirement: `@claude` Assistant Hardening
The `.github/workflows/claude.yml` workflow MUST gate every `@claude` invocation through:
1. An `author_association` allow-list (`OWNER`, `MEMBER`, `COLLABORATOR`) as a cheap pre-filter in the job `if:` condition.
2. An authoritative permission API check (`gh api /repos/.../collaborators/<actor>/permission`) requiring `admin|write|maintain` as the first job step.
3. A fork-PR refusal step covering all four event types (`issue_comment`, `pull_request_review_comment`, `pull_request_review`, `issues`).

User-controlled inputs (comment body, issue title, branch name, etc.) MUST flow through `env:` blocks and be referenced as `"$VAR"` in `run:` shell, never as direct `${{ github.event.* }}` substitution.

The workflow MUST NOT request `id-token: write` permission unless the action is configured for OIDC token exchange (Bedrock/Vertex/Foundry). With `claude_code_oauth_token` authentication, OIDC is unused.

#### Scenario: Triage-role user mentions @claude
- **WHEN** a user with only triage permission comments `@claude fix this` on a PR
- **THEN** the `author_association` pre-filter may pass (triage may surface as COLLABORATOR in some configurations)
- **AND** the permission API check MUST reject with `permission == 'triage'`
- **AND** the workflow MUST NOT execute the action step

#### Scenario: Trusted user mentions @claude on a fork PR
- **WHEN** a maintainer comments `@claude` on a PR whose head is from a fork
- **THEN** the fork-PR refusal step MUST abort before checkout
- **AND** secrets MUST NOT be exposed to fork-derived code
