#!/usr/bin/env bash
# Step 12: delete EVERYTHING this project created, then prove it is gone.
source "$(dirname "$0")/lib.sh"
L=99-cleanup.log

echo "This deletes the cluster, network, NAT and Terraform state bucket in project $PROJECT_ID."
read -r -p "Type the project ID to confirm: " typed
[[ "$typed" == "$PROJECT_ID" ]] || die "Project ID did not match. Nothing deleted."
export AUTO_APPROVE=1
export TF_VAR_admin_cidr="$(my_public_ip)/32"
export TF_VAR_repo_url="$(git_repo_url)"

info "1/4 Argo CD (Terraform bootstrap stack)"
if get_credentials 2>/dev/null; then
  kubectl delete ns loadgen untrusted --ignore-not-found --wait=false || true
fi
( cd "$REPO_ROOT/terraform/10-bootstrap" \
  && terraform init -input=false -reconfigure -backend-config="bucket=$STATE_BUCKET" >/dev/null \
  && terraform destroy -input=false -auto-approve ) 2>&1 | tee "$EVIDENCE_DIR/99-destroy-bootstrap.log" \
  || warn "Bootstrap destroy failed (e.g. Cloud Shell IP changed). Safe to continue: deleting the cluster removes Argo CD too."

info "2/4 Cluster + network (Terraform infra stack, ~5-10 min)"
( cd "$REPO_ROOT/terraform/00-infra" \
  && terraform init -input=false -reconfigure -backend-config="bucket=$STATE_BUCKET" >/dev/null \
  && terraform destroy -input=false -auto-approve ) 2>&1 | tee "$EVIDENCE_DIR/99-destroy-infra.log"

info "3/4 Proving nothing is left (empty lists = clean)"
: > "$EVIDENCE_DIR/$L"
evidence $L gcloud container clusters list --project "$PROJECT_ID"
evidence $L gcloud compute instances list --project "$PROJECT_ID"
evidence $L gcloud compute disks list --project "$PROJECT_ID"
evidence $L gcloud compute networks list --project "$PROJECT_ID" --filter="name~^${CLUSTER_NAME}"
evidence $L gcloud compute routers list --project "$PROJECT_ID"
evidence $L gcloud compute forwarding-rules list --project "$PROJECT_ID"
evidence $L gcloud compute addresses list --project "$PROJECT_ID"
evidence $L gcloud compute firewall-rules list --project "$PROJECT_ID" --filter="network~${CLUSTER_NAME}"
evidence $L gcloud iam service-accounts list --project "$PROJECT_ID" --filter="email~^tf-gke"

info "4/4 Deleting the Terraform state bucket"
evidence $L gcloud storage rm -r "gs://$STATE_BUCKET"
evidence $L bash -c "gcloud storage buckets list --project '$PROJECT_ID' --format='value(name)' | grep -c tfstate || echo 'state bucket gone'"

ok "Cleanup complete. Commit evidence/99-* to GitHub (README shows how)."
echo "Strongest proof (optional): delete the whole project — gcloud projects delete $PROJECT_ID"
