# What actually stands between us and tapeout — the physical-verification picture

> ## ⚠ STALE — a point-in-time report, not the current picture. Marked 2026-08-18.
>
> **The numbers below describe run `20260808T100330Z_route-setupopt` and nothing after
> it.** The design has been re-streamed twice since, and the DRC population this document
> explains no longer exists: the LEFOBS stream-map fix removed the phantom metal that was
> 68.8% of everything Calibre measured, `io-pad-abstract` results went 140 → 0, and the 691
> `PO.R.8` have since been shown to be a black-boxing artefact and waived by cell.
>
> **The explanations of the mechanisms are still worth reading. The counts are not.** Do not
> quote a number from this file.
>
> **Live sources, in order of authority:**
>
> | what | where |
> |---|---|
> | what signoff does **not** cover — *executable* | `ci/signoff.yaml` `unsupported:`. Run `python3 scripts/ci/signoff.py lint`: every gap carries a `refuted_by:` that must FAIL for the gap to still exist, so this one cannot rot silently. 9 gaps, all verified still real on 2026-08-18. |
> | current Calibre DRC, like-for-like | [43 — Calibre DRC on `fp1505`](43-drc-fp1505.md) |
> | every result assigned to fix or waive | [`docs/DRC_WAIVER_INVENTORY.md`](../DRC_WAIVER_INVENTORY.md) |
> | the `PO.R.8` reversal | [39 — `PO.R.8` resolved](39-po-r8-resolved.md) |
> | the PG-anchoring hazard behind the shorts | [36 — `split_row` PG anchoring](36-split-row-pg-anchoring-hazard.md) |

---


Written 2026-08-08 against run `20260808T100330Z_route-setupopt`.
Reports: `ASIC/genus-innovus/runs/20260808T100330Z_route-setupopt/reports/eval/`

This is the "explain it properly" companion to the audit docs. It assumes you know
RTL, simulation and FPGA flows, and no Innovus physical-design jargon.

## THREE CORRECTIONS TO WHAT WAS PREVIOUSLY REPORTED

1. The 2 `IMPVFC-98` "no routing at all" nets are **VDDIO and VSSIO**, not core
   VDD/VSS. Verified per-net: VDD 0, VSS 0, VDDACC 0, VDDIO 2, VSSIO 2. Earlier
   reports said the IO supplies were clean and the problems were all core — that
   conflated the *opens/dangling* counts (which ARE core VDD/VSS) with the
   *unrouted* count (which is the IO supplies).

2. "Metal density 35,685 -> 0" is true but measured against a **far weaker minimum,
   in a much smaller window**, than the foundry's own rule. The tech LEF gives each
   of M1-M8 THREE density specs, and Innovus used the LAST one parsed rather than
   the foundry sign-off spec. For M4 the shape is:

       MINIMUMDENSITY <min> ; MAXIMUMDENSITY <max> ; DENSITYCHECKWINDOW <w> <w> ;  <- foundry
       MINIMUMDENSITY <min> ; MAXIMUMDENSITY <max> ; DENSITYCHECKWINDOW <w> <w> ;
       MINIMUMDENSITY <min> ; MAXIMUMDENSITY <max> ; DENSITYCHECKWINDOW <w> <w> ;  <- used

   > Vendor tech-LEF density values redacted — TSMC licence forbids reproduction.
   > Source: `PRTF_EDI_N65_<stack>_RDL.<rev>.tlef`, the `LAYER` blocks for M1–M8.
   > The first spec in each block is the foundry one; read all three there.

   Fill genuinely worked (every layer now 33-44% mean, up from 12-33%), but the
   pass/fail claim is against the wrong threshold. Re-run `check_metal_density`
   against the FIRST spec's window and minimum before quoting it.

3. `route_gate.txt` prints "metal density fill (EVR_METAL_FILL, off)" even when
   fill DID run. That line is hardcoded at `4b_pnr_route_eval.tcl:1702`. Stale.

## 1. DRC — what a design rule is

At 65nm you draw features smaller than the 193nm light drawing them. What lands on
the wafer is a blurred, corner-rounded approximation. A design rule is the foundry
saying "shapes obeying these constraints reliably become what you intended".

