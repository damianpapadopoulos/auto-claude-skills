# Error Taxonomy and Exit Code Guide

Extracted from SKILL.md Step 2 (Extract Key Signals). Referenced inline from the investigation spine.

**Error taxonomy — prioritize by diagnostic value:**
Not all errors are equally informative. Classify extracted signals into three tiers:

| Tier | Type | Diagnostic value | Examples |
|------|------|-----------------|----------|
| 1 | **Anomalous** — unexpected exception types, application errors in unexpected services | Highest — often points to the **trigger** (why) | Template/parsing exceptions in message consumers, schema errors during read paths, application exceptions in services adjacent to the symptomatic one, message broker delivery failures (AMQ/Artemis/Kafka/JMS delivery errors) |
| 2 | **Infrastructure** — standard platform/network/resource errors | Medium — tells you **where** the system is breaking | `TimeoutException`, `ConnectionRefused`, `DeadlineExceeded`, `OOMKilled`, deadlocks |
| 3 | **Expected application** — known error types **at verified baseline rates** | Low — tells you **what** is normal | Authentication failures at typical rates, validation errors, 4xx responses |

**Investigate Tier 1 errors first**, even if they appear in services outside your current scope. A single anomalous error in an adjacent service is often more diagnostic than dozens of infrastructure errors in the symptomatic service. When Tier 1 errors are found in adjacent services, they are candidates for scope expansion — note them for Step 3.

**Message broker signals — always Tier 1:** When message delivery failures are found (e.g., `AMQ154004: Failed to deliver message`, Kafka consumer lag spikes, JMS `TransactionRolledbackException`), **immediately query the failing consumer service's own container logs** for the exception that caused the delivery failure. The consumer's error (e.g., a parsing exception, a constraint violation, a template compilation error) is the root cause; the broker's delivery failure is the amplification mechanism. A poison-pill message causes an infinite retry loop that exhausts connection pools and threads, producing infrastructure-level symptoms (connection pool exhaustion, timeouts, cascading failures) that mask the application-layer trigger. Do not investigate the downstream infrastructure symptoms until the consumer-side exception is identified.

**Quantitative baseline verification (mandatory before Tier 3 classification):** An error may only be classified as Tier 3 if its rate during the incident matches a verified baseline from a non-incident period (same endpoint, same error class, comparable time window). "This looks like it always happens" is not evidence — query the baseline rate and compare numerically. If the baseline cannot be verified (e.g., logs expired, no comparable window), classify as Tier 2 until proven otherwise. An order-of-magnitude increase from baseline reclassifies any error to Tier 1 regardless of how "expected" the error type appears.

**Container exit code guide** (when container termination status is available from pod describe or events):

| Exit Code | Signal | Meaning | Investigation Route |
|-----------|--------|---------|-------------------|
| 0 | Normal exit | Container completed successfully | Check if this is a long-running service that should not exit — possible entrypoint/command misconfiguration |
| 1 | Application error | Uncaught exception or assertion failure | Check previous container logs for stack trace → route to bad-release or config-regression |
| 137 | SIGKILL (OOMKilled) | Kernel OOM killer terminated the process | Check memory limits vs actual usage → route to resource-overload or node-resource-exhaustion. A restart will not help if limits are too low. |
| 139 | SIGSEGV | Segmentation fault in native code | Check recent deployment for native dependency changes → route to bad-release |
| 143 | SIGTERM | Graceful termination timeout exceeded | Check `terminationGracePeriodSeconds`, shutdown hooks, long-running connections. Not necessarily a failure — may indicate slow shutdown. |

Use exit codes to route investigation before proposing mitigation. Exit code 137 (OOMKilled) means restart is pointless — the pod will OOM again. Exit code 1 after a deploy points to bad-release, not workload-restart.
