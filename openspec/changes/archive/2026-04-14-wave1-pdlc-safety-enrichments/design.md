# Design: Wave 1 PDLC Safety Enrichments

## Architecture

All three new skills are domain skills routed via config entries in `default-triggers.json` and `fallback-registry.json`. No hook modifications, no new phases, no process skill additions. The hook's existing scoring engine (regex trigger match + priority + role-cap selection) handles the new skills without any code changes.

The scenario-eval suite uses fixture-based testing: JSON files define prompt, expected_skills, expected_phase, expected_in_composition, and must_not_match assertions. The runner loads the production fallback-registry and runs the hook against each fixture.

## Dependencies

No new external dependencies. All additions are Bash 3.2 compatible SKILL.md files, JSON config entries, and shell test scripts.

## Decisions & Trade-offs

**Domain skills only, no process competition:** The superpowers plugin owns the workflow backbone. The architecture rule locks driver invariants (DESIGN=brainstorming, PLAN=writing-plans, etc.). All Wave 1 additions are domain skills that co-select alongside process drivers, never displacing them. This was validated via driver-invariant tests and scenario evals.

**prototype-lab as trigger-based co-selection, not brainstorming escalation:** The initial design proposed prototype-lab as an escalation from brainstorming (like design-debate). Review identified this was not implementable because superpowers owns brainstorming and we cannot modify its internal chaining. Revised to narrow trigger-based co-selection with DESIGN phase guidance hints.

**starter-template phase anchor DESIGN only:** The initial design proposed PLAN/IMPLEMENT dual phase anchor. Review identified that the registry treats phase as a single scalar. Revised to DESIGN (co-selects with writing-skills) with cross-phase usage described as guidance.

**Process skeleton restriction:** starter-template restricts process skeletons to DISCOVER and LEARN edge overlays only. A warning is emitted if the user requests a process skeleton for a superpowers-owned phase.

**Scenario evals use fallback-registry, not synthetic test registry:** This tests against the production registry shape but means superpowers skills marked `available: false` can't be tested. Guardrail scenarios were adapted to test available skills while preserving semantic intent.

**agent-safety-review separate from security-scanner:** Architectural risk assessment (LLM-driven, design-time) is fundamentally different from deterministic static analysis (tool-driven, review-time). Merging them would dilute both.
