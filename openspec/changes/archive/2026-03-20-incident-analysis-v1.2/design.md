# Design: Incident Analysis v1.2 — Postmortem Permalinks

## Architecture

Extends Stage 3, Step 3 (Generate Postmortem) of the existing SKILL.md. No new files, no routing changes, no hooks.

Two formatting rules embedded after the content bullet list:
1. **Trace IDs** → `[Trace ID](https://console.cloud.google.com/traces/list?project=PROJECT_ID&tid=TRACE_ID)`
2. **Git commits** → `[Commit SHORT_HASH](https://github.com/ORG/REPO/commit/FULL_HASH)` via runtime `git remote get-url origin`

Cross-project aware: each trace reference uses its own service's project_id.

## Dependencies
- None new. Uses `project_id` and `trace_id` already available from Stage 2.
- `git remote get-url origin` for commit links (standard git, no extra tools).

## Decisions & Trade-offs
- **Runtime git remote detection** over CLAUDE.md config — zero config, works immediately.
- **GitHub-only commit links** — non-GitHub remotes fall back to raw hash. No URL guessing.
- **Cloud Console standard URL pattern** — `console.cloud.google.com/traces/list?project=...&tid=...` is the documented deep-link.
- **Embedded in Step 3** rather than a new step — keeps step count stable, avoids renumbering.
