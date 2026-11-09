#!/usr/bin/env bash
# Engine-side libwif on a Linux runner: can a root system service, like
# twingated, get the job's OIDC token? Prints results only, never a value.
# Usage: linux.sh start | check
set -uo pipefail

DIR=/opt/wif-spike
LOG=/var/log/wif-spike/service.log
END="$RUNNER_TEMP/forward_step_end"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
VARS=(ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN)

result() { echo "RESULT: $*"; echo "- $*" >> "$SUMMARY"; }

request_token_lifetime() {
  python3 - <<'EOF'
import os, json, base64, time
parts = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN", "").split(".")
if len(parts) != 3:
    print("not a JWT")
else:
    p = parts[1] + "=" * (-len(parts[1]) % 4)
    d = json.loads(base64.urlsafe_b64decode(p))
    start = d.get("iat", d.get("nbf", 0))
    print("valid for %ss more, lifetime %ss" % (d.get("exp", 0) - int(time.time()), d.get("exp", 0) - start))
EOF
}

start() {
  echo "## Linux" >> "$SUMMARY"
  sudo install -d -m 755 "$DIR"
  sudo install -m 755 spike/engine/probe.sh spike/engine/service.sh "$DIR/"
  sudo install -d -m 700 /var/log/wif-spike

  result "linux: the job's request token is $(request_token_lifetime)"
  result "linux: a step gets a token: $("$DIR/probe.sh")"

  result "linux control: a root system service, nothing forwarded: $(sudo systemd-run --wait --pipe --quiet "$DIR/probe.sh" 2>&1)"

  # Option C: the action pushes the variables into the system manager, then starts a unit.
  sudo --preserve-env="$(IFS=,; echo "${VARS[*]}")" systemctl import-environment "${VARS[@]}"
  result "linux option C (systemctl import-environment, new unit): $(sudo systemd-run --wait --pipe --quiet "$DIR/probe.sh" 2>&1)"
  sudo systemctl unset-environment "${VARS[@]}"

  # Option A: the CLI forwards the variables over IPC. A root-only file stands in for IPC.
  local f
  f=$(umask 077; mktemp)
  for v in "${VARS[@]}"; do printf '%s=%q\n' "$v" "${!v}"; done > "$f"
  sudo install -m 600 -o root -g root "$f" /run/wif-spike.env
  rm -f "$f"
  sudo systemd-run --unit=wif-spike --quiet "$DIR/service.sh" /run/wif-spike.env "$LOG"
  sleep 8
  sudo cat "$LOG"
  date +%s > "$END"
}

check() {
  sleep 30
  local end after
  end=$(cat "$END")
  after=$(sudo awk -v end="$end" '$1 > end' "$LOG")
  echo "$after" | tail -n 5
  result "linux option A, root service: $(sudo head -n1 "$LOG" | cut -d' ' -f2-)"
  result "linux option A, root service, after the forwarding step ended: $(grep -c ' ok ' <<<"$after") ok, $(grep -c ' fail' <<<"$after") fail; last: $(tail -n1 <<<"$after" | cut -d' ' -f2-)"
  sudo systemctl stop wif-spike || true
  grep -q ' ok ' <<<"$after" && ! grep -q ' fail' <<<"$after"
}

"$1"
