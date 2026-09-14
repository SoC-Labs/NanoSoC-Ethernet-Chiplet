# Why the violations survive, and what the flow must do about it

    measured 2026-09-14 from vt2ctl / vt3pg / vt4drv / vt6opt logs and reports
    goal     port the toolkit to a new project and inherit as few of these as possible
    status   mechanisms established; flow changes implemented alongside (see §5)

## 1. The three classes, and what each really is

| class | count on vt6opt | what it is | root mechanism |
|---|---|---|---|
| setup | 2 endpoints, WNS -0.010 | CPU -> 32-bit ADP address incrementer -> `adp_addr_reg[27..31]/SI` (the load-enable mux input of an SDF flop) | post-route optimisation ran on **low-effort extraction** and could not see the moves that close it |
| max_transition | 102 nets (190 in-flow) | 38 % hold-fix buffers (`FE_PHC*`, mostly `CKBD0/CKBD1`), 35 % flop outputs on the debug bus | CTS hold repair inserts the weakest buffers in the library; real routing then exposes 554 DRV; the last opt pass to run decides who wins |
| DRC (design-caused) | 7 rulechecks / 9 results | 2 ECO sites (VIA1 single-cut + 25 nm same-net M1 notch on a resized cell's pin) and 4 PG residue sites | Innovus's LEF has no MINSTEP on M1 and no via-redundancy rule; the residue pass is marker-driven and check_drc raised no marker |

The other 32 rulechecks on every stream, including the shipped one, are
collateral configuration: 29 density rules on an unfilled design (fill is the
foundry's), the 691-result PO.R.8 black-boxing artefact, and two informational
checks. A new project inherits those from the tech pack and the fill-owner
decision, not from the design.

## 2. Setup: the optimiser was working from the wrong parasitics

    vt4drv route stage         tQuantus (effort medium), 5 extractions -- its
                               early print of `extract_rc_effort_level = low`
                               is the PRE-ROUTE engine's value, read before
                               route_design; I first mistook it for the
                               post-route engine (corrected 2026-09-14 pm)
    in-flow post-route result  -0.104 ns / 5 endpoints
    same DB, signoff extraction -0.149 ns / 9 endpoints
    opt_signoff on those        -0.010 ns / 2 endpoints, 21 resizes, 0 inserts

The project already asks the route stage for +0.110 ns setup margin
(design.mk:1274) and the attribute took (read back 0.11). The optimiser still
ended at -0.104 with "setup improving moves not found". opt_signoff, on QRC
parasitics, found 21 resizes worth 140 ps on the same paths. The difference is
the extraction engine, not the optimiser -- but not the engine I first named.
The flow never sets `extract_rc_effort_level`; the tool's own post-route
default at this node with a QRC deck is tQuantus (medium), and every route run
in this lineage ran it (vt3pg 4 starts, vt4drv 5, vt7flow 4, all in their
logs). The stage's early line `extract_rc_effort_level = low` is the PRE-ROUTE
engine's value, printed before route_design. So the 45 ps is tQuantus versus
signoff qrc, not cap table versus qrc. The consequence is unchanged: the
optimiser's numbers were 45 ps kinder than the ones that judge it. vt7flow,
routed with ROUTE_EXTRACT_EFFORT=medium made explicit, reproduced vt3pg's
in-flow result to the picosecond -- which is how the misreading was caught.

The two endpoints that remain are a genuine structural path - a ripple-shaped
32-bit incrementer feeding a flop's SI pin at 100 MHz - and 10 ps at signoff.
That is inside what a setup target of 0.110 buys once the optimiser can see
the real numbers, and inside what an ECO stage closes if it cannot.

## 3. max_transition: manufactured by hold repair, and the pass order decides

    CTS end (hold_02_cts.rep)         4 max_tran violations
    route_design done                 554 (2548 terms), worst -0.493
    after opt_design -drv             1
    after opt_design -setup -hold     61  -> 76 at the gate, 190 across views

The CTS stage's hold pass inserted 34,736 `FE_PHC` cells: 17,397 `CKBD0` and
11,854 `CKBD1`, the two weakest buffers in tcbn65lp. Pre-route they look fine;
after detail routing 554 nets violate the design's 0.300 ns limit. The `-drv`
pass repairs all but one - and the `-setup -hold` pass that follows re-breaks
61, because hold repair post-route may only INSERT (opt_hold_allow_resize is
"auto" = off post-route) and inserts the same weak cells. WHICHEVER PASS RUNS
SECOND KEEPS ITS GAIN, as 4_route.tcl already records. The route stage's DRV
pass then reports "54 nets: gain is not enough, 3: location check rejected" -
the leftovers are flop-driven debug-bus nets at 96 % local density.

Two facts a new project should know before inheriting this:

- `set_max_transition 0.300 [current_design]` is THIS design's choice
  (constraints.sdc:1194), measured at +7.9 utilisation points. The library's
  own default is 0.7657. The example project's constraints carry no such line,
  so a new project starts with a quarter of this pressure.
- The measured arms (design.mk F29): setup_hold 195, setup_then_hold 230,
  hold_then_setup 305 max_tran; drv_then_setup_hold 190. No ordering of
  in-flow passes closes it. What does close it is an optimiser that fixes DRV
  on signoff parasitics and is told not to create new ones while fixing hold:
  `opt_signoff -drv` with `opt_signoff_check_drv_from_hold_views true`.

## 4. DRC: two sites Innovus cannot see, four it chose to tolerate

ECO-caused (vt6opt only): two sites, five results.

    (1249.45, 826.70)   M1.S.1 sliver 0.191x0.025 + VIA1.R.4:M1 single cut
    (1269.05, 882.90)   M1.S.1 sliver 0.177x0.025 + M1.S.5 + VIA1.R.4:M1

Each is a VIA1 dropped on the pin of a resized cell (ND2D1 -> CKND2D1 has a
different pin shape) whose M1 landing pad now sits 25 nm from the pin's own
metal - a same-net notch. The tech LEF's M1 block carries a spacing table, an
EOL property, AREA and MINENCLOSEDAREA, and NO MINSTEP; via redundancy is a
recommended rule not in LEF at all. So check_drc read 3 before and 3 after,
correctly by its own rules. The ECO stage cannot rely on Innovus to see these;
it must (a) ask NanoRoute for redundant cuts (`use_multi_cut_via_effort high`)
so the R.4 half does not arise, and (b) hand the result to Calibre against its
parent as a control, which is what caught it.

PG residue (vt4drv, inherited): four sites at 1 result each - M5.A.2 (an M5
island 0.12x0.25 um at (553.66,426.10)), VIA3.R.4:M4, VIA4.R.2__R.3,
VIA4.R.4:M4. The prune declares sites where two cuts cannot fit (both axes
under 0.300 um) and tolerates them under PG_V4R4_EXPECT {0 2} /
PG_V3R4_EXPECT {0 60}; Calibre finds 1 each, inside budget. The island was not
one the residue pass reported: that pass is driven by check_drc markers, and
Innovus's LEF M5 AREA is 0.052 um2 against a 0.030 um2 island it did not
flag - most likely because Innovus merges it into an adjacent stripe that
Calibre does not. A rule-view mismatch, budgeted and documented rather than
automated away.

## 5. What changes in the flow (implemented alongside this note)

1. **Extraction effort is set, read back and refused if it did not take**
   (`pnr_extraction_setup`, knob `ROUTE_EXTRACT_EFFORT`, default `medium`
   when the tech pack declares a QRC deck -- which is what the tool already
   chose; the knob makes it explicit and refusable, and `high` / `signoff`
   are now one variable away. vt7high tests `high`). The layer map the signoff engine
   needs is now a tech-pack key (`qrc_layer_map`) shipped with tsmc65.
2. **A signoff ECO stage** (`make eco`, `flow/innovus/5_eco.tcl`): opt_signoff
   setup+hold+DRV on signoff parasitics, told not to create DRV while fixing
   hold, followed by an ECO route asking for redundant cuts, re-fill, the
   in-flow checks judged against the PARENT run's own manifest rather than
   hand-typed baselines, a database, and the signoff artefacts. Its gate says
   in writing that check_drc is not signoff DRC.
3. **The example project carries the measured-good knobs explicitly** -
   ROUTE_OPT_MODE, the setup/hold targets, the extraction effort - with the
   measurement beside each, so a port starts from what was measured rather
   than from the toolkit's conservative defaults (hold-only post-route opt,
   tool-default extraction).
4. **Documented, not automated:** the PG residue rule-view mismatch (§4), and
   the design's 0.300 ns transition limit.

## 6. Validation

A cts -> route -> eco run from vt3pg's placed database with the changed flow,
then LEC / DRC / LVS against vt4drv and vt6opt as controls. Recorded in the
run's own manifests; summarised in docs/tapeout/72-* when it lands.
