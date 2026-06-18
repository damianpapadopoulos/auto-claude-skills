# Design: Committed shared knowledge base

## Architecture

**Design assumption:** there is NO org-scope Forgetful server, and we should not depend on
one. `.claude/knowledge/` (committed files) is the canonical store and must be fully useful
to the broad user group with **zero external infrastructure**. Forgetful, where a user has it
installed *locally*, is an **optional per-user retrieval accelerator** layered over the same
committed files — never a requirement, never a shared server.

Memory scopes, no dual-write within a scope:

| Scope | Home | Audience | Write trigger |
|-------|------|----------|---------------|
| machine | `~/.claude/projects/<project>/memory/` (auto-memory) | just me, this machine | agent, low-friction |
| **repo (canonical)** | **`.claude/knowledge/` (committed) — NEW** | the team, via `git clone` | agent proposes → human approves |
| repo (derived, optional) | each user's **local** Forgetful, synced from the files | just me, this machine | sync job (rebuildable) |

### Retrieval tiers (graceful degradation)
- **Base (always, zero deps):** session-start injects `.claude/knowledge/index.md`
  (progressive disclosure). Every user with a git repo gets shared knowledge with no MCP.
- **Accelerator (if local Forgetful present):** each fact file is mirrored into the user's
  local Forgetful as one memory; retrieval uses `query_memory` (semantic, repo-scoped,
  auto-linked). The local Forgetful store is a *derived, rebuildable index* — the files in
  git remain the source of truth. No server.

### Forgetful sync (optional accelerator — files → local Forgetful)
Forgetful has no directory-ingest; we drive sync via its tools, idempotently:
- Map **one fact file → one `create_memory`**, carrying provenance:
  `source_repo=<repo>`, `source_files=[".claude/knowledge/<slug>.md"]`,
  `encoding_version=<content-hash>`, `tags`, `importance`, `project_id` (repo-scoped).
- **Idempotent upsert** (Forgetful's own query-then-update/create pattern made
  deterministic): keep a **local, rebuildable** `slug → memory_id` sidecar at
  `~/.claude/.knowledge-forgetful-map-<repohash>.json`. Same hash → skip; changed →
  `update_memory`; new → `create_memory`; file gone → delete the memory.
