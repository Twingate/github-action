#!/usr/bin/env bash
# Does the Twingate user app (twingate-notifier) get the job's OIDC variables?
# Prints only whether each variable is present, never a value.
set -uo pipefail

VARS=(ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN)
UNIT=twingate-desktop-notifier
NOTIFIER=/usr/bin/twingate-notifier
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

section() { echo; echo "=== $*"; }
result() { echo "RESULT: $*"; echo "- $*" >> "$SUMMARY"; }

presence_in_lines() {
  local lines=$1 out=""
  for v in "${VARS[@]}"; do
    if grep -q "^$v=" <<<"$lines"; then out+="$v=yes "; else out+="$v=no "; fi
  done
  echo "$out"
}

proc_env() {
  tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null
}

proc_report() {
  local pid=$1 lines
  lines=$(proc_env "$pid") || true
  if [ -z "$lines" ]; then echo "pid $pid: environment not readable"; return; fi
  echo "pid $pid: $(presence_in_lines "$lines")(vars readable: $(grep -c '=' <<<"$lines"))"
}

manager_report() {
  local lines
  if ! lines=$(systemctl --user show-environment 2>/dev/null); then
    echo "user manager unreachable"
    return 1
  fi
  echo "user manager: $(presence_in_lines "$lines")"
}

probe_report() {
  systemctl --user stop wif-probe >/dev/null 2>&1 || true
  systemctl --user reset-failed wif-probe >/dev/null 2>&1 || true
  if ! systemd-run --user --quiet --unit=wif-probe sleep 120 >/dev/null 2>&1; then
    echo "probe unit: could not start"
    return
  fi
  sleep 1
  local pid
  pid=$(systemctl --user show -p MainPID --value wif-probe)
  echo "probe unit (started by the user manager like the notifier): $(proc_report "$pid")"
  systemctl --user stop wif-probe >/dev/null 2>&1 || true
}

notifier_report() {
  local pid="" i
  for i in $(seq 1 100); do
    pid=$(pgrep -u "$(id -u)" -f "^$NOTIFIER" | head -n1 || true)
    [ -n "$pid" ] && break
    sleep 0.1
  done
  if [ -z "$pid" ]; then echo "notifier: not running"; return; fi
  echo "notifier: $(proc_report "$pid")"
}

use_user_manager() {
  if [ -d "/run/user/$(id -u)" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  fi
}

echo "## Linux" >> "$SUMMARY"

section "Step environment"
for v in "${VARS[@]}"; do
  if [ -n "${!v:-}" ]; then echo "$v: present in the step"; else echo "$v: MISSING in the step"; fi
done

section "Session context"
id
echo "XDG_RUNTIME_DIR in the step: ${XDG_RUNTIME_DIR:-<unset>}"
loginctl list-sessions --no-pager || true
loginctl list-users --no-pager || true
loginctl show-user "$(id -un)" -p State -p Linger --no-pager || true
ls -la /run/user || true

section "Install Twingate"
echo "deb [trusted=yes] https://packages.twingate.com/apt/ /" | sudo tee /etc/apt/sources.list.d/twingate.list >/dev/null
sudo apt-get update -qq -o Dir::Etc::sourcelist="sources.list.d/twingate.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
sudo apt-get install -yq twingate >/dev/null
dpkg -s twingate | grep -i '^version'

section "After install"
use_user_manager
if manager_report; then
  systemctl --user status "$UNIT" --no-pager --lines=5 || true
  result "after install: $(manager_report)"
  result "after install: $(probe_report)"
  result "after install: $(notifier_report)"
else
  result "after install: no user manager for $(id -un), so postinst couldn't start the notifier"
  section "Enable lingering to get a user manager"
  sudo loginctl enable-linger "$(id -un)"
  for i in $(seq 1 20); do [ -S "/run/user/$(id -u)/bus" ] && break; sleep 0.5; done
  use_user_manager
  systemctl --user start "$UNIT" || true
  result "with lingering: $(manager_report)"
  result "with lingering: $(probe_report)"
  result "with lingering: $(notifier_report)"
fi

section "Workaround A: import the variables into the user manager, restart the notifier"
systemctl --user import-environment "${VARS[@]}"
systemctl --user restart "$UNIT" || true
result "workaround A: $(manager_report)"
result "workaround A: $(probe_report)"
result "workaround A: $(notifier_report)"
systemctl --user unset-environment "${VARS[@]}"

section "Workaround B: stop the unit, run the notifier from the step"
systemctl --user stop "$UNIT" || true
nohup "$NOTIFIER" >/dev/null 2>&1 &
result "workaround B: $(notifier_report)"
sleep 10
if pgrep -u "$(id -u)" -f "^$NOTIFIER" >/dev/null; then
  result "workaround B: still running after 10 s"
else
  result "workaround B: exited within 10 s (it needs the daemon's auth.sock)"
fi
pkill -u "$(id -u)" -f "^$NOTIFIER" || true
