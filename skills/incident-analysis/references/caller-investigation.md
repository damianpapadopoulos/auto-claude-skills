# Shared-Resource Caller Investigation

Mandatory escalation procedure when a shared dependency (authorization service, database,
message broker, cache, shared API gateway) is identified as the degraded component.

## Detection Heuristic

Any of these confirm a shared dependency:
- Multiple different services show correlated errors in the same time window
- The degraded service's access logs show requests from multiple distinct peer addresses/pods
- The degraded service is a known infrastructure component (SpiceDB, Redis, PostgreSQL, RabbitMQ, etc.)

## Procedure

1. **Identify dominant callers/producers:** Using the best available evidence — access logs (peer addresses), distributed traces, broker consumer metrics, connection pool stats, or infrastructure-as-code — identify the top 3 callers by volume during the incident window. Resolve each to a service name via trace correlation, pod events, or log correlation.
2. **Check each dominant caller's ERROR logs:** Query `severity>=ERROR` for each identified caller service in the same time window. This is the critical step that infrastructure-only investigation misses — a caller may be in a failure/retry loop that is *generating* the shared dependency overload, not just suffering from it.
3. **Check deployment history for all dominant callers:** Query deployments across dominant callers in the preceding 72 hours (not just the incident day). Account for delayed triggers: cached configurations, lazy initialization, and traffic-pattern-dependent code paths that may not execute until weekday/peak hours.
4. **Compare caller distribution to baseline:** Compare the current caller distribution to a **different day's same time window** (or the nearest comparable stable window if traffic patterns changed recently). If a single caller's share increased by >2x compared to baseline, it is a suspect — especially if that caller is also logging errors. If caller identification is unavailable through any evidence source, note "caller distribution not assessed" and flag as an open question.
5. **Check for amplification loops:** If any dominant caller shows error counts disproportionate to normal traffic volume, check for amplification signatures:
   - Rapidly repeating identical error messages from a single source (same exception, same stack frame)
   - Message broker redelivery patterns (JMS/AMQP poison-pill messages that fail processing and get requeued)
   - Transaction management annotations that acquire new connections per retry (`REQUIRES_NEW`, nested transactions)
   - Error counts that cannot be explained by user traffic volume (e.g., 60K errors in a 2-hour window from a low-traffic service)
   When an amplification loop is identified, trace it to the original failing operation — that operation's failure reason (not the resource exhaustion it caused) is the root cause.

This escalation is bounded to the shared resource's known consumer set. It does not permit unbounded global searches.
