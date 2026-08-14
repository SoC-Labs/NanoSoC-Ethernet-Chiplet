#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_lvs.sh -- portable Calibre nmLVS (layout-vs-schematic) runner.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Every input arrives as an environment variable (CONTRACT.md S1). This file
# contains no site paths, no PDK names and no project names, so it drops into
# any project on any PDK unchanged: the project supplies paths, the flow
# supplies logic.
#
#   run_lvs.sh                  full run: source prep -> Calibre -> verdict
#   run_lvs.sh --check          preflight only. Takes NO licence, launches
#                               NO tool. Reports exactly what is missing.
#   run_lvs.sh --source-only    steps 1-5 (netlist + deck + box list), stop
#                               before Calibre. Also NO licence.
#   run_lvs.sh --pg-check       re-run step 6b's power/ground-text guard over
#                               an EXISTING run directory and nothing else.
#                               Reads files only -- no licence, no tool, and
#                               no input needed beyond LVS_RUNDIR.
#   run_lvs.sh --help
#
# EXIT CODES. The verdict comes from the LVS *report*, never from Calibre's
# exit status -- Calibre exits 0 for "the run completed", not "the netlists
# matched", and exits 0 on some aborts too.
#   0  CORRECT              (or --check / --source-only completed cleanly)
#   1  INCORRECT            a real compare ran and the two sides differ
#   2  usage error, or a required environment variable is unset
#   3  preflight failure    a required input is missing or unreadable
#   4  source-prep failure  v2lvs, deck rewrite or LVS BOX splice failed
#   5  NO VERDICT           Calibre never reached a compare. This is the
#                           dangerous case: the classic '"Source could not be
#                           read" / "Cell X is referenced but not defined"'
#                           abort, which an exit-status check calls a pass.
#   6  NOT MEANINGFUL       a compare ran and produced a verdict, but the
#                           layout had NO power and NO ground net, so that
#                           verdict is about the wrong thing (step 6b). Ranked
#                           above INCORRECT deliberately: an INCORRECT you can
#                           go and debug, this one you must first re-stream.
#                           5 still wins over 6 -- no compare at all is the
#                           earlier and more basic failure.
#
# GLOSSARY (first use only, then we move on):
#   SVRF        Calibre's rule-deck language. Foundry decks are SVRF with an
#               embedded TVF (Tcl) tail; SVRF statements are illegal down there.
#   black box   a cell compared by its boundary only, with no interior.
#   boundary port  a pin on that boundary. On a black box, port connectivity is
#               the only thing LVS can check -- and it is most of what matters.
#   smashed mosfet  a transistor Calibre dissolved into a parallel/series merge;
#               "unbalanced smashed mosfets" in a report is a reduction warning,
#               not a mismatch.
#
# WHY BLACK-BOXING (the load-bearing idea; full argument in CONTRACT.md S4):
# academic PDKs ship Front-End only -- liberty/LEF/simulation Verilog, but no
# transistor CDL and no cell GDS. Both sides of the compare are then device-less
# for standard cells, IO and pads, and Calibre AUTO-FLATTENS the empty layout
# frames: the layout ends up with zero cell instances while the source keeps all
# of them, and the whole digital fabric mis-compares as an artifact of missing
# data. `LVS BOX` pins each leaf as a black box on BOTH sides so they compare by
# port connectivity instead. Hard macros that DO ship a real transistor CDL are
# never boxed -- they compare to devices, which is real verification.
#-----------------------------------------------------------------------------
set -u -o pipefail

RC_OK=0; RC_INCORRECT=1; RC_USAGE=2; RC_PREFLIGHT=3; RC_PREP=4; RC_NOVERDICT=5
RC_NOPG=6

die()  { local rc=$1; shift; printf 'FAIL: %s\n' "$*" >&2; exit "$rc"; }
info() { printf 'INFO: [lvs] %s\n' "$*"; }

usage() {
    sed -n '/^#   run_lvs.sh /,/^#$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    printf 'Inputs are environment variables; see CONTRACT.md section 1.\n'
}

# ---- mode ------------------------------------------------------------------
MODE=run
case "${1-}" in
    --check|-c)        MODE=check ;;
    --source-only|-s)  MODE=source ;;
    --pg-check)        MODE=pgcheck ;;
    --help|-h)         usage; exit "$RC_OK" ;;
    "")                ;;
    *) printf 'usage: %s [--check | --source-only | --pg-check | --help]\n' "$0" >&2
       exit "$RC_USAGE" ;;
esac

# ---- environment contract (CONTRACT.md S1) ---------------------------------
# Required, no defaults. Deliberately NOT ${VAR:?} so we can report every
# missing input in one pass and return a distinct exit code.
LVS_DECK="${LVS_DECK-}"          # foundry rule deck; read-only, never edited in place
LVS_GDS="${LVS_GDS-}"            # the layout
LVS_TOP="${LVS_TOP-}"            # top cell; must exist in BOTH layout and netlist
LVS_SRC_V="${LVS_SRC_V-}"        # the schematic: post-P&R Verilog, not the synth netlist
LVS_RUNDIR="${LVS_RUNDIR-}"      # everything lands here; we cd into it

# Leaf-cell resolution. All three are LISTS (space separated). IO_VLOG is empty
# for a block with no IO ring; MACRO_CDLS is empty for a design with no hard
# macros -- both are legitimate, so neither may be forced non-empty.
STDCELL_VLOG="${STDCELL_VLOG-}"  # standard-cell simulation Verilog (Front-End view)
IO_VLOG="${IO_VLOG-}"            # IO-driver simulation Verilog
MACRO_CDLS="${MACRO_CDLS-}"      # real transistor CDLs for hard macros (SRAM/ROM/...)

# Optional, with defaults.
LVS_SOURCE_ADDED="${LVS_SOURCE_ADDED-}"   # foundry primitive stubs -> v2lvs -lsp
LVS_POWER="${LVS_POWER:-VDD}"
LVS_GROUND="${LVS_GROUND:-VSS}"
# The .GLOBAL list step 3 emits into the assembled source -- its OWN knob, and
# not simply "the supplies", because the two answer different questions.
# LVS_POWER/LVS_GROUND tell Calibre which nets to TREAT as supplies; .GLOBAL
# tells the SPICE reader to merge every net of that NAME in every scope of the
# source into one. A name can be right for the first and wrong for the second:
# see the collision scan below. Default = the supplies, so a project that never
# sets this sees byte-identical behaviour. EMPTY = emit no .GLOBAL at all.
LVS_GLOBAL_NETS="${LVS_GLOBAL_NETS-$LVS_POWER $LVS_GROUND}"
BONDPAD_CELLS="${BONDPAD_CELLS-}"         # pin-less bump/pad cells needing empty stubs
LVS_BOX_LEAF="${LVS_BOX_LEAF:-1}"
# Physical-only cells: inserted by P&R and streamed into the GDS, but absent
# from write_netlist output. Box them and they linger as unmatched LAYOUT
# instances; EXCLUDE them and their empty frames auto-flatten to match the
# source's absence of them.
LVS_BOX_EXCLUDE_RE="${LVS_BOX_EXCLUDE_RE:-^(ANTENNA|DCAP|GDCAP|GFILL|OD25DCAP)}"
LVS_TURBO="${LVS_TURBO:-$(nproc 2>/dev/null || echo 4)}"
LVS_SOURCE_ONLY="${LVS_SOURCE_ONLY:-0}"
LVS_NOWAIT="${LVS_NOWAIT:-0}"             # 1 = fail if no licence free, else queue
V2LVS="${V2LVS:-v2lvs}"
CALIBRE="${CALIBRE:-calibre}"

[ "$MODE" = source ] && LVS_SOURCE_ONLY=1

