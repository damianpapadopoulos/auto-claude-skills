# Intent Truth — Feature Specification & Design Rationale

Retrieve canonical feature specifications, active change context, and design rationale.

Unlike other tiers that describe current state (what IS), Intent Truth defines intended
state (what SHOULD BE). When intent conflicts with code, the resolution depends on the
current SDLC phase — see phase documents.

**Artifact presence determines retrieval.** Check whether spec files exist in the
workspace — this is independent of CLI installation. The `OpenSpec:` capability line
from session-start indicates CLI availability for write operations, but Intent Truth
retrieval works with or without the CLI.

## Source 1 (In-Progress): OpenSpec Active Changes

**Condition:** `openspec/changes/<feature>/` exists in the workspace

Read active change artifacts for the feature being worked on:
- `proposal.md` for the change proposal (what and why)
- `design.md` for design decisions in flight (how)
- `specs/<capability>/spec.md` for delta requirements (acceptance criteria)

Active changes represent approved-but-unfinished work. They are the most current
intent source during development. Cross-reference with Internal Truth (current code
state) when ambiguity exists.

## Source 2 (Authoritative): OpenSpec Canonical Specs

**Condition:** Source 1 has no matching active change AND `openspec/specs/<capability>/spec.md` exists

Read the canonical spec for the capability being worked on. Canonical specs are the
single source of truth for feature requirements after a change has been archived.

If canonical spec conflicts with code behavior, the spec defines intended behavior —
the code may have drifted.

## Source 3 (Historical): Superpowers Specs

**Condition:** Sources 1+2 returned no matching artifacts AND Superpowers spec files
exist in `docs/superpowers/specs/`

Search for matching design specs:
- `docs/superpowers/specs/*-<keyword>-design.md` for the design specification

Superpowers specs are point-in-time design documents. They may be stale if the code
evolved after the spec was written. Always cross-reference with Internal Truth (actual
code) before treating as authoritative.

## Source 4: No Artifacts — Skip

No intent context is available. Do NOT hallucinate feature requirements. If the task
requires understanding feature intent and no specs exist, ask the user.
