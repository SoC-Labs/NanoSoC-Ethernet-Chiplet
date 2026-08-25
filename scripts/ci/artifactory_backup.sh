#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# artifactory_backup.sh - take a restorable copy of the artifact store OFF the
# host that serves it.
#
#     scripts/ci/artifactory_backup.sh                 take a snapshot
#     scripts/ci/artifactory_backup.sh --dry-run       say what it would take
#     scripts/ci/artifactory_backup.sh --dest DIR      somewhere else
#
# WHY A PULL, NOT A PUSH. This runs on srv03335 and reaches INTO mapstone-dev.
# The backup host holds the credentials and owns the destination; the source
# host cannot reach the backups at all. A push means a compromised, wedged or
# mistakenly-wiped mapstone-dev can take its own backups with it, which is the
# failure the backup exists for.
#
# WHY /research. mapstone-dev has NO /research mount (measured 2026-08-25:
# `ls /research` -> No such file or directory) and its filestore lives on the
# same /home LV as the Artifactory backup it writes -- one volume, one host,
# no copy anywhere else. srv03335 mounts arm.files.soton.ac.uk over NFS with
# 909 GB free, on different hardware, under institutional management. That is
# the whole point: a different disk, a different building, someone else's
# backup regime underneath ours.
#
# THE ORDER OF THE TWO BIG PARTS IS NOT ARBITRARY.
#
#     pg_dump FIRST, then rsync the filestore.
#
# The two cannot be taken atomically. Consider what a race produces each way:
#
#   filestore then DB: a blob uploaded between them lands in the DUMP but not
#                      in the filestore copy. The restore has a row pointing at
#                      bytes that do not exist. That is a CORRUPT restore.
#   DB then filestore: a blob uploaded between them lands in the filestore copy
#                      but not the dump. The restore has bytes nothing points
#                      at. That is a HARMLESS orphan, reclaimed by the next GC.
#
# The remaining hazard in the safe order is a DELETE landing between the two:
# the row is in the dump, the blob already swept from the filestore. On this
# instance that cannot happen inside the window, because the trashcan holds
# deletes for 14 days (`trashcanConfig.retentionPeriodDays 14`, measured) and
# GC runs 4-hourly -- the blob outlives a snapshot that takes minutes.
#
# WHAT MUST BE IN A BACKUP AND IS EASY TO LEAVE OUT: var/etc/security/
# master.key. Artifactory encrypts credentials at rest; a DB dump restored
# WITHOUT the master key that encrypted it yields a running instance that
# cannot decrypt its own stored secrets. The dump alone is not a backup. That
# is also why the destination is mode 700 and the manifest says so.
#
# THE ARTIFACTORY EXPORT IS COPIED TOO, ON PURPOSE. var/backup/artifactory/backup-daily is
# Artifactory's own self-consistent export (measured 195 MB / 3,824 files). It
# is slower to restore and it is a SECOND, FORMAT-INDEPENDENT path: if the
# DB+filestore pair is ever found inconsistent, the export does not depend on
# that pair being consistent. Two mechanisms that fail differently.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
set -euo pipefail

SRC_HOST="${ARTIFACTORY_HOST:-mapstone-dev.ecs.soton.ac.uk}"
SRC_USER="${ARTIFACTORY_SSH_USER:-}"          # empty -> ssh config decides
JFROG_VAR="${JFROG_VAR:-/home/david/jfrog/artifactory/var}"
DB_CONTAINER="${ARTIFACTORY_DB_CONTAINER:-artifactory-db}"
DEST="${ARTIFACTORY_BACKUP_DEST:-/research/dam1n19/artifactory-backup}"
KEEP="${ARTIFACTORY_BACKUP_KEEP:-14}"
DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --dest)    DEST="$2"; shift ;;
        --keep)    KEEP="$2"; shift ;;
        --host)    SRC_HOST="$2"; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "artifactory_backup: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done

SSH_TARGET="${SRC_USER:+$SRC_USER@}$SRC_HOST"
# -o BatchMode: a backup that stops for a password prompt is a backup that does
# not run from cron and is discovered missing on the day it is needed.
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_TARGET")

# podman on that host initialises under the WRONG username over SSH unless USER
# is set explicitly -- $USER carries over from the calling host, the subuid
# lookup fails, and every podman call silently uses a broken single-UID map.
REMOTE_ENV='export USER=david;'

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
snap="$DEST/$stamp"
prev="$(ls -1d "$DEST"/2* 2>/dev/null | sort | tail -1 || true)"

say() { printf 'backup: %-10s %s\n' "$1" "$2"; }

# THE QUOTES INSIDE ${var:+...} ARE LITERAL. Writing
#     ${prev:+--link-dest="$prev/filestore"}
# passes rsync a path that BEGINS WITH A DOUBLE-QUOTE CHARACTER. rsync does not
# error on a link-dest that does not exist -- it silently copies everything
# instead. The first two snapshots taken by this script cost 601 MB each
# because of it, and looked perfectly healthy. Build the option in an ARRAY.
link_filestore=()
link_export=()
if [ -n "$prev" ]; then
    link_filestore=(--link-dest="$prev/filestore")
    link_export=(--link-dest="$prev/export")
