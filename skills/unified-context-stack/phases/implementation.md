# Phase 2: Implementation

During file-by-file plan execution, use context as needed.

## Steps

### 1. Internal Truth (Primary)
For each file modification:
- Use Serena (Tier 1) or Grep (Tier 2) to verify current symbol locations
- Ensure insertions don't break existing references

### 2. External Truth (On-Demand)
If you encounter a library or API not covered in the original plan:
- Trigger the External Truth tier cascade for a mid-flight lookup
- Do not guess API signatures — look them up
