#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# verif/bscan/run_gate.sh -- the GATE-LEVEL boundary-scan gate, under VCS.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#   source ../../set_env.sh && ./run_gate.sh        # ~4 min, most of it compile
#
# WHAT IT GATES
#   The ROUTED nanosoc_eth_chiplet_pads netlist, contacted at its 48 package
#   pads and nowhere else. run.sh proves the boundary-scan RTL. This proves a
#   pattern shifts through the cells Genus mapped, Innovus placed and CTS
#   clocked -- reached from outside the chip, with NRST held low.
#
# WHICH NETLIST, AND THE TRAP IN THE OTHER ONE
#
#   The same P&R run writes the routed netlist twice:
#     ..._pnr.v      3064 modules, none of which shadow a library cell.
#                    18,833 of its instances are written WITHOUT supply pins.
#     ..._pnr_pg.v   every instance carries .VDD()/.VSS() -- and the file opens
#                    with 375 EMPTY MODULE DECLARATIONS for library cells
#                    (`module BUFFD1 (I,Z,VSS,VDD); ... endmodule`, no body),
#                    because Innovus wrote it with -write_supply0_supply1.
#
#   Hand the _pg file to VCS after the vendor library and every one of those 375
#   declarations OVERRIDES the real model -- VCS says so, 375 times, as
#   Warning-[OPD], and then compiles, elaborates, links and runs. MEASURED here
#   2026-08-19: the entire design simulates as z, every pad reads z, and the
#   bench reports 52 failures that have nothing to do with the design. It is the
#   cleanest possible instance of a run that measured nothing.
#
#   So this gate simulates the PLAIN netlist, PG-completed by the toolkit's own
#   transform (flow/verify/gls/pg_complete.py) into a copy under $BUILD -- the
#   same file ASIC/gls-netlist/Makefile's fp1505_cc item simulates, and the
#   configuration that already boots CPU1 out of a mask ROM. ASIC/ is never
#   written. Step 2 below refuses ANY netlist that shadows a library cell, so
#   the trap above cannot be re-entered silently by pointing
#   BSCAN_GATE_NETLIST somewhere else.
#
#   PG completion IS A DECLARED DEVIATION and must travel with any result: the
#   file simulated is not byte-identical to the file being taped out. It ties
#   supply pins the writer omitted to a local supply1/supply0, which is what the
#   vendor's own non-PG model of the same cell does, and the report naming every
#   instance touched is left at $BUILD/pg_dut.txt.
#
# WHY THE VERDICT IS NOT JUST `$?`
#   simv exits 0 on $finish whatever the bench decided. The failure modes that
#   actually happen are the silent ones -- see the paragraph above for one that
#   happened on the first run of this very script. So the gate requires the
#   machine-readable summary line to EXIST, to say PASS with fails=0, to report
#   every test run, and to report a plausible NUMBER OF COMPARISONS.
#
# EXIT CODES
#   0  pass          2  setup problem (no netlist, no models, no VCS, map drift)
#   1  test failure  3  compile/elaboration failure
#
# ENV
#   BSCAN_GATE_NETLIST     default .../build/bscan-probe/outputs/..._pnr.v
#   BSCAN_GATE_BUILD       default $HERE/build_gate  (relocatable)
#   BSCAN_GATE_MIN_CHECKS  default 4000
#   BSCAN_GATE_TIMEOUT     simv wall clock, default 1800
#   BSCAN_GATE_BUILD_TIMEOUT   vcs wall clock, default 3600
#   VCS                    default `vcs` on PATH
#   extra args go to simv, e.g.  ./run_gate.sh +seed=7 +clk
#-----------------------------------------------------------------------------
# NOT `set -u`: the component set_env.sh scripts reference positional args.
set -eo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHIPLET_HOME="$(cd "$HERE/../.." && pwd)"

VCS="${VCS:-vcs}"
BUILD="${BSCAN_GATE_BUILD:-$HERE/build_gate}"
MIN_CHECKS="${BSCAN_GATE_MIN_CHECKS:-4000}"
TOP=tb_bscan_gate

