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
    --help|-h)         usage; exit "$RC_OK" ;;
    "")                ;;
    *) printf 'usage: %s [--check | --source-only | --help]\n' "$0" >&2
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
   IO or pads. Front-End simulation Verilog is sufficient -- those leaves are
   compared as black boxes on port connectivity, which catches missing
   instances, mis-wired pins, shorts and opens in the routing. Hard macros that
   ship a real CDL still compare all the way down to transistors.
   It is NOT full signoff LVS: cell interiors are unverified by construction.
   Say "clean modulo black boxes", never "signoff clean".
EOF
    return "$RC_OK"
}

preflight; pf=$?
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
    # write_netlist emits no explicit power/ground, so the supplies must be
    # declared global for every leaf power pin to tie to them by name.
    echo ".GLOBAL $LVS_POWER $LVS_GROUND"

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

# "Did not reach a compare" is its own outcome and must never look like a pass:
# an aborted run leaves no OVERALL COMPARISON RESULTS section at all.
if [ ! -s "$LVS_REP" ] || ! grep -q 'OVERALL COMPARISON RESULTS' "$LVS_REP" 2>/dev/null; then
    echo "RESULT: NO VERDICT -- Calibre did not reach a compare."
    echo "        report : $LVS_REP"
    echo "        log    : $LOG"
    echo "        first errors in the log:"
    grep -nE 'ERROR|Cannot|could not be read|referenced but not defined|No matching|SPC[0-9]|INP[0-9]|TVF[0-9]' \
        "$LOG" 2>/dev/null | head -15 | sed 's/^/          /'
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
# [FIXED] G. TOOL DROPPINGS IN THE INVOKER'S DIRECTORY. Both v2lvs and Calibre
#    write into the CURRENT directory (v2lvs a multi-MB v2lvs.log, the deck its
#    relative svdb/ and ERC outputs). Run from a source tree, they litter it.
#    Fix: resolve every input path, then cd into $LVS_RUNDIR before step 1, so
#    everything a run produces is inside the run directory.
#
# [OPEN -- FIXABLE ONLY IN P&R, NOT HERE] F. POWER/GROUND NET NAMING. If
#    write_netlist ran without -include_pwr_gnd and the stream carries no PG
#    text, the layout supply grid is unnamed and cannot equate to the source's
#    global supplies. It surfaces as ~2 unmatched nets per side, 2 "missing"
#    layout ports, and bulk-pin flags on macro transistors whose bodies tie to
#    the supplies. It is a LABELLING artifact, not a connectivity error, and on
#    an otherwise clean run it is the sole reason the verdict reads INCORRECT.
#    The fix is `write_netlist -include_pwr_gnd -phys` (and dropping the .GLOBAL
#    in step 3), on the P&R side. Do NOT paper over it with `LVS IGNORE PORTS`
#    or bulk-check suppression -- that manufactures a CORRECT that means nothing.
#-----------------------------------------------------------------------------
