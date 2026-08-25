#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# artifactory_restore_check.sh - prove a backup snapshot is restorable, without
# restoring it over anything.
#
#     scripts/ci/artifactory_restore_check.sh                  check `latest`
#     scripts/ci/artifactory_restore_check.sh --snap DIR       check one
#     scripts/ci/artifactory_restore_check.sh --sample 25      hash more blobs
#
# A BACKUP NOBODY HAS READ IS A HYPOTHESIS. Every check here answers a
# different way of being wrong, and the interesting one is the last:
#
#   1. INTACT      every part's sha256 still matches what the manifest recorded
#                  when it was taken. Catches truncation, NFS write errors and
#                  bit rot. A truncated dump is byte-for-byte indistinguishable
#                  from a good one until something tries to read it.
#   2. LOADABLE    `pg_restore -l` parses the dump and lists its objects. Run
#                  INSIDE the source's postgres:16 container, because the only
#                  pg_restore on srv03335 is Calibre's bundled 11.4 and it
#                  cannot read a version-16 custom dump. A check that runs with
#                  the wrong tool and fails proves nothing about the backup.
#   3. KEYED       etc.tar.gz lists cleanly AND contains etc/security/master.key.
#                  Without that key a restored instance cannot decrypt its own
#                  stored credentials.
#   4. REAL BYTES  the end-to-end one. Sample artefacts from the LIVE store by
#                  AQL, take the sha1 Artifactory recorded for each, and look
#                  for filestore/<sha1[0:2]>/<sha1> in the BACKUP -- then hash
#                  the file found there and require it to equal its own name.
#                  This is the only check that proves the backup holds the
#                  actual bytes of actual artefacts rather than a plausible
#                  directory tree.
#
# AND A NEGATIVE CONTROL. A sha1 that cannot be in the store must NOT be found.
# Without it, a check that hardcodes "present" passes on an empty backup.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
set -uo pipefail

DEST="${ARTIFACTORY_BACKUP_DEST:-/research/dam1n19/artifactory-backup}"
SNAP=""
SAMPLE=10
SRC_HOST="${ARTIFACTORY_HOST:-mapstone-dev.ecs.soton.ac.uk}"
SRC_USER="${ARTIFACTORY_SSH_USER:-}"
DB_CONTAINER="${ARTIFACTORY_DB_CONTAINER:-artifactory-db}"

while [ $# -gt 0 ]; do
    case "$1" in
        --snap)   SNAP="$2"; shift ;;
        --dest)   DEST="$2"; shift ;;
        --sample) SAMPLE="$2"; shift ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "restore_check: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done

SNAP="${SNAP:-$DEST/latest}"
SSH_TARGET="${SRC_USER:+$SRC_USER@}$SRC_HOST"
BASE="http://$SRC_HOST:8082/artifactory"

ok=0
say() { printf '  %-34s %-5s %s\n' "$1" "$2" "${3:-}"; [ "$2" = FAIL ] && ok=1; return 0; }

echo "restore_check: $SNAP"
if [ ! -d "$SNAP" ]; then
    echo "restore_check: FAIL - no such snapshot. Has artifactory_backup.sh ever run?" >&2
    exit 1
fi
[ -f "$SNAP/MANIFEST.txt" ] || { echo "restore_check: FAIL - no MANIFEST.txt" >&2; exit 1; }
sed 's/^/  | /' "$SNAP/MANIFEST.txt"
echo

man() { awk -v k="$1" '$1==k{print $2}' "$SNAP/MANIFEST.txt"; }

# --- 1. INTACT --------------------------------------------------------------
for part in "db/artifactory.dump:db.sha256" "etc.tar.gz:etc.sha256"; do
    f="${part%%:*}"; k="${part##*:}"
    want="$(man "$k")"
    if [ ! -f "$SNAP/$f" ]; then
        say "intact: $f" FAIL "absent"
        continue
    fi
    got="$(sha256sum "$SNAP/$f" | cut -d' ' -f1)"
    if [ "$got" = "$want" ]; then
        say "intact: $f" ok "$(du -h "$SNAP/$f" | cut -f1)"
    else
        say "intact: $f" FAIL "sha256 $got != recorded $want"
    fi
done

