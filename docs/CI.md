# CI & Branch Protection

This repo ships a GitHub Actions workflow that validates every active OpenSpec
change on every pull request. The workflow alone produces a **check**;
promoting it to a **hard block** requires a one-time GitHub Settings change.

## OpenSpec Validate workflow

**File:** `.github/workflows/openspec-validate.yml`
**Job name:** `openspec-validate`
**Check name (used for branch protection):** `OpenSpec Validate`

**What it does:**

1. Runs on every `pull_request` (opened, synchronize, reopened, ready_for_review).
2. Installs the OpenSpec CLI at a pinned version (`@fission-ai/openspec@1.3.0`).
3. Runs `scripts/validate-active-openspec-changes.sh`, which:
   - Discovers all top-level directories under `openspec/changes/`, excluding `archive/`.
   - Runs `openspec validate <slug>` on each.
   - Aggregates failures across every active change (does not fail-fast).
   - Exits `1` if any validation fails, `0` if all pass or there are no active changes.

**Failure modes:**

- `openspec` CLI missing → loud failure (not silent skip).
- Any active change invalid → workflow red.
- No `openspec/changes/` directory → exits 0, no-op (default-mode repos).
- Only `openspec/changes/archive/` exists → exits 0, no-op.

## Making the gate a required check (hard block)

The workflow produces a check that **must be manually required** in branch
protection rules for it to actually block merges. Without this step, PRs can
merge even when the check is red.

1. Go to **Settings → Branches** in the GitHub repo.
2. Under **Branch protection rules**, click **Add rule** (or edit the existing rule for `main`).
3. **Branch name pattern:** `main`.
4. Check **Require status checks to pass before merging**.
5. Check **Require branches to be up to date before merging** (recommended).
6. In the status-check search box, type `OpenSpec Validate` and select it.
7. Click **Create** (or **Save changes**).

After this one-time setup, any PR with an invalid active OpenSpec change is
blocked from merging until the spec is fixed.

## Emergency: turning off the gate

If a false positive blocks legitimate work:

- **Short-term:** In Branch Protection, temporarily uncheck `OpenSpec Validate` from the required checks list. Fix and re-enable.
- **Medium-term:** Fix the script at `scripts/validate-active-openspec-changes.sh` and re-enable.
- **Never:** Do not use `git push --no-verify` or admin-override as a habit; those bypass the signal the gate is designed to surface.

## Pinning the OpenSpec CLI version

The workflow pins `@fission-ai/openspec@1.3.0`. To upgrade:

1. Open a PR that updates the version string in `.github/workflows/openspec-validate.yml`.
2. Verify the workflow still passes on the PR itself.
3. Merge.

Do not use `@latest` in CI: a breaking OpenSpec release would silently break
every subsequent PR until someone noticed.

## Local validation

Run the same checks locally before pushing:

```bash
bash scripts/validate-active-openspec-changes.sh
```

Exits 0 (green) or 1 (red) with aggregated output per change.

## Relationship to `spec-driven` preset

The `spec-driven` preset (see CLAUDE.md "Spec Persistence Modes") is designed
to be paired with this gate. Repos that set `{"preset": "spec-driven"}`
commit `openspec/changes/<feature>/` upfront during DESIGN phase; the gate
then enforces that every committed change is valid before merging.

Default-mode repos (no preset) typically have zero active changes except
during a ship window, so the gate is a cheap no-op for them.
