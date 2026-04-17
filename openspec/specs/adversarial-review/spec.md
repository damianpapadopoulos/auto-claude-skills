## ADDED Requirements

### Requirement: Always-On Adversarial Checklist
The REVIEW phase composition MUST include an always-on adversarial checklist hint with governance checks for HITL bypass, scope expansion, safety gate weakening, bypass patterns, and hook/config changes. The checklist MUST fire on every code review, not only pattern-matched reviews.

#### Scenario: Checklist reaches code-reviewer
- **WHEN** the REVIEW composition fires requesting-code-review
- **THEN** the code-reviewer's context includes the ADVERSARIAL REVIEW checklist

### Requirement: Adversarial-Reviewer Specialist
agent-team-review MUST include an adversarial-reviewer template as a 4th specialist alongside security-reviewer, quality-reviewer, and spec-reviewer. The adversarial-reviewer MUST use the same FINDING communication contract with a `governance` category.

#### Scenario: Governance reviewer spawned for large changes
- **WHEN** agent-team-review fires for a 5+ file change
- **THEN** an adversarial-reviewer is spawned with governance-focused instructions

### Requirement: Governance Regression Tests
The test suite MUST include content assertions verifying that key skills contain their governance constraints. The scenario eval suite MUST include adversarial routing fixtures testing that governance-sensitive prompts route through safety skills.

#### Scenario: Constraint removal detected
- **WHEN** a developer removes "lethal trifecta" from agent-safety-review
- **THEN** test-adversarial-governance.sh fails
