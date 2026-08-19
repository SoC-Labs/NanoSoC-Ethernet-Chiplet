#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# asic_stage_report.sh — one markdown block per ASIC stage, for the CI summary
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# The ASIC flow is a multi-HOUR job. Watching a spinner for five hours and then
# reading a 40,000-line log is not a report. This emits a small markdown table
# after each stage so GitHub's job summary shows the numbers that decide whether
# the run is worth continuing — WNS, cell count, DRC, PG opens — as they land.
#
# REPORT-ONLY, NEVER GATES. Every extraction tolerates a missing or truncated
# file and prints `n/a`. A stage that genuinely failed is caught by the
# Makefile's own artefact assertions; this script must not add a second,
# fuzzier verdict on top of them, and must never fail a job by itself.
#
# Usage:  asic_stage_report.sh <syn|place|cts|route> [>> $GITHUB_STEP_SUMMARY]
#
# Env:
#   ASIC_DIR       default ASIC/genus-innovus
#   BASELINE_DIR   a previous run's directory to diff against. Default is the
#                  newest ASIC_DIR/baseline_* — set to "" to disable.
#-----------------------------------------------------------------------------
set -uo pipefail

STAGE="${1:-}"
[ -n "$STAGE" ] || { echo "usage: $0 <syn|place|cts|route>" >&2; exit 2; }

ASIC_DIR="${ASIC_DIR:-ASIC/genus-innovus}"
BLOCK="${BLOCK:-nanosoc_eth_chiplet_pads}"
REP="$ASIC_DIR/reports"
OUT="$ASIC_DIR/outputs"

