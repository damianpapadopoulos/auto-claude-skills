# SDLC MCP Integration Design for auto-claude-skills

**Date:** 2026-03-06
**Status:** Approved
**Method:** Brainstorming with iterative review

## Problem

The auto-claude-skills routing engine is aware of 2 MCP servers (Context7, GitHub). The SDLC workflow benefits from structured MCP context injection across all phases -- requirements from Jira, runtime truth from GCP, visual verification from Playwright -- but the plugin doesn't model or route to these servers today.

## Approach

Extend the existing plugin registry pattern with a new `mcp_servers[]` top-level key in `default-triggers.json`, plus methodology hints and phase compositions gated on prompt-time MCP availability. Two hook enhancements: phase-scoped hints in `skill-activation-hook.sh` and MCP detection in the same hook (prompt-time, not session-time).

## Design Decisions

### MCP servers are separate from plugins

`plugins[]` means installable Claude plugins from the marketplace. MCP servers are configured differently (`.mcp.json`, `~/.claude.json`) and have different lifecycle semantics. A new `mcp_servers[]` key avoids confusion in health reporting, `/setup`, and the session-start hook.

### Prompt-time detection, not session-time

Project-scoped `.mcp.json` doesn't fit the global session-time registry cache. If session A in repo-with-Jira and session B in repo-without-Jira both write to the same cache, the last SessionStart wins. Prompt-time detection in `skill-activation-hook.sh` reads MCP config per-prompt, overrides `mcp_servers[].available` in memory, and never writes back to the cache.

### Hints + phase compositions, not skill file changes

Skills stay portable. Compositions and hints guide Claude to use MCP tools when available, but don't hard-wire MCP steps into skill workflows.

### Compositions only for high-signal MCPs; hints for the rest

Phase compositions fire whenever a plugin/mcp_server is available -- no prompt gating. To avoid noise, only Atlassian, GitHub, and GCP Observability get composition entries. GKE, Cloud Run, Firebase, and Playwright are hint-only (fire on trigger match + availability).

## Architecture

```
session-start-hook.sh (unchanged for MCP)
  -> builds global registry cache
  -> plugins[] availability from ~/.claude/plugins/cache/
  -> mcp_servers[] entries included with available: false

skill-activation-hook.sh (enhanced)
  -> reads registry cache
  -> prompt-time: resolves MCP config (local > project > user)
  -> overrides mcp_servers[].available in memory
  -> evaluates methodology_hints with phases[] + mcp_server gates
  -> evaluates phase_compositions with mcp_server gates
```

### MCP Config Resolution Order

Per Claude Code docs, three scopes with precedence local > project > user:

1. **Local scope**: `~/.claude.json` -> `projects[<project-path>].mcpServers`
2. **Project scope**: `<project-root>/.mcp.json` -> `mcpServers`
3. **User scope**: `~/.claude.json` -> `mcpServers` (top-level)

Detection pass:
1. Determine project root by walking up from `$PWD` for `.mcp.json` or `.git`
2. Compute the project path key for `~/.claude.json`
3. Read all three scopes, merge with local > project > user precedence
4. Extract final server names + command/url fields

### Multi-Signal MCP Identification

Three-tier strategy to avoid false negatives from user-defined server names:

**Tier 1 -- User override map** (highest priority):
```json
// ~/.claude/skill-config.json
{
  "mcp_mappings": {
    "my-custom-jira-server": "atlassian",
    "company-gcp-logs": "gcp-observability"
  }
}
```

**Tier 2 -- Command/URL matching**:

| Signal | Maps to |
|---|---|
| command contains `mcp-atlassian`, `uvx mcp-atlassian` | atlassian |
| command contains `gcloud-mcp`, args contain `observability` | gcp-observability |
| command contains `gke-mcp` | gke |
| command contains `cloud-run-mcp` | cloud-run |
| command contains `firebase-tools` and args contain `mcp` | firebase |
| command contains `playwright`, `@playwright/mcp` | playwright |

**Tier 3 -- Name pattern matching** (fallback):

