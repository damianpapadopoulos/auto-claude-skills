# Phase 3: Testing & Debug

When tests fail or errors occur, use context to resolve efficiently.

## Steps

### 1. Historical Truth (First Check)
Before investigating from scratch:
- Query memory for this exact error message or pattern
- Check if this is a known environmental quirk with a documented workaround

### 2. External Truth (Library Issues)
If the error involves a third-party library:
- Check Context Hub / Context7 for known issues or breaking changes
- Search for the specific error message in the library's documentation
- For API errors (4xx/5xx), check if there are known outages or recently discovered bugs
