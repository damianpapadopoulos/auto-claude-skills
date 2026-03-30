## Why
The alert-hygiene skill produced actionable reports but had three gaps reducing actionability: IaC location required manual search, routing problems were surfaced as data tables rather than prescriptive findings, and SLO coverage analysis had no visibility into which services actually had SLO definitions.

## What Changes
Three enrichments to the alert-hygiene skill, all implemented as optional GitHub-dependent features with graceful degradation:
1. Stage 1 SLO config enrichment — fetches slo-config.yaml via gh API, extracts normalized service names with Ruby stdlib YAML
2. Stage 4 routing validation — promotes zero-channel policies, unlabeled high-noise policies, and label-inconsistent clusters to Investigate findings
3. Stage 4 SLO coverage cross-reference — identifies SLO migration candidates and redundancy review candidates using deterministic service_key/signal_family extraction
4. Stage 5 IaC location resolution — uses gh search code to upgrade IaC Location from Search Required to Likely

Supporting script changes add `service_key` and `signal_family` fields to compute-clusters.py output.

## Capabilities

### Modified Capabilities
- `alert-hygiene`: Extended with Terraform IaC location resolution, routing-as-hygiene validation, and SLO coverage cross-referencing

## Impact
- `skills/alert-hygiene/SKILL.md` — 132 new lines of analysis instructions across Stages 1, 4, and 5
- `skills/alert-hygiene/scripts/compute-clusters.py` — 3 new functions (normalize_service_name, extract_service_key, classify_signal_family) + 2 new output fields
- `tests/test-alert-hygiene-scripts.sh` — 8 new test scenarios including cross-language normalization contract
- `tests/test-alert-hygiene-skill-content.sh` — 16 new content assertions
