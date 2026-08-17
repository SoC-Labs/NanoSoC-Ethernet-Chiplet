# Power delivery: what has now been measured, and what still cannot be

> **[2026-08-18] SUPERSEDED IN TWO PLACES by `32-ir-drop-stage.md`. Read that
> first; this file remains the long record of method and traps.**
>
> 1. **The premise of the paragraph immediately below is now false.** It says
>    every database under `ASIC/eth-chiplet/build/` is pad-less and that "no
>    power-delivery question can be asked of those builds". Both current builds —
>    `fp1505` and `full-20260814` — carry all six `PVDD1DGZ_G` and all four
>    `PVSS1DGZ_G`, at the same coordinates as the archived database. That
>    sentence was written against the pre-`padfix` builds and never re-checked.
>    The archived route-baseline is therefore **no longer the only place, nor the
>    right place**, to ask: it needs `read_db_file_check false` and cannot be
>    shown byte-identical to what was saved. Everything below has been re-taken
>    on `fp1505`.
>    *(The trap that hides this: the pads are NOT in `*.place.gz`. Grepping that
>    file returns zero on the pad-CORRECT archived database too.)*
>
> 2. **"worst-case total supply collapse = 6.33 + 8.97 = 15.3 mV" adds two
>    INDEPENDENT maxima**, which this document's own §4c-bis warns against
>    elsewhere. The co-located figure — both deviations at the same instance,
>    which is the only version that means anything — is smaller: **15.00 mV on
>    `fp1505`**, against a 15.21 mV naive sum. The gate now reports both.
>
> Two further findings from the re-take, neither visible here: the PG opens are
> **still present and at the same coordinates** five days and one floorplan
> later, and the shipping `full-20260814` database carries a **VDD-to-VSS short
> on metal5** that aborts extraction outright.

Date: 2026-08-17. Database under test:
`ASIC/genus-innovus/runs/20260812T133501Z_route-baseline-gds/work/nanosoc_eth_chiplet_pads_eval_route`
— routed, and the only class of database in the tree that carries all 34 supply
pads. Everything under `ASIC/eth-chiplet/build/` is pad-less: synthesis deleted
the supply pads because they are instantiated with empty port lists, and
`add_io_fillers` then backfilled the slots so the ring still *looks* right
(`ASIC/genus-innovus/scripts/power_plan.tcl:359`). No power-delivery question
can be asked of those builds.

Scripts: `ASIC/genus-innovus/rail/`. The working tree beside them is
git-ignored on purpose — the `pg_capacity` report prints current-density limits
read straight out of the vendor tech LEF, and this repository is public.

---

## 0. The headline

**The pads reach the mesh.** For a week every attempt to attach a voltage
source to the ten core supply pads reported success and put zero sources into
the circuit, and there were two candidate explanations with opposite
consequences: a tooling artefact, or a die whose supply pads are not connected
to anything. It is the tooling artefact — one command option, `-short_pin_nodes`,
whose default is `false`. That is settled in §4b-bis, twice: once by fixing the
tool, and once by a union-find over the drawn metal that never asks the tool
anything. Effective resistance is now measured, and the prediction that the
left and right core edges would be starved is **refuted** — they are the best
part of the die.

With that settled, the two measurements it was blocking both landed:
effective resistance (§4b-bis) and **static IR drop — worst 6.33 mV of VDD
droop and 8.97 mV of VSS rise, 15.3 mV total, 1.42 % of 1.08 V**, at 99.86 %
instance coverage with all ten voltage sources in the circuit and current
accounting at 0.997 (§4c-bis). All ten pads carry 7.9–13.1 mA and share to
within ±6 %.

Power delivery **can now be characterised on this site**, and the reason it
never had been was not the one written down. Three places in these docs said
there was no Voltus licence. That was false, and it had been false for as long
as the claim existed.

What is genuinely out of reach here is narrower and worth stating precisely:
there is **no cell SPICE and no cell GDS** on this site, so a *cell-accurate*
power grid library cannot be built, and therefore **no dynamic rail analysis is
possible here at all** — not "unrun", unreachable. Static rail analysis at an
assumed switching activity is the strongest claim available, and anything
derived from it must be labelled that way on the same line as the number.

---

## 1. The licence claim was wrong (three places, now corrected)

| Where | Claimed | Actually |
|---|---|---|
| `09-signoff-checklist.md:527` | "No Voltus, no RedHawk" | Voltus installed and licensed |
| `25-what-remains-explained.md:149` | "(no Voltus/RedHawk on site)" | same |
| `25-what-remains-explained.md:337` | "IR-drop signoff — no Voltus/RedHawk licence" | same |

Evidence, strongest first:

1. **A live checkout.** Launching the tool prints
   `vtsxl  Voltus Power Integrity Solution XL  21.1  checkout succeeded`,
   and `8 CPU jobs allowed with the current license(s)`. During the resistance
   run it also took an extra `Voltus_Power_Integrity_AA` seat on demand.
2. **The install is version-matched.** `SSV_21.11.000` sits in the same release
   tree as the `INNOVUS_21.11.000` this flow already runs (same Cadence release
   root; the mount is not spelled here). Binaries present: `voltus`, `voltus_rail_smg`,
   `voltus_extractor`, `voltus_libgds`, `voltus_shortcheck` and others.
3. **`lmstat`**: 41 issued / 0 in use on every `Voltus_Power_Integrity_*` and
   `Voltus_XFi_*` feature.
4. **The commands are inside Innovus too.** `report_resistance`,
   `set_rail_analysis_mode`, `set_power_pads`, `set_pg_nets`, `write_pg_library`
   and `report_rail` all resolve in the Innovus Stylus shell. In the end this is
   how the work was done — see §7.

While correcting these, one more stale item in the same list: item 20,
"**QRC/Quantus** tech file — absent". Also false. A QRC deck for this exact
stack is on site, the mmmc file has been pointed at it for some time, and it is
the extraction tech file every measurement below depends on.

### A retraction

`30-ir-drop-gate-design.md:8-10` claimed four prototype files existed in
`docs/tapeout/` — `rail_static.tcl`, `rail_gate.py`,
`rail_config.eth_chiplet.tcl`, `rail_budgets.eth_chiplet.txt` — with a green
20-case selftest. **None of those files has ever existed anywhere in the tree,
so neither did the selftest or its result.** That paragraph is struck in place
rather than deleted, so it cannot be quoted again out of an older revision.

---

## 2. The core supply voltage — four sources, two real answers

This had to be settled before any rail number could be quoted, because getting
it wrong scales every percentage while leaving every number plausible.

| Source | file:line | Value | Live? |
|---|---|---|---|
| Tech pack | `ASIC/asic-toolkit/tech/tsmc65/tech.tcl:96` | **1.20** | yes |
| UPF `ON_TYP` | `ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf:108` | **1.20** | yes |
| UPF `ON_SLOW` / `ON_FAST` | same :107 / :109 | 1.08 / 1.32 | yes |
| mmmc `default_libset_max` (**setup/signoff**) | `scripts/nanosoc_eth_chiplet_pads.mmmc:28` | **1.08** | yes |
| mmmc `default_libset_min` (hold) | same :43 | 1.32 | yes |
| mmmc `typical_libset` | same :58 | 1.20 | yes |
| Synthesis `.db` set | `ASIC/common.mk:137,162` | **1.08** (no 1.20 entry at all) | yes |
| CPF `create_nominal_condition` | `inputs/nanosoc_chip_pads.cpf:13` | 1.08 | **dead** — wrong block stem, zero references |
| The CPF Innovus actually reads | generated `*_gate1.cpf` | **no voltage at all** | yes |
| Resulting Innovus domain | `*.cpfdb:65,181` | `PD_TOP,low 0 PD_TOP,high 0` | yes |

There is no `-voltage`, `create_op_cond` or `set_operating_conditions` anywhere
in the mmmc file. Voltage reaches the tools **only** through `.lib`/`.db`
filenames.

**The resolution.** Both live numbers are correct for different jobs:

- **1.20 V is the process nominal.** It is what the tech pack and the UPF
  typical state describe.
- **1.08 V is what this design is actually analysed at.** The setup view
  resolves through `default_delay_corner_max` → `tc_max` → `default_libset_max`
  to the slow, 125 °C, minus-10 % corner, and `report_power` confirms it in its
  own rail table — `VDD  1.08` — on both the pad-less build and the
  pad-correct database. It is also the correct corner for IR analysis, since
  supply droop is a worst-case question.

