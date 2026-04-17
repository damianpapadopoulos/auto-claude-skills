# Design: Incident Analysis v1.3

## Architecture

Extends the 3-stage pipeline (MITIGATE → INVESTIGATE → POSTMORTEM) into a 6-stage confidence-gated mitigation system (MITIGATE → CLASSIFY → HITL/INVESTIGATE loop → EXECUTE → VALIDATE → POSTMORTEM).

Full design: `docs/superpowers/specs/2026-03-23-incident-analysis-v1.3-playbooks-design.md`

## Dependencies

- signals.yaml: Central signal registry
- compatibility.yaml: Playbook category compatibility matrix (closed-by-default)
- playbooks/*.yaml: 6 bundled playbook definitions
- scripts/redact-evidence.sh: Deterministic evidence sanitizer

## Decisions & Trade-offs

- Confidence normalizes by evaluable_weight (not max_possible) — missing data affects coverage gate only
- Closed-by-default compatibility — new categories must be explicitly classified
- cas_mode: native | revalidate_only (no none — fingerprint revalidation is universal)
- All mutations go through playbook framework — no bare command escape hatch
