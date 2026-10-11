#!/usr/bin/env bash
# Step 2: pin every container image to an exact version AND digest, then push to Git.
# A tag (like 6.14.0) can be moved by the publisher; a digest (sha256:...) cannot.
source "$(dirname "$0")/lib.sh"
R="$(dirname "$0")/resolve-digest.sh"

pin() {  # pin <image:tag> <file>
  local image="$1" file="$2" base digest
  base="${image%:*}"
  digest=$("$R" "$image")
  sed -i -E "s|image: ${base}:[^[:space:]]+|image: ${image}@${digest}|" "$file"
  echo "$(now)  ${image}@${digest}  ->  ${file#"$REPO_ROOT"/}" | tee -a "$EVIDENCE_DIR/02-image-pins.log"
}

info "Resolving digests"
pin "ghcr.io/stefanprodan/podinfo:${PODINFO_VERSION}" "$REPO_ROOT/gitops/apps/podinfo/deployment.yaml"
pin "$CURL_IMAGE" "$REPO_ROOT/tests/netpol/clients.yaml"
pin "$K6_IMAGE"   "$REPO_ROOT/tests/load/k6-job.yaml"

info "Changes:"
git -C "$REPO_ROOT" --no-pager diff --stat || true

info "Committing and pushing to GitHub"
push_change "Pin images to version + digest (podinfo ${PODINFO_VERSION})"
ok "Images pinned."
