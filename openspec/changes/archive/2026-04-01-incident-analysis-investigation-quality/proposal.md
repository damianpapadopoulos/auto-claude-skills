## Why
The incident-analysis skill's investigation pipeline produced high-quality root cause hypotheses
but had four gaps in how evidence was extracted, correlated, and carried into postmortems.
Timeline reconstruction relied on LLM attention over prior conversation (events got dropped),
source analysis was code-centric without cross-referencing production logs, expansion stopped
at the stack-frame file, and config-change incidents skipped source analysis entirely.

Identified by comparing against Google's SRE Gemini CLI workflow and Palladius's
postmortem-generator/cloud-build-investigation skills, validated against the SpiceDB
postmortem (2026-03-09).

## What Changes
Four additive improvements to the INVESTIGATE and POSTMORTEM stages:
- **Step 6b Timeline Extraction:** Structured extraction of candidate timeline events with
  time_precision labels and dedupe rules before synthesis
- **Step 4.5 Cross-Reference:** Regression candidates annotated with explains_patterns and
  cannot_explain_patterns linking commits to observed log errors
- **Step 4.5b Bounded Expansion:** Same-commit and same-package expansion when primary
  stack-frame analysis finds no regression candidate
- **Step 4b Gate Expansion:** Config-change trigger using existing signal plus user override,
  both requiring repo-backed git ref

## Capabilities

### Modified Capabilities
- `incident-analysis`: Improved source analysis quality (Steps 4.5, 4.5b), broader trigger
  coverage (config-change gate), and structured timeline extraction (Step 6b)

## Impact
- `skills/incident-analysis/SKILL.md` — Step 6b, expanded Step 4b gate, updated procedure summary
- `skills/incident-analysis/references/source-analysis.md` — Steps 4.5, 4.5b, expanded gate, three output shapes
- `tests/test-incident-analysis-output.sh` — Six new fixture assertions with jq has() for false/null
- `tests/fixtures/incident-analysis/` — SpiceDB fixture extended, README updated
