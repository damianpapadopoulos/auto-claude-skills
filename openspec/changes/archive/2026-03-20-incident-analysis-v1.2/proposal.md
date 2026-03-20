# Proposal: Incident Analysis v1.2 — Postmortem Permalinks

## Problem Statement
The v1.0/v1.1 postmortem output used raw text for trace IDs and commit hashes, forcing readers to manually copy-paste into Cloud Console or GitHub. The Palladius postmortem-generator pattern mandates "USE PERMALINKS" for all external references.

## Proposed Solution
Add two permalink formatting rules to Stage 3, Step 3 (Generate Postmortem). Both use data already available from Stage 2 — zero extra tool calls.
- Trace IDs as clickable Cloud Console links
- Git commits as clickable GitHub links (with runtime remote detection)

## Out of Scope
- Log entry permalinks (no stable Cloud Console URL pattern confirmed)
- Non-GitHub git providers (fallback to raw hash)
- Action item taxonomy (Mitigate/Detect/Prevent — separate feature)