fi

say host      "$SSH_TARGET"
say dest      "$snap"
say link-dest "${prev:-<none - this is a full first snapshot>}"

if [ "$DRY" = 1 ]; then
    say mode "DRY RUN - nothing will be written"
fi

# --- 0. establish the source is reachable and the store is up ---------------
# A snapshot of a half-started Artifactory is a snapshot of an inconsistent
# database. Ask the store itself, not the container state: `podman ps` says
# Up while the router is still 90 seconds from serving.
if ! "${SSH[@]}" true 2>/dev/null; then
    echo "backup: FAIL - cannot ssh to $SSH_TARGET (BatchMode; is the key present?)" >&2
    exit 1
fi
health="$(curl -sS -n --max-time 30 \
    "http://$SRC_HOST:8082/artifactory/api/system/ping" 2>/dev/null || true)"
if [ "$health" != "OK" ]; then
    echo "backup: FAIL - the store did not answer ping with OK (got: '${health:0:80}')." >&2
    echo "backup:        Refusing to snapshot a store that is not serving: a dump taken" >&2
    echo "backup:        during startup or recovery can be internally inconsistent." >&2
    exit 1
fi
say ping "OK"

if [ "$DRY" = 1 ]; then
    "${SSH[@]}" "$REMOTE_ENV podman unshare du -sh $JFROG_VAR/data/artifactory/filestore $JFROG_VAR/etc $JFROG_VAR/backup/artifactory/backup-daily 2>/dev/null" \
        | sed 's/^/backup: would    /'
    exit 0
fi

mkdir -p "$snap"
chmod 700 "$DEST" "$snap"

# --- 1. the database, FIRST (see the header) --------------------------------
# -Fc is the custom format: compressed, and pg_restore can list it, which is
# what makes the restore CHECK cheap. A plain .sql.gz can only be verified by
# restoring it.
say step "1/4 pg_dump (custom format)"
mkdir -p "$snap/db"
"${SSH[@]}" "$REMOTE_ENV podman exec $DB_CONTAINER pg_dump -U artifactory -d artifactory -Fc" \
    > "$snap/db/artifactory.dump"
say db "$(du -h "$snap/db/artifactory.dump" | cut -f1)"

# --- 2. var/etc: config, system.yaml, AND the keys --------------------------
# Read from inside the user namespace: var/etc/security is mode 700 owned by
# the container uid, so a plain tar as the login user silently produces an
# archive with the keys MISSING and exits 0. That is the shape of failure this
# whole tree is written against -- a zero that measured nothing.
say step "2/4 var/etc (config + master.key + join.key)"
"${SSH[@]}" "$REMOTE_ENV podman unshare tar -C $JFROG_VAR -czf - etc" > "$snap/etc.tar.gz"
# List ONCE into a variable and match with `case`. The obvious spelling --
#     tar -tzf f | grep -q PATTERN
# -- is WRONG under `set -o pipefail`: grep -q exits at the first match, tar
# takes SIGPIPE, the pipeline reports failure, and the guard fires on a
# PERFECTLY GOOD tarball. It did exactly that on the first real run of this
# script, refusing a backup whose master.key was present all along.
etclist="$(tar -tzf "$snap/etc.tar.gz")"
case "$etclist" in
    *"etc/security/master.key"*) ;;
    *)  echo "backup: FAIL - etc.tar.gz does not contain etc/security/master.key." >&2
        echo "backup:        A dump restored without the key that encrypted it cannot" >&2
        echo "backup:        decrypt its own stored credentials. This is not a backup." >&2
        exit 1 ;;
esac
say etc "$(du -h "$snap/etc.tar.gz" | cut -f1)  master.key present"

# --- 3. the filestore, SECOND -----------------------------------------------
# --link-dest hardlinks anything unchanged since the previous snapshot. The
# filestore is content-addressed (filestore/<2 chars of sha1>/<sha1>), so a
# blob never changes in place: every snapshot after the first costs only the
# NEW blobs. 152 MB today; a daily snapshot costs the day's uploads.
say step "3/4 rsync filestore"
mkdir -p "$snap/filestore"
# -rltD --no-perms, NOT -a. THE PERMISSIONS ARE WHY --link-dest FAILED.
# The blobs are mode 640 on mapstone-dev. /research applies a default ACL that
# forces every file it receives to 770. So rsync asks for 640 every run, the
# filesystem gives 770, and --link-dest compares the existing 770 file against
# the 640 it wants, decides they differ, and COPIES. Silently, forever: two
# snapshots cost 601 MB each and every log line said "done".
#
# Permissions in the backup are meaningless anyway -- a restore writes the
# files back inside the container namespace via `podman unshare`, which sets
# ownership and mode there. The tree as a whole is mode 700, which is the
# protection that matters.
rsync -rltD --no-perms --delete "${link_filestore[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=15" \
    --rsync-path="$REMOTE_ENV podman unshare rsync" \
    "$SSH_TARGET:$JFROG_VAR/data/artifactory/filestore/" "$snap/filestore/"
