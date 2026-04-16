## Why

The plugin's SDLC loop had a hard break between DISCOVER and LEARN. `product-discovery` output an ephemeral in-chat brief with no durable artifact. `outcome-review` referenced a `~/.claude/.skill-learn-baselines/` directory that nothing ever wrote to. Shipped features could not be validated against their original hypotheses because the hypotheses did not survive the session.

## What Changes

Threads a durable hypothesis artifact from DISCOVER through to LEARN via six targeted edits:

1. **product-discovery** gains a Hypotheses section in the brief template (Metric, Baseline, Target, Window fields)
2. **DISCOVER composition** gains a PERSIST DISCOVERY hint matching the existing DESIGN persistence pattern
3. **openspec-state.sh** gains a `openspec_state_set_discovery_path` helper for targeted jq merge
4. **openspec-ship** gains Step 7a-bis (hypothesis extraction into session state) and discovery_path in Step 7b archival
5. **SHIP composition** gains a `write-learn-baseline` terminal step that detects ship events from git state
6. **outcome-review** gains hypothesis-guided metric queries and a Hypothesis Validation table in the report

## Capabilities

### New Capabilities
- `hypothesis-loop`: Durable hypothesis artifact contract from DISCOVER through SHIP to LEARN. Structured fields (Metric, Baseline, Target, Window) persist as session state, get denormalized into learn-baseline JSON, and are consumed by outcome-review for per-hypothesis validation.

### Modified Capabilities
- `product-discovery`: Brief template extended with Hypotheses section
- `openspec-ship`: New Step 7a-bis extracts hypotheses; Step 7b archives discovery artifacts
- `outcome-review`: Consumes learn-baseline hypotheses for targeted metric queries and validation table
- `openspec-state`: New helper function, discovery_path in provenance output

## Impact

- **Skills modified:** product-discovery, openspec-ship, outcome-review (SKILL.md only)
- **Libraries modified:** hooks/lib/openspec-state.sh (additive — new function + provenance field)
- **Config modified:** default-triggers.json, fallback-registry.json (composition hints + SHIP sequence)
- **New files:** 3 test files (test-discovery-content.sh, test-openspec-ship-hypothesis.sh, test-outcome-review-content.sh)
- **Zero Superpowers files modified**
