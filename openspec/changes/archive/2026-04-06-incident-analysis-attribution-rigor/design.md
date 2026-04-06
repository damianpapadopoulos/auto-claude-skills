# Design: Attribution Rigor Upgrade

## Architecture
Targeted insertions into the existing SKILL.md investigation flow, not a structural refactor. The attribution proof integrates into Step 5 (hypothesis validation) where it logically belongs — after trace correlation, before synthesis. The YAML schema extension is additive (optional field, only required for 2+ services).

## Dependencies
No new packages or APIs. Uses existing test infrastructure (test-helpers.sh, jq-based fixture validation).

## Decisions & Trade-offs
- **Targeted insertions over rewrite**: Preserves existing flow, minimizes regression risk. 5 insertion points rather than restructuring the investigation stages.
- **4-state model over binary**: `confirmed-dependent / independent / inconclusive / not-investigated` captures the nuance of partial evidence. Binary "dependent/independent" would force premature conclusions when evidence is ambiguous or tools are unavailable.
- **Behavioral constraint over post-hoc check**: Banning speculative language at the constraint level (Constraint 7) prevents the problem at generation time rather than catching it after synthesis. Self-check instruction acts as a guardrail.
- **Optional service_attribution block**: Only required for multi-service incidents. Q10 is in the "not assessed" pool (questions 4-10), so single-service investigations are unaffected.
- **Baseline-relative comparison over fixed thresholds**: Step 3 application-logic analysis compares against baseline rather than using arbitrary thresholds (e.g., "40% gRPC skew"), which would be unproven and fragile.
