---
name: unified-context-stack
description: Tiered context retrieval across External Truth (docs), Internal Truth (dependencies), and Historical Truth (memory) with graceful degradation based on installed tools.
---

# Unified Context Stack

An infrastructure-level skill that provides tiered context retrieval for every SDLC phase. Reads your session's `Context Stack:` capabilities line to determine which tools are available, then follows strict fallback tiers.

## How to Use

1. Check the `Context Stack:` line from your session start for capability flags
2. Read the relevant **phase document** for your current SDLC phase
3. For each capability dimension needed, follow the **tier document** in strict order

## Capability Flags

These are injected by the session-start hook as: `Context Stack: context7=true, context_hub_cli=false, ...`

| Flag | Tool | What it enables |
|------|------|----------------|
| `context7` | Context7 MCP | Broad library doc retrieval |
| `context_hub_available` | Context Hub via Context7 | High-trust curated docs — flag means Hub is *reachable*, not that it has docs for your library (query `/andrewyng/context-hub`) |
| `context_hub_cli` | `chub` CLI | Local curated doc retrieval and annotations |
| `serena` | Serena MCP | LSP-powered dependency mapping and AST edits |
| `forgetful_memory` | Forgetful Memory | Persistent cross-session architectural knowledge |

## Tier Documents

- [External Truth](tiers/external-truth.md) — API documentation retrieval
- [Internal Truth](tiers/internal-truth.md) — Blast-radius mapping and safe code edits
- [Historical Truth](tiers/historical-truth.md) — Institutional memory retrieval and storage

## Phase Documents

- [Triage & Plan](phases/triage-and-plan.md) — Context gathering before writing plans
- [Implementation](phases/implementation.md) — Mid-flight lookups during execution
- [Testing & Debug](phases/testing-and-debug.md) — Error resolution and live issue discovery
- [Code Review](phases/code-review.md) — Claim verification and dependency checks
- [Ship & Learn](phases/ship-and-learn.md) — Memory consolidation before session close