#-----------------------------------------------------------------------------
# POWER/GROUND-TEXT GUARD (used by step 6b, and standalone via --pg-check)
#
# THE FAILURE THIS CATCHES. A GDS carries geometry, not connectivity: a net
# name only reaches the layout side of LVS as GDS *text*, and whether the
# power/ground grid gets any is decided by one thing -- whether the P&R
# GDS-out map has `NAME <layer>/SPNET` rows. Foundry-supplied maps routinely
# have `NAME <layer>/PIN` and no SPNET, so the special-route (PG) grid streams
# out UNNAMED and Calibre ends up with no POWER net and no GROUND net at all.
#
# WHY IT NEEDS A GUARD RATHER THAN A FOOTNOTE. The run still completes and the
# report still looks like a report, so it reads as an ordinary INCORRECT that
# somebody then spends days debugging. It is not one: with the supplies
# unidentifiable, device recognition that keys off them stops working. Measured
# on one chiplet, the SRAM bitcell injection template fired on the SOURCE side
# only and left 4,084,884 unmatched layout objects -- a comparison about
# nothing. There is no verdict worth reading until the layout is re-streamed.
#
# WHY THIS IS NOT A PREFLIGHT. Two reasons, both learned the hard way.
#   * Cost. Deciding it from the GDS means a structure-aware parse of a
#     300 MB stream. A flat `strings | grep VDD` is worse than useless: on a
#     design with merged memory macros it finds thousands of the VENDORS' own
#     internal pin labels (12,823 on one chiplet) and reports success while the
#     top-level supply grid is anonymous. Only text in the TOP structure counts.
#   * Sufficiency. Even a perfect "is there PG text" check answers the wrong
#     question. Text can be present and still name nothing -- it has to attach
#     to metal, and the net it attaches to has to be distinct. On the run this
#     guard was built against, both supply labels were written AND attached, and
#     VSS still came back with no data because the two supplies were shorted
#     together by fabricated pad-ring geometry. Only Calibre can see that.
# So: the emitting side reports what it labelled (that is lvs_pg_emit.tcl's
# job, and it is free there), and this guard reports what actually RESOLVED.
# Neither substitutes for the other.
#-----------------------------------------------------------------------------
PG_HITS=()     # evidence lines for a hard failure, printed by pg_banner
PG_PARTIAL=()  # supplies with no layout data when OTHERS did resolve
PG_SIDES=()    # which of POWER / GROUND came back empty

# pg_scan <rundir> -> 0 = supplies named, 1 = NOT named, 2 = cannot tell.
# Two independent signals; either one is conclusive on its own.
pg_scan() {
    local rundir=$1 deck="" erc="" d line n
    local -a files=() names_missing=()
    PG_HITS=(); PG_PARTIAL=(); PG_SIDES=()

    # The ERC summary's filename is the DECK's choice, so read it out of the
    # deck instead of hardcoding it -- a foundry deck that renames it must not
    # silently disable the guard.
    deck="$rundir/${LVS_TOP}_calibre_lvs.deck"
    if [ ! -r "$deck" ]; then
        deck=""
        for d in "$rundir"/*.deck; do [ -r "$d" ] && { deck=$d; break; }; done
    fi
    if [ -n "$deck" ]; then
        erc=$(sed -n 's/^[[:space:]]*ERC SUMMARY REPORT[[:space:]]*"\([^"]*\)".*/\1/p' \
              "$deck" | head -1)
    fi
    [ -z "$erc" ] && erc="calibre_erc.sum"
    case "$erc" in /*) ;; *) erc="$rundir/$erc" ;; esac

    [ -s "$erc" ] && files+=("$erc")
    [ -s "$rundir/calibre_lvs.log" ] && files+=("$rundir/calibre_lvs.log")
    [ "${#files[@]}" -eq 0 ] && return 2

    # Signal 1: the deck's own ERC PATHCHK statements refuse to run. Calibre
    # says so in as many words, and it cannot mean anything else.
    # The same sentence appears in both files, bare in the summary and behind a
    # "WARNING: " prefix in the log -- strip it before sort -u so the evidence
    # list is four lines of distinct fact, not eight of two.
    while IFS= read -r line; do
        [ -n "$line" ] && PG_HITS+=("$line")
    done < <(grep -hE 'no (POWER|GROUND) nets present' "${files[@]}" 2>/dev/null \
             | sed -e 's/^[[:space:]]*//' -e 's/^\(WARNING\|ERROR\)[: ]*//' | sort -u)

    # WHICH side is empty decides what the failure MEANS, so record it. Both
    # sides empty is a stream that carried no supply text at all. One side empty
    # is a stream that carried it and lost one name during extraction -- a
    # different problem with a different fix.
    while IFS= read -r line; do
        [ -n "$line" ] && PG_SIDES+=("$line")
    done < <(grep -hoE 'no (POWER|GROUND) nets present' "${files[@]}" 2>/dev/null \
             | awk '{print $2}' | sort -u)

    # Signal 2: which of the supply names this run asked for have no layout
    # data. ALL of them missing is conclusive and fires the guard. SOME of them
    # missing is not -- an IO supply a design never routes as a special net has
    # nothing to name, which is normal -- but it is worth saying out loud, so it
    # is collected separately and reported as a warning by the caller.
    local nnames=0
    for n in $LVS_POWER $LVS_GROUND; do
        nnames=$((nnames + 1))
        grep -qF "There is no data for layout net name ${n}." "${files[@]}" 2>/dev/null \
            && names_missing+=("$n")
    done
    if [ "$nnames" -gt 0 ] && [ "${#names_missing[@]}" -eq "$nnames" ]; then
        for n in "${names_missing[@]}"; do PG_HITS+=("no layout geometry is named $n"); done
    elif [ "${#names_missing[@]}" -gt 0 ]; then
        PG_PARTIAL=("${names_missing[@]}")
    fi

    [ "${#PG_HITS[@]}" -gt 0 ] && return 1
    return 0
}

# Non-fatal. A supply that resolved and one that did not is a real, reportable
# state -- not necessarily an error, and never silently fine.
pg_partial_warn() {
    [ "${#PG_PARTIAL[@]}" -eq 0 ] && return 0
    echo "WARNING: these supplies have NO layout data: ${PG_PARTIAL[*]}"
    echo "         Others in [$LVS_POWER] / [$LVS_GROUND] did resolve, so the layout"
    echo "         is not unlabelled -- these specific names are simply not on any"
    echo "         geometry. Two ordinary causes, and one that is not ordinary:"
    echo "           - the net is never routed as a SPECIAL net (nothing to name);"
    echo "           - the name is wrong for this design;"
    echo "           - the net IS named but SHORTED to another supply, in which case"
    echo "             Calibre keeps one name and drops the other. Check the report's"
    echo "             shorts file for a supply-to-supply entry before assuming the"
    echo "             benign reading."
    return 0
}