say filestore "$(find "$snap/filestore" -type f | wc -l) blob(s), $(du -sh --apparent-size "$snap/filestore" | cut -f1) apparent"

# --- 4. Artifactory's own export, as the independent second path ------------
say step "4/4 rsync artifactory export"
mkdir -p "$snap/export"
rsync -rltD --no-perms --delete "${link_export[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=15" \
    --rsync-path="$REMOTE_ENV podman unshare rsync" \
    "$SSH_TARGET:$JFROG_VAR/backup/artifactory/backup-daily/" "$snap/export/" || \
    say warn "export copy failed - the DB+filestore pair is still a complete backup"
say export "$(find "$snap/export" -type f 2>/dev/null | wc -l) file(s)"

# --- did the hardlinking actually happen? ------------------------------------
# rsync reports success either way, so this is the only thing that can tell a
# rotated snapshot from a full second copy. Without it the disk fills at 4x the
# expected rate and every log line still says "done".
if [ -n "$prev" ]; then
    # `find ... | head -1` under `set -o pipefail` KILLS THIS SCRIPT: head exits
    # at the first line, find dies of SIGPIPE, the pipeline reports failure and
    # `set -e` takes it. It did exactly that here -- the script stopped before
    # writing MANIFEST.txt or updating `latest`, and the pipeline's exit code
    # was masked by the `| tail` it was being read through. Third time this
    # trap has bitten in one file; -quit makes find stop on its own terms.
    sample="$(find "$snap/filestore" -type f -print -quit 2>/dev/null)"
    if [ -n "$sample" ]; then
        links="$(stat -c '%h' "$sample" 2>/dev/null || echo 1)"
        if [ "${links:-1}" -ge 2 ]; then
            say linked "yes - sampled blob has $links links, so this snapshot shares storage"
        else
            say WARN "NOT HARDLINKED - a sampled blob has 1 link. This snapshot is a"
            say ""   "full second copy. Check --link-dest against $prev/filestore."
        fi
    fi
fi

# --- MANIFEST ---------------------------------------------------------------
# Digests of every part, so restore_check can tell "this backup is intact" from
# "this backup is present". A file that exists and is truncated looks identical
# to a good one until something reads it.
{
    echo "artifactory backup"
    echo "taken_utc          $stamp"
    echo "source_host        $SRC_HOST"
    echo "source_var         $JFROG_VAR"
    echo "taken_by           $(id -un)@$(hostname -s)"
    echo "order              pg_dump BEFORE filestore (see script header)"
    echo "link_dest          ${prev:-none}"
    echo "artifactory_ver    $(curl -sS -n --max-time 20 "http://$SRC_HOST:8082/artifactory/api/system/version" 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version","UNVERIFIED"))' 2>/dev/null || echo UNVERIFIED)"
    echo "db.sha256          $(sha256sum "$snap/db/artifactory.dump" | cut -d' ' -f1)"
    echo "db.bytes           $(stat -c%s "$snap/db/artifactory.dump")"
    echo "etc.sha256         $(sha256sum "$snap/etc.tar.gz" | cut -d' ' -f1)"
    echo "etc.bytes          $(stat -c%s "$snap/etc.tar.gz")"
    echo "filestore.blobs    $(find "$snap/filestore" -type f | wc -l)"
    echo "filestore.bytes    $(du -sb --apparent-size "$snap/filestore" | cut -f1)"
    echo "export.files       $(find "$snap/export" -type f 2>/dev/null | wc -l)"
    echo "contains_master_key yes"
    echo "mode               700 - this tree contains the key that decrypts the store's secrets"
} > "$snap/MANIFEST.txt"

ln -sfn "$stamp" "$DEST/latest"

# --- rotation ---------------------------------------------------------------
# Hardlinked snapshots share storage, so deleting an old one reclaims only what
# is unique to it.
n=$(ls -1d "$DEST"/2* 2>/dev/null | wc -l)
if [ "$n" -gt "$KEEP" ]; then
    ls -1d "$DEST"/2* | sort | head -n $((n - KEEP)) | while read -r old; do
        say rotate "removing $(basename "$old")"
        rm -rf "$old"
    done
fi

say total "$(du -sh "$snap" | cut -f1) on disk ($(du -sh --apparent-size "$snap" | cut -f1) apparent)"
say done  "$snap"
echo
echo "backup: a snapshot nobody has restored is a hypothesis. Run:"
echo "backup:   scripts/ci/artifactory_restore_check.sh"
