# Phase 4: Code Review

When processing reviewer feedback, verify claims before accepting changes.

## Steps

### 1. External Truth (Claim Verification)
If a reviewer claims incorrect API usage:
- Look up the specific parameter/method in curated docs before accepting the change
- If the reviewer is wrong, cite the documentation source in your response

### 2. Internal Truth (Dependency Safety)
If a reviewer suggests an architectural change:
- Map downstream dependencies before implementing the suggestion
- Flag any files that would break silently from the proposed change
