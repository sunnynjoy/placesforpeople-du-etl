# Places for People: DU University Chapters ETL Pipeline

A production-ready ETL pipeline that ingests Ducks Unlimited university chapter data 
from ArcGIS Feature Server, processes it, and stores it in PostgreSQL on Google Cloud SQL.

## Assessment

- [x] Python ETL pipeline (Ducks Unlimited API → PostgreSQL)
- [x] Idempotent upserts with data validation
- [x] Docker containerization (multi-stage build, AMD64 compatible)
- [x] PostgreSQL schema with indexing
- [x] Cloud SQL integration (GCP)
- [x] Cloud Run Jobs deployment (serverless)
- [x] Secret Manager for credential storage
- [x] Artifact Registry for Docker images
- [x] Infrastructure as Code (Terraform)
- [x] GitHub Actions CI/CD pipeline

## Architecture

```
GitHub Push → GitHub Actions → Build Docker Image (AMD64)
                                      ↓
                          Artifact Registry (Docker repo)
                                      ↓
                          Cloud Run Job (serverless)
                                      ↓
                          Cloud SQL PostgreSQL
```

## Tech Stack

- **Language:** Python 3.11
- **ETL Framework:** Custom (requests, psycopg2)
- **Database:** PostgreSQL 15 (Cloud SQL)
- **Containerization:** Docker (multi-stage)
- **Cloud Platform:** Google Cloud Platform (GCP)
- **Compute:** Cloud Run Jobs (serverless)
- **IaC:** Terraform
- **CI/CD:** GitHub Actions
- **Secret Management:** Secret Manager

## Data Pipeline

**Source:** Ducks Unlimited ArcGIS Feature Server API
**Endpoint:** `https://services2.arcgis.com/5I7u4SJE1vUr79JC/arcgis/rest/services/UniversityChapters_Public/FeatureServer/0/query`

**Processing:**
1. Fetch chapters from DU API
2. Filter by state (configurable, default: CA)
3. Validate data (required fields, coordinates)
4. Upsert into PostgreSQL (idempotent)

**Database Schema:**
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
```

## Execution Methods

### Local Docker Compose
```bash
docker-compose up --build
```

### Cloud Run Job (Manual)
```bash
gcloud run jobs execute placesforpeople-etl \
  --region us-central1 \
  --project placesforpeople-500907
```

### GitHub Actions (Automatic)
Push to `main` branch → GitHub Actions builds, pushes image, deploys to Cloud Run automatically.

## Project Structure

```
placesforpeople-du-etl/
├── src/
│   ├── config.py              # Configuration management
│   ├── etl.py                 # Main orchestration
│   ├── extractors/
│   │   └── du_api.py          # DU API client
│   └── loaders/
│       └── postgres.py        # PostgreSQL loader
├── terraform/
│   ├── main.tf                # Cloud Run Job, Secret Manager, Artifact Registry
│   ├── variables.tf           # Variable definitions
│   ├── outputs.tf             # Terraform outputs
│   └── terraform.tfvars       # Configuration (not committed)
├── .github/workflows/
│   └── deploy.yml             # GitHub Actions CI/CD
├── docker-compose.yml         # Local development
├── Dockerfile                 # Multi-stage production build
├── requirements.txt           # Python dependencies
├── wait-for-db.py             # Database readiness probe
└── README.md                  # This file
```

## Environment Configuration

### Local Development (.env)
```
DB_HOST=localhost
DB_PORT=5432
DB_USER=du_user
DB_PASSWORD=changeme
DB_NAME=du_chapters
DU_API_BASE_URL=https://services2.arcgis.com/5I7u4SJE1vUr79JC/arcgis/rest/services/UniversityChapters_Public/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=json
API_TIMEOUT_SECONDS=30
API_MAX_RETRIES=3
API_RETRY_BACKOFF_SECONDS=2
STATE_FILTER=CA
LOG_LEVEL=INFO
```

### Production (Terraform + Secret Manager)
All credentials stored securely in GCP Secret Manager. No secrets in code.

## Key Features

- **Idempotent Upserts:** Safe to run multiple times without duplicating data
- **Data Validation:** Validates coordinates, required fields, data types
- **Error Handling:** Graceful degradation with proper logging
- **Retry Logic:** 3 retries with exponential backoff on API failures
- **Serverless:** Cloud Run Jobs — pay only for execution time
- **Automatic Deployment:** GitHub Actions triggers on every `git push`
- **Infrastructure as Code:** Entire GCP infrastructure reproducible via Terraform

## Testing

### Manual Test
```bash
# Execute the job and wait for completion
gcloud run jobs execute placesforpeople-etl --region us-central1 --wait

# Check the job status
gcloud run jobs describe placesforpeople-etl --region us-central1
```

### Verify Data
```bash
psql -h <CLOUD_SQL_IP> -U postgres -d du_chapters -c "SELECT COUNT(*), state FROM chapters GROUP BY state;"
```

### Docker Compose Test
```bash
docker-compose up --build
# Expected: ETL pipeline completed, 3 chapters upserted
```

## Deployment

### Prerequisites
- Google Cloud Project (placesforpeople-500907)
- Cloud SQL PostgreSQL instance
- Terraform installed
- gcloud CLI configured

### One-Time Setup
```bash
# Initialize Terraform
cd terraform
terraform init

# Apply infrastructure
terraform apply
```

### Continuous Deployment
1. Push code to `main` branch
2. GitHub Actions automatically:
   - Builds Docker image (AMD64 compatible)
   - Pushes to Artifact Registry
   - Deploys to Cloud Run Job

## Security

- Credentials stored in **Secret Manager** (not in code)
- Service accounts with **least-privilege IAM roles**
- Docker images stored in **private Artifact Registry**
- Cloud Run Job triggered by **GitHub Actions only**
- Database password managed via **Terraform secrets**

## Performance & Cost

- **Execution Time:** ~30-45 seconds per run
- **Cost:** Estimated ~$5-10/month (free tier covers most costs)
- **Scaling:** Cloud Run Jobs can handle 1000+ concurrent executions
- **Database:** db-f1-micro (free tier) sufficient for current load

## API Notes

- DU API returns ~400+ university chapters
- Filtered to California (CA) by default, configurable via `STATE_FILTER`
- Coordinates in WGS84 (EPSG:4326) format
- Data updated periodically; check API for refresh intervals

## Troubleshooting

**Cloud Run Job fails to start:**
- Check logs: `gcloud run jobs describe placesforpeople-etl --region us-central1`
- Verify image exists in Artifact Registry
- Ensure database credentials in Secret Manager are correct

**Database connection fails:**
- Verify Cloud SQL instance is running
- Check IP whitelisting for your machine
- Confirm credentials in `.env` or Terraform

**GitHub Actions workflow fails:**
- Check workflow logs in GitHub Actions tab
- Verify `GCP_SA_KEY` secret is set correctly
- Ensure service account has required IAM roles

## Future Enhancements

- Cloud Scheduler for daily automated execution
- Data quality monitoring & alerting
- Historical data tracking & change detection
- Support for multiple states
- Performance metrics & dashboard

---
