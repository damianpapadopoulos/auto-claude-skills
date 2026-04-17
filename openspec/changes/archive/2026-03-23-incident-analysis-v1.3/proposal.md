# Incident Analysis v1.3: Confidence-Gated Playbooks

## Why

Current skill has no structured mitigation framework. Investigation stops at root cause hypothesis; no playbook selection, evidence capture, or post-execution validation. The gap between "I found the problem" and "I fixed the problem" is unstructured and lacks safety guarantees.

## What Changes

Confidence-gated playbooks with evidence capture and validation:
- Adds CLASSIFY, EXECUTE, VALIDATE stages to the state machine
- Bundled YAML playbooks (3 commandable, 3 investigation-only) with repo-local overrides
- Central signal registry with structured detection parameters
- Three-tier eligibility (proposal_eligible, classification_credible, unscored)
- Sanitized evidence bundles with deterministic redaction
- Two-phase post-execution validation (stabilization + observation)
- Compact decision record format for on-call engineers

## Out of Scope

- Historical confidence calibration (requires outcome telemetry)
- Non-kubectl playbooks (gcloud, gh CLI, WAF)
- Evidence-bundle ingestion by incident-trend-analyzer
- Multi-hop trace correlation beyond one hop