| Pattern | Maps to |
|---|---|
| `*atlassian*`, `*jira*`, `*confluence*` | atlassian |
| `*gcloud*observ*`, `*gcp*observ*` | gcp-observability |
| `*gke*` | gke |
| `*cloud*run*`, `*cloudrun*` | cloud-run |
| `*firebase*` | firebase |
| `*playwright*` | playwright |

## New MCP Server Entries

Six entries for `mcp_servers[]` in `default-triggers.json`:

| Name | phase_fit | mcp_tools | Policy |
|---|---|---|---|
| atlassian | DESIGN, PLAN, REVIEW | `searchJiraIssuesUsingJql`, `getJiraIssue`, `getConfluencePage`, `searchConfluenceUsingCql`, `getJiraIssueTypeMetaWithFields` | Read-only |
| gcp-observability | SHIP, DEBUG | `list_log_entries`, `list_time_series`, `get_trace`, `list_error_groups`, `get_error_group_stats` | Read-only |
| gke | SHIP, DEBUG | `list_clusters`, `get_cluster`, `query_logs`, `get_kubeconfig` | Read-only; `get_kubeconfig` elevated |
| cloud-run | SHIP, DEBUG | `list_services`, `get_service`, `get_service_log`, `get_service_revisions` | Read-only |
| firebase | IMPLEMENT, SHIP, DEBUG | `list_projects`, `get_firestore_documents`, `get_auth_users`, `get_rules` | Read-only (no deploy tools) |
| playwright | IMPLEMENT, REVIEW, DEBUG, SHIP | `browser_navigate`, `browser_screenshot`, `browser_click`, `browser_type`, `browser_console_logs` | Interactive |

## Updated GitHub Plugin Entry

Expand `phase_fit` from `["REVIEW", "SHIP"]` to `["DESIGN", "PLAN", "REVIEW", "SHIP"]`.

## Methodology Hints

Eight new hints with phase-scoping (new `phases` field, optional, backwards compatible):

| Gate | Triggers | Phases | Hint |
|---|---|---|---|
| mcp_server: atlassian | `(ticket\|story\|epic\|acceptance.criter\|definition.of.done\|requirement\|user.story\|jira\|sprint\|backlog)` | DESIGN, PLAN | ATLASSIAN MCP: Use Jira MCP tools (searchJiraIssuesUsingJql, getJiraIssue) to pull acceptance criteria and linked context before planning. Prefer targeted issue lookups over broad searches. |
| mcp_server: atlassian | `(confluence\|wiki\|knowledge.base\|design.doc\|architecture.doc\|adr\|decision.record)` | DESIGN, PLAN | ATLASSIAN MCP: Use Confluence MCP tools (getConfluencePage, searchConfluenceUsingCql) for design references. Keep searches narrow -- broad page search adds noise. |
| mcp_server: gcp-observability | `(runtime.log\|error.group\|metric.regress\|production.error\|staging.error\|verify.deploy\|post.deploy\|list.log\|list.metric\|trace.search)` | SHIP, DEBUG | GCP OBSERVABILITY: Use observability MCP tools (list_log_entries, list_time_series, list_error_groups) to verify runtime state. Scope queries to service + environment + bounded time window (30-60 min). |
| mcp_server: gke | `(cluster\|kubernetes\|k8s\|pod\|node\|namespace\|workload\|gke)` | SHIP, DEBUG | GKE MCP: Use GKE MCP tools (query_logs, list_clusters) for cluster context and log queries. Prefer LQL log queries over broad log dumps. |
| mcp_server: cloud-run | `(cloud.?run\|serverless.deploy\|revision\|service.log\|cloud.?run.service)` | SHIP, DEBUG | CLOUD RUN MCP: Use Cloud Run MCP tools (get_service, get_service_log) to check service state and logs after deployment. |
| mcp_server: firebase | `(firebase\|firestore\|auth.user\|security.rules\|realtime.db\|cloud.function\|hosting)` | IMPLEMENT, SHIP, DEBUG | FIREBASE MCP: Use Firebase MCP tools for read-only resource inspection (documents, auth, rules). Use CLI for deployment and mutations. |
| mcp_server: playwright | `(screenshot\|visual.test\|browser.test\|layout.regress\|lighthouse\|a11y\|smoke.test\|e2e\|playwright)` | IMPLEMENT, REVIEW, DEBUG, SHIP | PLAYWRIGHT MCP: Use Playwright MCP tools (browser_navigate, browser_screenshot) for visual verification and interactive debugging. Captures what CLI test runners can't show. |
| plugin: github (update) | `(pull.?request\|issue\|github\|merge\|branch\|repo\|related.pr\|similar.change\|previous.attempt\|what.was.tried\|prior.art\|code.history)` | DESIGN, PLAN, REVIEW, SHIP | GITHUB MCP: Use GitHub MCP tools for PR/issue context, workflow run status, and code history. During brainstorming/planning, search for related PRs and issues to ground decisions in engineering history. |