Failure modes: too close -> the blur merges and you get a metal bridge (a short);
too narrow -> the etch eats it (an open); sharp tiny jogs -> lithography rounds
them away and the position varies wafer to wafer; tiny enclosed holes -> the
etchant cannot get in and out, leaving residue.

Two classes matter differently:
  - "chip does not work" — shorts and opens, deterministic, every die
  - "yield and reliability" — marginal geometry that usually prints, fails on a
    slow-etch corner, or degrades over years (electromigration)

### Our 64, and the one fact that matters most

    44  SPACING   43 on M4, 1 on M8
    10  MINSTEP    9 M5, 1 M4
     6  MINHOLE    all M5
     3  NSMETAL    2 M6, 1 M7
     1  SHORT      M4

**All 64 are on Special Wire of VDD (58) or VSS (9). None on a signal net. None
inside a standard cell.** The router's own work is clean across ~85k timing paths.
What is broken is the hand-drawn power grid in `scripts/power_plan.tcl`, where it
crosses the SRAM macros. 34 of the 40 that name a macro are QSPI flash cache RAMs.

### What a "blockage" is

Hard macros (SRAMs) are not loaded as full layout. Innovus loads a LEF *abstract*:
outline, pin locations, and an OBS section listing where the macro already has its
own metal. `rf_16k.lef`'s OBS declares M1, M2, M3, **M4** — 23,418 rectangles of
real internal routing. So "VDD special wire vs blockage" means our power grid put
M4 metal on top of metal that physically exists inside the SRAM.

Why: `floorplan.tcl:119` creates a **place** halo, which keeps standard cells away
but does nothing to `add_stripes`/`route_special`. And `power_plan.tcl` sets
`add_stripes_ignore_block_check true` with `stacked_via_bottom_layer M1`, so vias
punch down through M4 wherever they land. There is no **route** blockage over the
macros anywhere in the flow.

### The SHORT — severity genuinely unknown

    SHORT: Special Wire of Net VDD & Blockage of Cell .../u_region_dmem_0 ... (M4)
    Bounds: (1214.490, 1624.500) (1214.705, 1625.650)      0.215 x 1.15 um

A LEF OBS rectangle carries **no net name**. It says "metal here", not "this is
VDD". So Innovus must report a short without knowing whether the metal underneath
is the SRAM's own VDD rail (harmless, waivable) or a bitline/wordline/VSS (that
SRAM is dead, possibly a supply-to-ground short across the die).

**Resolvable in about an hour**: we DO have `rf_16k.gds2` (it is in the
`write_stream -merge` list). Open it at macro-local coords near (155.9, 285.2) and
look. This is the only item on the list that could be fatal and the cheapest to
settle. Do it first.

### The other 63
- **43 M4 SPACING** — same root cause, near rather than on. Yield, not function.
- **1 M8 SPACING** at (1188.955,191.0)-(1190.45,203.0) — 1.5 x 12um, on a wide top
  power wire, not near a macro. Different in kind; look at it individually.
- **10 MINSTEP** — 10nm x 65nm staircase notches from stripe jogs. Electrically
  irrelevant on a 3.6um stripe; still a hard deck failure.
- **6 MINHOLE** — ~0.19um2 enclosed gaps against a 0.200um2 rule. The etchant
  cannot clear a hole that small.
- **3 NSMETAL** — 55x95nm overlaps where two same-layer shapes join. On a POWER
  net a marginal joint that breaks disconnects grid. Same class as the dangling
  wires below.

DRC went 88 -> 64 across the filler-repair pass. Neither `add_fillers -fix_drc`
nor `route_eco` touches special wires, so the 64 will not move until
`power_plan.tcl` changes.

## 2. PG — the power grid

203,260 cells need VDD and VSS. You build a mesh, not per-cell wires, because of
two physics problems:

**IR drop.** V = I*R. A cell seeing 0.95V instead of 1.08V switches slower — a 10%
droop can cost 15-20% speed on that cell. STA assumed a fixed voltage everywhere,
so the chip fails timing at a frequency STA said was fine, in a location- and
temperature-dependent way that is miserable to debug.

