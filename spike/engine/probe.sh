#!/usr/bin/env bash
# Asks GitHub for an OIDC token the way libwif's github_actions provider does,
# using only this process's environment.
# Prints "ok aud=<aud> lifetime=<s>" or "fail <reason>", never a token.
set -uo pipefail

aud="https://wif-spike.twingate.invalid"
aud_q="https%3A%2F%2Fwif-spike.twingate.invalid"

if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
  echo "fail variables missing"
  exit 1
fi

# The request token goes through a curl config on stdin, so it is never on a command line.
out=$(curl -sS -m 10 -o - -w '\n%{http_code}' -K - <<EOF 2>/dev/null
url = "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${aud_q}"
header = "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}"
header = "Accept: application/json; api-version=2.0"
EOF
)
rc=$?
code=${out##*$'\n'}
body=${out%$'\n'*}
if [ $rc -ne 0 ]; then echo "fail curl exit=$rc"; exit 1; fi
if [ "$code" != "200" ]; then echo "fail http=$code"; exit 1; fi

printf '%s' "$body" | python3 -c '
import sys, json, base64
v = json.load(sys.stdin)["value"]
p = v.split(".")[1]
p += "=" * (-len(p) % 4)
d = json.loads(base64.urlsafe_b64decode(p))
print("ok aud=%s lifetime=%ss" % (d.get("aud"), d.get("exp", 0) - d.get("iat", 0)))
' 2>/dev/null || { echo "fail unreadable answer"; exit 1; }
