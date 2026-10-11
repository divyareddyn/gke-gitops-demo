#!/usr/bin/env bash
# Step 9: repeatable load test showing scale-out and scale-in.
#   - k6 Job in the "loadgen" namespace hammers podinfo for LOAD_DURATION
#   - a watcher records HPA/replica/CPU every 5s           -> 09-hpa-timeline.csv
#   - a probe calls the app once per second the whole time -> 09-reachability.csv
#   - at the end, a summary table is written               -> 09-loadtest-summary.md
source "$(dirname "$0")/lib.sh"
get_credentials

TL="$EVIDENCE_DIR/09-hpa-timeline.csv"
RC="$EVIDENCE_DIR/09-reachability.csv"
MK="$EVIDENCE_DIR/09-markers.txt"
L=09-loadtest.log
to_seconds() { local d="$1"; case "$d" in *m) echo $(( ${d%m} * 60 ));; *s) echo "${d%s}";; *) echo "$d";; esac; }
LOAD_SECS=$(to_seconds "$LOAD_DURATION")
MIN_REPLICAS=$(kubectl -n demo get hpa podinfo -o jsonpath='{.spec.minReplicas}')

info "Preparing (test clients + k6 job definition)"
kubectl apply -f "$REPO_ROOT/tests/netpol/clients.yaml" >/dev/null
kubectl -n loadgen wait --for=condition=Ready pod/allowed-client --timeout=120s >/dev/null
kubectl -n loadgen delete job k6-load --ignore-not-found --wait=true >/dev/null
JOB_FILE=$(mktemp)
sed -e "s/__VUS__/${LOAD_VUS}/" -e "s/__DURATION__/${LOAD_DURATION}/" "$REPO_ROOT/tests/load/k6-job.yaml" > "$JOB_FILE"

echo "time_utc,epoch,hpa_current_replicas,hpa_desired_replicas,cpu_utilization_pct,ready_pods" > "$TL"
echo "time_utc,http_code,latency_s" > "$RC"
: > "$MK"
: > "$EVIDENCE_DIR/$L"
mark() { echo "$(now) $(date +%s) $*" | tee -a "$MK"; }

