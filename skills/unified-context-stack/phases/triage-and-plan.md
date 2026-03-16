# Phase 1: Triage & Plan

Before writing the implementation plan, gather context across all four dimensions.

## Steps

### 0. Intent Truth
IF the task references a known feature or capability, check for specification context before planning:
- **IF `openspec/changes/<feature>/` exists:** Read `proposal.md`, `design.md`, and `specs/` for active change context. These represent the most current intent for this feature. Carry forward existing requirements and acceptance scenarios into the plan.
- **ELSE IF `openspec/specs/<capability>/spec.md` exists:** Read the canonical spec for authoritative requirements. The plan must satisfy all specified scenarios unless the user explicitly says otherwise.
- **ELSE IF `docs/superpowers/specs/` has a matching design spec:** Read it for design intent, but cross-reference with the current codebase — SP specs may be stale.
- **IF no artifacts found:** Proceed without spec context. If the task scope is ambiguous, ask the user to clarify requirements.

### 1. Historical Truth
Query institutional memory for past constraints in this area:
- **forgetful_memory=true**: Use `memory-search` to query past architectural decisions and known constraints
- **forgetful_memory=false**: Read CLAUDE.md, docs/architecture.md, and .cursorrules for project context

### 2. External Truth
If the task involves third-party services or libraries:
- **context_hub_available=true**: Query Context Hub via Context7 for curated API docs for the specific version
- **context7=true** (no Hub match): Use broad Context7 query, verify signatures before including in plan
- **neither available**: Use WebSearch for official docs, cross-reference multiple sources
- Include relevant API signatures and usage examples in the written plan

### 3. Internal Truth
Map the blast radius before committing to a plan:
- **serena=true**: Use `find_symbol` / `find_referencing_symbols` to map all dependent files
- **serena=false**: Use Grep to find references across the codebase, Read to verify context
- List these files in the plan so the implementer knows the full scope
