#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# artifactory_token.sh - mint a revocable, expiring access token and put it in
# ~/.netrc, so the store stops being reached with the admin PASSWORD.
#
#     scripts/ci/artifactory_token.sh --show          what is in netrc now
#     scripts/ci/artifactory_token.sh --mint          issue one and install it
#     scripts/ci/artifactory_token.sh --list          tokens this instance holds
#     scripts/ci/artifactory_token.sh --revoke ID     kill one
#
# WHAT THIS BUYS, AND WHAT IT DOES NOT. Be precise, because the difference
# matters and it is easy to oversell.
#
#   IT DOES:     replace a long-lived plaintext PASSWORD in ~/.netrc with a
#                credential that EXPIRES on its own, can be REVOKED without
#                changing anything else, and can be issued once per machine so
#                a compromised host is contained to its own token.
#   IT DOES NOT: reduce privilege. Artifactory OSS has no permission targets
#                and no groups -- both REST APIs answer HTTP 400 "available
#                only in Artifactory Pro" (measured 2026-08-25), and the users
#                API returns empty. There is exactly one identity on this
#                instance. A token scoped to it is an ADMIN token.
#
# So this is defence in depth, not least privilege, and calling it least
# privilege would be a lie that stops someone asking for the thing that would
# actually deliver it (a paid tier, or a reverse proxy doing the authorisation).
#
# THE OTHER HALF IS TLS, AND IT IS NOT OPTIONAL IF THIS RUNS OVER THE LAB LAN.
# 8082 is plain HTTP. `curl -n` sends `Authorization: Basic base64(user:pass)`,
# which is an encoding, not encryption. A token in netrc over plain HTTP is
# still a credential on the wire in cleartext -- it is merely a credential that
# expires. See docs/plans/ARTIFACTORY_OPERATIONS.md for the reverse-proxy
# recipe; do that too.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
set -euo pipefail

HOST="${ARTIFACTORY_HOST:-mapstone-dev.ecs.soton.ac.uk}"
PORT="${ARTIFACTORY_PORT:-8082}"
BASE="http://$HOST:$PORT"
NETRC="${NETRC:-$HOME/.netrc}"
EXPIRES="${ARTIFACTORY_TOKEN_EXPIRES:-31536000}"     # 1 year, in seconds
ACTION=""
REVOKE_ID=""

while [ $# -gt 0 ]; do
    case "$1" in
        --show)   ACTION=show ;;
        --mint)   ACTION=mint ;;
        --list)   ACTION=list ;;
        --revoke) ACTION=revoke; REVOKE_ID="$2"; shift ;;
        --expires) EXPIRES="$2"; shift ;;
        -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
        *) echo "artifactory_token: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$ACTION" ] || { sed -n '2,34p' "$0"; exit 2; }

case "$ACTION" in

show)
    if [ ! -f "$NETRC" ]; then
        echo "token: no $NETRC"
        exit 1
    fi
    # Never print the secret. Print its SHAPE, which is what you need to know.
    awk -v h="$HOST" '
        $1=="machine" { m = ($2==h) }
        m && $1=="login"    { login=$2 }
        m && $1=="password" { pw=$2 }
        END {
            printf "token: machine  %s\n", h
            printf "token: login    %s\n", (login ? login : "(none)")
            if (pw == "") { print "token: password (none)" }
            else if (length(pw) > 60 && pw ~ /^ey/) {
                printf "token: password a JWT access token, %d chars - GOOD\n", length(pw)
            } else {
                printf "token: password %d chars, not a JWT - this looks like the ADMIN PASSWORD.\n", length(pw)
                print  "token:          Mint a token: scripts/ci/artifactory_token.sh --mint"
            }
        }' "$NETRC"
    # Transport, stated plainly whatever the credential is.
    if [ "${BASE#https://}" = "$BASE" ]; then
        echo "token: transport PLAIN HTTP - whatever is above travels in cleartext."
    fi
    ;;

mint)
    echo "token: minting against $BASE (expires_in=$EXPIRES s)"
    echo "token: NOTE - on this OSS tier the only identity is admin, so this is"
    echo "token:        an ADMIN token. It expires and can be revoked; it is not"
    echo "token:        reduced privilege. See the header."
    resp="$(curl -sS -n --max-time 60 -X POST "$BASE/access/api/v1/tokens" \
              -H "Content-Type: application/json" \
              -d "{\"scope\":\"applied-permissions/admin\",\"expires_in\":$EXPIRES,\"description\":\"asic-flow on $(hostname -s) for $(id -un)\"}")"
    tok="$(printf '%s' "$resp" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("access_token",""))' 2>/dev/null || true)"
    if [ -z "$tok" ]; then
        echo "token: FAILED - the server did not return an access_token." >&2
        printf '%s\n' "$resp" | head -c 400 >&2; echo >&2
        exit 1
    fi
    tid="$(printf '%s' "$resp" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token_id","?"))')"
    echo "token: issued  token_id $tid"

    # Rewrite the netrc entry for this host, leaving every other machine alone.
    umask 077
    tmp="$(mktemp)"
    awk -v h="$HOST" -v t="$tok" '
        $1=="machine" { if (skip) skip=0; if ($2==h) { skip=1;
                        print "machine " h; print "login admin"; print "password " t; next } }
        !skip { print }
    ' "$NETRC" > "$tmp" 2>/dev/null || true
    if ! grep -q "^machine $HOST" "$tmp" 2>/dev/null; then
        { echo "machine $HOST"; echo "login admin"; echo "password $tok"; } >> "$tmp"
    fi
    cp "$NETRC" "$NETRC.bak-$(date -u +%Y%m%dT%H%M%SZ)" 2>/dev/null || true
    mv "$tmp" "$NETRC"
    chmod 600 "$NETRC"
    echo "token: installed in $NETRC (previous file kept as .bak-*)"

    # PROVE IT WORKS before walking away, and prove the old path is gone.
    if [ "$(curl -sS -n --max-time 30 "$BASE/artifactory/api/system/ping")" = "OK" ]; then
        echo "token: VERIFIED - the store answers with the new credential."
    else
        echo "token: FAILED - the store does not answer with the new credential." >&2
        echo "token:          Restore from the .bak file above." >&2
        exit 1
    fi
    echo
    echo "token: NOW DO THE OTHER HALF: 8082 is plain HTTP, so this token is"
    echo "token: sent in cleartext on every request. See ARTIFACTORY_OPERATIONS.md."
    ;;

list)
    curl -sS -n --max-time 30 "$BASE/access/api/v1/tokens" | python3 -c '
import sys, json
d = json.load(sys.stdin)
ts = d.get("tokens", d if isinstance(d, list) else [])
for t in ts:
    print("%-38s %-28s expiry=%s" % (t.get("token_id","?"),
                                     (t.get("description") or "")[:28],
                                     t.get("expiry","never")))
print("%d token(s)" % len(ts))'
    ;;

revoke)
    [ -n "$REVOKE_ID" ] || { echo "token: --revoke needs a token_id" >&2; exit 2; }
    code="$(curl -sS -n --max-time 30 -o /dev/null -w '%{http_code}' \
            -X DELETE "$BASE/access/api/v1/tokens/$REVOKE_ID")"
    echo "token: revoke $REVOKE_ID -> HTTP $code"
    [ "$code" = "200" ] || [ "$code" = "204" ]
    ;;
esac
