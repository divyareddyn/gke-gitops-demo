#!/usr/bin/env bash
# Step 0: confirm every tool we need is installed and record versions.
source "$(dirname "$0")/lib.sh"

info "Checking tools"
missing=0
for t in gcloud terraform kubectl helm git jq curl python3 gke-gcloud-auth-plugin; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t found"; else warn "$t is MISSING"; missing=1; fi
done
[[ $missing == 0 ]] || die "Install the missing tools (Terraform: see ~/bin install step) and re-run."

info "Recording versions to evidence/00-tool-versions.log"
: > "$EVIDENCE_DIR/00-tool-versions.log"
evidence 00-tool-versions.log gcloud version
evidence 00-tool-versions.log terraform version
evidence 00-tool-versions.log kubectl version --client
evidence 00-tool-versions.log helm version --short
evidence 00-tool-versions.log git --version

info "Context"
echo "Project:   $PROJECT_ID"
echo "Region:    $REGION / Zone: $ZONE"
echo "Cluster:   $CLUSTER_NAME"
echo "Git repo:  $(git_repo_url)"
ok "Tools ready."