**The bug this was hiding.** `pg_capacity` printed `core voltage 1.20 V` (from
the tech pack) while the milliwatts it was about to divide came from a 1.08 V
report. That division never actually happened — the demand parser was broken
too, see §5 — so the error was latent rather than shipped. It is now fixed at
the root: the step reads the voltage out of `report_power`'s rail table and
reports the disagreement instead of silently picking a side.

**A second, separate disagreement, left open.** The IO supply: `tech.tcl:97`
and `design_config.tcl:219` say **2.5 V**, the UPF says **3.3 V**
(`:111`, with a ±10 % band around it, so not a typo). The IO library actually
loaded is the 2.5 V one. Two sources and the loaded library agree on 2.5; the
UPF is the outlier. This does not affect any number here — the IO ring is
excluded from all of it — but it should be reconciled before anyone analyses
VDDIO.

---

## 3. The supply pads, as built

Read from the database, not from the floorplan source:

| Net | Count | Master | Placement |
|---|---|---|---|
| VDD | 6 | `PVDD1DGZ_G` | 3 bottom (x = 310, 1110, 1270), 3 top (x = 230, 790, 1350) |
| VSS | 4 | `PVSS1DGZ_G` | 2 bottom (x = 390, 1350), 2 top (x = 310, 950) |
| VDDIO | 12 | `PVDD2DGZ_G` ×8, `PVDD2POC_G` ×4 | 3 per side |
| VSSIO | 12 | `PVSS2DGZ_G` | 3 per side |

Die `0 0 1600 2000`; core `205 205 1395 1795`.

**Every core supply pad is on the top or bottom edge. There is none on the left
or right, and the VDD/VSS counts are asymmetric (6 vs 4).** That is the
geometry that makes the resistance question in §4 worth asking, and it is why
VDD and VSS are measured separately rather than assumed to mirror.

The core and IO pads are *different master cells*, with no overlap — which is
what makes it possible to select exactly the ten core supply pads by master and
be certain nothing from the IO ring leaked in.

---

## 4. The IO ring — measured for the first time

`ASIC/genus-innovus/scripts/probe_pg_channels.tcl` existed, contained an
abutment-measuring block, and had **never been run** — no saved output anywhere
in the tree. It also pointed at a pre-pad-fix database, so even if it had been
run it would have measured the wrong pad set. It now defaults to the
pad-correct tapeout database and is overridable with `PGPROBE_DB`.

**Result — 493 `P*` instances, and ZERO abutment gaps on every side:**

| Side | Pad-ring cells | Gaps |
|---|---|---|
| bottom | 113 | **0** |
| top | 115 | **0** |
| left | 144 | **0** |
| right | 121 | **0** |

Why this matters: VDDIO and VSSIO are distributed by **abutment** through the
IO fillers and corner cells, not by routing. Both nets therefore raise
`IMPVFC-98` "no routing at all", and `check_connectivity` gives up on such a net
entirely — it cannot distinguish "abutted and fine" from "severed". This is the
failure mode where the chip is dead on arrival and every report is green.

Until now the continuity argument was arithmetic: the flow's own comment
(`4b_pnr_route_eval.tcl:1979-1983`) closes it by showing the four sides sum to
1330/1330/1730/1730 against a 1600×2000 die with four 135 µm corners, and then
says plainly: *"What remains unclosed is that NOTHING IN THIS FLOW VERIFIES
IT."* Two independent methods now agree — the arithmetic, and a direct
measurement on a routed database that has the pads.

**What this does and does not establish.** It establishes that the pad-ring
cells tile each edge with no lateral gap between adjacent cell bounding boxes:
86 explicitly placed pads (including the four `PCORNER_G`) plus 407 inserted
fillers. It does **not** prove electrical continuity of the supply buses
*inside* those cells — a filler of the wrong variant could abut geometrically
and still not connect — and the probe checks gaps *between* cells, not whether
the first and last cell on each side reach the die edge (the arithmetic above
covers that second point). Confirming the filler variants against the IO
databook is a paper check, and is the remaining step on this question.

---

## 4b. The diagnosis that led there — kept, because its traps are still live

**SETTLED 2026-08-17: the answer is H1, the tooling. See §4b-bis for the proof
and the numbers.** Everything from here to the end of this section is the state
of knowledge *before* that, preserved rather than rewritten, because each trap
in it will catch the next person and because "we suspected a dead chip and it
was a default option" is only a useful lesson if the suspicion is still legible.
Read it as history, not as an open question.

### What DID work

The power grid extracts correctly, and that is not a small result — it is the
first time this grid has been built into an electrical model at all:

```
Grid statistics, net VDD
  Total node                    852,190
  Total element (resistors)   1,118,378
  Total tap                     349,742
  Instance logically connected  338,903  of 339,390  = 99.86%
  Dropped for missing/incomplete cell library:  0
```

Parasitic extraction ran to completion against the QRC deck. The techonly PGV
built cleanly. So the model of the metal is sound.

### Where it stops

**No voltage source ever enters the circuit.** Every run ends:

```
Circuit total   852,191 nodes   1,118,378 resistors   332,976 current sources
                                                      0 voltage sources
** ERROR: (VOLTUS_RAIL-5097): All nodes of net VDD are disconnected.
```

With zero voltage sources there is no reference node, so `report_resistance`
writes an empty report — and, per trap 1 above, returns success while doing it.

Three independent ways of specifying the ten core supply pads were tried:

| Method | Result |
|---|---|
| `-format xy`, coordinates on PG metal inside each pad footprint (M7) | `Voltage Source Added/Total: 6/6 (100.00%)` → **0 in circuit** |
| `-format padcell`, master `PVDD1DGZ_G` | 6 pads matched (`VDD.padcells` lists all six) → **0 in circuit** |
| `-auto_voltage_source_creation -layer RV` | `0/0 (-nan%)` — no candidate via cuts found on that layer |

Note that "Voltage Source Added 6/6 (100.00%)" is **not** evidence of
attachment. It is printed on runs that end with none. The number to check is the
Voltage Sources column of the circuit profile.

### The two hypotheses, and which experiment separates them

**H1 — tooling.** The PGV is `techonly`, which models layers and vias but not
the inside of a cell. If the IO pad's PG pin is described only in its abstract,
there is no node there for a source to bind to. **Consequence: measure from the
grid instead; the resistance number is still real, just referenced to the
top-layer feed points rather than to the pad bumps.**

**H2 — design.** The pads genuinely do not reach the mesh in this database.
**Consequence: that is a dead chip and the most important finding on it.**

H1 is much the more likely — the same techonly PGV connected 99.86 % of
instances, and an earlier GDS-level inspection found the core VDD/VSS pads on
the rings — but **it is not proven, and it must not be assumed.** The
discriminating experiment was attempted and mis-aimed: auto-creation was pointed
at layer `RV`, which yielded no candidates, so it tested nothing.

**The next run, specifically.** *(This experiment was run, and it is a trap —
`-region` is silently ignored, so it produces sources over the whole die and a
flattering number. See trap 15. The experiment that actually settled it was
`-short_pin_nodes true`, §4b-bis.)* Re-run `reff_auto.tcl` with
`-auto_voltage_source_creation true` on a layer that certainly carries VDD via
cuts — `VIA8` has 9,013 and `VIA7` has 24,692 — constrained with `-region` to
the pad rows (`y < 210` and `y > 1790`) so the sources land where the pads feed
rather than across the whole die. If sources appear, H1 is confirmed and the
resistance map follows immediately. If they do not, escalate H2.

`ASIC/genus-innovus/rail/analyse_reff.py` is written and self-tested against a
synthetic dataset with a known gradient; it joins each instance's ohms to its
placement coordinate and reports the distribution, the worst points, an 8×10
spatial map and a band comparison built specifically to test the prediction that
falls out of the pad placement — that resistance peaks at **mid-height**, and
worst at the **left and right core edges**, because all ten core supply pads are
on the top and bottom edges. `inst_xy.txt` (339,390 rows) is already generated.
Everything is in place except the sources.

---

## 4b-bis. How H1 was proven, and the resistance numbers

### The one-word cause

`set_power_pads -format padcell` takes an option nobody had used:

```
-short_pin_nodes {true|false}     default FALSE
    "short all interface nodes on a pad cell pin to a single node and
     create voltage source for that node"
```

With it, the *identical* command that had produced zero voltage sources on
every previous attempt produces this:

