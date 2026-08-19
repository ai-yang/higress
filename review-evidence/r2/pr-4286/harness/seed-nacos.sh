#!/usr/bin/env bash
set -euo pipefail
set -x

export KUBECONFIG=/tmp/pr4286-r2-kubeconfig
KUBECTL=/tmp/pr4286-bin/kubectl
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
NACOS=http://127.0.0.1:18848/nacos

mkdir -p "${EVIDENCE}/raw"

backend0_ip=$("${KUBECTL}" get pod -n pr4286-runtime -l app=pr4286-backend-0 -o jsonpath='{.items[0].status.podIP}')
backend1_ip=$("${KUBECTL}" get pod -n pr4286-runtime -l app=pr4286-backend-1 -o jsonpath='{.items[0].status.podIP}')

curl -fsS -X POST "${NACOS}/v1/ns/instance" \
  --data-urlencode serviceName=pr4286-backend \
  --data-urlencode groupName=PR4286_GROUP \
  --data-urlencode "ip=${backend0_ip}" \
  --data-urlencode port=5678 \
  --data-urlencode ephemeral=false
printf '\n'
curl -fsS -X POST "${NACOS}/v1/ns/instance" \
  --data-urlencode serviceName=pr4286-backend \
  --data-urlencode groupName=PR4286_GROUP \
  --data-urlencode "ip=${backend1_ip}" \
  --data-urlencode port=5678 \
  --data-urlencode ephemeral=false
printf '\n'
curl -fsS -X POST "${NACOS}/v1/cs/configs" \
  --data-urlencode dataId=pr4286-backend-mcp-tools.json \
  --data-urlencode group=PR4286_GROUP \
  --data-urlencode "content@${SCRIPT_DIR}/cluster/nacos-tool-config.json"
printf '\n'

curl -fsS "${NACOS}/v1/ns/instance/list?serviceName=pr4286-backend&groupName=PR4286_GROUP" \
  > "${EVIDENCE}/raw/nacos-instances-after-seed.json"
for attempt in $(seq 1 30); do
  if curl -fsS "${NACOS}/v1/cs/configs?dataId=pr4286-backend-mcp-tools.json&group=PR4286_GROUP" \
    > "${EVIDENCE}/raw/nacos-tool-config-after-seed.json"; then
    break
  fi
  sleep 1
done
test -s "${EVIDENCE}/raw/nacos-tool-config-after-seed.json"

"${KUBECTL}" exec -n higress-system deployment/higress-gateway -- curl -fsS "http://${backend0_ip}:5678/"
"${KUBECTL}" exec -n higress-system deployment/higress-gateway -- curl -fsS "http://${backend1_ip}:5678/"
python3 - "${EVIDENCE}/raw/nacos-instances-after-seed.json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
hosts = payload.get("hosts", [])
assert len(hosts) == 2, hosts
assert all(item.get("healthy") and item.get("enabled") for item in hosts), hosts
assert all(item.get("weight") == 1.0 for item in hosts), hosts
assert {item["port"] for item in hosts} == {5678}, hosts
print("nacos_two_healthy_equal_weight_instances=true")
PY
