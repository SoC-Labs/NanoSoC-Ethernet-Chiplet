### Congestion and Timing Setting
# design_process_node is NOT set here. 2_pnr_setup.tcl:44 already sets it from
# $process_node (config.tcl:4), and this file is sourced afterwards - so a
# hardcoded 65 here silently overrode the parameterised value, and retargeting
# the node in config.tcl would have been a no-op with no warning.
set_db place_global_cong_effort auto
set_db place_global_timing_effort high

### Uniform Cell Distribution and fill gap
set_db place_global_uniform_density true
set_db place_detail_legalization_inst_gap 2

### Placement Mode Config
set_db place_design_floorplan_mode false

### SIGNAL ROUTING IS CONFINED TO M1-M7. M8/M9 ARE POWER-ONLY.
#
# THE RC MODEL FOR M9 IS WRONG BY 3.8x AND THERE IS NO CORRECT ONE ON THIS SITE.
# Measured, layer by layer:
#
#     layer   tech LEF (real)   ARM cap table (what the timer believes)
#     M8          0.900                 0.900     ok
#     M9          3.400                 0.900     3.8x TOO THIN
#     AP          1.450                 1.450 (as "M10")
#
# The design's tech LEF and DRC deck are both 9M_6X1Z1U: six thin layers, one
# thick (M8, 0.9um "Z") and one ULTRA-thick (M9, 3.4um "U"). The mmmc's RC
# corners use ARM's 1p9m_6x2z cap tables, which model BOTH top layers at 0.9um.
# A 3.4um conductor modelled as 0.9um has its resistance badly overstated.
#
# No correct dataset exists here. ARM's tree ships six cap tables and none is
# 6X1Z1U. TSMC's QRC package (util/T-N65-CL-SP-036-V1_11a) resolves to a single
# 9-metal dataset whose own README defines it as "M2-M7:Mx + M8-M9:My" — i.e.
# 6X2Y, both top layers the same, also not this stack. It belongs on the
# collateral request alongside the missing standard-cell GDS and CDL.
#
# WHAT THIS SETTING DOES ABOUT IT. `design_top_routing_layer` bounds "global and
# detail routing" (Cadence DBcom root.html) — SIGNAL routing only. add_stripes
# and route_special are SPECIAL routing and are unaffected, so the M8/M9 power
# grid is untouched. Confining signals to M1-M7 means the mis-modelled layer
# carries power only, where the error shows up in IR estimates rather than in
# every setup path. Previously nothing bounded routing at all and NanoRoute put
# 35,937um of signal on M8.
#
# HONEST ABOUT THE TRADE: this removes two routing layers, so congestion may
# rise and this could COST setup rather than gain it. The justification is
# accuracy, not speed — the -0.242ns setup measured on 2026-08-07 was measured
# against a model known to be wrong on the layer carrying the longest routes,
# and the error direction is PESSIMISTIC (over-resistive M9). Revert this line
# if congestion regresses materially; it is one line and independent of
# everything else.
# MEASURED 2026-08-08. 7 was one layer too conservative. The RC error is on M9
# ONLY -- the table above shows M8 at 0.900 in BOTH the tech LEF and the ARM cap
# table, i.e. modelled correctly; M9 is the 3.4 vs 0.9 outlier. Confining signals
# to M1-M7 therefore gave up an accurately-modelled layer to avoid an
# inaccurate one, and it cost real timing. Same CTS database, one knob:
#     M1-M7   setup WNS -0.487   TNS -44   FEPS 319
#     M1-M8   setup WNS -0.286   TNS -14   FEPS 146
# with DRC 64 and PG 350/1518 bit-identical, and 32 s LESS wall time. M9 and AP
# still carry zero signal, which is the whole point.
set_db design_top_routing_layer 8
