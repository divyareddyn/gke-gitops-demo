# GKE cluster via the community module terraform-google-modules/kubernetes-engine
# (private-cluster submodule). See README "Terraform" for what it creates and
# which defaults were changed.

module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "45.0.0"

  project_id = var.project_id
  name       = var.cluster_name
  regional   = false # zonal: cheaper, and the free tier covers one zonal cluster's fee
  region     = var.region
  zones      = [var.zone]

  network           = google_compute_network.vpc.name
  subnetwork        = google_compute_subnetwork.nodes.name
  ip_range_pods     = "pods"
  ip_range_services = "services"

  release_channel = "REGULAR"

  # Dataplane V2 (Cilium/eBPF) enforces Kubernetes NetworkPolicy natively.
  # The legacy Calico add-on must stay off when Dataplane V2 is used.
  datapath_provider = "ADVANCED_DATAPATH"
  network_policy    = false

  # Nodes get only private IPs; the control plane keeps a public endpoint that
  # only the admin CIDR (your Cloud Shell IP) can reach.
  enable_private_nodes    = true
  enable_private_endpoint = false
  master_ipv4_cidr_block  = var.master_cidr
  master_authorized_networks = [
    { cidr_block = var.admin_cidr, display_name = "admin" }
  ]

  horizontal_pod_autoscaling = true # HPA controller (default, stated explicitly)
  create_service_account     = true # dedicated node SA with minimal roles
  remove_default_node_pool   = true
  deletion_protection        = false # sandbox: allow `terraform destroy`

  node_pools = [
    {
      name         = "pool-1"
      machine_type = var.machine_type
      min_count    = var.node_min
      max_count    = var.node_max
      disk_size_gb = var.disk_size_gb
      disk_type    = "pd-balanced"
      image_type   = "COS_CONTAINERD"
      spot         = var.use_spot
      auto_repair  = true
      auto_upgrade = true
    }
  ]
}
