# Design: Design Phase Context Stack

## Architecture
The unified-context-stack is an infrastructure-level skill with per-phase documents that guide tiered context retrieval. A new `phases/design.md` was added as the first phase doc (Phase 0), positioned before `triage-and-plan.md` (Phase 1). The activation hook's `phase_compositions.DESIGN` parallel entry was narrowed to emit tier-specific hint text.

## Dependencies
No new dependencies. Uses existing:
- `openspec/specs/`, `openspec/changes/`, `docs/superpowers/specs/` for Intent Truth (file reads)
- Forgetful Memory MCP (`memory-search`) or flat files for Historical Truth

## Decisions & Trade-offs
**Why only Intent Truth + Historical Truth during brainstorming?**
- External Truth (API docs) requires knowing which libraries the solution will use — that depends on the chosen approach, which brainstorming hasn't settled yet
- Internal Truth (blast-radius mapping) requires knowing which files will be touched — also premature during brainstorming
- Intent Truth and Historical Truth are about "what has been decided before" — directly relevant to proposing viable approaches

**Why modify config rather than the brainstorming skill?**
- The brainstorming skill is upstream (superpowers plugin, not ours to modify)
- The context stack is designed to compose with phase-driver skills via the activation hook's PARALLEL mechanism
- Changing the hint text and adding a phase doc achieves the same effect without touching upstream code
