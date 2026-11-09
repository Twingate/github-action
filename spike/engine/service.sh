#!/usr/bin/env bash
# Stands in for the engine in a system service. Reads the variables the CLI
# would forward over engine IPC from a file only its own user can read,
# deletes the file, then asks for a token every 5 s for 5 minutes.
# Usage: service.sh <forwarded file or -> <log>
set -uo pipefail

src=$1
log=$2
probe="$(dirname "$0")/probe.sh"

own=no
[ -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ] && own=yes
if [ "$src" != "-" ] && [ -f "$src" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$src"
  set +a
  rm -f "$src"
  forwarded=yes
else
  forwarded=no
fi
echo "$(date +%s) context user=$(id -un) variables-in-own-environment=$own forwarded=$forwarded file-left-on-disk=$([ -e "$src" ] && echo yes || echo no)" >> "$log"

for _ in $(seq 1 60); do
  echo "$(date +%s) $("$probe")" >> "$log"
  sleep 5
done
