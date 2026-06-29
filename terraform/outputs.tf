output "cloud_run_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_service.etl.status[0].url
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance connection name"
  value       = google_sql_database_instance.postgres.connection_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL instance private IP (for VPC connection)"
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "cloud_sql_public_ip" {
  description = "Cloud SQL instance public IP"
  value       = google_sql_database_instance.postgres.public_ip_address
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository path"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.docker_repo.repository_id}"
}

output "cloud_scheduler_job_name" {
  description = "Cloud Scheduler job name"
  value       = google_cloud_scheduler_job.etl_trigger.name
}

output "database_name" {
  description = "Cloud SQL database name"
  value       = google_sql_database.chapters.name
}

output "etl_service_account" {
  description = "Service account for Cloud Run execution"
  value       = google_service_account.etl_sa.email
}

output "scheduler_service_account" {
  description = "Service account for Cloud Scheduler"
  value       = google_service_account.scheduler_sa.email
}