[ -f "$CHIPLET_HOME/set_env.sh" ] && source "$CHIPLET_HOME/set_env.sh" >/dev/null

setup_fail() { echo "== bscan-gate SETUP FAIL: $* =="; exit 2; }

command -v "$VCS" >/dev/null 2>&1 || \
    setup_fail "'$VCS' is not on PATH. Set VCS=/path/to/vcs."
command -v python3 >/dev/null 2>&1 || setup_fail "python3 is not on PATH."

# ---------------------------------------------------------------------------
# 0. SITE COLLATERAL. NOT SPELLED HERE -- this repository is public, and an
#    absolute mount paired with a revision-coded release directory is together
#    an inventory of what this site is licensed to hold. ASIC/common.mk defines
#    each of these exactly once; read them from there, and resolve the two
#    release-coded PDK paths with this repository's own resolver, exactly as
#    ASIC/gls-netlist/Makefile does. A pointer cannot drift; a second copy is a
#    second thing to keep in step.
# ---------------------------------------------------------------------------
common_mk_var() {
    sed -n "s/^export $1[[:space:]]*?*=[[:space:]]*//p" "$CHIPLET_HOME/ASIC/common.mk" \
        2>/dev/null | head -1
}
MEM_BASE="${MEM_BASE:-$(common_mk_var MEM_BASE)}"
TSMC_65_HOME="${TSMC_65_HOME:-$(common_mk_var TSMC_65_HOME)}"
PHYS_IP="${PHYS_IP:-$(common_mk_var PHYS_IP)}"
export TSMC_65_HOME PHYS_IP

PDK_PATHS_SH="$CHIPLET_HOME/ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh"
[ -f "$PDK_PATHS_SH" ] || setup_fail "no $PDK_PATHS_SH"
STDCELL_V="$(bash "$PDK_PATHS_SH" stdcell-vlog 2>/dev/null || true)"
IOCELL_V="$( bash "$PDK_PATHS_SH" io-vlog      2>/dev/null || true)"
[ -n "$STDCELL_V" ] && [ -r "$STDCELL_V" ] || \
    setup_fail "pdk_paths.sh could not resolve a readable stdcell-vlog (TSMC_65_HOME=${TSMC_65_HOME:-unset})"
[ -n "$IOCELL_V" ] && [ -r "$IOCELL_V" ] || \
    setup_fail "pdk_paths.sh could not resolve a readable io-vlog (TSMC_65_HOME=${TSMC_65_HOME:-unset})"

# CAVEAT THAT TRAVELS WITH EVERY CLAIM MADE FROM A RUN OF THIS, and it is the
# same one ASIC/gls-netlist/Makefile carries: the simulation Verilog above is an
# OLDER CELL REVISION than the Liberty the design was timed against, for both
# libraries. This is a FUNCTIONAL check. It says the boundary register shifts.
# It says nothing whatever about whether it closes timing.
MEM_V=(
    "$MEM_BASE/rf_01k/rf_01k.v"
    "$MEM_BASE/rf_08k/rf_08k.v"
    "$MEM_BASE/rf_16k/rf_16k.v"
    "$MEM_BASE/rf_32k/rf_32k.v"
    "$MEM_BASE/flash_cache_data/flash_cache_data.v"
    "$MEM_BASE/flash_cache_tag/flash_cache_tag.v"
)
ROMLIBS="$CHIPLET_HOME/ASIC/romlibs"
ROM_V=( "$ROMLIBS/cc_rom/rom_via.v" "$ROMLIBS/eth_rom/eth_rom_via.v" )
# ASIC/romlibs is evidence in an open investigation: READ here, never written.
ROM_RCF=( "$ROMLIBS/cc_rom/rom_via_verilog.rcf" "$ROMLIBS/eth_rom/eth_rom_via_verilog.rcf" )

