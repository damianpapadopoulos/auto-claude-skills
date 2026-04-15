# Intent Truth — Feature Specification & Design Rationale

Retrieve canonical feature specifications, active change context, and design rationale.

Unlike other tiers that describe current state (what IS), Intent Truth defines intended
state (what SHOULD BE). When intent conflicts with code, the resolution depends on the
current SDLC phase — see phase documents.

**Artifact presence determines retrieval.** Check whether spec files exist in the
workspace — this is independent of CLI installation. The `OpenSpec:` capability line
from session-start indicates CLI availability for write operations, but Intent Truth
retrieval works with or without the CLI.

## Intent Truth Sources (checked in order)

### Source 1: OpenSpec Active Changes (highest authority — in-progress work)
**When:** `openspec/changes/<feature>/` exists in workspace
**Read:** `proposal.md`, `design.md`, `specs/<capability>/spec.md`
**Authority:** Most current — approved but unfinished work

### Source 2: Live Intent Artifacts (canonical design/plan/spec)
**When:** Source 1 has no match AND `docs/plans/*-<keyword>-{design,plan,spec}.md` exists
**Read:** Matching `-design.md`, `-plan.md`, `-spec.md` files
**Authority:** Current session's design intent — may still be in progress

### Source 3: OpenSpec Canonical Specs (post-ship authoritative)
**When:** Sources 1+2 have no match AND `openspec/specs/<capability>/spec.md` exists
**Read:** The canonical spec
**Authority:** Single source of truth after archival; code may have drifted

### Source 4: Archived Intent (shipped intent history)
**When:** Sources 1-3 have no match AND `docs/plans/archive/*-<keyword>-design.md` exists
**Read:** Archived design/plan/spec files
**Authority:** Historical — shows what was intended at ship time

### Source 5: Legacy Superpowers Specs (deprecated fallback)
**When:** Sources 1-4 returned nothing AND `docs/superpowers/specs/*-<keyword>-design.md` exists
**Read:** Legacy design specs
**Authority:** Point-in-time; may be stale. Cross-reference with current code.
**Note:** This source will be removed in a future version. New artifacts should go to `docs/plans/`.

### No Artifacts Found
**When:** All sources unavailable
**Action:** Skip Intent Truth. Ask user. Do NOT hallucinate requirements.