if [ -z "${BASELINE_DIR+x}" ]; then
    # Prefer the newest completed runs/ directory (the new per-iteration layout,
    # see scripts/ci/new_run.sh); fall back to the older baseline_* dirs.
    BASELINE_DIR=$(ls -d "$ASIC_DIR"/runs/*/ 2>/dev/null | sort | tail -1)
    [ -n "$BASELINE_DIR" ] || BASELINE_DIR=$(ls -d "$ASIC_DIR"/baseline_* 2>/dev/null | sort | tail -1)
    BASELINE_DIR="${BASELINE_DIR%/}"
fi
BREP="${BASELINE_DIR:+$BASELINE_DIR/reports}"

# --- extractors -------------------------------------------------------------
# Each prints a value or "n/a". None may exit non-zero.

# report_timing_summary lays SETUP out as:
#     # SETUP                  WNS    TNS   FEP
#     #------------------------------------------
#      View : ALL            0.068  0.000     0
# so take the first "View : ALL" AFTER the "# SETUP" banner. Anchoring on the
# banner matters: the file repeats "View : ALL" under later sections with the
# columns blank, and a naive grep picks one of those and reports nothing.
timing() {  # timing <repfile> <field 1=WNS 2=TNS 3=FEP>
    local f="$1" n="$2"
    [ -s "$f" ] || { echo "n/a"; return 0; }
    awk -v n="$n" '
        /^# SETUP/       { in_setup = 1; next }
        in_setup && /^ *View : ALL/ {
            if (NF >= 3 + n && $(3 + n) != "") { print $(3 + n); exit }
        }
    ' "$f" 2>/dev/null | head -1 | grep . || echo "n/a"
}

area_field() {  # area_field <1=instcount 2=totalarea>
    local f="$REP/${BLOCK}_imp_area.rep" n="$1"
    [ -s "$f" ] || { echo "n/a"; return 0; }
    awk -v b="$BLOCK" -v n="$n" '
        $1 == b { print (n == 1 ? $(NF-1) : $NF); exit }
    ' "$f" 2>/dev/null | grep . || echo "n/a"
}

# Trust the report's OWN trailer ("Total Violations : N Viols.") ahead of counting
# record lines. A case-SENSITIVE `^[A-Z]+:` count silently undercounts, because
# some violation keywords are mixed case (`EndOfLine:`), which also shifts every
# percentage derived from the total. Fall back to a case-INSENSITIVE count only
# when the trailer is missing.
drc_total() {
    local f="${1:-$REP}/${BLOCK}_imp_drc.rep"
    [ -s "$f" ] || { echo "n/a"; return 0; }
    local t
    t=$(grep -oE 'Total Violations[ ]*:[ ]*[0-9]+' "$f" 2>/dev/null | tail -1 | grep -oE '[0-9]+$')
    if [ -n "$t" ]; then echo "$t"
    else grep -cE '^[A-Za-z]+:' "$f" 2>/dev/null || echo "n/a"; fi
}
# `grep -c` prints "0" AND exits 1 when there are no matches, so the obvious
# `grep -c ... || echo n/a` prints BOTH — garbling the table precisely when the
# count is zero, i.e. when the news is good. Guard the file test separately and
# swallow only the exit status.
drc_bondpad() {
    local f="${1:-$REP}/${BLOCK}_imp_drc.rep"
    [ -s "$f" ] || { echo "n/a"; return 0; }
    grep -c 'Blockage of Cell BuPAD' "$f" 2>/dev/null || true
}
drc_pg_bp() {
    local f="${1:-$REP}/${BLOCK}_imp_drc.rep"
    [ -s "$f" ] || { echo "n/a"; return 0; }
    grep -c 'Special Wire of Net V.* & Blockage of Cell BuPAD' "$f" 2>/dev/null || true
}

# check_connectivity CAPS its message list (1000 by default) and says so in the
# file: "1000 total info(s) created." Once saturated the count is a LOWER BOUND,
# and a delta between a capped run and an uncapped one is not a measurement at
# all — so a capped count is labelled (CAPPED) in the table.
# For a true count, re-run: check_connectivity -error 200000 -warning 200000
pg_opens() {
    local f="${1:-$REP}/${BLOCK}_imp_connectivity.rep"
    [ -s "$f" ] || { echo "n/a"; return 0; }
    local n; n=$(grep -c 'has special routes with opens' "$f" 2>/dev/null || true)
    if grep -qE '^ *[0-9]+ total info\(s\) created' "$f" 2>/dev/null; then
        echo "$n (CAPPED)"
    else
        echo "$n"
    fi
}

# HOLD IS NOT IN timing_summary_*.rep AT ALL.
#
# `report_timing_summary` with no options emits "# SETUP", "# DRV" and
# "# Clock checks" sections and NOTHING for hold — the tool even labels its own
# closing line `timing.setup.wns`. A design deep in hold violation therefore
# reads as "timing closed, 0 failing endpoints" from that file alone. The hold
# numbers exist only in the stage log's "Hold mode" table, so parse that.
#
# Field 2 of the table is the "all" column: WNS / TNS / Violating Paths.
hold_field() {  # hold_field <logdir> <WNS|TNS|Violating>
    local d="$1" key="$2" lg
    # Pick the log by CONTENT, not mtime: logs/ also collects LEC selftest logs
    # and anything else a tool drops there, and the newest is often not the P&R
    # run. Both the Hold-mode and DRV tables live in the same stage log.
    lg=$(grep -lE "^\|[ ]*Hold mode" "$d"/*.log 2>/dev/null | xargs -r ls -t 2>/dev/null | head -1)
    [ -n "$lg" ] && [ -s "$lg" ] || { echo "n/a"; return 0; }
    awk -v k="$key" '
        /Hold mode/ { inblk = 1 }
        inblk && $0 ~ k {
            n = split($0, f, "|")
            gsub(/ /, "", f[3])
            if (f[3] != "") { val = f[3] }
        }
        END { print (val == "" ? "n/a" : val) }
    ' "$lg" 2>/dev/null | tail -1
}

drv_field() {  # drv_field <logdir> <max_cap|max_tran>
    local d="$1" key="$2" lg
    # Pick the log by CONTENT, not mtime: logs/ also collects LEC selftest logs
    # and anything else a tool drops there, and the newest is often not the P&R
    # run. Both the Hold-mode and DRV tables live in the same stage log.
    lg=$(grep -lE "^\|[ ]*Hold mode" "$d"/*.log 2>/dev/null | xargs -r ls -t 2>/dev/null | head -1)
    [ -n "$lg" ] && [ -s "$lg" ] || { echo "n/a"; return 0; }
    awk -v k="$key" '$0 ~ k && /\|/ { n=split($0,f,"|"); gsub(/ /,"",f[3]); if(f[3]!="") v=f[3] }
                     END { print (v=="" ? "n/a" : v) }' "$lg" 2>/dev/null
}

antenna() {
    local f="$REP/${BLOCK}_imp_antenna.rep"
    [ -s "$f" ] || { echo "n/a"; return 0; }
    grep -q 'No Violations Found' "$f" && echo "clean" || echo "VIOLATIONS"
}

gds_size() { [ -s "$OUT/$BLOCK.gds" ] && du -h "$OUT/$BLOCK.gds" | cut -f1 || echo "n/a"; }

# delta with an explicit sign, blank when either side is unavailable
delta() {
    local new="$1" old="$2"
    case "$new$old" in *n/a*) echo "" ; return 0 ;; esac
    awk -v a="$new" -v b="$old" 'BEGIN{ d = a - b; printf (d > 0 ? "+%g" : "%g"), d }'
}

row() { printf '| %s | %s | %s | %s |\n' "$1" "$2" "${3:-—}" "${4:-}"; }

# --- emit -------------------------------------------------------------------
echo "### ASIC stage: \`$STAGE\`"
echo
[ -n "$BREP" ] && [ -d "$BREP" ] \
    && echo "_baseline: \`$(basename "$BASELINE_DIR")\`_" \
    || echo "_no baseline to compare against_"
echo
echo "| metric | this run | baseline | delta |"
echo "|---|---|---|---|"

case "$STAGE" in
  syn)
    row "gate netlist" "$([ -s "$OUT/${BLOCK}_gate_power.v" ] && du -h "$OUT/${BLOCK}_gate_power.v" | cut -f1 || echo n/a)"
    row "CPF supply-net patch" \
        "$(grep -q 'update_power_domain' "$OUT/${BLOCK}_gate1.cpf" 2>/dev/null && echo 'present' || echo 'MISSING — add_fillers will insert nothing')"
    ;;
  place|cts|route)
    case "$STAGE" in
      place) T=timing_summary_01_place.rep ;;
      cts)   T=timing_summary_03_cts_opt.rep ;;
      route) T=timing_summary_05_route_opt.rep ;;
    esac
    nw=$(timing "$REP/$T" 1); ow=$(timing "${BREP:-/nonexistent}/$T" 1)
    nt=$(timing "$REP/$T" 2); ot=$(timing "${BREP:-/nonexistent}/$T" 2)
    nf=$(timing "$REP/$T" 3); of=$(timing "${BREP:-/nonexistent}/$T" 3)
    row "setup WNS (ns)"    "$nw" "$ow" "$(delta "$nw" "$ow")"
    row "setup TNS (ns)"    "$nt" "$ot" "$(delta "$nt" "$ot")"
    row "failing endpoints" "$nf" "$of" "$(delta "$nf" "$of")"
    # Huge negatives at `place` are expected, not alarming: the clock tree does
    # not exist yet, so every path is timed against an ideal-network estimate.
    # The number worth reading at this stage is the DELTA against baseline.
    ;;
esac

if [ "$STAGE" = route ]; then
    nd=$(drc_total);        od=$(drc_total   "$BREP")
    nb=$(drc_bondpad);      ob=$(drc_bondpad "$BREP")
    np=$(drc_pg_bp);        op=$(drc_pg_bp   "$BREP")
    no=$(pg_opens);         oo=$(pg_opens    "$BREP")
    # Hold and DRV come from the LOG, not the timing summary — see hold_field().
    BLOG="${BASELINE_DIR:+$BASELINE_DIR/logs}"
    row "**hold WNS (ns)**"          "$(hold_field "$ASIC_DIR/logs" 'WNS')"        "$(hold_field "${BLOG:-/nonexistent}" 'WNS')"
    row "**hold TNS (ns)**"          "$(hold_field "$ASIC_DIR/logs" 'TNS')"        "$(hold_field "${BLOG:-/nonexistent}" 'TNS')"
    row "**hold violating paths**"   "$(hold_field "$ASIC_DIR/logs" 'Violating')"  "$(hold_field "${BLOG:-/nonexistent}" 'Violating')"
    row "DRV max_tran nets(terms)"   "$(drv_field  "$ASIC_DIR/logs" 'max_tran')"   "$(drv_field  "${BLOG:-/nonexistent}" 'max_tran')"
    row "DRV max_cap nets(terms)"    "$(drv_field  "$ASIC_DIR/logs" 'max_cap')"    "$(drv_field  "${BLOG:-/nonexistent}" 'max_cap')"
    row "instances"                  "$(area_field 1)"
    row "total cell area (um2)"      "$(area_field 2)"
    row "DRC total"                  "$nd" "$od" "$(delta "$nd" "$od")"
    row "DRC vs bond-pad blockage"   "$nb" "$ob" "$(delta "$nb" "$ob")"
    row "DRC PG-ring vs bond pad"    "$np" "$op" "$(delta "$np" "$op")"
    row "PG opens (lower bound)"     "$no" "$oo" "$(delta "$no" "$oo")"
    row "antenna"                    "$(antenna)"
    row "GDSII"                      "$(gds_size)"
    echo
    echo "> DRC here is Innovus \`check_drc\` on a GDS whose \`gds_merge_list\` holds"
    echo "> only the 8 memory macros — standard cells, IO drivers and bond pads are"
    echo "> empty references. It is a routing/PG check, **not signoff DRC**."
fi
echo
exit 0
