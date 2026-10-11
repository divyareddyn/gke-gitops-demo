variable "project_id" {
  type = string
}

variable "zone" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "repo_url" {
  description = "Public HTTPS URL of the GitHub repo Argo CD reconciles from"
  type        = string
}

variable "target_revision" {
  description = "Git branch Argo CD follows"
  type        = string
  default     = "main"
}

variable "app_path" {
  description = "Folder in the repo that holds the app manifests"
  type        = string
  default     = "gitops/apps/podinfo"
}

variable "argocd_chart_version" {
  description = "Exact argo-cd Helm chart version"
  type        = string
  default     = "10.3.2"
}
