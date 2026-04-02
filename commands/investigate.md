---
description: Launch a systematic incident investigation
argument-hint: "Service name and symptoms (e.g., 'user-service 500s in hb-prod')"
---

Launch the incident-analysis skill for a systematic, evidence-based investigation of a
production incident.

## What Happens

1. The skill detects available tools (MCP, gcloud CLI, or guidance-only)
2. Establishes scope: service, environment, time window from your input
3. Runs inventory and impact quantification (MITIGATE stage)
4. Classifies the incident against playbooks (CLASSIFY stage)
5. Investigates with targeted queries (INVESTIGATE stage)
6. If remediation is needed, presents playbook with HITL gate (EXECUTE stage)
7. Validates post-mitigation (VALIDATE stage)
8. Generates structured postmortem (POSTMORTEM stage)

## Usage

**With arguments:**
The `$ARGUMENTS` are passed as initial context. Include the service name, environment, and
symptoms.

**Without arguments:**
The skill will ask for incident details interactively.

## Steps

1. Load the `incident-analysis` skill using the Skill tool.
2. **Preflight:** Before entering Stage 1, run the observability preflight:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/obs-preflight.sh"
   ```
   Report any issues from the `summary` field. If `gcloud` is `unauthenticated`, resolve auth before proceeding.
3. Begin at Stage 1 — MITIGATE. Pre-populate scope from `$ARGUMENTS`:
   - Extract service name, environment (hb-prod, dg-prod, etc.), and symptoms
   - Convert any local times to UTC
   - Pass extracted context as MITIGATE Step 2 (Establish Scope) inputs
4. Follow the full investigation pipeline as defined in the skill.

## Important

- All investigation is **read-only** by default
- Remediation actions require **explicit user approval** (HITL gate)
- Must not bypass MITIGATE steps (tool detection, inventory, impact quantification)