# PAD70GU / PAD70NU are physical-only cells with no Verilog anywhere in this
# PDK. Innovus writes them with an EMPTY connection list, so an empty-module
# declaration cannot change behaviour. Same file the LEC flow uses.
BONDPAD_STUBS="$CHIPLET_HOME/ASIC/genus-innovus/scripts/lec/bondpad_stubs.v"

PROBE_OUT="$CHIPLET_HOME/ASIC/eth-chiplet/build/bscan-probe/outputs"
NETLIST_SRC="${BSCAN_GATE_NETLIST:-$PROBE_OUT/nanosoc_eth_chiplet_pads_pnr.v}"
PAD_TABLE="$CHIPLET_HOME/src/rtl/bscan/pad_table.json"
PG_COMPLETE="$CHIPLET_HOME/ASIC/asic-toolkit/flow/verify/gls/pg_complete.py"

for f in "$NETLIST_SRC" "$BONDPAD_STUBS" "$PAD_TABLE" "$PG_COMPLETE" \
         "${MEM_V[@]}" "${ROM_V[@]}"; do
    [ -r "$f" ] || setup_fail "missing or unreadable: $f"
done
grep -qsE '^module[[:space:]]+nanosoc_eth_chiplet_pads[[:space:]]*\(' "$NETLIST_SRC" || \
    setup_fail "$NETLIST_SRC does not define module nanosoc_eth_chiplet_pads"
grep -qsE '^module[[:space:]]+nanosoc_eth_chiplet_bscan[[:space:]]*\(' "$NETLIST_SRC" || \
    setup_fail "$NETLIST_SRC contains no nanosoc_eth_chiplet_bscan -- this is a netlist from
   a run WITHOUT boundary scan inserted, and every test below would fail for
   that reason and no other. Point BSCAN_GATE_NETLIST at a bscan-probe build."

# ---------------------------------------------------------------------------
# STALE-BUILD TRAP. VCS re-runs yesterday's simv whenever today's compile fails
# in a way a script does not notice, and the bench then reports a green for a
# netlist that is not on disk any more. The build directory is destroyed on
# every run; there is no incremental mode and there should not be one.
# ---------------------------------------------------------------------------
rm -rf "$BUILD"
mkdir -p "$BUILD"
# The repository's .gitignore names `build/`, not `build_gate/`, and this gate
# leaves ~220 MB of csrc/simv.daidir behind. A self-ignoring stamp keeps that out
# of `git status` without a tracked change, and it is rewritten on every run
# because the directory it lives in is destroyed on every run.
printf '*\n' > "$BUILD/.gitignore"

# ---------------------------------------------------------------------------
# 1. CHAIN-MAP DRIFT GUARD.
#
#    tb_bscan_gate.sv hard-codes the chain indices it checks, because at the
#    package there is no generated header to hand it names -- the DUT is a
#    netlist with 48 pins. Those literals are DERIVED from pad_table.json by
#    contract section 6, so re-derive them here and refuse to compile if they
#    have drifted. A TB testing a ring order the table no longer describes would
#    still pass most of its tests and would mean nothing.
# ---------------------------------------------------------------------------
echo "== re-deriving the chain map from src/rtl/bscan/pad_table.json =="
set +e
python3 - "$PAD_TABLE" "$HERE/tb_bscan_gate.sv" <<'ENDOFPY'
import json, re, sys

pad_table, tb_path = sys.argv[1], sys.argv[2]
CELLS = {'input': ['obs'], 'output': ['data'],
         'bidir': ['oe', 'data', 'obs'], 'opendrain': ['oe', 'obs']}

pads = sorted(json.load(open(pad_table))['pads'], key=lambda p: p['ring_index'])
chain = []                                  # (chain_index, pad_dict, cell_kind)
for p in pads:
    for c in CELLS[p['kind']]:
        chain.append((len(chain), p, c))

tb = open(tb_path).read()
errs = []

