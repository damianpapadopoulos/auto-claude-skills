---
name: supply-chain-investigation
description: Use when investigating a published supply-chain attack on a registry package (npm, Maven, PyPI, Go, Gradle) — advisory-driven org-wide audit. Triggers on attack-language ("compromised", "malicious", "hijacked", "backdoored", "typosquatted"). NOT for routine CVE scanning — that routes to security-scanner.
---

# Supply-Chain Attack Investigation

Orchestrated workflow for determining whether a published supply-chain attack affects your GitHub organization. Uses `gh` CLI only — no new tool dependencies.

## When to Use

| Use this skill | Use `security-scanner` instead |
|----------------|-------------------------------|
| Published advisory: "X@1.14.1 contains a RAT dropper" | Routine REVIEW phase scan for outdated deps |
| News: "Y package was hijacked" | Generic CVE question: "is CVE-NNNN exploitable?" |
| Investigating org-wide blast radius | Scanning current repo's SBOM |
| Need pin-tightness verdict per repo | Need install-time vulnerability list |
| Need CI log forensics since timestamp T | Need a fresh SAST report |

If both fit, the trigger discriminator in `config/default-triggers.json` will route to whichever has stronger signal. When in doubt, start with this skill — it falls back to recommending `security-scanner` for non-attack scenarios.

## Workflow

### Step 1 — PARSE

Accept advisory input from the user. Supported shapes:

- Advisory URL (GHSA-XXXX, PyPA, GitHub Security Advisories)
- Plain text describing the attack
- News article link

Extract and present to user for confirmation:

| Field | Source |
|-------|--------|
| Package name | URL path, advisory body, or user prompt |
| Ecosystem | npm / Maven / PyPI / Go / Gradle |
| Compromised versions | Advisory body |
| Last-known-good version | Advisory body or registry |
| Publish timestamp (UTC) | Advisory metadata |
| IOCs | Malicious transitive deps, exfil domains, file paths from advisory |

If the user provides only a package name without an advisory, ask once for the compromised version range before proceeding. Don't guess.

### Step 2 — ORG SCAN

Search every repo in the target org for manifests/lockfiles containing the package. Ecosystem-specific commands documented in `references/ecosystem-patterns.md`. High-level shape:

```bash
gh search code --owner <ORG> "<package>" --filename package.json --json repository,path -L 100
gh search code --owner <ORG> "<package>" --filename package-lock.json --json repository,path -L 100
# ... (per ecosystem — see references/ecosystem-patterns.md)
```

**Handle false positives.** Substring matches will surface — e.g., searching `axios` matches `gaxios`. Verify each hit against the actual dependency tree, not just text presence.

### Step 3 — PIN AUDIT

For each hit, download the manifest/lockfile and classify pin tightness:

| Class | Example | Risk |
|-------|---------|------|
| **Exact pin** | `"axios": "1.14.0"` (npm), `==1.14.0` (Python) | Safe IF version is not in compromised range |
| **Range** | `"axios": "^1.13.5"` (npm), `>=1.0,<2.0` (Python), `[1.0,2.0)` (Maven) | Risky — may resolve to compromised version |
| **Unpinned** | `"axios": "*"`, `requests` (no version) | Highest risk — always latest |
| **SNAPSHOT / dynamic** | `1.+` (Gradle), `*-SNAPSHOT` (Maven) | Always risky |

Read lockfile (if present) to extract the resolved version. Per-ecosystem patterns in `references/ecosystem-patterns.md`.

```bash
gh api repos/<ORG>/<REPO>/contents/<PATH> --jq '.content' | base64 -d
```

For large files (>1MB), use git blob API:
```bash
SHA=$(gh api repos/<ORG>/<REPO>/contents/<PATH> --jq '.sha')
gh api "repos/<ORG>/<REPO>/git/blobs/$SHA" --jq '.content' | base64 -d
```

### Step 4 — CI RISK

Read each affected repo's CI configuration (`.github/workflows/*.yml`, `Dockerfile`, `Makefile`, `cloudbuild.yaml`, `Jenkinsfile`). Classify the dependency install command:

| Ecosystem | Safe (respects pins/locks) | Risky (may resolve newer) |
|-----------|--------------------------|---------------------------|
| npm | `npm ci` | `npm install`, `npm update` |
| yarn | `yarn install --frozen-lockfile` | `yarn install`, `yarn upgrade` |
| pnpm | `pnpm install --frozen-lockfile` | `pnpm install`, `pnpm update` |
| Maven | Pinned versions + enforcer plugin | Version ranges, SNAPSHOT, `mvn versions:use-latest-releases` |
| Gradle | Dependency locking enabled | Dynamic versions (`1.+`) |
| pip | `pip install -r requirements.txt` with `==` pins, `--require-hashes` | Unpinned, `--upgrade` |
| Poetry | `poetry install --no-update` | `poetry update`, `poetry install` without lock |
| Pipenv | `pipenv install --deploy` | `pipenv install`, `pipenv update` |

Also flag absence of `--ignore-scripts` (npm) which would let postinstall hooks execute — many supply-chain payloads use this.

### Step 5 — LOG FORENSICS

Critical step — many investigations skip this and miss historical resolution evidence.

```bash
gh run list --repo <ORG>/<REPO> -L 100 --json databaseId,createdAt,conclusion,workflowName,displayTitle | \
  jq --arg ts "<COMPROMISE_TIMESTAMP>" '[.[] | select(.createdAt >= $ts)]'
```

For each run since the compromise timestamp:

```bash
gh run view <RUN_ID> --repo <ORG>/<REPO> --log 2>&1 | grep -iE "<compromised-version>|<malicious-dep>|<package>@"
```

Ecosystem-specific log patterns:

- npm: `<package>@<version>` (e.g., `axios@1.14.1`), `added N packages`
- Maven: `Downloading from.*<artifactId>.*<version>`
- Python: `Successfully installed <package>-<version>`, `Downloading <package>-<version>`

### Step 6 — VERDICT

Per-repo verdict scale:

| Verdict | Criteria |
|---------|----------|
| **COMPROMISED** | Compromised version found in lockfile, CI logs, OR malicious transitive dep present |
| **AT RISK** | No compromise evidence yet, but pinning OR CI command could allow resolution (range pin + risky install command) |
| **SAFE WITH CAVEATS** | Pins/locks resolve to safe versions, but CI uses risky install commands that could bypass them |
| **SAFE** | Dependencies pinned to safe versions AND CI uses pin-respecting commands |

Org-wide rolls up to worst-case verdict.

## Output Format

Present findings as:

```markdown
## Supply-Chain Investigation: <package> (<ecosystem>)

### Attack Summary
- Package: <name>
- Compromised versions: <range>
- Safe version: <last-known-good>
- Payload: <type — RAT / cryptominer / exfil / etc.>
- Publish: <UTC timestamp>
- Advisory: <URL>

### Affected Repos
| Repo | Manifest | Declared | Resolved | Pin | CI Install | CI Logs | Verdict |
|------|----------|----------|----------|-----|------------|---------|---------|
| ... |

### CI Log Analysis
- Total runs checked since compromise: N
- Hits: M

### Overall Org Verdict
<worst-case>

### Prioritized Remediation
1. **Immediate**: Pin/override to safe version, block IOC domains/IPs
2. **Short-term**: Switch CI to lock-respecting commands, add `--ignore-scripts` or `--require-hashes`
3. **Long-term**: Enforce lock-file commits, add dependency review workflows
```

If compromise is detected, recommend checking developer machines and CI runners for payload artifacts (IOC file paths, exfil domain DNS, suspicious processes).

## References

- [Ecosystem-specific patterns](references/ecosystem-patterns.md) — manifest/lockfile/pin/CI-command reference per ecosystem
- [OSV.dev](https://osv.dev) — aggregated open-source advisory database
- [GitHub Security Advisories](https://github.com/advisories) — primary advisory source for org-wide context

## Related Skills

- `security-scanner` — proactive SAST + CVE scan during REVIEW. Use it for routine vulnerability detection; this skill is for advisory-driven org audit.
- `incident-analysis` — for production symptoms (latency spikes, crashes). Different trigger surface.
