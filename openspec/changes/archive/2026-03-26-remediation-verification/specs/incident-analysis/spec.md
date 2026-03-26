## ADDED Requirements

### Requirement: Scheduling Constraint Inventory
The inventory step (Step 2b) MUST capture scheduling constraints for k8s workloads: pod affinity/anti-affinity rules, topologySpreadConstraints, node affinity, taints and tolerations. The agent MUST query these from the same deployment spec used for resource requests.

#### Scenario: K8s deployment with topologySpreadConstraints
- **WHEN** investigating an incident involving a k8s deployment that has topologySpreadConstraints configured
- **THEN** the Step 2b inventory MUST include the topologySpreadConstraints configuration (maxSkew, topologyKey, whenUnsatisfiable)

#### Scenario: kubectl unavailable
- **WHEN** kubectl cannot reach the cluster (private endpoint, no VPN, auth expired)
- **THEN** the agent MUST fall back to GitOps manifests via `gh api` or `git show` to check deployment configuration
- **AND** if neither is available, the agent MUST flag affected inventory fields as unverified

### Requirement: Interpretation Guidance for Equivalent Mechanisms
The skill MUST include guidance that topologySpreadConstraints and podAntiAffinity both control pod distribution. The agent MUST distinguish enforcement level: soft (ScheduleAnyway, preferredDuringScheduling) vs hard (DoNotSchedule, requiredDuringScheduling).

#### Scenario: Deployment has topologySpreadConstraints but no podAntiAffinity
- **WHEN** a deployment has topologySpreadConstraints with topologyKey=kubernetes.io/hostname
- **THEN** the agent MUST recognize this as a functionally equivalent mechanism to podAntiAffinity for hostname-based spreading

### Requirement: Current State Field in Action Items
The postmortem action items format MUST include a "current state" field. The agent MUST populate this field with the relevant existing configuration before recommending changes. The agent MUST check for functionally equivalent configurations, not just exact field matches.

#### Scenario: Action item for scheduling change when constraints exist
- **WHEN** the agent drafts an action item recommending a scheduling change (e.g., "add podAntiAffinity")
- **AND** the inventory shows a functionally equivalent mechanism already exists (e.g., topologySpreadConstraints)
- **THEN** the "current state" field MUST reference the existing mechanism
- **AND** the action item SHOULD be reframed to address the specific gap (e.g., "change enforcement from ScheduleAnyway to DoNotSchedule")

#### Scenario: Current state cannot be determined
- **WHEN** the agent cannot verify the current state of infrastructure targeted by an action item
- **THEN** the "current state" field MUST state "Not verified against live config"