def want(name, value):
    """Require `localparam ... name ... = value` to appear verbatim in the TB."""
    pat = re.compile(r'\b' + re.escape(name) + r'\b[^\n=]*=\s*' + re.escape(value))
    if not pat.search(tb):
        errs.append("%s should be %s -- the TB does not say that" % (name, value))

def arr(idxs):
    return "'{" + ",".join(str(i) for i in idxs) + "}"

def inst(p):
    return p['inst'][len('uPAD_'):] if p['inst'].startswith('uPAD_') else p['inst']

want('N_CELLS', str(len(chain)))

out_cells = [i for i, p, c in chain if p['kind'] == 'output']
in_names  = ['NRST_I', 'TEST_I', 'SE_I', 'RMII_CRS_DV', 'RMII_RXD1', 'RMII_RXD0',
             'RMII_REF_CLK', 'TL_RX_0', 'TL_RX_1', 'TL_RX_2', 'TL_RX_3',
             'TL_CLK_RX', 'TL_RX_4', 'TL_RX_5', 'TL_RX_6', 'TL_RX_7']
in_cells  = sorted(i for i, p, c in chain if c == 'obs' and inst(p) in in_names)
bidir_oe  = [i for i, p, c in chain if c == 'oe' and p['kind'] == 'bidir']
i2c_oe    = [i for i, p, c in chain if c == 'oe' and p['kind'] == 'opendrain']

def qspi(kind):
    # the list index is the QSPI_IO PIN BIT, not the chain order.
    out = []
    for b in range(4):
        m = [i for i, p, c in chain
             if c == kind and p['port'] == 'QSPI_IO' and p['idx'] == b]
        if len(m) != 1:
            errs.append("expected exactly one %s cell for QSPI_IO[%d], found %d"
                        % (kind, b, len(m)))
            return None
        out.append(m[0])
    return out

want('NOUT', str(len(out_cells)))
want('NIN',  str(len(in_cells)))
want('NBOE', str(len(bidir_oe)))
want('OUT_CELL',      arr(out_cells))
want('IN_CELL',       arr(in_cells))
want('BIDIR_OE_CELL', arr(bidir_oe))
want('I2C_OE_CELL',   arr(i2c_oe))
qo, qd = qspi('oe'), qspi('data')
if qo: want('QSPI_OE_CELL',   arr(qo))
if qd: want('QSPI_DATA_CELL', arr(qd))

# The pad NAMES the TB prints for the 15 output cells, in chain order. A wrong
# name here would mis-attribute a real failure to the wrong pin.
exp_names = [p['pad'] for i, p, c in chain if p['kind'] == 'output']
body = re.search(r'function automatic string out_name.*?endfunction', tb, re.S)
if not body:
    errs.append("the TB has no out_name() function")
else:
    got = [g for g in re.findall(r'return\s+"([^"]+)"', body.group(0)) if g != '?']
    if got != exp_names:
        errs.append("out_name() lists %s\n       pad_table says   %s" % (got, exp_names))

if errs:
    print("   CHAIN MAP DRIFT -- tb_bscan_gate.sv no longer matches pad_table.json:")
    for e in errs:
        print("     * " + e)
    sys.exit(1)
print("   %d cells; OUT_CELL %s" % (len(chain), arr(out_cells)))
print("   IN_CELL  %s" % arr(in_cells))
print("   chain map agrees with pad_table.json")
ENDOFPY
map_rc=$?
set -e
if [ "$map_rc" -ne 0 ]; then
    echo "== bscan-gate SETUP FAIL: the TB's chain map has drifted from pad_table.json =="
    echo "   Re-derive the literals in tb_bscan_gate.sv, or explain the deviation there."
    exit 2
fi

# ---------------------------------------------------------------------------
# 1b. IDCODE VINTAGE.
#
#     The netlist is a snapshot and its ID register holds whatever
#     IDCODE_VALUE was when it was built. If today's RTL says something else,
#     the bench is right to keep expecting the netlist's value -- but nobody
#     should have to discover that from a red. So both are printed whenever
#     they differ, with the override that resolves it.
# ---------------------------------------------------------------------------
BSCAN_RTL="$CHIPLET_HOME/src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv"
RTL_ID="$(sed -n "s/.*IDCODE_VALUE[[:space:]]*=[[:space:]]*32'h\([0-9a-fA-F_]*\).*/\1/p" \
          "$BSCAN_RTL" 2>/dev/null | head -1 | tr -d '_' | tr 'A-F' 'a-f')"
