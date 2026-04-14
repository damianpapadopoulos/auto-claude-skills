## Why

The auto-claude-skills SDLC backbone (TDD, routing, review, phase composition) was mature but had gaps upstream and cross-cutting: no runnable prototyping in DESIGN, no architectural safety analysis for autonomous agent designs, no skill skeleton for consistent new additions, and no suite-level behavioral evaluation of routing judgment. These gaps were identified by mapping Simon Willison's agentic engineering practices against the current plugin capabilities.

## What Changes

Added three DESIGN-phase domain skills and a scenario-eval test suite to enrich the plugin's PDLC coverage without altering the superpowers workflow backbone.

- **starter-template**: Emits repo-native seed files (SKILL.md skeleton, routing entry, test snippets) when creating new skills, commands, or plugins. Ensures agents follow existing patterns from the first file.
- **prototype-lab**: Produces 3 thin comparable variants of a proposed design with a comparison artifact and mandatory Human Validation Plan. Fires alongside brainstorming, never displaces it.
- **agent-safety-review**: Evaluates designs involving autonomous agents for the lethal trifecta (private data + untrusted input + outbound action). Recommends blast-radius controls, not detection scores.
- **scenario-evals**: 12-scenario behavioral test suite validating routing judgment, safety interception, guardrail preservation, and driver-invariant protection.

## Capabilities

### New Capabilities
- `pdlc-safety`: Three domain skills enriching the DESIGN phase with prototyping, safety review, and skill templating, plus suite-level behavioral evaluation

### Modified Capabilities
- `unified-context-stack`: DESIGN phase guidance updated with prototype-lab and agent-safety-review awareness hints

## Impact

- `config/default-triggers.json`: 3 new skill routing entries
- `config/fallback-registry.json`: 3 matching fallback entries (base state preserved)
- `skills/`: 3 new SKILL.md files
- `skills/unified-context-stack/phases/design.md`: 2 new awareness sections
- `tests/`: 1 new test runner + 12 scenario fixtures + 6 new routing tests
- No changes to hooks, phase_guide, phase_compositions, or superpowers skills
