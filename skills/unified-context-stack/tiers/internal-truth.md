# Internal Truth — Blast-Radius Mapping & Safe Edits

Capability: Understand local file dependencies, inject code safely, and surface compiler/type errors authoritatively.

## Tier 0: LSP Diagnostics

**Condition:** `lsp = true`

- Use `mcp__ide__getDiagnostics` for compile errors, type errors, and linter warnings
- Authoritative for compiler truth — Tier 1 and Tier 2 tools cannot produce this
- Prefer this over grepping for error strings when the question is "what is broken"

## Tier 1: Serena Symbol Navigation

**Condition:** `serena = true`

- Use `find_symbol` to locate definitions
- Use `find_referencing_symbols` to map which files depend on a symbol (blast-radius)
- Use `insert_after_symbol` / `replace_symbol_body` / `rename_symbol` for safe AST-level edits without breaking formatting

## Tier 2: Standard Tools (Fallback)

**Condition:** `serena = false` and `lsp = false`, or for non-code content (logs, YAML values, config strings, free text)

- Use `Grep` to find references across the codebase
- Use `Read` to examine file contents
- Use `Edit` for modifications

**WARNING:** Without Serena's AST awareness, proceed with extra caution on:
- Large files (>500 lines) — higher risk of formatting/indentation errors
- Complex class hierarchies — manual dependency tracing may miss references
- Refactors that rename symbols — grep may miss dynamic references

Always verify changes compile/pass after editing without Serena.

## When to use which

| Question | Preferred tier |
|---|---|
| "What type/compile errors exist?" | Tier 0 (LSP) — authoritative |
| "Where is this function defined?" | Tier 1 (Serena) if available, else Tier 2 Grep |
| "Who calls this function?" | Tier 1 (Serena `find_referencing_symbols`) |
| "Rename X to Y across the codebase" | Tier 1 (Serena `rename_symbol`) |
| "Find this log message / YAML key / config string" | Tier 2 (Grep) — not a symbol |
| "Read this specific file" | Tier 2 (Read) — direct access |

LSP and Serena are complementary, not alternatives. When both are present, use LSP for diagnostics and Serena for navigation and edits.
