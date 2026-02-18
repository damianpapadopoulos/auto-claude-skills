# Shared Contracts Template

## When to Update

- Specialist requests a contract change via SendMessage
- Reviewer rejection reveals a contract mismatch between specialists
- Lead discovers undefined interface between specialists

After every edit: update the Change Log, then SendMessage affected specialists: "Contract updated: [what changed]. Re-read shared-contracts.md."

## Template

Copy below into `shared-contracts.md` at the workspace root. Fill in from plan.

---

```markdown
# SHARED CONTRACTS

> **READ-ONLY for Specialists.** To request changes, SendMessage to the Lead.
> **Last updated by:** Lead
> **Last update reason:** Initial creation from plan

## 1. Data Models

{types and interfaces from plan -- field names, types, descriptions}

## 2. API Signatures

{function signatures, endpoint definitions, parameter and return types}

## 3. Environment and Config

{environment variables, configuration values, ports, feature flags}

## 4. Change Log

| Timestamp | Changed By | What Changed | Reason |
|-----------|-----------|--------------|--------|
| {now} | Lead | Initial creation | Plan analysis |
```

## Example

```markdown
# SHARED CONTRACTS

> **READ-ONLY for Specialists.** To request changes, SendMessage to the Lead.
> **Last updated by:** Lead
> **Last update reason:** Initial creation from plan

## 1. Data Models

### User

| Field | Type | Description |
|-------|------|-------------|
| id | string (UUID) | Primary key |
| email | string | Unique, used for login |
| passwordHash | string | bcrypt hash, never exposed in API |
| createdAt | Date | Account creation timestamp |

### Session

| Field | Type | Description |
|-------|------|-------------|
| id | string (UUID) | Primary key |
| userId | string (UUID) | Foreign key to User.id |
| token | string | Opaque session token |
| expiresAt | Date | Default 24h from creation |

## 2. API Signatures

### POST /api/auth/login
- **Request:** `{ email: string, password: string }`
- **Success (200):** `{ token: string, expiresAt: string }`
- **Errors:** `400` (validation), `401` (invalid credentials)

### POST /api/auth/logout
- **Headers:** `Authorization: Bearer {token}`
- **Success (204):** no body

## 3. Environment and Config

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| DATABASE_URL | string | -- | PostgreSQL connection string |
| SESSION_SECRET | string | -- | Token signing secret |
| SESSION_TTL_HOURS | number | 24 | Session time-to-live |

## 4. Change Log

| Timestamp | Changed By | What Changed | Reason |
|-----------|-----------|--------------|--------|
| 2026-02-18 10:00 | Lead | Initial creation | Plan analysis |
```
