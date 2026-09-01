# The three power-grid rows: what they are, what was fixable, and what the gate should assert instead of zero

    date     2026-09-01
    branch   flow/rc5-virtual-tapeout
    scope    check_power_vias and check_connectivity -type special, the three
             route-gate rows that have failed on every candidate this design
             has produced: 380 missing power vias, 51 PG opens, 727 dangling
             PG wires.
    summary  docs/tapeout/66-rc5-flow-findings.md, F31. This file is the
             evidence; that entry is the conclusion.
    changed  ASIC/genus-innovus/scripts/power_plan.tcl:1189 (new pass),
             ASIC/eth-chiplet/hooks/post_powerplan.tcl (one prose amendment).
    NOT changed  design.mk. The three budgets are PROPOSED in section F31.7 and
             are for that file's owner to land.

The route stage's signoff gate has failed the same three rows on every candidate
this design has ever produced:

    380 missing power vias   check_power_vias -layer_range {M1 AP}   > budget 0
     51 PG opens             check_connectivity -type special        > budget 0
    727 dangling PG wires    check_connectivity -type special        > budget 0

All three are now diagnosed object by object, **355 / 25 / 551 of them are gone**
from a change to `power_plan.tcl` that is proven on a real database, and the
remainder has a per-row reason and a withdrawal condition. A gate that fails
permanently on three rows nobody can act on teaches people to skip the gate;
these three rows have taught that for a month.

## F31.0 — THE NUMBERS, IN ONE TABLE

Measured 2026-09-01 by driving the **committed bytes** of `power_plan.tcl`
(lines 1189–1513 sliced out of the file at run time, so this is the code, not a
paraphrase of it) against a **copy** of `rc5vt-20260829`'s own
`work/nanosoc_eth_chiplet_pads_fplan`. Read-only source; no run artefact was
written to. Evidence: `ASIC/eth-chiplet/build/pgdiag-20260901/` (gitignored,
host-only — see the collection note at the end).

| | before | after | delta |
|---|---:|---:|---:|
| missing power vias | 367 | **12** | −355 (−96.7%) |
| PG opens (IMPVFC-200) | 51 | **26** | −25 (−49.0%) |
| dangling PG wires (IMPVFC-94) | 727 | **176** | −551 (−75.8%) |
| `check_drc` markers | 3 | 9 | +6 |
| PG special vias | 169,736 | 171,135 | +1,399 (+0.82%) |
| PG special wires | 14,966 | 14,921 | −45 |

The same recipe run against `rc6route-20260831`'s **routed** database gives
367 → 12, 51 → 26, 727 → 175 — the identical landing point from the other end
of the flow.

## F31.1 — THE THREE ROWS ARE ONE POPULATION, AND PLACE, CTS AND ROUTE MAKE NONE OF IT

The `Net ...` lines of both reports, sorted, are **byte-identical across four
runs**, one of which (`rc6full-20260831`) is a whole RTL→GDS rebuild with a
different synthesis, placement, CTS and route:

    connectivity  md5 0a857957822e0aa8fa32ba901721e9ec   (all four runs)
    power vias    md5 67731cf0a8becbc166937938e31fd6f3   (all four runs)
    diff lines between rc5vt and rc6full: 0 and 0

