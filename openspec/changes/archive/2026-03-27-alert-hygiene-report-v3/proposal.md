## Why
The alert-hygiene report grouped findings by confidence band (High/Medium/Needs Analyst) with separate Track A/B priority tables. This structure made it hard for leads to triage quickly and did not guarantee that high-confidence items were actually PR-ready. Engineers receiving "High-Confidence" findings still had to interpret vague recommendations, hunt for IaC locations, and guess at success criteria.

## What Changes
Restructured the report from confidence-band grouping to action-class grouping (Do Now / Investigate / Needs Decision) with strict gating rules. Do Now items must pass a six-requirement gate to ensure they are PR-ready. Investigate items use a two-stage DoD to prevent parking-lot investigations. Needs Decision items require named owners and advisory deadlines. A compact Decision Summary table replaces Track A/B for lead-facing triage.

## Capabilities

### Modified Capabilities
- `alert-hygiene`: Report template restructured from confidence bands to action classes with strict Do Now gating, two-stage investigation DoDs, verification scorecard, and systemic issues consolidation.

## Impact
- `skills/alert-hygiene/SKILL.md`: Report Skeleton, Per-Item Templates, Confidence Levels, Stage 5 instructions all replaced. New sections: Decision Summary, Systemic Issues, Verification Scorecard, Global Implementation Standard, Do Now Gate, IaC Location Rules, Metric Families.
- `tests/test-alert-hygiene-skill-content.sh`: Assertions updated from 70 to 108 covering structural and behavioral contracts.
- No script changes. No data pipeline changes. No breaking changes to upstream consumers.
