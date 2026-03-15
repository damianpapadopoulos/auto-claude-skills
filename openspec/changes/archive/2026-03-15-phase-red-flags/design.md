# Design: Phase-Aware RED FLAGS

## Architecture
Phase-specific RED FLAGS are injected in `_format_output()` via a `case "${PRIMARY_PHASE}"` statement. Each phase has a targeted HALT checklist appended to `SKILL_LINES`. The existing SHIP verification RED FLAGS (which check for `verification-before-completion` in SELECTED) are preserved as an additional append, not replaced.

A phase-enforcement methodology hint fires during DESIGN/PLAN phases when implementation-intent language (fix, change, refactor, etc.) is detected. The hint reinforces "complete current phase before editing."

The REVIEW phase composition sequence was expanded from 1 step (requesting-code-review) to 3 steps (requesting → agent-team-review → receiving-code-review) to clarify the review flow.

## Dependencies
No new dependencies. Uses existing RED FLAGS injection mechanism, existing methodology hint infrastructure, existing phase_compositions sequence rendering.

## Decisions & Trade-offs

### RED FLAGS vs PreToolUse hooks
A design debate (architect, critic, pragmatist) evaluated 4 approaches. PreToolUse hooks were rejected because file path classification is fuzzy, they add latency on every tool call, and superpowers deliberately chose instruction-level enforcement over programmatic blocking. RED FLAGS are proven (already work for verification), zero latency, and follow the superpowers pattern.

### Phase-enforcement hint as complement
The methodology hint adds a second signal at the routing level (in addition to RED FLAGS in the output). It fires only at DESIGN/PLAN with implementation-intent triggers, reducing noise at other phases.

### REVIEW 3-step sequence
The original REVIEW composition had only requesting-code-review as a sequence entry. Expanding to 3 steps makes the dispatch → review → process-feedback flow explicit in the hook output, preventing the model from summarizing instead of dispatching the subagent.
