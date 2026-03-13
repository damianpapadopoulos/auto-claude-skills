# Internal Truth — Blast-Radius Mapping & Safe Edits

Capability: Understand local file dependencies and inject code safely.

## Tier 1: Serena LSP

**Condition:** `serena = true`

- Use `find_symbol` to locate definitions and references
- Use `cross_reference` to map which files depend on a symbol
- Use `insert_after_symbol` for safe AST-level code injection without breaking formatting

## Tier 2: Standard Tools (Fallback)

**Condition:** `serena = false`

- Use `Grep` to find symbol references across the codebase
- Use `Read` to examine file contents and understand context
- Use `Edit` for modifications

**WARNING:** Without Serena's AST awareness, proceed with extra caution on:
- Large files (>500 lines) — higher risk of formatting/indentation errors
- Complex class hierarchies — manual dependency tracing may miss references
- Refactors that rename symbols — grep may miss dynamic references

Always verify changes compile/pass after editing without Serena.
