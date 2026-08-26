#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# ant_manifest.py --- write ant_manifest.txt for a Calibre antenna run.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
# ---------------------------------------------------------------------------
# WHY A MANIFEST AND NOT A GREP OF THE LOG
#
# The evidence gate for this row has to answer four questions that a Calibre
# summary cannot: which LAYOUT was checked (by content, not by path -- four
# green verdicts on this project have been read off the wrong stream), which
# DECK produced it, what the result CAP was (a count at the cap is a floor and
# Calibre writes the truncated value into both count fields), and whether the
# run REACHED THE END. Reading those out of a 4 MB tool log with regexes is
# how a gate ends up agreeing with whatever it happens to match.
#
# So the runner states them, once, in a file it writes LAST -- which also
# makes "the manifest is absent" mean exactly "the run did not finish".
#
# Separated from run_ant.sh so it can be re-run over a completed rundir
# without spending another Calibre licence-hour.
#
#   ant_manifest.py --rundir DIR --deck DECK --layout GDS --top CELL \
#                   --foundry-deck FILE --cpus N --started EPOCH [--rc N]
# ---------------------------------------------------------------------------

import argparse
import hashlib
import os
import re
import sys
import time


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def deck_value(deck, stmt):
    """First `<stmt> "value"` in the deck. The deck is the authority on where
    Calibre was told to write, not the runner's idea of it."""
    pat = re.compile(r'^\s*%s\s+"([^"]*)"' % stmt)
    for line in open(deck, errors="replace"):
        m = pat.match(line)
        if m:
            return m.group(1)
    return ""


def switch_state(foundry_deck, deck):
    """-> "NAME=on, NAME=off, ..." for every switch the FOUNDRY deck tests.

    Reported by name only. A switch name appears in every violation report and
    in public literature; the values behind it do not appear here at all."""
    tested = []
    for line in open(foundry_deck, errors="replace"):
        m = re.match(r'^#IFN?DEF\s+([A-Za-z0-9_]+)', line)
        if m and m.group(1) not in tested:
            tested.append(m.group(1))
    defined = set()
    for line in open(deck, errors="replace"):
        m = re.match(r'^#DEFINE\s+([A-Za-z0-9_]+)', line)
        if m:
            defined.add(m.group(1))
    if not tested:
        return "the foundry deck tests no switches"
    return ", ".join("%s=%s" % (n, "on" if n in defined else "off")
                     for n in sorted(tested))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rundir", required=True)
    ap.add_argument("--deck", required=True)
    ap.add_argument("--layout", required=True)
    ap.add_argument("--top", required=True)
    ap.add_argument("--foundry-deck", required=True)
    ap.add_argument("--cpus", default="")
    ap.add_argument("--started", type=int, default=0)
    ap.add_argument("--rc", default="")
    ap.add_argument("--control", default="")
    a = ap.parse_args()

    log = os.path.join(a.rundir, "calibre_ant.log")
    ltxt = open(log, errors="replace").read() if os.path.isfile(log) else ""

    summary = deck_value(a.deck, "DRC SUMMARY REPORT")
    results = deck_value(a.deck, "DRC RESULTS DATABASE")
    spath = summary if os.path.isabs(summary) else os.path.join(a.rundir, summary)

    # THE CAP IS READ OUT OF THE DECK THAT RAN, not out of the generator that
    # wrote it. A `DRC MAXIMUM RESULTS` appended later, or one inherited from
    # the foundry body, is the one in force.
    cap = ""
    for line in open(a.deck, errors="replace"):
        m = re.match(r'^\s*DRC MAXIMUM RESULTS\s+(\d+|ALL)\s*$', line)
        if m:
            cap = m.group(1)
    if cap == "ALL":
        cap = "0"          # 0 means "no cap" to the gate

    # `ant_finished` is what the whole manifest hinges on, so it is not the
    # tool's exit status -- Calibre exits 0 on a clean RUN and this project has
    # already been bitten by tools that exit 0 after a failed script. It is the
    # summary existing AND the log carrying Calibre's own end-of-execution line.
    executed = re.search(r'TOTAL RULECHECKS EXECUTED\s*=\s*(\d+)', ltxt)
    m = re.search(r'CALIBRE::DRC-H COMPLETED\s*-\s*(.+?)\s*$', ltxt, re.M)
    completed = ""
    if m:
        try:
            completed = time.strftime(
                "%FT%T", time.strptime(m.group(1), "%a %b %d %H:%M:%S %Y"))
        except ValueError:
            completed = ""
    m = re.search(r'TOTAL CPU TIME\s*=\s*\d+\s+REAL TIME\s*=\s*(\d+)', ltxt)
    real_time = m.group(1) if m else ""
    finished = bool(executed) and os.path.isfile(spath) and os.path.getsize(spath) > 0

    out = [
        ("layout", os.path.abspath(a.layout)),
        ("layout_md5", md5(a.layout)),
        ("layout_bytes", os.path.getsize(a.layout)),
        ("top_cell", a.top),
        ("deck", os.path.abspath(a.deck)),
        ("deck_md5", md5(a.deck)),
        ("foundry_deck", os.path.abspath(a.foundry_deck)),
        ("foundry_deck_name", os.path.basename(a.foundry_deck)),
        ("foundry_deck_md5", md5(a.foundry_deck)),
        # DERIVED, NOT SPELLED. This used to be the literal string
        # "28K_AP off, DTM off (foundry defaults, both verified)" -- a second
        # copy of a fact the deck already states, and one that would have kept
        # saying "off" the day somebody turned a switch on. The switch NAMES
        # come from the foundry deck (every name it tests with #IFDEF/#IFNDEF)
        # and their state from the deck that actually ran.
        ("deck_switches", switch_state(a.foundry_deck, a.deck)),
        ("coverage_control", a.control or "none"),
        ("summary", summary),
        ("results_db", results),
        ("max_results", cap),
        ("rulechecks_executed", executed.group(1) if executed else ""),
        ("cpus", a.cpus),
        ("calibre_exit_status", a.rc),
        # FROM THE TOOL'S OWN LOG, NOT FROM THIS SCRIPT'S CLOCK. This file can
        # be regenerated over a finished rundir without spending another
        # licence-hour, and the first version of it stamped the REGENERATION
        # time as `ant_finished` and computed a wall clock from it -- so a
        # rebuild of the manifest silently turned a 24-minute run into a
        # 50-minute one. Calibre records both facts itself; use those.
        ("ant_started", time.strftime("%FT%T", time.localtime(a.started))
         if a.started else ""),
        ("ant_finished", completed or (time.strftime("%FT%T") if finished else "")),
        ("ant_wall_clock_s", real_time or
         (int(time.time()) - a.started if a.started else "")),
    ]
    with open(os.path.join(a.rundir, "ant_manifest.txt"), "w") as fh:
        for k, v in out:
            fh.write("%-22s= %s\n" % (k, v))
    print("wrote %s/ant_manifest.txt (ant_finished=%s)"
          % (a.rundir, "yes" if finished else "NO"))
    return 0 if finished else 1


if __name__ == "__main__":
    sys.exit(main())
