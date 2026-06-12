# behavioral-evaluation — delta spec: coverage-report-precision

## ADDED Requirements

### Requirement: Coverage report counts only behavioral outcome lines

The behavioral-pack coverage report MUST count probabilistic-verb matches only in outcome lines of a capability spec. It MUST exclude markdown headings (lines beginning with `#`), MUST exclude `GIVEN`/`WHEN` precondition lines, and MUST exclude static-artifact assertions (clauses whose subject is a doc, banner, `.md` file, or config flag — already covered deterministically by grep-based tests). A documentation/guidance capability whose spec asserts only static-artifact content MUST NOT be reported as an uncovered behavioral gap, while a capability with genuine probabilistic outcome assertions and no behavioral pack MUST still be flagged.

#### Scenario: Documentation/guidance capability is not over-flagged
- **GIVEN** a capability whose spec's probabilistic-verb matches are all static-artifact assertions (e.g. "the banner MUST mention X", "appears in `internal-truth.md`")
- **WHEN** the coverage report runs
- **THEN** the capability falls below the probabilistic-outcome threshold and is not listed as uncovered

#### Scenario: Heading and precondition noise is not counted
- **GIVEN** a capability whose probabilistic-verb matches occur only in `### Requirement:` / `#### Scenario:` headings or `Given`/`When` lines
- **WHEN** the coverage report runs
- **THEN** those matches are excluded and the capability is not flagged

#### Scenario: Genuine behavioral gap is still flagged
- **GIVEN** a skill-execution capability with at least the threshold of probabilistic outcome assertions (in `THEN` or requirement-body lines) and no behavioral pack
- **WHEN** the coverage report runs
- **THEN** the capability is reported `UNCOVERED`