watcher() {
  set +e
  while true; do
    cur=""; des=""; cpu=""
    read -r cur des cpu < <(kubectl -n demo get hpa podinfo -o jsonpath='{.status.currentReplicas} {.status.desiredReplicas} {.status.currentMetrics[0].resource.current.averageUtilization}{"\n"}' 2>/dev/null)
    ready=$(kubectl -n demo get deploy podinfo -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
    echo "$(now),$(date +%s),${cur:-},${des:-},${cpu:-},${ready:-0}" >> "$TL"
    sleep 5
  done
}

info "Starting watcher and 1-request-per-second reachability probe"
watcher & WATCH_PID=$!
PROBE_SECS=$(( 30 + LOAD_SECS + 900 ))
kubectl -n loadgen exec allowed-client -- sh -c "end=\$(( \$(date +%s) + $PROBE_SECS )); while [ \$(date +%s) -lt \$end ]; do r=\$(curl -s -o /dev/null -m 2 -w '%{http_code},%{time_total}' http://podinfo.demo.svc.cluster.local/); echo \"\$(date -u +%Y-%m-%dT%H:%M:%SZ),\$r\"; sleep 1; done" >> "$RC" 2>/dev/null &
PROBE_PID=$!
cleanup() { kill "$WATCH_PID" "$PROBE_PID" 2>/dev/null || true; }
trap cleanup EXIT

info "Baseline (30s, no load)"
mark BASELINE_START
evidence $L kubectl -n demo get hpa,deploy podinfo
sleep 30

info "LOAD: k6 with ${LOAD_VUS} virtual users for ${LOAD_DURATION}"
mark LOAD_START
kubectl apply -f "$JOB_FILE"
job_deadline=$(( $(date +%s) + LOAD_SECS + 300 ))
while true; do
  s=$(kubectl -n loadgen get job k6-load -o jsonpath='{.status.succeeded}{.status.failed}' 2>/dev/null || true)
  [[ -n "$s" ]] && break
  (( $(date +%s) > job_deadline )) && { warn "k6 job did not finish in time — check: kubectl -n loadgen get pods"; break; }
  printf '[%s] cpu=%s%%  current=%s  desired=%s\n' "$(now)" \
    "$(kubectl -n demo get hpa podinfo -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)" \
    "$(kubectl -n demo get hpa podinfo -o jsonpath='{.status.currentReplicas}' 2>/dev/null)" \
    "$(kubectl -n demo get hpa podinfo -o jsonpath='{.status.desiredReplicas}' 2>/dev/null)"
  sleep 15
done
mark LOAD_END
kubectl -n loadgen logs job/k6-load > "$EVIDENCE_DIR/09-k6-output.log" 2>&1 || true
evidence $L kubectl -n loadgen get job k6-load
evidence $L kubectl -n demo get hpa,deploy podinfo
evidence $L kubectl -n demo top pods

info "COOL-DOWN: waiting for replicas to return to minReplicas=$MIN_REPLICAS (up to 12 min)"
end=$(( $(date +%s) + 720 )); streak=0
while (( $(date +%s) < end )); do
  cur=$(kubectl -n demo get hpa podinfo -o jsonpath='{.status.currentReplicas}')
  printf '[%s] replicas=%s\n' "$(now)" "$cur"
  if [[ "$cur" == "$MIN_REPLICAS" ]]; then streak=$((streak+1)); else streak=0; fi
  (( streak >= 2 )) && break
  sleep 15
done
mark COOLDOWN_END
sleep 5; cleanup; trap - EXIT

evidence $L kubectl -n demo describe hpa podinfo
evidence $L kubectl -n demo get events --field-selector involvedObject.kind=HorizontalPodAutoscaler --sort-by=.lastTimestamp

info "Building summary"
python3 - "$TL" "$RC" "$MK" "$EVIDENCE_DIR/09-loadtest-summary.md" "$LOAD_VUS" "$LOAD_DURATION" "$MIN_REPLICAS" <<'PY'
import csv, sys, statistics
tl_path, rc_path, mk_path, out, vus, dur, minr = sys.argv[1:8]
minr = int(minr)
marks = {}
for line in open(mk_path):
    t, ep, name = line.split()[:3]; marks[name] = (t, int(ep))
rows = [r for r in csv.DictReader(open(tl_path)) if r["hpa_current_replicas"] not in ("", "-")]
def i(v):
    try: return int(v)
    except: return None
ls, le = marks["LOAD_START"][1], marks["LOAD_END"][1]
base = rows[0]
peak = max(rows, key=lambda r: i(r["hpa_current_replicas"]) or 0)
peak_cpu = max((i(r["cpu_utilization_pct"]) or 0) for r in rows)
first_desired = next((r for r in rows if int(r["epoch"]) >= ls and (i(r["hpa_desired_replicas"]) or 0) > minr), None)
first_ready = next((r for r in rows if int(r["epoch"]) >= ls and (i(r["ready_pods"]) or 0) > minr), None)
back = next((r for r in rows if int(r["epoch"]) >= le and i(r["hpa_current_replicas"]) == minr), None)
probe = [r for r in csv.DictReader(open(rc_path)) if r.get("http_code")]
ok = [r for r in probe if r["http_code"] == "200"]
lat = sorted(float(r["latency_s"]) for r in ok) or [0]
p95 = lat[int(0.95 * (len(lat) - 1))]
fmt = lambda r, ref: f'{r["time_utc"]} (+{int(r["epoch"]) - ref}s)' if r else "not observed"
with open(out, "w") as f:
    f.write("# Load test summary\n\n")
    f.write("| Item | Value |\n|---|---|\n")
    f.write(f"| Load method | k6 Job in namespace `loadgen` (allowed by NetworkPolicy), {vus} VUs, constant for {dur}, GET `/` on Service `podinfo.demo` |\n")
    f.write("| HPA target | CPU 60% of the 50m request, min 2 / max 6, scale-down window 60s |\n")
    f.write(f"| Load window | {marks['LOAD_START'][0]} → {marks['LOAD_END'][0]} |\n")
    f.write(f"| Baseline replicas / CPU | {base['hpa_current_replicas']} pods / {base['cpu_utilization_pct']}% |\n")
    f.write(f"| Peak replicas / peak CPU | {peak['hpa_current_replicas']} pods at {peak['time_utc']} / {peak_cpu}% |\n")
    f.write(f"| HPA first asked for more pods | {fmt(first_desired, ls)} after load start |\n")
    f.write(f"| First extra pod Ready | {fmt(first_ready, ls)} after load start |\n")
    f.write(f"| Back to {minr} replicas | {fmt(back, le)} after load end |\n")
    f.write(f"| Reachability probe (1 req/s, whole test) | {len(ok)}/{len(probe)} OK ({(100*len(ok)/max(len(probe),1)):.2f}%), p95 {p95*1000:.0f} ms, max {lat[-1]*1000:.0f} ms |\n")
    f.write("\n## Timeline (every ~30s)\n\n| Time (UTC) | Phase | Current | Desired | CPU % | Ready |\n|---|---|---|---|---|---|\n")
    last = 0
    for r in rows:
        ep = int(r["epoch"])
        if ep - last < 30: continue
        last = ep
        phase = "baseline" if ep < ls else ("LOAD" if ep <= le else "cool-down")
        f.write(f"| {r['time_utc']} | {phase} | {r['hpa_current_replicas']} | {r['hpa_desired_replicas']} | {r['cpu_utilization_pct']} | {r['ready_pods']} |\n")
print(open(out).read())
PY
ok "Load test done. Evidence: 09-loadtest-summary.md, 09-hpa-timeline.csv, 09-reachability.csv, 09-k6-output.log"
echo "Next: ./scripts/10-observability.sh"
