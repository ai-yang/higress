#!/bin/sh

set -eu

part_one='{"id":"chatcmpl-pr4232","object":"chat.completion","usage":{'
part_two='"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}'
round=0

while :; do
  round=$((round + 1))
  response_fifo="/tmp/pr4232-response-${round}"
  mkfifo "${response_fifo}"
  exec 3<>"${response_fifo}"
  nc -l -N -p 8080 <&3 | {
    IFS= read -r request_line
    printf 'received_request_round=%s line=%s\n' "${round}" "${request_line}"
    printf 'HTTP/1.1 200 OK\r\n' >&3
    printf 'Content-Type: application/json\r\n' >&3
    printf 'Transfer-Encoding: chunked\r\n' >&3
    printf 'Connection: close\r\n' >&3
    printf '\r\n' >&3
    printf '%x\r\n%s\r\n' "${#part_one}" "${part_one}" >&3
    sleep 0.35
    printf '%x\r\n%s\r\n' "${#part_two}" "${part_two}" >&3
    printf '0\r\n\r\n' >&3
    cat >/dev/null
  }
  exec 3>&-
  rm -f "${response_fifo}"
  printf 'served_chunked_json_round=%s part_sizes=%s,%s\n' \
    "${round}" "${#part_one}" "${#part_two}"
done