and the counts on the four saved databases of a single run walk like this:

    work/..._fplan    (power_plan.tcl's own output)    51 / 727 / 367
    work/..._placed                                    51 / 727 / 367
    work/..._cts                                       51 / 727 / 367
    work/..._routed                                    51 / 727 / 367   (see F31.6)

**Placement, CTS and routing contribute nothing at all.** That is why the numbers
never move with the design, and it is why the fix belongs in `power_plan.tcl`
and could not have belonged anywhere else.

`check_connectivity -type regular` is clean on all four runs — 0 `Net` lines,
"Found no problems or warnings" in `*_imp_connectivity_prestream.rep`. Verified,
not taken on trust. Whatever this is, it is confined to the power grid.

**Neither report is truncated.** The connectivity report reads `778 total
info(s) created` and the power-via report `380`, both under the 1,000 default
cap and far under the `-error 200000 -warning 200000` the flow passes, and
51 + 727 = 778 exactly. The saturation trap that made "329 opens / 671 dangling"
a floor rather than a total on older runs is not in play here.

## F31.2 — ROW 2 (51 OPENS): THE MARKER COUNTS PIECES, AND TWO OF THE 51 ARE THE HEALTHY GRID

Per net: **VDD 9, VSS 18, VDDIO 12, VSSIO 12**. Decomposed by querying every
marker box in the database:

| n | what it is | electrically |
|---:|---|---|
| 24 | VDDIO/VSSIO pad-pin taps — five coincident 4.0 × 22.0 `padring` plates on M3..M7, one stack per IO supply pad, each lying on that pad's own PG pin | **live** |
| 2 | the bounding boxes of the WHOLE VDD and VSS grids: (191.000, 82.815)–(1409.000, 1917.185) containing 8,280 special wires and 4,469 PG pins, and (176.000, 82.815)–(1424.000, 1917.185) containing 6,566 and 4,467 | **live — this is the power grid** |
| 23 | one dead M3 `corewire` each: 0.33 µm wide, 0.49–4.075 µm long, no via, no same-layer same-net neighbour within 1 nm, no PG pin | **dead** |
| 2 | short isolated rail clusters at (1038.535, 279.870) VDD and (1038.535, 278.245) VSS — an M1 followpin stub with M1/M2/M5 corewires, 8 and 5 wires | **live within themselves, isolated from the grid** |

24 + 2 + 23 + 2 = 51.

**The recorded finding that the opens count PIECES and not breaks is CONFIRMED,
three independent ways:**

1. Innovus's own documentation. `check_connectivity -bbox_open_markers`:
   *"Displays violation markers for opens as the bounding box of the island."*
2. A break marker cannot have the whole core as its box. Two of the 51 do.
3. **The arithmetic discriminates.** VDDIO has 12 supply pads, 12 mutually
   disconnected taps and **12** markers. Twelve disconnected pieces are ELEVEN
   breaks. The count is 12, not 11. Likewise VDD: 1 main body + 8 fragments = 9
   pieces = 9 markers, where breaks would be 8.

and a fourth, produced by the fix: after the pass **VDD reports nothing at all**.
Its 9 markers went to **0**, not to 1 — a net that becomes a single piece stops
being reported. So the marker is per piece, and the "main body" marker only
exists because other pieces do.

**Why the 24 IO markers exist, and why they are not a defect.** They are the
direct product of `power_plan.tcl:179/188`, the `route_special -connect {pad_pin
pad_ring}` pass added on 2026-08-18 so that VDDIO/VSSIO would carry *some*
special-net metal for GDS `SPNET` labels to attach to (doc 51). `add_rings` at
:115 names only `{VDD VSS}`, so those two nets have **no ring**: the IO supply is
distributed by **abutment** through the pad ring, and `check_connectivity` cannot
trace abutment. Before that fix the two nets had zero geometry and appeared as
IMPVFC-98 ("no routing at all"). The flow traded 2 unrouted nets for 24 open
pieces, deliberately, and the trade is right — but nobody wrote down that the
24 would show up here.

**What the 23 M3 islands are, with a worked example.** `route_special` draws each
core-pin tap as a chain of collinear segments on different layers and does not
always via them together. One of 23 identical sites:

    VDD M1 corewire   698.635 -> 699.085    off the followpin, which ends at 698.8
    VDD M3 corewire   699.085 -> 702.010    ISLAND: no via, no neighbour, no pin
    VDD M7 corewire   702.010 -> 728.100    reaches the grid at its far end

Three segments, two layer changes, **zero vias**, and the segments ABUT at a line
rather than overlap, so no via could be generated. The VSS taps at the same x
have a full VIAGEN12/23/34/45 stack and work. That single defect is counted once
in the opens row, **twice** in the dangling row (both ends) and twice more in the
missing-via row — which is how one mechanism produces three "independent"
failures.

## F31.3 — ROW 3 (727 DANGLING): EVERY MARKER IS A POINT, AND 678 OF THEM ARE ON A LIVE WIRE

Every one of the 727 markers has **identical start and end coordinates** —
checked on all 727, zero exceptions. It is not a wire; it is the unterminated
END of one. The 727 markers sit on **702 distinct wires** (678 with one dangling
end, 23 with two, 1 with three).

Classified by asking the database, for the wire under each marker, whether
anything at all touches it (any via, any same-net metal on its layer, any PG pin,
within 1 nm):

| n | state | what it is |
|---:|---|---|
| 678 | LIVE | a tap or riser connected somewhere else, with one end left unterminated. 357 `corewire`, 320 `blockwire`, 1 `stripe` |
| 46 | ISLAND | the two ends of the 23 dead M3 corewires of F31.2 — the same 23 objects |
| 3 | — | a via landing with no wire of that net on that layer (M8 ×2, AP ×1) |

**A dangling end on a wire that is live elsewhere is inert.** It carries no
current, breaks nothing, and shorts nothing. Row 3 as it stands is 93% a report
of cosmetic overhang.

But it is not *only* that, and the fix proves it: 551 of the 727 disappeared when
the missing vias were filled. So most of those "overhangs" were ends that
**should** have had a via and did not — rows 1 and 3 are largely the same defect
seen through two instruments.

## F31.4 — ROW 1 (380 MISSING VIAS): TWO PG RISERS CROSSING, WITH NOTHING BETWEEN THEM

    layer pair   M4:M5 192   M5:M6 106   M6:M7 45   M3:M4 16   M4:M9 13 (stacked)
                 M1:AP 3 (stacked)   M8:M9 3   M7:M8 1   M9:AP 1
    kind         368 orthogonal / 12 nonorthogonal ; 364 adjacent / 16 stacked
    nets         VDD 260 / VSS 120

The overlap boxes are tiny and repetitive: **195 are 0.35 × 0.33 µm and 76 are
0.35 × 0.35 µm** — 71% of the row is two shapes of one size. Querying what lies
on each side, the parties are overwhelmingly `blockwire` × `blockwire`,
`blockwire` × `corewire` and `corewire` × `corewire`: **two `route_special`
risers crossing each other**, not a stripe failing to reach the grid. Only about
30 of the 380 involve an actual stripe or ring. No route blockage sits at any of
the 380 sites (checked; 380 of 380 have none).

`check_power_vias` reports **every** same-net cross-layer overlap that has no
via, whether or not one is needed and whether or not one is legal. That is the
row's character: it is a redundancy census, not a continuity check.

## F31.5 — THE FIX, AND THE PROOF THAT IT COULD HAVE FAILED

`power_plan.tcl:1189` now asks the two checks where they are unhappy, hands
exactly those boxes to Innovus's own via generator, and lets the `fix_via
-min_step` / `-min_cut` pass that already sits at :1504 clean up after it.
Nothing is coordinate-driven; every site comes from the tool, so a floorplan
change moves the sites and the pass follows them.

**The one box it must never pass on** is a whole-net piece bbox — because the
marker is per piece, a net's main body is reported with the core as its box, and
handing that to `update_power_vias` would silently make a targeted pass global.
Boxes over 50 µm in either axis are dropped, and the run says how many:
`1143 site box(es); 2 whole-net piece box(es) dropped`. Two: VDD's and VSS's.

**Why the order matters.** Adding the vias costs 117 new `check_drc` markers,
**111 of them MINSTEP** — precisely what `fix_via -min_step` exists to repair.
Measured: 3 → 120 → 9. Put the pass anywhere after the fix_via block and the
cost stays; put it before, and the flow already owns the cleanup.

**Discrimination — the check can still fail.** Deleting exactly one PG via from
the baseline database (a `VIAGEN78` on VDD; 93,128 → 93,127) moved

    missing power vias   367 -> 368
    dangling PG wires    727 -> 728
    PG opens              51 ->  51   (a lost via makes an end, not a piece)

Two of the three rows are sensitive to a **single object**, so a fall of 355 and
551 is a real fall and not an instrument that stopped looking. Row 2's
sensitivity is shown by the fix itself: 51 → 26, and 42 in a weaker arm.

**The guards were tested, not asserted.** Three negative tests against the
committed bytes:

| test | result |
|---|---|
| `EVP_PG_ADD_VIAS=bogus` | refuses: *"is not one of off\|markers\|global"* |
| `EVP_PG_ADD_VIAS=off` | prints the skip line, edits nothing |
| `REPORT_DIR` made unwritable so the BEFORE report cannot be written | refuses: *"no summary line … Refusing to run a repair whose BEFORE state is unknown — an unparsed report is not a clean one"* |

That third one is the one that matters. `_pgav_total` returns **−1**, not 0, when
a report cannot be read, and −1 does not mean "no sites". A pass that treated an
unreadable report as a clean one would be another zero that measured nothing.

**A second pass converges.** Running the finder again after the first pass found
213 boxes, added **zero** vias and left the missing-via count at 12. One pass is
enough and the block runs one.

**What was rejected, and why.** `update_power_vias -add_vias 1` with no `-area`
was measured on the same database:

| arm | missing | opens | dangling | check_drc | PG vias |
|---|---:|---:|---:|---:|---:|
| baseline | 367 | 51 | 727 | 3 | 169,736 |
| **marker-driven (shipped)** | **12** | **26** | **176** | **9** | **171,135** (+0.8%) |
| global, no `-area` | 32 | 28 | 202 | 18 | 261,296 (**+54%**) |

Global is better on two rows and costs **+91,560 PG vias, about 34,000 of them on
VIA12/VIA23/VIA34** — a routing-resource change on the three densest signal
layers of a die at 85.7% utilisation. Nothing short of a full route can say
whether that is affordable, and I did not run one. It is reachable as
`EVP_PG_ADD_VIAS=global` and should not be turned on without one.

**Two honest caveats on the +6 DRC.**

* It is an **upper bound**. Those markers were measured against a database that
  had already been through this file's fix_via pass, its PG-residue cleanup and
  the `post_powerplan` hook's DRC edits. In the flow all three run *after* the
  new block and get a chance at the residue that this measurement did not give
  them. The 9 are 4 MINCUT M5, 3 MINCUT M4 (the pre-existing SRAM-pin trio), 1
  MINHOLE M5, 1 MINCUT M4.
* The same recipe applied to a **routed** database costs **72** DRC, not 9. The
  added PG metal contends with signal routing that does not exist yet at
  power-plan time. That is a second reason the pass belongs where it is put, and
  a warning against anyone re-deriving it as a post-route ECO.

## F31.6 — AND ONE THING I COULD NOT CLOSE: THE ROUTE GATE'S NUMBER IS NOT REPRODUCIBLE FROM THE DATABASE IT SHIPS

`rc6route-20260831` reports **380** missing power vias and **0** `check_drc`
violations. Re-running the identical commands in a fresh session on that run's
own saved `work/nanosoc_eth_chiplet_pads_routed` gives **367** and **3**.

    05:08:38  reports/..._imp_drc.rep          "No DRC violations were found"
    05:09:33  reports/..._power_vias.rep       380 total info(s) created
    05:14:54  work/..._routed                  saved
    fresh session on that saved database:      367 missing vias, 3 check_drc

The connectivity numbers agree (51 / 727 / 778 total, both ways), so it is not a
wrong database: it is the same design. The 13 that differ are all one shape —
M4 macro risers crossing under the M9 core ring, 0.351 × 6.0 µm boxes, 12 in the
top band at y 1796.403–1802.403 and one in the bottom at 197.002–203.002. The 3
`check_drc` markers that differ are the SRAM M4 MINCUT trio, present in `_fplan`
and in `_routed` and absent from the run's own report.

Nothing between the census and the save mutates geometry — the only step there is
`pg_capacity`, and it contains no `update_power_vias`, `add_via`, `edit_*`,
`delete_obj`, `create_*`, `fix_via`, `route_special` or `add_stripes`. So the
difference is **session state, not layout**: the checkers behave differently in a
session that has just run the router than in a fresh `read_db`.

**Why this matters more than 13 vias.** It means the three rows the gate asserts
on are not reproducible from the artefact the run hands over, so a budget set
from a run's report is a budget against a number nobody can re-measure. This is
the same class as the 08-10 LVS and the rest of "green verdicts read the wrong
stream", arriving in a new place.

**Cheapest next probe, for whoever owns `4_route.tcl`:** run `check_power_vias`
and `check_drc` a second time immediately after `pnr_write_db routed` and write
both to `*_postsave.rep`. If they read 367/3, the census is stale relative to the
database and the manifest should carry the post-save pair. Two minutes of stage
time. The connectivity pair does NOT disagree — 51 / 727 / 778 both in-flow and
from a fresh session on the saved database — so whatever this is, it is specific
to `check_power_vias` and `check_drc`.

## F31.7 — THE BUDGET: A FORMULA PER ROW, NOT A RUN'S NUMBER

`ROUTE_BUDGET_OPENS`, `ROUTE_BUDGET_DANGLING` and `ROUTE_BUDGET_PG_VIAS` all
default to 0 in `4_route.tcl:171/172/182` and nothing in `design.mk` overrides
them. `design.mk:2284` is explicit about why nobody has set the via one: *"Do NOT
write ROUTE_BUDGET_PG_VIAS from any run on record."* That instruction is right
and this section does not break it. **None of the three numbers below is a run's
count.** Two are formulas over the pad census and the net list, and the third is
a declared ratchet that says so.

`design.mk` is the integration point and is not mine. These are the lines to add,
each with the reason and the condition on which it must be withdrawn.

---

**Row 2 — `export ROUTE_BUDGET_OPENS ?= 24`**

*Reason.* `check_connectivity` emits **one marker per piece** of a special net
that has more than one piece (proven four ways in F31.2). This design has an
irreducible 24: one per IO supply pad. `prov.pads.VDDIO 12` + `prov.pads.VSSIO 12`
= 24, and each is a live pad-pin tap on a net whose bus is carried by pad
abutment, which the checker cannot trace. **The budget is a function of the pad
census, not of a run** — add or remove an IO supply pad and it moves with it.
VDD and VSS contribute 0 when each is a single piece, and after the fix VDD does.

*What must still fail.* The 25th open. On the fixed database the count is 26, so
**this budget fails today by 2**, and both are named: the VSS main body, plus one
isolated 17 µm VSS rail segment at (1038.535, 278.245). That segment is the last
PG island this floorplan produces, it is exactly the class doc 42 chased, and the
gate should go on saying so. Do not round the budget up to 26 to make the row
green — 26 would make the design's one remaining island invisible, which is what
a budget set to the day's number always does.

*Withdrawal.* Give VDDIO/VSSIO a real ring (or delete their pad-pin taps and
accept IMPVFC-98 for them again) and the 24 goes to 0. If the marker semantics
change in a future Innovus release, re-derive from F31.2's test: count the pieces
of a net you know to be in N pieces and see whether the report says N or N−1.

---

**Row 1 — `export ROUTE_BUDGET_PG_VIAS ?= 25`**

*Reason.* Composed, not observed:

| n | class | why it cannot be filled |
|---:|---|---|
| 4 | non-orthogonal M5:M6 adjacent | `check_power_vias` flags same-direction overlaps; `update_power_vias -orthogonal_only` defaults to 1 and refuses them. The checker demands a via the fixer is forbidden to place. Innovus says so out loud: IMPPP-532, *"top layer and bottom layer have same direction but only orthogonal via is allowed"* |
| 4 | the M9/AP corner stack at x 249.305, y 1784.8–1794.6 | the AP stripe/pad stack; RV vias into AP |
| 13 | M4 macro risers under the M9 core ring | the 13 of F31.6 — they are only reported in-flow, and until F31.6 is closed nobody knows whether they exist in the shipped database at all |
| 4 | singletons: one VIA4, one VIA7, one VIA8, one VIA4 | individually triaged, none in a stripe-to-stripe path |

4 + 4 + 13 + 4 = 25, and the measured post-fix figure is 12 on the saved database
and would be 12 + 13 = 25 if the route stage's own census is the one that counts.
**Assert the per-layer-pair split as well as the total** — the manifest already
carries `pg_via_by_pair`, and "25 missing, 13 of them in one pair" and "25
scattered" are different designs. `4_route.tcl:2665` already prints the split into the failure text and
`route_manifest.txt` records `pg_via_by_pair`; what is missing is a gate on it.

*Withdrawal.* Drops to 12 the moment F31.6 resolves in favour of the saved
database. Drops by 4 more if the M9/AP corner stack is built properly. The
non-orthogonal 4 go only if Innovus grows a fixer for them, so they are the
long-term floor.

---

**Row 3 — `export ROUTE_BUDGET_DANGLING ?= 176`  — declared as a RATCHET, not a floor**

*Reason, and it is a weaker one than the other two — say so in the file.* There is
no structural formula for this row. A dangling marker is an unterminated wire END
and 678 of the original 727 were on wires that are live elsewhere, so the row is
mostly inert. It also carries no information the opens row does not: an island
contributes at least two dangling markers **and** an open marker, while a live
overhang contributes one dangling marker and nothing else. Once `ROUTE_BUDGET_OPENS`
is armed at 24, this row's job is regression detection only.

176 is the measured post-fix value on `rc5vt-20260829`'s `_fplan`, and the
provenance belongs beside it. **This is the one number here that is a run's
number, and it is only defensible because it is declared as a ratchet:** the gate
fails on an increase, not on the value. It is armed — the negative control moved
it 727 → 728 by deleting one via.

*Withdrawal.* Replace the whole row the moment the flow can count **islands**
instead of ends. The property test is already written and cheap
(`power_plan.tcl:1710` `_pgr_dead`, and the probe in
`build/pgdiag-20260901/scripts/liveness.tcl`): a wire with no via, no same-layer
same-net neighbour and no PG pin within 1 nm. On the baseline that number is 23
and after the fix it is 0. A gate on *that* is worth failing on; a gate on 176
ends is worth a ratchet and no more.

---

## F31.8 — SHOULD IMEC'S CLEAN DRC ON THESE BYTES REASSURE US OR WORRY US?

**Neither. It is silent on the question, and reading it as reassurance is exactly
the failure this project keeps writing down.**

A foundry DRC deck contains no rule of the form *"there shall be a via where two
same-net shapes on adjacent layers overlap"*, and none of the form *"a wire shall
not end without a connection"*. Both are legal geometry. imec's deck could not
report any of these 1,158 objects however real they were, so its silence carries
no information about them — the same shape as the 08-10 LVS reading clean because
`.GLOBAL` omitted VSS, and of every other entry in "a zero that measured nothing".

There is exactly one path by which DRC *can* see PG debris: when a fragment is
small enough to trip minimum area or minimum width. That has happened here
before — the M5 island at (565.425, 477.900) trips MAR and MINWIDTH and is the
one the residue cleanup deletes. The 23 M3 islands are 0.16–1.34 µm², comfortably
over M3 minimum area, so **no deck anywhere would have reported them**. That is
the honest reason imec is quiet, and it is a property of the objects, not
evidence about them.

Nor would LVS have caught them, because a dead island connects nothing and a live
overhang connects nothing extra: neither changes the netlist. And the design's
LVS runs black-box.

So what *should* worry us is narrower and more useful than "imec is wrong":
**the rc5/rc6 lineage has no independent instrument confirming grid continuity.**
The three rows are that instrument, they have been failing for a month with a
budget of zero, and the response has been to read past them. The Voltus rail
solve — the one measurement that would find a stranded cell rather than infer it
— was last run on `fp1505`/`rzG`, not on anything in this lineage, and it is the
right thing to run next now that the opens row has been reduced to 24 structural
markers plus one named site.

Concretely, and this is the part imec's report genuinely cannot help with: after
the fix, VDD is a single connected piece and VSS is two — the grid, and one
17 µm island at (1038.535, 278.245). Asked which instances sit on that island,
the routed database answers **four `DCAP4` endcaps and eight `FILL*` cells and
nothing else**: `ENDCAP_PD_TOP_241/242/247/248` and
`FILLER_PD_TOP_T_1_4445..4448` and `4568..4571`. **No functional cell is on it**,
which agrees with the 08-24 correction to doc 42 rather than with its original
330. So the honest verdict on grid continuity in this lineage is better than
feared: the entire opens row reduces to 24 structural IO markers and one decap
that decouples nothing.

That is a good result and it is also the point. It took a day of measurement to
learn it, because the row that carried it has read `51 > 0` for a month and
nobody could tell 24-structural-plus-one-decap from twenty-five stranded flops.
imec's clean DRC could never have told them apart either.

## F31.9 — EVIDENCE, AND WHERE IT IS NOT

Everything above is reproducible from
`ASIC/eth-chiplet/build/pgdiag-20260901/` — database copies, probe scripts,
per-arm report sets and Innovus logs. **That directory is under `build/` and is
therefore gitignored and host-only**, which is the same collection hole doc
`evidence-is-gitignored-and-unreachable` names for the LEC and ROM chains. The
scripts are small and self-contained (`scripts/arm.tcl`, `scripts/armm.tcl`,
`scripts/liveness.tcl`, `scripts/census.tcl`, `scripts/verify_block.tcl`) and
should be promoted into `ASIC/genus-innovus/scripts/checks/` if this
measurement is ever to be re-run by anyone else; that is not done here and is
listed as owed rather than claimed.

**No full flow run was launched for any of this.** Every number comes from
`read_db` on a copy plus the checks, on databases that already existed.
