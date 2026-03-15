# Phase 4: Code Review

When processing reviewer feedback, verify claims before accepting changes.

## Steps

### 0. Intent Truth (Requirement Verification)
IF reviewing changes to a specified capability:
- **IF `openspec/changes/<feature>/specs/` exists:** Read delta specs for the active change. These are the most current intent during development. Verify the implementation matches the specified scenarios.
- **ELSE IF `openspec/specs/<capability>/spec.md` exists:** Read the canonical spec. Verify the implementation satisfies all acceptance scenarios. Flag any specified requirement that is missing from the implementation or tests.
- **ELSE IF `docs/superpowers/specs/` has a matching design spec:** Reference it for design intent verification, but note that SP specs may have diverged from implementation.
- **IF no artifacts found:** Review based on code quality and internal consistency only.
- **IF the PR intentionally diverges from spec:** Note this as a spec update candidate — the spec should be revised to match the new intent after shipping.

### 1. External Truth (Claim Verification)
If a reviewer claims incorrect API usage:
- **context_hub_available=true**: Look up the specific parameter/method in Context Hub curated docs
- **context7=true** (no Hub match): Use broad Context7, verify against web-scraped docs
- **neither available**: Use WebSearch for official API reference
- If the reviewer is wrong, cite the documentation source in your response

### 2. Internal Truth (Dependency Safety)
If a reviewer suggests an architectural change:
- **serena=true**: Use `cross_reference` to map all downstream dependencies before implementing
- **serena=false**: Use Grep to find all references, Read to verify each usage. Extra caution on complex hierarchies.
- Flag any files that would break silently from the proposed change
