# max_transition, diagnosed

Companion to `66-rc5-flow-findings.md` **F32**. That entry carries the verdict
and the settings; this file carries the evidence, object by object.

It is a separate file for the reason F31 recorded: `66-rc5-flow-findings.md` is
245,278 bytes at HEAD against `check-vendor-collateral.sh`'s 262,144-byte
`file.size` threshold, and this analysis is 23 KB.

All measurements are on `build/rc6route-20260831` and `build/rc6full-20260831`
artefacts, plus a read-only copy of rc6route's routed database. No run's saved
artefacts were written.


### 1. THE FOUR ARMS, RE-COUNTED FROM THE ARTEFACTS

Counted by parsing data rows out of each run's `reports/drv_05_route_opt.rep` —
not with `grep -c`, which counts lines containing a word and would have counted
this report's *wrapped continuation lines* (long hierarchical names split across
two table rows, with the numeric columns blank) as violations. Cross-checked
against `reports/nanosoc_eth_chiplet_pads_routed.tran.gz`, which is the same
population grouped by net with untruncated names, and which agrees row for row.

| run | route_opt rows | IO rows | internal rows | internal NETS | worst |
|---|---|---|---|---|---|
| `rc5vt-20260829` | 195 | 96 | 99 | 27 | −6.023 |
| `rc6hold-20260831` | 230 | 96 | 134 | 53 | −6.024 |
| `rc6route-20260831` | 305 | 96 | 209 | 77 | −6.024 |
| `rc6full-20260831` | **156** | **0** | 156 | 61 | **−0.132** |

The 195 / 230 / 305 progression and the 96 constant are confirmed. Note the
second-to-last column: **209 rows is 77 nets.** `report_constraint` lists the
driver pin and every violating load pin of the same net separately, so the
endpoint count the gate uses is roughly 2.7x the number of nets to repair.

### 2. THE 96 IS 48 CHIP PINS COUNTED TWICE

Grouped by net, the IO half is **48 nets with exactly 2 violating pins each** —
the top-level port and the pad cell's `PAD` pin, which are the same electrical
node reported under both names. 48 of the design's 52 ports are in it. The slew
census on rc6route's own routed database reproduces the table in
`inputs/pnr_io_drv.sdc`'s header **exactly**:

    6.324 x2   6.321 x2   5.000 x8   3.000 x16   2.000 x18
    1.866 x8   1.200 x2   1.087 x4   0.676 x18   0.593 x18   = 96

That file's documentation needs no correction.

### 3. WHICH RUNS ACTUALLY HAVE THE OVERRIDE — AND A TRAP

| run | `PNR_IO_DRV_OVERRIDE` in env | pinned mmmc names the file | file actually read |
|---|---|---|---|
| `rc5vt-20260829` | (absent) | no | **no** |
| `rc6hold-20260831` | (empty) | no | **no** |
| `rc6route-20260831` | **1** | **no** | **no** |
| `rc6full-20260831` | 1 | yes | **yes** |

`rc6route` printed `PNR_IO_DRV_OVERRIDE  1` in its own launch header while the
mechanism was **structurally absent**: its pinned mmmc (md5 `7ca43955920a`) does
not name the file at all, and its log contains no `pnr_io_drv.sdc:` line. A knob
set in the environment is not a knob that ran — the artefact to check is the
file's own `pnr_io_drv.sdc: max_transition ... -override on ...` line, which only
`rc6full` has.

**And a resume can never fix it.** `read_mmmc` / `init_design` appear 6 times in
`flow/innovus/2_place.tcl` and **zero** times in `3_cts.tcl` and `4_route.tcl`;
the constraint mode is inherited from the database that is read. F29 closed by
offering the IO override to "a route-only resume, about 70 minutes" — that is not
available. It requires a run that executes the place stage.

### 4. WHAT THE INTERNAL VIOLATIONS ARE

**Min-drive cells that acquired a load.** Taking the driver (output) pin of each
of rc6route's 77 internal nets:

    driver drive strength:  D1 x55   D0 x19   D2 x2   D3 x1    (74 of 77 are D0/D1)
    load cells, top four:   CKBD1 x24  CKBD0 x13  BUFFD1 x10  CKBD2 x9