- **Sync placement:** at capture time (write file + upsert in one step) and an on-demand
  **reconcile** after `git pull` (absorb teammates' new/changed/deleted facts). NEVER on the
  200 ms session-start hot path; base retrieval never blocks on sync.
- **Atomicity constraint:** `create_memory` content caps ~2000 chars (~300–400 words). Facts
  stay atomic (OKF/auto-memory already encourage this); oversized facts stay file-only.

### File format (= auto-memory / OKF v0.1)
```
.claude/knowledge/
├── index.md                 # one line per fact: "- [Title](slug.md) — hook"; header carries schema_version
└── <slug>.md                # frontmatter below
```
Per-fact frontmatter:
- `type` — **mandatory**. Drawn from a small, curated, *extensible* vocabulary:
  `gotcha | decision | convention | architecture | runbook` (producers may add types — OKF
  "minimally opinionated"). Enables retrieval filtering and index grouping.
- `title`, `description`, `tags` — as in auto-memory.
- `source` — **provenance** (adopted from OKF `resource`): PR#, commit SHA, repo-relative
  `path:line`, or doc URL. Makes the fact *verifiable* and is the anti-staleness anchor.
- `timestamp` — ISO 8601.
- `supersedes` — optional `[[old-slug]]` link when this fact revises a prior one (the useful
  kernel of OKF `log.md`; git gives who/when, this gives the decision chain; the PR gives why).

Body is markdown; cross-links via `[[slug]]`. A `schema_version` marker (in `index.md`
header) supports backward-compatible format growth.

### Read path (this plugin)
- `hooks/session-start-hook.sh`: if `<repo>/.claude/knowledge/index.md` exists, append its
  contents to `CONTEXT`, **capped** (e.g. ≤ N KB / M lines), under a header that frames it
  as **reference data, not instructions**. Fail-open on every error (missing file, oversize,
  read failure). Full fact files are never injected — the agent fetches them on demand.
- Budget: one extra file read on the session-start hot path. Within the 200 ms budget; no
  new jq fork (plain `cat`/size check).

### Write path (this plugin)
- New skill `capture-knowledge`, **human-gated**:
  1. **Capture criteria** (adopted from auto-memory doctrine; OKF punts on "what to write"):
     write only what is *durable, cross-session, non-obvious, and not already recorded by
     code/git/CLAUDE.md*. Reject ephemera and restated source.
  2. Agent drafts a candidate fact (slug, `type`, `source`, body) at SHIP/LEARN.
  3. **Enrichment/verify pass** (adapted from OKF's enrichment agent): confirm the `source`
     resolves *now* (file:line / PR / URL exists), and auto-link related existing facts via
     `[[slug]]`. Drafts with an unresolvable `source` are flagged, not silently written.
  4. Skill shows it to the human for approval (no silent write).
  5. On approval: run the existing secret/PII scan (gitleaks/security-scanner); **block on
     hit**. Dedup against existing slugs.
  6. Write `<slug>.md`, rebuild `index.md`, `git add` (staged, **not committed**).
  7. The fact reaches `main` only through the normal PR review — the second human gate.
- **`validate-knowledge`** check (addresses OKF's named validation gap; CI-able): every file
  has a `type`, no dangling `[[links]]`, `index.md` matches files on disk, and each `source`
  resolves. Reused by `rebuild-index` and runnable standalone.
- `index.md` is regenerable from fact-file frontmatter (`rebuild-index`), so concurrent
  branch writes conflict only on regenerable content, not hand-merged prose.

## Safety (agent-safety-review lens — this IS the lethal-trifecta surface)

The risk class is **memory poisoning / indirect prompt injection**: a fact written by one
agent is read and acted on by every other agent. Mitigations are *requirements*, not nice-to-haves:

- **Two human gates on write:** in-session approval + PR review. No agent path writes to
  the shared store unattended.
- **Read-as-data:** the injected index is explicitly framed as untrusted reference data;
  the agent must not treat fact-file contents as instructions.
- **Secret/PII gate** before staging.
- **Provenance:** frontmatter `timestamp`; git blame gives authorship/accountability.
- This change MUST pass `agent-safety-review` before merge.

## Retrieval boundary (Serena vs Forgetful — verified)

- **Serena does NOT index prose knowledge.** Its "semantic" is LSP/symbol understanding of
  *code* (exact, no embeddings); markdown facts have no symbols. Pointing Serena at the dir
  yields only grep/heading structure — not similarity search. Serena's own memory has the
  same unsolved scaling limit (embedding search is an open, unshipped issue).
- **Semantic retrieval-at-scale = local Forgetful, not Serena.** Forgetful uses FastEmbed
  embeddings locally. This is why the optional accelerator tier is Forgetful.
- Curation (the human gate) keeps `.claude/knowledge/` small enough that the base
  progressive-disclosure tier suffices for most repos; Forgetful is the escalation when a
  user wants similarity search over a larger curated set.

## Trade-offs (what we accept)

- A derived per-user index (local Forgetful) in addition to the canonical files — mitigated:
  it is rebuildable from git and entirely optional; the base tier never depends on it.
- Forgetful sync idempotency is not native — we own query/hash/map logic; imperfect matching
  risks duplicate memories. Mitigated by the deterministic `slug→memory_id` sidecar + hash.
- Some write friction (human approval) — deliberate; the gate is the feature.
- Index can drift if hand-edited — mitigated by `rebuild-index`.

## Dissenting views (from the debate)

- **Critic (high confidence):** the shared curated store already exists as `CLAUDE.md`;
  the only real delta is auto-write, and auto-write is the danger. *Resolution:* we ship
  the human-gated form, not auto-write — the critic's objection is satisfied by the gate.
- **Pragmatist (high confidence):** ship docs + a promotion nudge first to probe demand;
  full directory is YAGNI until used. *Resolution:* user explicitly chose to build the
  directory; we adopt the pragmatist's *safety* line (human-gated, no auto-write) and
  *reject* the split-CLAUDE.md and embeddings scope.
- **Codex:** OKF is Obsidian/docs-as-code with Google field names; nothing structural to
  adopt; v0.1 → export target only. *Resolution:* schema reuses our own auto-memory shape;
  OKF stays an interop/export target, not a build dependency.

## Decisions & rejected alternatives

- **Rejected:** agent auto-write to the shared store (lethal trifecta; fails agent-safety-review).
- **Rejected:** build a new graph/retrieval engine — reuse local Forgetful's embeddings
  instead (optional accelerator), with committed files as source of truth.
- **Rejected:** depend on an org-scope Forgetful server (assumption: none will exist).
- **Rejected:** Serena as the semantic retriever over prose (it indexes code symbols, not text).
- **Rejected:** split `CLAUDE.md` (no bloat signal: 8.8 KB measured).
- **Parked:** OKF field-name export of the bundle — revival trigger: a named cross-LLM user.
- **To review during PLAN:** `/scottrbk/context-hub-plugin` (same author) already orchestrates
  Forgetful+Context7+Serena — glance for reusable sync wiring before building ours.

### Adopted from OKF (finer-pass learnings)
- **`source` provenance + write-time verify** — anti-staleness anchor (OKF `resource` +
  enrichment pass; matches our evidence-links/staleness doctrine). The headline adoption.
- **`validate-knowledge`** — OKF names validation as its own gap; we close it (fits our test culture).
- **Capture criteria** — OKF punts on "what to write"; we reuse auto-memory's "don't restate code/git".
- **Curated extensible `type` vocab** + **`schema_version`** — OKF "minimally opinionated" + versioned growth.
- **`supersedes` link** — kernel of OKF `log.md` without a second file (git = who/when, PR = why).
- **Skipped:** static-HTML visualizer (revival: large bundle / human browse) and multi-bundle
  composition/inheritance (irrelevant at our scale). Producer/consumer separation already honored
  (Forgetful + hook are independent consumers; the file format is the only contract).