**Electromigration.** At high current density the electron wind physically moves
metal atoms until a void opens the wire. Works at t=0, dies in the field. This is
why power wires are wide and vias come in arrays.

**Vocabulary:** *ring* = wide loops around the core (ours: M8/M9, 12um wide).
*stripe* = regular parallel wires crossing the core (M8 vertical 3.6um every 60um;
M9 horizontal 3.6um every 60um; M5 1um every 15um over macros). *followpin* = the
thin M1 rails along every cell row that cells abut onto. *via* = vertical
connection; a stripe with no vias is decoration. *special routing* = power
geometry drawn by a human, off-grid, which NanoRoute will not touch — which is
exactly why all 64 DRC violations are special wires.

### Our numbers

    350  IMPVFC-200  pieces of the net not connected together   VDD 171, VSS 179
    1501 IMPVFC-94   dangling wire(s)                           VDD 830, VSS 671
    2    IMPVFC-98   no global and no special routing           VDDIO, VSSIO

**The 350 "opens" are far less alarming than the number suggests.** Bounding-box
analysis of all 171 VDD fragments: ONE spans (186.76, 82.815)-(1418.16, 1917.185)
— the entire die. 18 are 10-1000um2. 152 are under 10um2. VSS is the same shape.
So the grid is one connected mesh spanning the chip, plus ~170 tiny orphan scraps
left where stripes were trimmed at macro edges. Not "the grid is in 350 pieces" —
"the grid is intact and there is litter". The litter is an LVS liability (each
fragment is a node that does not exist in the schematic), not an IR-drop one.

CAVEAT: bounding-box overlap is not connectivity. That the big fragment IS the
main mesh is strongly indicated, not proven. Proving it needs a database query or
IR-drop analysis. ~~(no Voltus/RedHawk on site)~~ — **that parenthesis was wrong.
Voltus is installed and licensed here** (`SSV_21.11.000`, version-matched to the
Innovus in use; checkout verified live, not just `lmstat`). See
`31-power-delivery-measured.md`.

**The 1501 dangling wires are mostly cosmetic**, and their layer distribution is
the diagnosis: M2 634, M1 466, M5 341, M3 41, rest <10. 1100 of 1501 on M1/M2 —
the followpin layer and the one above — are stubs from stitching cell-row rails to
the grid. A few femtofarads on a supply node; nobody will notice. They matter for
min-area DRC and LVS noise only. Note the count wanders run to run (1518/1496/
1499/1501) while the 350 opens and 64 DRC do not — the dangles are incidental, the
opens are structural.

**The 2 unrouted nets are the IO supply, and this is expected but unverified.**
VDDIO/VSSIO are the 2.5V pad domain. `power_plan.tcl` gives them a
`connect_global_net` and nothing else, because the TSMC staggered ring distributes
VDDPST/VSSPST **by abutment** through the IO filler cells — butt them together and
the buses connect cell-to-cell with no explicit routing. We place 3 VDDIO and 3
VSSIO pads per side, 24 supply pads. So: not a defect. BUT nothing in this flow
verifies the abutment bus is actually continuous. If one filler is missing or the
wrong variant, the IO supply is broken on that side and no report here would show
it. **LVS is what would catch it.**

### One item not previously listed

`*_eval_power_vias.rep`: **8 missing vias between M8 and M9** (6 VDD, 2 VSS). Our
top power layers carry the most current, and via EM limits are the tightest
constraint in the grid. Eight missing crossings will not open the mesh but push
current through neighbours. Five of the VDD locations also appear in the M8
dangling-wire list — the same defect seen by two checks.

## 3. The other checks

**Antenna — clean, and it is a real result.** During fabrication, metal is
patterned in a plasma that carries charge. A wire acts as an antenna collecting
that charge; if it connects to a transistor gate, the charge tunnels through a
~2nm gate oxide and damages it. The damage happens at manufacture, before power-on,
and often leaves a transistor that works but has degraded lifetime. Fixes are layer
hopping and antenna diodes. Zero violations means the router honoured the rules and
`filler.tcl`'s ANTENNA cell insertion worked — which matters given the earlier
failure where filler insertion silently did nothing. Caveat: clean against the LEF
rules, which are a simplification of the foundry deck. Expect a few at real signoff.

