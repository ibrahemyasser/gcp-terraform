# ==================== OUTPUTS ====================



output "gke_cluster_endpoint" {
  description = "GKE Cluster endpoint (private)"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "artifact_registry_url" {
  description = "Artifact Registry Repository URL"
  value       = "us-central1-docker.pkg.dev/${var.project_id}/gcp-docker-repo"
}

output "management_vm_internal_ip" {
  description = "Internal IP of management VM"
  value       = google_compute_instance.management_vm.network_interface[0].network_ip
}

output "gke_node_service_account" {
  description = "Service Account for GKE Nodes"
  value       = google_service_account.gke_node_sa.email
}

