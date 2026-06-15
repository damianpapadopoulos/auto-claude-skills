# Capability: skill-routing

## ADDED Requirements

### Requirement: SHIP-phase no-work advisory

When the activation hook derives `PRIMARY_PHASE == SHIP`, it MUST emit an advisory `PHASE REALITY:` line if the repository shows no committed work — specifically when `git rev-list --count origin/main..HEAD` is `0` AND `git status --porcelain` is empty. The advisory MUST be informational (`[i]`), MUST NOT block, and MUST be appended to the activation context (the same channel as the design-guard advisory). The check MUST be gated to SHIP only (it MUST NOT run at REVIEW or any other phase). The check MUST fail open: if the commit count is non-numeric (detached HEAD, no `origin/main`, fresh clone, or any git error) OR the working tree is dirty OR commits exist ahead of `origin/main`, the hook MUST emit no advisory line and MUST NOT error.

#### Scenario: SHIP claimed with no committed work
- **GIVEN** a git repository on a branch with 0 commits ahead of `origin/main` and a clean working tree
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the activation output MUST contain a `PHASE REALITY:` advisory noting no committed work exists
- **AND** the hook MUST NOT block or deny anything

#### Scenario: Silent when committed work exists
- **GIVEN** a git repository with at least one commit ahead of `origin/main` OR a non-empty `git status --porcelain`
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the no-work advisory MUST NOT be emitted

#### Scenario: Fail-open when origin/main is unresolvable
- **GIVEN** a detached HEAD, a repository with no `origin/main` ref, or any git error resolving the commit count
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the no-work advisory MUST NOT be emitted and the hook MUST exit normally (routing proceeds unaffected)

### Requirement: SHIP-phase REVIEW-skip advisory

When the activation hook derives `PRIMARY_PHASE == SHIP` and a composition state file exists for the session whose `.chain` contains `requesting-code-review` but whose `.completed` does not, the hook MUST emit an advisory `PHASE REALITY:` line noting that REVIEW has not completed before SHIP. The advisory MUST be informational (`[i]`) and MUST NOT block. The rule MUST be self-scoping: it MUST check `.chain` membership so that chains which never included `requesting-code-review` do not fire. The check MUST fail open: a missing state file, malformed JSON, missing jq, or stale/foreign composition state MUST result in no advisory line. Because composition state is only written for multi-skill chains, this rule is SILENT when no chain exists — that case is covered by the no-work advisory, and the implementation MUST document this so it is not mistaken for a bug.

#### Scenario: SHIP claimed but chain skipped REVIEW
- **GIVEN** a composition state file whose `.chain` includes `requesting-code-review` and whose `.completed` does not include it
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the activation output MUST contain a `PHASE REALITY:` advisory noting REVIEW has not completed
- **AND** the hook MUST NOT block

#### Scenario: Silent with no active chain
- **GIVEN** no composition state file exists for the session (single-skill or no-skill prompt)
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the REVIEW-skip advisory MUST NOT be emitted (the no-work advisory may still fire independently)

#### Scenario: Silent at non-SHIP phases
- **GIVEN** any `PRIMARY_PHASE` other than SHIP (e.g. REVIEW, IMPLEMENT, DESIGN)
- **WHEN** the activation hook runs
- **THEN** neither phase-reality advisory MUST be emitted and no git or composition-state checks for this feature MUST run
