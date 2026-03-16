# Phase 0: Design

Before proposing approaches, check what's already been decided.

## Steps

### 0. Intent Truth
IF the task involves a known feature or capability, check for existing specifications:
- **IF `openspec/changes/<feature>/` exists:** Read `proposal.md`, `design.md`, and `specs/` for active change context. These represent the most current intent — proposed approaches must account for them.
- **ELSE IF `openspec/specs/<capability>/spec.md` exists:** Read the canonical spec. Proposed approaches should satisfy existing requirements unless the user explicitly wants to change direction.
- **ELSE IF `docs/superpowers/specs/` has a matching design spec:** Read it for design intent, but note it may be stale.
- **IF no artifacts found:** Proceed without spec context.

### 1. Historical Truth
Query institutional memory for past decisions and constraints in this area:
- **forgetful_memory=true**: Query Forgetful for past architectural decisions, failed approaches, and known constraints
- **forgetful_memory=false**: Read CLAUDE.md, docs/architecture.md, and .cursorrules for project context

**Note:** External Truth (API docs) and Internal Truth (blast-radius mapping) are deferred to the Plan phase — you don't know which libraries or files will be involved until an approach is chosen.
