# 07 — `filler.tcl` and `place_bondpads.tcl`, annotated

`nanosoc_eth_chiplet_pads` · Cadence Innovus 21.11-s130_1 · **Stylus / Common UI**

A line-by-line reference for the two scripts that finish the die: core filler +
antenna-diode insertion, and the staggered bond-pad ring. Every Innovus claim on
this page is cited to a manual page that was opened on this machine; every
project claim is cited to a file and line, a log line, or a LEF.

Companion to [`../06-fill-antenna-bondpads.md`](../06-fill-antenna-bondpads.md),
which is the *stage* narrative. This page is the *command* reference, and where
the two disagree, this page states so explicitly.

**Manual paths used here** (all under `$INNOVUS_HOME/doc/`):

| Short form | Path | Product version string on the page |
|---|---|---|
| Stylus TCR | `TCRcom/<cmd>.html` | Innovus Stylus Common UI Text Command Reference, 21.11, July 2021 |
| Stylus UG | `UGcom/<Chapter>.html` | Innovus Stylus Common UI User Guide, 21.11, July 2021 |
| Messages | `innovuserrmsg/<ID>.html` | Innovus Error Message Reference, 21.10, May 2021 |

**Every command quotation on this page comes from `TCRcom/` or `UGcom/`** — the
Common UI editions, which are the ones that describe the command set this flow
actually runs. The install also carries `innovusTCR/` and `innovusUG/`, the
**legacy-UI** editions covering a different command set (`addFiller`,
`ecoRoute`, `verifyGeometry`, `addMetalFill`). Those are referenced twice below,
both times only to name the legacy spelling of something — never as a source for
behaviour. If you find yourself reading `innovusTCR/addFiller.html` to understand
this flow, you have the wrong manual open.

---

## Contents