```
  # Voltage Source Added/Total (%): 6/6 (100.00%)
  Circuit total  852,191 nodes  1,118,522 resistors  332,976 current sources
                                                     6 VOLTAGE SOURCES
  uPAD_VDD_B_0:VDD  x=1122.5  y=84.815    layer=metal7
  uPAD_VDD_B_1:VDD  x= 322.5  y=84.815    layer=metal7
  uPAD_VDD_B_2:VDD  x=1282.5  y=84.815    layer=metal7
  uPAD_VDD_T_0:VDD  x= 242.5  y=1915.19   layer=metal7
  uPAD_VDD_T_1:VDD  x= 802.5  y=1915.19   layer=metal7
  uPAD_VDD_T_2:VDD  x=1362.5  y=1915.19   layer=metal7
```

Six sources, at the six VDD pads, and four more at the four VSS pads — ten,
which is the number that has to appear. The reason the default fails is exactly
H1 and can be stated precisely: **a techonly PGV gives a pad cell no internal
nodes at all.** Its only nodes are the *interface* nodes where its PG pin meets
the top-level grid. The default asks for a source on a node that a techonly
model never builds; `-short_pin_nodes` collapses the interface nodes into one
and binds there, which for a bond pad is also the physically right thing to do.

That the same option is the fix for both nets, that the sources land on the pad
pins' own coordinates, and that the solve then reaches 99.8 % of instances, is
H1 confirmed from inside the tool.

### The independent confirmation, with no rail analysis at all

The tool proving itself innocent is not enough when the tool is the suspect, so
the pad-to-mesh connection was also checked directly against the drawn metal.
`ASIC/genus-innovus/rail/padgeom.tcl` dumps, in design coordinates, every
special wire that is not a followpin and every special via with its bottom and
top rectangles; `padconn.py` runs a union-find over them — same layer and
overlapping is one node, a via joins its own bottom and top rectangles — and
asks which component each pad's metal is in. It is self-tested against a
synthetic fixture containing a deliberately severed pad and a deliberately
connected one, and it reports each correctly.

Followpins are excluded on purpose: they are ~350k M1 row shapes that hang
*off* the mesh and can play no part in a pad-to-ring path.

Result on the tapeout database:

| | VDD | VSS |
|---|---|---|
| non-followpin special wires | 7,255 | 5,793 |
| special vias | 107,690 | 81,230 |
| geometric components | 368 | 306 |
| rectangles in the largest component | 221,901 of 222,905 (99.6 %) | 167,451 of 168,385 (99.4 %) |
| `ring` shapes in that component | 4 of 4 | 4 of 4 |
| `stripe` shapes in that component | 198 of 198 (100 %) | 206 of 206 (100 %) |
| `iowire` shapes in that component | **120 of 120 (100 %)** | **56 of 56 (100 %)** |
| pad PG pin shapes, transformed to design coords | 270 | 132 |
| transform self-check failures | 0 | 0 |
| **pads whose PG PIN RECTANGLE is in that component** | **6 of 6** | **4 of 4** |

`iowire` is the shape type `route_special -connect {pad_pin pad_ring}` draws
from a pad's PG pin, and the counts are not approximately right, they are
exactly the counts the router printed when it drew them — *"Number of IO ports
routed: 120"* for VDD and *56* for VSS, in the power-plan log. All 120 and all
56 are in the ring's component, evenly distributed at 20 per VDD pad and 14 per
VSS pad — which is also exactly how many M1 ports (and how many M2 ports) each
of those pads has. **The pads reach the mesh.** H2 is refuted by the metal
itself.

The pin rectangles were transformed out of cell coordinates with a containment
self-check: every transformed rectangle must land inside its pad's own placed
bounding box, and the run reports the failure count, which is 0 of 402. Each
VDD pad has 45 PG pin shapes (20 on M1, 20 on M2, one each on M3–M7) and 40 of
them — the M1 and M2 ports — are in the ring's component; each VSS pad has 33
and 28 are. The M3–M7 ports are alternate ports of the *same* logical pin, one
piece of metal inside the cell, and the router had no need of them.

That also explains a detail in the voltage-source report that would otherwise
look wrong: the sources bind at `layer=metal7`, on ports that carry no
top-level wire. `-short_pin_nodes` shorts all of a pad pin's interface nodes
into one before binding, so the source is the whole pin, and the current
actually leaves through the M1/M2 ports that `route_special` wired.

**The one way this test could be wrong, and why it is not.** `special_wire.rect`
is the *bounding box* for a polygon or a 45° path segment, so a union-find over
rectangles can only ever over-connect, never under-connect — which is the
direction that would produce a false "connected". That is exactly why the two
proofs are kept separate and both are required: the rail extractor is an
independent implementation that works from the real shapes against the QRC deck
and does not use bounding boxes, and with sources bound at the pad pins it
returns a finite resistance for 338,648 of 339,390 instances. Had the pads not
been connected, every instance would have come back `D/C` — which is precisely
what the 255 genuinely orphaned ones do. A bounding-box artefact cannot produce
that result.

**Sensitivity.** The union-find counts two rectangles as joined when they
overlap *or* merely touch. Re-run demanding a genuine 1 nm overlap
(`--eps -0.001`), the verdict is unchanged on both nets — 6 of 6 and 4 of 4
pads still in the ring's component, still 120 of 120 and 56 of 56 iowires — and
the component count moves by one on VSS. The answer does not rest on an
edge-touching convention.

**A third agreement, between the geometry dump and the solver's own model.**
The dump counts `special_via` *objects*; Voltus's extracted grid counts via
*cuts*, and a special via may be an array. On VIA8 the dump finds 5,893 VDD
objects and 3,120 VSS objects, and auto-creation — which places one source per
cut — makes 7,706 and 3,936 sources respectively. Those are exactly the VIA8
resistor counts in the extracted grid for the two nets. Two independent readers
of the same metal, arriving at the same numbers by different routes.

Two honest limits on that statement. First, the path from the bond-pad opening
to the pad cell's PG pin is *inside* the vendor cell and this site has only its
LEF abstract, so that last hop is taken on the abstract — as it must be for any
vendor IO. Second, the 30 VDD and 20 VSS `padring` shapes are **not** in the
ring's component (0 %), which is expected rather than alarming: the pad ring is
joined through the IO cells' internal buses by *abutment*, which is not drawn
metal and cannot appear in a geometric dump. Their continuity is the separate
measurement in §4, which found zero abutment gaps on all four sides.

### An asymmetry worth recording — and it invalidates the RV margin in §5

VDD has **no RV vias and no AP metal at all** in the top-level special routing.
Its via stack is VIA1–VIA8 and stops there. VSS has 7 RV vias and 5 AP shapes.
This is why the earlier auto-creation attempt on layer RV returned
`0/0 (-nan%)` for VDD — the tool said so plainly, `VOLTUS_RAIL_SMG-0142: no
layer VIA9 found` — while the same command on VSS silently *worked*, created 7
sources and produced a complete resistance report that nobody read.

Then look at what those seven VSS RV vias actually are:

```
  M9 (308.1 175.0)-(314.1 187.0)   -> AP        M9 (308.1 206.0)-(314.1 212.0)   -> AP
  M9 (1268.1 175.0)-(1274.1 187.0) -> AP        M9 (1268.1 206.0)-(1274.1 212.0) -> AP
  M9 (248.1 1812.4)-(254.1 1824.4) -> AP        M9 (788.1 1787.4)-(794.1 1794.4) -> AP
  M9 (788.1 1812.4)-(794.1 1824.4) -> AP
```

and the five AP shapes they land on are all `shape = stripe`, 3.6 µm wide, at
x ≈ 249, 309, 789 and 1269, spanning y 175–212 and y 1787–1824. They are
**stripe jumpers** — short M9→AP→M9 hops that let a stripe cross the ring band,
which `add_stripes -pad_core_ring_top_layer_limit AP` is entitled to make.
They are not a supply entry point, and they carry no VDD current because VDD
has no RV at all.

**Consequence, and it is not small.** §5 reports `pg_capacity`'s worst cut
plane as *"RV at 77.0 mA, margin 1.52×"* and calls it "the whole story… seven
vias carry the entire core supply from the top aluminium into the mesh". That
premise is **wrong**. The core supply does not enter through RV. It enters
through the pad cells — internally, on geometry this site cannot see — and
appears at top level as 120 VDD and 56 VSS `iowire` shapes on **M1 and M2**,
which then climb VIA1→VIA8 to the M8/M9 rings and stripes. Dividing the core's
full 50.7 mA demand by a plane that carries none of it is not a margin.

