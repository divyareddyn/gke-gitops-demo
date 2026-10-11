#!/usr/bin/env bash
# Step 5: verify the app — pods, Service, probes, resources, HPA, metrics, image, version.
source "$(dirname "$0")/lib.sh"
get_credentials
L=05-app-verify.log
: > "$EVIDENCE_DIR/$L"

info "Waiting for the rollout"
evidence $L kubectl -n demo rollout status deploy/podinfo --timeout=180s

info "What's running"
evidence $L kubectl -n demo get deploy,pods,svc,hpa,pdb -o wide
evidence $L kubectl -n demo get deploy podinfo -o jsonpath='{range .spec.template.spec.containers[*]}image={.image}{"\n"}requests={.resources.requests}{"\n"}limits={.resources.limits}{"\n"}readiness={.readinessProbe.httpGet.path}  liveness={.livenessProbe.httpGet.path}{"\n"}{end}'
evidence $L kubectl -n demo get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  imageID="}{.status.containerStatuses[0].imageID}{"\n"}{end}'

info "Metrics pipeline for the HPA (GKE-managed metrics-server)"
evidence $L kubectl get apiservice v1beta1.metrics.k8s.io
for i in $(seq 1 24); do
  t=$(kubectl -n demo get hpa podinfo -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)
  [[ -n "$t" ]] && break
  echo "  HPA has no CPU reading yet (normal for the first 1-2 minutes)..."; sleep 10
done
evidence $L kubectl -n demo top pods
evidence $L kubectl -n demo get hpa podinfo
evidence $L kubectl -n demo describe hpa podinfo

info "Calling the app (port-forward from Cloud Shell)"
kubectl -n demo port-forward svc/podinfo 9898:80 >/dev/null 2>&1 &
PF=$!; sleep 4
evidence $L bash -c "curl -s localhost:9898 | jq '{hostname, version, revision, message}'"
evidence $L bash -c "curl -s -o /dev/null -w 'GET /healthz -> %{http_code}\n' localhost:9898/healthz; curl -s -o /dev/null -w 'GET /readyz  -> %{http_code}\n' localhost:9898/readyz"
kill $PF 2>/dev/null || true

ok "App verified. Next: ./scripts/06-netpol-test.sh"
