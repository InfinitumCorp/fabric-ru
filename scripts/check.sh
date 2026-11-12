#!/bin/bash
# Outside checks for https://ru.infinitumfabric.app. Exits non-zero if any check fails.
set -uo pipefail
BASE=${1:-https://ru.infinitumfabric.app}
fail=0
check() { # name expected-code url [curl args...]
  local name=$1 want=$2 url=$3; shift 3
  local got; got=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 --retry 3 "$@" "$url")
  if [ "$got" = "$want" ]; then echo "ok   $name ($got)"; else echo "FAIL $name: got $got, want $want"; fail=1; fi
}
check "well-known client"        200 "$BASE/.well-known/matrix/client"
check "client versions"          200 "$BASE/_matrix/client/versions"
check "registration closed"      403 "$BASE/_matrix/client/v3/register" -X POST -H 'Content-Type: application/json' -d '{"username":"probe","password":"probe-not-real","auth":{"type":"m.login.dummy"}}'
# Sign-in is Cumulus://ID only: the login flows offer SSO and not passwords.
flows=$(curl -s --max-time 20 --retry 3 "$BASE/_matrix/client/v3/login")
if echo "$flows" | grep -q '"m.login.sso"' && ! echo "$flows" | grep -q '"m.login.password"'; then
  echo "ok   sign-in is Cumulus://ID (SSO only)"
else
  echo "FAIL sign-in: want m.login.sso and no m.login.password, got $flows"; fail=1
fi
check "admin API hidden"         404 "$BASE/_synapse/admin/v1/server_version"
check "federation off"           404 "$BASE/_matrix/federation/v1/version"
check "http redirects to https"  301 "${BASE/https:/http:}/_matrix/client/versions"
exit $fail
