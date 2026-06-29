# Architecture & Design Decisions

## Overview

The DU ETL pipeline follows a clean separation of concerns pattern:

```
Ducks Unlimited API
       ↓ (Extract)
   DUAPIClient
       ↓ (Validate & Transform)
   Chapter List (filtered by state)
       ↓ (Load)
   PostgresLoader
       ↓
   Cloud SQL / PostgreSQL Database
```

## Key Design Decisions

### 1. Python + Requests for API Client

**Decision**: Use Python with `requests` library for API communication.

**Rationale**:
- Simple, readable code
- Built-in retry/retry logic via `urllib3`
- Good error handling
- Easy to test (mock requests)

**Trade-off**: No async/await, but sufficient for single daily run.

### 2. Idempotent Upsert Pattern

**Decision**: Use PostgreSQL `ON CONFLICT DO UPDATE` for inserts.

```sql
INSERT INTO chapters (...) VALUES (...)
ON CONFLICT (chapter_id) DO UPDATE SET
  chapter_name = EXCLUDED.chapter_name,
  updated_at = CURRENT_TIMESTAMP
```

**Rationale**:
- Re-running the pipeline doesn't create duplicates
- Atomic operation (no race conditions)
- Automatic timestamp updates
- Simple and performant

**Alternative Considered**: Delete then insert (would lose historical data, slower).

### 3. Stateless Design

**Decision**: No pipeline state tracking or checkpoints.

**Rationale**:
- Simpler code, fewer moving parts
- Daily full refresh is acceptable (small dataset)
- Idempotent upsert handles duplicates

**Trade-off**: Can't resume partial failures. Would need event log for large-scale pipelines.

### 4. Cloud Run (Serverless) over Fargate/App Engine

**Decision**: Deploy on Google Cloud Run.

**Rationale**:
- Perfect for periodic batch jobs (daily run)
- Pay-per-invocation (pennies per run)
- No infrastructure to manage
- Easy integration with Cloud Scheduler
- VPC connector for private Cloud SQL access

**Alternative Considered**:
- **Cloud Functions**: Too limiting for complex Python (would need async handler)
- **Compute Engine**: Over-engineered, always-on cost
- **Kubernetes**: Way too complex for this scope

### 5. Cloud Scheduler + Cloud Tasks Trigger Pattern

**Decision**: Cloud Scheduler (cron) → Cloud Tasks queue → Cloud Run service.

```
Cloud Scheduler (cron: "0 2 * * *")
       ↓
Cloud Tasks Queue
       ↓
Cloud Run HTTP endpoint
```

**Rationale**:
- Cloud Scheduler can't invoke Cloud Run directly (requires auth)
- Cloud Tasks provides reliable queuing and retries
- Decouples scheduling from execution
- Supports complex retry logic if needed

**Alternative Considered**: EventArc/Pub/Sub (overkill for simple daily runs).

### 6. Cloud SQL (managed database) not self-managed

**Decision**: Use Google Cloud SQL for PostgreSQL.

**Rationale**:
- Automated backups, patching, failover
- VPC-private connectivity
- No DevOps overhead
- Free tier covers this use case
- Zero setup complexity

### 7. Multi-Stage Docker Build

**Dockerfile Strategy**:
- **Build stage**: Install dependencies, compile if needed
- **Runtime stage**: Only include runtime dependencies + app code

**Rationale**:
- Smaller final image (~150MB vs ~400MB)
- Faster deployments
- Better security (no build tools in production)

### 8. Environment-Based Configuration

**Decision**: All configuration via environment variables.

```python
config = {
    "db_host": os.getenv("DB_HOST"),
    "db_password": os.getenv("DB_PASSWORD"),  # Never hardcode!
    ...
}
```

**Rationale**:
- Works everywhere (local, Docker, Cloud Run, K8s)
- Secrets stored in Secret Manager, not config files
- No config file parsing complexity

**Secret Management**:
- Terraform creates Secret Manager secret
- Cloud Run fetches at runtime
- GitHub Actions uses workload identity (no service account keys)

## Database Schema

