#!/usr/bin/env bash
# Usage: resolve-digest.sh <registry/repo:tag>
# Prints the sha256 digest of the image (multi-arch index digest when available),
# using the registry's anonymous pull API. Supports ghcr.io and docker.io.
set -euo pipefail
image="$1"
registry="${image%%/*}"
rest="${image#*/}"
repo="${rest%:*}"
tag="${rest##*:}"

case "$registry" in
  ghcr.io)
    token=$(curl -fsS "https://ghcr.io/token?scope=repository:${repo}:pull" | jq -r .token)
    api="https://ghcr.io" ;;
  docker.io)
    token=$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" | jq -r .token)
    api="https://registry-1.docker.io" ;;
  *) echo "unsupported registry: $registry" >&2; exit 1 ;;
esac

accept="application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json"
digest=$(curl -fsSI -H "Authorization: Bearer $token" -H "Accept: $accept" \
  "$api/v2/$repo/manifests/$tag" | awk 'tolower($1)=="docker-content-digest:" {print $2}' | tr -d '\r')
[[ "$digest" == sha256:* ]] || { echo "could not resolve digest for $image" >&2; exit 1; }
echo "$digest"