Two independent reads agree that VDD has no RV: the geometric dump above, and
Voltus's own extracted grid, whose VDD layer list starts at `metal9` with no
`metal10` and no `VIA9` row while VSS's has both.

**This bears directly on a live P&R gate.** `2b_pnr_place_eval.tcl` gates on an
RV via count with a floor of 8, and `30-ir-drop-gate-design.md` treats that as
the last thing guarding the tightest plane on the die. On this floorplan the RV
plane is not in the core supply path at all, so the count is not guarding the
core supply. That should be settled before either the gate or the document is
revised further; it is flagged here rather than acted on, because the gate is
owned elsewhere.

### The numbers

Effective resistance, pad-referenced, 125 °C, from the pad cells' own PG pins.
**VDDIO and VSSIO are excluded by name** — they are in no domain, in no
`set_pg_nets`, and carry no voltage source. Including them would return ~0 mV
and look excellent, because they have no routing and no attributed demand;
that is a false green by construction.

| | VDD (6 pads) | VSS (4 pads) |
|---|---|---|
| voltage sources in circuit | 6 | 4 |
| instances with a resistance | 338,648 | 338,599 |
| coverage | 99.8 % | 99.8 % |
| **disconnected (D/C)** | **255** | **302** |
| p50 | 5.99 Ω | 6.27 Ω |
| p90 | 7.94 Ω | 8.01 Ω |
| p99 | 9.40 Ω | 10.52 Ω |
| p99.9 | 24.47 Ω | 37.93 Ω |
| **max** | **46.16 Ω** | **52.81 Ω** |
| mean | 5.62 Ω | 5.84 Ω |

A cross-check that costs nothing. The VSS grid was also solved from the seven
auto-created sources on AP — a completely different set of injection points,
found by the tool rather than named by us:

| VSS | from 4 pad pins | from 7 AP feed points | difference |
|---|---|---|---|
| p50 | 6.2731 Ω | 6.1883 Ω | +0.085 |
| p90 | 8.0118 Ω | 7.9274 Ω | +0.084 |
| p99 | 10.5160 Ω | 10.4140 Ω | +0.102 |
| max | 52.8050 Ω | 52.7020 Ω | +0.103 |
| mean | 5.8382 Ω | 5.7526 Ω | +0.086 |

The two agree to 1.5 %, and the difference is a near-constant **+0.085 Ω** on
every percentile — which is what a series element common to all instances
should look like. That is the pad-to-AP hop, measured. Two independent source
placements, one of them chosen by the tool, give the same grid.

**The caveat that rides on every number in this section.** They come from the
archived tapeout database, which is **not frozen**: its `libs/lef/` entries are
symlinks into the live tree and both ROM LEFs were rebuilt two days after the
save, so `read_db_file_check false` is required and byte-equality with the
version used at save time cannot be demonstrated (trap 5). A better database —
pads, corrected ROMs and the 1505.60 floorplan — is being built; every number
here should be re-taken on it, and the scripts are parameterised on one `DB`
variable so that is a one-line change.

### How much of that resistance is the distribution network? About 3 %.

Solve the same VDD grid again with the sources moved from the ten pads to
**every one of the 7,706 VIA8 cuts** — i.e. delete the entire pad-to-mesh
distribution problem and inject directly into the top of the mesh everywhere:

| | 10 pad sources | 7,706 VIA8 sources |
|---|---|---|
| p50 | 5.99 Ω | 5.78 Ω |
| p90 | 7.94 Ω | 7.74 Ω |
| max | 46.16 Ω | 45.93 Ω |

Removing the whole distribution network changes the typical instance by
**0.21 Ω out of 6 Ω (3.5 %)** and the worst instance by 0.5 %. So the ring, the
stripes and the pad connections are **not** where this die's resistance lives:
roughly 97 % of it is the local tap — the last few microns from the mesh down
through the stack into the cell's own rail. That is the same fact the flat map
and the refuted prediction are both showing, measured a third way.

It is also a warning. A 7,706-source run is *not* a legitimate rail
configuration — it would let current enter the die anywhere — and it still
produced numbers within 4 % of the honest ones. "Sources attached" is not the
check. **How many, and where** is the check.

### The prediction was REFUTED

The prediction on record was that resistance should peak at **mid-height** and
be worst at the **left and right core edges**, because every core supply pad is
on the top or bottom edge. Measured, it is not true, and not marginally:

| band | VDD max / mean (Ω) | VSS max / mean (Ω) |
|---|---|---|
| bottom 20 % (nearest the pads) | 43.44 / 5.63 | 52.81 / 5.90 |
| top 20 % (nearest the pads) | 33.56 / 5.60 | 51.07 / 6.70 |
| **mid-height 20 % (farthest in Y)** | **17.34 / 5.58** | **38.84 / 5.75** |
| left 20 % | 20.97 / 5.39 | 51.07 / 5.96 |
| right 20 % | 46.16 / 5.46 | 19.30 / 5.52 |
| left edge AND mid-height | 8.51 / 5.29 | 9.09 / 5.72 |
| right edge AND mid-height | 17.34 / 5.68 | 19.25 / 5.74 |

**A refutation is only worth as much as the instrument's ability to have found
the thing.** So `analyse_reff.py` was re-run against a synthetic dataset built
to contain exactly the predicted pattern — resistance rising linearly from 1 Ω
at the top and bottom core edges to 10 Ω at mid-height, with the bus names
escaped the way Innovus escapes them and one `D/C` row mixed in. It reports
mid-height mean 9.10 Ω against 2.76 / 2.81 Ω at the edges, and 9.05 Ω for
"left edge AND mid-height". The instrument sees the pattern when it is there.
It reports none on this die because there is none.

Mid-height is the **best** Y band on both nets, not the worst. The left edge is
the **best** X band on VDD. The intersection the prediction called worst of all
— left edge at mid-height — is the *lowest* mean on the whole die for VDD
(5.29 Ω) and has the second-lowest maximum.

The reason is in `power_plan.tcl` and it is a good one: `add_rings -type
core_rings -follow core` puts a ring on **all four sides**. Read back out of the
routed database rather than off the command line, the eight ring segments are:

| net | side | layer | extent | width |
|---|---|---|---|---|
| VDD | bottom | M9 | x 191 → 1409 | 12 µm |
| VDD | top | M9 | x 191 → 1409 | 12 µm |
| VDD | left | M8 | y 191 → 1808.4 | 12 µm |
| VDD | right | M8 | y 191 → 1808.4 | 12 µm |
| VSS | bottom / top | M9 | x 175 → 1425 | 12 µm |
| VSS | left / right | M8 | y 175 → 1824.4 | 12 µm |

VSS sits concentrically outside VDD. **The pads feed the ring; the ring — not a
long lateral traverse through the mesh — feeds the left and right core edges.**
Supply pads on two edges therefore do not make a two-edge supply, and the
prediction, which reasoned from pad placement straight to core coverage, skipped
the ring. The grid is flat: p50 6.0 Ω and p90 7.9 Ω is a 1.3× spread across
90 % of the die.

### What the tail actually is, and it is not distance

Every one of the worst points is a sliver of standard-cell rows jammed against
a **macro edge**, not a point far from a pad:

| net | worst instance | Ω | what is beside it |
|---|---|---|---|
| VDD | `ENDCAP_PD_TOP_2405` (1234.8, 1171.6) | 46.16 | dense row block at a macro corner |
| VDD | `ENDCAP_PD_TOP_909` (879.8, 460.6) | 43.44 | macro occupies x < 870 |
| VSS | `ENDCAP_PD_TOP_548` (714.4, 368.8) | 52.81 | placement stops dead at x = 720 |
| VSS | `ENDCAP_PD_TOP_3612` (286.4, 1542.4) | 51.07 | placement stops dead at x = 290 |

The macro blocks the stripes, the rows in its shadow are fed from one side, and
the last cells in the row carry the whole detour.

The tail is small as well as localised — on VDD, against a p50 of 6 Ω:

| above | instances | share of the die |
|---|---|---|
| 10 Ω | 3,065 | 0.905 % |
| 15 Ω | 1,364 | 0.403 % |
| 20 Ω | 650 | 0.192 % |
| 30 Ω | 153 | 0.045 % |
| 40 Ω | 35 | 0.010 % |

VSS's tail is fatter but the same shape — 1.030 % above 10 Ω, 0.484 % above
20 Ω, 0.069 % above 40 Ω, 35 instances above 50 Ω — which is expected from four
supply pads against VDD's six.