```sql
CREATE TABLE chapters (
    chapter_id VARCHAR(100) PRIMARY KEY,
    chapter_name VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_state_city ON chapters (state, city);
```

**Design Rationale**:
- `chapter_id` as primary key (immutable, from API)
- Coordinates as DECIMAL (precise for geographic queries)
- State + city index for fast filtering
- Timestamps for audit trail

## Error Handling Strategy

### API Client Errors
- **Network timeouts**: Retry with exponential backoff (3 attempts)
- **5xx errors**: Retry (temporary service issues)
- **4xx errors**: Don't retry (client error, will always fail)
- **Parsing errors**: Log and skip, continue with other records

### Database Errors
- **Connection errors**: Fail fast, log, exit with error code
- **Constraint violations**: Should not occur (upsert handles it)
- **SQL errors**: Log, rollback, exit with error code

### Validation Errors
- **Missing fields**: Log warning, skip record
- **Invalid coordinates**: Log warning, skip record
- **Type errors**: Log warning, skip record

## Logging Strategy

```
INFO: High-level pipeline progress
  - "Fetching chapters from API"
  - "Upserted 42 chapters into database"
  
WARNING: Data quality issues
  - "Chapter missing fields: {missing}"
  - "Invalid latitude 91 for chapter X"
  
ERROR: Pipeline failures
  - "Failed to connect to database: [error]"
  - "ETL pipeline failed: [error]"
```

## Scalability Considerations

### Current Design Supports:
- ✅ Multiple states (change `STATE_FILTER` env var)
- ✅ Different API endpoints (change `DU_API_BASE_URL`)
- ✅ Larger datasets (same code, no changes)

### Future Enhancements:
- **Parallel state processing**: Run multiple Cloud Run jobs concurrently
- **Incremental loads**: Track last-modified timestamps (would need state table)
- **Dead letter queue**: Failed records → Cloud Storage for manual review
- **Monitoring**: Cloud Monitoring alerts for pipeline failures
- **Data lineage**: BigQuery export for analytics

## Cost Analysis

### Monthly Estimate (GCP)
| Service | Cost | Notes |
|---------|------|-------|
| Cloud SQL db-f1-micro | $0 | Free tier |
| Cloud Run | $0 | 2M free invocations/month |
| Cloud Scheduler | $0.1 | Free for first 3 jobs |
| Secret Manager | $0.06 | Free for first 6 secrets |
| Cloud Logging | $0 | Free tier |
| **Total** | **~$0.16** | Effectively free |

### What Costs Money After Free Tier:
- Database storage beyond 10GB
- Egress beyond 1GB/month
- High-volume Cloud Scheduler (> 3 jobs)

## Testing Strategy

### Unit Tests
- **du_api.py**: Mock `requests.Session`, test parsing and validation
- **postgres.py**: Use `testcontainers-postgres` for real DB testing
- **config.py**: Test env var loading and defaults

### Integration Tests
- **Full pipeline**: docker-compose up, verify data in DB

### What's Not Tested (Scope)
- GCP-specific services (Cloud SQL connectivity) — tested in terraform plan
- Cloud Scheduler invocation — tested manually post-deployment
- GitHub Actions workflow — tested on actual push

## Security Considerations

### Implemented
- ✅ Non-root Docker user
- ✅ Secrets in Secret Manager (not env files)
- ✅ VPC-private Cloud SQL connection
- ✅ Service account least-privilege IAM roles
- ✅ HTTPS-only for Cloud Run (automatic)

### Not Implemented (Out of Scope)
- SSL for Cloud SQL (set `require_ssl = true` in terraform/main.tf if needed)
- API authentication (DU API is public)
- Database encryption (Cloud SQL handles at-rest encryption)

## Monitoring & Observability

### Current
- ✅ Structured logging to stdout (picked up by Cloud Logging)
- ✅ Error logging with `exc_info=True` (includes stack trace)
- ✅ Pipeline metrics (rows upserted, total count)

### Recommended Enhancements
- Cloud Monitoring alerts for pipeline failures
- Pub/Sub notifications on completion
- BigQuery export for historical analysis
- Cloud Trace integration for latency tracking