**Metal density — why a MINIMUM.** After each metal layer, the surface is bumpy and
must be flattened before the next layer prints (lithography's depth of focus is
under a micron). CMP presses the wafer against a rotating pad with abrasive slurry.
Metal and dielectric polish at different rates: too much metal in a region and the
surface *dishes*, leaving wires thinner and more resistive; too little and isolated
wires *erode*. Both scale with non-uniformity, so foundries require every window in
a stepped grid to fall in a band, and sparse areas get **dummy metal** — floating
rectangles that do nothing but make the polish uniform.

Pre-fill we had 35,685 windows under 1% metal (12,475 of them M8, where only power
stripes on a 60um pitch exist). Post-fill every layer is 33-44% mean. That is a
real improvement. But see correction 2 above: it was checked against 1% in 20x20,
not the foundry's 10%/20% in 75x75. Applying the tighter numbers to the post-fill
data: M1-M7 and M9 have ZERO windows under 10%. Only M8 has residual sparse windows
(167 under 10%, 1035 under 20%) against its 20% minimum — and a 75x75 window
averages ~14 of the 20x20 ones, so with a 43.68% mean most of those very likely
smooth out. Re-run the check properly to convert "probably fine" into "known".

Done right: a full post-route RC extraction re-ran AFTER fill, so the timing
numbers describe the filled database. Fill changes coupling capacitance; timing
computed before it would not describe the chip.

**Filler cells — zero gaps.** Cells sit in rows and abut. Gaps are not harmless
empty space: they break N-well continuity (isolated well with no tap can float,
forward-bias, and latch up — a parasitic thyristor shorting VDD to VSS until you
power-cycle), they break the VDD/VSS followpin rails, and they leave base layers
sparse for CMP. Fillers are dummy cells that close every gap. Zero gaps is a real
result given the run that once shipped a GDS with zero fillers and 95,568 free-site
gaps.

**Cut/via density — 520,933 violations, all "below minimum".** Vias have density
rules for the same CMP reason, plus via etch depth is loading-dependent (too few
vias in a region and the etch punches through). `add_via_fill` has never run. BUT
treat the number as indicative only: the stream it is measured over contains no
standard-cell geometry, and standard cells are full of VIA1 contacts. It is the
routing contribution to density, not a density signoff.

## 4. Signoff, and why we cannot do it

**Tool DRC vs foundry DRC.** `check_drc` in Innovus checks the router's work
against the tech LEF — a deliberately simplified *routing* abstraction, because it
runs thousands of times during optimisation. **Signoff DRC** runs the final GDSII
through Calibre against the foundry's rule deck: tens of thousands of lines
covering base layers (diffusion, poly, implant, well), every density variant,
latch-up spacing, ESD, seal ring, and context-dependent conditional rules LEF
cannot express. A LEF-clean design is routinely thousands of violations away from
Calibre-clean.

**LVS — the check that catches chip-killing bugs.** Layout Versus Schematic
extracts a netlist from the GDSII geometry itself (finding transistors where poly
crosses diffusion, tracing every wire and via) and compares it against the netlist
you intended, flattened to transistors via each cell's CDL. DRC proves the shapes
are manufacturable; **LVS proves they are the right shapes.** It is the only check
that operates on the layout rather than the netlist — every simulation, gate-level
run and FPGA prototype tests the *netlist*. If the layout does not match, none of
that verification applies to the object being fabricated. LVS would settle our M4
SHORT, prove the IO abutment bus, and flag all 350 PG fragments.

**Why neither can run here.** A **CDL** is the transistor-level schematic of a
library cell. Without `AN2D1`'s CDL, "AN2D1" in our netlist is a name with no
circuit behind it. A **cell GDS** is the actual polygons of that cell; Innovus
writes our routing plus instance *placements*, then merges each cell's real layout
in at stream-out.

Searching the entire PDK:

    $ find $TSMC_65_HOME \( -iname '*.cdl' -o -iname '*.gds*' \)
    $TSMC_65_HOME/CMOS/util/unit.cdl        <- a units header. That is all.

