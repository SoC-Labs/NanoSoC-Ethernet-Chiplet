#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_live_guard.sh — refuse to disturb a directory another flow is standing in.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# THE HAZARD THIS CLOSES, MEASURED
#
# scripts/ci/new_run.sh section 3 does, unconditionally:
#
#     for d in work logs reports outputs; do
#         [ -d "$d" ] && mv "$d" "$RUN/prev_$d"
#     done
#
# on the SHARED ASIC/genus-innovus tree. On 2026-08-13 another session's Innovus
# had its working directory inside ASIC/genus-innovus/work while a full flow was
# running. Renaming a directory out from under a live process does not fail and
# does not warn: the process keeps its now-detached inode, writes its databases
# into a path nobody will look in, and the ONE thing that would have told anyone
# — the log — moves with it. Several sessions edit this tree all day, so "nobody
# else is running anything" is never a safe assumption, and it is not one a
# script should make silently.
#
# So: before rotating anything, ask whether a process is standing in it.
#
# HOW IT LOOKS
#   1. /proc/*/cwd            — a process whose working directory is in the tree
#   2. /proc/*/fd/*           — a process holding a file open under the tree
#   3. $ASIC/.run_live        — an advisory stamp another run left behind
#
# (`fuser` was tried and removed; see the comment above occupants() for why.)
#
# LIMITATION, STATED RATHER THAN HIDDEN: /proc entries for OTHER UNIX USERS are
# not readable, so a run started by a different account is invisible to 1 and 2.
# Every session on this project runs as the same user, so this covers the case
# that actually occurs — but it is a detector, not a proof, and "clear" here
# means "nothing detected", never "nothing running". That is why the advisory
# stamp exists as well: it survives across users and across reboots of the
# checking process.
#
# USAGE
#   run_live_guard.sh check   <dir> [dir...]      0 = clear, 3 = busy
#   run_live_guard.sh claim   <asic-dir> <label>  write the advisory stamp
#   run_live_guard.sh release <asic-dir>          remove our stamp
#
# Never gates on an exit code from an EDA tool; it reads the filesystem.
#-----------------------------------------------------------------------------
set -uo pipefail

STAMP_NAME=".run_live"

die()  { echo "run_live_guard: $*" >&2; exit 2; }
note() { echo "run_live_guard: $*" >&2; }

# --- who is standing in these directories ------------------------------------
# Implemented in python3 because the bash form was unusable: readlink-ing every
# descriptor of every process is tens of thousands of forks and took over two
# minutes on this host. A guard that slow gets commented out.
#
# `fuser` WAS used here and has been removed on measurement. `fuser -m <dir>`
# asks about the mounted FILESYSTEM, not the directory, so on a shared home it
# reports every directory as busy and the guard fires constantly -- which is the
# fastest possible route to someone deleting the guard. Plain `fuser <dir>` only
# reports processes with the directory itself open, missing the case that
# actually happened (a tool with its CWD in a SUBdirectory). Neither form is
# right, so neither is used.
occupants() {
    python3 - "$@" <<'PYEOF'
import os, sys

targets = []
for d in sys.argv[1:]:
    try:
        targets.append(os.path.realpath(d))
    except OSError:
        pass
if not targets:
    sys.exit(1)

def under(link):
    for t in targets:
        if link == t or link.startswith(t + os.sep):
            return t
    return None

def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")[:120]
    except OSError:
        return "?"

hits, me = [], str(os.getpid())
pids = [p for p in os.listdir("/proc") if p.isdigit()]

# Pass 1: working directories. This is the case that was measured -- another
# session's Innovus with its CWD inside work/ while a rotation was about to
# rename work/ out from under it.
cwd_suspects = set()
for pid in pids:
    if pid == me:
        continue
    try:
        link = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        continue                      # another user, or the process just exited
    t = under(link)
    if t:
        hits.append((pid, "cwd", link))
    cwd_suspects.add((pid, link))

# Pass 2: open descriptors. Scanning every fd of every process is what made the
# bash version unusable, so this looks only at processes that are plausibly a
# flow: named like a tool, or already sitting somewhere in the same tree.
TOOLS = ("genus", "innovus", "calibre", "lec", "make", "tclsh", "python",
         "cdnWrapper", "fm_shell", "dc_shell", "icv", "klayout")
roots = set(os.path.dirname(t) for t in targets)
for pid, link in cwd_suspects:
    try:
        comm = open(f"/proc/{pid}/comm").read().strip()
    except OSError:
        continue
    interesting = any(t in comm for t in TOOLS) or \
        any(link == r or link.startswith(r + os.sep) for r in roots)
    if not interesting:
        continue
    try:
        fds = os.listdir(f"/proc/{pid}/fd")
    except OSError:
        continue
    for fd in fds[:4096]:
        try:
            tgt = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if under(tgt):
            hits.append((pid, "open", tgt))
            break

for pid, kind, path in hits:
    sys.stderr.write(f"  BUSY  pid {pid:<8} {kind:<4} {path}\n")
    sys.stderr.write(f"        cmd  {cmdline(pid)}\n")
# Exit 3 = busy, 0 = nothing detected. Deliberately NOT the shell habit of
# 0-means-true: an inverted sense here turns the guard into its own opposite,
# and it did exactly that in the first draft -- a busy tree read as clear.
sys.exit(3 if hits else 0)
PYEOF
}

