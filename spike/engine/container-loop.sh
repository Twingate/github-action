#!/usr/bin/env bash
# Runs inside the container as the engine would. Prints its own context, then
# asks for a token every 5 s for 5 minutes, one "<unix time> <result>" line each.
# Prints names, yes/no and probe results only, never a value.
set -uo pipefail

probe="$(dirname "$0")/probe.sh"

url=no; [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] && url=yes
tok=no; [ -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ] && tok=yes
rootfs=$(awk '$2 == "/" { split($4, o, ","); r = o[1] } END { print r }' /proc/mounts)
if err=$(touch /tmp/.wif-spike-write-test 2>&1); then
  tmp=yes; rm -f /tmp/.wif-spike-write-test
else
  tmp="no (${err##*: })"
fi
caps=$(awk '/^CapEff:/ { print $2 }' /proc/self/status)
nnp=$(awk '/^NoNewPrivs:/ { print $2 }' /proc/self/status)

echo "$(date +%s) context uid=$(id -u) gid=$(id -g) rootfs=$rootfs /tmp-writable=$tmp CapEff=$caps NoNewPrivs=$nnp ACTIONS_ID_TOKEN_REQUEST_URL=$url ACTIONS_ID_TOKEN_REQUEST_TOKEN=$tok"

for _ in $(seq 1 60); do
  echo "$(date +%s) $(bash "$probe")"
  sleep 5
done
