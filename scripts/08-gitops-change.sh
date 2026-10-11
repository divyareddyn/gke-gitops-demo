#!/usr/bin/env bash
# Step 8: the GitOps proof. Change ONE thing in Git (podinfo 6.14.0 -> 6.14.1 and
# the UI message v1 -> v2), push, and watch Argo CD apply it on its own.
# We do NOT nudge Argo CD here — it finds the change through its normal polling.
source "$(dirname "$0")/lib.sh"
get_credentials
L=08-gitops-change.log
OUT="$EVIDENCE_DIR/08-gitops-change.md"
DEP="$REPO_ROOT/gitops/apps/podinfo/deployment.yaml"
NEXT="ghcr.io/stefanprodan/podinfo:${PODINFO_NEXT_VERSION}"

app_version() {  # asks the running app itself, from the allowed client
  { kubectl -n loadgen exec allowed-client -- curl -s -m 5 http://podinfo.demo.svc.cluster.local/ \
    | jq -r '"version=\(.version) message=\(.message)"'; } 2>/dev/null || echo "unreachable"
}
running_images() {
  kubectl -n demo get pods -l app.kubernetes.io/name=podinfo \
    -o jsonpath='{range .items[*]}{.status.containerStatuses[0].image}{"\n"}{end}' | sort -u | tr '\n' ' '
}

info "BEFORE"
BEFORE_SHA=$(app_field '{.status.sync.revision}')
BEFORE_APP=$(app_version)
BEFORE_IMG=$(running_images)
evidence $L bash -c "echo 'Argo CD revision: $BEFORE_SHA'; echo 'App reports:      $BEFORE_APP'; echo 'Images:           $BEFORE_IMG'"

info "Editing deployment.yaml"
DIGEST=$("$REPO_ROOT/scripts/resolve-digest.sh" "$NEXT")
sed -i -E "s|image: ghcr.io/stefanprodan/podinfo:[^[:space:]]+|image: ${NEXT}@${DIGEST}|" "$DEP"
sed -i -E 's|value: "gitops-demo v1"|value: "gitops-demo v2"|' "$DEP"
evidence $L git -C "$REPO_ROOT" --no-pager diff -- gitops/

PUSH_TIME=$(now); PUSH_EPOCH=$(date +%s)
push_change "GitOps demo: podinfo ${PODINFO_VERSION} -> ${PODINFO_NEXT_VERSION}, message v2"
echo "Pushed $PUSHED_SHA at $PUSH_TIME" | tee -a "$EVIDENCE_DIR/$L"

info "Waiting for Argo CD to notice and apply it by itself (polls every ~60s)"
wait_for_sync "$PUSHED_SHA" > >(tee -a "$EVIDENCE_DIR/$L")
SYNCED_EPOCH=$(date +%s)
evidence $L kubectl -n demo rollout status deploy/podinfo --timeout=300s
ROLLED_EPOCH=$(date +%s)

info "AFTER"
AFTER_APP=$(app_version)
AFTER_IMG=$(running_images)
evidence $L bash -c "echo 'Argo CD revision: $(app_field '{.status.sync.revision}')'; echo 'App reports:      $AFTER_APP'; echo 'Images:           $AFTER_IMG'"
evidence $L bash -c "kubectl -n argocd get application podinfo -o json | jq -r '.status.history[] | \"\(.deployedAt)  \(.revision)\"'"
evidence $L bash -c "kubectl -n argocd get application podinfo -o json | jq '.status.operationState | {phase, startedAt, finishedAt, message, syncResult: .syncResult.revision}'"

cat > "$OUT" <<EOF
# GitOps change evidence

| | Before | After |
|---|---|---|
| Git commit deployed by Argo CD | \`${BEFORE_SHA}\` | \`${PUSHED_SHA}\` |
| App self-report | ${BEFORE_APP} | ${AFTER_APP} |
| Running image(s) | \`${BEFORE_IMG}\` | \`${AFTER_IMG}\` |

- Pushed to GitHub at **${PUSH_TIME}**
- Argo CD Synced + Healthy at the new commit after **$(( SYNCED_EPOCH - PUSH_EPOCH ))s** (no manual sync, no kubectl apply)
- Rolling update finished **$(( ROLLED_EPOCH - PUSH_EPOCH ))s** after the push
EOF
cat "$OUT"
ok "GitOps change proven. Next: ./scripts/09-loadtest.sh"
