# Behavioral Eval Variance Report — subagent-propagation

**Scenario:** `subagent-propagation`
**Iterations:** 5
**Captured:** 2026-05-07T16:28:32Z

## Per-assertion pass rates

| # | Description | Pass | Fail | Pass rate | Classification |
|---|---|---|---|---|---|
| 0 | explore\|subagent\|spawn\|Mentions spawning a subagent or using the Task tool | 5 | 0 | 100% | stable |
| 1 | find_symbol\|find_referencing_symbols\|Spawn prompt contains a Serena reference (literal banner copy, find_symbol, or find_referencing_symbols paraphrase) | 1 | 4 | 20% | broken |
| 2 | references\|symbol\|Spawn prompt carries the user's symbol-search task into the subagent | 2 | 3 | 40% | flaky |

## Classification thresholds

- `stable`: ≥ 90% pass rate
- `flaky`: 50–89% pass rate
- `broken`: < 50% pass rate

## Mutation test (PR2)

_Pending — appended after PR2 is executed._
