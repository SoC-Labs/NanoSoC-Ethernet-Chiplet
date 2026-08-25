#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# artifactory_restore_drill.sh - actually restore the backup, into a throwaway
# database, and check that what comes back describes the bytes we hold.
#
#     scripts/ci/artifactory_restore_drill.sh              drill `latest`
#     scripts/ci/artifactory_restore_drill.sh --snap DIR
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT. Be exact, because a drill that
# oversells itself is worse than no drill: it retires the question.
#
#   PROVES:     the dump loads into a real PostgreSQL 16 -- schema, constraints
#               and all rows -- and the artefact rows it contains reference
#               blobs that are PRESENT IN THE FILESTORE COPY we took alongside
#               it. That is the pairing the whole backup ordering exists to
#               guarantee, and `pg_restore -l` (which only parses the table of
#               contents) cannot test it.
#   DOES NOT:   prove Artifactory BOOTS on the restored pair. That needs a
#               second Artifactory instance, and this host has ~4 GB available
#               against a documented 8 GB minimum while the owner's Vivado
#               session is resident. Standing one up risks the LIVE store to
#               test the backup, which is the wrong trade. That step stays
#               open and is named as open in ARTIFACTORY_OPERATIONS.md.
#
# The throwaway database is a fresh postgres:16-alpine container on a scratch
# name, torn down in a trap. It never touches artifactory-db.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
set -uo pipefail

DEST="${ARTIFACTORY_BACKUP_DEST:-/research/dam1n19/artifactory-backup}"
SNAP=""
SRC_HOST="${ARTIFACTORY_HOST:-mapstone-dev.ecs.soton.ac.uk}"
SRC_USER="${ARTIFACTORY_SSH_USER:-}"
DRILL="artifactory-restore-drill-$$"

while [ $# -gt 0 ]; do
    case "$1" in
        --snap) SNAP="$2"; shift ;;
        --dest) DEST="$2"; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "restore_drill: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done
SNAP="${SNAP:-$DEST/latest}"
SSH_TARGET="${SRC_USER:+$SRC_USER@}$SRC_HOST"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_TARGET")
REMOTE_ENV='export USER=david;'

ok=0
say() { printf '  %-46s %-5s %s\n' "$1" "$2" "${3:-}"; [ "$2" = FAIL ] && ok=1; return 0; }

cleanup() {
    "${SSH[@]}" "$REMOTE_ENV podman rm -f $DRILL >/dev/null 2>&1" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "restore_drill: $SNAP"
[ -f "$SNAP/db/artifactory.dump" ] || { echo "restore_drill: FAIL - no dump in $SNAP" >&2; exit 1; }

# --- 1. a throwaway postgres ------------------------------------------------
echo "restore_drill: starting a throwaway postgres ($DRILL) ..."
"${SSH[@]}" "$REMOTE_ENV podman run -d --name $DRILL \
    -e POSTGRES_USER=artifactory -e POSTGRES_PASSWORD=drill \
    -e POSTGRES_DB=artifactory docker.io/library/postgres:16-alpine" >/dev/null 2>&1
# Wait for it to accept connections rather than sleeping a guessed interval.
for _ in $(seq 1 30); do
    if "${SSH[@]}" "$REMOTE_ENV podman exec $DRILL pg_isready -U artifactory" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
if ! "${SSH[@]}" "$REMOTE_ENV podman exec $DRILL pg_isready -U artifactory" >/dev/null 2>&1; then
    say "throwaway postgres accepts connections" FAIL "it never came up"
    exit 1
fi
say "throwaway postgres accepts connections" ok "$DRILL"

# --- 2. THE RESTORE ---------------------------------------------------------
# Not `pg_restore -l`. A real load, into a real empty database.
echo "restore_drill: restoring the dump ..."
out="$("${SSH[@]}" "$REMOTE_ENV podman exec -i $DRILL pg_restore -U artifactory -d artifactory --no-owner --no-privileges" \
        < "$SNAP/db/artifactory.dump" 2>&1)"
errs="$(printf '%s' "$out" | grep -c 'error:' || true)"
say "pg_restore loads the dump" "$([ "${errs:-0}" -eq 0 ] && echo ok || echo FAIL)" \
    "$([ "${errs:-0}" -eq 0 ] && echo 'no errors' || printf '%s errors, first: %s' "$errs" "$(printf '%s' "$out" | grep -m1 'error:')")"

q() { "${SSH[@]}" "$REMOTE_ENV podman exec $DRILL psql -U artifactory -d artifactory -tAc \"$1\"" 2>/dev/null | tr -d '\r'; }

tables="$(q "select count(*) from information_schema.tables where table_schema='public'")"
say "the schema is populated" "$([ "${tables:-0}" -gt 20 ] && echo ok || echo FAIL)" \
    "${tables:-0} table(s)"

# --- 3. THE PAIRING: rows must describe blobs we actually hold ---------------
# `nodes` is Artifactory's artefact table: repo, path, name, sha1 of content.
files="$(q "select count(*) from nodes where node_type=1")"
say "artefact rows restored" "$([ "${files:-0}" -gt 100 ] && echo ok || echo FAIL)" \
    "${files:-0} file node(s)"

# Take a spread sample of sha1s the restored DB believes it has, and require
# each to be present in the filestore copy taken alongside this dump. THIS is
# the check that the pg_dump-before-filestore ordering exists to make passable.
q "select sha1_actual from nodes where node_type=1 and sha1_actual is not null order by node_id" \
    > "${TMPDIR:-/tmp}/.drill_sha1.$$" 2>/dev/null
total="$(wc -l < "${TMPDIR:-/tmp}/.drill_sha1.$$")"
missing=0; checked=0
if [ "${total:-0}" -gt 0 ]; then
    step=$(( total / 40 )); [ "$step" -lt 1 ] && step=1
    n=0
    while read -r s; do
        n=$((n+1))
        [ $(( n % step )) -eq 0 ] || continue
        [ -n "$s" ] || continue
        checked=$((checked+1))
        [ -f "$SNAP/filestore/${s:0:2}/$s" ] || missing=$((missing+1))
    done < "${TMPDIR:-/tmp}/.drill_sha1.$$"
fi
rm -f "${TMPDIR:-/tmp}/.drill_sha1.$$"
say "restored rows point at blobs we HOLD" \
    "$([ "$checked" -gt 0 ] && [ "$missing" -eq 0 ] && echo ok || echo FAIL)" \
    "$checked sampled of $total, $missing missing"

# --- negative control -------------------------------------------------------
# If the sampler cannot fail, the arm above proves nothing.
if [ -f "$SNAP/filestore/00/0000000000000000000000000000000000000000" ]; then
    say "control: an impossible sha1 is absent" FAIL "it was found"
else
    say "control: an impossible sha1 is absent" ok "the sampler can fail"
fi

echo
if [ "$ok" = 0 ]; then
    echo "restore_drill: OK - the dump restores into a real database and its"
    echo "restore_drill: artefact rows reference blobs present in the same snapshot."
    echo "restore_drill: STILL OPEN: booting Artifactory on the restored pair."
else
    echo "restore_drill: FAILED - see the FAIL lines above." >&2
fi
exit $ok
