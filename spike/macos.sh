#!/usr/bin/env bash
# Does the Twingate app get the job's OIDC variables?
# Prints only whether each variable is present, never a value.
set -uo pipefail

VARS=(ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN)
APP=/Applications/Twingate.app
BIN="$APP/Contents/MacOS/Twingate"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

section() { echo; echo "=== $*"; }
result() { echo "RESULT: $*"; echo "- $*" >> "$SUMMARY"; }

app_pid() {
  local pid="" i
  for i in $(seq 1 30); do
    pid=$(pgrep -u "$(id -u)" -x Twingate | head -n1 || true)
    [ -n "$pid" ] && break
    sleep 1
  done
  echo "$pid"
}

proc_report() {
  local pid=$1 line out=""
  line=$(ps eww -o command= -p "$pid" 2>/dev/null || true)
  if ! grep -q " HOME=" <<<"$line"; then
    line=$(sudo ps eww -o command= -p "$pid" 2>/dev/null || true)
  fi
  if ! grep -q " HOME=" <<<"$line"; then echo "pid $pid: environment not readable"; return; fi
  for v in "${VARS[@]}"; do
    if grep -q " $v=" <<<"$line"; then out+="$v=yes "; else out+="$v=no "; fi
  done
  echo "pid $pid: $out"
}

app_report() {
  local pid
  pid=$(app_pid)
  if [ -z "$pid" ]; then echo "app: not running"; return; fi
  echo "app: $(proc_report "$pid")"
}

launchd_report() {
  local out=""
  for v in "${VARS[@]}"; do
    if [ -n "$(launchctl getenv "$v")" ]; then out+="$v=yes "; else out+="$v=no "; fi
  done
  echo "launchd user domain: $out"
}

echo "## macOS" >> "$SUMMARY"

section "Step environment"
for v in "${VARS[@]}"; do
  if [ -n "${!v:-}" ]; then echo "$v: present in the step"; else echo "$v: MISSING in the step"; fi
done

section "Session context"
echo "step user: $(id -un) ($(id -u)), console user: $(stat -f '%Su' /dev/console)"
launchctl managername || true

section "Install Twingate"
curl -fsSL -o "$RUNNER_TEMP/Twingate.pkg" "https://api.twingate.com/download/darwin?installer=pkg"
sudo installer -pkg "$RUNNER_TEMP/Twingate.pkg" -target / | tail -n 3
LABEL=""
AGENT=$(ls /Library/LaunchAgents/*.plist 2>/dev/null | grep -i twingate | head -n1 || true)
if [ -n "$AGENT" ]; then
  LABEL=$(plutil -extract Label raw "$AGENT" 2>/dev/null || basename "$AGENT" .plist)
  echo "LaunchAgent: $AGENT (label $LABEL)"
else
  echo "LaunchAgent: none"
fi

section "After install"
result "after install: $(launchd_report)"
result "after install: $(app_report)"

section "Workaround A: launchctl setenv, restart the app through launchd"
for v in "${VARS[@]}"; do launchctl setenv "$v" "${!v}"; done
if [ -n "$LABEL" ]; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL" || true
else
  pkill -u "$(id -u)" -x Twingate || true
  sleep 2
  open -a "$APP" || true
fi
sleep 5
result "workaround A: $(launchd_report)"
result "workaround A: $(app_report)"
for v in "${VARS[@]}"; do launchctl unsetenv "$v"; done

section "Workaround B: run the app binary from the step"
if [ -n "$LABEL" ]; then launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; fi
pkill -u "$(id -u)" -x Twingate || true
sleep 2
nohup "$BIN" >/dev/null 2>&1 &
result "workaround B: $(app_report)"
sleep 10
if pgrep -u "$(id -u)" -x Twingate >/dev/null; then
  result "workaround B: still running after 10 s"
else
  result "workaround B: exited within 10 s"
fi
