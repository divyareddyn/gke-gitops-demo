#!/usr/bin/env bash
# Step 1: enable the Google Cloud APIs we need and create the Terraform state bucket.
source "$(dirname "$0")/lib.sh"

info "Checking billing is enabled on project $PROJECT_ID"
billing=$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled)' 2>/dev/null || echo "unknown")
[[ "$billing" == "True" ]] || die "Billing is not enabled for $PROJECT_ID (got: $billing). Link your Free Trial billing account in the Console."
ok "Billing enabled"

info "Enabling APIs (takes 1-2 minutes the first time)"
evidence 01-project-setup.log gcloud services enable \
  container.googleapis.com compute.googleapis.com iam.googleapis.com \
  cloudresourcemanager.googleapis.com logging.googleapis.com monitoring.googleapis.com \
  serviceusage.googleapis.com --project "$PROJECT_ID"

info "Creating Terraform state bucket gs://$STATE_BUCKET (private, versioned)"
if gcloud storage buckets describe "gs://$STATE_BUCKET" >/dev/null 2>&1; then
  ok "Bucket already exists"
else
  evidence 01-project-setup.log gcloud storage buckets create "gs://$STATE_BUCKET" \
    --project "$PROJECT_ID" --location "$REGION" \
    --uniform-bucket-level-access --public-access-prevention
fi
evidence 01-project-setup.log gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
evidence 01-project-setup.log gcloud storage buckets describe "gs://$STATE_BUCKET" \
  --format='yaml(name,location,versioning_enabled,public_access_prevention,uniform_bucket_level_access)'

ok "Project prepared. Terraform state will live in gs://$STATE_BUCKET (never in Git)."
