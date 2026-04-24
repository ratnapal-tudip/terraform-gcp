###############################################################
# ROOT VARIABLES
###############################################################

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "ratnapal-project"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "db_password" {
  description = "MySQL root password for Cloud SQL"
  type        = string
  sensitive   = true
  default     = "Admin@123"
}