Zero GDS files. The Milkyway library is literally named `frame_only`: 855 FRAM
views (abstracts, same as LEF) and 2 dummy CEL tiles. Consequently our run log
carries ~401 unique `IMPOGDS-217: Master cell: <name> not found in merged file(s)`
messages, and `write_stream -merge` lists only the 8 memory macros.

**The GDS we are producing is our routing and power grid, plus 21 SRAMs, plus
~203,000 named holes.** No Innovus setting fills them. Every clean report in that
directory describes an object that cannot be manufactured — they are meaningful
checks on OUR work, and that is genuinely valuable, but they are not checks on the
chip. This is procurement, not engineering.

## 5. The other gaps

**~~No QRC deck.~~ ⚠ CORRECTED 2026-08-18: THE QRC DECK IS PRESENT.** This heading
contradicted **this same document's own item 20**, which already read
"~~QRC/Quantus tech file — absent.~~ **Present.**" §5's header was simply never updated
when item 20 was. Measured: `<PDK>/…/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile`,
186,639,161 bytes; Quantus installed (`QUANTUS_21.11.000`), `QRC_Advanced_Analysis`
41 issued / 0 in use. **The rest of this paragraph — why cap tables are not signoff
extraction, and that the flow currently falls back to `extract_rc_effort_level low` — is
still accurate and still matters.** What changed is that closing it is a flow edit, not a
procurement request. See also `17-silent-noops.md`, corrected the same day for the same
reason.

Parasitic extraction turns geometry into the R and C that
determine delay. Cap tables are 2.5-D lookups; a QRC/Quantus tech file is a
foundry-calibrated field-solver model, and that is what timing signoff means at
65nm. We get `IMPEXT-3518` and fall back to `extract_rc_effort_level low` — the
lowest tier the tool offers, on a node where the tool says that tier is
inappropriate. Cap-table vs QRC disagreement at 65nm is commonly 5-15% on
interconnect delay. **Our error bar is many times our reported margin, so we do not
currently know the sign of our setup slack.** Same for hold, and hold is worse:
hold failures are not fixable by lowering the clock.

**No `set_timing_derate`.** OCV mode IS on (`cts_setup.tcl:72`, and the eval route
stage fails the run if it is not). What is missing is the derate factors. Corners
answer "what if the whole die is slow?"; OCV answers "what if THIS path is slow and
THAT one fast, on the same die?" — which is the case that actually breaks setup and
hold, since both compare a launch path against a capture path. We have 0.350ns
clock uncertainty, but that is a flat number at the clock, whereas derating scales
with path depth, which is the point. A path closing at zero derate can open by
5-10% under realistic derating.

**DFT/scan not implemented** (`config.tcl:113`, `DFT 0`). Scan chains every flop
into a shift register so ATPG can toggle every node, giving 95%+ stuck-at coverage.
Without it, our only test is "boot the M0+ and see" — typically 60-70% coverage,
so we ship parts with latent faults and cannot distinguish a bad die from a bad
board from bad firmware. Defensible for a prototype with tens of parts; not for a
yield target. Adding it later means re-synthesis and re-P&R.

**Post-P&R LEC, run but not on this netlist.** *(Corrected 2026-08-17; this paragraph
was headed "No post-P&R LEC".)* Between synthesis and GDS, Innovus ran pre-CTS opt, CTS,
post-CTS opt, post-CTS hold, post-route opt and post-route hold. Instance count
went 183,836 -> 203,260 — ~20,000 instances added or changed, every one a logic
rewrite. LEC proves formally that those transforms preserved function, and on
2026-08-08 it did: 61,375/61,375 equivalent, 0 non-equivalent, 0 abort, in 412 s.
**But against `_pnr.v` sha1 `45a6c089…`, which is not the netlist we would tape out**
(`runs/latest/` holds `7a8d6cdb…`), so the verification story still does not attach to
the shipped object. Re-run it. Note `make lec` — the *other*, RTL-side target — exits 0
even on non-equivalence; grep for "Compare Results:". Run `make lec-selftest` (~15s,
mutation-tests the harness) BEFORE trusting `lec-pnr`, and read its `LEC-RUNNER:` verdict
line rather than `LEC-VERDICT:`. A LEC that always passes is worse than no LEC.
Details: [13 §7 item 1](13-lec.md).

