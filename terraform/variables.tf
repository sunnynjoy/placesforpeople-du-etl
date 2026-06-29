variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "db_host" {
  description = "Cloud SQL instance IP address"
  type        = string
}

variable "db_port" {
  description = "Database port"
  type        = string
  default     = "5432"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "postgres"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "du_chapters"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "du_api_base_url" {
  description = "DU API base URL"
  type        = string
  default     = "https://services2.arcgis.com/5I7u4SJE1vUr79JC/arcgis/rest/services/UniversityChapters_Public/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=json"
}

variable "state_filter" {
  description = "State filter for chapters"
  type        = string
  default     = "CA"
}