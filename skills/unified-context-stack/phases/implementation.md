# Phase 2: Implementation

During file-by-file plan execution, use context as needed.

## Steps

### 1. Internal Truth (Primary)
For each file modification, verify current symbol locations:
- **serena=true**: Use `find_symbol` / `cross_reference` for dependency mapping, `insert_after_symbol` for safe AST edits
- **serena=false**: Use Grep to find references, Read to verify context. Extra caution on large files (>500 lines) and symbol renames — grep may miss dynamic references. Always verify changes compile after editing.

### 2. External Truth (On-Demand)
If you encounter a library or API not covered in the original plan:
- **context_hub_available=true**: Query Context Hub via Context7 first for curated docs
- **context7=true** (no Hub match): Use broad Context7, verify method signatures before implementing
- **neither available**: Use WebSearch, treat with high skepticism
- Do not guess API signatures — look them up
