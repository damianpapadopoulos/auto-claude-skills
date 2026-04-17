# Design: Adversarial Review Lens

## Architecture

Three components compose into one governance layer:

- **Path A (all reviews):** REVIEW composition hint with 6-point adversarial checklist. Always-on — the LLM reviewer evaluates these alongside its normal review. Reaches the code-reviewer subagent via the composition hint system without modifying the Superpowers skill.
- **Path B (large reviews):** adversarial-reviewer specialist template in agent-team-review. Spawned as 4th reviewer for 5+ file changes. Uses same FINDING format and communication contract as other reviewers.
- **Path C (regression testing):** Routing scenario fixtures (4 adversarial prompts) + content assertion tests (10 governance constraints). Catches "wrong skill fires" and "skill lost its constraint" regressions.

## Dependencies

No new dependencies. Uses existing composition hint system, agent-team-review spawn pattern, scenario eval framework, and content assertion pattern.

## Decisions & Trade-offs

- **Always-on over pattern-triggered:** The adversarial checklist fires on every review rather than only when governance-sensitive patterns are detected. Pattern detection is fragile and will miss cases; 6 questions are cheap enough to evaluate every time.
- **Composition hint over skill modification:** The checklist augments the Superpowers-owned requesting-code-review via a hint, not by editing the skill. Zero Superpowers files modified.
- **Phase assertions omitted for ambiguous routing:** Scenario fixtures 19 and 20 omit `expected_phase` because their prompts trigger skills from multiple phases, producing an unresolved `[PHASE]` placeholder in the test environment. Skill presence assertions are what matter for governance coverage.
