# Delta Spec: pdlc-safety — evaluator-surface push advisory

## ADDED Requirements

### Requirement: Evaluator-surface advisory on push

The push gate MUST emit an advisory (never a permission denial) when a `git push` command's branch diff (mainline merge-base to HEAD) touches any declared evaluator surface, naming the touched files. The evaluator-surface list MUST be a superset of the drift-canary gate-enforcement manifest (`hooks/openspec-guard.sh` + `_GATE_ENFORCE_LIBS`) and MUST include `.verify.yml`. The predicate MUST fail open: an unresolvable diff base or git error yields no advisory and never blocks.

#### Scenario: Push touching .verify.yml warns but proceeds

- GIVEN a branch whose diff against the mainline merge-base modifies `.verify.yml`
- WHEN the agent runs `git push` and all deny gates pass
- THEN the hook output contains an evaluator-surface advisory naming `.verify.yml`
- AND the hook emits no `permissionDecision` of `deny` for that advisory

#### Scenario: Advisory emits outside SHIP phase

- GIVEN the same branch state with no SHIP-phase signal file for the session
- WHEN the agent runs `git push`
- THEN the evaluator-surface advisory is still emitted as `additionalContext` (not silently dropped)

#### Scenario: Clean branch stays silent

- GIVEN a branch whose diff touches only `README.md`
- WHEN the agent runs `git push`
- THEN no evaluator-surface advisory is emitted

#### Scenario: Canary manifest growth is caught by CI

- GIVEN a new lib is added to `_GATE_ENFORCE_LIBS` in `hooks/session-start-hook.sh`
- WHEN `tests/test-evaluator-surface.sh` runs without the same lib added to `_EVALUATOR_SURFACES`
- THEN the test fails
