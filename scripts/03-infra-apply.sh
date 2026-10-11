#!/usr/bin/env bash
# Step 3: create the VPC + GKE cluster with Terraform (about 10-15 minutes).
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT/terraform/00-infra"

export TF_VAR_admin_cidr="$(my_public_ip)/32"
info "Kubernetes API will only accept connections from: $TF_VAR_admin_cidr (this Cloud Shell)"

info "terraform init (state -> gs://$STATE_BUCKET/gke-demo/infra)"
terraform init -input=false -reconfigure -backend-config="bucket=$STATE_BUCKET"

info "terraform fmt / validate"
terraform fmt -check -recursive || warn "Formatting differences (cosmetic only)."
terraform validate

info "terraform plan"
terraform plan -input=false -out=tfplan
terraform show -no-color tfplan > "$EVIDENCE_DIR/03-infra-plan.txt"
terraform show -json tfplan | jq -r '.resource_changes[] | select(.change.actions != ["no-op"]) | "\(.change.actions | join(","))\t\(.address)"' \
  | tee "$EVIDENCE_DIR/03-infra-plan-summary.txt"
echo "Resources to change: $(wc -l < "$EVIDENCE_DIR/03-infra-plan-summary.txt")"

confirm "Apply this plan? It creates billable resources." || die "Stopped before apply."

info "terraform apply (go get a coffee: ~10-15 min)"
start=$(date +%s)
terraform apply -input=false tfplan 2>&1 | tee "$EVIDENCE_DIR/03-infra-apply.log"
echo "Apply took $(( $(date +%s) - start ))s" | tee -a "$EVIDENCE_DIR/03-infra-apply.log"
rm -f tfplan

info "Recording versions"
{
  echo "# Recorded $(now)"
  terraform version
  echo; echo "## Provider versions locked in .terraform.lock.hcl"
  grep -E '^provider|^  version' .terraform.lock.hcl
  echo; echo "## Module"
  grep -E '^\s+(source|version)\s+=' gke.tf | head -2
} > "$EVIDENCE_DIR/03-versions.txt"
terraform output | tee -a "$EVIDENCE_DIR/03-versions.txt"

info "Connecting kubectl to the cluster"
get_credentials

L=03-cluster-verify.log
evidence $L kubectl get nodes -o wide
evidence $L gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" \
  --format='yaml(name,currentMasterVersion,status,networkConfig.datapathProvider,privateClusterConfig.enablePrivateNodes,masterAuthorizedNetworksConfig)'
evidence $L kubectl -n kube-system get daemonset anetd
evidence $L kubectl get apiservice v1beta1.metrics.k8s.io
evidence $L kubectl top nodes

ok "Cluster ready. Next: ./scripts/04-bootstrap-argocd.sh"
