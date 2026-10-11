variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the VPC subnet and Cloud NAT"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone for the (zonal) GKE cluster"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "GKE cluster name (also used as a prefix for network resources)"
  type        = string
  default     = "gitops-demo"
}

variable "machine_type" {
  description = "Node machine type"
  type        = string
  default     = "e2-standard-2"
}

variable "node_min" {
  description = "Minimum nodes in the node pool (cluster autoscaler)"
  type        = number
  default     = 2
}

variable "node_max" {
  description = "Maximum nodes in the node pool (cluster autoscaler)"
  type        = number
  default     = 3
}

variable "disk_size_gb" {
  description = "Boot disk size per node"
  type        = number
  default     = 50
}

variable "use_spot" {
  description = "Use Spot VMs (cheaper, but nodes can be reclaimed mid-demo)"
  type        = bool
  default     = false
}

variable "admin_cidr" {
  description = "CIDR allowed to reach the Kubernetes API (your Cloud Shell IP /32)"
  type        = string
}

variable "subnet_cidr" {
  description = "Primary range for nodes"
  type        = string
  default     = "10.10.0.0/24"
}

variable "pods_cidr" {
  description = "Secondary range for pods"
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for Services"
  type        = string
  default     = "10.30.0.0/20"
}

variable "master_cidr" {
  description = "/28 range for the GKE control plane private endpoint"
  type        = string
  default     = "172.16.0.0/28"
}