## 6. What stands between us and tapeout

### (a) Must be ZERO — no waiver exists
1. Signoff DRC (Calibre, foundry deck) — never run. The fab will not accept the masks.
2. LVS clean — never run. Without it our verification is about a different object.
3. The M4 SHORT — severity unknown, could be fatal. Settle it against `rf_16k.gds2`.
4. Hold timing — currently WNS -0.099ns / 68 endpoints. Not fixable by slowing the
   clock. A chip failing hold is scrap.
5. Post-P&R LEC **re-run on the netlist actually being shipped** — passed on 2026-08-08
   against a since-superseded `_pnr.v`; costs ~7 minutes of Conformal, not runtime worth
   deferring.

### (b) Waivable with justification, or one iteration away
6. 43 M4 + 1 M8 SPACING — one root cause; route blockage over macros.
7. 10 MINSTEP, 6 MINHOLE, 3 NSMETAL — small-geometry artefacts, same grid re-run.
8. 350 PG opens — one real mesh plus ~348 scraps; must be cleaned for LVS.
9. 1501 dangling wires — cosmetic on silicon, LVS/min-area noise.
10. 8 missing M8->M9 power vias — reliability, cheap.
11. Metal density at the FOUNDRY thresholds — re-check at 75x75 / 10% / 20%.
12. Cut/via density — `add_via_fill` never run; number not meaningful without cell GDS.
13. `set_timing_derate` — add it and re-time. Margin will get worse. Better to know.
14. 6 max_transition DRVs on I2C/QSPI pads — likely SDC load modelling, 20 minutes.
15. VDDIO/VSSIO abutment bus — expected fine, only LVS proves it.
16. DFT/scan — waivable for a prototype, in writing.
17. Setup WNS -0.007 (summary) vs -0.199 (report_timing) — different views. Decide
    which is the signoff view before quoting either.

### (c) Procurement / lead time — these GATE section (a)
18. Standard-cell, IO and bond-pad **GDS** — absent. Blocks signoff DRC.
19. **CDL** netlists for the same — absent. Blocks LVS.
20. ~~**QRC/Quantus** tech file — absent.~~ **Present.** A QRC deck for the exact
    stack is on site and the mmmc file has been wired to it for some time —
    see the note at the head of
    `ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc`. It is also the
    extraction tech file the rail work now uses.
21. Seal ring and scribe — not in the design data. Without a seal ring the die
    cracks at dicing and moisture kills it in the field.
22. ~~IR-drop signoff — no Voltus/RedHawk licence.~~ **The licence exists.**
    `SSV_21.11.000`, version-matched to the Innovus in use, 41 features issued
    and idle, checkout verified live. What is genuinely absent is cell SPICE
    and cell GDS, so a *cell-accurate* PGV — and therefore all dynamic rail
    analysis — cannot be built here. Static rail and effective resistance can.
    See `31-power-delivery-measured.md`.
23. Calibre + foundry rule deck — licence + NDA.

**Items 18, 19 and 20 are the same conversation with the same broker, and they gate
items 1, 2 and 4. Nothing we fix in DRC or PG moves us closer to tapeout until
those arrive.** Everything in (b) is real work worth doing — but it is work on a
design we cannot yet verify.

### Order
1. **Today:** open the broker conversation — cell GDS, CDL, QRC deck, seal ring.
2. **This week, parallel:** settle the M4 SHORT against `rf_16k.gds2`;
   `make lec-selftest` then `make lec-pnr`; re-run `check_metal_density` at 75x75.
3. **Next P&R iteration:** route blockage over macros + fix
   `add_stripes_ignore_block_check`. Expect the 44 SPACING, the SHORT, most of the
   19 small-geometry items and a good share of the opens/dangles to go together.
4. **Then:** derate, re-time, and attack hold with honest numbers.

## What could not be determined
- Whether the M4 SHORT is electrically real (needs the macro GDS, which we have).
- Whether every row and macro taps the MAIN PG fragment (indicated, not proven).
- Whether M8 passes 20% density at the correct 75x75 window (likely).
- Which analysis view is the intended setup signoff view.
- Whether VDDACC is properly routed or simply has no instances.
