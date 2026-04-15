# Design: Incident-Analysis Skill Refactor

## Architecture
The refactor applies a "spine + references" pattern: SKILL.md retains the investigation flow (stages, steps, constraints, hypothesis formulation) as the spine that every invocation reads, while reference-lookup material (taxonomy tables, conditional sub-playbook procedures) moves to dedicated files under `references/`. Compressed pointer paragraphs in the spine summarize routing decisions and link to the full reference.

## Dependencies
No new dependencies. Uses existing `references/` directory convention and `tests/test-incident-analysis-content.sh` test infrastructure.

## Decisions & Trade-offs

**Keep all 13 behavioral constraints inline** — Constraints are guardrails, not reference material. Compressing their prose (−338 words) preserves the safety contract while reducing size.

**Extract error taxonomy + exit codes vs. keep inline** — The 3-tier table and exit code guide are lookup material used only when specific signals are present. Pointer text preserves routing terms (exit codes 137/139/143, tier names, "Message broker signals always Tier 1") so agents can make decisions without reading the reference.

**Extract CrashLoopBackOff/probe/pod-start branches vs. keep inline** — These are step-by-step procedures that behave like sub-playbooks. The pointer preserves the redirect conditions (OOMKilled → resource, deploy → bad-release) while the detailed procedures live in the reference file.

**Constraint 7 replacement table removed** — The 4-row table showing "likely caused by X" → replacements was cut for 60-word savings. The generic rule ("replace with evidence-backed language or move to open_questions") covers the same ground. Trade-off: less scannable, but the self-check procedure remains intact with its remediation clause.

**Word count guard at 11,500 (not 11,000)** — Honest math based on actual extraction sizes and pointer additions. Leaves ~100 words of headroom. Phase 2 candidates identified for further reduction if needed.
