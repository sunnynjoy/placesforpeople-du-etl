terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Generate random suffix for unique resource names
resource "random_id" "db_suffix" {
  byte_length = 4
}

# ============================================
# CLOUD SQL - PostgreSQL Database
# ============================================
resource "google_sql_database_instance" "postgres" {
  name             = "${var.db_instance_name}-${random_id.db_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.gcp_region

  settings {
    tier = "db-f1-micro"  # Free tier eligible

    # Backup settings
    backup_configuration {
      enabled            = true
      start_time         = "03:00"  # Start backup at 3 AM UTC
      transaction_log_retention_days = 7
    }

    # IP settings - allow all (adjust for production)
    ip_configuration {
      require_ssl = false  # For simplicity; use SSL in production
    }

    # Maintenance window
    maintenance_window {
      day          = 7    # Sunday
      hour         = 3    # 3 AM
      update_track = "stable"
    }
  }

  deletion_protection = false  # Allow deletion for testing

  depends_on = [google_project_service.sqladmin]
}

resource "google_sql_database" "chapters" {
  name     = var.db_name
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "db_user" {
  name     = var.db_user
  instance = google_sql_database_instance.postgres.name
  password = var.db_password
}

# ============================================
# ARTIFACT REGISTRY - Container Registry
# ============================================
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.gcp_region
  repository_id = "du-etl-repo"
  description   = "Docker container registry for DU ETL pipeline"
  format        = "DOCKER"

  depends_on = [google_project_service.artifactregistry]
}

# ============================================
# CLOUD RUN - Serverless Execution
# ============================================
resource "google_cloud_run_service" "etl" {
  name     = var.service_name
  location = var.gcp_region

  template {
    spec {
      service_account_name = google_service_account.etl_sa.email

      containers {
        # Use GCR image format: REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY/IMAGE:TAG
        image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.docker_repo.repository_id}/${var.image_name}:${var.image_tag}"

        env {
          name  = "DB_HOST"
          value = google_sql_database_instance.postgres.private_ip_address
        }

        env {
          name  = "DB_PORT"
          value = "5432"
        }

        env {
          name  = "DB_USER"
          value = var.db_user
        }

        env {
          name  = "DB_NAME"
          value = var.db_name
        }

        env {
          name  = "STATE_FILTER"
          value = var.state_filter
        }

        env {
          name  = "LOG_LEVEL"
          value = var.log_level
        }

        # DB_PASSWORD from Secret Manager
        env {
          name = "DB_PASSWORD"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_password.id
              key  = "latest"
            }
          }
        }

        # Set timeout and memory
        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }

      # Enable VPC connection to Cloud SQL
      vpc_access_connector {
        name = google_vpc_access_connector.etl_connector.id
      }

      timeout_seconds = 300
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "10"
        "autoscaling.knative.dev/minScale" = "0"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.run,
    google_secret_manager_secret_iam_member.etl_can_access_secret
  ]
}

# ============================================
# VPC ACCESS CONNECTOR - For Cloud SQL Connection
# ============================================
resource "google_vpc_access_connector" "etl_connector" {
  name          = "du-etl-connector"
  region        = var.gcp_region
  ip_cidr_range = "10.8.0.0/28"

  depends_on = [google_project_service.vpcaccess]
}

# ============================================
# SECRET MANAGER - Store Database Password
# ============================================
resource "google_secret_manager_secret" "db_password" {
  secret_id = "du-db-password"

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

# ============================================
# SERVICE ACCOUNT - Cloud Run Execution
# ============================================
resource "google_service_account" "etl_sa" {
  account_id   = "du-etl-sa"
  display_name = "DU ETL Service Account"
}

# Allow service account to access Secret Manager
resource "google_secret_manager_secret_iam_member" "etl_can_access_secret" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.etl_sa.email}"
}

# Allow service account to connect to Cloud SQL
resource "google_project_iam_member" "cloudsql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.etl_sa.email}"
}

# ============================================
# CLOUD SCHEDULER - Daily Trigger
# ============================================
resource "google_cloud_scheduler_job" "etl_trigger" {
  name             = "du-etl-daily"
  description      = "Trigger DU ETL pipeline daily"
  schedule         = var.schedule_expression
  time_zone        = "UTC"
  region           = var.gcp_region
  attempt_deadline = "320s"

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_service.etl.status[0].url}/"
    oidc_token_header {
      service_account_email = google_service_account.scheduler_sa.email
      audience              = google_cloud_run_service.etl.status[0].url
    }
  }

  depends_on = [google_project_service.cloudscheduler]
}

# Service account for Cloud Scheduler
resource "google_service_account" "scheduler_sa" {
  account_id   = "du-scheduler-sa"
  display_name = "DU Scheduler Service Account"
}

# Allow scheduler to invoke Cloud Run
resource "google_cloud_run_service_iam_member" "scheduler_invoker" {
  service  = google_cloud_run_service.etl.name
  location = google_cloud_run_service.etl.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# ============================================
# ENABLE REQUIRED APIS
# ============================================
resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sqladmin" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "vpcaccess" {
  service            = "vpcaccess.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudscheduler" {
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}
