terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Service Account for Cloud Run
resource "google_service_account" "etl_service_account" {
  account_id   = "placesforpeople-etl"
  display_name = "Places for People ETL Service Account"
}

# IAM: Allow Cloud Run to access Secret Manager
resource "google_secret_manager_secret_iam_member" "etl_secret_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.etl_service_account.email}"
}

# Secret Manager: Database Password
resource "google_secret_manager_secret" "db_password" {
  secret_id = "du-chapters-db-password"
  
  replication {
    user_managed {
      replicas {
        location = var.gcp_region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

# Artifact Registry: Docker Repository
resource "google_artifact_registry_repository" "etl_repo" {
  location      = var.gcp_region
  repository_id = "placesforpeople-etl"
  description   = "Docker images for Places for People ETL"
  format        = "DOCKER"
}

# Cloud Run Job (not Service - better for batch workloads)
resource "google_cloud_run_v2_job" "etl" {
  name     = "placesforpeople-etl"
  location = var.gcp_region

  template {
    task_count = 1
    template {
      service_account = google_service_account.etl_service_account.email
      
      containers {
        image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.etl_repo.name}/placesforpeople-etl:latest"

        env {
          name  = "DB_HOST"
          value = var.db_host
        }
        env {
          name  = "DB_PORT"
          value = var.db_port
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
          name  = "DB_PASSWORD"
          value = var.db_password
        }
        env {
          name  = "DU_API_BASE_URL"
          value = var.du_api_base_url
        }
        env {
          name  = "STATE_FILTER"
          value = var.state_filter
        }
        env {
          name  = "LOG_LEVEL"
          value = "INFO"
        }
      }
    }
  }
}