TB_ID="$(sed -n "s/.*IDCODE_INTENDED[^=]*=[[:space:]]*32'h\([0-9a-fA-F_]*\).*/\1/p" \
          "$HERE/tb_bscan_gate.sv" | head -1 | tr -d '_' | tr 'A-F' 'a-f')"
if [ -n "$RTL_ID" ] && [ -n "$TB_ID" ] && [ "$RTL_ID" != "$TB_ID" ]; then
    echo "== NOTE: the RTL's IDCODE_VALUE (32'h$RTL_ID) is not what this bench expects (32'h$TB_ID) =="
    echo "   That is not automatically wrong: the netlist under test is a snapshot and holds"
    echo "   the value it was BUILT with. If this netlist was regenerated after the RTL"
    echo "   changed, re-run with  +idcode=$RTL_ID  and move the constant in the TB."
fi

# ---------------------------------------------------------------------------
# 2. THE LIBRARY-SHADOWING GUARD.
#
#    See the header. A netlist that redeclares library cells as empty modules
#    silently replaces the vendor models with nothing, and the simulation runs
#    perfectly while measuring absolutely nothing. VCS reports it only as
#    Warning-[OPD], which is not a stop and is buried in thousands of lines.
#    So it is checked here, by name, against the two libraries actually being
#    compiled -- not against a list of cell names typed into this script.
# ---------------------------------------------------------------------------
echo "== checking the netlist does not shadow the vendor cell libraries =="
set +e
python3 - "$NETLIST_SRC" "$STDCELL_V" "$IOCELL_V" <<'ENDOFPY'
import re, sys
netlist, libs = sys.argv[1], sys.argv[2:]
lib = set()
for f in libs:
    lib |= set(re.findall(r'^module\s+(\w+)', open(f, errors='replace').read(), re.M))
mods = set(re.findall(r'^module\s+(\w+)', open(netlist, errors='replace').read(), re.M))
shadow = sorted(mods & lib)
print("   %d modules in the netlist, %d cells in the two libraries, %d collisions"
      % (len(mods), len(lib), len(shadow)))
if shadow:
    print("   THE NETLIST REDECLARES %d LIBRARY CELLS, e.g. %s"
          % (len(shadow), ", ".join(shadow[:8])))
    sys.exit(1)
ENDOFPY
shadow_rc=$?
set -e
if [ "$shadow_rc" -ne 0 ]; then
    setup_fail "the netlist redeclares library cells.
   Innovus emits those stubs when write_netlist is given -write_supply0_supply1
   (the ..._pnr_pg.v variant). Given to VCS after the vendor library, each one
   OVERRIDES the real model, the design simulates entirely as z, and the run
   reports failures that say nothing about the design. Use the plain ..._pnr.v
   -- this script PG-completes it below -- or strip the stub declarations."
fi