cmd_check() {
    [ $# -ge 1 ] || die "check needs at least one directory"
    local asic stamp rc=0
    occupants "$@" || rc=3

    # 4: the advisory stamp, checked for every directory's ASIC root.
    for d in "$@"; do
        asic=$(readlink -f "$d/.." 2>/dev/null)
        stamp="$asic/$STAMP_NAME"
        [ -f "$stamp" ] || continue
        # shellcheck disable=SC1090
        local spid slabel sdir
        spid=$(sed -n 's/^pid *//p'   "$stamp" | head -1)
        slabel=$(sed -n 's/^label *//p' "$stamp" | head -1)
        sdir=$(sed -n 's/^run *//p'   "$stamp" | head -1)
        if [ -n "${spid:-}" ] && kill -0 "$spid" 2>/dev/null; then
            note "advisory stamp $stamp names LIVE pid $spid (label '${slabel:-?}', run ${sdir:-?})"
            rc=3
        else
            note "advisory stamp $stamp is STALE (pid ${spid:-?} is gone). Remove it with 'release' once you have confirmed nothing is running."
        fi
    done

    if [ "$rc" = "3" ]; then
        cat >&2 <<'EOF'
run_live_guard: REFUSING — something is standing in the directories that were
about to be rotated. Rotating them would detach a live tool from its own work
directory silently. Wait for it, or point this run somewhere else.
EOF
        return 3
    fi
    echo "run_live_guard: nothing detected in: $*  (a detector, not a proof — see the header)"
    return 0
}

cmd_claim() {
    [ $# -ge 2 ] || die "claim needs <asic-dir> <label>"
    local asic="$1" label="$2" stamp
    stamp="$(readlink -f "$asic")/$STAMP_NAME"
    if [ -f "$stamp" ]; then
        local spid
        spid=$(sed -n 's/^pid *//p' "$stamp" | head -1)
        if [ -n "${spid:-}" ] && kill -0 "$spid" 2>/dev/null; then
            note "already claimed by live pid $spid — refusing"
            return 3
        fi
        note "overwriting a stale stamp (pid ${spid:-?} is gone)"
    fi
    # The pid recorded must be the CALLER's, not this script's: the guard exits
    # immediately, so a stamp naming $$ is stale the instant it is written and
    # every later check reads it as "the run that made this is gone".
    local claim_pid="${GUARD_PID:-$PPID}"
    {
        echo "pid   $claim_pid"
        echo "label $label"
        echo "run   ${RUN:-unset}"
        echo "user  ${USER:-unknown}"
        echo "host  $(hostname -s)"
        echo "utc   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$stamp"
    echo "run_live_guard: claimed $stamp"
}

cmd_release() {
    [ $# -ge 1 ] || die "release needs <asic-dir>"
    local stamp
    stamp="$(readlink -f "$1")/$STAMP_NAME"
    [ -f "$stamp" ] || { echo "run_live_guard: no stamp at $stamp"; return 0; }
    local spid
    spid=$(sed -n 's/^pid *//p' "$stamp" | head -1)
    if [ -n "${spid:-}" ] && [ "$spid" != "${GUARD_PID:-$PPID}" ] && \
       kill -0 "$spid" 2>/dev/null; then
        note "stamp belongs to LIVE pid $spid, not to us ($$) — refusing to remove"
        return 3
    fi
    rm -f "$stamp" && echo "run_live_guard: released $stamp"
}

case "${1:-}" in
    check)   shift; cmd_check   "$@" ;;
    claim)   shift; cmd_claim   "$@" ;;
    release) shift; cmd_release "$@" ;;
    *) die "usage: $0 {check <dir>...|claim <asic-dir> <label>|release <asic-dir>}" ;;
esac
