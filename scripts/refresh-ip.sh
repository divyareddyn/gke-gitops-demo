#!/usr/bin/env bash
# Cloud Shell gets a new public IP when it restarts. If kubectl starts timing out,
# run this: it updates the cluster's authorized network to your current IP.
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT/terraform/00-infra"
export TF_VAR_admin_cidr="$(my_public_ip)/32"
info "Allowing Kubernetes API access from $TF_VAR_admin_cidr"
terraform init -input=false -reconfigure -backend-config="bucket=$STATE_BUCKET" >/dev/null
terraform apply -input=false -auto-approve -target=module.gke.google_container_cluster.primary
get_credentials
kubectl get nodes && ok "Access restored."