Thirty-five instances on the whole die are above 40 Ω. And the 650 above 20 Ω
resolve, at 40 µm linkage, into just **nine spatial clusters**, every one of
them a thin strip:

```
  142 insts  x  546- 586  y 1308-1490   max 33.6 ohm
  112 insts  x  284- 286  y 1503-1767   max 21.0
   96 insts  x  880- 927  y  408- 461   max 43.4
   87 insts  x 1235-1288  y 1172-1173   max 46.2
   61 insts  x  546- 567  y 1218-1235   max 30.6
   57 insts  x  702- 714  y  365- 381   max 25.0
   46 insts  x  906- 927  y 1452-1469   max 30.8
   39 insts  x  906- 927  y 1362-1379   max 30.8
   10 insts  x  703- 723  y  279- 281   max 29.4
```

Several are two microns tall — a single standard-cell row. This is a grid with
nine sore spots at macro edges, not a grid with a distribution problem, and
that shape says the fix is local ECO work rather than a floorplan change.

### A defect this found that nothing else was measuring

**255 instances have no path to VDD and 302 have no path to VSS.** That is the
report's own word — `D/C`, "the instance is disconnected from the net" — not a
large resistance. They are 0.075 % and 0.089 % of the design, and they are
**not scattered**. Clustered at 40 µm they resolve into four distinct sites,
three of which break *both* supplies:

| site | x | y | VDD insts | VSS insts |
|---|---|---|---|---|
| A | 1034.2 – 1054.8 | 352.6 – 493.0 | 219 | 176 |
| B | 1051.8 – 1054.2 | 1544.2 – 1592.8 | 24 | 36 |
| C | 1043.2 – 1054.8 | 262.6 – 280.6 | 12 | 24 |
| D | 869.2 – 906.8 | 439.0 – 491.2 | — | 66 |

Sites A, B and C are the last sliver of standard-cell rows against the left
edge of the large macro block that runs from x ≈ 1060 to x ≈ 1386, where cell
density triples (580 per 10 µm bin against a typical 150) right up to the macro
edge and then falls to zero. Site D is the mirror case on the other side of a
different macro — the placement hole there is to the *left*, at x < 870.

Two independent tools agree on the location. The flow's own
`check_connectivity -type special` already reported 36 VDD and 30 VSS pieces
"not connected together" (`IMPVFC-200`), and the large majority of them sit in
the same band — x ≈ 1030–1059, y ≈ 263–1691. (It also lists a second cluster
around x ≈ 616–720 which orphans no instances: those pieces are stubs with no
cells on them, which is why the two lists are not identical.) It was 36 lines
among 589 informational messages in a report nobody had reason to place on the
die.

**It is a discrete open, not a starved region**, which matters for whoever
fixes it. The 9,632 instances inside site A's band that *are* connected read
p50 7.04 Ω, p90 8.63 Ω, max 15.26 Ω — only mildly above the die-wide 5.99 /
7.94 / 46.16. The band is not short of supply metal; a specific piece of it is
missing.

And the connectivity report says exactly which piece. Its open geometries in
these sites are all short horizontal strips one row tall, and they nearly all
**end at x ≈ 1058.9–1059.07** — the macro edge:

```
VDD  (1030.73 368.80)-(1059.07 371.33)     28.3 x 2.5 um
VDD  (1034.34 430.80)-(1059.07 432.53)     24.7 x 1.7
VDD  (1046.73 492.27)-(1059.07 493.73)     12.3 x 1.5
VSS  (1034.34 440.25)-(1059.07 441.60)     24.7 x 1.4
VSS  (865.74 490.64)-(910.90 491.89)       45.2 x 1.3   <- site D
```

That is the signature of **severed follow-pin row segments**: the last stretch
of each standard-cell row's M1 rail, running up to the macro edge, with nothing
tying it into the mesh above. The fix is vias into that sliver, not more
stripes — and the row-by-row pattern is why the count is in the hundreds of
instances rather than a handful.

This is a real, fixable defect — cells that will not power up — and it is
separate from the pad question. `analyse_reff.py` now counts and places `D/C`
rows rather than dropping them, so the next run cannot hide it, and the full
list with coordinates is written to
`ASIC/genus-innovus/rail/work/disconnected_instances.txt` (559 rows, net + x +
y + instance name) for whoever repairs them. That file lives under the
git-ignored `work/` tree; regenerate it with the `analyse_reff.py` step in the
reproduction recipe above.

### How to reproduce all of this

Every script takes the database from a single `set DB` line at its top, so
re-running the whole chain on the better database that is being built is one
edit per file. From `ASIC/genus-innovus/rail/work`:

```
innovus -stylus -nowin -files ../pgv.tcl      -log pgv_run      -overwrite < /dev/null
innovus -stylus -nowin -files ../padgeom.tcl  -log padgeom_run  -overwrite < /dev/null
innovus -stylus -nowin -files ../padpins.tcl  -log padpins_run  -overwrite < /dev/null
python3 ../padconn.py padgeom
python3 ../analyse_reff.py PadA_VDD/VDD_125C_reff_1/Reports/VDD/VDD.effr inst_xy.txt
python3 ../analyse_reff.py PadA_VSS/VSS_125C_reff_1/Reports/VSS/VSS.effr inst_xy.txt
innovus -stylus -nowin -files ../rail_static.tcl  -log rail_static_run -overwrite < /dev/null
# then build the demand file from the instance power report that step produced,
# and solve the rail from it (see trap 16 for why this is two steps, not one):
innovus -stylus -nowin -files ../rail_static2.tcl -log rail2_run       -overwrite < /dev/null
```

`< /dev/null` is not optional: an uncaught Tcl error leaves Innovus sitting at
a prompt holding an Innovus *and* a Voltus licence indefinitely. Do not name a
`-log` the same as an existing directory (trap 3) — `padgeom` is a directory,
`padgeom_run` is the log.

### Two bugs fixed in the analysis while doing this

1. **A 17 % silent join loss.** Innovus escapes bus brackets in the `.effr`
   report (`foo_reg\[44\]`) and does not in `get_db insts .name`
   (`foo_reg[44]`). Joining the two raw dropped **58,530 of 338,903 rows** —
   and every one was a bussed register, i.e. precisely the clustered datapath
   the spatial map exists to show. The failure mode was a smaller instance
   count, which looks like nothing. Names are now normalised on both sides and
   the join is 100 %.
2. **`D/C` parsed as a number.** A row whose resistance column is the literal
   `D/C` is a disconnected instance, not a zero-ohm one. It is now counted and
   reported separately instead of being silently skipped.

---

## 4c. Static rail — the pre-fix state, kept for its reasoning

**MEASURED 2026-08-17; the result is in §4c-bis.** The blocker described below
is gone. `rail_static.tcl` now carries `-short_pin_nodes true` on both
`set_power_pads` calls, and `rail_static2.tcl` takes the demand from an ASCII
instance power file (traps 16–18) and asserts the voltage-source count is 10
before believing any voltage it prints. The paragraph below is the pre-fix
state, kept because its method discipline is still exactly right.

`rail_static.tcl` is written, uses `-method static` (never `era_*`, whose
grid-completion invents virtual follow-pins and vias and would bridge exactly
the PG opens worth finding), and never `-stream_file` (a large fraction of the
metal in the streamed GDS is routing blockage streamed as conductor, which would
flatter every result). It asserts instance coverage, voltage-source count and
current accounting before believing any number.

It was **not run to a result**, because rail analysis needs the same voltage
sources that §4b cannot yet attach. A rail solve with zero voltage sources
cannot produce a drop; and a rail run with poor coverage reports *small* drops,
which is the failure mode that would look like good news. It is gated behind the
one experiment named above.

---

## 4c-bis. Static rail (IR drop) — MEASURED

**What this claim is, in one sentence:** static rail analysis at an ASSUMED
switching activity, from a `techonly` power grid library, die-only with no
package model, on a database that cannot be shown byte-identical to the one
saved. That is the strongest claim achievable on this site, and it is stated
here rather than in a footnote.

### The three coverage assertions, before any number

A rail run that fails to attach current reports **small** drops, which is the
failure mode that looks like good news. So:

| assertion | required | measured |
|---|---|---|
| instance coverage | high | **338,903 of 339,390 on VDD, 338,901 on VSS — 99.86 %** |
| voltage sources | **exactly 10** | **10** — 6 VDD pads + 4 VSS pads |
| current accounting | 0.90 – 1.10 | **0.997** (VDD), **1.000** (VSS) |

