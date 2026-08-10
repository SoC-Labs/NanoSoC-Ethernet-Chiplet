## Snapshot the POST-PLACE database. See the note in route_setup.tcl: every
## stage writes the same DB name, so without this only the final post-route
## state survives and any CTS experiment costs a full re-run from placement.
## 3_pnr_clock.tcl sources this file right after its `read_db`, so the design
## here is exactly the post-place state.
##
##   resume from here:  cd work && innovus -stylus
##                      source ../scripts/config.tcl ; read_db ${block_name}_placed
write_db ${block_name}_placed

### Buffer Cells
## Left commented DELIBERATELY, for now. The attributes are real
## (innovus/etc/rdaDesign.tcl) and the patterns do match this library —
## tcbn65lp has CKBD0..CKBD24 and CKND0..CKND24. Enabling them constrains
## CCOpt's clock-cell choice, which changes the clock tree and therefore the
## hold profile; that is a physical change to evaluate on its own, not to
## bundle with a hold-repair experiment. For reference, this run's clock tree
## used 41,228 CKBD0, 5,648 CKND0 and 3,126 CKBD1 — plus 3,290 BUFFD1, a
## general-purpose buffer that a cts_buffer_cells list would have excluded.
#set_db cts_buffer_cells {CKB*}
### Inverter Cells
#set_db cts_inverter_cells {CKN*}

set_db cts_delay_cells {DEL*}

### OCV IS ENABLED HERE, BEFORE ccopt — NOT in route_setup.tcl.
#
# THE BUG THIS FIXES. After building the tree, ccopt_design writes the clock
# tree's insertion delay back as a NEGATIVE source latency, so I/O constraints
# written against an ideal clock stay valid. It does that per (clock, view), and
# it emits only the sides the analysis mode has. With OCV still OFF at that
# moment, min and max are not yet separated, and for default_analysis_view_hold
# it wrote the -min form ONLY:
#
#     set_clock_latency -source -early -min -rise -1.07637 [get_pins CLK]
#     set_clock_latency -source -late  -min -rise -1.07637 [get_pins CLK]
#
# route_setup.tcl then turned OCV on. Min and max delay analysis separate, and a
# HOLD check needs the launch clock's MIN path and the capture clock's MAX path.
# Launch finds -1.076. Capture finds nothing and uses ZERO. Seen directly on a
# real path (reports/holdexp2_before.rpt):
#
#                        Capture       Launch
#         Src Latency:+    0.000       -1.108      Slack:= -1.086
#
# Every hold check in the design lost ~1.1 ns of pure fiction. Cost:
#     hold WNS -1.167 ns, TNS -66,212 ns, 96,545 violating paths
#     +37,407 instances / +90,682 um2 of hold buffers chasing skew that is
#     not there, driving density 83.6% -> 92.2%, which then blocked DRV repair
#     (153 max_tran nets: "gain not enough" / "location check rejected")
# and it was invisible, because report_timing_summary emits NO hold section --
# its own closing line is labelled `timing.setup.wns`.
#
# PROOF the mechanism is real: supplying the missing -max for `clk` alone (by
# hand, on the _cts snapshot) moved worst-case hold -1.086 -> -0.808, and the
# worst path relocated to rmii_ref_clk, which carries the identical
# -min-only signature. All four written-back clocks have it.
#
# WHAT WAS TRIED AND REJECTED:
#   - Two-sided delay corners in the .mmmc. NO EFFECT: the writeback was
#     byte-identical and post-CTS hold unchanged. set_clock_latency -min/-max is
#     an SDC property of the CLOCK, not of the delay corner. (Kept anyway, as
#     they are more explicit; see the note in the .mmmc.)
#   - Mirroring -min onto -max after CTS. Works, but the values change with
#     every clock tree, and report_clock_timing does not separate min from max,
#     so deriving them reliably is guesswork. Enabling OCV first makes ccopt
#     emit both sides itself, which is the real fix rather than a repair.
#
# VERIFY AFTER ANY CTS RUN — this must not silently regress:
#     grep -v '^@file' <log> | grep -A1 'View: default_analysis_view_hold' \
#       | grep -c ' -max '        # must be > 0
set_db timing_analysis_type ocv

# CPPR — clock reconvergence pessimism removal. OCV above derates launch and
# capture clock paths INDEPENDENTLY, including the segment they physically
# share, so a hold path whose two flops sit on the same buffer sees pessimism
# that cannot exist in silicon. Nothing in this flow removed it: `cppr` had zero
# occurrences in scripts/ before 2026-08-09. OCV without CPPR is the maximally
# pessimistic combination.
#
# Spelling checked against /eda/cadence/innovus/doc/UGcom/Timing_Analysis.html
# for this exact tool version (21.11-s130_1). Default threshold is 20 ps.
#
# Here, NOT after ccopt, for the same reason as the OCV line above: enabling the
# analysis mode after the tree is built cost 96,545 fictional hold violations
# and ~37,000 hold buffers on 2026-08-06 (see the note at the top of this file).
set_db timing_analysis_cppr true

# All FOUR derate arms, always. Innovus inherits the last defined value for any
# arm left unspecified, so setting two of them silently mis-derates the other
# two (documented at 3b_pnr_cts_eval.tcl:747). These are the values already
# carried as EVC_DERATE_* defaults at 3b_pnr_cts_eval.tcl:130-133 - they existed
# and were simply never applied, because EVC_DERATE defaulted to 0.
#
# Expected effect, to be checked against the next post-CTS hold report: hold was
# 75 failing endpoints at WNS -0.008 (8 ps), which is BELOW the 20 ps CPPR
# threshold, so most of it should disappear. Setup gain will be much smaller -
# the -0.195 setup path is wire-dominated across the die with little common
# clock to recover. Enabling CPPR and derate together is roughly slack-neutral
# by design: the same margin, honestly accounted for rather than doubled.
set_timing_derate -early -data  0.95
set_timing_derate -late  -data  1.05
set_timing_derate -early -clock 0.97
set_timing_derate -late  -clock 1.03