# ---------------------------------------------------------------------------
# 3. PG COMPLETION, MEASURED.
#
#    The plain routed netlist writes ~186k instances with .VDD()/.VSS() and
#    leaves ~19k -- everything P&R inserted, which is the whole clock-tree
#    buffering -- without. The only standard-cell Verilog that matches the
#    first group is the POWER-AWARE library, in which every cell routes its
#    output through the u_power_down UDP (`? x ? : x`), so the second group
#    would drive X and TCK would never reach the boundary register. The
#    toolkit's transform writes a COPY with those pins tied to a local
#    supply1/supply0 and we simulate the copy. ASIC/ is not written.
#
#    A ZERO HERE IS NOT A PASS. pg_complete.py returns 0 cheerfully when it was
#    given no models, so a zero and a clean run are indistinguishable from a
#    measurement that did nothing. On this netlist the answer is ~18,800; a 0
#    means the invocation resolved no cells and is refused.
# ---------------------------------------------------------------------------
SIM_NETLIST="$BUILD/$(basename "${NETLIST_SRC%.v}")_pgc.v"
echo "== PG-completing $(basename "$NETLIST_SRC") into the build directory =="
set +e
python3 "$PG_COMPLETE" --netlist "$NETLIST_SRC" --out "$SIM_NETLIST" \
    --model "$STDCELL_V" --model "$IOCELL_V" --define POWER_PINS \
    --pair VDD:VSS --pair VDDE:VSSE --report "$BUILD/pg_dut.txt" >/dev/null 2>&1
pg_rc=$?
set -e
[ "$pg_rc" -eq 0 ] && [ -r "$SIM_NETLIST" ] || \
    setup_fail "pg_complete.py failed (rc=$pg_rc). See $PG_COMPLETE."
PG_FIXED="$(sed -n 's/.*instances fixed[[:space:]]*:[[:space:]]*//p' "$BUILD/pg_dut.txt" | head -1)"
echo "   $PG_FIXED instance(s) given a local supply pair; report at $BUILD/pg_dut.txt"
if [ "${PG_FIXED:-0}" -eq 0 ] 2>/dev/null; then
    setup_fail "pg_complete.py fixed ZERO instances on a netlist known to need ~18,800.
   That means the invocation resolved no cells at all -- not that the netlist is
   complete. Nothing downstream of this can be believed. Check --model."
fi

# ---------------------------------------------------------------------------
# 4. Stage the ROM content beside simv. The ROM macro models $readmemb their
#    .rcf by BASENAME out of the working directory. The content is irrelevant to
#    boundary scan -- the core never runs here -- but an unfound $readmemb is a
#    warning in a log nobody then trusts.
# ---------------------------------------------------------------------------
for f in "${ROM_RCF[@]}"; do
    if [ -r "$f" ]; then cp -f "$f" "$BUILD/"
    else echo "   note: no $f (ROM arrays stay X; harmless here)"; fi
done

# ---------------------------------------------------------------------------
# 5. Compile.
#
#    +nospecify +notimingcheck: a ZERO-DELAY functional run. It says whether the
#    boundary register shifts through the routed gates. It says NOTHING about
#    whether it closes timing, and it could not -- see the cell-revision caveat
#    at the top. An SDF-annotated run (..._pnr.sdf, 362 MB, sits beside the
#    netlist) is a separate exercise and a separate claim.
# ---------------------------------------------------------------------------
VLOG="$BUILD/vcs.log"
echo "== vcs: compiling $TOP over $(basename "$SIM_NETLIST") ($(du -m "$SIM_NETLIST" | cut -f1) MB) =="
echo "   a couple of minutes; the netlist is ~200k instances"
set +e
( cd "$BUILD" && timeout "${BSCAN_GATE_BUILD_TIMEOUT:-3600}" \
  "$VCS" -full64 -sverilog -timescale=1ns/1ps \
      +nospecify +notimingcheck \
      +define+ARM_UD_MODEL +define+ARM_UD_DP +define+ARM_UD_CP +define+ARM_UD_SEQ \
      +define+INITIALIZE_MEMORY +define+POWER_PINS \
      "$STDCELL_V" "$IOCELL_V" "${MEM_V[@]}" "${ROM_V[@]}" "$BONDPAD_STUBS" \
      "$SIM_NETLIST" "$HERE/tb_bscan_gate.sv" \
      -top "$TOP" -o "$BUILD/simv" -Mdir="$BUILD/csrc" -l "$VLOG" ) >/dev/null 2>&1
vcs_rc=$?
set -e
if [ "$vcs_rc" -ne 0 ] || [ ! -x "$BUILD/simv" ]; then
    echo "== bscan-gate COMPILE FAIL (rc=$vcs_rc) =="
    grep -aE '^(Error|Warning)-\[|^Error|\*E,' "$VLOG" 2>/dev/null | head -25 | sed 's/^/   /'
    echo "   log: $VLOG"
    exit 3