## Phase Compositions

Only Atlassian, GitHub, and GCP Observability get composition entries. All others are hint-only.

### DESIGN (extend existing)

parallel[] additions:
- mcp_server: atlassian, use: `mcp:searchJiraIssuesUsingJql + getJiraIssue`, purpose: "Pull acceptance criteria and constraints while brainstorming clarifies intent"
- plugin: github, use: `mcp:list_issues + search_repositories`, purpose: "Inspect known related issues and search repo for prior approaches"

hints[] additions:
- mcp_server: atlassian, text: "Use Jira MCP to ground brainstorming in real requirements, not assumed ones"

### PLAN (currently empty)

parallel[] additions:
- mcp_server: atlassian, use: `mcp:getJiraIssue`, purpose: "Re-read Jira AC to validate plan steps map to acceptance criteria"
- plugin: github, use: `mcp:get_pull_request`, purpose: "Inspect known related PRs for implementation patterns and pitfalls"

hints[] additions:
- mcp_server: atlassian, text: "Verify each plan step traces to a Jira acceptance criterion"

### IMPLEMENT (no new compositions)

No changes. Firebase and Playwright reach IMPLEMENT through methodology hints only.

### REVIEW (extend existing)

parallel[] additions:
- mcp_server: atlassian, use: `mcp:getJiraIssue`, purpose: "Cross-check PR changes against Jira AC during review"

### SHIP (extend existing)

sequence[] additions (prepended before existing commit/branch entries):
1. mcp_server: gcp-observability, use: `mcp:list_log_entries`, purpose: "Check logs for deployment window errors"
2. mcp_server: gcp-observability, use: `mcp:list_error_groups`, purpose: "Verify no new error groups"
3. mcp_server: gcp-observability, use: `mcp:list_time_series`, purpose: "Confirm metrics didn't regress"

hints[] additions:
- mcp_server: gcp-observability, text: "Include runtime verification evidence in PR: log window, error delta, metric delta"

### DEBUG (extend existing)

parallel[] additions:
- mcp_server: gcp-observability, use: `mcp:list_log_entries + list_error_groups`, purpose: "Runtime signals for the error window to ground debugging hypotheses"

hints[] additions:
- mcp_server: gcp-observability, text: "Scope debug queries to service + environment + narrow time window. Avoid broad log dumps."

## Schema Changes

Two additive changes to `default-triggers.json`:

1. **`mcp_servers[]`** -- new top-level array. Same structure as `plugins[]` but for MCP servers. Not counted in plugin health messages. Availability set at prompt-time only.

2. **`methodology_hints[].phases`** -- optional string array. When present, the hint only fires if `PRIMARY_PHASE` matches one of the listed phases. When absent, the hint fires unconditionally (backwards compatible).

3. **`methodology_hints[].mcp_server`** / **`phase_compositions.*.*.mcp_server`** -- new gate field parallel to existing `plugin` gate. Gates on `mcp_servers[]` prompt-time availability instead of `plugins[]` cache availability.

## Hook Changes

### skill-activation-hook.sh

1. **MCP detection pass** (new, before hint/composition evaluation):
   - Walk up from `$PWD` to find `.mcp.json` or `.git` for project root
   - Read local scope (`~/.claude.json` projects section), project scope (`.mcp.json`), user scope (`~/.claude.json` top-level)
   - Merge with local > project > user precedence
   - Apply three-tier identification (user map > command/URL > name pattern)
   - Override `mcp_servers[].available` in memory

