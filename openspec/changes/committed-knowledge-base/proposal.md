# Proposal: Committed shared knowledge base (`.claude/knowledge/`)

## Why

Project-fact knowledge a developer's agent learns (gotchas, "how this repo actually
works", decisions) today lives in one of two non-ideal places:

1. A single committed `CLAUDE.md`, manually curated and loaded wholesale every session.
2. Each developer's **private, per-machine** auto-memory at
   `~/.claude/projects/<project>/memory/` — invisible to teammates. Dev A's agent
   learns a fact, saves it locally, Dev B's agent never sees it.

There is no **committed, shared, progressively-disclosed** store that the whole team's
agents read. The private auto-memory is already the right *form* (markdown + YAML
frontmatter, `MEMORY.md` index, `[[slug]]` links — which is also Google's Open Knowledge
Format v0.1) and is *one property* away from the answer: it is not committed/shared.

A design debate (architect/critic/pragmatist + Codex) confirmed the gap is real but that
the dangerous part is **agent auto-write to a shared store** (memory poisoning / indirect
prompt injection — the lethal-trifecta surface our own `agent-safety-review` skill exists
to reject). This proposal captures the value while keeping a **human curation gate**.

## What Changes

Introduce a committed, repo-local knowledge directory `.claude/knowledge/` in the
*consuming* repo:

- **Schema** = the auto-memory / OKF v0.1 shape: one markdown file per fact, YAML
  frontmatter with a mandatory `type`, an `index.md` manifest (one line per fact),
  `[[slug]]` cross-links.
- **Read (this plugin):** the session-start hook injects **only** `index.md` (capped,
  fail-open, framed as reference *data* not instructions). Full fact files are fetched
  on demand by the agent following links — never loaded wholesale.
- **Write (this plugin):** a new **human-gated** `capture-knowledge` skill. The agent
  *proposes* a fact at SHIP/LEARN; the human approves in-session; the skill writes one
  fact-file + one index line, **staged not committed** — the commit rides the normal PR
  (a second human gate). Writes are routed past the existing secret/PII scanners first.
- **Index integrity:** `index.md` is regenerable from fact-file frontmatter so concurrent
  writes never hard-conflict on the manifest.
- **Optional local semantic retrieval:** where a user has Forgetful installed *locally*
  (no server), each fact file is synced into their local Forgetful (provenance-tagged,
  repo-scoped, idempotent upsert) so retrieval can use semantic `query_memory`. This is a
  derived, rebuildable per-user accelerator; the committed files stay canonical and the base
  index tier works with zero MCP dependency.
- **Scope boundary** codified: machine (auto-memory) / repo canonical (`.claude/knowledge/`)
  / repo derived-optional (local Forgetful). No org server assumed. No dual-write within a scope.

## Capabilities

**Modified:** `unified-context-stack` — adds a committed, shared leaf to the Historical
Truth tier (read injection + human-gated write + scope boundary). No new capability.

## Impact

- `hooks/session-start-hook.sh` — new fail-open block that injects `.claude/knowledge/index.md`.
- New skill `skills/capture-knowledge/` (capture criteria + draft + source-verify/enrich + human-gated write + index rebuild + optional local Forgetful upsert).
- `validate-knowledge` check (type present, no dangling links, index↔files match, source resolves) — CI-able, reused by index rebuild.
- Per-fact frontmatter: mandatory `type` (curated extensible vocab), `source` provenance, optional `supersedes`; bundle `schema_version` marker.
- Optional sync/reconcile path (files → local Forgetful, idempotent via `slug→memory_id` sidecar) — graceful no-op when Forgetful absent.
- `skills/unified-context-stack/tiers/historical-truth.md` — three-scope boundary docs.
- `config/default-triggers.json` + `config/fallback-registry.json` — routing entry for the new skill.
- Tests: `tests/test-context.sh` (injection + cap + fail-open), routing fixture, behavioral safety case (poisoned fact must not be acted on).
- `CLAUDE.md` — one gotcha note; seed one fact migrated from the Gotchas section as a dogfood example.

## Out of Scope

- **Agent auto-write without a human gate** — rejected (lethal trifecta).
- **Building our own embedding/vector engine** — rejected; reuse local Forgetful's embeddings as an optional accelerator. The base tier stays flat files + an index.
- **Depending on an org/shared Forgetful server** — explicitly out (assumption: none will exist). Forgetful integration is local-only and optional.
- Splitting `CLAUDE.md` into progressive-disclosure leaves — parked (CLAUDE.md is 8.8 KB, not bloated). Revival trigger: CLAUDE.md crosses a measured byte/budget threshold.
- Building against OKF's evolving schema — OKF is an **export/interop target only** (v0.1, mutable); we own only the v0.1 field-name mapping.
