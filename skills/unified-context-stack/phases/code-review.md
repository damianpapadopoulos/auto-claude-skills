# Phase 4: Code Review

When processing reviewer feedback, verify claims before accepting changes.

## Steps

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