2. **Phase-scoped hint evaluation** (modify existing hint loop ~line 887):
   - If hint has `phases` array, check `PRIMARY_PHASE` is in it; skip if not
   - If hint has `mcp_server` instead of `plugin`, check against prompt-time MCP availability

3. **MCP-gated composition evaluation** (modify existing composition loop ~line 940):
   - Composition entries with `mcp_server` gate checked against prompt-time availability (parallel to existing `plugin` gate)

### session-start-hook.sh

No changes for MCP. The `mcp_servers[]` entries are included in the registry cache with `available: false`. Health messages do not count MCP servers.

## Test Plan

### New tests required

- **Phase-scoped hints**: hint with `phases: ["DESIGN"]` fires during DESIGN, suppressed during DEBUG
- **Backward compat**: hint without `phases` fires unconditionally
- **MCP name matching**: server name `claude_ai_Atlassian` maps to `atlassian` via Tier 3
- **MCP command matching**: server with command `uvx mcp-atlassian` maps to `atlassian` via Tier 2
- **MCP user override**: `mcp_mappings` entry overrides name/command matching via Tier 1
- **Project-vs-user precedence**: `.mcp.json` and local `~/.claude.json` both contribute; union with precedence
- **SHIP sequence order**: gcp-observability entries render before commit/branch entries
- **MCP-gated compositions**: entries with `mcp_server` gate only render when server detected at prompt-time
- **Zero MCP case**: no `.mcp.json`, no MCP servers -- all `mcp_servers[]` stay `available: false`, no noise

### Existing test updates

- `test-registry.sh` (line 289): update plugin count expectations
- `test-routing.sh` (line 792): update methodology hint assertions
- `config/fallback-registry.json`: add `mcp_servers[]` key (empty array)
- Test fixtures in both suites: include `mcp_servers[]` in mock registries

## Implementation Order

1. Add `mcp_servers[]` to `default-triggers.json` (6 entries)
2. Update `config/fallback-registry.json` with `mcp_servers: []`
3. Update GitHub plugin `phase_fit` to include DESIGN, PLAN
4. Add `phases` field support to hint evaluation in `skill-activation-hook.sh`
5. Add `mcp_server` gate support to hint and composition evaluation
6. Add MCP detection pass to `skill-activation-hook.sh`
7. Add 8 methodology hints (7 new mcp_server-gated, 1 updated github)
8. Add phase composition entries
9. Update test fixtures and add new test cases

## Trade-offs Accepted

- **Hint-only for 4 of 8 MCPs** (GKE, Cloud Run, Firebase, Playwright) to avoid noisy always-on compositions. Promotable to compositions if prompt-aware composition gating is added later.
- **Tool names from READMEs** for new MCPs -- may need minor corrections when users install actual servers. Easy to patch.
- **No skill file changes** -- compositions and hints guide Claude, but don't hard-wire MCP steps into skill workflows. Skills stay portable.
- **Prompt-time detection cost** -- 1-2 jq calls on local JSON files per prompt. Negligible latency but adds code to the hot path.
- **Three-tier identification adds complexity** -- but name-only matching would produce too many false negatives. The user override map is the escape hatch.

## Sources

- [Claude Code MCP docs](https://docs.anthropic.com/en/docs/claude-code/mcp)
- [GitHub MCP Server](https://github.com/github/github-mcp-server)
- [Atlassian MCP](https://github.com/sooperset/mcp-atlassian)
- [GCP MCP (gcloud-mcp)](https://github.com/googleapis/gcloud-mcp)
- [GKE MCP](https://github.com/GoogleCloudPlatform/gke-mcp)
- [Cloud Run MCP](https://github.com/GoogleCloudPlatform/cloud-run-mcp)
- [Firebase MCP docs](https://firebase.google.com/docs/cli/mcp-server)
- [Playwright MCP](https://github.com/microsoft/playwright-mcp)
- [awesome-mcp-servers](https://github.com/punkpeye/awesome-mcp-servers)
