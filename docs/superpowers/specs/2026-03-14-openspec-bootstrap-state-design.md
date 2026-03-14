# Design: OpenSpec Bootstrap + Session State (Spec A)

## Overview

Make OpenSpec a first-class bootstrap capability detected at session start, parallel to `context_capabilities`. Persist SP/OpenSpec linkage in a session-scoped state file so that `openspec-ship` can consume deterministic state instead of guessing. Add provenance metadata to archived changes for future retrieval.

## Motivation

The current `openspec-ship` skill detects the OpenSpec CLI ad hoc at execution time via `command -v openspec`. It has no knowledge of which OPSX commands are available, no way to carry `plan_path`/`spec_path` forward from earlier SHIP chain steps, and no provenance trail in archived artifacts. This creates three problems:

1. **Detection redundancy** — Every skill that touches OpenSpec must re-probe the environment.
2. **Artifact ambiguity** — `openspec-ship` relies on explicit user input for `plan_path` because no session state carries it forward.
3. **Non-deterministic retrieval** — Archived changes have no machine-readable record of where they came from.

## Hard Boundary

- This spec makes OpenSpec information **available** to future consumers.
- This spec does **NOT** change unified-context-stack behavior, add OpenSpec as a context tier, or modify phase document retrieval logic. That is Spec B.

## 1. Bootstrap Detection

### Location

`hooks/session-start-hook.sh` — add a new detection block after the existing `context_capabilities` detection (Step 8d, line ~489).

### Workspace Root Derivation

The targeted workspace probe requires a workspace root. Derive it as:

```bash
_WORKSPACE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

### Detection Logic

**Binary detection:**
```bash
command -v openspec >/dev/null 2>&1
```

**Workspace command discovery (targeted, OpenSpec only):**

Scan `${_WORKSPACE_ROOT}/.claude/commands/opsx/*.md` for command files. Map filenames to `/opsx:<name>` commands. This is a targeted probe — it does NOT add generic workspace command discovery.

```bash
# Example: propose.md → /opsx:propose, archive.md → /opsx:archive
for _cmd in "${_WORKSPACE_ROOT}/.claude/commands/opsx"/*.md; do
    [ -f "${_cmd}" ] || continue
    _cmd_name="/opsx:$(basename "${_cmd}" .md)"
    # accumulate into commands list
done
```

**Surface derivation (set-based, by command names):**

| Surface | Condition |
|---------|-----------|
| `none` | `binary=false`. If commands were found anyway, add to `warnings`. |
| `openspec-core` | `binary=true`, no OPSX core commands detected. |
| `opsx-core` | `binary=true`, commands contain at minimum `propose`, `apply`, `archive`. |
| `opsx-expanded` | `binary=true`, commands contain any of: `new`, `ff`, `continue`, `verify`, `sync`. |

### Registry Schema

Add `openspec_capabilities` to the registry cache JSON, parallel to `context_capabilities`:

```json
{
  "openspec_capabilities": {
    "binary": true,
    "commands": ["/opsx:propose", "/opsx:apply", "/opsx:archive", "/opsx:explore"],
    "surface": "opsx-core",
    "warnings": []
  }
}
```

### Capability Line Emission

Emit an `OpenSpec:` line in the session-start `additionalContext` output, following the same pattern as the existing `Context Stack:` line:

```
OpenSpec: binary=true, surface=opsx-core, commands=/opsx:propose,/opsx:apply,/opsx:archive,/opsx:explore
```

### Fallback Registry

Regenerate `config/fallback-registry.json` to include `openspec_capabilities` with all-false/empty defaults:

```json
{
  "openspec_capabilities": {
    "binary": false,
    "commands": [],
    "surface": "none",
    "warnings": []
  }
}
```

## 2. Session State File

### Path

`~/.claude/.skill-openspec-state-${_SESSION_TOKEN}`

Session-scoped via the same token mechanism used by composition state.

### Schema

```json
{
  "openspec_surface": "opsx-core",
  "verification_seen": true,
  "verification_at": "2026-03-14T15:30:00Z",
  "changes": {
    "openspec-ship": {
      "sp_plan_path": "docs/superpowers/plans/2026-03-14-openspec-ship.md",
      "sp_spec_path": "docs/superpowers/specs/2026-03-14-openspec-ship-design.md",
      "capability_slug": "openspec-ship",
      "archived_at": null
    }
  }
}
```

Top-level fields are session-wide. Per-change fields are nested under `changes.<slug>`. Multiple features in one session produce multiple entries in the `changes` map.

### Lifecycle (Lazy-Create)

The state file does not exist until a SHIP skill writes it. Session-start and routing hooks never create it.

**`verification-before-completion`** creates the file on successful completion:
- `verification_seen: true`
- `verification_at: <ISO 8601>`
- `openspec_surface`: read from the session's `OpenSpec:` capability line (primary) or `~/.claude/.skill-registry-cache.json` (fallback)

**`openspec-ship`** fills `changes.<slug>` when it starts:
- `sp_plan_path`, `sp_spec_path`, `capability_slug`
- `openspec_surface` if still missing (e.g., openspec-ship invoked directly without verification)

Both operations are **idempotent merges** — they read the existing file, merge their fields, and write back. They never overwrite the entire file.

## 3. Persistence Helper

### File

`hooks/lib/openspec-state.sh`

Small bash library with functions for reading and writing the state file. Sourced by skills/hooks that need state access. Directly testable in bash.

### Functions

**`openspec_state_mark_verified <session_token> <surface>`**

Create or update the state file with verification fields. Idempotent merge — preserves existing `changes` map if file already exists.

**`openspec_state_upsert_change <session_token> <slug> <plan_path> <spec_path> <capability>`**

Add or update a change entry in the `changes` map. Idempotent — if the slug already exists, updates fields without losing other entries.

**`openspec_state_read <session_token>`**

Read and output the current state file as JSON. Returns empty JSON `{}` if file doesn't exist.

**`openspec_write_provenance <archive_path> <session_token> <slug>`**

Write `source.json` to `<archive_path>/superpowers/source.json` by reading from the session state file and adding `source_branch`, `base_commit`, and `archived_at`.

### Fail-Open Behavior

These writes **never block SHIP**:
- Missing session token → skip state write with warning
- Missing/malformed registry → treat surface as `none`
- Provenance write failure → warn, but do not fail archive
- State file read failure → return empty `{}`, let consuming skill fall back to user input

## 4. Provenance Metadata

### File

`openspec/changes/archive/YYYY-MM-DD-<feature>/superpowers/source.json`

### Schema

```json
{
  "schema_version": 1,
  "sp_plan_path": "docs/superpowers/plans/2026-03-14-openspec-ship.md",
  "sp_spec_path": "docs/superpowers/specs/2026-03-14-openspec-ship-design.md",
  "change_slug": "openspec-ship",
  "capability_slug": "openspec-ship",
  "source_branch": "main",
  "base_commit": "<full SHA at archive time>",
  "openspec_surface": "opsx-core",
  "archived_at": "2026-03-14T16:00:00Z"
}
```

- All paths are repo-relative, not absolute
- `base_commit` is a full SHA (not short) — this is HEAD at archive time, before the shipping commit
- `schema_version` enables future evolution
- Written by `openspec-ship` after archive path exists, via `openspec_write_provenance` helper

## 5. openspec-ship Updates

Modify `skills/openspec-ship/SKILL.md` to consume bootstrap capabilities and session state:

### Environment detection

**Replace** the current `command -v openspec` check with:
- **Primary:** Read the session's `OpenSpec:` capability line (already in conversation context from session-start output)
- **Fallback:** Read `~/.claude/.skill-registry-cache.json` field `openspec_capabilities`

This matches the existing context-stack pattern where skills read capability lines from session-start output rather than accessing the registry directly.

### Artifact source

**Replace** user-input-only `plan_path` with:
- **Primary:** Read from session state file (`changes.<slug>.sp_plan_path`)
- **Fallback:** Explicit user input (backwards compatibility if state file doesn't exist)

### Provenance

**Add** `source.json` write at archive time via the persistence helper.

### Backwards compatibility

If the state file doesn't exist (e.g., user hasn't updated `verification-before-completion` yet), fall back to the current behavior: `command -v openspec` for detection, user input for `plan_path`.

## 6. Files to Modify

| File | Change |
|------|--------|
| `hooks/session-start-hook.sh` | Add targeted workspace OPSX command probe + `openspec_capabilities` detection block + `OpenSpec:` capability line emission |
| `hooks/lib/openspec-state.sh` | New file: persistence helper functions (`openspec_state_mark_verified`, `openspec_state_upsert_change`, `openspec_state_read`, `openspec_write_provenance`) |
| `skills/openspec-ship/SKILL.md` | Consume `OpenSpec:` capability line and session state; add `source.json` write at archive time; maintain backwards compatibility |
| `config/fallback-registry.json` | Regenerate to include `openspec_capabilities` with all-false defaults |
| `tests/test-registry.sh` | 8 bootstrap detection tests |
| `tests/test-openspec-state.sh` | New file: 4+ state persistence and provenance tests |

## 7. Tests

### Bootstrap detection (`tests/test-registry.sh`)

1. **Binary detected** — Mock `openspec` in PATH. Assert `openspec_capabilities.binary == true`.
2. **Binary absent** — No openspec. Assert `binary == false`, `surface == "none"`.
3. **OPSX core detection** — Create `${PROJECT_ROOT}/.claude/commands/opsx/{propose,apply,archive}.md`. Assert `surface == "opsx-core"`, commands list correct.
4. **OPSX expanded detection** — Add `new.md`, `ff.md`. Assert `surface == "opsx-expanded"`.
5. **Binary-only (no OPSX commands)** — Binary in PATH, no command files. Assert `surface == "openspec-core"`.
6. **Commands without binary (mismatch)** — Command files present, no binary. Assert `surface == "none"`, `warnings` contains mismatch message.
7. **Capability line emission** — Assert session-start output contains `OpenSpec:` line with `binary=`, `surface=`.
8. **Workspace-only command discovery** — Project-local `.claude/commands/opsx/*.md` exists, no plugin command roots. Assert `openspec_capabilities.commands` still populates from the workspace probe.

### State persistence (`tests/test-openspec-state.sh`)

9. **Session-start and routing hooks alone do not create the OpenSpec state file** — Run hooks. Assert no `~/.claude/.skill-openspec-state-*` file exists.
10. **mark_verified creates state** — Call `openspec_state_mark_verified`. Assert file exists with `verification_seen == true`, `openspec_surface` populated.
11. **upsert_change adds to changes map** — Call `openspec_state_upsert_change` twice with different slugs. Assert both entries exist in `changes` map, neither overwrites the other.
12. **write_provenance produces valid source.json** — Call `openspec_write_provenance` after state is populated. Assert `superpowers/source.json` exists with `schema_version == 1` and all required fields non-null.

## Non-Goals

- Does NOT change unified-context-stack behavior or add OpenSpec as a context tier (that is Spec B).
- Does NOT add generic workspace command discovery (only targeted OpenSpec probe).
- Does NOT modify skill-activation-hook.sh routing logic or role caps.
- Does NOT require OpenSpec CLI to be installed — all paths degrade gracefully to `surface: "none"`.