Current accounting in full: the solver loaded 50.567 mA on VDD and 50.688 mA on
VSS against the 50.70 mA that `report_power` attributes to the VDD rail
(54.76 mW / 1.08 V). `Rail Analysis completed successfully`, 0 violations
against the threshold, 341 artefacts written.

### The result

| | VDD (6 pads) | VSS (4 pads) |
|---|---|---|
| worst node | **1.074 V** | **+8.973 mV** |
| **worst deviation from nominal** | **6.33 mV droop** | **8.97 mV rise** |
| average deviation | ~5 mV | 7.25 mV |
| total current | 50.567 mA | 50.688 mA |
| violations vs threshold | 0 | 0 |

**Worst-case total supply collapse = 6.33 + 8.97 = 15.3 mV, or 1.42 % of
1.08 V.** VSS is the worse half, which is exactly what four supply pads against
six should give.

### Every pad carries current — the third refutation of H2

The solver reports the current drawn through each voltage source individually,
and **not one of the ten is zero**:

```
VDD  uPAD_VDD_B_1  8.988 mA     VSS  uPAD_VSS_T_1  13.113 mA
     uPAD_VDD_T_1  8.765 mA          uPAD_VSS_B_0  12.960 mA
     uPAD_VDD_T_2  8.485 mA          uPAD_VSS_B_1  12.558 mA
     uPAD_VDD_T_0  8.246 mA          uPAD_VSS_T_0  12.056 mA
     uPAD_VDD_B_0  8.145 mA
     uPAD_VDD_B_2  7.938 mA
```

A pad that did not reach the mesh would carry 0 A. All ten carry between 7.9
and 13.1 mA. After the geometry (§4b-bis) and the source attachment, this is
the third independent demonstration that the pads are connected, and it is the
most physical of the three: current is actually flowing through every one.

**Current sharing is good.** VDD spreads 7.938–8.988 mA about a mean of
8.428 mA — ±6.2 %. VSS spreads 12.056–13.113 mA about 12.672 mA — ±4.2 %. No
pad is doing double duty, which matters because the `pg_capacity` margins in §5
assume perfect sharing and this is the first measurement of how good that
assumption is. It is good to within about 6 %.

### Where the drop happens: the opposite of where the resistance is

| layer | worst drop on VDD |
|---|---|
| metal9 | 3.82 mV |
| metal8 | 3.86 mV |
| metal7 / 6 / 5 | 6.14 mV |
| metal4 / 3 / 2 | 6.15 mV |
| metal1 | 6.33 mV |

**About 60 % of the total droop (3.8 of 6.3 mV) has already happened by the
time current reaches M8** — in the rings and the pad connections — and the
entire descent through M7 down to the cell rail adds only 2.5 mV more.

That is the mirror image of the effective-resistance result in §4b-bis, and
both are correct because they answer different questions. *Effective
resistance* is dominated by the local tap, because only one instance's own
0.2 µA flows there. *IR drop* is dominated by the shared upper network, because
all 50.7 mA flows through it. Quoting either one alone gives a misleading
picture of where to spend metal; the pair says: **the rings and top stripes set
the droop, the local taps set the per-instance resistance.**

### The caveats, on the same page as the number

- **No switching activity.** No SAIF and no VCD exists anywhere in this flow.
  50.7 mA is `report_power`'s default-activity estimate. The relative map is
  dominated by the grid and is sound; the absolute millivolts inherit this
  assumption entirely.
- **The threshold is a convention, not a budget.** 1.026 V (5 %) was chosen to
  make the pass/fail column meaningful. "0 violations" means "0 violations of a
  limit nobody derived". It does not change a single computed millivolt.
- **Die-only.** No package model, so bond-wire and package drop are excluded.
  Add them before comparing against any system-level budget.
- **`techonly` PGV.** Cell internals are not modelled, here or ever on this
  site. The drop reported is to each cell's PG pin, not to its transistors.
- **Static only.** Dynamic droop, di/dt and decap effectiveness remain
  permanently unmeasurable here (§8), and 15.3 mV static says nothing about
  them.
- **269 current sources are disconnected** — the same orphaned instances as
  §4b-bis. Their demand is not in the 50.567 mA, which is one reason the
  accounting ratio is 0.997 rather than 1.000.
- **The database is not frozen** (trap 5).

---

## 5. `pg_capacity` — a margin, for the first time

The step had run before and produced half its output. Both halves were broken
by the same class of defect, and neither had ever been noticed because neither
fails: each silently omits.

### 5.1 "core box unavailable — lateral scan skipped"

The diagnosis on record was that `get_db current_design .core_bbox` "returned
nothing". **It does not.** It returns

```
{205.0 205.0 1395.0 1795.0}
```

— a perfectly good core box, but as a **list of rectangles**, so on a
single-core design it is a ONE-element list whose single element is the 4-list.
The guard was `if {[llength $box] != 4}`, which is true for a correct answer.
The lateral capacity of the mesh — M5/M8/M9/AP, the actual bottleneck — was
skipped on every run because of a missing unwrap, not a missing attribute.

Fixing that exposed a **second instance of the same bug one level down**:
`get_db <shape> .rect` is also a list-of-rectangles, so `pg_cap_scan_layer`'s
`[llength $r] != 4` test discarded *every* shape on *every* layer. The rects
list was always empty, the proc returned "" ten times, and the report printed a
table header with no rows beneath it. Both are fixed, and the scan now warns
loudly if a layer has PG shapes but yields no usable rectangle, so the next
change in the tool's return shape is noisy instead of silent.

### 5.2 "estimated core demand unavailable"

`ROUTE_PG_DEMAND_MA` was 0, so the step fell back to parsing `report_power`.
The matcher required the total row to end in a unit token:

```
^\s*Total\s+.*?([0-9]+\.?[0-9]*)\s*(mW|W)\s*$
```

Innovus does not write one. The row is `Total Power:   78.88605883`, with the
unit declared once, far above, as `*  Power Units = 1mW`. The regex never
matched, so **no margin has ever been computed by this step** — for want of a
unit token that was never going to be there.

The replacement parses the declared unit, the total, **and the per-rail table**,
which is the only place `report_power` states the voltage it used. It is
unit-tested against both a pad-less build's report and the pad-correct one.

### 5.3 The result

Run on the pad-correct database, with `report_power` re-run on that same
database so the milliwatts and the metal come from one design:

```
core demand         50.7 mA        (VDD rail 54.76 mW / 1.08 V)
WORST PLANE         RV at 77.0 mA  margin 1.52x
```

Per-layer margins now exist for every cut plane. They are enormous for VIA1–VIA8
(1650×–7400×) and then fall off a cliff:

| plane | vias | total mA | margin |
|---|---|---|---|
| VIA4 | 61759 | 176173 | 3475× |
| VIA7 | 24692 | 376766 | 7431× |
| VIA8 | 9013 | 151715 | 2992× |
| **RV** | **7** | **77.0** | **1.52×** |

(Current-density limits per layer are foundry tech-LEF values and are
deliberately not reproduced here; the report itself is git-ignored for the same
reason.)

And the lateral scan, which had never produced a single row before:

| layer | dir | shapes | min mA | margin |
|---|---|---|---|---|
| M1 | hori | 6614 | 108.9 | **2.15×** |
| M2 | vert | 474 | 0 | no continuous cross-section |
| M3 | hori | 98 | 0 | no continuous cross-section |
| M4 | vert | 4110 | 0 | no continuous cross-section |
| M5 | hori | 3376 | 88.0 | **1.73×** |
| M6 | vert | 440 | 0 | no continuous cross-section |
| M7 | hori | 34 | 0 | no continuous cross-section |
| M8 | vert | 52 | 1551.8 | 30.61× |
| M9 | hori | 59 | 7085.6 | 139.74× |
| AP | vert | 5 | 0 | no continuous cross-section |

(The narrowest-cross-section column is omitted deliberately: published beside
the current it would let the foundry's per-micron limit be recovered by
division. The report on disk carries both and is git-ignored for that reason.)

A **zero** here is not a bottleneck — it means at least one scan line crossed no
PG metal on that layer, i.e. the layer does not form a continuous lateral plane
across the core. That is the correct and expected answer for the stitching
layers, which carry local stubs rather than distribution. The first version of
this fix let M2's zero become "WORST PLANE, margin 0.00×", which is a false
alarm in the headline; zero-cross layers are now labelled and excluded from the
verdict.

