# Phase 1: Triage & Plan

Before writing the implementation plan, gather context across all three dimensions.

## Steps

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
- **serena=true**: Use `find_symbol` / `cross_reference` to map all dependent files
- **serena=false**: Use Grep to find references across the codebase, Read to verify context
- List these files in the plan so the implementer knows the full scope