# --- 2. LOADABLE ------------------------------------------------------------
# Streamed into the source's own postgres:16. Nothing is written: -l LISTS.
if [ -f "$SNAP/db/artifactory.dump" ]; then
    n=$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_TARGET" \
          "export USER=david; podman exec -i $DB_CONTAINER pg_restore -l" \
          < "$SNAP/db/artifactory.dump" 2>/dev/null | grep -c '^[0-9]' || true)
    if [ "${n:-0}" -gt 50 ]; then
        say "loadable: pg_restore -l" ok "$n object(s) in the dump"
    else
        say "loadable: pg_restore -l" FAIL "listed ${n:-0} objects - a real Artifactory schema has hundreds"
    fi
fi

# --- 3. KEYED ---------------------------------------------------------------
if [ -f "$SNAP/etc.tar.gz" ]; then
    # ONE listing, matched with `case`. `tar -tzf | grep -q` reports failure on
    # a good archive whenever pipefail is set, because grep -q exits early and
    # tar dies of SIGPIPE. That false failure is not hypothetical: it fired on
    # the first real run of artifactory_backup.sh.
    if etclist="$(tar -tzf "$SNAP/etc.tar.gz" 2>/dev/null)"; then
        case "$etclist" in
            *"etc/security/master.key"*) say "keyed: master.key in etc.tar.gz" ok ;;
            *) say "keyed: master.key in etc.tar.gz" FAIL \
                   "the dump cannot be decrypted without it" ;;
        esac
        case "$etclist" in
            *"etc/system.yaml"*) say "keyed: system.yaml present" ok ;;
            *) say "keyed: system.yaml present" FAIL "service gating would be lost" ;;
        esac
    else
        say "keyed: etc.tar.gz readable" FAIL "tar cannot list it"
    fi
fi

# --- 4. REAL BYTES ----------------------------------------------------------
# The live store names the bytes; the backup must contain them.
aql=$(curl -sS -n --max-time 60 -X POST -H "Content-Type: text/plain" \
      -d 'items.find({"$or":[{"repo":"asic-candidate"},{"repo":"asic-record"}]}).include("repo","path","name","actual_sha1")' \
      "$BASE/api/search/aql" 2>/dev/null)
if [ -z "$aql" ] || printf '%s' "$aql" | grep -q '"errors"'; then
    say "real bytes: query the live store" FAIL \
        "NOT-MEASURED - the store did not answer; this check did not run"
else
    printf '%s' "$aql" > "${TMPDIR:-/tmp}/.rc_aql.$$"
    read -r found missing checked < <(python3 - "$SNAP" "$SAMPLE" "${TMPDIR:-/tmp}/.rc_aql.$$" <<'PY'
import hashlib, json, os, sys
snap, n, aqlf = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = [r for r in json.load(open(aqlf)).get("results", []) if r.get("actual_sha1")]
# Deterministic sample, spread across the listing rather than the first N -
# the first N are one directory and would pass on a partial copy of it.
step = max(1, len(rows) // n) if rows else 1
pick = rows[::step][:n]
found = missing = 0
for r in pick:
    s = r["actual_sha1"]
    p = os.path.join(snap, "filestore", s[:2], s)
    if not os.path.isfile(p):
        missing += 1
        continue
    h = hashlib.sha1()
    with open(p, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    found += 1 if h.hexdigest() == s else 0
    missing += 0 if h.hexdigest() == s else 1
print(found, missing, len(pick))
PY
    )
    rm -f "${TMPDIR:-/tmp}/.rc_aql.$$"
    if [ "${checked:-0}" -gt 0 ] && [ "${missing:-1}" -eq 0 ]; then
        say "real bytes: $checked sampled artefact(s)" ok "every sha1 present AND re-hashed correct"
    else
        say "real bytes: ${checked:-0} sampled artefact(s)" FAIL \
            "${found:-0} good, ${missing:-?} missing or mis-hashed"
    fi
fi

# --- negative control -------------------------------------------------------
# Without this, every check above passes on an empty tree by finding nothing.
ctl="0000000000000000000000000000000000000000"
if [ -f "$SNAP/filestore/${ctl:0:2}/$ctl" ]; then
    say "control: an impossible sha1 is absent" FAIL "it was FOUND - this check is not discriminating"
else
    say "control: an impossible sha1 is absent" ok "a search that always hits is not a search"
fi

echo
if [ "$ok" = 0 ]; then
    echo "restore_check: OK - this snapshot is intact, loadable, keyed, and holds real bytes."
else
    echo "restore_check: FAILED - see the lines marked FAIL above." >&2
fi
exit $ok
