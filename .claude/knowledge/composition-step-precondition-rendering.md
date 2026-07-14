---
type: gotcha
title: Composition step text renders only the description's first sentence — add per-step lines via a separate field
description: The composition renderer truncates each step to description sentence-1; per-step additions (e.g. a PRECONDITION) need a separate optional field rendered in the CURRENT branch, not an appended sentence.
tags: [hooks, composition, skill-routing, jq]
source: hooks/skill-activation-hook.sh:839,902-910
timestamp: 2026-07-12T00:00:00Z
---

The composition-chain renderer in `hooks/skill-activation-hook.sh` builds each step line
from `(.description // "" | split(".")[0])` (line 839) — only the **first sentence** of a
skill's `description`. So you cannot add per-step guidance by appending a sentence to
`description`: it is silently truncated, and any period in the addition (e.g. a path like
`docs/plans/*-discovery.md`) cuts the split even earlier. `description` is also read by two
other surfaces (catalog, breadcrumb), so editing it there has side effects.

To attach an extra line to a step (e.g. the DISCOVER PRECONDITION on `brainstorming`), add a
**separate optional field** to the skill's registry entry and render it in the render loop's
**CURRENT branch only** (lines 902-910): `if [[ "$_marker" == "CURRENT" ]]` → one targeted
`jq` lookup → emit an indented line. Keep it CURRENT-only so LATER/DONE steps do not bloat;
fail-open (no field → no line).

Two more traps in that code:

- The batch-lookup row (~line 840) is `\x1f`-joined; a value containing `\x1f`/`\x01` would
  corrupt the `read -r` split. The separate-field lookup sidesteps this — keep such config
  values single-line plain text.
- The `\u001f` separators appear as **literal 6-character escapes** in the jq source. The
  Edit tool JSON-decodes `\u001f` in your parameter to the real control byte, so it cannot
  match the literal in the file — anchor edits on non-separator substrings instead.

Measuring whether such step-text guidance is actually *obeyed* (not merely present) is a
model-behavior question — see [[behavioral-eval-subject-read-contamination]] for eval-fixture
pitfalls when measuring uptake.
