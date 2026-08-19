#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly EVIDENCE_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd "${EVIDENCE_ROOT}"

grep -Fq $'ok  \tgithub.com/alibaba/higress/plugins/wasm-go/extensions/ai-proxy/provider' logs/provider-unit.txt
grep -Fq $'ok  \tgithub.com/alibaba/higress/plugins/wasm-go/extensions/ai-proxy/provider' logs/provider-race-x20.txt
grep -Fq 'github.com/alibaba/higress/plugins/wasm-go/extensions/ai-proxy' logs/full-module-tests.txt

cmp -s logs/vet-baseline.txt logs/vet-fixed.txt
grep -Fxq 'baseline=1' logs/vet-status.txt
grep -Fxq 'fixed=1' logs/vet-status.txt
! grep -Eq 'gemini\.go|gemini_test\.go' logs/vet-baseline.txt logs/vet-fixed.txt

grep -Fq '699234632268bc4c5cce2c6c981759097d88c87dc40605a2e001f8bddcae83ab' logs/wasm-sha256.txt
grep -Fq 'e24b2003ae808a1551acdfad2d2b91418c434fb68862c79d4a83af60e550c0d7' logs/wasm-sha256.txt

[[ $(grep -c '^200$' results/baseline-http-codes.txt) -eq 3 ]]
[[ $(grep -c '^200$' results/fixed-http-codes.txt) -eq 3 ]]
grep -Fxq 'panic_count=3' results/baseline-counts.txt
grep -Fxq 'response_log_count=3' results/baseline-counts.txt
grep -Fxq 'mock_200_count=3' results/baseline-counts.txt
grep -Fxq 'panic_count=0' results/fixed-counts.txt
grep -Fxq 'response_log_count=3' results/fixed-counts.txt
grep -Fxq 'mock_200_count=3' results/fixed-counts.txt

[[ $(grep -cF 'recovered from panic runtime error: invalid memory address or nil pointer dereference' logs/baseline-envoy.log) -eq 3 ]]
! grep -Eq 'panic|nil pointer dereference' logs/fixed-envoy.log

cmp -s results/baseline-body-1.bin results/baseline-body-2.bin
cmp -s results/baseline-body-1.bin results/baseline-body-3.bin
for body in results/baseline-body-1.bin results/baseline-body-2.bin results/baseline-body-3.bin; do
  python3 harness/assert_baseline_response.py "$body" harness/gemini-response.json >/dev/null
done
for body in results/fixed-body-1.json results/fixed-body-2.json results/fixed-body-3.json; do
  python3 harness/assert_fixed_response.py "$body" >/dev/null
done

test ! -s results/cleanup-compose-ps.json
test ! -s results/cleanup-docker-ps.txt
grep -Fxq '11088=7' results/cleanup-port-status.txt
grep -Fxq '19988=7' results/cleanup-port-status.txt
grep -Fxq 'docker_project_containers=0' results/cleanup-audit.txt
grep -Fxq 'docker_project_networks=0' results/cleanup-audit.txt
grep -Fxq 'docker_project_volumes=0' results/cleanup-audit.txt

sha256sum -c --quiet SHA256SUMS
echo 'offline evidence verification: PASS'