`CKBD0/1/2` are the library's weakest clock buffers, used as datapath delay
elements — what hold repair inserts. **48 of the 76 nets rc6route has and rc5
does not have a CKBD load.** The mechanism: hold repair hangs a delay buffer on
a net whose driver was sized when the net was lighter, and the min-drive driver's
slew goes past 0.300.

**They do not cluster.** 22 unnamed synthesis nets, 14 `u_dmac_0`,
9 `u_network_core`, 8 `u_dap_ss_0`, 8 `u_tidelink`, then single figures across
debug, interconnect, qspi and the chip wrapper. rc6full's 61 redistribute
differently again (dmac 14→3, dap_ss 8→10). Diffuse, not a hotspot — so there is
no floorplan or congestion fix to make.

**They are churn, not a hard set.** rc5's 27 nets and rc6route's 77 share
**one net.** The population is re-created from scratch by whichever optimisation
arm ran. Chasing individual nets is pointless.

**None of them exceeds the library's own limit.** `default_analysis_view_setup`
→ `default_delay_corner_max` → `default_libset_max` → `tcbn65lpwc.lib`, whose
`default_max_transition` is **0.7657 ns**. The worst internal violator in any arm
is **0.543 ns**, so every internal row is inside the library's characterised slew
range and its delay is interpolated, not extrapolated. What they violate is the
project's own `set_max_transition 0.300 [current_design]`, deliberately 2.55x
tighter. That constraint is not negotiable — `inputs/constraints.sdc:1191` prices
it and shows it is worth 25 ps on the critical path and removed the last
post-route setup ECO — but it does mean this row is a *target*, not a silicon
risk. (The IO half is the opposite: 6.324 ns is genuinely past the library's last
characterised point, which is why that half has to be re-stated rather than met.)

### 5. THE POPULATION IS MANUFACTURED BY THE FLOW

Endpoints per stage, IO / internal. (The place-stage report is space-separated,
not pipe-delimited like the later ones; a parser written for one silently
returns zero rows on the other, so this table uses both.)

| run | place_opt | cts_opt | route_opt | post_fill (GATE) |
|---|---|---|---|---|
| `rc5vt-20260829` | 94 / 2 | 96 / 357 | 96 / 99 | 195 |
| `rc6hold-20260831` | — | 96 / 242 | 96 / 134 | 227 |
| `rc6route-20260831` | — | — | 96 / 209 | **325** |
| `rc6full-20260831` | **0 / 4** | 0 / 50 | 0 / 156 | 155 |

**rc6full leaves placement with four internal violating endpoints, worst
−0.030.** Everything else is added later: 4 → 50 at CTS → 156 at route. The
internal count is a product of clock-tree and post-route optimisation, not a
property of the netlist or the floorplan.

### 6. THE ORDERING DEFECT

`opt_design -post_route` runs its own DRV phases. rc6route's route log, showing
each `GigaOpt DRV Optimization` block as the violating-net count on the first and
last row of its own table, with what it spent (the separate
`*info: Total N net(s) ... can't be fixed` line is a different quantity — nets
attempted and failed — and is quoted in section 7):

    nets 715 -> 42    +101 buf +155 inv  522 resize   density 85.58 -> 85.64%
    nets  79 -> 44      +2 buf   +7 inv   24 resize
    nets 327 -> 327      0        0        0          (a block that did nothing)
    nets 327 -> 105    +30 buf +119 inv  145 resize   density -> 86.03%

and then, **with no DRV pass after them**: `GigaOpt WNS recovery`,
`GigaOpt harden opt (Recovery)`, `GigaOpt Optimization in post-eco TNS mode
(Recovery)`. The last DRV pass left 105 nets; the run reports 125. The residue of
the recovery passes is what the final count is made of.

### 7. THE OVERRIDE IS NOT COSMETIC — IT UNPOISONS THE OPTIMISER

