#!/usr/bin/env bash
# Step 6: prove the NetworkPolicy works.
#   1. Start 3 test clients (1 should be allowed, 2 should be denied).
#   2. BEFORE any policy: all 3 can reach podinfo (Kubernetes default = allow all).
#   3. Move the policies into the GitOps folder, push, let Argo CD apply them.
#   4. AFTER: only the allowed client gets through.
source "$(dirname "$0")/lib.sh"
get_credentials
URL="http://podinfo.demo.svc.cluster.local/"
RESULTS="$EVIDENCE_DIR/06-netpol-results.md"
APP_DIR="$REPO_ROOT/gitops/apps/podinfo"
STAGED="$REPO_ROOT/gitops/staged-policies"

run_matrix() {  # run_matrix <phase>
  local phase="$1"
  {
    echo; echo "### Phase: $phase  ($(now))"; echo
    echo "| Time (UTC) | Client pod | Namespace | Has loadgen label | Expected | HTTP code | curl exit | Result |"
    echo "|---|---|---|---|---|---|---|---|"
  } | tee -a "$RESULTS"
  while read -r ns pod label expect; do
    set +e
    code=$(kubectl -n "$ns" exec "$pod" -- curl -sS -m 5 -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null)
    rc=$?
    set -e
    if [[ "$phase" == "before-policy" ]]; then expect="allow"; fi
    if [[ "$expect" == "allow" && "$code" == "200" ]] || [[ "$expect" == "deny" && "$code" != "200" ]]; then
      result="PASS"; else result="FAIL"; fi
    echo "| $(now) | $pod | $ns | $label | $expect | ${code:-none} | $rc | $result |" | tee -a "$RESULTS"
  done <<'EOF'
loadgen allowed-client yes allow
loadgen unlabeled-client no deny
untrusted outsider yes deny
EOF
}

info "Starting test clients"
kubectl apply -f "$REPO_ROOT/tests/netpol/clients.yaml"
kubectl -n loadgen wait --for=condition=Ready pod/allowed-client pod/unlabeled-client --timeout=120s
kubectl -n untrusted wait --for=condition=Ready pod/outsider --timeout=120s

echo "# NetworkPolicy test results" > "$RESULTS"
echo "Target: \`$URL\` (Service podinfo in namespace demo). curl exit 28 = timed out (packet dropped)." >> "$RESULTS"

if ls "$STAGED"/netpol-*.yaml >/dev/null 2>&1; then
  info "BEFORE: no NetworkPolicy yet — expect all three to reach the app"
  evidence 06-netpol.log kubectl -n demo get networkpolicy
  run_matrix "before-policy"

  info "Moving policies into the GitOps folder and pushing to GitHub"
  git -C "$REPO_ROOT" mv "$STAGED"/netpol-*.yaml "$APP_DIR/"
  push_change "Add NetworkPolicies: default-deny ingress, allow loadgen only, DNS-only egress"
  wait_for_sync "$PUSHED_SHA" refresh > >(tee -a "$EVIDENCE_DIR/06-netpol.log")
  sleep 10   # give the dataplane a moment to program the new rules
else
  info "Policies are already in Git (this is a re-run)"
fi

evidence 06-netpol.log kubectl -n demo get networkpolicy
evidence 06-netpol.log kubectl -n demo describe networkpolicy
evidence 06-netpol.log kubectl -n demo get pods -o wide
evidence 06-netpol.log kubectl get pods -A -l app.kubernetes.io/name=loadgen --show-labels

info "AFTER: expect allowed-client=200, the other two to time out"
run_matrix "after-policy"

info "Egress check: podinfo itself should NOT reach the internet (DNS-only egress)"
evidence 06-netpol.log bash -c "kubectl -n demo exec deploy/podinfo -- curl -sS -m 5 -o /dev/null -w '%{http_code}\n' https://www.google.com || echo 'BLOCKED (expected)'"

info "Pods still healthy after the policy?"
evidence 06-netpol.log kubectl -n demo get pods

echo
cat "$RESULTS"
grep -q '| FAIL |' <(sed -n '/after-policy/,$p' "$RESULTS") && warn "Some AFTER checks failed — see above and describe what you found in the README." || ok "NetworkPolicy enforced as expected."
echo "Next: ./scripts/07-security-checks.sh"
