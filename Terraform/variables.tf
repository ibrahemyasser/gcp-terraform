# ==================== VARIABLES ====================

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "gke_cluster_name" {
  description = "GKE Cluster name"
  type        = string
  default     = "private-gke-cluster"
}

variable "app_image" {
  description = "Container image from GAR"
  type        = string
}