Without it the DRV engine's worklist contains the 48 unfixable pad nets, and it
says so in every block:

    rc6route:  *info: 13 net(s): Could not be fixed as the violating term's net is not routed.
               *info: 29 net(s): Could not be fixed because it is multi driver net.
    rc6full:   *info: Total 2 net(s) ...   (zero multi-driver in three of its four blocks)

`wViol` in rc6route's DRV tables is **−6.02** — I2C_SDA. The engine is measuring
its own worst violation against a pad it can never fix. In rc6full the same
column reads **−0.04**. Bidirectional pad nets are multi-driver by construction,
so "multi driver net" *is* the pad ring.

**And with the poison removed the engine simply works.** rc6full's first
route-stage DRV block, at 86.06% density:

    | nets | terms|  wViol  | ... |  #Buf | #Inv | #Resize| Density |
    |   492|  2517|    -0.37| ... |     0 |    0 |      0 |  86.06% |
    |    20|    83|    -0.04| ... |    80 |   65 |    372 |  86.09% |
    |     2|     5|    -0.01| ... |     2 |    7 |     13 |  86.09% |
    |     1|     3|    -0.00| ... |     0 |    0 |      0 |  86.09% |

**492 nets to 1, in ten seconds, for 80 buffers + 65 inverters + 372 resizes and
+0.03 points of density.** The capability is not in doubt. The problem is
entirely that this happens in the middle of `opt_design` and the recovery passes
afterwards put 61 back.

### 8. WHERE THE REPAIR CAN GO, MEASURED: NOT AFTER THE FILL

The gate does not read `drv_05_route_opt.rep`. `ROUTE_BUDGET_DRV_TRAN` is 0 and
is compared against `::pnr_last`, which for this row comes from
`timing_summary_06_post_fill.rep` — written after `flow_step filler` and after
`place_bondpads.tcl`:

| run | 05_route_opt | 06_post_fill | `route_gate.txt` |
|---|---|---|---|
| rc5 | 195 | 195 | `FEP 195` |
| rc6hold | 230 | 227 | `FEP 227` |
| rc6route | 305 | **325** | `FEP 325` |
| rc6full | 156 | 155 | `FEP 155` |

So the obvious move — repair what the gate measures — was worth testing, and it
fails for a structural reason.

**Phase C.** `opt_design -post_route -drv` on the post-fill database with the IO
override active. The engine is invoked internally as

    Internal optDRV -postRoute -max_tran -max_cap -maintainWNS
      -setupTNSCostFactor 0.3 -maxLocalDensity 0.96 -numThreads 14 -glitch

— **its own local-density ceiling is 0.96** — and its table then reports
`Density 100.01%` on every row:

    | nets | terms|  wViol  | ... |  #Buf | #Inv | #Resize| Density |
    |   197|   695|    -0.25| ... |     0 |    0 |      0 | 100.01% |
    |   155|   566|    -0.25| ... |     0 |    0 |     60 | 100.01% |
    |    78|   224|    -0.24| ... |     0 |    0 |      0 | 100.01% |

    *info: Total 155 net(s) have violations which can't be fixed by DRV optimization.
    *info:     3 net(s): Could not be fixed because the gain is not enough.
    *info:   124 net(s): Could not be fixed because of exceeding max local density.

**Zero buffers and zero inverters inserted** — after `add_fillers` the core is
full by construction and there is nowhere to put one. 124 of the 155 residual
nets say exactly that. It then spent 17 minutes and 59 NanoRoute ECO iterations
repairing the routing around 60 resizes, and I stopped it.

**No post-fill DRV repair is possible on this design.** The repair has to happen
at `4_route.tcl:1082`, which is where `ROUTE_OPT_DRV` already sits — after the
`ROUTE_OPT_MODE` switch, before `flow_step filler` at 1208.

### 9. AND THE 20 THE FILL ADDS ARE REVERSIBLE

Diffing rc6route's two populations pin by pin: all 193 route-opt internal pins
are still violating at post-fill, and 20 new ones appear — the fill step is
strictly additive. But **every one of the twenty is at slack −0.000**, over the
limit by less than half a picosecond; eighteen are a contiguous run of synthesis
gates (`g88320 … g88832`, mostly `/B1` and `/B2` pins) and two are in `u_dmac_0`.

