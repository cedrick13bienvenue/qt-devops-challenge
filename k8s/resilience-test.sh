#!/usr/bin/env bash
set -uo pipefail

NS=qt-spring-app
URL=${1:-http://192.168.160.211:30080}

step() { printf '\n========== %s ==========\n' "$*"; }

traffic() {
  local out=$1
  while [ -f "$out.run" ]; do
    printf '%s %s\n' "$(date +%T)" "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$URL/api/health")" >> "$out"
    sleep 0.2
  done
}

login_token() {
  curl -s -X POST "$URL/api/auth/login" -H 'Content-Type: application/json' \
    -d '{"email":"admin@qt.rw","password":"Admin@123"}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))'
}

step "Context"
echo "date:    $(date)"
echo "target:  $URL"
kubectl get nodes

step "Part 1: scale the API to 3 replicas"
kubectl -n "$NS" scale deploy/api --replicas=3
kubectl -n "$NS" rollout status deploy/api --timeout=120s
kubectl -n "$NS" get pods -l app=api -o wide

step "Start traffic: GET /api/health every 200 ms"
log=$(mktemp)
touch "$log.run"
traffic "$log" &
traffic_pid=$!
sleep 3

victim=$(kubectl -n "$NS" get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
step "Delete API pod $victim while traffic is running"
kubectl -n "$NS" delete pod "$victim" --wait=false
sleep 15
kubectl -n "$NS" get pods -l app=api -o wide

rm -f "$log.run"
wait "$traffic_pid"

step "Traffic result during the pod deletion"
total=$(wc -l < "$log" | tr -d ' ')
ok=$(grep -c ' 200$' "$log")
echo "requests sent: $total"
echo "HTTP 200:      $ok"
echo "failed:        $((total - ok))"
echo "status codes:"
awk '{print $2}' "$log" | sort | uniq -c
rm -f "$log"

step "Part 2: stop the cache (scale Valkey to 0)"
kubectl -n "$NS" scale deploy/valkey --replicas=0
kubectl -n "$NS" wait --for=delete pod -l app=valkey --timeout=60s 2>/dev/null || true
sleep 3
kubectl -n "$NS" get deploy valkey

step "/api/health with the cache stopped"
curl -s "$URL/api/health"; echo

step "The app still works without the cache"
token=$(login_token)
[ -n "$token" ] && echo "POST /api/auth/login -> token received" || echo "POST /api/auth/login -> FAILED"
printf 'GET /api/projects -> HTTP %s\n' "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" "$URL/api/projects")"
printf 'GET /api/stats    -> HTTP %s\n' "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" "$URL/api/stats")"

step "Restore the cache"
kubectl -n "$NS" scale deploy/valkey --replicas=1
kubectl -n "$NS" rollout status deploy/valkey --timeout=120s
sleep 8
curl -s "$URL/api/health"; echo

step "Final state"
kubectl -n "$NS" get pods -o wide
