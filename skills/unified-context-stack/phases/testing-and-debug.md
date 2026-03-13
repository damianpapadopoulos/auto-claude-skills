# Phase 3: Testing & Debug

When tests fail or errors occur, use context to resolve efficiently.

## Steps

### 1. Historical Truth (First Check)
Before investigating from scratch:
- **forgetful_memory=true**: Use `memory-search` for this exact error message or pattern
- **forgetful_memory=false**: Check CLAUDE.md and docs/learnings.md for known environmental quirks
- Check if this is a known workaround with a documented fix

### 2. External Truth (Library Issues)
If the error involves a third-party library:
- **context_hub_available=true**: Check Context Hub via Context7 for known issues or breaking changes
- **context7=true** (no Hub match): Use broad Context7 for library-specific error documentation
- **neither available**: Use WebSearch for the specific error message in the library's docs
- For API errors (4xx/5xx), check for known outages or recently discovered bugs