pg_banner() {
    local h
    if [ "${#PG_SIDES[@]}" -eq 1 ]; then
        printf '\n%s\n' "*******************************************************************************"
        printf '**  LVS RESULT IS NOT MEANINGFUL: THE LAYOUT HAS NO %s NET%*s**\n' \
            "${PG_SIDES[0]}" $((21 - ${#PG_SIDES[0]})) ''
        printf '%s\n' "*******************************************************************************"
    else
        cat <<'EOF'

*******************************************************************************
**  LVS RESULT IS NOT MEANINGFUL: THE LAYOUT HAS NO POWER AND NO GROUND NET  **
*******************************************************************************
EOF
    fi
    echo "  Evidence, from this run's ERC summary / Calibre log:"
    for h in "${PG_HITS[@]}"; do printf '      %s\n' "$h"; done

    if [ "${#PG_SIDES[@]}" -eq 1 ]; then
        cat <<EOF

  READ THIS BEFORE RE-STREAMING: the OTHER side resolved, so this layout is NOT
  missing its supply text and re-streaming it will change nothing. One supply
  name survived extraction and this one did not. In order of likelihood:

    1. The two supplies are SHORTED. Calibre keeps one name for the merged net
       and drops the other, which looks exactly like this. Check the report's
       shorts file for a supply-to-supply entry FIRST -- it names both texts and
       prints the shorting path.
    2. This supply is never routed as a special net, so it has no geometry to
       carry a name. Then it is not an error, and the name does not belong in
       LVS_POWER / LVS_GROUND.

  On a Front-End-only PDK, a frequent cause of (1) is LEF OBSTRUCTION streamed
  as if it were metal. Foundry GDS-out maps put LEFOBS on the same GDS layer as
  real metal, and with macro output enabled every routing blockage becomes a
  polygon. Pad spacers, which are nothing BUT obstruction, then tile into a
  continuous sheet that shorts every net reaching a pad -- supplies included.
  That is a stream-out artifact, not a design defect: fix it in the GDS-out map,
  not in the design, and never by suppressing the check.
EOF
        # The banner already gives the full reasoning; here just name names.
        [ "${#PG_PARTIAL[@]}" -gt 0 ] && \
            echo "  No layout data for, specifically: ${PG_PARTIAL[*]}"
        return 0
    fi

    cat <<EOF

  LIKELY CAUSE. The layout was streamed WITHOUT power/ground text: the P&R
  GDS-out map has \`NAME <layer>/PIN\` rows but no \`NAME <layer>/SPNET\` rows, so
  the special-route (power) grid went out unnamed. Nothing in the deck or the
  netlist can recover a name that is not in the stream.

  WHY THIS IS NOT AN ORDINARY 'INCORRECT'. With no supplies identified, ERC is
  vacuous and supply-dependent device recognition stops working -- on one
  chiplet that turned a sound compare into 4,084,884 unmatched layout objects.
  Do not debug the discrepancy list above; it is describing the wrong problem.

  FIX. Re-stream the SAME routed database with an extended GDS-out map:

      make lvs_pg_gds            # ASIC/lvs-flow/lvs_pg_emit.tcl
      make lvs_batch LVS_PG=1    # then compare against that stream

  It is read-only on the database (no write_db) and produces a new filename, so
  the signoff GDS and the tapeout database are untouched. Background:
  CONTRACT.md section 6, and the header of lvs_pg_emit.tcl.

  A GDS with no PG text is a broken INPUT, not a design defect -- and it is
  never fixed by \`LVS IGNORE PORTS\` or by suppressing the bulk checks.
EOF
    # Which supplies specifically, when only some of them failed to resolve --
    # that distinction is what points at a short rather than a missing label.
    pg_partial_warn
}

# One line, accurate for whichever failure it was; callers add their own context.
pg_result_line() {
    if [ "${#PG_SIDES[@]}" -eq 1 ]; then
        printf 'RESULT: LVS NOT MEANINGFUL -- the layout has no %s net.\n' "${PG_SIDES[0]}"
    else
        printf 'RESULT: LVS NOT MEANINGFUL -- the layout carries no power/ground text.\n'
    fi
}

if [ "$MODE" = pgcheck ]; then
    [ -n "$LVS_RUNDIR" ] || die "$RC_USAGE" \
        "--pg-check needs LVS_RUNDIR: it inspects an existing run directory."
    [ -d "$LVS_RUNDIR" ] || die "$RC_PREFLIGHT" "no run directory at $LVS_RUNDIR"
    pg_scan "$LVS_RUNDIR"; pg_state=$?
    case "$pg_state" in
        0) echo "PG CHECK: OK -- the layout in $LVS_RUNDIR named its supplies."
           echo "          (checked for [$LVS_POWER] / [$LVS_GROUND])"
           pg_partial_warn
           exit "$RC_OK" ;;
        2) die "$RC_PREFLIGHT" \
               "nothing to check in $LVS_RUNDIR: no ERC summary and no Calibre log.
      --pg-check reads a COMPLETED run's artefacts; run the LVS first." ;;
        *) pg_banner
           pg_result_line
           exit "$RC_NOPG" ;;
    esac
fi

#-----------------------------------------------------------------------------
# .GLOBAL COLLISION SCAN
#
# THE FAILURE THIS CATCHES, in one sentence: `.GLOBAL VSS` is right for cells
# and wrong for a hard macro that uses the name VSS for something that is not
# chip ground.
#
# WHY .GLOBAL IS THERE AT ALL. A post-P&R Verilog netlist that wires .VDD/.VSS
# on every instance needs no help; one that does not, needs the supplies
# declared global so each leaf's power pin ties to them by name. That is the
# case step 3 was written for, and it is the common one.
#
# WHAT IT COSTS. `.GLOBAL <name>` is not scoped: it merges EVERY net called
# <name>, in EVERY .SUBCKT of the source, into one net. Hard-macro CDLs are
# vendor output with a vendor's naming, and a macro is free to use `VSS` (or
# `VDD`, or any supply name) for an INTERNAL node while bringing its real
# supplies out under different pin names -- `VSSE`/`VDDE` is a common pair.
# Power-gated macros do exactly this: the internal `VSS` is the SWITCHED
# (virtual) ground, sitting on the other side of the power-gate footers from
# the real one. `.GLOBAL VSS` then ties the two together, which fabricates a
# short across the switch -- IN THE SOURCE ONLY. The layout keeps them apart,
# because in silicon there is a transistor between them.
#
# WHY IT NEEDS A DETECTOR RATHER THAN A NOTE. Nothing in the run says
# "collision". Calibre reports no SHORT, ERC stays clean, and the damage is
# confined to the macro's interior, so every symptom points at the macro:
# unmatched instances inside it, unmatched nets inside it, W/L property errors
# on the devices either side of the switch -- and one supply net whose SOURCE
# connection count exceeds the layout's by roughly the number of internal taps.
# That last number is the fingerprint; nobody looks for it unaided. Measured on
# a 323,124-instance chiplet with two power-gated ROMs: 34 unmatched instances,
# 44 unmatched nets, 70 property errors, 436 net discrepancies -- all of it, and
# a source-side `Net VSS` +1,980 connections. The layout was the correct side.
#
# THE TEST. For each name in the emitted .GLOBAL list, and each macro CDL: is
# the name USED inside the macro while NOT being a port of that macro's top
# .SUBCKT? Used-and-a-port is the safe case: an SRAM whose top reads
# `.SUBCKT <macro> VDD VSS ...` brings the supply out as a real pin, so the
# merge is a no-op -- which is why compiled SRAM is normally immune.
# Used-and-NOT-a-port means some scope inside the macro creates a local net of
# that name, and .GLOBAL will capture it. The top .SUBCKT is found structurally
# -- the one no other .SUBCKT in the file instantiates -- so this needs no
# naming convention, no cell list and no per-PDK knowledge.
#
# A macro that declares the name .GLOBAL ITSELF is deliberate, and exempt.
#-----------------------------------------------------------------------------
GLOBAL_COLLISIONS=0

# Emits one tab-separated record per finding on stdout, for the shell to format:
#   HIT   <top subckts> <net> <use count> <scopes that create it locally>
#   NOTOP <subckt>                 -- no un-instantiated .SUBCKT; assumed the top
#   SCAN  <#subckt> <#top> <tops>  -- always, one per file
# shellcheck disable=SC2016   # this is an awk program, not shell: $0 is awk's
GLOBAL_SCAN_AWK='
BEGIN { nw = split(NAMES, want_i); for (i = 1; i <= nw; i++) want[want_i[i]] = 1 }
function flush(   n, t, i, p, tk, ref, refpos) {
    if (buf == "") return
    n = split(buf, t); buf = ""
    if (n == 0) return
    p = tolower(t[1])
    if (p == ".subckt") {                      # definition: name then ports
        scope = t[2]; defined[scope] = 1; order[++nsub] = scope
        for (i = 3; i <= n; i++)
            if (t[i] != "" && index(t[i], "=") == 0 && (t[i] in want)) portof[scope, t[i]] = 1
        return
    }
    if (substr(p, 1, 5) == ".ends")  { scope = ""; return }
    if (substr(p, 1, 7) == ".global") {        # the macro asked for it itself
        for (i = 2; i <= n; i++) if (t[i] in want) selfglobal[t[i]] = 1
        return
    }
    if (substr(t[1], 1, 1) == "*" || substr(t[1], 1, 1) == ".") return
    if (scope == "") return
    refpos = 0
    if (toupper(substr(t[1], 1, 1)) == "X") {  # subckt call: which subckt?
        for (i = 2; i <= n; i++) {
            if (toupper(t[i]) == "$PINS") { refpos = i - 1; break }
            if (t[i] == "/")              { refpos = i + 1; break }
        }
        if (refpos == 0)
            for (i = n; i >= 2; i--) if (index(t[i], "=") == 0) { refpos = i; break }
        ref = (refpos > 1 && refpos <= n) ? t[refpos] : ""
        if (ref != "") refd[ref] = 1
    }
    for (i = 2; i <= n; i++) {                 # everything else on the line is a net
        if (i == refpos) continue
        tk = t[i]
        if (index(tk, "=") > 0) sub(/^.*=/, "", tk)   # $PINS pin=net, and W=/L=
        if (tk == "" || !(tk in want)) continue
        total[tk]++
        if (!((scope, tk) in portof) && !((scope, tk) in seenorph)) {
            seenorph[scope, tk] = 1
            born[tk] = born[tk] (born[tk] == "" ? "" : ",") scope
        }
    }
}
{ line = $0; sub(/\r$/, "", line)
  if (line ~ /^[ \t]*\+/) { sub(/^[ \t]*\+/, " ", line); buf = buf line; next }
  flush(); buf = line }
END {
    flush()
    ntop = 0
    for (s in defined) if (!(s in refd)) { istop[s] = 1; ntop++ }
    if (ntop == 0 && nsub > 0) { istop[order[nsub]] = 1; ntop = 1; print "NOTOP\t" order[nsub] }
    tl = ""
    for (i = 1; i <= nsub; i++) if (order[i] in istop) tl = tl (tl == "" ? "" : ",") order[i]
    for (i = 1; i <= nw; i++) {
        g = want_i[i]
        if (total[g] == 0 || (g in selfglobal)) continue    # unused, or deliberate
        safe = 0
        for (s in istop) if ((s, g) in portof) { safe = 1; break }   # a real pin
        if (!safe) print "HIT\t" tl "\t" g "\t" total[g] "\t" born[g]
    }
    print "SCAN\t" nsub "\t" ntop "\t" tl
}'

# global_collision_scan -- prints its own section; never fatal, always loud.
# Sets GLOBAL_COLLISIONS. Runs in every mode including --check, so the answer
# arrives before a licence is spent rather than after a report is misread.
global_collision_scan() {
    local f kind a b c d nfile=0 nsubckt=0
    GLOBAL_COLLISIONS=0

    if [ -z "${LVS_GLOBAL_NETS// /}" ]; then
        printf '  (none)  %-14s LVS_GLOBAL_NETS is empty -- no .GLOBAL emitted, nothing can collide\n' "globals"
        return 0
    fi
    if [ -z "${MACRO_CDLS// /}" ]; then
        printf '  (none)  %-14s [%s] -- no macro CDLs to check\n' "globals" "$LVS_GLOBAL_NETS"
        return 0
    fi

    # shellcheck disable=SC2086   # MACRO_CDLS is a space-separated list
    for f in $MACRO_CDLS; do
        [ -r "$f" ] && [ -s "$f" ] || continue
        nfile=$((nfile + 1))
        while IFS=$'\t' read -r kind a b c d; do
            case "$kind" in
            HIT)   # a=top(s)  b=net  c=use count  d=scopes that create it locally
                GLOBAL_COLLISIONS=$((GLOBAL_COLLISIONS + 1))
                [ "$GLOBAL_COLLISIONS" = 1 ] && printf '  %s\n  %s\n  %s\n' \
                    '****************************************************************************' \
                    '**  A .GLOBAL NAME IS AN INTERNAL NET OF A HARD MACRO                     **' \
                    '****************************************************************************'
                printf '    macro CDL   : %s\n' "$f"
                printf '    top .SUBCKT : %s\n' "$a"
                printf '    net         : %s -- used %s time(s) inside the macro, and NOT a port of %s\n' \
                    "$b" "$c" "$a"
                [ -n "$d" ] && printf '    created in  : %s\n' "$(printf '%s' "$d" | tr ',' ' ')"
                printf '                  (the scope(s) that use %s without declaring it -- where the\n' "$b"
                printf '                   local net is born, and what .GLOBAL would capture)\n'
                ;;
            NOTOP) # a=the .SUBCKT assumed to be the top
                printf '  WARN    %-14s %s: every .SUBCKT is instantiated by another; assuming top = %s\n' \
                    "globals" "$(basename -- "$f")" "$a"
                ;;
            SCAN)  # a=#subckt  b=#top  c=top names
                nsubckt=$((nsubckt + a))
                ;;
            esac
        done < <(awk -v NAMES="$LVS_GLOBAL_NETS" "$GLOBAL_SCAN_AWK" "$f")
    done

    if [ "$GLOBAL_COLLISIONS" -eq 0 ]; then
        printf '  OK      %-14s [%s] vs %d macro CDL(s), %d .SUBCKT(s): no name is a macro internal\n' \
            "globals" "$LVS_GLOBAL_NETS" "$nfile" "$nsubckt"
        return 0
    fi

    cat <<EOF

  WHAT THIS DOES. \`.GLOBAL <name>\` is not scoped: every net of that name, in
  every .SUBCKT of the source, becomes ONE net. The macro above uses the name
  for an internal node -- a power-gated virtual ground, a second supply domain,
  an internal rail -- and brings its real supplies out under different pin
  names. Merging the two fabricates a connection that does not exist in
  silicon, typically a SHORT ACROSS A POWER-GATE SWITCH, and it exists only on
  the SOURCE side. The layout is the correct side.

  HOW IT WILL SHOW UP, so it is recognisable in a report you already have:
    * unmatched instances and unmatched nets CONFINED to that macro's interior,
      on both sides, in equal-ish numbers -- a cell-type substitution, not a
      missing device (Calibre's injected pseudo-cells change type when a
      device's bulk net stops differing from its source net);
    * device property (W/L) errors inside the macro, from parallel reduction
      grouping different numbers of fingers on the two sides;
    * one supply net whose SOURCE connection count exceeds the LAYOUT's by
      roughly the number of internal taps -- the fingerprint;
    * no SHORT record, and clean ERC. It does not look like a short.

  REMEDY -- cheapest first, and neither one touches the design or the layout:
    1. Take the name out of LVS_GLOBAL_NETS (it defaults to
       "\$LVS_POWER \$LVS_GROUND"; set it to the subset that is genuinely
       global, or to nothing). SAFE WHEN the post-P&R netlist wires the
       supplies explicitly -- check that cell instances carry .VDD/.VSS and
       that this macro's own supply pins are connected to the chip supplies.
       Then the global was doing no work and only this damage.
    2. If some cells DO rely on the global, keep it and point MACRO_CDLS at a
       PROJECT-LOCAL COPY of this CDL with the internal net renamed (e.g.
       VSS -> VSS_<macro>_INT), leaving the real supply pins alone. Vendor and
       PDK collateral is read-only: copy it into the project tree, never edit
       it in place.
  Suppressing the resulting discrepancies is not a third option.

EOF
    return 0
}

# Printed after preflight, so the finding is the LAST thing on screen rather
# than something scrolled away by the OK block.
global_collision_reminder() {
    [ "$GLOBAL_COLLISIONS" -eq 0 ] && return 0
    echo "WARNING: $GLOBAL_COLLISIONS .GLOBAL/macro-internal collision(s) -- see the banner above."
    echo "         The comparison will run, and its macro-interior discrepancies will be"
    echo "         an artifact of the source, not a defect. Fix LVS_GLOBAL_NETS first."
    return 0
}

#-----------------------------------------------------------------------------
# PREFLIGHT -- validates every input. Takes no licence and launches no tool
# (note: even `v2lvs -h` acquires a calibrelvs licence, so we only ever do
# `command -v` here).
#-----------------------------------------------------------------------------
miss_env=0
miss_file=0

chk_file() {   # chk_file <label> <path>
    if [ -r "$2" ] && [ -s "$2" ]; then printf '  OK      %-14s %s\n' "$1" "$2"
    else printf '  MISSING %-14s %s\n' "$1" "$2"; miss_file=1; fi
}

chk_list() {   # chk_list <label> <space-separated paths>; empty list is allowed
    local label=$1 list=$2 f n=0
    if [ -z "${list// /}" ]; then printf '  (none)  %-14s -- allowed to be empty\n' "$label"; return; fi
    for f in $list; do chk_file "$label" "$f"; n=$((n + 1)); done
    [ "$n" -gt 1 ] && printf '          %-14s %d file(s)\n' "$label" "$n"
    return 0
}

preflight() {
    local v d
    echo "== LVS preflight (no licence taken, no tool launched) =="

    for v in LVS_DECK LVS_GDS LVS_TOP LVS_SRC_V LVS_RUNDIR STDCELL_VLOG; do
        if [ -z "${!v-}" ]; then printf '  UNSET   %s\n' "$v"; miss_env=1; fi
    done
    if [ "$miss_env" = 1 ]; then
        echo
        echo "  Set the variables above (see CONTRACT.md section 1) and re-run."
        return "$RC_USAGE"
    fi

    echo "  -- tools --"
    for v in "$V2LVS" "$CALIBRE"; do
        if command -v "$v" >/dev/null 2>&1; then
            printf '  OK      %-14s %s\n' "$(basename "$v")" "$(command -v "$v")"
        else
            printf '  MISSING %-14s not on PATH (set V2LVS / CALIBRE)\n' "$(basename "$v")"
            miss_file=1
        fi
    done

    echo "  -- layout and schematic --"
    chk_file "layout"  "$LVS_GDS"
    chk_file "netlist" "$LVS_SRC_V"
    chk_file "deck"    "$LVS_DECK"
    [ -n "$LVS_SOURCE_ADDED" ] && chk_file "source.added" "$LVS_SOURCE_ADDED"

    echo "  -- leaf-cell data --"
    chk_list "stdcell vlog" "$STDCELL_VLOG"
    chk_list "io vlog"      "$IO_VLOG"
    chk_list "macro cdl"    "$MACRO_CDLS"

    # A macro CDL that uses a .GLOBAL name for an internal net is a valid input
    # that produces an invalid source. It is an input inconsistency, so it is
    # reported here -- before a licence is spent, not after a report is misread.
    echo "  -- .GLOBAL vs macro internals --"
    global_collision_scan

    echo "  -- run directory --"
    # Do not create anything in check mode: walk up to the nearest existing
    # ancestor and test that it is writable.
    d="$LVS_RUNDIR"
    while [ -n "$d" ] && [ "$d" != "/" ] && [ ! -e "$d" ]; do d=$(dirname "$d"); done
    if [ -d "$d" ] && [ -w "$d" ]; then printf '  OK      %-14s %s\n' "rundir" "$LVS_RUNDIR"
    else printf '  MISSING %-14s %s (not writable)\n' "rundir" "$LVS_RUNDIR"; miss_file=1; fi

    # Cheap drift check on the foundry deck, before a licence is spent: does it
    # still speak the dialect step 4 rewrites? Deliberately an unanchored
    # substring test -- the anchored assertion in step 4 is the real backstop,
    # and catches subtler drift (an indented placeholder) that this would pass.
    if [ -r "$LVS_DECK" ]; then
        echo "  -- deck placeholders --"
        local tok found=0 absent=0
        for tok in 'LAYOUT PRIMARY "lvs_top"' 'LAYOUT PATH "lvs_top.gds"' \
                   'SOURCE PRIMARY "lvs_top"' 'SOURCE PATH "lvs_top.cdl"' \
                   'LVS REPORT "lvs.rep"' 'LVS POWER NAME POWER_NAME' \
                   'LVS GROUND NAME GROUND_NAME'; do
            if grep -qF "$tok" "$LVS_DECK"; then found=$((found + 1))
            else printf '  MISSING %-14s [%s]\n' "placeholder" "$tok"; absent=1; fi
        done
        [ "$absent" = 0 ] && printf '  OK      %-14s all %d present\n' "placeholder" "$found"
        [ "$absent" = 1 ] && miss_file=1
    fi

    # Top cell must exist in the schematic. (The GDS side is not checked here:
    # that means reading the whole stream, which is the run's job, not a
    # preflight's.) A warning, not a failure -- netlist styles vary.
    if [ -r "$LVS_SRC_V" ] && ! grep -qE "^[[:space:]]*module[[:space:]]+${LVS_TOP}([[:space:]]|\(|$)" "$LVS_SRC_V"; then
        printf '  WARN    %-14s no "module %s" found in %s\n' "top cell" "$LVS_TOP" "$LVS_SRC_V"
    fi

    if [ "$miss_file" = 1 ]; then
        echo
        echo "== LVS preflight FAILED: the inputs marked MISSING above are needed. =="
        echo "   Each one is a path this project supplies; fix the path, or install"
        echo "   the missing collateral, and re-run --check."
        return "$RC_PREFLIGHT"
    fi

    cat <<'EOF'

== LVS preflight OK ==
   NOTE on scope, so nobody re-derives it wrongly: this flow does NOT require
   foundry Back-End packages (transistor CDL + cell GDS) for the standard cells,
   IO or pads. Front-End simulation Verilog is sufficient.

   WHAT A PASS PROVES. Every cell present, of the right type and count, and the
   routed nets between them reconciled against the netlist. Hard macros that
   ship a real CDL compare all the way down to transistors.

   WHAT IT DOES NOT PROVE, all three by construction:
     * cell interiors -- boxed leaves are black boxes;
     * pin-level wiring ON those boxed leaves -- with no cell GDS their layout
       frames carry no pins Calibre recognises, so it can match the instance and
       still report "non-floating extra pins" against the source stub;
     * the pad ring -- its cells are LEF-only and their obstruction geometry is
       deliberately stripped from the LVS stream because it fabricates shorts.

   Say "clean modulo black boxes and modulo the pad ring". Never "signoff
   clean", and never "every port wired as the netlist says".
   Detail: CONTRACT.md sections 5, 6c.
EOF
    return "$RC_OK"
}

preflight; pf=$?
global_collision_reminder
[ "$pf" -ne 0 ] && exit "$pf"
[ "$MODE" = check ] && exit "$RC_OK"

#-----------------------------------------------------------------------------
# Absolute paths everywhere. The run below works from inside $LVS_RUNDIR (both
# tools write into the current directory), so any relative input path a project
# supplied would break the moment we cd. Resolve them all first.
#-----------------------------------------------------------------------------
mkdir -p "$LVS_RUNDIR" || die "$RC_PREP" "cannot create rundir $LVS_RUNDIR"
LVS_RUNDIR=$(readlink -f "$LVS_RUNDIR")
LVS_GDS=$(readlink -f "$LVS_GDS")
LVS_SRC_V=$(readlink -f "$LVS_SRC_V")
LVS_DECK=$(readlink -f "$LVS_DECK")
[ -n "$LVS_SOURCE_ADDED" ] && LVS_SOURCE_ADDED=$(readlink -f "$LVS_SOURCE_ADDED")

# Split the space-separated LISTS into arrays once, resolving each entry, so
# every later use is quoted and an empty list simply contributes no arguments.
# Resolve-then-dedupe: a project Makefile that names the same library twice (or
# by two different routes to the same file) would otherwise define every subckt
# in it twice, which Calibre reports as thousands of duplicate-definition
# warnings and which makes the boxed/unboxed counts lie.
V_ARGS=(); L_ARGS=(); S_ARGS=(); MACRO_ARR=()
declare -A _seen=()
# shellcheck disable=SC2086   # splitting the lists on whitespace is the point
for v in $STDCELL_VLOG $IO_VLOG; do
    v=$(readlink -f "$v"); [ -n "${_seen[$v]-}" ] && continue; _seen[$v]=1
    V_ARGS+=(-v "$v"); L_ARGS+=(-l "$v")
done
# shellcheck disable=SC2086
for c in $MACRO_CDLS; do
    c=$(readlink -f "$c"); [ -n "${_seen[$c]-}" ] && continue; _seen[$c]=1
    S_ARGS+=(-s "$c"); MACRO_ARR+=("$c")
done

LIBS_CDL="$LVS_RUNDIR/${LVS_TOP}_libs.cdl"
DESIGN_CDL="$LVS_RUNDIR/${LVS_TOP}_design.cdl"
SRC_CDL="$LVS_RUNDIR/${LVS_TOP}_lvs_src.cdl"
BOX_SVRF="$LVS_RUNDIR/${LVS_TOP}_lvs_box.svrf"
RUN_DECK="$LVS_RUNDIR/${LVS_TOP}_calibre_lvs.deck"
LVS_REP="$LVS_RUNDIR/${LVS_TOP}.lvs.rep"
LOG="$LVS_RUNDIR/calibre_lvs.log"

cat <<EOF
== Calibre nmLVS ==
  top cell  : $LVS_TOP
  layout    : $LVS_GDS
  schematic : $LVS_SRC_V
  deck      : $LVS_DECK
  rundir    : $LVS_RUNDIR
  supplies  : power [$LVS_POWER]  ground [$LVS_GROUND]
  globals   : [$LVS_GLOBAL_NETS]
  box leaves: $LVS_BOX_LEAF (exclude /$LVS_BOX_EXCLUDE_RE/)
EOF

# Work from inside the run directory from here on. Both v2lvs and Calibre drop
# transcripts and scratch files into the CURRENT directory (v2lvs writes a
# v2lvs.log, the deck's svdb/ and ERC outputs are relative paths), and those
# belong to the run, not to wherever the user happened to type `make`. Every
# input path was resolved above, so the cd cannot break one.
cd "$LVS_RUNDIR" || die "$RC_PREP" "cannot cd to $LVS_RUNDIR"

# ---- 1. v2lvs -e on the cell libraries -> empty .SUBCKT stubs ---------------
# `-e` emits one stub per module and translates no instances. Required because
# scan-flops and IO cells use UDP-based behavioural models that v2lvs would
# otherwise drop, giving "No matching .SUBCKT" at compare time. Only the
# Front-End libraries go here; hard macros come from their real CDL in step 3.
info "step 1: v2lvs -e (cell libraries -> empty .SUBCKT stubs)"
"$V2LVS" -e "${V_ARGS[@]}" \
    -o "$LIBS_CDL" || die "$RC_PREP" "v2lvs -e failed on the cell libraries"
[ -s "$LIBS_CDL" ] || die "$RC_PREP" "v2lvs -e produced nothing at $LIBS_CDL"
nstub=$(grep -cE '^\.SUBCKT' "$LIBS_CDL" || true)
info "step 1: $nstub leaf stub(s) -> $LIBS_CDL"

# ---- 2. v2lvs on the design -> the translated netlist ----------------------
# `-l` = library Verilog: leaves are referenced, not redefined (they already
# exist as stubs from step 1). `-lsp` = the foundry's primitive stubs.
# `-s` only writes an `.INCLUDE "<path>"` header line -- it does NOT read the
# file (see the ISSUE LOG). We strip those lines in step 3 and concatenate the
# CDLs instead, so the assembled source is one self-contained file.
LSP_ARGS=()
[ -n "$LVS_SOURCE_ADDED" ] && LSP_ARGS=(-lsp "$LVS_SOURCE_ADDED")
info "step 2: v2lvs (translate design)"
"$V2LVS" \
    -v "$LVS_SRC_V" \
    "${L_ARGS[@]}" "${S_ARGS[@]}" "${LSP_ARGS[@]}" \
    -o "$DESIGN_CDL" || die "$RC_PREP" "v2lvs failed on the design netlist"
[ -s "$DESIGN_CDL" ] || die "$RC_PREP" "v2lvs produced nothing at $DESIGN_CDL"

# ---- 3. assemble one SPICE source deck -------------------------------------
# Batch Calibre LVS reads SPICE only: `SOURCE SYSTEM VERILOG` is a Calibre
# Interactive feature and the foundry deck rejects it with INP1.
# Order: globals, bond-pad stubs, leaf stubs, design, real macro CDLs.
info "step 3: assemble source CDL"
INC_PAT=$(mktemp "$LVS_RUNDIR/.lvs_inc_pat.XXXXXX") || die "$RC_PREP" "mktemp failed"
trap 'rm -f "$INC_PAT"' EXIT
: > "$INC_PAT"
for c in "${MACRO_ARR[@]}"; do printf '.INCLUDE "%s"\n' "$c" >> "$INC_PAT"; done

{
    # A netlist that emits no explicit power/ground needs the supplies declared
    # global, so every leaf power pin ties to them BY NAME. LVS_GLOBAL_NETS
    # defaults to exactly that and is emitted verbatim. Empty = no .GLOBAL line
    # at all, which is the right answer when the netlist wires the supplies
    # itself AND a macro uses one of the names internally (see the collision
    # scan above -- .GLOBAL would fabricate a short inside that macro).
    [ -n "${LVS_GLOBAL_NETS// /}" ] && echo ".GLOBAL $LVS_GLOBAL_NETS"

    # shellcheck disable=SC2086   # BONDPAD_CELLS is a space-separated list
    # Bond pads / bumps are placed straight into the layout and are LEF-only:
    # top-metal shapes with no pins and no Verilog or CDL model. The netlist
    # instances them with zero nets, nothing defines them, and the source is
    # rejected outright ("Source could not be read") before any compare. An
    # empty, pin-less .SUBCKT is the faithful schematic view of a bump.
    for cell in $BONDPAD_CELLS; do printf '.SUBCKT %s\n.ENDS\n' "$cell"; done

    cat "$LIBS_CDL"

    # Drop v2lvs's `.INCLUDE` header lines for the macro CDLs -- we concatenate
    # those files verbatim below, and having both defines every macro subckt
    # twice (thousands of "Duplicate subckt definition" warnings).
    if [ -s "$INC_PAT" ]; then grep -Fv -f "$INC_PAT" "$DESIGN_CDL"; else cat "$DESIGN_CDL"; fi

    # Real transistor CDLs: these macros compare to devices, not as black boxes.
    [ "${#MACRO_ARR[@]}" -gt 0 ] && cat "${MACRO_ARR[@]}"
    true   # an empty macro list must not make the whole group exit non-zero
} > "$SRC_CDL" || die "$RC_PREP" "could not assemble $SRC_CDL"
[ -s "$SRC_CDL" ] || die "$RC_PREP" "assembled source $SRC_CDL is empty"
info "step 3: source CDL $(du -h "$SRC_CDL" | cut -f1) -> $SRC_CDL"

# ---- 4. rewrite the foundry deck's placeholders into a local copy -----------
# Foundry decks ship lvs_top / lvs_top.gds / lvs_top.cdl / lvs.rep / POWER_NAME
# / GROUND_NAME as LITERAL strings, expecting an edit-in-place workflow.
# Substitute into a project-local copy; never INCLUDE + override, because a
# duplicate specification statement is a hard SPC1 error. The foundry deck
# itself is read-only lab collateral and is not touched.
info "step 4: rewrite deck placeholders -> $RUN_DECK"

# Escape the replacement side: '&' means "the whole match" to sed and '|' is our
# delimiter, so a path containing either would silently corrupt the deck.
sed_rep() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

SED_ARGS=()
ASSERTS=()
subst() {   # subst <literal deck text> <replacement text>
    SED_ARGS+=(-e "s|^$1|$(sed_rep "$2")|")
    ASSERTS+=("$2")
}
# Anchored at ^ so the deck's commented-out variants (`//LAYOUT PATH ...`) and
# unrelated longer lines (`LVS REPORT MAXIMUM`) are left alone. Not anchored at
# $, because foundry decks routinely leave trailing whitespace on these lines.
subst 'LAYOUT PRIMARY "lvs_top"'     "LAYOUT PRIMARY \"${LVS_TOP}\""
subst 'LAYOUT PATH "lvs_top.gds"'    "LAYOUT PATH \"${LVS_GDS}\""
subst 'SOURCE PRIMARY "lvs_top"'     "SOURCE PRIMARY \"${LVS_TOP}\""
subst 'SOURCE PATH "lvs_top.cdl"'    "SOURCE PATH \"${SRC_CDL}\""
subst 'LVS REPORT "lvs.rep"'         "LVS REPORT \"${LVS_REP}\""
subst 'LVS POWER NAME POWER_NAME'    "LVS POWER NAME ${LVS_POWER}"
subst 'LVS GROUND NAME GROUND_NAME'  "LVS GROUND NAME ${LVS_GROUND}"

sed "${SED_ARGS[@]}" "$LVS_DECK" > "$RUN_DECK" || die "$RC_PREP" "deck rewrite failed"

# Deck-drift guard: assert EVERY substitution landed. Without this, a foundry
# deck that renamed a placeholder would run happily against lvs_top.gds and
# report a verdict about the wrong design.
for token in "${ASSERTS[@]}"; do
    grep -qF "$token" "$RUN_DECK" || die "$RC_PREP" \
"deck placeholder substitution did not land: [$token]
      The deck $LVS_DECK no longer contains the line this flow rewrites.
      Compare its LAYOUT/SOURCE PRIMARY, LAYOUT/SOURCE PATH, LVS REPORT and
      LVS POWER/GROUND NAME lines against the subst() calls in $0 and update
      them together."
done
info "step 4: ${#ASSERTS[@]} placeholder substitution(s) verified"

# ---- 5. build and splice the LVS BOX block ---------------------------------
if [ "$LVS_BOX_LEAF" = "1" ]; then
    info "step 5: build LVS BOX list (excluding /$LVS_BOX_EXCLUDE_RE/ and macro subckts)"

    # Never box a cell that has a real transistor CDL: it would throw away the
    # only genuine device-level verification in the run. This matters when a
    # macro also ships simulation Verilog that landed in the step-1 stubs.
    MACRO_SUBCKTS=$(mktemp "$LVS_RUNDIR/.lvs_macro_subckt.XXXXXX") || die "$RC_PREP" "mktemp failed"
    trap 'rm -f "$INC_PAT" "$MACRO_SUBCKTS"' EXIT
    : > "$MACRO_SUBCKTS"
    if [ "${#MACRO_ARR[@]}" -gt 0 ]; then
        # -i: CDLs use .SUBCKT or .subckt interchangeably.
        grep -hiE '^[[:space:]]*\.subckt[[:space:]]' "${MACRO_ARR[@]}" \
            | awk '{print $2}' | sort -u > "$MACRO_SUBCKTS"
    fi
    nmacro=$(wc -l < "$MACRO_SUBCKTS")

    BOX_CELLS=$(mktemp "$LVS_RUNDIR/.lvs_box_cells.XXXXXX") || die "$RC_PREP" "mktemp failed"
    trap 'rm -f "$INC_PAT" "$MACRO_SUBCKTS" "$BOX_CELLS"' EXIT
    {
        grep -E '^\.SUBCKT' "$LIBS_CDL" | awk '{print $2}'
        # shellcheck disable=SC2086   # space-separated list
        for cell in $BONDPAD_CELLS; do echo "$cell"; done
    } | grep -Ev "$LVS_BOX_EXCLUDE_RE" | sort -u > "$BOX_CELLS"
    ncand=$(wc -l < "$BOX_CELLS")

    if [ -s "$MACRO_SUBCKTS" ]; then
        grep -Fxv -f "$MACRO_SUBCKTS" "$BOX_CELLS" > "$BOX_CELLS.f" || true
        mv "$BOX_CELLS.f" "$BOX_CELLS"
    fi
    nbox_cells=$(wc -l < "$BOX_CELLS")

    # 8 names per LVS BOX statement purely for a readable deck.
    {
        echo "// Front-End-only leaf cells boxed as boundary black boxes (run_lvs.sh step 5)"
        awk 'NR%8==1{if(NR>1)print"";printf"LVS BOX"}{printf" %s",$1}END{if(NR)print""}' "$BOX_CELLS"
    } > "$BOX_SVRF" || die "$RC_PREP" "could not build $BOX_SVRF"

    if [ "$nbox_cells" -eq 0 ]; then
        echo "WARNING: LVS BOX list is empty -- no Front-End-only leaves found." >&2
        echo "         If this design really has none, set LVS_BOX_LEAF=0." >&2
    fi

    # Splice into the SVRF region, immediately after LVS GROUND NAME -- NOT at
    # end-of-file, where the deck's embedded TVF (Tcl) tail would parse SVRF as
    # Tcl and die with "TVF2 invalid command name".
    awk -v boxfile="$BOX_SVRF" '
        { print }
        /^LVS GROUND NAME/ && !spliced {
            while ((getline line < boxfile) > 0) print line
            close(boxfile); spliced = 1
        }' "$RUN_DECK" > "$RUN_DECK.tmp" \
        || die "$RC_PREP" "could not splice the LVS BOX block into $RUN_DECK"
    mv "$RUN_DECK.tmp" "$RUN_DECK"

    nbox_want=$(grep -cE '^LVS BOX' "$BOX_SVRF" || true)
    nbox_got=$(grep -cE '^LVS BOX' "$RUN_DECK" || true)
    [ "$nbox_got" -eq "$nbox_want" ] && [ "$nbox_got" -gt 0 ] || die "$RC_PREP" \
"LVS BOX splice landed $nbox_got of $nbox_want line(s) in $RUN_DECK.
      The deck must contain a line starting 'LVS GROUND NAME' for the splice
      point; check step 4 rewrote it."
    info "step 5: boxed $nbox_cells cell(s) in $nbox_got LVS BOX line(s)" \
         "(from $ncand candidate(s), $nmacro macro subckt(s) held back for device compare)"
else
    info "step 5: LVS_BOX_LEAF=0 -- raw un-boxed compare (diagnostic only)"
fi

if [ "$LVS_SOURCE_ONLY" = "1" ]; then
    echo "OK: source prep complete, Calibre not launched (no licence taken)."
    echo "    source : $SRC_CDL"
    echo "    deck   : $RUN_DECK"
    [ "$LVS_BOX_LEAF" = "1" ] && echo "    box    : $BOX_SVRF"
    exit "$RC_OK"
fi

# ---- 6. run Calibre, then read the REPORT ----------------------------------
WAITFLAG=()
[ "$LVS_NOWAIT" = "1" ] && WAITFLAG=(-nowait)   # else queue for a free licence

rm -f "$LVS_REP"    # never let a previous run's verdict be read as this one's
info "step 6: $CALIBRE -lvs -hier -64 -turbo $LVS_TURBO ${WAITFLAG[*]} $RUN_DECK"
# cwd is already $LVS_RUNDIR (set before step 1), which the deck's relative
# svdb/ and ERC output paths depend on.
"$CALIBRE" -lvs -hier -64 -turbo "$LVS_TURBO" "${WAITFLAG[@]}" "$RUN_DECK" 2>&1 | tee "$LOG"
calibre_rc=${PIPESTATUS[0]}
echo
echo "== calibre exit status: $calibre_rc (informational -- the verdict is in the report) =="

# ---- 6b. did the layout actually carry its supplies? ------------------------
# Run the scan now, report it below. The verdict extract is still printed
# first: seeing it is what makes "and none of that meant anything" land.
pg_scan "$LVS_RUNDIR"; pg_state=$?

# "Did not reach a compare" is its own outcome and must never look like a pass:
# an aborted run leaves no OVERALL COMPARISON RESULTS section at all.
if [ ! -s "$LVS_REP" ] || ! grep -q 'OVERALL COMPARISON RESULTS' "$LVS_REP" 2>/dev/null; then
    echo "RESULT: NO VERDICT -- Calibre did not reach a compare."
    echo "        report : $LVS_REP"
    echo "        log    : $LOG"
    echo "        first errors in the log:"
    grep -nE 'ERROR|Cannot|could not be read|referenced but not defined|No matching|SPC[0-9]|INP[0-9]|TVF[0-9]' \
        "$LOG" 2>/dev/null | head -15 | sed 's/^/          /'
    # No compare at all is the earlier failure, so it keeps the exit code -- but
    # say the PG part too, or the next run repeats it.
    [ "$pg_state" = 1 ] && pg_banner
    exit "$RC_NOVERDICT"
fi

echo "== LVS report: $LVS_REP =="
# The verdict banner plus the Error:/Warning: bullets under it, stopping at the
# rule of asterisks that opens the next report section.
verdict=$(awk '/OVERALL COMPARISON RESULTS/{f=1}
               f && /^\*\*\*\*\*\*\*\*\*\*/ {exit}
               f {print; if (++n > 24) exit}' "$LVS_REP")
printf '%s\n' "$verdict" | grep -vE '^\s*$' | head -20
sed -n '/CELL  SUMMARY/,+8p' "$LVS_REP" | head -12

# The PG verdict OVERRIDES CORRECT and INCORRECT alike. A CORRECT reached
# without supplies would be the more alarming of the two, not the safer one.
if [ "$pg_state" = 1 ]; then
    pg_banner
    pg_result_line
    echo "        The report above is not evidence -- fix this first, then re-run."
    echo "        report : $LVS_REP"
    exit "$RC_NOPG"
fi
if [ "$pg_state" = 2 ]; then
    echo "NOTE: the power/ground-text guard could not run -- no ERC summary and no"
    echo "      Calibre log in $LVS_RUNDIR. Confirm by hand that the layout names"
    echo "      [$LVS_POWER] / [$LVS_GROUND]; see CONTRACT.md section 6."
fi
pg_partial_warn

if printf '%s\n' "$verdict" | grep -qw 'INCORRECT'; then
    echo "RESULT: LVS INCORRECT -- layout and source differ. See $LVS_REP"
    exit "$RC_INCORRECT"
fi
if printf '%s\n' "$verdict" | grep -qw 'CORRECT'; then
    echo "RESULT: LVS CORRECT -- layout matches source."
    [ "$LVS_BOX_LEAF" = "1" ] && echo "        Scope: clean MODULO BLACK BOXES; cell interiors are not compared."
    exit "$RC_OK"
fi
echo "RESULT: NO VERDICT -- report has a comparison section but no CORRECT/INCORRECT."
echo "        Inspect $LVS_REP and $LOG."
exit "$RC_NOVERDICT"

#-----------------------------------------------------------------------------
# ISSUE LOG -- the failure classes this flow was iterated against, each one hit
# for real on a padded chiplet before it reached a Calibre compare verdict.
# Every fix is implemented above; do not remove one without reproducing its
# symptom first.
#
# [FIXED] A. PIN-LESS PHYSICAL CELLS ABORT THE SOURCE READ. Bump/bond-pad cells
#    placed directly into the layout are LEF-only: no pins, no Verilog, no CDL.
#    The netlist references them, nothing defines them, and Calibre gives
#    thousands of `No matching ".SUBCKT"` then "Source could not be read" and
#    ABORTS before any compare. Fix: step 3 emits a pin-less empty .SUBCKT per
#    $BONDPAD_CELLS. Class of problem: any cell that exists only as geometry.
#
# [FIXED] B. FRONT-END-ONLY LEAVES MIS-COMPARE WHOLESALE. With no transistors on
#    either side, Calibre auto-flattens the empty layout frames: the layout ends
#    up with zero leaf instances against a source that has all of them, and the
#    entire fabric shows as unmatched (measured: 63 unmatched ports, 554,108
#    unmatched source nets). Fix: step 5 boxes every FE-only leaf so both sides
#    are black boxes compared by port connectivity (after: 2 and 2, with
#    instances matching exactly). NB the block MUST be spliced into the SVRF
#    region -- appended at EOF it lands in the deck's TVF tail and dies with
#    "TVF2 invalid command name".
#
# [FIXED] C. PHYSICAL-ONLY CELLS MUST NOT BE BOXED. Fill, decap and antenna
#    diodes are inserted by P&R and streamed into the GDS, but write_netlist
#    does not emit them, so the source has zero of them. Boxing them leaves them
#    as unmatched LAYOUT instances (measured: 68,842 antenna + 5,530 decap).
#    Fix: $LVS_BOX_EXCLUDE_RE drops them from the box list so their frames
#    auto-flatten and match the source's absence. Extend the regex per PDK.
#
# [FIXED] D. HARD MACROS MUST NOT BE BOXED EITHER, for the opposite reason: they
#    ship a real transistor CDL and a real GDS, so they are the one part of an
#    FE-only run that gets genuine device-level verification. Step 5 subtracts
#    every .SUBCKT defined in $MACRO_CDLS from the box list, which also covers
#    the case where a macro's simulation Verilog was listed in $STDCELL_VLOG and
#    so produced a step-1 stub.
#
# [FIXED] E. DUPLICATE MACRO DEFINITIONS. `v2lvs -s <file>` does NOT read the
#    file -- it only writes an `.INCLUDE "<file>"` line into the output (see
#    `v2lvs -h`). Concatenating the same CDLs in step 3 therefore defined every
#    macro subckt twice and produced thousands of "Duplicate subckt definition"
#    warnings. Fix: step 3 strips those .INCLUDE lines, leaving one
#    self-contained source file. (Pin ORDER is not at stake: v2lvs emits named
#    $PINS connections by default, so the order is never needed. Use -lsp/-lsr,
#    not -s, if a future flow really does need v2lvs to read a SPICE library.)
#    The same class of bug arrives via the env vars: a project naming one
#    library twice, or by two paths to the same file, doubles every subckt in
#    it -- hence the resolve-then-dedupe on all three lists.
#
# [FIXED] I. A .GLOBAL NAME THAT IS A MACRO'S INTERNAL NET. `.GLOBAL VDD VSS`
#    is correct for cells and wrong for a hard macro that uses one of those
#    NAMES for something other than the chip supply. `.GLOBAL` is unscoped: it
#    merges every net of that name in every .SUBCKT of the source into one.
#    Vendor macros routinely bring their real supplies out as `VDDE`/`VSSE` and
#    keep `VDD`/`VSS` for internal nodes; a POWER-GATED macro's internal `VSS`
#    is the SWITCHED (virtual) ground, on the far side of the power-gate footers
#    from the real one. Merging them fabricates a short across the switch, in
#    the SOURCE ONLY -- the layout keeps them apart, because in silicon there is
#    a transistor between them.
#
#    MEASURED, on a 323,124-instance chiplet with two power-gated via-ROMs
#    (2026-08-10): 34 unmatched instances, 44 unmatched nets, 70 device property
#    errors and 436 net discrepancies, ALL of them inside the two ROMs, plus a
#    source-side `Net VSS` carrying +1,980 connections over the layout's (~990
#    internal taps per ROM). The design and the layout were both correct. The
#    SRAMs on the same die were untouched because their top .SUBCKT declares VDD
#    and VSS as real ports, which makes the merge a no-op.
#
#    WHY IT IS SO EXPENSIVE TO FIND: Calibre reports no SHORT, ERC stays clean,
#    and every symptom is inside the macro -- so it reads as "the vendor's GDS
#    and CDL disagree", which is a different and much worse conclusion.
#
#    Fix: $LVS_GLOBAL_NETS is now its own knob (default `$LVS_POWER
#    $LVS_GROUND`, so nothing changed for existing projects; empty emits no
#    .GLOBAL at all), and preflight runs a structural scan of every $MACRO_CDLS
#    file -- for each name in the list, is it USED inside the macro while NOT a
#    port of that macro's top .SUBCKT? The top is found structurally (the
#    .SUBCKT no other .SUBCKT instantiates), so the check needs no naming
#    convention and no per-PDK list, and a macro that declares the name .GLOBAL
#    itself is exempt. Dropping a name is only safe if the netlist wires that
#    supply explicitly; otherwise rename the internal net in a PROJECT-LOCAL
#    COPY of the CDL and point MACRO_CDLS at the copy.
#
# [FIXED] G. TOOL DROPPINGS IN THE INVOKER'S DIRECTORY. Both v2lvs and Calibre
#    write into the CURRENT directory (v2lvs a multi-MB v2lvs.log, the deck its
#    relative svdb/ and ERC outputs). Run from a source tree, they litter it.
#    Fix: resolve every input path, then cd into $LVS_RUNDIR before step 1, so
#    everything a run produces is inside the run directory.
#
# [GUARDED HERE, FIXED IN P&R] F. POWER/GROUND NET NAMING. A P&R signoff stream
#    typically carries NO PG text: the foundry GDS-out map has
#    `NAME <layer>/PIN` and no `NAME <layer>/SPNET`, so the special-route supply
#    grid streams out unnamed and cannot equate to anything on the source side.
#    First seen as the mild version -- ~2 unmatched nets per side, 2 "missing"
#    layout ports, bulk-pin flags on macro transistors -- which is what made it
#    look like a footnote. It is not. On a memory-heavy design the same missing
#    text stopped supply-dependent device recognition working and produced
#    4,084,884 unmatched layout objects (measured, 2026-08-10): ~2M loose SRAM
#    pass-gates plus ~2M inverters, from an otherwise sound comparison.
#    THE FIX IS UPSTREAM: re-stream the same routed database with an extended
#    GDS-out map -- ASIC/lvs-flow/lvs_pg_emit.tcl, `make lvs_pg_gds`, then
#    `make lvs_batch LVS_PG=1`. Read-only on the database, new filename, so the
#    tapeout deliverables are untouched. (A PG-explicit source netlist,
#    `write_netlist -include_pwr_gnd -phys` plus dropping step 3's .GLOBAL, is
#    the matching change on the other side; change one side at a time.)
#    WHAT THIS FILE ADDS is step 6b: the run now refuses to present a verdict it
#    knows is meaningless, and exits 6 instead of 1. Do NOT paper over it with
#    `LVS IGNORE PORTS` or bulk-check suppression -- that manufactures a CORRECT
#    that means nothing.
#
# [FIXED IN THE GDS-OUT MAP] H. LEF OBSTRUCTION STREAMED AS METAL. The general
#    hazard of a Front-End-only PDK, and the one that wastes the most time,
#    because every symptom points somewhere else.
#
#    SYMPTOMS, in the order you will meet them:
#      - millions of unmatched layout objects, dwarfing anything the design
#        could plausibly contain;
#      - almost no top-level layout ports resolved (1 of 52, in the case this
#        was found on) while the source has all of them;
#      - ONE supply resolves and the other does not, so ERC reports POWER fine
#        and GROUND missing, or the reverse;
#      - a single net with an absurd connection count (6,147,666, measured).
#
#    CHECK THIS FIRST, before any of it: the report's `.shorts` file, for a
#    SUPPLY-TO-SUPPLY entry (`SHORT n. VDD - VSS`). It names both texts, gives
#    their coordinates, and prints the shorting path as polygons. If it is
#    there, everything above is one downstream consequence and there is no
#    point debugging any of it. Two supplies merged into one net also stops
#    SRAM bitcell recognition dead -- a 6T cell whose supply and ground are the
#    same node is not a 6T cell -- which is where the millions of unmatched
#    objects come from.
#
#    CAUSE. `write_stream -output_macros` streams LEF abstracts for cells with
#    no Back-End GDS, and foundry GDS-out maps put `LEFOBS` on the SAME GDS
#    layer as real metal. A LEF OBS is a routing BLOCKAGE, not a manufactured
#    shape, and an abstract flattens the real cell into one covering rectangle
#    per layer. Pad spacers, which are obstruction and nothing else, then tile
#    into a continuous sheet around the die that shorts every net reaching a
#    pad. The shells lack devices AND fabricate connectivity; `LVS BOX` handles
#    the first problem and is silent about the second.
#
#    FIX: `lvs_pg_emit.tcl` moves LEFOBS to a scratch GDS layer the deck never
#    reads (LVS_PG_STRIP_OBS=1, on by default), keeping LEFPIN. It is a map
#    change; the design is not touched. WHAT IT COSTS: the pad ring then has no
#    geometry at all in an FE-only stream, so pad-ring power connectivity is
#    NOT verified by LVS and cannot be without Back-End IO cell GDS. A clean
#    run after this fix does not cover the pad ring. Say so when quoting it.
#-----------------------------------------------------------------------------
