# LAUNCH CARD — eth chiplet GDS run, evening of 2026-08-19

## THE DELIVERABLE, agreed in advance
**A stream plus an honest verdict. NOT a green route gate.**
`4_route.tcl:2266-2267` — `hard` AND `soft` both call `flow_fail`. Eight soft
budgets sit at absolute zero and fp1505 exceeded all eight, including setup
FEP 1444 / WNS -0.759 which nothing tonight touches. A failing gate is the
EXPECTED outcome. Nobody waives a budget at 2am to make it green.

## LAUNCH POINT: `4ddf4be`  (NOT 2029e0a — see below)
    flist sha256   14fda93eb7221c02...  == gate1r's proven-green input, byte-identical
    bscan files    0 tracked            (2029e0a carries 4; 85bbfd1 is its ancestor)
    power_plan.tcl / floorplan.tcl / .io   byte-identical to HEAD
    toolkit pin 8e23478, tidelink pin e6aaa82   identical to HEAD
    contains d93331f corner rotation, c7e488f VDDIO/VSSIO, bc63efc+bfbccf6 island feed,
             c94306c C2 revert
Losing bscan from this stream costs nothing physical.

## G9 — NOT FIXED. Measured failing 12:15 TODAY on our exact pin.
    pgfix-B, toolkit 8e23478 (== our pin), __byname fix present at pnr_utils.tcl:416-430
    -> PLACE-FAIL: could not resolve 21 of 21 macros ... strict mode - stopping here
    real=0:04:51.  place_macro_insts.rep enumerated 21 macros fine at 12:12:51,
    so get_db worked; the by-name fallback ran and still missed.
    The names are why: u_..._u_soc/u_network_core/u_region_dmem_0_u_sram_u_sram_gen_rf_16k.u_rf_sp_hdf
    -- they mix `/`, `_` AND `.`.

**THE UNIT TEST IS A FALSE GREEN. Do not cite it.**
`tclsh test/run-tests.tcl common/pnr_utils.test` -> 95/95 passed, but it runs
against `t_install_macro_stub`. The stub says the fix works; real Innovus says
it does not.

**UNBLOCK: `PLACE_MACRO_PG_CHECK=0` on the make line.** Justified, not waved:
the compensating whole-die check ran in that same 12:15 session and passed --
FP-SHORT 0 (rail-to-rail, HARD at >0), FP-ISLAND 0 of 18, VERDICT PASS.
What is lost is the `crossings` metric (an uncut ladder spanning a macro edge),
not an actual touch. Do NOT set PLACE_STRICT=0 instead - that downgrades every
place check.

## PRE-LAUNCH, in order
    git switch -c gds-run-20260819 4ddf4be
    # the toolkit SHORT: class guard MUST still be in the worktree - grep -c 'SHORT:'
    # ASIC/asic-toolkit/flow/innovus/4_route.tcl  >= 1. Commit it for provenance.
    # commit both submodule pins; push to the LIVE remote (git ls-remote, not the tracking ref)
    # write the G7 predictions file and commit it
    ps -eo cmd | grep -E 'innovus|genus' | grep -v grep        # must be empty
    setsid nohup make -C ASIC/eth-chiplet all RUN_TAG=<tag> PLACE_MACRO_PG_CHECK=0 > <log> 2>&1 &

## THREE WATCH CHECKPOINTS
    T+6min    grep -cE 'SDC-202|TIM-303|TUI-66' build/<tag>/logs/syn.log
              -> you learn the SDC verdict SIX MINUTES into a 1h44 stage. Kill on any hit.
    T+1h50    grep -a PLACE-FAIL build/<tag>/work/innovus.log*      (the G9 window)
    T+3h05    the CTS hold-latency gate is fatal

## THREE HARD CONSTRAINTS WHILE IT RUNS
1. **No superproject commits between launch and route finishing.** Provenance is
   collected PER STAGE from the live tree; a commit at T+2h gives four stages with
   three different SHAs. During-run lanes work in a `git worktree`, never the live tree.
2. **No `.sdc` touched between syn finishing and place starting** or place hard-fails
   (`sdc-check` is a place prerequisite). Freeze `ASIC/genus-innovus/inputs/` entirely.
3. **Route budgets are read at route-stage start (T+3h+).** Change them before launch
   or after route completes -- never in between.

## TIMING
Run is strictly serial, one seat: syn 1h44 / place 1h05 / cts 1h16 / route 1h15
= 5h25 worst case measured on fp1505's scope.
**Launch by 19:00 (recommended). 21:00 hard latest.** After that a single stage
failure means no stream by morning.
CONTENTION IS THE RISK, NOT LICENCES: 41 seats, 0 in use. But load is 45+ on 16
cores from Vivado. A second Innovus roughly doubles wall clock. Re-check `ps`
immediately before launch -- from ps, not from a status report.

## RECOVERY IS BOUNDED (a DB is saved at every stage boundary)
    dies in syn    -> full 1h44, no intra-syn checkpoint
    dies in place  -> make place PLACE_FROM_DB=fplan, ~50 min
    dies in cts    -> <=76 min, placement not repeated
    dies in route  -> <=75 min, CTS not repeated
    gate only      -> 0. The GDS is already on disk; fix the gate and re-evaluate.
