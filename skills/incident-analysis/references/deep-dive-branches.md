# Deep-Dive Branches — Conditional Investigation Procedures

Extracted from SKILL.md Step 3 (Single-Service Deep Dive). These conditional branches execute when specific signals are present. Referenced inline from the investigation spine.

**CrashLoopBackOff triage (conditional — when `crash_loop_detected` signal is present):**

Before proposing workload-restart, complete the diagnostic sequence defined in the `workload-restart` playbook's `investigation_steps`. The sequence requires: pod describe → scoped events → termination reason and exit code (see exit code guide in Step 2) → previous container logs → deployment/probe configuration → rollout history correlation. Each step may redirect to a different root-cause playbook:
- Exit code 137 (OOMKilled) → resource-overload or node-resource-exhaustion, not restart
- Exit code 1 with stack trace after recent deploy → bad-release investigation
- Events show ImagePullBackOff or CreateContainerConfigError → pod-start failure branch below
- Crash onset correlates with rollout timestamp → bad-release-rollback investigation
- Only if triage is inconclusive and no other playbook has higher confidence does workload-restart remain a candidate.

**Probe and startup-envelope checks (conditional — when `liveness_probe_failures` signal is present or pod restart count is high without clear application errors):**

Before attributing failures to application state, verify whether probe configuration is appropriate:
1. **Probe configuration review:** Extract `initialDelaySeconds`, `timeoutSeconds`, `periodSeconds`, `failureThreshold`, and `startupProbe` (if any) from the pod spec
2. **Startup time analysis:** Compare `initialDelaySeconds` to actual container startup time. If startup takes longer than the initial delay and no startupProbe is configured, liveness probes will kill the container before it is ready — this is a probe misconfiguration, not an application failure
3. **Timeout budget:** Is `timeoutSeconds` realistic for what the probe endpoint does? If the probe hits a database or external service, network latency may exceed the timeout under load
4. **Restart cadence:** Calculate time between restarts. If it matches `initialDelaySeconds + (failureThreshold x periodSeconds)`, the probe is killing the container during startup — fix probe config, not restart
5. **Dependency reachability:** Does the probe endpoint depend on services that are currently unavailable? (database, cache, upstream API). If so, the probe failure is a symptom of dependency failure — route to dependency-failure investigation

Routing from probe findings — **this branch is guidance-only (no autonomous mutations)**:
- Probe timing causes restarts during startup → record "probe misconfiguration" as root cause in the investigation synthesis and recommend a config fix (increase `initialDelaySeconds`, add `startupProbe`) as a **postmortem action item**. Do NOT propose workload-restart — a restart will hit the same probe wall. There is no commandable playbook for probe config changes; the fix is a code/manifest change tracked through the normal development workflow.
- Probe endpoint depends on unavailable dependency → route to dependency-failure investigation
- Probe config is reasonable and application genuinely fails health checks → continue with workload-failure classification

**Pod-start failure branch (conditional — when events show `ImagePullBackOff`, `ErrImagePull`, or `CreateContainerConfigError`):**

These symptoms indicate the pod cannot start at all — this is fundamentally different from a running application crashing. Investigate before classifying:

1. **ImagePullBackOff / ErrImagePull:**
   - Extract the exact error message from pod events: "unauthorized" (credential issue), "not found" or "manifest unknown" (wrong image/tag), "timeout" or "connection refused" (registry unreachable)
   - Verify the image reference (registry, repository, tag) in the deployment spec
   - Check `imagePullSecrets` configuration: does the Secret exist, is it type `kubernetes.io/dockerconfigjson`, are credentials valid and not expired?
   - If image tag was recently changed → route to bad-release (wrong tag pushed)
   - If `imagePullSecrets` were changed or Secret is missing → route to config-regression
   - If registry is unreachable and no config changed → route to dependency-failure (registry as external dependency)

2. **CreateContainerConfigError:**
   - Check for missing ConfigMap or Secret references in the pod spec
   - Check if a referenced ConfigMap or Secret was recently deleted or renamed
   - Check environment variable references that point to non-existent keys
   - Route to config-regression for further investigation

3. **Volume mount failures** (`FailedMount`, `FailedAttachVolume`):
   - Check PVC status (Pending, Lost, Bound) and StorageClass availability
   - Check if the volume or StorageClass was recently modified
   - Route to infra-failure if the storage backend is unhealthy

This branch is non-mutating — it gathers evidence that feeds back into CLASSIFY for root-cause playbook selection. Do not propose restart or rollback from this branch.
