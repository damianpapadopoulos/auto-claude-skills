# Phase 5: Ship & Learn

Before completing the session, consolidate what was learned.

## Memory Consolidation

Evaluate your available tools and execute the highest available tier:

### IF forgetful_memory = true
Execute `memory-save` to permanently store:
- New architectural rules or conventions discovered
- Project-specific quirks that would be useful in future sessions
- Decisions made and their rationale

### IF context_hub_cli = true
Execute `chub annotate <library-id> "<note>"` to record:
- API workarounds or undocumented behaviors discovered
- Version-specific gotchas (e.g., "React Router v7 requires X wrapper in our setup")

### IF NEITHER are available
Append findings to `docs/learnings.md` using standard file editing:

```
## YYYY-MM-DD: [Brief Title]

**Context:** [What task was being performed]
**Learning:** [The specific insight or workaround]
**Applies to:** [Which part of the codebase]
```
