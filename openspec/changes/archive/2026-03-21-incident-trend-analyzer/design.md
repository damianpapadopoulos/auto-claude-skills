# Design: Incident Trend Analyzer

## Architecture
Standalone prompt-driven skill (`skills/incident-trend-analyzer/SKILL.md`) with domain-role routing entry in `config/default-triggers.json`. No helper scripts or external dependencies — the LLM reads postmortem files directly and performs analysis in-context.

Data flow: `docs/postmortems/*.md` (non-recursive) → parser (raw section extraction) → analysis engine (normalized incident records) → metric computation → terminal summary output.

## Dependencies
- Depends on `incident-analysis` v1.0+ for canonical postmortem schema (7-section format)
- No new packages, APIs, or database changes
- Routing entry uses existing skill-activation-hook scoring infrastructure

## Decisions & Trade-offs

### Standalone skill vs embedded Stage 4
Chose standalone because aggregation and investigation are fundamentally different interaction patterns (batch reads vs live systems). Keeps incident-analysis focused on reactive debugging.

### Parser/engine separation
Parser extracts raw sections; analysis engine interprets them. This makes the pipeline auditable and prevents coupling between extraction and classification.

### Tiered eligibility
Rather than requiring all sections for any analysis, eligibility is tiered (recurrence → timeline → MTTR → MTTD). Avoids discarding partial postmortems that lack timeline data but have valid recurrence signals.

### Vocabulary-key grouping
Failure modes use a fixed 8-key vocabulary. Raw text shown as evidence but never used as grouping key. Prevents wording differences from fragmenting recurrence groups.

### Terminal-first output
Default is ephemeral terminal summary. Persist only on explicit request. Avoids write-amplification for exploratory analysis.
