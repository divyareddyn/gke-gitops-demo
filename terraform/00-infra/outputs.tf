output "cluster_name" {
  value = module.gke.name
}

output "location" {
  value = module.gke.location
}

output "node_service_account" {
  description = "Dedicated, minimal-permission service account used by the nodes"
  value       = module.gke.service_account
}

output "network" {
  value = google_compute_network.vpc.name
}

output "get_credentials" {
  value = "gcloud container clusters get-credentials ${module.gke.name} --zone ${var.zone} --project ${var.project_id}"
}