**So three planes sit in the same narrow band, and they are the real answer:**

```
RV (cut, 7 vias)      77.0 mA    1.52x
M5 (lateral)          88.0 mA    1.73x
M1 (lateral, followpins) 108.9 mA 2.15x
```

M8 and M9 — the rings and stripes people worry about — are 30× and 140× clear.
The tight points are the top-level via transition and the two fine layers.

> **WITHDRAWN 2026-08-17 — the RV row above is not a margin.** The paragraph
> that followed here said "the RV plane is the whole story: seven vias carry the
> entire core supply from the top aluminium into the mesh." They do not. Net VDD
> has **no RV via and no AP metal anywhere in the top-level special routing**;
> all seven RV vias belong to VSS and are M9→AP→M9 stripe jumpers over the ring
> band. The core supply enters through the pad cells' own internal geometry and
> appears at top level on **M1 and M2**. Dividing the core's full 50.7 mA demand
> by a plane none of it crosses produces a number, not a margin. See §4b-bis for
> the evidence, from two independent reads of the database. The M5 (1.73×) and
> M1 (2.15×) lateral figures are unaffected and remain the real answer.

**Every caveat that belongs to it, on the same page:**

- The demand has **no switching activity behind it** — no SAIF, no VCD anywhere
  in this flow. 50.7 mA is `report_power`'s default-activity estimate.
- It is **core-only**. A further **16.32 mW sits on `report_power`'s "Default"
  rail** — power the tool could not attribute to any declared rail, because
  VDDIO/VSSIO are absent from the CPF power intent. That is roughly the IO ring:
  real current, through a path none of this measures. The report now names it
  explicitly rather than folding it in or dropping it.
- The capacity side assumes **perfect current sharing** across every via on a
  plane. Real grids crowd. For a 7-via plane that assumption is doing a great
  deal of work.
- This is **DC average only** — the lenient limit. No AC, RMS or peak check.
- It is **not IR drop**. It computes no voltage anywhere.

---

## 7. Traps found while doing this, which will catch the next person

Written down because every one of them produces a result that looks fine.

**1. `report_resistance` prints `**ERROR` and returns success.** The first
attempt wrapped it in `catch`, got a clean return for both nets, and printed
`REFF-OK VDD` / `REFF-OK VSS`. The command had written no file at all. A
`catch` tests whether Tcl raised, not whether anything was measured. Every
script in `rail/` now asserts the **artefact** — existence *and* non-zero size —
and dumps the output directory when it is missing.

**2. A zero-byte report at the end of a symlink.** The next attempt did produce
`REFF/effr.rpt`, which is a symlink to `Reports/<net>/<net>.effr`. The symlink
existed; the target was 0 bytes. `file exists` would have passed it.

**3. `-log <name>` silently becomes `<name>/innovus.log` if `<name>` is a
directory.** The PGV run wrote its log inside `pgv/`, so the stale log from the
previous failed run was still sitting at `pgv.log` reporting `PGV-FAIL` while
the PGV had in fact been built. Two contradictory verdicts, both real files.

**4. A PGV library is a DIRECTORY, not a file.** `techonly.cl` is a directory.
`file size` on it returns 4096, so a naive "exists and non-empty" check passes
whether or not the library was built.

**5. The archived tapeout database is not frozen.** Its `libs/lef/` entries are
**symlinks into the live repository**, not copies. Both ROM LEFs were
regenerated on 2026-08-14, two days after the database was saved, so `read_db`
refuses it with `IMPIMEX-7024`. No pre-08-14 copy survives anywhere — every
historical `libs/lef/rom_via.lef` in every run directory is a symlink to the
same live file — so byte-equality with the version used at save time **cannot be
demonstrated**. Work proceeded with `read_db_file_check false` on the reasoning
that LEF is a physical abstract and the rebuild changed the ROM's `-code_file`
(its contents) while `-words/-bits/-mux/-top_layer` are unchanged. Expected, not
proven; it is a caveat on every number taken from this database, and a good
argument for archiving run directories with real copies.

**6. The PGV generator refuses its own auto-generated layer map.**
`VOLTUS_LGEN-4123` requires `-lef_layer_map` to be supplied explicitly. This is
the tool being right: at the top of this stack `metal9→M9`, `VIA9→RV`,
`metal10→AP`, and a silent mis-mapping there would misprice exactly the layers
that carry current in from the pads. The map is frozen at
`ASIC/genus-innovus/rail/inputs/lef_layermap.txt` with its provenance.

**7. Voltus proper cannot read this database; Innovus can.** The `voltus`
binary aborts during `read_db` with `IMPESI-3490` — "cdB based analysis is not
supported with CMMMC configuration". The identical rail commands
(`set_rail_analysis_mode`, `set_power_pads`, `set_pg_nets`, `report_resistance`,
`write_pg_library`, `report_rail`) are all present **inside Innovus**, which
reads the database without complaint. All rail work here runs under Innovus and
checks out the Voltus features on demand.

**8. The pad-cell voltage-source file rejects comments.** The manual's own
example shows `*` banner comments; this parser answers
`VOLTUS_RAIL_SMG-0041: line 1: Syntax error`. The files hold a bare cell name
and the explanation lives in the script.

**9. `-short_pin_nodes` defaults to FALSE, and without it `-format padcell`
attaches nothing while reporting 100 %.** This single default cost the project
a week and nearly cost it a dead-chip scare. See §4b-bis.

**10. `-def_shape_only` defaults to TRUE, so auto-creation cannot see a pad at
all.** Its own documentation: "when this parameter is set to false, voltage
sources are created for both the DEF routing shapes and shapes inside cell
instances." At the default, an auto-creation run is structurally incapable of
finding a pad cell, so using it to test whether pads are reachable tests
nothing.

**11. One net can succeed silently while the other fails loudly.** The
auto-creation run on layer RV printed `VOLTUS_RAIL_SMG-0142 ... no layer VIA9
found` and `0/0 (-nan%)` for VDD — and for VSS, in the same run, created 7
sources, solved the grid and wrote a complete 39 MB effective-resistance
report. The failure was read; the success in the second half of the same log
was not. Always check every net's circuit profile, not the first one that
errors.

**12. Orientation strings are lower-case in this database.** `get_db inst
.orient` returns `r0` and `r180`, not `R0`/`R180`. A case-sensitive comparison
against the documented spellings silently skips every pad. This was caught only
because the guard that did the comparison was written to *count and announce*
its skips instead of quietly falling through — a coordinate transform under an
unrecognised orientation would have produced ten plausible, wrong rectangles.

**13. `get_db insts .name` and the `.effr` report escape bus brackets
differently.** `foo_reg[44]` against `foo_reg\[44\]`. Joining them raw drops
17 % of the design — all of it bussed registers — and the only symptom is a
smaller row count.

**14. "Voltage sources attached" is not the check; the count and the location
are.** An auto-creation run that put a source on all 7,706 VIA8 cuts — every
via on the layer, an illegal configuration that lets current enter the die
anywhere — produced a resistance distribution within 4 % of the honest
ten-source one. Nothing in the output looked wrong.

**15. `-region` did not restrict auto voltage-source creation, silently.** This
one matters more than the rest, because restricting auto-creation to the pad
rows with `-region` was the *named next experiment* in the previous revision of
this document. It was run:

```
set_power_pads -net VDD -auto_voltage_source_creation true -layer VIA8 -region {0 0 1600 210}
set_power_pads -net VDD -auto_voltage_source_creation true -layer VIA8 -region {0 1790 1600 2000}
```

and produced **7,706 sources spanning y = 192.95 to 1807.8** — the full core
height, identical in count to the unrestricted run, with only 2,162 of them
inside the two declared regions. VSS behaved the same way (3,936 sources, every
VIA8 cut on the net). No warning on either. Had that been the experiment
that "worked", it would have produced a complete, plausible, flattering
resistance map referenced to injection points spread over the whole die.

Stated precisely, because the tool may not be at fault in the way it looks:
what is *observed* is that two accumulated `-region` calls yielded the same
source set as none at all. A single `-region` call, or `-region` together with
`-tile`, may behave differently — that was not tested. What is certain is that
the declared region cannot be assumed: **read the `<net>_vsrcs.rpt` coordinates
and check them against the region you asked for.**

