## Why
The incident-analysis skill generated postmortem action items without verifying whether the recommended configuration was already in place. The 2026-03-24 backend-core postmortem recommended "Add podAntiAffinity" when topologySpreadConstraints was already configured with the same intent. This produced incorrect recommendations that waste engineering time and undermine trust in the postmortem process.

## What Changes
Three targeted edits to `skills/incident-analysis/SKILL.md`:
1. Step 2b inventory expanded to capture scheduling constraints (affinity, topologySpreadConstraints, taints/tolerations) with tiered retrieval (kubectl > GitOps > flag unverified)
2. Action item format gains a "current state" field that forces the agent to document existing config before recommending changes
3. Interpretation guidance distinguishes soft vs hard enforcement and functionally equivalent mechanisms

## Capabilities

### Modified Capabilities
- `incident-analysis`: Added remediation verification — inventory expansion with scheduling constraints and "Current State" forcing function for postmortem action items

## Impact
- `skills/incident-analysis/SKILL.md`: 7 lines added, 2 lines replaced
- No playbook changes, no new files, no schema changes
- Postmortem output format gains one column ("Current State") in the action items table
