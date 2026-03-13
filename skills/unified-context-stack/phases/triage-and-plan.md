# Phase 1: Triage & Plan

Before writing the implementation plan, gather context across all three dimensions.

## Steps

### 1. Historical Truth
Query institutional memory for past constraints in this area:
- "Do we have a standard way we handle [relevant pattern] in this project?"
- "Are there known architectural constraints for [affected module]?"

### 2. External Truth
If the task involves third-party services or libraries:
- Fetch curated API docs for the specific version used in this project
- Include relevant API signatures and usage examples in the written plan

### 3. Internal Truth
Map the blast radius before committing to a plan:
- Identify all files that depend on the modules being changed
- List these files in the plan so the implementer knows the full scope
