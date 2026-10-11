#!/usr/bin/env bash
# Step 4: install Argo CD with Terraform and point it at our GitHub repo.
# From here on, Argo CD deploys the app from Git — we never `kubectl apply` it.
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT/terraform/10-bootstrap"

export TF_VAR_repo_url="$(git_repo_url)"
info "Argo CD will watch: $TF_VAR_repo_url (branch $GIT_BRANCH, folder gitops/apps/podinfo)"

# Make sure GitHub has what we have locally
git -C "$REPO_ROOT" fetch -q origin "$GIT_BRANCH"
[[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$(git -C "$REPO_ROOT" rev-parse "origin/$GIT_BRANCH")" ]] \
  || die "Local commits are not pushed to GitHub yet. Run: git push"

terraform init -input=false -reconfigure -backend-config="bucket=$STATE_BUCKET"
terraform validate
terraform plan -input=false -out=tfplan
terraform show -no-color tfplan > "$EVIDENCE_DIR/04-bootstrap-plan.txt"
confirm "Install Argo CD?" || die "Stopped before apply."
terraform apply -input=false tfplan 2>&1 | tee "$EVIDENCE_DIR/04-bootstrap-apply.log"
rm -f tfplan
terraform output | tee -a "$EVIDENCE_DIR/04-bootstrap-apply.log"

get_credentials
L=04-gitops-sync.log
evidence $L kubectl -n argocd get pods
evidence $L kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
evidence $L kubectl -n argocd get appproject,application

info "Waiting for Argo CD to pull the app from GitHub and report Synced + Healthy"
SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
wait_for_sync "$SHA" refresh > >(tee -a "$EVIDENCE_DIR/$L")

evidence $L bash -c "echo \"Git HEAD on GitHub : $SHA\"; echo \"Argo CD deployed   : \$(kubectl -n argocd get application podinfo -o jsonpath='{.status.sync.revision}')\""
evidence $L kubectl get ns demo --show-labels
evidence $L kubectl -n demo get all

ok "GitOps is live. Next: ./scripts/05-verify-app.sh"
echo "Optional — open the Argo CD UI:"
echo "  password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo "  tunnel:   kubectl -n argocd port-forward svc/argocd-server 8080:80"
echo "  then click Cloud Shell 'Web Preview' -> 'Preview on port 8080' and log in as admin"
