# Proposal: Jira Branch + PR Naming Convention (advisory)

## Why

The plugin already wires Jira into DISCOVER (`product-discovery`) and LEARN (`outcome-review`), but nothing tied **branch names** or **PR titles** back to the Jira ticket that sourced the work. When a Jira ticket is the unit of work, branches and PRs should reflect it so the ticket ↔ code ↔ review trail is traceable.

A second, latent problem surfaced during design: the `"plugin": "atlassian"` availability gate never fired. `hooks/session-start-hook.sh` detects serena/forgetful/context7/posthog MCP servers from `~/.claude.json`, but had no detection for `atlassian` (a `claude-ai-managed` plugin, absent from the installed-plugin scan and not a context_capability). Its `.available` was permanently `false`, so three pre-existing atlassian-gated entries (DISCOVER hint, DISCOVER `searchJiraIssuesUsingJql` parallel, LEARN `createJiraIssue` parallel) were dead.

## What Changes

Add an **advisory-only**, fail-open Jira convention with two injection points in `config/default-triggers.json`, plus the prerequisite detection that makes the gate real:

- **Atlassian MCP detection** (`session-start-hook.sh`): flip the `atlassian` plugin `.available=true` when an `atlassian` MCP server is present in user- or current-project-scoped `mcpServers`. Mirrors the serena/posthog fallback pattern, fail-open. Side effect: revives the three dormant atlassian-gated entries (intended).
- **Branch-naming hint** (`methodology_hints[]`): fires on a lowercased Jira-ID-shaped token, gated on Atlassian availability — advises naming the branch `<type>/<JIRA-ID>` (e.g. `feature/PROJ-123`).
- **PR-title hint** (`phase_compositions.SHIP.hints[]`): at SHIP, gated on Atlassian availability — advises deriving the Jira ID from the branch name and titling the PR `<JIRA-ID>: <exact ticket subject>` (subject fetched via the Atlassian MCP).

**No teeth, no commit-message changes.** Commit-message prefixing was explicitly dropped to avoid colliding with the existing Conventional Commits convention. Both hints are advisory context lines; neither blocks. PR-title correctness is inherently advisory (no hook can fetch the live ticket subject or intercept `gh pr create`).

## Capabilities

### Modified
- **`skill-routing`** — the session-start and activation hooks gain Atlassian MCP availability detection plus two advisory, Atlassian-gated hints (branch naming on Jira-ID mention; PR title at SHIP). Advisory-only, fail-open, silent for non-Atlassian repos. (Same home as the existing methodology-hint and phase-composition routing requirements.)

## Impact

**Files modified:**
- `hooks/session-start-hook.sh` — additive Atlassian MCP detection block after the posthog flip; flips `PLUGINS_JSON` `atlassian.available=true`. Fail-open. Reuses `_CLAUDE_JSON` and `_WORKSPACE_ROOT`.
- `config/default-triggers.json` — new `jira-branch-convention` methodology hint + new SHIP-phase PR-title hint.
- `config/fallback-registry.json` — regenerated in sync.
- `tests/test-registry.sh`, `tests/test-routing.sh`, `tests/fixtures/routing/jira-branch-convention.txt` — detection tests, both-directions gate test, regex fixtures.

**No guardrail reduced:** push gate, composition state, and design-guard are untouched. Net effect is additive advisory routing.
