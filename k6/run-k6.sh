#!/usr/bin/env bash
# Runs the k6 load test and pushes results to Prometheus on vm-monitor (Grafana dashboard "TravelAgency load test (k6)").
# Uses the grafana/k6 Docker image, so k6 does not have to be installed.
#
#   TEST_TYPE=smoke  ./k6/run-k6.sh     # 1 user, 1 min: check that everything works
#   TEST_TYPE=load   ./k6/run-k6.sh     # 30 users, 10 min (VUS=50 to change)
#   TEST_TYPE=stress ./k6/run-k6.sh     # 20 -> 150 users, 24 min: find the limit
#   TEST_TYPE=spike  ./k6/run-k6.sh     # 5 -> 150 -> 5 users
#
# Run it from a machine that is NOT one of the tested servers (ansible host, your PC, vm-agent),
# otherwise k6 eats the CPU of the server it measures.
set -euo pipefail
cd "$(dirname "$0")"

TEST_TYPE="${TEST_TYPE:-smoke}"
BASE_URL="${BASE_URL:-http://192.168.18.106}"          # nginx on vm-lb
PROMETHEUS="${PROMETHEUS:-http://192.168.18.108:9090}"  # Prometheus on vm-monitor
GRAFANA="${GRAFANA:-http://192.168.18.108:3000}"
TESTID="${TESTID:-${TEST_TYPE}-$(date +%Y%m%d-%H%M)}"   # name of this run in Grafana
K6_IMAGE="${K6_IMAGE:-grafana/k6:1.3.0}"

mkdir -p results
echo "k6: ${TEST_TYPE} against ${BASE_URL}, testid=${TESTID}"
echo "Watch: ${GRAFANA}/d/travelagency-k6?var-testid=${TESTID}&from=now-30m&to=now&refresh=10s"

docker run --rm -i --network host \
  -u "$(id -u):$(id -g)" \
  -v "$PWD:/scripts" -w /scripts \
  -e TEST_TYPE="$TEST_TYPE" -e VUS -e USERS -e THINK -e USER_PREFIX -e K6_USER_PASSWORD \
  -e K6_PROMETHEUS_RW_SERVER_URL="${PROMETHEUS}/api/v1/write" \
  -e K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true \
  -e K6_PROMETHEUS_RW_PUSH_INTERVAL=5s \
  -e BASE_URL="$BASE_URL" \
  "$K6_IMAGE" run \
    -o experimental-prometheus-rw \
    --tag testid="$TESTID" \
    --summary-export "results/${TESTID}.json" \
    travelagency.js