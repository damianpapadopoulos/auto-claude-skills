# Design: Alert Hygiene Report v3

## Architecture
The change is entirely within SKILL.md Stage 5 (report template) and the Stage 3 classification instructions. The data pipeline (Stages 0-2), prescriptive reasoning (Stage 3), metric validation (Stage 3b), coverage gap check (Stage 4), and Python scripts are unchanged.

The report follows a two-layer architecture:
1. **Decision Summary** (lead-facing): Compact table capped at 8-12 items with anchor links to detailed sections. Three row groups: Do Now, Investigate, Needs Decision.
2. **Detailed Sections** (operator-facing): Do Now with Config Diff & Derivation tables, Investigate with Two-Stage DoD, Needs Decision with owner/deadline/default recommendation.

## Dependencies
No new dependencies. Existing compute-clusters.py output (clusters, metric_types_in_inventory, unlabeled_ranking) is consumed by the new Systemic Issues section without script changes.

## Decisions & Trade-offs

### Summary + Detail vs Single Merged Table
Chose two-layer architecture (compact summary + detailed sections) over a single polymorphic table. A single table with Do Now, Investigate, and Needs Decision rows requires different column sets per row type, producing either empty cells or overloaded columns. Two layers keep the lead view clean and the operator view complete.

### Action Classes vs Confidence Bands
Replaced confidence bands (High/Medium/Low) with action classes (Do Now/Investigate/Needs Decision). Confidence is preserved as a secondary attribute (Readiness) within each class. This prevents high-confidence but underspecified items from being presented as actionable.

### Do Now Gate as Strict Operational Gate
Made Do Now a strict six-requirement gate rather than a confidence label. Items failing any requirement drop to Investigate regardless of evidence quality. This guarantees every Do Now item is PR-ready.

### Two-Stage Investigation DoD
Split investigation work into bounded discovery (Stage 1) and separate execution follow-up (Stage 2). This prevents investigations from becoming open-ended parking lots by separating hypothesis validation from implementation work.

### IaC Location: Search Required as Valid Do Now State
Allowed Search Required as a Do Now-eligible IaC status (with strict four-component requirements) rather than requiring Confirmed/Likely only. This prevents demoting solid fixes just because the analyst operates outside the infra repo.
