#!/usr/bin/env bash
# Engine-side libwif on a macOS runner: can a root launchd daemon, or a launchd
# agent in the user's GUI domain like the app that hosts engine IPC, get the
# job's OIDC token when the variables are forwarded to it? Also reports whether
# the shipped app is sandboxed. Prints results only, never a value.
# Usage: macos.sh start | check
set -uo pipefail

DIR=/usr/local/libexec/wif-spike
DLOG=/var/log/wif-spike/daemon.log
CLOG=/var/log/wif-spike/control.log
ALOG="$HOME/wif-spike-agent.log"
END="$RUNNER_TEMP/forward_step_end"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
VARS=(ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN)

result() { echo "RESULT: $*"; echo "- $*" >> "$SUMMARY"; }

plist() {
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$1</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$DIR/service.sh</string><string>$2</string><string>$3</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
EOF
}

forward_file() {
  local f
  f=$(umask 077; mktemp)
  for v in "${VARS[@]}"; do printf '%s=%q\n' "$v" "${!v}"; done > "$f"
  echo "$f"
}

start() {
  echo "## macOS" >> "$SUMMARY"
  sudo install -d -m 755 "$DIR"
  sudo install -m 755 spike/engine/probe.sh spike/engine/service.sh "$DIR/"
  sudo install -d -m 755 /var/log/wif-spike

  result "macos: a step gets a token: $("$DIR/probe.sh")"

  plist com.twingate.wif-spike.control - "$CLOG" | sudo tee /Library/LaunchDaemons/com.twingate.wif-spike.control.plist >/dev/null
  sudo launchctl bootstrap system /Library/LaunchDaemons/com.twingate.wif-spike.control.plist

  # Option A, root daemon. A root-only file stands in for engine IPC.
  local f
  f=$(forward_file)
  sudo install -m 600 -o root -g wheel "$f" /var/run/wif-spike.env
  rm -f "$f"
  plist com.twingate.wif-spike.daemon /var/run/wif-spike.env "$DLOG" | sudo tee /Library/LaunchDaemons/com.twingate.wif-spike.daemon.plist >/dev/null
  sudo launchctl bootstrap system /Library/LaunchDaemons/com.twingate.wif-spike.daemon.plist

  # Option A, launchd agent in the GUI domain, where the app runs.
  f=$(forward_file)
  mv "$f" "$HOME/.wif-spike.env"
  mkdir -p "$HOME/Library/LaunchAgents"
  plist com.twingate.wif-spike.agent "$HOME/.wif-spike.env" "$ALOG" > "$HOME/Library/LaunchAgents/com.twingate.wif-spike.agent.plist"
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.twingate.wif-spike.agent.plist" || result "macos: could not bootstrap the agent in gui/$(id -u)"

  sleep 8
  date +%s > "$END"
  sudo cat "$CLOG" "$DLOG"; cat "$ALOG"
}

report() {
  local name=$1 log=$2 end after
  end=$(cat "$END")
  after=$(sudo awk -v end="$end" '$1 > end' "$log")
  result "macos $name: $(sudo head -n1 "$log" | cut -d' ' -f2-)"
  result "macos $name, after the forwarding step ended: $(grep -c ' ok ' <<<"$after") ok, $(grep -c ' fail' <<<"$after") fail; last: $(tail -n1 <<<"$after" | cut -d' ' -f2-)"
}

check() {
  curl -fsSL -o "$RUNNER_TEMP/Twingate.pkg" "https://api.twingate.com/download/darwin?installer=pkg"
  sudo installer -pkg "$RUNNER_TEMP/Twingate.pkg" -target / | tail -n 1
  local ents
  ents=$(codesign -d --entitlements - --xml /Applications/Twingate.app 2>/dev/null | grep -o '<key>[^<]*</key>' | sed 's/<[^>]*>//g' | tr '\n' ' ')
  [ -n "$ents" ] || ents=$(codesign -d --entitlements :- /Applications/Twingate.app 2>/dev/null | grep -o '<key>[^<]*</key>' | sed 's/<[^>]*>//g' | tr '\n' ' ')
  echo "app entitlements: $ents"
  result "macos: the released app is sandboxed: $(grep -q 'com.apple.security.app-sandbox' <<<"$ents" && echo yes || echo no), network client entitlement: $(grep -q 'com.apple.security.network.client' <<<"$ents" && echo yes || echo no)"

  sleep 20
  report "control (root daemon, nothing forwarded)" "$CLOG"
  report "option A (root daemon)" "$DLOG"
  report "option A (GUI-domain agent, like the app)" "$ALOG"
  sudo launchctl bootout system/com.twingate.wif-spike.control || true
  sudo launchctl bootout system/com.twingate.wif-spike.daemon || true
  launchctl bootout "gui/$(id -u)/com.twingate.wif-spike.agent" || true
}

"$1"
