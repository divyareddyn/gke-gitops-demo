#!/usr/bin/env bash
# Shared helpers for all scripts. Source it; don't run it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$REPO_ROOT/config.env"

EVIDENCE_DIR="$REPO_ROOT/evidence"
mkdir -p "$EVIDENCE_DIR"

# ---------- pretty output ----------
now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

# Prefix every line from stdin with a UTC timestamp.
ts() { while IFS= read -r line; do printf '[%s] %s\n' "$(now)" "$line"; done; }

# evidence <file> <command...>
# Runs a command, shows it on screen, and appends the timestamped command +
# output + exit code to evidence/<file>. Never aborts the script.
evidence() {
  local file="$1"; shift
  {
    echo "### $(now)  \$ $*"
    ( set +e; "$@" 2>&1; echo "(exit code: $?)" ) | ts
    echo
  } | tee -a "$EVIDENCE_DIR/$file"
}

confirm() {
  local prompt="$1"
  if [[ "${AUTO_APPROVE:-0}" == "1" ]]; then return 0; fi
  read -r -p "$prompt [yes/no] " ans
  [[ "$ans" == "yes" ]]
}

# ---------- environment detection ----------
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$PROJECT_ID" ]] || die "No GCP project set. Run: gcloud config set project <YOUR_PROJECT_ID>"
STATE_BUCKET="${PROJECT_ID}-tfstate"

git_repo_url() {
  # https URL of the GitHub repo, with any embedded credentials stripped.
  local url
  url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  [[ -n "$url" ]] || die "This folder has no 'origin' git remote. Clone it from GitHub first (see README)."
  url="$(echo "$url" | sed -E 's#^git@github.com:#https://github.com/#; s#https://[^@/]+@#https://#')"
  echo "$url"
}

my_public_ip() {
  curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null \
    || curl -4 -fsS --max-time 10 https://api.ipify.org
}

# Terraform variables (shared by both stacks)
export TF_IN_AUTOMATION=1
export TF_VAR_project_id="$PROJECT_ID"
export TF_VAR_region="$REGION"
export TF_VAR_zone="$ZONE"
export TF_VAR_cluster_name="$CLUSTER_NAME"
export TF_VAR_machine_type="$MACHINE_TYPE"
export TF_VAR_node_min="$NODE_MIN"
export TF_VAR_node_max="$NODE_MAX"
export TF_VAR_disk_size_gb="$DISK_SIZE_GB"
export TF_VAR_use_spot="$USE_SPOT"
export TF_VAR_argocd_chart_version="$ARGOCD_CHART_VERSION"
export TF_VAR_target_revision="$GIT_BRANCH"

get_credentials() {
  gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null
}

# ---------- Argo CD helpers ----------
app_field() {  # app_field <jsonpath>
  kubectl -n argocd get application podinfo -o jsonpath="$1" 2>/dev/null || true
}

app_status_line() {
  echo "sync=$(app_field '{.status.sync.status}') health=$(app_field '{.status.health.status}') revision=$(app_field '{.status.sync.revision}')"
}

# wait_for_sync <git-sha> [refresh]
# Waits until Argo CD reports Synced + Healthy at the given commit.
# If "refresh" is passed, asks Argo CD to re-poll Git now instead of waiting
# for its normal 60s polling interval (it still pulls the change from Git).
wait_for_sync() {
  local sha="$1" refresh="${2:-}" start elapsed rev sync health
  start=$(date +%s)
  while true; do
    if [[ "$refresh" == "refresh" ]]; then
      kubectl -n argocd annotate application podinfo argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
    fi
    rev=$(app_field '{.status.sync.revision}')
    sync=$(app_field '{.status.sync.status}')
    health=$(app_field '{.status.health.status}')
    elapsed=$(( $(date +%s) - start ))
    printf '[%s] t+%3ss  sync=%-10s health=%-12s revision=%s\n' "$(now)" "$elapsed" "$sync" "$health" "${rev:0:12}"
    if [[ "$rev" == "$sha" && "$sync" == "Synced" && "$health" == "Healthy" ]]; then
      SYNC_SECONDS=$elapsed
      return 0
    fi
    (( elapsed > 600 )) && { warn "Timed out after 10 minutes waiting for Argo CD."; return 1; }
    sleep 5
  done
}

push_change() {  # push_change "<commit message>"  -> sets PUSHED_SHA
  git -C "$REPO_ROOT" add -A gitops tests
  if git -C "$REPO_ROOT" diff --cached --quiet; then
    warn "Nothing to commit."
  else
    git -C "$REPO_ROOT" commit -q -m "$1"
  fi
  git -C "$REPO_ROOT" push -q origin "HEAD:$GIT_BRANCH"
  PUSHED_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  ok "Pushed commit $PUSHED_SHA"
}

