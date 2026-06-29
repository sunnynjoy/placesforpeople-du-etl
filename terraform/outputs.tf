output "job_name" {
  value       = google_cloud_run_v2_job.etl.name
  description = "Cloud Run Job name"
}

output "artifact_registry_repo" {
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.etl_repo.name}"
  description = "Artifact Registry repository URL"
}

output "service_account_email" {
  value       = google_service_account.etl_service_account.email
  description = "Service account email for Cloud Run Job"
}