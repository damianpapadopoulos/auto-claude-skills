## Why
Five validated findings (2 P1, 3 P2) were identified in the incident-analysis skill where the SKILL.md had internal contradictions, drifted from its OpenSpec contract, or left safety-critical steps implicit. An agent following the skill literally could skip infrastructure-level investigation, present an incomplete HITL safety gate, produce a lossy postmortem appendix, or skip evidence persistence entirely.

## What Changes
All changes are to Markdown prose (SKILL.md, spec.md) and Bash test assertions. No runtime code changes.

- Constraint 2 (Scope Restriction) narrowed to application-level queries with an explicit infrastructure escalation exception
- High-confidence decision record template restored to match spec: added Evidence Age, VETO SIGNALS, State Fingerprint, and Explanation fields
- Step 7 synthesis instruction expanded from a single paragraph to a 6-item enumerated list covering ruled-out hypotheses, hypothesis revisions, completeness gate answers, and inventory/impact
- OpenSpec spec.md updated from "7 section headers" to "8 section headers" to match the canonical postmortem schema
- EXECUTE and VALIDATE stages now have explicit evidence persistence steps (pre.json and validate.json)

## Capabilities

### Modified Capabilities
- `incident-analysis`: Fixed 5 internal contradictions and spec drift issues in behavioral constraints, decision records, synthesis instructions, and execution flow

## Impact
- `skills/incident-analysis/SKILL.md` — 4 sections modified (Constraint 2, Decision Record, Step 7, EXECUTE/VALIDATE)
- `openspec/specs/incident-analysis/spec.md` — section count corrected
- `tests/test-skill-content.sh` — 9 new assertions (from 20 to 29)
- `tests/test-postmortem-shape.sh` — 1 new assertion (from 24 to 25)
