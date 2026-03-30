## ADDED Requirements

### Requirement: SLO Config Enrichment
Stage 1 MUST attempt to fetch SLO service definitions from GitHub when `github_org` is provided and `gh` is authenticated. The enrichment MUST short-circuit with structured status artifacts when preconditions are not met. SLO service names MUST be normalized using the same rules as `service_key`.

#### Scenario: SLO fetch succeeds
- **WHEN** github_org is provided AND gh is authenticated AND slo-config.yaml exists
- **THEN** slo-services.json contains normalized service names AND slo-source-status.json has status "ok"

#### Scenario: SLO fetch unavailable
- **WHEN** github_org is empty OR gh is not authenticated
- **THEN** slo-services.json is empty array AND slo-source-status.json has status "unavailable" with reason

### Requirement: Routing Validation
Stage 4 MUST check for zero-channel policies and unlabeled high-noise policies as routing gaps. Findings MUST be promoted to Investigate items when incident thresholds are exceeded.

#### Scenario: Zero-channel policy with high incidents
- **WHEN** a policy has empty notification_channels AND enabled is true AND raw_incidents > 10
- **THEN** the policy is promoted to Investigate with "add notification channel or disable" action

#### Scenario: Unlabeled high-noise policy
- **WHEN** a policy has no squad/team/owner label AND raw_incidents > 10
- **THEN** the policy is promoted to Investigate with generic ownership language

#### Scenario: Label inconsistency with incidents
- **WHEN** a cluster has label_inconsistency true AND raw_incidents > 5
- **THEN** the cluster is promoted to Investigate as a cluster-level finding

### Requirement: SLO Coverage Cross-Reference
Stage 4 MUST cross-reference cluster service_keys against slo-services.json when SLO data is available. Only clusters with signal_family in (error_rate, latency, availability) SHALL be considered.

#### Scenario: SLO migration candidate
- **WHEN** a service_key has total_raw_incidents > 20 across user-facing clusters AND is NOT in slo-services.json
- **THEN** surface as Coverage Gap with "SLO review candidate" language

#### Scenario: SLO redundancy candidate
- **WHEN** a service_key IS in slo-services.json AND has noisy user-facing threshold alerts
- **THEN** surface as Needs Decision with "review for redundancy or intentional overlap" language

### Requirement: IaC Location Resolution
Stage 5 MUST attempt to upgrade IaC Location tier via gh search code for Do-Now-ready items. Search MUST use policy ID as primary token and identifying fragment as secondary. GitHub search MUST NOT upgrade Unknown to Search Required on failure.

#### Scenario: Search finds match
- **WHEN** gh search code returns 1+ results for policy ID
- **THEN** IaC Location upgrades to Likely with repo:path reference

#### Scenario: Search finds nothing
- **WHEN** gh search code returns 0 results after both tokens
- **THEN** IaC Location preserves original tier unchanged

### Requirement: Service Key Extraction
compute-clusters.py MUST extract a deterministic service_key from condition_query and condition_filter. Priority chain MUST be: container_name → container → application → service → null. Values MUST be normalized (lowercase, strip env suffixes, unify separators).

#### Scenario: Container label in PromQL
- **WHEN** condition_query contains `container="diet-suggestions-prod"`
- **THEN** service_key is "diet-suggestions" (normalized)

#### Scenario: No extractable service identity
- **WHEN** condition_filter and condition_query contain no container, application, or service labels
- **THEN** service_key is null

### Requirement: Signal Family Classification
compute-clusters.py MUST classify each cluster's signal_family as error_rate, latency, availability, or other. Classification MUST derive from condition_query/filter content first, then metric_type name.

#### Scenario: Error rate from status match
- **WHEN** condition_query contains `status=~"5.."`
- **THEN** signal_family is "error_rate"

#### Scenario: Default classification
- **WHEN** no error, latency, or availability signals are detected
- **THEN** signal_family is "other"
