variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string
  default     = "du-etl"
}

variable "image_name" {
  description = "Container image name (without tag)"
  type        = string
  default     = "du-etl"
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "db_instance_name" {
  description = "Cloud SQL instance name"
  type        = string
  default     = "du-chapters-db"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "du_chapters"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "du_user"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
  # This should be provided via terraform.tfvars or via -var flag
  default     = ""
}

variable "schedule_expression" {
  description = "Cloud Scheduler cron expression (daily at 2 AM UTC)"
  type        = string
  default     = "0 2 * * *"
}

variable "state_filter" {
  description = "State to filter chapters (e.g., CA)"
  type        = string
  default     = "CA"
}

variable "log_level" {
  description = "Logging level (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
}
