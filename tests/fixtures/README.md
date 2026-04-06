# Test Fixtures — Example Vocabulary

Test fixtures and skill examples use a shared fictional service topology.
This keeps examples consistent, org-agnostic, and semantically meaningful
for model reasoning (cascade detection, caller analysis, shared-dependency
patterns).

## Service Topology

| Role | Name | Notes |
|------|------|-------|
| API gateway / proxy | `api-gateway` | Entry point, fans out to backends |
| Authorization database | `SpiceDB` | Open-source product (real name) |
| Recommendation backend | `recommendation-service` | Stateless, calls SpiceDB |
| Messaging / notification | `notification-service` | Async, can trigger retry storms |
| Calendar service | `calendar` | Independent backend |
| User service (Java) | `com.example.user.UserController` | For source-analysis examples |

## Infrastructure

| Context | Name |
|---------|------|
| GCP K8s project | `example-k8s-prod` |
| GCP cluster | `example-cluster-prod` |
| GitHub org | `example-org` |
| Monitoring project | `example-monitoring` |

## Conventions

- **RFC 2606 `example.*`** for domains, orgs, and projects
- **`{placeholder}`** template variables where user substitution is expected
- **Open-source products** keep their real names (SpiceDB, FluxCD, Handlebars)
- **Generic service names** for already-neutral names (calendar, user-service)