1. [What these two steps are for](#1-what-these-two-steps-are-for)
2. [`filler.tcl`, block by block](#2-fillertcl-block-by-block)
3. [The filler trap: `IMPSP-5110`, and how to make it impossible](#3-the-filler-trap-impsp-5110-and-how-to-make-it-impossible)
4. [`place_bondpads.tcl`, block by block](#4-place_bondpadstcl-block-by-block)
5. [What is not done and would be needed for a real tapeout](#5-what-is-not-done-and-would-be-needed-for-a-real-tapeout)
6. [Stream-out: `write_stream`, the layer map, and the empty cells](#6-stream-out-write_stream-the-layer-map-and-the-empty-cells)
7. [Command index and quick checks](#7-command-index-and-quick-checks)

---

## 1. What these two steps are for

### 1.1 Base-layer density fill — why gaps in the rows are a manufacturing defect

After detailed routing there are still gaps between standard cells: sites where
nothing was placed. Physically that is not empty space, it is *missing diffusion
and missing poly*. Two things go wrong.

**Chemical-mechanical polish.** Each layer is planarised by grinding. The removal
rate depends on the local pattern density: a sparse region dishes, a dense region
stays proud. Dishing on one layer becomes a thickness error on every layer above
it. The foundry defends against this with per-layer density windows, and this
PDK's tech LEF states them explicitly for every routing layer, through four
keywords per `LAYER` block: `MINIMUMDENSITY`, `MAXIMUMDENSITY`,
`DENSITYCHECKWINDOW` and `DENSITYCHECKSTEP`.

> Vendor tech-LEF rule values redacted — TSMC licence forbids reproduction. Source:
> `PRTF_EDI_N65_<stack>_RDL.<rev>.tlef`, the `LAYER` blocks for M1–M9 and AP. Read
> the four density keywords there before planning any fill.

So each layer must reach a minimum metal fraction inside a sliding window, and must
also stay under a cap. The floors, the caps and the window sizes are **not** uniform
across the stack — the upper metals differ from the thin ones on all three — so a
fill strategy tuned on one layer does not transfer to another. Those are foundry
rules sitting on disk, and §5 covers the fact that nothing in this flow checks
them.

**Well and rail continuity.** The Stylus manual states the primary purpose of
filler directly — Stylus TCR, `add_fillers` (`TCRcom/add_fillers.html`):

> Inserts filler cell instances in the gaps between standard cell instances.
> Filler cell instances provide continuity for the power and ground rails, as
> well as for n-wells.

A gap in a row is a gap in the M1 VDD/VSS rail and a break in the n-well. Filler
cells carry both across.

### 1.2 The antenna diode — plasma-induced gate damage

During plasma etch of an upper metal layer, any conductor connected to a gate
acts as a charge collector. Charge has nowhere to go except through the thin gate
oxide, and if the ratio of collecting metal area to gate area is high enough the
oxide is damaged before the die is ever powered. The fix is a reverse-biased
diode to substrate on the net, which gives the charge a path that is not the
gate.

TSMC's cell for this is `ANTENNA` in `tcbn65lp`. Its abstract was read directly
from `tcbn65lp_9lmT2.lef` (the `MACRO ANTENNA` block, from line 3657 onward). What
it declares: `CLASS CORE`, on the `core` site, **two sites wide and one row tall**
— the same footprint as `FILL2` — with the standard abutment VDD/VSS rails and a
single input pin `I` that carries an `ANTENNADIFFAREA` value and **no**
`ANTENNAGATEAREA`.

> Vendor LEF geometry redacted — TSMC licence forbids reproduction. Source:
> `$TSMC_65_HOME/CMOS/LP/stclib/9-track/tcbn65lp-set/.../lef/tcbn65lp_9lmT2.lef`,
> `MACRO ANTENNA`.

`ANTENNADIFFAREA` and no `ANTENNAGATEAREA` is the signature of a diode: it
*supplies* diffusion area to a net, it does not consume gate area. It is two
sites wide and sits in a core row like any filler, which is why this flow inserts
it through `add_fillers`. **Whether the diodes this flow inserts are electrically
connected to anything is a separate question, and the answer is no — see §2.8.**

### 1.3 The staggered bond-pad ring

A wire-bond die needs an aluminium opening per signal, large enough for a
capillary to land a ball on. The openings, not the drivers, set the pitch.

Both cells used here come from TSMC's `tpbn65v` bond-pad library
(`config.tcl:134` → `.../iolib/tpbn65v_<rev>_FE/.../lef/tpbn65v_9lm.lef`). Read
out of that LEF:

| | `PAD70GU` (outer) | `PAD70NU` (inner) |
|---|---|---|
| `CLASS` | `BLOCK` | `BLOCK` |
| Cell height (the number the floorplan has to clear) | 86.685 µm | 171.000 µm |
| AP opening | one rectangle, same size in both cells | ditto |
| Where the opening sits in the cell | at the bottom of the cell body | **102 µm higher** |
| `PIN` statements | **none** | **none** |

> Vendor LEF geometry redacted — TSMC licence forbids reproduction. The AP-opening
> rectangles, the polygon wings and the full `SIZE`/`OBS` statements are in
> `$TSMC_65_HOME/iolib/tpbn65v_<rev>_FE/.../lef/tpbn65v_9lm.lef`, macros `PAD70GU`
> and `PAD70NU`.

The two cells carry the **same aluminium opening**; the only difference is where
along the cell it sits. That 102 µm offset *is* the stagger, and 171 µm is where
this design's bond-pad keep-out comes from.

The trade, stated plainly:

- **Inline (one row).** Along-ring pitch is bounded below by the AP opening plus
  the AP-to-AP spacing rule — call it ≳ 60 µm here. Costs one pad-cell height of
  die perimeter; buys the fewest pads.
- **Staggered (two rows).** Consecutive pads alternate rows, so the *along-ring*
  pitch of pads within a row doubles while the pitch of the ring as a whole
  halves. Buys roughly 2× the pad count for a given die perimeter.
- **What it costs.** (a) Area: the inner row reaches 171 − 86.685 = 84.3 µm
  further inboard than the outer row, and on this design that forced
  `CORE_TO_IO` from 50 to 70 — 20 µm per side, 112,800 µm², **5.6 % of the core**
  (`floorplan.tcl:58-60`). (b) Routing: the inner row's M8/M9 blockage lands on
  exactly the layers the core power rings use. §4.5.

---

## 2. `filler.tcl`, block by block

153 lines, of which 86 are the header. Sourced from `place_bondpads.tcl:29`,
which is itself sourced from `4_pnr_route.tcl:39` — i.e. **after** `route_design
-global_detail` and `opt_design -post_route -hold`.

### 2.1 Lines 1–86 — the header

The header is not decoration; it is the only record of two bugs and one
unverified command. Its three load-bearing claims, all independently confirmed
here:

- **Two different repairs, not one.** Lines 34–35:
  ```
  ##       filler cell vs adjacent CELL  ->  add_fillers -fix_drc  (needs markers)
  ##       filler cell vs NET routing    ->  route_eco             (needs a router)
  ```
  Confirmed by Stylus TCR, `add_fillers` (`TCRcom/add_fillers.html`): *"This
  command resolves only filler-related violations; it cannot resolve net-based
  violations. To repair net-based violations, reroute the violated net(s)."*
- **Legacy vs Stylus spelling.** Lines 38–45 note that both warning texts use
  legacy-UI names. That is correct and worth repeating, because it is the single
  most confusing thing about reading Innovus logs in Stylus mode: **the messages
  are not renamed.** `IMPSP-9082` says `verifyGeometry` and `-fixDRC`;
  `IMPSP-5217` says `addFiller` and `ecoRoute`. The commands you actually type
  are `check_drc`, `-fix_drc`, `add_fillers`, `route_eco`.
- **The surviving violation.** Lines 55–56 name the one M1 EndOfLine violation in
  which both objects are cell pins and one is a filler. Confirmed in the shipped
  report — `baseline_2026-08-06/reports/nanosoc_eth_chiplet_pads_imp_drc.rep:277`:
  ```
  EndOfLine: ( EndOfLine Spacing ) Pin of Cell .../FILLER_PD_TOP_T_14_3927 & Pin of Cell u_tidelink/g72197  ( M1 )
  ```
  `grep -c FILLER_PD_TOP` on that report returns **1**. It is the entire
  measurable payload of the `-fix_drc` gap.

### 2.2 Line 88 — `add_filler_gaps 0.2 -effort high`

```tcl
88: add_filler_gaps 0.2 -effort high
```

Stylus TCR, `add_filler_gaps` (`TCRcom/add_filler_gaps.html`):

> `add_filler_gaps min_gap [-effort {none | low | medium | high}] [-radius value_in_micron]`
>
> Moves placed standard cell instances to create gaps so that filler cells can be
> added. Tries to move cells to create a gap of the specified size. If enough
> space is not available, moves cells until they touch each other. If a gap
> already exists, and it is larger than the specified size, the command does not
> move cells to make it smaller.

- **`0.2`** is `min_gap`, positional, **microns** (`Data_type: float, required`).
  0.2 µm is exactly **one `core` site** — the site pitch declared in
  `tcbn65lp_9lmT2.lef:2151` (geometry not reproduced here, TSMC licence). So the
  request is "leave me at least one legal
  filler site wherever you can" — the smallest thing `FILL1` can occupy. The
  header of `06-fill-antenna-bondpads.md` says to confirm the units with `-help`;
  they are confirmed here, from the manual.
- **`-effort high`** — `Default: low`, so this is a real change. The manual's
  ladder: `none` moves nothing; `low` moves single-height cells within a row;
  `medium` moves single-height cells across rows; `high` *"specifies that the
  standard cells can be moved across rows, and double height standard cells can
  be moved within the same row."*
- **`-radius`** is not given; `Default: 16` (µm search radius).

**Two landmines in this one line.**

> **(a) It is documented to delete routing.** The same page: *"By default, this
> command deletes all routing, because the routing is no longer valid due to the
> movement of the cells. To override this behavior, specify the following
> command: `set_db place_detail_preserve_routing true`."*
>
> `grep -rn "preserve_routing" ASIC/genus-innovus/scripts ASIC/asic-flows` returns
> **nothing**. The attribute is not set. This line runs on a fully routed,
> hold-repaired database at `-effort high`.
>
> It has never fired, because it has never moved a cell. Both calls, both runs:
> ```
> Summary Report:
> Instances move: 0 (out of 230927 movable)
> ```
> (`baseline_2026-08-06/logs/pnr_run_core70.log`, at `@file 1:` and `@file 6:`).
> The design is at 92.17 % density after `opt_design_postroute_hold`
> (`reports/qor_05_route_opt.rep`) and there is simply nowhere to move anything.
> **That is luck, not design.** Loosen the floorplan, and the first cell this
> command moves takes the whole route with it. *Inference, but the manual sentence
> is unambiguous:* set `place_detail_preserve_routing true` before this line, or
> drop the two `add_filler_gaps` calls entirely — they are provably no-ops on this
> design.

> **(b) The manual places it in the wrong stage for this flow.** *"Use this
> command after placement and before routing."* This flow calls it twice after
> routing. That is a deliberate consequence of the ordering fix documented in
> `06-fill-antenna-bondpads.md` §2, not an oversight — but it is worth knowing
> that the tool does not expect it.

### 2.3 Lines 94–95 — `add_fillers`, pass 1 (insert)

```tcl
94: add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
95:     -prefix FILLER -fill_gap -merge true -check_drc true
```

Option by option, against Stylus TCR `add_fillers` (`TCRcom/add_fillers.html`):

| Option | Manual | Effect here |
|---|---|---|
| `-base_cells` | *"Specifies the list of filler base cell names to add."* | The 7 `FILL*` sizes plus `ANTENNA`. Order matters in practice — see §2.7. |
| `-prefix FILLER` | *"Specifies the prefix for the placed instances. **Default: FILLER**"* | **A no-op.** It restates the default. Innovus then appends the power-domain name, so instances are `FILLER_PD_TOP_*`. |
| `-fill_gap` | *"Fills a gap between cells by adding a combination of cells, instead of by adding the single largest cell that fits, if doing so avoids leaving an unfilled single-width gap."* | Meaningful. This is what keeps a 5-site gap from becoming `FILL4` + one dead site. |
| `-merge true` | *"When checking for spacing violations, merge same-net geometries to determine width-dependent spacing … **Default: false**"* | Meaningful. `true` merges overlapping same-net shapes into one large rectangle before applying width-dependent spacing — the correct choice against a power grid built from abutting wide straps. |
| `-check_drc true` | *"Controls postroute DRC violation checking against existing net routing, without considering adjacent cell DRC violations … **Default: true**"* | **A no-op.** It restates the default. |

The `-check_drc` semantics are the crux of the whole file, and the manual is
precise about the limit:

> If the design is routed, this command also does DRC checks of the filler cells
> added versus the wires in the design. **It does not check versus adjacent
> cells.**

and about the failure behaviour:

> When the inserted filler violates the existing routing, `add_fillers` tries to
> use other filler cells to replace the violating one; if it fails to fill the
> gap without violation, **it leaves a gap**.

A gap is the designed outcome of a conflict. Pass 2 handles the other half.

**One documented precondition this flow does satisfy.** The manual: *"Before
using `add_fillers`, run the `connect_global_net` command to provide
global-net-connection rules for supply pins of the added fillers. Without these
rules, the built-in design-rule checks of `add_fillers` will not be accurate."*
`power_plan.tcl:46-49` issues all four `connect_global_net` calls (VDD, VDDIO,
VSS, VSSIO), long before this point.

### 2.4 Line 97 — `add_filler_gaps` again

Identical to line 88, same caveats. Its purpose is to open gaps that pass 1 could
not fill so pass 2 can. It has never moved anything (§2.2).

### 2.5 Line 102 — `check_filler > check_filler.log`

```tcl
102: check_filler > check_filler.log
```

Stylus TCR, `check_filler` (`TCRcom/check_filler.html`):

> Checks for locations that are missing filler cells, after adding the cells with
> the `add_fillers` command … If you run this command without any parameters, it
> reports the total number of sites in the core area that are missing filler
> cells.

The manual's own example output is the format to look for:

> ```
> *INFO: Total number of gaps found: 85
> ```

Note the wording collision: the *description* says **sites**, the *output line*
says **gaps**. §3.4 shows this matters.

This call is deliberately unparameterised and Tcl-redirected to a local file, so
it cannot clobber `$REPORT_DIR/${block_name}_imp_filler.rep`, which
`4_pnr_route.tcl:42` writes later with `-out_file`. Both baselines' local
snapshot reads:

```
*INFO: Total number of padded cell violations: 0
*INFO: Total number of gaps found: 0
```

Useful `check_filler` options this flow does not use, all from the same page:
`-report_gap microns` (only gaps of exactly that size), `-area {x1 y1 x2 y2}`,
`-power_domain`, and `-adjacent_filler1`, which *"flags any one-site-width filler
placed next to each other as a violation"* — potentially interesting on a design
where `FILL1` is 30 % of the fill population, but it requires
`set_db add_fillers_cells fillerCellList` first.

### 2.6 Line 115 — `check_drc` (the 2026-08-06 addition)

```tcl
115: check_drc -out_file $REPORT_DIR/${block_name}_imp_drc_prerepair.rep
```

This line exists to make line 121 stop being inert. Stylus TCR, `check_drc`
(`TCRcom/check_drc.html`):

> Checks for DRC violations and **creates violation markers in the design
> database** that can be seen on the GUI and browsed with the Violation Browser.

Those markers are precisely the input `-fix_drc` consumes. Without them,
`add_fillers -fix_drc` emits `IMPSP-9082` and does nothing.

Three deliberate choices in this one line, all documented in the script header
(lines 47–86) and all correct:

1. **It writes to its own file** (`_imp_drc_prerepair.rep`), leaving the signoff
   report from `4_pnr_route.tcl:41` alone. The difference between the two files
   is the only record of what the repair achieved.
2. **It is unscoped.** `check_drc` offers `-check_only {all | regular | special |
   selected_net | selected | cell | default}` and `-layer_range`; narrowing to
   `cell` would look like an optimisation and would risk failing to mark exactly
   the violations `-fix_drc` needs. Cost is measured: 22 s elapsed / 2:12 CPU on
   8 threads.
3. **It runs before the bond pads exist.** `place_bondpads.tcl` creates the pads
   only after this file returns, so the marker set describes the *core* only. In
   the `CORE_TO_IO 50` baseline the pad ring produced 398 of 580 violations; had
   they been in the marker database, the filler repair would have been handed a
   database dominated by M8/M9/AP geometry it cannot touch.

### 2.7 Lines 121–122 — `add_fillers`, pass 2 (repair)

```tcl
121: add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
122:     -prefix FILLER -check_drc true -fix_drc
```

The only new option is `-fix_drc`. Stylus TCR, `add_fillers`:

> **`-fix_drc`** — Corrects DRC violations reported by `verify_drc` between filler
> cells and adjacent standard cells.
>
> Use this parameter in subsequent runs of the `add_fillers` command, after adding
> filler cells and checking for violations with `verify_drc`. The command replaces
> filler cells that cause DRC violations with fillers that do not cause
> violations. **If it cannot replace a violating filler cell without causing
> another violation, it leaves a gap.**

Note `-fill_gap` and `-merge` are *dropped* on this pass. That is consistent —
this pass is not trying to fill new space, it is swapping violating cells.

Two things the reader should hold on to:

- `verify_drc` in that quote is the legacy-UI name. In Stylus it is `check_drc`,
  which line 115 now runs.
- A **gap** is an acceptable outcome of `-fix_drc`; an unrepaired violation is
  not. This is why the pre-repair `check_filler` at line 102 is worth diffing
  against the post-repair one from `4_pnr_route.tcl:42` — the delta is the set of
  gaps `-fix_drc` chose to leave.

### 2.8 The cell list: what each class contributes physically

`tcbn65lp` names its filler cells by **site count**, not by micron width: the
digit in the name *is* the width in `core` sites, and every one of these cells is
one row tall. Multiply by the site pitch (`tcbn65lp_9lmT2.lef:2151`) to get
microns — the LEF dimensions themselves are not reproduced here (TSMC licence).

| Cell | Sites | Contents (from the LEF `PIN` sections) | 08-06 count | 08-05 count |
|---|---:|---|---:|---:|
| `FILL64` | 64 | M1 VDD + VSS `SHAPE ABUTMENT` rails only | 386 | 674 |
| `FILL32` | 32 | ditto | 64 | 93 |
| `FILL16` | 16 | ditto | 328 | 379 |
| `FILL8` | 8 | ditto | 835 | 1 194 |
| `FILL4` | 4 | ditto | 9 626 | 18 391 |
| `FILL2` | 2 | ditto | 19 822 | 27 799 |
| `FILL1` | 1 | ditto | 30 482 | 51 788 |
| `ANTENNA` | 2 | same rails **plus** `PIN I` carrying an `ANTENNADIFFAREA` value | **41 217** | **50 274** |
| | | **Total** | **102 760** | **150 592** |

Counts from `baseline_2026-08-06/logs/pnr_run_core70.log:33676-33684` and
`baseline_2026-08-05/logs/pnr_all.log:38338-38346`.

**What each class contributes.**

- `FILL*` contribute **diffusion, poly and well continuity plus M1 rail
  continuity**, and nothing electrical. They have no signal pins at all.
- `ANTENNA` contributes the same plus a diode. It is 2 sites wide — the same as
  `FILL2` — which is why the tool reaches for it so often: 40 % of all inserted
  instances. On this design `ANTENNA` and `FILL2` are interchangeable from a
  gap-filling point of view, and the tool's ordering preference decided the split.
- `FILL1`+`FILL2`+`ANTENNA` = 91 521 of 102 760 (89 %) in the 08-06 run. That is
  what a 92 %-density design looks like: the leftover space is single- and
  double-site slivers.

**The diodes are not connected to anything.** *Inference, high confidence, stated
because the stage doc reads the other way.* Three independent facts:

1. `add_fillers` has no option that connects a filler's signal pin — the full
   synopsis on `TCRcom/add_fillers.html` contains nothing of the kind, and the
   command's stated job is rails and wells.
2. Filler instances are physical-only and do not reach the netlist:
   `grep -c FILLER_PD_TOP baseline_2026-08-06/outputs/nanosoc_eth_chiplet_pads_pnr.v`
   returns **0**, as does `grep -c ANTENNA`.
3. Nothing runs after them that would connect them. `grep -rni antenna` over
   `ASIC/genus-innovus/scripts/*.tcl` and `ASIC/asic-flows/Cadence/*.tcl` finds no
   antenna-diode attribute, no NanoRoute diode-insertion setting, and no
   `fix_antenna`-class command anywhere in the flow.

So the 41 217 `ANTENNA` instances are base-layer density fill with a diode
drawn on them, sitting unconnected. They do not protect any net.

**This is a direct consequence of the ordering fix,** and worth stating because
the two "correct" orderings pull against each other. Moving filler *after*
routing is right for `-check_drc`/`-fix_drc` (real routing to check) and right
for hold repair (rows have stopped changing). But diode insertion only does
anything if the router can hook the diodes up, and the router has finished. The
flow gets away with it because there was nothing to fix:
`reports/nanosoc_eth_chiplet_pads_imp_antenna.rep` ends `No Violations Found`,
and NanoRoute's own in-route antenna avoidance is what earned that. Stylus TCR,
`check_process_antenna` (`TCRcom/check_process_antenna.html`): *"Verifies process
antenna effect (PAE) and maximum floating area violations."* — it verifies, it
does not repair.

**Unused, and available.** `tcbn65lp` also ships `DCAP`, `DCAP4`, `DCAP8`,
`DCAP16`, `DCAP32`, `DCAP64` (`tcbn65lp_9lmT2.lef:18957-19236`), same 1.800 µm
row height, same site-count naming — decoupling capacitance cells. This flow
inserts none. Every gap that could have held on-die decap holds inert `FILL*`
instead. Whether that matters is a power-integrity question nobody on this design
has asked; the cells are there if the answer is yes.

### 2.9 Lines 148–153 — `route_eco -target`, wrapped in a `catch`

```tcl
148: if {[catch {route_eco -target} route_eco_msg]} {
149:     puts "ERROR: route_eco -target FAILED: $route_eco_msg"
150:     puts "ERROR: filler-induced net-based DRC is NOT repaired in this run (IMPSP-5217)."
151:     puts "ERROR: treat ${REPORT_DIR}/${block_name}_imp_drc.rep as UNREPAIRED."
152:     puts "ERROR: do not stream this database out."
153: }
```

This closes the second half of the repair — the class `add_fillers` is documented
as unable to touch.

Stylus TCR, `route_eco` (`TCRcom/route_eco.html`):

> **`-target`** — Enables NanoRoute to work on only eco nets identified by
> NanoRoute to route. In this mode, the router ignores the already existing DRC
> violation markers that are not on the ECO nets or are on nets selected to route.

That is both the tool's own recommendation in `IMPSP-5217` and the conservative
choice: it will not go re-routing the 64 power-grid markers `check_drc` just
wrote. The synopsis shows `-target`, `-fix_drc` and `-prototype` in one
mutually-exclusive group; do not combine them.

**The header's caution is well founded.** The same page states a precondition:

> You must first run the `place_eco` command before you use this command.

That sentence is written for the netlist-ECO flow, where `eco_read_def` leaves
new cells unplaced. `add_fillers` leaves nothing unplaced, so `place_eco` should
be unnecessary — but that is reasoning, not evidence, and no Innovus seat was
available to test it (licence-constrained, 2026-08-06). Hence the `catch`.

**Two options on this page worth knowing before the first seat becomes
available**, both from `TCRcom/route_eco.html` and neither used here:

- `-fix_filler_drc_with_patch_only` — *"Fixes filler related drc with metal patch
  only."* Named for exactly this situation.
- `-trim_layer_patch` — *"Enables the `route_eco` command to only add trim and
  patch metals in a given area … you can fix drc violations flagged in
  sign-off/`verify_drc` and only add trim and patch metals where minimum spacing
  criteria is not met."*

Both are more surgical than `-target`. Try `route_eco -help` and compare before
committing.

**The warning will not go away.** `IMPSP-5217` fires *at* `add_fillers`, twice
per run — before `route_eco` has had a chance to run. It is not a regression
indicator. `IMPSP-9082` is: it should now be zero.

---

## 3. The filler trap: `IMPSP-5110`, and how to make it impossible

**This is the highest-value section on the page. The failure it describes shipped
a GDSII.**

### 3.1 The causal chain, link by link

| # | Link | Evidence |
|---|---|---|
| 1 | The design's power intent is written in UPF/1801. | — |
| 2 | Genus cannot translate the UPF supply commands to CPF. | Synthesis log: `Unable to translate command 'create_supply_net' ... from 1801 to CPF format` (`Makefile:86-87`) |
| 3 | `write_power_intent -cpf` therefore emits a CPF whose entire content is `create_power_domain -name PD_TOP -default` — **no power net, no ground net**. | `Makefile:88` |
| 4 | `2_pnr_setup.tcl:40` reads that file with `read_power_intent -cpf`. | `04-power-plan.md:50-51` |
| 5 | `PD_TOP` exists in the database but has no `primary_power_net` / `primary_ground_net`. | — |
| 6 | Every `add_fillers` pass fails: `**ERROR: (IMPSP-5110): No supply-net names for Power Domain 'PD_TOP'.` | `04-power-plan.md:55-57` |
| 7 | `add_fillers` reports `For 0 new insts, *** Applied 0 GNC rules.` | same |
| 8 | The script does not abort. `write_stream` runs. | `4_pnr_route.tcl` has no error handling around `source ../scripts/place_bondpads.tcl` |
| 9 | The die ships with **zero filler cells, zero `ANTENNA` diodes, ~95,568 free-site gaps (~5.9 % of the core)**. | `Makefile:92-94`; `power_plan.tcl:19-20` |

**Why the power domain gates filler at all.** `add_fillers` takes
`-power_domain powerDomainName`, and its documented default is *"tries to add
fillers to all power domains"* (`TCRcom/add_fillers.html`). Every filler cell it
places carries `PIN VDD / USE POWER` and `PIN VSS / USE GROUND` with `SHAPE
ABUTMENT` (§2.8), so the tool must know which supply nets those rails belong to
before it can legally place one. A domain with no supply nets makes every
candidate insertion illegal — not *wrong*, **illegal**, so the count is exactly
zero rather than merely low. The `-prefix` that comes out as `FILLER_PD_TOP` is
the same coupling seen from the other side: filler instance naming is
power-domain-scoped.

### 3.2 `IMPSP-5110` is not in the installed manual — verified

The task of quoting it properly runs into a wall, and the wall is worth
recording. **There is no `IMPSP-5110.html` in this install.**

```sh
$ ls $INNOVUS_HOME/doc/innovuserrmsg/ | grep -E '^IMPSP-51'
IMPSP-5101.html
IMPSP-5106.html
IMPSP-5113.html
IMPSP-5119.html
...
$ grep -rl "IMPSP-5110" $INNOVUS_HOME/doc/
(no output)
```

The Error Message Reference is a **selective** manual, not a complete one: it
carries only messages with an expanded `DESCRIPTION`, and its next/previous links
skip the gaps. `IMPSP-5106.html`'s trailer links forward to `IMPSP-5113`, and
`IMPSP-5113.html`'s links back to `IMPSP-5106` — 5110 is not between them. Same
for `IMPSP-9082` (the sequence runs `IMPSP-9053` → `IMPSP-9099`) and for every
`IMPOGDS-217` / `-218` / `-4004` message §6 relies on.

So the only authoritative text for `IMPSP-5110` on this machine is `man
IMPSP-5110` inside a live Innovus session, and the transcription already in the
tree:

```
**ERROR: (IMPSP-5110):  No supply-net names for Power Domain 'PD_TOP'.
For 0 new insts, *** Applied 0 GNC rules.
```

(`04-power-plan.md:55-57`, from the 2026-08-03 run.) Do not treat any longer
quotation of this message as manual-sourced; there is no manual page behind it.

For contrast, here is a message that **does** have a page —
`innovuserrmsg/IMPSP-5217.html`, quoted in full:

> **SUMMARY** — addFiller command is running on a postRoute database. It is
> recommended to be followed by ecoRoute -target command to make the DRC clean.
>
> **DESCRIPTION** — When `-enableLeglizer` is set to true, there might be DRC left
> if running `addFiller` command on a postRoute DB. You can call `ecoRoute`
> command after `addFiller` to clean up the DRC, or set `setFillerMode
> -enableLeglizer` to false to avoid this warning message.

Note the third option that page offers and the script header does not mention:
turning the legaliser off. Running `route_eco` is the right choice — but it is
worth knowing the warning is conditional on a mode setting, not unconditional.

### 3.3 The fix is a CPF edit, not an Innovus command

`update_power_domain` in this Innovus build takes the domain **positionally** and
has no `-primary_power_net` / `-primary_ground_net` options; its entire option set
is floorplan geometry (`core_to_*`, `row_*`, `gap_*`). Verified by running it —
`IMPTCM-162` plus the usage string (`Makefile:96-98`, `04-power-plan.md:1.3`).

`create_ground_nets`, `create_power_nets` and CPF-form `update_power_domain` are
**CPF statements**, so the repair belongs in the file before Innovus reads it.
`make syn` now runs `cpf-patch` (`Makefile:103-114`), which inserts before
`end_design`:

```
create_ground_nets -nets VSS
create_power_nets -nets VDD

update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS
```

The target is idempotent (it greps for `create_power_nets` first), fails loudly
if the CPF is missing or has no `end_design`, and re-checks its own edit. The
backstop is in `power_plan.tcl:40-42`:

```tcl
if {[llength [get_db power_domains PD_TOP]] == 0} {
    error "power_plan: no PD_TOP power domain — check read_power_intent"
}
```

Note what that guard does and does not catch: it checks the **domain exists**,
not that it **has supply nets**. It would not have caught the actual bug. A
stricter guard is in §3.4.

### 3.4 How to verify filler actually got inserted

This is the part that has to be right, because the failure is silent and the
existing check is worthless.

**Do not use `reports/*_imp_filler.rep` as the gate.** Both baselines' copies are
9 lines long and contain nothing beyond the header and `Checking Power Domain:
PD_TOP` — no gap census, no counts. `check_filler` reports gaps by *presence*, so
a clean run and a run in which the command found no rows to check produce
similarly empty files. `04-power-plan.md:406-408` says the same: *"`check_filler`
output is uninformative … Do not use it as the filler sign-off gate."*

**Use the insertion count. It is the only number that cannot be faked.**

```sh
# 1. THE gate. Must print a number, and it must be large.
grep -E "Total [0-9]+ filler insts added" ASIC/genus-innovus/logs/*.log
#    good  ->  *INFO: Total 102760 filler insts added - prefix FILLER_PD_TOP (CPU: 0:00:32.3).
#    bad   ->  (nothing at all)

# 2. The refusal. Must be zero.
grep -c "IMPSP-5110" ASIC/genus-innovus/logs/*.log ASIC/genus-innovus/work/innovus.log*

# 3. The tell. Must be zero.
grep -c "For 0 new insts" ASIC/genus-innovus/logs/*.log

# 4. The diodes specifically. Must be tens of thousands.
grep "cell ANTENNA" ASIC/genus-innovus/logs/*.log
#    good  ->  *INFO:   Added 41217 filler insts (cell ANTENNA / prefix FILLER_PD_TOP).

# 5. The repair became non-inert (2026-08-06 change). Must be zero.
grep -c "WARN: (IMPSP-9082)" ASIC/genus-innovus/logs/*.log
```

**In a live session,** the database-side equivalent (`check_filler` parameters
from `TCRcom/check_filler.html`):

```tcl
check_filler                                                  ;# expect: Total number of gaps found: 0
llength [get_db insts FILLER_PD_TOP*]                         ;# expect: ~10^5
llength [get_db insts FILLER_PD_TOP* -if {.base_cell.name == ANTENNA}]   ;# expect: ~4x10^4
```

**A guard that would actually have caught it.** *Suggestion, not in the tree.*
Put this immediately after each `add_fillers` in `filler.tcl`; it converts the
worst failure mode in the flow from silent to immediate, at the cost of one
`get_db`:

```tcl
set n [llength [get_db insts FILLER_PD_TOP*]]
if {$n < 10000} {
    error "filler: only $n filler insts — check for IMPSP-5110 (CPF has no supply nets for PD_TOP)"
}
```

**Reference numbers for "is this plausible?"** — derived from the LEF cell widths
in §2.8 and the log counts, so they are reproducible arithmetic, not lore:

| | 2026-08-05 (`CORE_TO_IO 50`) | 2026-08-06 (`CORE_TO_IO 70`) |
|---|---:|---:|
| Filler instances | 150 592 | 102 760 |
| of which `ANTENNA` | 50 274 | 41 217 |
| Row length consumed | 68 645.2 µm | 45 948.8 µm |
| Filler area (× 1.8 µm row height) | 123 561 µm² | 82 708 µm² |
| Core box | 1230 × 1630 = 2 004 900 µm² | 1190 × 1590 = 1 892 100 µm² |
| **Filler as % of core** | **6.16 %** | **4.37 %** |

**A number in the existing docs that does not reconcile — flagged, not
resolved.** `Makefile:92-94` and `power_plan.tcl:19` both state the failed run
shipped "95,568 free-site gaps (~5.9 % of the core)". Those two figures cannot
both be site counts:

- `check_filler`'s manual describes its output as *"the total number of **sites**
  in the core area that are missing filler cells"* (`TCRcom/check_filler.html`).
  At 0.2 × 1.8 µm per site, 95 568 sites is 34 405 µm², which is **1.72 %** of the
  `CORE_TO_IO 50` core — not 5.9 %.
- The **6.16 %** in the table above — the area the fill actually occupied in the
  run that worked, on the same core box — is within rounding of 5.9 %.

*Inference:* the 5.9 % is a fill-area fraction and the 95 568 is a count of
contiguous **gaps**, not sites. 343 226 sites ÷ 95 568 gaps ≈ 3.6 sites per gap,
which is exactly the right shape for a 92 %-density design. `04-power-plan.md:408`
already warns that "the 95,568 free-site figure is not independently reproducible
from the surviving logs" — this page adds that it is also arithmetically
inconsistent with the 5.9 % it is quoted alongside. **Settle it by running
`check_filler` on an unfilled database and reading its own output line**, which is
labelled `Total number of gaps found:`. Until someone does, quote the insertion
count instead; it has no such ambiguity.

---

## 4. `place_bondpads.tcl`, block by block

177 lines. Sourced from `4_pnr_route.tcl:39`.

### 4.1 Lines 1–29 — the header and the `source`

```tcl
29: source ../scripts/filler.tcl
```

The first executable line of the file creates no bond pads at all; it runs the
entire fill stage. The header (lines 20–28) explains why the `source` must stay
*above* the pad loops, and it is correct: `filler.tcl`'s `check_drc` at line 115
marks the violations the repair passes then act on, and running it here keeps the
marker set core-only. Moving it below the loops would hand the filler repair a
database dominated by M8/M9/AP pad-ring geometry — the class that was 376 of 379
shorts in the `CORE_TO_IO 50` baseline.

### 4.2 Lines 31–136 — the eight pad lists

Eight Tcl lists, 82 names total, no comments:

| Side | outer list | inner list | total |
|---|---:|---:|---:|
| top (31, 43) | 9 | 8 | 17 |
| left (54, 69) | 13 | 13 | 26 |
| bottom (87, 99) | 9 | 8 | 17 |
| right (110, 124) | 11 | 11 | 22 |
| | **42** | **40** | **82** |

Confirmed against the shipped netlist:
`grep -c "PAD70GU\|PAD70NU" baseline_2026-08-06/outputs/nanosoc_eth_chiplet_pads_pnr.v`
returns **82**.

**The lists are not arbitrary, and no document in the repo says what they are.
They are the IO ring order, de-interleaved.**

`floorplan.tcl:85` runs `read_io_file ../scripts/nanosoc_eth_chiplet_pads.io`,
which fixes the IO driver order on each side. Take that per-side order and split
it by parity — odd positions (1st, 3rd, 5th …) and even positions (2nd, 4th, 6th
…). The odd positions are exactly `<side>_pads_outer`; the even positions are
exactly `<side>_pads_inner`. **Verified for all four sides and all 82 pads**, in
list order, no exceptions:

```
--- top:    .io=17  outer=9  inner=8   odd==outer True   even==inner True
--- left:   .io=26  outer=13 inner=13  odd==outer True   even==inner True
--- bottom: .io=17  outer=9  inner=8   odd==outer True   even==inner True
--- right:  .io=22  outer=11 inner=11  odd==outer True   even==inner True
```

Worked example, top side. `nanosoc_eth_chiplet_pads.io` lines 25–41 give the ring
order `VDDIO_T_0, VDD_T_0, VSS_T_0, NRST_I, SWDCK_I, CLK_I, TEST_I, SE_I, VDD_T_1,
SWDIO_IO, VSS_T_1, VDDIO_T_1, VDDIO_T_2, VSSIO_T_0, VSSIO_T_1, …`. Positions
1,3,5,7,9,11,13,15 are `VDDIO_T_0, VSS_T_0, SWDCK_I, TEST_I, VDD_T_1, VSS_T_1,
VDDIO_T_2, VSSIO_T_1` — `place_bondpads.tcl:32-40`, verbatim and in order.

**Consequences, and this is why it matters:**

- **These lists are derived data.** Reorder anything in the `.io` file and these
  eight lists are stale. Nothing in the tree enforces the relationship, nothing
  documents it, and the failure mode is a pad landing next to the wrong driver —
  which `create_relative_floorplan` will do perfectly happily because it resolves
  `-ref` by exact instance name (§4.4).
- **The parity split *is* the stagger.** Consecutive IO drivers alternate between
  the short outer pad and the tall inner pad, so along-ring pad spacing within a
  row is two driver pitches, while the ring as a whole delivers one pad per
  driver. With a 57.44 µm AP opening (§1.3) on a 25.000 × 135.000 µm driver
  (`tphn65lpgv2od3_sl_9lm.lef`), a single row would be spacing-limited; two rows
  are not.
- **The `.io` file itself warns you off its own numbers.** Its header (lines 9–11)
  reads: *"the offset= values are EVENLY-SPACED PLACEHOLDERS — real placement is a
  PnR (Innovus) output, not derivable from the RTL model."* The **order** is
  authoritative; the coordinates are not.

`docs/PIN_MAP.md` is *not* the cross-reference for this. It is marked `Status:
TEMPLATE`, describes 46 logical pad *cells* rather than 82 bond pads, has `[TEAM
DECISION]` in every die-side column, and never mentions `PAD70GU`, `PAD70NU`,
`tpbn65v`, `place_bondpads.tcl` or the `.io` file. (`docs/PIN_POLICY.md` is about
git submodule commit pins and is unrelated to pads despite the name.) The
authoritative ring record is the `.io` file plus these eight lists.

### 4.3 Lines 139–177 — the eight placement loops

All eight loops have the same two-line body:

```tcl
139: foreach pads $left_pads_outer {
140:     create_inst -cell PAD70GU -inst B$pads -ori R270
141:     create_relative_floorplan -place B$pads -orient R270  -ref_type object -ref $pads -horizontal_edge_separate {0  -2.5  0} -vertical_edge_separate {0  0  0}
142: }
```

**Cell selection is purely by row:** `PAD70GU` for every `*_outer` loop,
`PAD70NU` for every `*_inner` loop. Nothing about the signal influences the cell.

**Instance naming:** `B$pads`, so IO driver `uPAD_TL_RX_0` gets bond pad
`BuPAD_TL_RX_0`. That prefix is how you read the DRC report — every pad-clearance
violation in the `CORE_TO_IO 50` baseline names a `BuPAD_*` blockage.

**A Stylus-mode note on `create_inst`.** The Stylus reference
(`TCRcom/create_inst.html`) gives the synopsis as:

```
create_inst [-location {x y}] [-orient {r0 r90 r180 r270 mx mx90 my my90}]
            [-physical] {-base_cell base_cell} {-name inst_name} ...
```

The script writes `-cell`, `-inst` and `-ori`. `-ori` is an unambiguous prefix of
`-orient`, but `-cell` and `-inst` are not prefixes of `-base_cell` and `-name` —
they are legacy spellings that this build still accepts. They ran without a
warning in the 2026-08-06 log (`pnr_run_core70.log:33819` onward echoes them and
nothing follows). **Flagged as legacy-UI usage in a Stylus flow.** The
Stylus-clean form is:

```tcl
create_inst -base_cell PAD70GU -name B$pads -orient r270 -physical
```

`-physical` is worth considering separately: *"Places a physical instance without
updating the netlist."* Without it, the 82 pads land in the netlist —
`write_netlist` emits `PAD70NU BuPAD_HOST_IO_6 ();` with an empty port list,
82 times (`baseline_2026-08-06/outputs/nanosoc_eth_chiplet_pads_pnr.v:1398677`
onward). That is 82 instances in `*_pnr.v` that no RTL and no synthesis netlist
contains, which any downstream LVS or equivalence run has to be told about.

### 4.4 `create_relative_floorplan` — and a correction to the stage doc

Stylus TCR, `create_relative_floorplan` (`TCRcom/create_relative_floorplan.html`):

> The `create_relative_floorplan` command captures and defines the placement
> relationship of floorplan objects independently from the actual coordinates in a
> floorplan …

Options used, and what they mean:

| Option | Manual |
|---|---|
| `-place B$pads` | *"Specifies the target object to place. It can be hInst, inst, group, power_domain, pin_guide, blockages, or port."* |
| `-ref $pads` | *"Specifies the reference object name."* Resolved by exact name — this is why a stale list silently misplaces a pad. |
| `-ref_type object` | *"Specifies the type of reference."* `Default: object`, so this is a no-op restatement. The alternatives are `core_boundary` and `die_boundary`. |
| `-orient R270` | *"Specifies the orientation of the target object."* `Default: r0`. |
| `-horizontal_edge_separate {a b c}` | *"Specifies the **vertical** spacing between the **horizontal** edge of the target and reference objects."* Synopsis form: `{ref_edge_horizontal y_offset obj_edge_horizontal}`. |
| `-vertical_edge_separate {a b c}` | *"Specifies the **horizontal** spacing between the **vertical** edge of the target and reference objects."* Synopsis form: `{ref_edge_vertical x_offset obj_edge_vertical}`. |

> **Correction.** `06-fill-antenna-bondpads.md:365-368` states that the
> three-element form is `{<left/bottom> <centre> <right/top>}` and flags it as
> observed rather than documented. **It is documented, and it is not that.** The
> manual's synopsis is `{ref_edge y_offset obj_edge}` — a *reference edge
> selector*, an *offset in microns*, and an *object edge selector*. Only the
> middle element is a distance. The stage doc's reading is wrong; the numbers in
> the script are unchanged by the correction, but anyone editing them on the old
> reading will get a surprise.
>
> Also note the axis inversion, which is genuinely counter-intuitive:
> `-horizontal_edge_separate` sets a **y** offset (between horizontal edges) and
> `-vertical_edge_separate` sets an **x** offset. The manual's own example,
> `–horizontal_edge_separate {3 -20 1} –vertical_edge_separate {4 40 0}`, shows
> integer edge selectors in the outer positions and signed micron distances in the
> middle.

The manual does not enumerate what integers 0–5 (and −1) select. That part remains
undocumented here; confirm with `create_relative_floorplan -help` before changing
an outer or inner element.

Per side, exactly as written in the file:

| Side | Lines | Orient | `-horizontal_edge_separate` (y) | `-vertical_edge_separate` (x) |
|---|---|---|---|---|
| left | 139–147 | `R270` | `{0 -2.5 0}` | `{0 0 0}` |
| top | 149–157 | `R180` | `{1 0 1}` | `{2 2.5 2}` |
| bottom | 159–167 | `R0` | `{0 0 0}` | `{0 -2.5 0}` |
| right | 169–177 | `R90` | `{1 2.5 1}` | `{2 0 2}` |

Outer and inner rows on a side share orientation **and** separations. The stagger
therefore comes entirely from the two cells' geometry — the 102 µm offset of the
AP opening within the cell body (§1.3) — and not from the placement arguments.
The single `2.5` on each side appears on the axis and with the sign that pushes
the pad outward from the die centre. The along-ring position of every pad is
inherited from its IO driver, which is why the parity split in §4.2 is the whole
mechanism.

### 4.5 The M8/M9/AP blockage, and what it collides with

`PAD70GU` and `PAD70NU` are `CLASS BLOCK` and carry **only `OBS`, no `PIN`**.
Read the `PAD70NU` `OBS` section of `tpbn65v_9lm.lef` and the shape of the problem
is immediate: on **M8 and M9 it is the same five-shape figure** — a rectangle
covering the whole cell body, a rectangle either side of it, and a chamfered
polygon capping each of those — and on **AP** a single wide rectangle with a
chamfered polygon at each end. No pins, no routing targets, blockage only.

> Vendor LEF geometry redacted — TSMC licence forbids reproduction. Source:
> `$TSMC_65_HOME/iolib/tpbn65v_<rev>_FE/.../lef/tpbn65v_9lm.lef`, `MACRO PAD70NU`,
> the `OBS` section.

> **A second correction.** `floorplan.tcl:18-19` and
> `06-fill-antenna-bondpads.md:380-384` both record this obstruction as a single
> full-cell rectangle on M8 and M9 — the **body rectangle only**. The real
> obstruction is **five shapes per layer**, and the outer ones reach past both
> sides of the cell body: measured across all of them it is **59.5 µm wide, not
> 30**.
>
> **The inboard-direction arithmetic in `floorplan.tcl` is unaffected** — every
> shape stays within the cell's own 171 µm height — so the 16 µm overlap at
> `CORE_TO_IO 50` and the 4 µm clearance at 70 are both correct. The extra width is
> **along the ring**, in the side "wings" that let the pad reach its neighbours'
> routing channels. Do not re-derive along-ring pad spacing from the 30 µm cell
> width.

Three interlocking facts make this the design's dominant DRC source at
`CORE_TO_IO 50`:

1. `add_rings` draws the core power ring on **M8** (left/right) and **M9**
   (top/bottom) — exactly the pad-blockage layers.
2. Both pad cells are `CLASS BLOCK`, not `CLASS PAD`, so
   `create_floorplan -core_margins_by io` **does not see them**. It insets the
   core by the 135 µm IO-driver height only, and knows nothing about the inner
   bond pads reaching 84.3 µm further inboard (`floorplan.tcl:11-16`).
3. `add_rings` draws geometrically and does not honour `OBS`.

Measured result, from `floorplan.tcl:31-56`:

| | `CORE_TO_IO 50` | `CORE_TO_IO 70` |
|---|---:|---:|
| Ring outer edge (left) | 155 | 175 |
| `PAD70NU` inboard edge (left) | 171 | 171 |
| | **16.00 µm overlap** | **4.00 µm clear** |
| Total DRC violations | 580 | **102** |
| Naming a `BuPAD_*` blockage | 398 | **0** |
| PG-ring vs bond-pad shorts | 318 | **0** |
| `SHORT` records overall | 379 | **1** |

`PAD70GU` is the control: 32 of its 398, and **zero** of them VDD/VSS special
wire, because the shorter outer pad's inboard edge never reaches the ring band.
Confirmed in the shipped report — `grep -c BuPAD` on the 2026-08-06
`_imp_drc.rep` returns **0**.

The 4 µm clears both wide-metal rules — M8's `SPACINGTABLE` and M9's flat
`SPACING`, at their worst bands, both ask for less than that. Both layers also
carry a `MAXWIDTH` limit, and the 12 µm ring width was chosen against it — legal
as it stands, with nothing left over. Do not widen them without re-reading that
rule. (Rule values not reproduced — TSMC licence.)

### 4.6 Routing between pad and driver: there isn't any

**Neither bond-pad cell has a single `PIN` statement.** Their LEF is
`CLASS`/`FOREIGN`/`ORIGIN`/`SIZE`/`SYMMETRY`/`OBS`/`END`, nothing else. It follows
that:

- There is no pad-side connection point for the router to reach.
- The 82 instances appear in `*_pnr.v` with **empty port lists**.
- `check_connectivity` cannot and does not check the pad-to-driver connection.
- Nothing is routed between an IO driver and its bond pad in this database at all.
  The connection is made **by abutment on AP**, in the foundry's own pad-cell
  layout, which is not in this GDS (§6).

The related VDDIO/VSSIO observation is blunter than the DRC story suggests.
`baseline_2026-08-06/reports/nanosoc_eth_chiplet_pads_imp_connectivity.rep` opens:

```
Net VDDIO: no routing
Net VSSIO: no routing
Net VSS: has special routes with opens at (175.000, 82.815) (1425.000, 1917.185)
```

The IO supplies are **entirely unrouted**. So the M8/M9 pad-blockage conflict that
dominated the `CORE_TO_IO 50` DRC report was between the pad blockages and the
**core** VDD/VSS rings, not the IO rings — the IO rings do not exist yet. That is
a separate open defect (see `docs/tapeout/15-pg-opens-analysis.md`), and it means
the pad-clearance fix has not yet been tested against the routing that will
eventually have to reach these pads.

### 4.7 Why the pads are created last

`PAD70GU`/`PAD70NU` sit on M8/M9/AP and occupy no core rows, so they never compete
with standard cells, filler or hold buffers for sites. There is no reason to place
them before routing and one good reason not to: they are `CLASS BLOCK`, so their
`OBS` would constrain NanoRoute on M8/M9/AP for the whole run. Placing them last
is deliberate. Note the asymmetry this creates — the signoff `check_drc` in
`4_pnr_route.tcl:41` is the *only* DRC that ever sees the pad ring, and by then
no repair pass runs after it.

---

## 5. What is not done and would be needed for a real tapeout

### 5.1 Metal fill — genuinely absent, and the rules are on disk

**Verified, not assumed.** Scoped to the flow this page documents:

```sh
$ grep -rn -iE 'add_metal_fill|addMetalFill|set_metal_fill|setMetalFill|verify_metal_density|check_metal_density' \
      ASIC/genus-innovus/scripts ASIC/asic-flows ASIC/genus-innovus/Makefile
(no command hits — the only matches on 'density' are prose in comments and a Calibre README)
```

**Zero occurrences of any metal-fill or density-check command anywhere in
`ASIC/genus-innovus/scripts/`, `ASIC/asic-flows/` or the `Makefile`.**

Two findings sharpen that.

**(a) The reference flow this project descends from does have it.** A sibling
nanoSoC flow in the tree — `nanosoc-multicore-system/ethernet-subsystem-ahb/
nanosoc_arch_tech/asic/ASIC/TSMC65nm/28pin/Cadence/scripts/pnr_flow.tcl`, lines
55–65 — carries the complete step for this same PDK:

```tcl
set_metal_fill -layer M1 -opc_active_spacing 0.090 -border_spacing -0.001
...
set_metal_fill -layer AP -opc_active_spacing 2.000 -border_spacing -0.001
add_metal_fill -layers { M1 M2 M3 M4 M5 M6 M7 M8 M9 AP } -nets { VSSIO VSS VDDACC VDDIO VDD }
```

So metal fill was not omitted for want of a recipe. It is present in the ancestor
flow and absent from this one.

**(b) The foundry's density rules are already loaded.** The tech LEF this flow
reads (`config.tcl:131`) carries `MINIMUMDENSITY` / `MAXIMUMDENSITY` /
`DENSITYCHECKWINDOW` / `DENSITYCHECKSTEP` for every routing layer (§1.1). Innovus
would use them automatically: Stylus TCR, `check_metal_density`
(`TCRcom/check_metal_density.html`) — *"Checks the metal density of each routing
layer and of macros against values specified by `set_metal_fill`, by LEF file, or
against its own internal default values."* The check is free and nobody has ever
run it.

**What the missing step would look like.** Stylus TCR, `add_metal_fill`
(`TCRcom/add_metal_fill.html`):

> Inserts inactive metal into a placed and routed design to achieve the metal
> density within the range required by a specific manufacturing process. Avoids
> inserting metal on top of macros if it can achieve the preferred metal density
> without doing so. **Use this command to insert metal fill after timing analysis
> and post route is complete.**
>
> This command uses the values specified by the `set_metal_fill` command.
>
> It is recommended that you add metal fill after adding via fill.

Stylus UG, *Optimizing Metal Density* (`UGcom/Optimizing_Metal_Density.html`),
gives the physics and the cost:

> The dielectric layers in chip designs often vary in thickness due to the
> different patterns of metal on successive metal layers. These variations reduce
> yield and impact chip performance. To minimize these, you can add inactive metal
> segments, called metal fills, to the open areas of the design.
>
> The additional metal increases cross-coupling capacitance, however, so it is
> important to balance the decrease in thickness variations with the increase in
> capacitance.
>
> **Before You Begin** — Complete detailed routing.

and confirms the checks that would gate it: *"the `check_metal_density` and
`check_cut_density` commands enable you to check that the metal density of the
metal and cut layers is within the minimum and maximum density values specified
by the LEF file or the `set_metal_fill` and `set_via_fill` commands."*

**The command a reader would actually run is `add_metal_fill`,** spelled exactly
that way — it is present in the Stylus reference at
`TCRcom/add_metal_fill.html`, so no translation is needed. (The legacy-UI
edition spells it `addMetalFill`; ignore that page.) The whole Stylus fill family
is present under Common UI names, and `ls TCRcom/ | grep -E '(fill|density)'`
lists it: `add_metal_fill`, `add_metal_fill_signoff`, `set_metal_fill`,
`set_metal_fill_spacing_table`, `trim_metal_fill`, `trim_metal_fill_near_net`,
`delete_metal_fill`, `add_via_fill`, `set_via_fill`, `add_notch_fill`,
`check_metal_density`, `check_cut_density`.

A first cut, in flow order, would be roughly: `add_via_fill` → `set_metal_fill`
per layer → `add_metal_fill -timing_aware` → `check_metal_density` →
`check_cut_density` → re-run timing. `TCRcom/add_via_fill.html`,
`TCRcom/check_cut_density.html`, `TCRcom/set_metal_fill.html` and
`TCRcom/add_metal_fill_signoff.html` all exist in this install. **Note the
insertion point: after fill, after pads, before `write_stream` — i.e. between
`4_pnr_route.tcl:44` and `:60`.** It is a real timing-affecting change, not a
cosmetic one; the UG's capacitance warning above is the reason
`-timing_aware {on|off|sta}` exists.

**One encouraging detail: the layer map is already ready for it.** The GDS-out map
(`PRTF_EDI_N65_gdsout_6X1Z1U.<rev>.map`) carries a full `FILL` row for every routing
layer and for AP, in the form:

```
<layer>  FILL  <gds layer>  <datatype>
```

Each `FILL` row targets the same GDS layer as that layer's real metal, on a separate
fill datatype; the upper metals use different fill datatypes from the thin ones,
matching their new-scheme numbering.

> Vendor stream-map rows redacted — TSMC licence forbids reproduction. Source: the
> GDS-out map named above; read its `FILL` rows directly.

Those datatypes are unused today because nothing generates fill geometry.

### 5.2 Seal ring and scribe — not in the design data

Not in these two scripts and not anywhere in the flow. `grep -rn "seal
ring\|sealring\|seal_ring\|scribe"` over `ASIC/genus-innovus/scripts` matches only
the word "describe". The tapeout docs are consistent and explicit:

- `09-signoff-checklist.md:41` — `| 18 | Seal ring + scribe | **broker** | **not in the design data** |`
- `09-signoff-checklist.md:487` — *"There is no seal ring and no scribe structure
  in the stream, and no space reserved for one inside the die box."*
- `10-tapeout-submission.md:214` — *"do they add seal ring and scribe outside our
  1600 × 2000, or must it come out of it? **If it must come out of it, the
  floorplan changes and everything re-runs**"*

That last question is the schedule risk. `CORE_TO_IO` and 21 absolute macro
coordinates are coupled to the 1600 × 2000 die box; a seal ring that has to come
out of it re-opens the entire floorplan, including the 4 µm bond-pad clearance
this page's §4.5 documents.

### 5.3 Decoupling capacitance

No `DCAP*` cell is inserted (§2.8). The cells exist in `tcbn65lp`, at the same row
height, with the same site-count naming. Every gap the fill pass closed with an
inert `FILL*` could have held decap instead. Not a blocker; an unexamined choice.

### 5.4 Summary

| Step | Status | Evidence |
|---|---|---|
| Core filler | done | 102 760 insts, 2026-08-06 log |
| Antenna diodes (physical) | done | 41 217 `ANTENNA` insts |
| Antenna diodes (connected) | **no** | §2.8 — no netlist presence, no connecting command in flow |
| Filler-vs-cell DRC repair | done as of 2026-08-06 | `check_drc` at `filler.tcl:115` |
| Filler-vs-net DRC repair | **unproven** | `route_eco -target` in a `catch`, never executed on a licensed seat |
| Bond pads | done | 82 insts, 0 `BuPAD_*` DRC |
| Via / cut fill | **no** | no `add_via_fill` anywhere |
| Metal density fill | **no** | §5.1 |
| Metal density check | **no** | §5.1 — rules are in the LEF, unread |
| Decap | **no** | §5.3 |
| Seal ring | **no** | §5.2 |
| Scribe | **no** | §5.2 |

---

## 6. Stream-out: `write_stream`, the layer map, and the empty cells

`4_pnr_route.tcl:60-64`:

```tcl
60: write_stream $OUT_DIR/${block_name}.gds \
61:     -map_file $TSMC_65_HOME/CMOS/util/lef/PRTF_EDI_65nm_<rev>/PR_tech/Cadence/GdsOutMap/PRTF_EDI_N65_gdsout_6X1Z1U.<rev>.map \
62:     -lib_name DesignLib \
63:     -merge $gds_merge_list\
64:     -output_macros -unit 1000 -mode all
```

Options, against Stylus TCR `write_stream` (`TCRcom/write_stream.html`):

| Option | Manual | Note |
|---|---|---|
| `-map_file` | *"Specifies the file used for layer mapping. **This file is required for successful stream out**"* | The TSMC PDK's own map. Also: *"You must specify all layers to stream out. Layers that are not specified in the map file are not included."* |
| `-lib_name DesignLib` | `Default: DesignLib` | No-op restatement of the default. |
| `-merge` | *"Specifies a single file or list of files to merge … **The Innovus software automatically creates blackboxes when merging and writing macro files.** It ignores any cells in the merge files that are not used in the design."* | See below. |
| `-output_macros` | *"Writes LEF abstract information such as LEF pin geometries and obstructions for macros … **If you specify this parameter and LEFPIN and LEFOBS are not specified in the map file for the layers in the LEF macros the GDSII structures for those macros will be empty.**"* | |
| `-unit 1000` | *"Specifies the resolution for values in the GDSII file."* `Default:` LEF units | Produces `**WARN: (IMPOGDS-250): Specified unit is smaller than the one in db.` |
| `-mode all` | *"ALL — Writes all layer information specified in mapFile as follows: All instances / All via instances / All generated via cells"* | The alternatives are `FILLONLY`, `NOFILL`, `NOINSTANCES`. |

### 6.1 `gds_merge_list` merges only the memory macros

`config.tcl:198-207`:

```tcl
set gds_merge_list [list \
    ${RF32_GDS} ${RF16_GDS} ${RF8_GDS} ${RF1_GDS} \
    ${CC_ROM_GDS} ${ETH_ROM_GDS} ${FLASH_DATA_GDS} ${FLASH_TAG_GDS} ]
```

Eight files: four Arm register-file compilations, two ROMs, two flash-cache RAMs.
**No standard-cell GDS, no IO-driver GDS, no bond-pad GDS.** All three of those
libraries are `_FE` (Front End) packages on this site, which ship LEF and
timing but no layout — see `docs/TSMC_BACKEND_PACKAGE_REQUEST.md`.

Innovus says so, once per cell and then in aggregate:

```
**WARN: (IMPOGDS-217): Master cell: DFSND2 not found in merged file(s) and will
therefore not be included in the resulting write_stream file. ...
**WARN: (IMPOGDS-218): Number of master cells not found after merging: 424
```

(`baseline_2026-08-06/logs/pnr_run_core70.log:35153` and `:35175`. Only 21
`IMPOGDS-217` lines are printed before the tool caps them; `IMPOGDS-218` carries
the real total. Neither message has a page in the installed Error Message
Reference — §3.2.)

### 6.2 What the resulting GDS actually contains

The stage docs say the standard cells, IO and bond pads are "empty references".
That is close, but the truth is more specific and more useful. Scanning the
shipped 435 MB stream (`baseline_2026-08-06/outputs/nanosoc_eth_chiplet_pads.gds`,
2 485 structures) for shape records per structure:

| Structure | Placements (SREF) | Shape records | GDS layers present |
|---|---:|---:|---|
| `INVD1` (a standard cell) | 2 659 | 8 | 31 (M1) only |
| `FILL1` | 30 482 | 2 | 31 (M1) only |
| `FILL64` | 386 | 2 | 31 (M1) only |
| `ANTENNA` | 41 217 | 5 | 31 (M1) only |
| `PFILLER20_G` (IO filler) | 156 | 7 | 31–37 (M1–M7) |
| `PAD70GU` | 42 | 13 | 38, 39, 74 (M8, M9, AP) |
| `PAD70NU` | 40 | 13 | 38, 39, 74 (M8, M9, AP) |
| `PDDWUWSWCDG_G` (IO driver) | — | **0** | — |
| `rf_16k` (merged macro) | — | 913 | incl. 6 (OD), 17 (PO) |

So, precisely:

- **The structures exist and are referenced correctly.** The placements are all
  there — 41 217 `ANTENNA` SREFs, 42 + 40 bond pads, matching the log counts and
  the netlist exactly.
- **What they contain is the LEF abstract, and nothing else.** `-output_macros`
  plus `LEFPIN,LEFOBS` on M1–M9/AP/VIA1–8/RV in the map file means every cell
  contributes its pin and obstruction geometry on those layers. `ANTENNA`'s 5
  shapes are its three `PIN I` M1 rects plus the two rail rects — the diode's
  diffusion is not there. `PAD70GU`/`PAD70NU`'s 13 shapes are their M8/M9/AP `OBS`
  and nothing more.
- **There are no transistors anywhere except in the merged macros.** The map file
  is 48 lines and contains **only** `DIEAREA`, M1–M9, AP, VIA1–8, RV, their `FILL`
  variants, and pin-name text layers. There is no `OD`, `PO`, `CO`, `NW`, `PP` or
  `NP` row. Innovus therefore *cannot* emit device geometry from its own database
  regardless of what the LEF says. The 10 109 OD (layer 6) and 12 854 PO (layer
  17) shapes die-wide come entirely from the eight merged macro files — confirmed
  by the layer histogram above and consistent with `Makefile:356-358`.
- **The true empties are the IO drivers.** `PDDWUWSWCDG_G` has 0 shape records,
  because the patched IO driver LEF supplies pins on layers the map does
  carry but the tool found no geometry to write for it under `-output_macros`.

**Consequence, stated the way a reviewer needs it:** this GDS is a routing-and-
macro stream. Every metal and via shape is real and checkable. Every device-level
shape is missing except inside the eight memory macros. Front-end DRC rules,
density rules and seal-ring rules run against it will fail or return meaningless
results; the back-end metal/via/antenna rules are the only real signal. That is
exactly what `Makefile:356-360` says, and this section is the independent
confirmation of it.

One further stream-out warning worth not chasing: `**WARN: (IMPOGDS-392): Unknown
layer M11`. The Error Message Reference does document this one
(`innovuserrmsg/IMPOGDS-392.html`): *"If in the specified map file a layer name is
used that is not known from the LAYER statement of the LEF … then this warning is
issued."* The map's last two lines name `M10/PIN` and `M11/PIN`; this is a 9-metal
stack. Harmless.

---

## 7. Command index and quick checks

### 7.1 Every command in the two files

| Command | File:line | Stylus? | Manual page opened for this document |
|---|---|---|---|
| `add_filler_gaps` | `filler.tcl:88, 97` | yes | `TCRcom/add_filler_gaps.html` |
| `add_fillers` | `filler.tcl:94, 121` | yes | `TCRcom/add_fillers.html` |
| `check_filler` | `filler.tcl:102` | yes | `TCRcom/check_filler.html` |
| `check_drc` | `filler.tcl:115` | yes | `TCRcom/check_drc.html` |
| `route_eco` | `filler.tcl:148` | yes | `TCRcom/route_eco.html` |
| `create_inst` | `place_bondpads.tcl:140 …` | **legacy option spellings** (`-cell`, `-inst`) | `TCRcom/create_inst.html` |
| `create_relative_floorplan` | `place_bondpads.tcl:141 …` | yes | `TCRcom/create_relative_floorplan.html` |

Adjacent commands cited from pages opened here: `write_stream`
(`TCRcom/write_stream.html`), `check_process_antenna`
(`TCRcom/check_process_antenna.html`), `add_metal_fill`
(`TCRcom/add_metal_fill.html`), `set_metal_fill` (`TCRcom/set_metal_fill.html`),
`check_metal_density` (`TCRcom/check_metal_density.html`), plus
`UGcom/Optimizing_Metal_Density.html`, `innovuserrmsg/IMPSP-5217.html`,
`innovuserrmsg/IMPSP-5106.html`, `innovuserrmsg/IMPSP-5113.html`,
`innovuserrmsg/IMPOGDS-392.html`.

Pages confirmed present in this install but **not opened** for this document, and
therefore not quoted: `innovusTCR/verify_drc.html`, `innovusTCR/ecoRoute.html`,
`innovusTCR/addFiller.html`, `innovusTCR/addMetalFill.html`,
`TCRcom/add_via_fill.html`, `TCRcom/check_cut_density.html`,
`TCRcom/delete_filler.html`, `TCRcom/add_io_fillers.html`.

### 7.2 Naming trap

`floorplan.tcl:87-115` places IO fillers with `add_io_fillers -cells PFILLER*_G
-prefix FILLER`, and `filler.tcl` places core fillers with `add_fillers -prefix
FILLER`. **Same prefix, two completely different populations.** Innovus
disambiguates only by appending the power-domain name to the core ones. Search for
`FILLER_PD_TOP`, never bare `FILLER`.

### 7.3 The checklist

```sh
B=ASIC/genus-innovus

# --- fill actually happened (§3.4) ---
grep -E "Total [0-9]+ filler insts added" $B/logs/*.log     # must print a large number
grep -c "IMPSP-5110"     $B/logs/*.log                       # must be 0
grep -c "For 0 new insts" $B/logs/*.log                      # must be 0
grep "cell ANTENNA"      $B/logs/*.log                       # must be tens of thousands

# --- the repairs are non-inert (§2.6, §2.9) ---
grep -c "WARN: (IMPSP-9082)" $B/logs/*.log                   # must be 0 since 2026-08-06
grep -c "WARN: (IMPSP-5217)" $B/logs/*.log                   # expected 2 — fires before route_eco
grep -c "route_eco -target FAILED" $B/logs/*.log             # must be 0
grep -c FILLER_PD_TOP $B/reports/*_imp_drc.rep               # target 0; was 1

# --- pad ring (§4) ---
grep -c BuPAD $B/reports/*_imp_drc.rep                       # must be 0 at CORE_TO_IO 70
grep -c "PAD70GU\|PAD70NU" $B/outputs/*_pnr.v                # must be 82

# --- the lists are still the .io ring order (§4.2) ---
# no automated check exists. If nanosoc_eth_chiplet_pads.io is regenerated,
# re-derive the eight lists by parity before trusting a run.

# --- stream (§6) ---
grep "IMPOGDS-218" $B/logs/*.log                             # 424 masters missing — expected today
```

---

## Related pages

[`../00-index.md`](../00-index.md) ·
[`../03-floorplan.md`](../03-floorplan.md) ·
[`../04-power-plan.md`](../04-power-plan.md) ·
[`../05-place-cts-route.md`](../05-place-cts-route.md) ·
[`../06-fill-antenna-bondpads.md`](../06-fill-antenna-bondpads.md) ·
[`../07-reading-reports.md`](../07-reading-reports.md) ·
[`../09-signoff-checklist.md`](../09-signoff-checklist.md) ·
[`../10-tapeout-submission.md`](../10-tapeout-submission.md) ·
[`../14-drc-triage.md`](../14-drc-triage.md) ·
[`../15-pg-opens-analysis.md`](../15-pg-opens-analysis.md) ·
[`../16-open-defects.md`](../16-open-defects.md)