**16. `report_power -rail_analysis_format VS` under Innovus does not write the
current files `set_power_data -format current` wants.** It writes an ASCII
per-instance power report. `-format current` wants `*.ptiavg`, which Voltus's
own power engine produces. A rail script that globs for `*.ptiavg` therefore
aborts with "no demand to solve" after a seven-minute power run that in fact
succeeded — the 33 MB instance report it produced totals 78.8859 mW against
`report_power`'s own headline of 78.88606, i.e. every instance is present. The
documented route for this case is `set_power_data -format ascii` with a
three-column `<instance> <power in W> <power pin>` file, which is what
`rail_static2.tcl` uses.

**17. `report_rail` requires the domain/net name LAST, and prints an error and
returns success if it is not.** Written as

```
report_rail -type domain ALL -output_dir $OUT      # WRONG
```

the answer is `**ERROR: (VOLTUS-1030): Bad option: ALL.` with a **zero return
code** and no output directory. The correct form puts the name at the end:

```
report_rail -type domain -output_dir $OUT ALL      # RIGHT
```

Then, with the name in the right place, `ALL` is rejected as well:

```
**ERROR: (VOLTUS-1123): ALL is not a valid power domain.
```

— also with a zero return code — even though the same reference page states
*"You can specify the variable ALL to analyze all domains"* and gives it as a
worked example. The domain has to be named: `PD_TOP`, the one declared by
`set_rail_analysis_domain`.

And then, with both of those right, a third refusal:

```
**ERROR: (VOLTUS-1246): Domain threshold must be specified using
set_rail_analysis_domain or net thresholds must be specified using
set_pg_nets before analyzing domain PD_TOP.
```

— again returning success. A threshold is mandatory before a rail solve will
run at all. **It is a reporting filter, not a budget**: it sets the pass/fail
column and the IR plot range and does not change a single computed millivolt.
Nobody on this project has derived an IR budget, so `rail_static2.tcl` uses the
5 % convention (VDD ≥ 1.026 V, VSS ≤ 0.054 V) and says so in its own output,
precisely so that no later reader mistakes a conventional number for an
engineered one.

That is now the third, fourth and fifth command invocation in this family
observed to print `**ERROR` and return success, after `report_resistance`. Treat it as the
family's default behaviour rather than as a series of separate surprises:
**assert the artefact, always.** The assertion in `rail_static2.tcl` caught
both of these inside two minutes each, which is the only reason two wrong
syntaxes cost twenty minutes instead of a day.

**18. An edit to a running script does not take effect, and looks like it
should have.** `rail_static.tcl`'s current-file glob was widened while the run
was in flight; Innovus had already read the file at `source` time, so the run
failed with the old message and none of the new diagnostics. Obvious in
hindsight, easy to misread as "the fix did not work".

---

## 8. What cannot be measured here, and why

Stated as limits of the site, not as work not yet done.

**Cell-accurate PGV — impossible here.** `set_pg_library_mode -cell_type
stdcells|macros` needs cell SPICE netlists or cell GDS to model the path from a
cell's PG pin to its transistors. This site has LEF abstracts and `.lib` timing
only. Only `techonly` can be built, which models the grid — layers, vias, their
resistances — and treats each instance as a tap at its PG pin.

**Therefore: no dynamic rail analysis, at all.** Not "unrun". Dynamic droop,
di/dt and decap effectiveness cannot be assessed on this site by any route.
This should be stated to the recipient as a hand-off item alongside LVS and
metal fill, not carried as an open action.

**No switching activity.** No SAIF and no VCD exists anywhere in this flow, so
every current here descends from `report_power`'s default activity assumption.
Relative comparisons are sound; absolute margins carry that assumption.

**No package model.** Voltage sources are declared with no package R/L/C, so
every number is **die-only** and excludes bond-wire and package drop.

**30.6 % of chip power cannot be attributed to a rail.** The IO group is
30.57 % of total power, and VDDIO/VSSIO are absent from the CPF power intent, so
`report_power` files 16.32 mW on an unnamed "Default" rail at the *core*
voltage. Two consequences, both important:

1. Any core margin quoted here excludes it, deliberately.
2. **A rail analysis that INCLUDES VDDIO/VSSIO would return ~0 mV and look
   excellent** — because those nets have no routing and no attributed demand.
   That is a false green, and it is the single most likely way for someone to
   produce a reassuring IR-drop number for this die that means nothing. If IO
   rail analysis is ever wanted, the power intent has to declare VDDIO/VSSIO
   first.

---

## 9. Where this leaves the die

**Measured, and standing:**

- The IO ring abuts with zero gaps on all four sides. The dead-on-arrival
  failure mode that no report could have caught is ruled out geometrically.
- Core demand is 50.7 mA at 1.08 V, on default switching activity.
- The narrowest *lateral* planes are **M5 at 1.73×** and **M1 at 2.15×** of that
  demand — DC-average electromigration, assuming perfect current sharing.
  **The RV figure of 1.52× is withdrawn**: net VDD has no RV via and no AP metal
  anywhere in the top-level special routing, so that plane carries none of the
  core supply and the margin was computed against a plane the current does not
  cross (§4b-bis). This also means the RV-via-count gate in
  `2b_pnr_place_eval.tcl` is not guarding the core supply path.
- The core supply grid extracts into an 852,190-node electrical model reaching
  99.86 % of instances.
- **All ten core supply pads reach the core ring.** Proven twice: by geometry,
  with a union-find over the drawn special-wire and via rectangles that puts
  every pad's PG pin rectangle in the ring's connected component; and by the
  rail solver, which now binds all ten voltage sources at the pad pins. The
  dead-chip hypothesis (H2) is **refuted**, not merely unconfirmed.
- **Effective resistance, pad-referenced**: VDD p50 5.99 Ω / max 46.16 Ω, VSS
  p50 6.27 Ω / max 52.81 Ω, at 99.8 % instance coverage (§4b-bis).
- **Static IR drop, pad-referenced**: worst VDD droop **6.33 mV**, worst VSS
  rise **8.97 mV**, total **15.3 mV = 1.42 % of 1.08 V**, at 99.86 % instance
  coverage, 10 voltage sources and current accounting 0.997/1.000 (§4c-bis).
  Static, at an assumed activity, die-only — the strongest claim this site
  supports.
- **All ten pads carry current**, 7.9–13.1 mA each, sharing to within ±6 %.
  Nothing is at zero, and nothing is doing double duty.
- **Where the metal matters**: ~60 % of the droop occurs at or above M8, in the
  rings and pad connections; the whole descent to the cell rail adds 2.5 mV.
  Effective resistance says the opposite because it weights the local tap —
  both are right, and quoting either alone misdirects where to spend metal.
- **The grid is flat, and the pad placement does not matter.** The prediction
  that the left and right core edges would be starved because no core supply
  pad is on those edges is **refuted**: they are the *best* bands on the die.
  The ring runs on all four sides, so it — not a lateral traverse through the
  mesh — feeds them. Removing the entire distribution network (7,706 sources
  instead of 10) moves the typical instance by 3.5 %.

**A defect found, not previously localised:**

- **255 instances have no path to VDD and 302 none to VSS**, concentrated in a
  ~20 µm band of standard-cell rows against a macro edge at x ≈ 1034–1055,
  y ≈ 263–1592. The flow's own `check_connectivity` already saw this (36 and 30
  `IMPVFC-200` pieces at the same coordinates) but reported it as 66 lines
  among 976 informational messages and never placed it. This is separate from
  the pad question and is fixable.

**Not measurable here at all:**

- Dynamic rail analysis, and any cell-accurate PGV. Hand-off item, alongside
  LVS and metal fill.

**The judgement call this now supports — revised.** The earlier revision of
this section said "do not retire the RV-via-count gate until the resistance run
lands", on the reasoning that the count was the only thing guarding the
tightest plane on the die. The resistance run has now landed, and it removed
the premise rather than confirming it: **RV is not in the core supply path**,
because net VDD has no RV via and no AP metal at top level (§4b-bis). A floor
of 8 on a plane that carries no core current is not a guard, whatever number is
chosen for it.

What should replace it is now measurable rather than aspirational. The planes
that *are* in the path are M1 and M5 laterally, and VIA1–VIA8 as cut planes,
and effective resistance is available per instance on both nets. The concrete
proposal — for whoever owns `2b_pnr_place_eval.tcl` and
`30-ir-drop-gate-design.md`, not for this document — is a gate on the measured
quantity: p99.9 effective resistance per net, plus a hard zero-tolerance check
on `D/C` instance count, which today would read 255 on VDD and 302 on VSS and
would have caught the macro-edge opens the moment they appeared.
