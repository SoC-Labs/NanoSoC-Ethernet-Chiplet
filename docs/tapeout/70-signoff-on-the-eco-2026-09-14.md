# Signoff on the opt_signoff ECO — vt6opt-20260911

    measured 2026-09-14, all numbers from artefacts in this repository
    subject   ASIC/eth-chiplet/build/vt6opt-20260911  (opt_signoff -setup on vt4drv)
    controls  vt4drv-20260910 (its parent) and rc4-20260829 (the SHIPPED stream)

## Why there are controls at all

The audit of 2026-09-11 found NO signoff evidence for any `vt*` build — no DRC,
no LVS, no signoff STA, no foundry antenna, no rail. Only Innovus in-flow
checks, which the route stage's own gate text already says are not signoff.

So "vt6opt has N violations" answers nothing on its own: it cannot separate what
the ECO did from what it inherited. Every number below is a DELTA against a
control that had to be created first. Both controls are new work — this is the
first Calibre DRC and the first LVS ever run on this lineage.

## LEC — PASS

    golden   vt1-20260902/outputs/nanosoc_eth_chiplet_pads_gate_power.v
    revised  vt6opt-20260911/outputs/nanosoc_eth_chiplet_pads_pnr.v
    compare_points=61599 equivalent=61599 nonequivalent=0 abort=0 notcompared=0
    unmapped_extra_golden=0 unmapped_extra_revised=0

`notcompared=0` is the load-bearing number: nothing was skipped. The 21
instances opt_signoff resized or VT-swapped preserved function.

## DRC — the ECO costs 5 results, all at M1

Like-for-like over the RULECHECK RESULTS STATISTICS section only:

    rc4-20260829     (shipped, imec-graded clean)   32 failing rulechecks
    vt4drv-20260910  (parent, pre-ECO)              36
    vt6opt-20260911  (after the ECO)                39

ATTRIBUTABLE TO THE ECO — three rules, five results, none present in the parent:

    M1.S.1        0 -> 2   minimum-spacing rule (read the value in your own
                           PDK -- it is not reproduced here). Both are narrow
                           slivers, clustered at (1249.35, 826.69) and
                           (1268.96, 882.92).
    M1.S.5        0 -> 1
    VIA1.R.4:M1   0 -> 2

Standard-cell GDS is not in the merge list, so these are ROUTING M1 —
`route_eco -fix_drc` is the plausible source, not the resizes. The ECO cleared
nothing.

NOT the ECO's: M5.A.2, VIA3.R.4:M4, VIA4.R.2__VIA4.R.3 and VIA4.R.4:M4 are
present in the PARENT at identical counts (1 each). They are the PG work's
residue, and 1 each is what 380/51/727 in-flow markers came down to. Comparing
vt6opt against rc4 alone would have mis-attributed all four to the ECO.

PO.R.8 is 691 (4282) in every one of the three, unchanged — the known
black-boxing artefact.

## LVS — INCORRECT, and it is NOT the ECO, NOT the lineage

                        Ports    Nets (layout/source)      MN devices        incorrect nets
    rc4-20260829        52/52    2,926,534 / 2,295,621     4,138,107/4,108,264      99
    vt4drv-20260910     52/52    2,967,261 / 2,336,513     4,138,107/4,108,264      99
    vt6opt-20260911     52/52    2,967,255 / 2,336,509     4,138,107/4,108,264      99

THE SHIPPED STREAM HAS THE SAME RESULT. Same verdict, same 99 nets, identical
device counts. The ECO moved 4-6 nets and nothing else. The vt lineage's extra
~40k layout nets against rc4 are the added PG vias.

The 99 are PG and top-level IO — VDD, VSS, VDDIO, VSSIO, plus SE and SWDCK —
and VDDIO shows 2 connections in layout against 13 in source, missing every
`XuPAD_VDDIO_*:VDDPST`. That is the pad ring, which is the scope the LVS
preflight already declares itself outside of: "clean modulo black boxes and
modulo the pad ring" (docs/tapeout/45-measured-status-2026-08-18.md §4.3, which
also records that the one build ever measured came back INCORRECT).

So this is the design's standing state, newly confirmed on three streams rather
than one. It is not a finding against the ECO. It IS a finding against the
belief that rc4's LVS was clean.

## The gate that missed the DRC regression

The ECO script reported "drc 3, baseline 3, no regression" and wrote the
database. It compares Innovus `check_drc`, which reads routing, the power grid,
blockages and merged cell GDS — not the rules an ECO breaks at M1. Calibre says
36 -> 39. The gate is not mis-tuned, it is the wrong instrument, and it now
writes `reports/SIGNOFF_DRC_REQUIRED.txt` saying so.

## Two counting errors made and corrected while producing this

1. Grepping rc4's whole summary file pulled in its `(BY CELL)` section and gave
   "108 failing rulechecks", which would have had this ECO reported as an
   improvement on the shipped stream instead of 7 rulechecks worse. Diff the
   RULECHECK RESULTS STATISTICS section ONLY.
2. Reading "112,475 filler insts added" from the parent's log against 41,622
   from the ECO's suggested a 31% under-fill. Counting the surviving population
   in each database instead gives 76,773 and 88,482 — the ECO has MORE fillers,
   in smaller cells. A log line counts cumulative adds across passes, not what
   is in the database.

## What is still not measured

Signoff STA (Tempus), foundry antenna — which has no CI stage to run in at all,
not merely an unrun one — and rail/IR-drop, whose dynamic half has no PDK data
source on this site.

## Reproducing

    make eco-emit RUN_TAG=vt6opt-20260911          # GDS + netlist from the DB
    make lec-pnr  RUN_TAG=vt6opt-20260911 SYN_RUN_TAG=vt1-20260902
    make drc      RUN_TAG=vt6opt-20260911
    make drc      RUN_TAG=vt4drv-20260910          # the control

LVS does not run from this flow. Nothing here builds the `_lvs.gds` it needs,
and the genus-innovus side does not inherit eth-chiplet/design.mk, so four
overrides must be passed by hand — LVS_PG_DB (its default is the bare block
name, which exists in no run of this flow), LVS_PG_MERGE_GDS, ROMLIBS_DIR and
LVS_ROM_CDL_DIR. The preflight names every one of them without taking a
licence, which is the flow working; needing them at all is not.

    cd ASIC/genus-innovus
    R=<abs path to the run>
    make lvs_pg_gds LVS_RUN=$R LVS_PG_DB=$R/work/<block>_routed LVS_PG_MERGE_GDS="<6 mem gds> $R/romlibs/*/*.gds2"
    make lvs_batch  LVS_RUN=$R ROMLIBS_DIR=$R/romlibs LVS_ROM_CDL_DIR=$R/lvs_rom_cdl
