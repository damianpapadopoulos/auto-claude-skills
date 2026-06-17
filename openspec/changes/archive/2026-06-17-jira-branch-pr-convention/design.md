# Design: Jira Branch + PR Naming Convention (advisory)

## Architecture

The prompt is lowercased before all trigger matching (`hooks/skill-activation-hook.sh:78`). Triggers are authored lowercase; hint text instructs the model to use the original uppercase ticket ID (the model sees the un-lowercased prompt) for the branch and PR title.

Two advisory injection points, gated on Atlassian plugin availability:

1. **Branch-time (on Jira-ID mention).** A `methodology_hints[]` entry `jira-branch-convention`. Trigger regex `(^|[^a-z0-9])[a-z][a-z0-9]+-[0-9]+($|[^a-z0-9])` — self-anchored because `methodology_hints` triggers bypass the scorer word-boundary post-filter (Bash 3.2 ERE has no `\b`). Emitted only when the `atlassian` plugin is in the available set (emitter `skill-activation-hook.sh:1234-1237`).

2. **SHIP-time (PR creation).** A `phase_compositions.SHIP.hints[]` entry, plugin-gated on `atlassian` (emitter `skill-activation-hook.sh:1326-1332`). Fires at SHIP independent of the prompt.

Prerequisite: `session-start-hook.sh` flips `atlassian.available=true` when an `atlassian` MCP server is present in `~/.claude.json` (user- or current-project-scoped). Without this, the gate — and three pre-existing atlassian-gated entries — never fire.

## Dependencies

No new packages. Relies on the Atlassian Rovo MCP (claude.ai-managed) for the model to fetch the live ticket subject; absence degrades gracefully (hints suppressed / "skip — don't fabricate").

## Decisions & Trade-offs

- **Advisory only, no hard gate.** Hooks can't run an LLM, reach Jira, or intercept `gh pr create`; "exact subject" is inherently advisory. Consistent with the `project-verification` lesson (enforcement is unsolvable in-hook).
- **Plugin-gate as the noise control.** `[a-z]{2,}-[0-9]+`-shaped tokens (`utf-8`, `sha-256`) match the regex by design; the Atlassian plugin-gate suppresses them for non-Jira repos. The regex stays readable rather than over-tightened. These tokens are therefore NOT listed as fixture NO_MATCH lines (that would contradict the regex); the design decision is documented in the fixture header.
- **Commit-message prefixing dropped.** Avoids colliding with Conventional Commits (`<type>: <description>`).
- **Fix the latent gate bug as a prerequisite** rather than gating differently — repairs three dormant entries as an intended side effect.

## Implementation Notes (synced at ship time)

- Atlassian detection mirrors the posthog/serena MCP-fallback exact-key match (`has("atlassian")`); the managed-integration server key is `atlassian` by convention. Users who rename it can force availability via `skill-config.json`.
- Task 4 (fallback regeneration) was folded into the Task 3 commit; the in-sync test (`test_fallback_registry_in_sync_with_default_triggers`) passes.
- Final whole-branch review (opus): Ready to merge — Yes, 0 Critical/Important, 2 optional cosmetic Minors, no blocking governance findings. Full suite 59/59 files.
