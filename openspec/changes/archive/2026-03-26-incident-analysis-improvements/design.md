# Design: Incident Analysis Improvements

## Architecture
The existing monolithic incident-analysis pipeline (MITIGATE → CLASSIFY → INVESTIGATE → EXECUTE → VALIDATE → POSTMORTEM) is extended in-place — no architectural overhaul.

**Disambiguation probes** add a bounded query mechanism between CLASSIFY and INVESTIGATE's deep dive. CLASSIFY emits a SHORTLIST artifact (leader + up to 2 runner-ups with probe references). Probes execute one pre-canned read-only query per runner-up, feed evidence into the existing signal evaluator, and rerank via the unchanged scorer. Anti-looping is enforced via a `classification_fingerprint` derived from the pre-probe evidence snapshot.

**Step 4b source analysis** is placed within INVESTIGATE between trace correlation (Step 4) and hypothesis formation (Step 5). It resolves deployed code at the git ref (not HEAD), maps stack frames to source files, and checks recent commits for regressions. Gated on bad-release category only.

## Dependencies
- No new external dependencies
- GitHub API (`gh api`) used by Step 4b for source code access (existing tool, not new)
- Playbook schema extended with optional `queries` + `disambiguation_probe` fields

## Decisions & Trade-offs

### Multi-agent parallelism rejected (unanimous)
PR #38 proposed 5 parallel agents. Rejected because: causal chain (log → k8s → metric → hypothesis) is the skill's core value; parallel agents break it; coordinator synthesis from independent summaries produces lower-quality hypotheses; wall-clock savings ~0-10s negated by spawn overhead; context budget 3-4x higher.

### Bounded disambiguation over full differential
A full "CLASSIFY emits a differential" approach would duplicate existing scoring machinery. Instead, probes only flip signal states and the existing scorer re-ranks — one mechanism, no architectural churn.

### Step 4b placement (not Step 3b, not separate stage)
Before trace correlation is too early (trace hop can shift target service). After INVESTIGATE is too late (code evidence can't shape hypothesis). Step 4b between Steps 4 and 5 is the right position.

### SLO signal as context-only (not playbook-wired)
SLO burn rate alerts don't map cleanly to a single playbook category. The signal enriches investigation context without driving classification. A future playbook could reference it.
