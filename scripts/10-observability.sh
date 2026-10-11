#!/usr/bin/env bash
# Step 10: capture the "where do I look?" observability evidence and print
# direct Cloud Console links for screenshots.
source "$(dirname "$0")/lib.sh"
get_credentials
L=10-observability.log
: > "$EVIDENCE_DIR/$L"

info "Cluster health"
evidence $L gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" --format='value(status,currentMasterVersion,currentNodeCount)'
evidence $L kubectl get nodes
evidence $L kubectl top nodes
evidence $L kubectl get --raw='/readyz?verbose'

info "Workload health"
evidence $L kubectl -n demo get deploy,pods,hpa -o wide
evidence $L kubectl -n demo top pods
evidence $L kubectl -n argocd get application podinfo -o jsonpath='sync={.status.sync.status} health={.status.health.status} revision={.status.sync.revision}{"\n"}'

info "HPA metrics and events"
evidence $L kubectl -n demo describe hpa podinfo
evidence $L kubectl -n demo get events --sort-by=.lastTimestamp

info "Application logs (last 20 lines per pod)"
evidence $L kubectl -n demo logs -l app.kubernetes.io/name=podinfo --tail=20 --prefix
evidence $L gcloud logging read \
  "resource.type=\"k8s_container\" AND resource.labels.cluster_name=\"$CLUSTER_NAME\" AND resource.labels.namespace_name=\"demo\"" \
  --limit=5 --freshness=1h --format='table(timestamp,resource.labels.pod_name,jsonPayload.msg)'

C="https://console.cloud.google.com"
cat <<EOF | tee -a "$EVIDENCE_DIR/$L"

Open these in your browser and take screenshots (include the clock / time range):
  Cluster overview : $C/kubernetes/clusters/details/$ZONE/$CLUSTER_NAME/details?project=$PROJECT_ID
  Workload podinfo : $C/kubernetes/deployment/$ZONE/$CLUSTER_NAME/demo/podinfo/overview?project=$PROJECT_ID
  Logs (namespace) : $C/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.namespace_name%3D%22demo%22?project=$PROJECT_ID
  Metrics Explorer : $C/monitoring/metrics-explorer?project=$PROJECT_ID
  Argo CD UI       : kubectl -n argocd port-forward svc/argocd-server 8080:80  -> Web Preview port 8080
EOF
ok "Observability evidence captured. Next: ./scripts/11-package-evidence.sh"