Deleting the fillers again on the loaded database takes the internal count
**229 → 211** — recovering 18 of the 20 — with setup and hold unchanged at
+0.091 / +0.003. They are nets sitting exactly on 0.300 that the fillers'
coupling tipped microscopically over, not a degradation the fill causes. A
repair that leaves real margin removes them as a side effect.


### 10. THE MEASUREMENT

`build/rc6route-20260831/work/nanosoc_eth_chiplet_pads_routed` copied to scratch
and opened read-only. The run's own artefacts were never written. The copy is
faithful: `244135 insts / 2207884.220 um2`, setup/hold `+0.091 / +0.003`,
identical to that run's `imp_area.rep` and `timing_summary_05_route_opt.rep`.
The saved database is the **post-fill** state, so its baseline is 325 — the
number the gate judges, not the 305 in the route-opt report.

| phase | database state | rows | IO | internal | worst tran | setup | hold |
|---|---|---|---|---|---|---|---|
| **A** | as saved (post-fill) | 325 | 96 | 229 | −6.024 | +0.091 | +0.003 |
| **B** | + `pnr_io_drv.sdc` | **229** | **0** | 229 | −0.243 | — | — |
| **C** | + `-drv`, post-fill | *density-blocked, §8* | | | | | |
| **D** | fillers removed | 211 | 0 | 211 | −0.243 | +0.091 | +0.003 |
| **D** | + `opt_design -post_route -drv` | **99** | 0 | 99 | −0.192 | **−0.054** | +0.003 |

**B is surgical and free.** A pin-by-pin diff finds 96 rows in A and not in B,
and **0 rows in B and not in A**, at identical instance count and area — it is a
constraint change. `pnr_io_drv.sdc` printed `drv_limit_override enabled (reads
back true)` and `max_transition 7.000 ns -override on 52 port(s) and 48 pad PAD
pin(s)`; its documented interactive caveat (`set_interactive_constraint_modes`
first) is accurate, and the file is byte-identical (md5 `42a2f22a1278`) to the
copy rc6full ran.

**D is the state `ROUTE_OPT_DRV` actually runs in.** `delete_filler -prefix
FILLER` removed 113,935 instances and took the internal count 229 → **211**,
reproducing the real pre-fill `05_route_opt` figure of 209 to within two
endpoints, with timing unchanged.

### 11. THE DRV BLOCK REACHES ZERO. THE COMMAND THAT CONTAINS IT DOES NOT.

This is the part that would have been misreported by reading the log instead of
the database. Inside `opt_design -post_route -drv`, the GigaOpt DRV block does
exactly what it is asked:

    | nets | terms|  wViol  | ... |  #Buf | #Inv | #Resize| Density |
    |   197|   695|    -0.25| ... |     0 |    0 |      0 |  86.06% |
    |    21|    50|    -0.21| ... |    47 |   39 |    125 |  86.08% |
    |     2|     4|    -0.00| ... |     6 |    0 |     14 |  86.08% |
    |     1|     2|    -0.00| ... |     0 |    0 |      1 |  86.08% |
    |     0|     0|     0.00| ... |     0 |    0 |      0 |  86.08% |

**197 nets to zero**, no `Reasons for remaining drv violations` block printed at
all, and its own setup table reading `WNS 0.091 / 0 violating paths`. A log-only
reading of this experiment says "solved".

The database says otherwise. The same command then runs `refinePlace
-preserveRouting true`, `EcoRoute #1` — NanoRoute re-routing **4.7% of the
area** — and a fresh tQuantus extraction. Re-measured on the result:

    max_transition   211 -> 99 endpoints   worst -0.243 -> -0.192
    max_capacitance  0 -> 0
    setup WNS        +0.091 -> -0.054      <-- MET becomes VIOLATED
    hold  WNS        +0.003 -> +0.003
    area             244135 insts / 2207884.220 um2
                  -> 244227 insts / 2208195.260 um2   (+92 insts, +311.04 um2)

