## Why
The incident-analysis SKILL.md had grown to 12,806 words — 25x over the writing-skills recommended target for non-heavy-reference skills. Reference-like material (error taxonomy tables, exit code guides, conditional investigation branches) was inline alongside the investigation spine, making the file harder to scan and consuming excessive context when loaded.

## What Changes
Reduced SKILL.md from 12,806 to 11,408 words (~11%) through targeted extractions, prose compression, and a stage-transition flowchart. Two new reference files hold extracted content. 18 new tests verify content preservation and navigation-chain integrity.

## Capabilities

### Modified Capabilities
- `incident-analysis`: Refactored skill structure — extracted reference material to dedicated files, compressed behavioral constraint prose, added stage-flow visualization. No behavioral changes to the investigation pipeline.

## Impact
- `skills/incident-analysis/SKILL.md` — reduced by ~1,400 words
- `skills/incident-analysis/references/error-taxonomy.md` — new (616 words)
- `skills/incident-analysis/references/deep-dive-branches.md` — new (691 words)
- `tests/test-incident-analysis-content.sh` — 18 new assertions (170 → 188)
- `CLAUDE.md` — word count guard reference updated
