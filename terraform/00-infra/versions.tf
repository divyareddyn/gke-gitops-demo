terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.39.0, < 8.0.0" # GKE module v45 requires >= 7.39
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10, < 4.0.0" # required by the GKE module (unused features only)
    }
  }

  # Remote state in a private, versioned GCS bucket. The bucket name is passed
  # at `terraform init -backend-config=bucket=...` so nothing project-specific
  # is hard-coded here and no state ever lands in Git.
  backend "gcs" {
    prefix = "gke-demo/infra"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Short-lived OAuth token from your own gcloud login — no keys on disk.
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}