The DRV block optimised against the parasitics it had **before** the re-route.
Once the wires it forced actually exist, about half the violations come back —
and the worst setup path moves from `..._core_iq_branch_q_reg/D` (MET +0.091) to
`u_dap_ss_0_..._mst_rddata_cdc_check_reg[0]/D` (VIOLATED −0.054), a different
endpoint off the same startpoint.

**That is the same ordering defect as §6, one level down.** In §6 the recovery
passes run after the last DRV pass; here the ECO route runs after the DRV block
inside the very command whose job is DRV.

### 12. IT REPRODUCES, AND THE FLOW'S OWN TARGETS DO NOT RESCUE IT

Phase D ran `-drv` on a bare session. The flow does not: `4_route.tcl:1033-1038`
sets three optimiser attributes before every post-route `opt_design`, the `-drv`
one included. Phase E repeated the experiment with all three applied and read
back — `opt_post_route_setup_recovery auto`, `opt_setup_target_slack 0.11`,
`opt_hold_target_slack 0.08` — from the same starting database.

| | max_transition rows | worst tran | setup WNS | hold WNS |
|---|---|---|---|---|
| baseline (pre-fill equivalent) | 211 | −0.243 | **+0.091** | +0.003 |
| D — `-drv`, bare session | **99** | −0.192 | **−0.054** | +0.003 |
| E1 — `-drv`, flow's targets set | **99** | −0.192 | **−0.042** | +0.003 |

**The DRV outcome is identical to the row and the setup regression survives.**
Telling the optimiser to aim for +110 ps of setup slack buys 12 ps of the 145 it
gave away, and the worst path is still `VIOLATED`. This is not a configuration
mistake in the experiment; it is what the pass does to this design.

So `ROUTE_OPT_DRV=1` is a **trade, not a free win**: it halves the internal
`max_transition` population and hands back the setup closure that F29 had just
won. That is exactly what the toolkit's own knob comment asks for —
"Compare DRV FEP against a `ROUTE_OPT_DRV=0` run before promoting the result" —
and the comparison says do not promote it on its own.

### 13. IT CONVERGES — GEOMETRICALLY, AND THE SETUP HIT IS ONE-TIME

Two passes, same session, same starting database, flow targets set:

| state | rows | worst tran | setup | hold | insts | Δinsts | area (um2) | Δarea | Δutil pts |
|---|---|---|---|---|---|---|---|---|---|
| baseline | 211 | −0.243 | **+0.091** | +0.003 | 244135 | — | 2207884.220 | — | — |
| after 1 × `-drv` | 99 | −0.192 | −0.042 | +0.003 | 244227 | +92 | 2208197.060 | +312.84 | +0.029 |
| after 2 × `-drv` | **47** | **−0.105** | **−0.043** | +0.003 | 244257 | +122 | 2208262.940 | +378.72 | +0.036 |

Two things this settles.

**The pass converges, at roughly ×0.47 per iteration for ~190 um2 each.** Each
pass fixes most of what it sees; the ECO route puts back rather less than half.
Extrapolating the ratio, reaching zero takes about **eight passes and ~1,500 um2
(+0.14 utilisation points)** — trivial against 65,600 um2 of headroom below the
92.2% wall, but eight passes at ~8-9 minutes each.

**The setup regression is one-time, not cumulative.** −0.042 after one pass,
−0.043 after two. The first pass gives up 133 ps and the second gives up one
more. So this is not a runaway; it is a fixed toll at the door.

But it is still a toll on the row F29 had just closed, and nothing in
`4_route.tcl` after `ROUTE_OPT_DRV` recovers it — `opt_post_route_setup_recovery`
is an attribute set *before* the passes (line 1035), and it was `auto` throughout
phase E.

### 14. WHAT TO SET FOR THE INTEGRATED RUN

**Enable this. It is free and it is 30% of the row:**

    PNR_IO_DRV_OVERRIDE  = 1        (already the design.mk default)
    PNR_IO_MAX_TRAN      = 7.000    (already the design.mk default)

325 → 229 endpoints, measured; exactly the 96 IO rows and nothing else; zero
instances, zero area, no timing change. **The only requirement is that the run
executes the place stage** — `read_mmmc` is in `2_place.tcl` and nowhere else, so
a cts or route resume cannot pick it up however the environment is set. Verify on
the artefact, not the launch header:

    pnr_io_drv.sdc: max_transition 7.000 ns -override on 52 port(s) and 48 pad PAD pin(s)

