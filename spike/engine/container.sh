#!/usr/bin/env bash
# Engine in a container on a Linux runner: a step starts a hardened container
# with `docker run -e NAME` (name only, docker copies the value from the step's
# environment). Does it get the job's OIDC token, and keep getting it after
# that step ended? Prints results only, never a value. Never inspects the
# containers or dumps their environment.
# Usage: container.sh start | check
set -uo pipefail

IMAGE=python:3.12.12-bookworm
END="$RUNNER_TEMP/container_step_end"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
HARDEN=(--user 1000:1000 --read-only --cap-drop ALL --security-opt no-new-privileges
        -v "$PWD/spike/engine:/spike:ro")
LOOP=(bash /spike/container-loop.sh)

result() { echo "RESULT: $*"; echo "- $*" >> "$SUMMARY"; }
label() { case $1 in wif-control) echo "control (no -e)";; wif-test) echo "test (-e names, uid 1000, read-only, no caps)";; esac; }

start() {
  echo "## Container" >> "$SUMMARY"
  docker pull "$IMAGE" | grep -E '^(Digest|Status):'
  result "container: image $IMAGE as uid 1000 on a read-only rootfs has: $(docker run --rm "${HARDEN[@]}" "$IMAGE" \
    bash -c 'echo "bash $BASH_VERSION, $(curl --version | head -n1 | cut -d" " -f1-2), $(python3 --version)"' 2>&1)"
  result "container: the step itself gets a token: $(bash spike/engine/probe.sh)"

  docker run -d --name wif-control "${HARDEN[@]}" "$IMAGE" "${LOOP[@]}" >/dev/null
  docker run -d --name wif-test \
    -e ACTIONS_ID_TOKEN_REQUEST_URL -e ACTIONS_ID_TOKEN_REQUEST_TOKEN \
    "${HARDEN[@]}" "$IMAGE" "${LOOP[@]}" >/dev/null
  sleep 8
  for c in wif-control wif-test; do
    docker logs "$c" 2>&1 | sed "s/^/PROBE $c: /"
    result "container $(label $c): $(docker logs "$c" 2>&1 | awk '$2 == "context"' | cut -d' ' -f2-)"
  done
  date +%s > "$END"
}

check() {
  sleep 60
  local end c logs before after pass=0
  end=$(cat "$END")
  for c in wif-control wif-test; do
    logs=$(docker logs "$c" 2>&1)
    echo "$logs" | sed "s/^/PROBE $c: /"
    before=$(awk -v end="$end" '$1 ~ /^[0-9]+$/ && $1 <= end && $2 != "context"' <<<"$logs")
    after=$(awk -v end="$end" '$1 ~ /^[0-9]+$/ && $1 > end' <<<"$logs")
    result "container $(label $c): first result before the start step ended: $(head -n1 <<<"$before" | cut -d' ' -f2-)"
    result "container $(label $c): after the start step ended: $(grep -c ' ok ' <<<"$after") ok, $(grep -c ' fail' <<<"$after") fail; last, $(( $(tail -n1 <<<"$after" | cut -d' ' -f1) - end ))s after the step ended: $(tail -n1 <<<"$after" | cut -d' ' -f2-)"
    local other
    other=$(grep -cvE '^[0-9]+ ' <<<"$logs")
    [ "$other" -gt 0 ] && result "container $(label $c): $other other output line(s), shown above"
    case $c in
      wif-control) grep -q ' ok ' <<<"$after" || ! grep -q ' fail variables missing' <<<"$after" && pass=1;;
      wif-test) grep -q ' ok ' <<<"$after" && ! grep -q ' fail' <<<"$after" || pass=1;;
    esac
  done
  docker rm -f wif-control wif-test >/dev/null
  return $pass
}

"$1"
