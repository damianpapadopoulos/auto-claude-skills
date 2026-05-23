# Ecosystem Patterns Reference

Per-ecosystem manifest, lockfile, pin syntax, and CI install command patterns for the `supply-chain-investigation` skill.

## npm / Node.js

**Manifests to search:**
```bash
gh search code --owner <ORG> "<package>" --filename package.json --json repository,path -L 100
gh search code --owner <ORG> "<package>" --filename package-lock.json --json repository,path -L 100
gh search code --owner <ORG> "<package>" --filename yarn.lock --json repository,path -L 100
gh search code --owner <ORG> "<package>" --filename pnpm-lock.yaml --json repository,path -L 100
```

**Pin syntax:**
- `"axios": "1.14.0"` — exact pin (safe)
- `"axios": "^1.13.5"` — caret range (may resolve compromised)
- `"axios": "~1.13.5"` — tilde range (may resolve compromised within minor)
- `"axios": "*"` or `"axios": "latest"` — always latest (highest risk)

**Lockfile resolved version:**
- `package-lock.json` → `dependencies["axios"].version` or `packages["node_modules/axios"].version`
- `yarn.lock` → block starting with `axios@^1.13.5:` followed by `version "1.14.1"`
- `pnpm-lock.yaml` → `/axios/1.14.1:` block

**CI install command safety:**
| Safe | Risky |
|------|-------|
| `npm ci` | `npm install`, `npm update` |
| `yarn install --frozen-lockfile` | `yarn install`, `yarn upgrade` |
| `pnpm install --frozen-lockfile` | `pnpm install`, `pnpm update` |

**Extra defense:** `--ignore-scripts` blocks postinstall hooks (commonly used by supply-chain payloads).

**CI log signatures (resolved version evidence):**
- `npm: added N packages`
- `axios@1.14.1`
- `Downloading axios-1.14.1.tgz`

## Maven

**Manifests to search:**
```bash
gh search code --owner <ORG> "<artifactId>" --filename pom.xml --json repository,path -L 100
```

**Key files to check:**
- `pom.xml` — direct `<dependency>` entries, `<dependencyManagement>`, property-driven versions (`${name.version}`)
- BOM imports — `<type>pom</type><scope>import</scope>` in `<dependencyManagement>` may pin transitive versions
- Parent POMs — version inherited via `<parent>` reference

**Pin syntax:**
- `<version>1.14.0</version>` — exact (safe)
- `<version>[1.0,2.0)</version>` — range (risky)
- `<version>1.14.0-SNAPSHOT</version>` — SNAPSHOT (always dynamic, risky)
- `<version>${axios.version}</version>` — property reference (trace to declaration)

**Transitive dependency exposure:** A compromised artifact may not appear in any manifest if it's pulled in via a shared BOM. Supplement manifest search with `dependency:tree` output from CI logs.

**CI install command safety:**
| Safe | Risky |
|------|-------|
| Pinned versions + `<requireUpperBoundDeps>` enforcer rule | Version ranges, SNAPSHOT deps, `mvn versions:use-latest-releases` |

**CI log signatures:**
- `Downloading from central: .*axios.*1.14.1`
- `[INFO] BUILD SUCCESS` with `dependency:tree` output

## Gradle

**Manifests to search:**
```bash
gh search code --owner <ORG> "<artifactId>" --filename build.gradle --json repository,path -L 100
gh search code --owner <ORG> "<artifactId>" --filename build.gradle.kts --json repository,path -L 100
```

**Pin syntax:**
- `implementation 'group:artifact:1.14.0'` — exact (safe)
- `implementation 'group:artifact:1.+'` — dynamic (risky)
- `platform('group:bom:1.0')` — BOM-managed (generally safe if BOM pinned)

**Lockfile (if enabled):**
- `gradle.lockfile` — exact pinned versions

**CI install command safety:**
| Safe | Risky |
|------|-------|
| Dependency locking enabled + pinned versions | Dynamic versions, `--write-locks` |

## Python / PyPI

**Manifests to search:**
```bash
gh search code --owner <ORG> "<package>" --filename requirements.txt --json repository,path -L 100
gh search code --owner <ORG> "<package>" --filename setup.py --json repository,path -L 100
gh search code --owner <ORG> "<package>" --filename pyproject.toml --json repository,path -L 100
gh search code --owner <ORG> "<package>" --filename Pipfile --json repository,path -L 100
gh search code --owner <ORG> "<package>" --filename setup.cfg --json repository,path -L 100
gh search code --owner <ORG> "<package>" --filename constraints.txt --json repository,path -L 100
```

**Key files to check:**
- `requirements.txt` — `==`, `>=`, `~=`, or unpinned
- `Pipfile.lock`, `poetry.lock`, `uv.lock` — exact resolved versions
- `pyproject.toml` — `[project.dependencies]`, `[tool.poetry.dependencies]`
- `constraints.txt` — pip constraints (can pin transitive)

**Pin syntax:**
- `requests==2.32.0` — exact (safe)
- `requests>=2.30,<3.0` — range (risky)
- `requests` (no specifier) — always latest (highest risk)
- `requests~=2.30` — compatible release (range, risky)

**CI install command safety:**
| Safe | Risky |
|------|-------|
| `pip install -r requirements.txt` with `==` pins | Unpinned, `pip install --upgrade` |
| `pip install --require-hashes` | `pip install <pkg>` (no requirements file) |
| `poetry install --no-update` | `poetry update`, `poetry install` without lock |
| `pipenv install --deploy` | `pipenv install`, `pipenv update` |

**CI log signatures:**
- `Successfully installed requests-2.33.0`
- `Downloading requests-2.33.0-py3-none-any.whl`

## Go

**Manifests to search:**
```bash
gh search code --owner <ORG> "<module>" --filename go.mod --json repository,path -L 100
gh search code --owner <ORG> "<module>" --filename go.sum --json repository,path -L 100
```

**Pin syntax:**
- `go.mod` always has exact versions for direct deps (e.g., `github.com/foo/bar v1.2.3`)
- `go.sum` has hashes for integrity verification (safe if committed)

**CI install command safety:**
| Safe | Risky |
|------|-------|
| `go build` / `go test` (uses go.mod + go.sum) | `go get -u`, `go mod tidy -e` without review |

**Special:** Go's module proxy and checksum database (`GOSUMDB`) provide additional integrity. Verify `GONOSUMCHECK` is not set in CI.