fi

# ---------------------------------------------------------------------------
# 6. Run.
# ---------------------------------------------------------------------------
SLOG="$BUILD/sim.log"
echo "== simv: shifting patterns through the routed boundary register =="
set +e
( cd "$BUILD" && timeout "${BSCAN_GATE_TIMEOUT:-1800}" ./simv -l "$SLOG" "$@" ) >/dev/null 2>&1
sim_rc=$?
set -e
if [ "$sim_rc" -eq 124 ] || [ "$sim_rc" -eq 137 ]; then
    echo "== bscan-gate FAIL: simv was KILLED at ${BSCAN_GATE_TIMEOUT:-1800}s wall clock =="
    echo "   Nothing below can be read as a result. log: $SLOG"
    exit 1
fi

sed -n '/^--- T/,$p' "$SLOG" 2>/dev/null | grep -avE '^\$finish|^ *$' | sed 's/^/   /' || true

# ---------------------------------------------------------------------------
# 7. Verdict -- see "WHY THE VERDICT IS NOT JUST $?" above.
# ---------------------------------------------------------------------------
SUMMARY="$(grep -a '^BSCAN_GATE_SUMMARY:' "$SLOG" 2>/dev/null | tail -1 || true)"
if [ -z "$SUMMARY" ]; then
    echo "== bscan-gate FAIL: the bench printed NO summary line =="
    echo "   It did not reach the end of its stimulus, so there is no verdict to read."
    echo "   simv rc=$sim_rc. log: $SLOG"
    tail -20 "$SLOG" 2>/dev/null | sed 's/^/   /'
    exit 1
fi

VERDICT="$(sed -n 's/^BSCAN_GATE_SUMMARY: \([A-Z]*\).*/\1/p' <<<"$SUMMARY")"
CHECKS="$( sed -n 's/.*checks=\([0-9]*\).*/\1/p'             <<<"$SUMMARY")"
FAILS="$(  sed -n 's/.*fails=\([0-9]*\).*/\1/p'              <<<"$SUMMARY")"
TPASS="$(  sed -n 's/.*tests=\([0-9]*\)\/[0-9]*.*/\1/p'      <<<"$SUMMARY")"
TTOT="$(   sed -n 's/.*tests=[0-9]*\/\([0-9]*\).*/\1/p'      <<<"$SUMMARY")"

echo
echo "== $SUMMARY =="

if [ "$VERDICT" != "PASS" ] || [ "${FAILS:-1}" -ne 0 ]; then
    echo "== bscan-gate FAIL: $FAILS failing comparison(s) across $((TTOT - TPASS)) test(s) =="
    grep -aE '^    FAIL' "$SLOG" | head -25 | sed 's/^/   /'
    echo "   full log: $SLOG"
    exit 1
fi
if [ "${TTOT:-0}" -lt 7 ] || [ "${TPASS:-0}" -ne "${TTOT:-0}" ]; then
    echo "== bscan-gate FAIL: only $TPASS of $TTOT tests passed, and the bench defines >= 7 =="
    echo "   log: $SLOG"
    exit 1
fi
if [ "${CHECKS:-0}" -lt "$MIN_CHECKS" ]; then
    echo "== bscan-gate FAIL: only $CHECKS comparisons were performed (floor $MIN_CHECKS) =="
    echo "   A green over a stimulus this short is not evidence. A zero that measured"
    echo "   nothing is not a zero. log: $SLOG"
    exit 1
fi

echo "== bscan-gate OK: $TTOT/$TTOT tests, $CHECKS comparisons, 0 failures =="
echo "   netlist:  $NETLIST_SRC"
echo "   simulated: $SIM_NETLIST  ($PG_FIXED instance(s) PG-completed -- a declared deviation)"
echo "   log:      $SLOG"
