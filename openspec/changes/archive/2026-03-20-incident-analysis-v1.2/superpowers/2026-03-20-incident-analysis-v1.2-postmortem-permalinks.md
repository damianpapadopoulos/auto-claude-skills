# Incident Analysis v1.2: Postmortem Permalinks Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add clickable trace and commit permalinks to the postmortem output in Stage 3 of the incident-analysis skill.

**Architecture:** Insert permalink formatting rules into the existing Step 3 (Generate Postmortem) of SKILL.md. Zero extra tool calls — uses data already available from Stage 2. Update v1.0 spec evolution path.

**Tech Stack:** Markdown (SKILL.md prompt engineering)

**Spec:** `docs/superpowers/specs/2026-03-20-incident-analysis-v1.2-postmortem-permalinks-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `skills/incident-analysis/SKILL.md:207` | **Modify** — Insert permalink formatting rules after the "Action items" bullet |
| `docs/superpowers/specs/2026-03-19-incident-analysis-design.md:390` | **Modify** — Insert v1.2 entry in evolution path |

---

### Task 1: Add permalink rules to SKILL.md Stage 3, Step 3

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:207` (insert after existing content)

- [ ] **Step 1: Confirm the insertion point**

```bash
sed -n '205,210p' skills/incident-analysis/SKILL.md
```

Expected:
```
- Impact (from error rates/metrics, quantified)
- Root cause (from investigation hypothesis)
- Action items (concrete, assignable, with suggested owners)

### Step 4: Write to Disk
```

Line 207 is `- Action items (concrete, assignable, with suggested owners)`. Insert after this line, before the blank line at 208.

- [ ] **Step 2: Insert permalink formatting rules**

After line 207 (`- Action items ...`), insert this exact block:

```markdown

**Permalink formatting (apply to all references in the generated postmortem):**
- **Trace IDs:** Format as `[Trace TRACE_ID](https://console.cloud.google.com/traces/list?project=PROJECT_ID&tid=TRACE_ID)` using the project_id and trace_id from Stage 2. If cross-project trace correlation was used (Step 4), use the relevant project for each reference — Service A traces use Service A's project_id, Service B traces use Service B's project_id.
- **Git commits:** If a commit hash is referenced (e.g., a deployment trigger), derive the repo URL via `git remote get-url origin`. If GitHub-hosted, format as `[Commit SHORT_HASH](https://github.com/ORG/REPO/commit/FULL_HASH)`. If not GitHub-hosted or the command fails, use the raw commit hash without a link.
```

- [ ] **Step 3: Verify the insertion**

```bash
grep -n "Permalink formatting" skills/incident-analysis/SKILL.md
```

Expected: One match, in the Stage 3 Step 3 section.

```bash
grep -c "console.cloud.google.com/traces" skills/incident-analysis/SKILL.md
```

Expected: 1

```bash
grep -c "git remote get-url origin" skills/incident-analysis/SKILL.md
```

Expected: 1

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat: add trace and commit permalink formatting to postmortem output (v1.2)"
```

---

### Task 2: Update v1.0 spec evolution path and verify

**Files:**
- Modify: `docs/superpowers/specs/2026-03-19-incident-analysis-design.md:390`

- [ ] **Step 1: Insert v1.2 entry in evolution path**

Find line 390:
```
v1.1  One-hop trace correlation: Service A → Service B (Tier 1 MCP only) [SHIPPED]
```

Insert after it:
```
v1.2  Postmortem permalinks: trace IDs + commit hashes as clickable Markdown links [SHIPPED]
```

- [ ] **Step 2: Verify**

```bash
grep "v1.2" docs/superpowers/specs/2026-03-19-incident-analysis-design.md
```

Expected: The new v1.2 line with `[SHIPPED]`.

- [ ] **Step 3: Run routing tests (regression check)**

```bash
bash tests/test-routing.sh 2>&1 | tail -8
```

Expected: 243/243 pass.

- [ ] **Step 4: Run full test suite**

```bash
bash tests/run-tests.sh 2>&1; echo "exit: $?"
```

Expected: Exit 1 (known baseline: test-registry.sh with 2 pre-existing parity failures). No other test file fails.

- [ ] **Step 5: Behavioral verification**

Read the full Step 3 section of SKILL.md and confirm:

| # | Scenario | Expected behavior | Check |
|---|----------|-------------------|-------|
| 1 | Trace ID in timeline | Formatted as `[Trace ...](https://console.cloud.google.com/traces/list?project=...&tid=...)` | [ ] |
| 2 | Cross-project trace (Service B different project) | Service A traces use A's project, Service B traces use B's project | [ ] |
| 3 | Commit hash in timeline | Agent runs `git remote get-url origin`, formats as GitHub link | [ ] |
| 4 | Non-GitHub remote | Raw commit hash, no link | [ ] |
| 5 | `git remote get-url origin` fails | Raw commit hash, no link | [ ] |
| 6 | No trace IDs in postmortem (Tier 2/3) | No trace links generated | [ ] |
| 7 | No commit refs in postmortem | No commit links generated | [ ] |
| 8 | Both services in cross-project postmortem | Each trace reference uses its own service's project_id | [ ] |

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-03-19-incident-analysis-design.md
git commit -m "docs: update v1.0 spec evolution path with v1.2 (shipped)"
```