**Do not enable this yet:**

    ROUTE_OPT_DRV        = 1

Measured, twice, on a real database: it halves the internal population per pass
and costs setup closure — **+0.091 → −0.042**, with hold unchanged. That is the
comparison the toolkit's own knob comment asks for ("Compare DRV FEP against a
`ROUTE_OPT_DRV=0` run before promoting the result"), and on its own the answer is
no: it trades the row F29 just closed for the row F29 left open.

**And leave this exactly as it is:**

    set_max_transition 0.300 [current_design]      inputs/constraints.sdc:1191

Raising it to 0.400 would clear 201 of the 209 internal rows for no area at all,
and it is still the wrong move: `constraints.sdc:1097-1099` measures that this
limit is worth 25 ps on the critical path and is what removed the last
post-route setup ECO. It buys the DRV row with the setup row, the same trade as
`ROUTE_OPT_DRV`, just paid up front.

### 15. THE KNOB THIS ACTUALLY NEEDS, WHICH I DO NOT OWN

`ROUTE_OPT_DRV=1` becomes the right answer the moment something recovers setup
after it. The shape is a setup-recovery pass between `4_route.tcl:1082` and
`pnr_end_reports 05_route_opt` at 1117 — the slot is empty today — and then the
pair iterated two or three times. Every ingredient is measured: the DRV side
converges ×0.47 per pass at ~190 um2, the setup toll is one-time at 133 ps, and
hold never moves.

`design.mk` also needs one line for the knob to be usable as a default at all: it
documents `ROUTE_OPT_DRV` at line 993 and prints `$(ROUTE_OPT_DRV)` at line 2442,
but never assigns or exports it. `make route ROUTE_OPT_DRV=1` does reach the flow
today — GNU Make 4.2.1 exports command-line variables and `4_route.tcl` reads
`$::env(ROUTE_OPT_DRV)`; tested against a makefile that only references the
variable — but without `export ROUTE_OPT_DRV ?= 0|1` the run header records a
blank, which is precisely how `rc6route` came to print `PNR_IO_DRV_OVERRIDE 1`
for a mechanism it did not have.

### 16. THE FLOOR, HONESTLY

**Zero is not reachable today, and the thing standing in the way is setup, not
`max_transition`.**

* **The IO 96 goes to zero for free** — but by being correctly constrained, not
  by repair. Those 48 pins carry `set_input_transition` assertions and 100 pF
  off-chip loads; 6.324 ns is past the library's last characterised point. The
  new limit is 7.000 ns against a worst observed 6.324, which is thin: a material
  change to the I2C load fires it.
* **The internal 229 has no irreducible core.** Every category that looked like
  one dissolved: the 29 "multi driver net" and 13 "not routed" entries are the
  pad ring and disappear with the override; the 124 "exceeding max local density"
  entries are an artefact of asking after the fill. What is left converges
  geometrically — 211 → 99 → 47 → (extrapolated) ~0 in about eight passes for
  ~1,500 um2.
* **What blocks it is the 133 ps.** Every measured route to zero on the internal
  half goes through `opt_design -post_route -drv`, and that command's own ECO
  route breaks setup. Until something recovers it, the honest floor is:

      with the IO override alone, and nothing else changed:   229 endpoints, no timing cost
      each further -drv pass:                                 x0.47 rows, +190 um2, setup -0.042

* **And the gate reads a number two steps later.** `06_post_fill` is what
  `route_gate.txt` judges, and on rc6route the fill added 20 endpoints on top of
  the route-opt figure. All twenty were at −0.000 and 18 of them came back when
  the fillers were deleted, so a repair with real margin should absorb them — but
  that has not been measured end to end, and §8 shows it cannot be repaired after
  the fact.

So the defensible statement for the integrated run is: **229, down from 325, at
zero cost and zero risk.** Not zero — and the remaining 229 is one flow change
(a setup recovery after the DRV pass) away from being a bounded, cheap,
eight-pass problem rather than an open one.
