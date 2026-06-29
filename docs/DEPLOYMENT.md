# Setup Instructions

## Prerequisites

### Local Development
- Docker & Docker Compose
- Python 3.11+
- Git

### GCP Deployment
- GCP Project with billing enabled
- `gcloud` CLI
- Terraform
- GitHub account (for Actions)

---

## Part 1: Local Development Setup

### 1.1 Clone Repository

```bash
git clone <your-repo-url>
cd pfp-du-etl
```

### 1.2 Create Environment File

```bash
cp .env.example .env
# Edit .env if needed (defaults work for docker-compose)
```

### 1.3 Start Local Services

```bash
docker-compose up --build
```

First run will:
1. Build the Docker image
2. Start PostgreSQL container
3. Wait for DB to be ready (health check)
4. Run the ETL pipeline

Expected output:
```
du_etl | ✓ ETL pipeline completed successfully
du_etl |   - Chapters upserted: 42
du_etl |   - Total chapters in DB: 42
```

### 1.4 Verify Data

```bash
# Connect to local database
docker-compose exec postgres psql -U du_user -d du_chapters

# Inside psql:
SELECT COUNT(*) FROM chapters;
SELECT * FROM chapters LIMIT 5;
\q
```

### 1.5 Clean Up

```bash
# Stop services
docker-compose down

# Remove volumes (to reset database)
docker-compose down -v
```

---

## Part 2: Local Development (Python Venv)

If you prefer running Python directly without Docker:

### 2.1 Create Virtual Environment

```bash
python3 -m venv venv
source venv/bin/activate  # Linux/Mac
# or
venv\Scripts\activate  # Windows
```

### 2.2 Install Dependencies

```bash
pip install -r requirements.txt
```

### 2.3 Start PostgreSQL

```bash
# Option 1: Use docker-compose for just DB
docker-compose up postgres -d

# Option 2: Install PostgreSQL locally and create user
createuser du_user
createdb -O du_user du_chapters
```

### 2.4 Set Environment Variables

```bash
# Linux/Mac
export DB_HOST=localhost
export DB_USER=du_user
export DB_PASSWORD=changeme
export LOG_LEVEL=DEBUG

# Windows (PowerShell)
$env:DB_HOST="localhost"
$env:DB_USER="du_user"
$env:DB_PASSWORD="changeme"
$env:LOG_LEVEL="DEBUG"
```

### 2.5 Run Pipeline

```bash
python -m src.etl
```

### 2.6 Run Tests

```bash
pytest tests/ -v --cov=src
```

---

## Part 3: GCP Deployment

### 3.1 Set Up GCP Project

```bash
# Set your project ID
export GCP_PROJECT_ID="your-gcp-project-id"

# Authenticate with gcloud
gcloud auth login
gcloud config set project $GCP_PROJECT_ID
```

### 3.2 Enable Required APIs

```bash
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  vpcaccess.googleapis.com \
  cloudscheduler.googleapis.com \
  artifactregistry.googleapis.com
```

### 3.3 Build and Push Docker Image

```bash
# Set variables
export REGION=us-central1
export IMAGE_NAME=du-etl

# Configure Docker auth
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Build image
docker build -t ${REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/du-etl-repo/${IMAGE_NAME}:latest .

# Push image
docker push ${REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/du-etl-repo/${IMAGE_NAME}:latest
```

### 3.4 Deploy Infrastructure with Terraform

#### 3.4.1 Initialize Terraform

```bash
cd terraform
terraform init
```

#### 3.4.2 Create terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Example `terraform.tfvars`:
```hcl
gcp_project_id = "my-gcp-project"
gcp_region     = "us-central1"
db_password    = "MyStrong!Password123"  # Use a strong password!
image_tag      = "latest"
```

#### 3.4.3 Plan and Apply

```bash
# Review what will be created
terraform plan

# Deploy infrastructure
terraform apply
```

Expected resources created:
- Cloud SQL PostgreSQL instance
- Artifact Registry repository
- Cloud Run service
- VPC access connector
- Cloud Scheduler job
- Secret Manager secret
- Service accounts with IAM roles

#### 3.4.4 Save Outputs

```bash
terraform output
# Note: cloud_run_url, cloud_sql_instance_name, etc.
```

### 3.5 Configure GitHub Actions (Optional)

To enable automated deployments on push:

#### 3.5.1 Set Up Workload Identity

```bash
# Create service account for GitHub Actions
gcloud iam service-accounts create github-actions \
  --display-name="GitHub Actions SA"

# Grant necessary roles
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/run.developer"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:github-actions@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Create workload identity federation
gcloud iam workload-identity-pools create github \
  --project=$GCP_PROJECT_ID \
  --location=global \
  --display-name=GitHub

# Get workload identity provider resource name
gcloud iam workload-identity-pools describe github \
  --project=$GCP_PROJECT_ID \
  --location=global \
  --format='value(name)'
```

#### 3.5.2 Add GitHub Secrets

In your GitHub repo settings, add:

```
GCP_PROJECT_ID: your-gcp-project-id
WORKLOAD_IDENTITY_PROVIDER: projects/123456789/locations/global/workloadIdentityPools/github/providers/github
SERVICE_ACCOUNT: github-actions@your-gcp-project-id.iam.gserviceaccount.com
```

#### 3.5.3 Push to Trigger Deploy

```bash
git add .
git commit -m "Initial deployment setup"
git push origin main
```

GitHub Actions will:
1. Run tests
2. Build Docker image
3. Push to Artifact Registry
4. Update Cloud Run service

---

## Part 4: Verification & Troubleshooting

### 4.1 Verify Local Pipeline

```bash
# Check database has data
docker-compose exec postgres psql -U du_user -d du_chapters -c "SELECT COUNT(*) FROM chapters;"

# Check logs
docker-compose logs etl | tail -20
```

### 4.2 Verify Cloud Run Deployment

```bash
# Describe service
gcloud run services describe du-etl --region=us-central1

# Check recent executions
gcloud run services logs du-etl --region=us-central1 --limit=50

# Manually trigger (test)
gcloud run services call du-etl \
  --region=us-central1 \
  --request-timeout=300
```

### 4.3 Verify Cloud SQL Database

```bash
# Connect to Cloud SQL from local machine
gcloud sql connect $(terraform output -raw cloud_sql_instance_name) \
  --user=du_user

# Query tables
SELECT COUNT(*) FROM chapters;
SELECT * FROM chapters WHERE state = 'CA' LIMIT 5;
```

### 4.4 Verify Cloud Scheduler

```bash
# Check job
gcloud scheduler jobs describe du-etl-daily --location=us-central1

# Manually trigger job
gcloud scheduler jobs run du-etl-daily --location=us-central1

# Check execution history
gcloud logging read "resource.type=cloud_scheduler_job AND resource.labels.job_id=du-etl-daily" \
  --limit=10 \
  --format=json
```

---

## Troubleshooting

### Docker Compose Issues

**Problem**: "postgres service unhealthy"
```bash
# Solution: Check DB initialization
docker-compose logs postgres
docker-compose down -v  # Reset
docker-compose up --build
```

**Problem**: ETL exits immediately
```bash
docker-compose logs etl
# Check: DB_HOST is "postgres" (not localhost) in docker-compose.yml
```

### GCP Deployment Issues

**Problem**: "Cloud SQL connection refused"
```bash
# Check VPC connector
gcloud compute networks vpc-access connectors list --region=us-central1

# Verify Cloud Run service account has cloudsql.client role
gcloud projects get-iam-policy $GCP_PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:du-etl-sa@*"
```

**Problem**: "Artifact Registry authentication failed"
```bash
# Re-authenticate
gcloud auth configure-docker us-central1-docker.pkg.dev
docker push ...
```

**Problem**: Terraform apply fails
```bash
# Check APIs are enabled
gcloud services list --enabled | grep -E "run|sqladmin|scheduler"

# Get detailed error
terraform apply -auto-approve -lock=false
```

### Python Test Issues

**Problem**: psycopg2 build fails on M1 Mac
```bash
# Use binary version
pip install psycopg2-binary
```

**Problem**: Tests fail on local PostgreSQL
```bash
# Ensure PostgreSQL is running
pg_isready -h localhost

# Check credentials match .env.example
```

---

## Next Steps

1. ✅ Verify local pipeline works
2. ✅ Deploy to GCP
3. ✅ Monitor Cloud Scheduler executions
4. ✅ Add GitHub Actions (optional)
5. ✅ Document any customizations

See [ARCHITECTURE.md](CTURE.md) for design rationale.
