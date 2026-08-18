# 54 — `check_fp_pg.tcl` vs. the toolkit's `pnr_macro_stripe_census`: posture and recommendation

**Status: NOT a reinvention. Keep both, promote two of the three project-side checks to
the toolkit when the current bug-fix and power-plan lanes land, and do not merge FP-SHORT
into the toolkit census's near-miss arm even after promotion — worked geometry below shows
they cover different territory.**

**Measured 2026-08-18, by reading the Tcl and by reading real run evidence
(`ASIC/eth-chiplet/build/pgfix-A/work/innovus.log4`, 22:58). No Genus, Innovus or Calibre
was launched to produce this page, and `check_fp_pg.tcl`, `pnr_macro_stripe_census` and
`power_plan.tcl` were not edited — this is analysis only, per the standing constraint on
this task.**

---

## 0. The answer in five lines

1. **They ask different geometric questions.** `pnr_macro_stripe_census` asks, per macro,
   "does a PG stripe intersect this macro's *placed bounding box*, and how" (§1).
   `check_fp_pg.tcl` asks three unrelated questions over the *whole die*: is any VDD/VSS
   geometry touching (FP-SHORT), is any row segment unfed (FP-ISLAND), is any strip
   walled in (FP-CORRIDOR) (§1). Only FP-SHORT overlaps the toolkit census's *intent*, and
   even that overlap is partial — see point 3.
2. **FP-ISLAND and FP-CORRIDOR have no toolkit equivalent at all**, bug fixed or not.
   `pnr_macro_stripe_census` never looks at a standard-cell row. Deleting either check
   because "the toolkit does this now" would remove real coverage with nothing behind it.
3. **A worked example on this design's own real defect shows the toolkit's *hard* gate
   would likely have missed it, even fixed.** The four historical VDD–VSS shorts
   (`32-macro-placement-pg-short-window.md`) sit on a stripe that only *partially* overlaps
   the shorting macro's bounding box — it is not an edge-to-edge "crossing", which is the
   only thing `PLACE_MAX_MACRO_STRIPES` hard-gates by default. The metric that *would* show
   it — `min_gap` → 0 — is deliberately left ungated on this design
   (`PLACE_MIN_MACRO_PG_GAP = -1`, design.mk §11d). §2.2 shows the arithmetic.
4. **The toolkit check is NOT disabled today.** `PLACE_MACRO_PG_CHECK` is still `1`
   (toolkit default, no override in `design.mk`). The most recent real run
   (`pgfix-A`, today) shows it **actively hard-failing** — 0 of 21 macros resolved — and,
   because `PLACE_STRICT` also sits at its default of `1`, that failure **stopped the
   entire place stage before `place_design` ever ran.** `check_fp_pg.tcl` had already run
   and passed, moments earlier, in the same session. §5.
5. **The `get_db insts` fix appears to have landed in the tree during this analysis**, but
   as of this page there is no run evidence — none — of it having been exercised
   successfully against this design. Until someone re-runs `place` and it produces a real
   `overlaps`/`crossings`/`min_gap` census, the project's *only* proven, unconditionally
   hard-gated defence against a repeat of the four-short defect is `check_fp_pg.tcl`'s
   FP-SHORT arm. §5.

---

## 1. What each check actually measures — read from the Tcl, not the comments

### 1.1 `pnr_macro_stripe_census` (`ASIC/asic-toolkit/flow/common/pnr_utils.tcl:348`)

Per macro in the caller's list, for every PG special-wire shape on the requested layers:

| Metric | What it counts | How |
|---|---|---|
| `overlaps` | (macro, wire) pairs whose rects intersect at all | `pnr_rect_overlap $mb $r` — touching counts |
| `crossings` | the subset that spans the macro's footprint **edge to edge in one axis** | `($x1<=$mx1 && $x2>=$mx2) \|\| ($y1<=$my1 && $y2>=$my2)` — both ends of the *macro's own span* have to be inside the stripe |
| `min_gap` | smallest edge-to-edge gap between two **intersecting** stripes on **different nets**, within that macro/layer | `pnr_rect_gap`, only over stripes that already overlap the macro bbox |

**The unit of measurement is the macro's own placed bounding box.** A PG shape that never
intersects a macro's bbox is invisible to this proc, however close it runs to that macro's
row region, halo, or the row region of the macro next door. `overlaps`/`crossings` are
hard-gated by default (`PLACE_MAX_MACRO_STRIPES = 0`, i.e. any crossing at all fails).
`min_gap` is measured and reported every run but is **not** gated by default
(`PLACE_MIN_MACRO_PG_GAP = -1`) — a deliberate choice recorded in `design.mk` §11d, pending
a number "measured once on this design," which nobody has yet measured because the census
has never completed successfully (§5).

This is a **macro-footprint-scoped mechanism check**: "was the fine mesh cut at this
macro's boundary, and if two nets both touch this macro, how close did they get." It answers
the same question as `check_drc`'s rail-short class would, restricted to the neighbourhood
of a macro, before the tool has spent hours getting to `check_drc`.

### 1.2 `check_fp_pg.tcl` (`ASIC/genus-innovus/scripts/checks/check_fp_pg.tcl`)

Three independent checks, none of them macro-scoped:

| Check | What it measures | Scope | Default gating |
|---|---|---|---|
| **FP-SHORT** | VDD/VSS special-wire geometry that overlaps or has a coincident edge, on the same layer, anywhere | **whole die** (`get_obj_in_area` over the full core/die bbox) | **hard, unconditional** — `overlap >= 0` fails at any count above zero; only escape is a written `FP_PG_SHORT_WAIVER` |
| **FP-ISLAND** | a `split_row` row segment with no same-net *vertical* supply stripe crossing it, whose ends are macro halos rather than the core edge | whole die, keyed off `get_db rows` | report-only by default (no ceiling has ever been set — deliberately, per the file's own comment, so an unfixed defect can't read as a pass) |
| **FP-CORRIDOR** | a wide 1–2 row strip with no row above or below it | whole die | report-only |

**FP-SHORT's scope is the whole die, not any macro's bbox.** It would catch a short
between two ladders wherever it lands — inside a macro, in a row region between two
macros, anywhere VDD and VSS special-wire geometry touches. **FP-ISLAND and FP-CORRIDOR
are not PG-vs-PG checks at all** — they read `get_db rows` and vertical stripe geometry to
ask whether a *standard cell*, not a macro, will have a metal path to a rail once placed.
That is the mechanism `42-stranded-cells-pg-islands.md` measured after the fact, with
Voltus, on 330 disconnected instances; FP-ISLAND asks the same question before placement,
for free, from the same underlying `split_row`/`add_stripes` mechanism `36-…` and `32-…`
already root-caused for the shorts.

### 1.3 Hazard-by-hazard table

| Hazard | Toolkit (`pnr_macro_stripe_census`) | Project (`check_fp_pg.tcl`) | Relationship |
|---|---|---|---|
| Actual VDD/VSS rail short, opposite-net stripes touching, *inside* a macro bbox | `min_gap` → 0, report-only by default; `crossings` only if the shorting stripe happens to span the macro edge-to-edge | FP-SHORT, hard, unconditional, whole die | **overlapping intent, different scope and different default strength — see §2.2** |
| Same defect, in a row region the mesh anchors *around* a macro but that falls outside that macro's own placed bbox | invisible — the overlap test is against the macro's bbox only | FP-SHORT catches it (whole-die scan) | **project-only** |
| Uncut ladder spanning a macro footprint edge-to-edge (the *mechanism*, whether or not it has produced a short yet) | `crossings`, hard-gated at 0 | not measured — FP-SHORT only fires on an actual opposite-net touch | **toolkit-only** |
| Row segment with no same-net vertical stripe feeding it (stranded-cell precursor) | not measured at all | FP-ISLAND | **project-only, no toolkit equivalent** |
| Walled-in 1–2 row corridor (legalizer risk, IMPSP-2021/2040) | not measured at all | FP-CORRIDOR | **project-only, no toolkit equivalent** |
| PG stripe shorting into a *macro's own blockage/keepout* rather than into the opposite PG net | not measured | **not measured either** — `check_fp_pg.tcl` "compares VDD against VSS. It does not compare VDD against a macro blockage" (`47-pg-island-feed-fragility.md` §2, a real incident: 7 new shorts, FP-ISLAND still PASS) | **neither check owns this — a genuine open gap, named already** |

---

## 2. Is `check_fp_pg.tcl` a reinvention of the toolkit's check?

**No — partial overlap on one of three checks, not a reinvention.**

### 2.1 FP-ISLAND / FP-CORRIDOR: not a reinvention, because there is nothing to reinvent

`pnr_macro_stripe_census` has no row-segment logic, no vertical-stripe-vs-row-segment
crossing test, and no adjacency-to-core-edge distinction. These two checks are the only
pre-placement, no-licence-cost early warning this project has for the defect class
`42-stranded-cells-pg-islands.md` spent a full investigation measuring post-route with
Voltus. Retiring them because "the toolkit's macro census covers PG" would delete real
coverage of a defect class the toolkit census cannot see, structurally, by its own stated
design (it is a macro-bbox test; rows are not macros).

### 2.2 FP-SHORT: same intent as the near-miss arm, but the scope and the default strength
differ enough that it is not redundant even once the toolkit check is fixed

Take this design's own historical defect — the four VDD–VSS shorts documented in
`32-macro-placement-pg-short-window.md` (offset-8 case, since fixed by relocating one
memory macro; the fix is landed, but the underlying per-region re-anchoring mechanism is
still open per that document and `design.mk` §11d, and four more macro pairs are recorded
sitting within half a micron of the same phase window). The shorting geometry there is
`x = [844.500, 912.900]`, `y ∈ {1546.600, 1561.600, 1576.600, 1591.600}`, height 0.020 µm —
a coincident-edge marker, opposite nets.

The macro that band belongs to is this project's own boot-ROM macro
(`ASIC/romlibs/eth_rom/eth_rom_via.lef`, a project-generated macro tracked in this
repository, not vendor collateral), placed at `(883.535, 1538.600)`, orientation `MY`,
size `164.665 × 59.735` — giving it a placed bounding box of `x = [883.535, 1048.200]`,
`y = [1538.600, 1598.335]`.

Working through `pnr_macro_stripe_census`'s own tests against that geometry:

- **`overlaps`**: the shorting stripe's rect (`x = [844.5, 912.9]`, `y` at one of the four
  values, all inside `[1538.600, 1598.335]`) does intersect the macro's bbox — `883.535 ≤
  912.9` and `844.5 ≤ 1048.200` hold in x, and the y-band sits fully inside the macro's y
  extent. **So the census would see this shape, once the resolution bug is actually
  fixed and actually re-run.**
- **`crossings`** (the metric `PLACE_MAX_MACRO_STRIPES = 0` hard-gates): requires the
  stripe to span the macro's *own* extent edge to edge in one axis —
  `($x1 \le mx1 \&\& x2 \ge mx2)` or the equivalent in y. In x: `844.5 \le 883.535` is true,
  but `912.9 \ge 1048.200` is **false** — the stripe's right edge falls 135 µm short of the
  macro's right edge. In y: the stripe is 0.02 µm tall and sits well inside the macro's
  59.7 µm height, so neither y-test can trigger either. **`cross` evaluates false for this
  exact defect shape.** The stripe is a partial overlap, not an edge-to-edge span — which
  is consistent with the project's own account of the mechanism: these are 15 µm-pitch M5
  "rungs" drawn across a region's width, not full-macro-width straps.
- **`min_gap`**: this pair of opposite-net stripes *does* intersect the macro and *does*
  touch (a coincident edge is a gap of 0), so `min_gap` would read `0.0000` for this macro
  and `c(worst)` would name it — **but only as a report line.** `PLACE_MIN_MACRO_PG_GAP`
  is `-1` on this design by explicit, written decision (`design.mk` §11d: "stays ungated
  until it has been measured once on this design"), so nothing fails on it.

**Conclusion, stated as a specific and falsifiable claim rather than an assertion:** on
this design's own defect history, and under this design's own current knob configuration,
the toolkit's *hard* gate would most likely **not** have fired on the actual historical
short — the shape of the defect (a partial-width rung, not a full-width crossing) sits
outside what `crossings` tests, and the arm that would show it (`min_gap`) is left
ungated. `32-macro-placement-pg-short-window.md` §6 states, untested, that the toolkit
gate's near-miss arm "would catch this class where it lands inside a macro footprint" —
that is true of `overlaps`/`min_gap` as *measurements*, but the sentence elides that
`min_gap` does not fail the build today, and this page's arithmetic is the first check of
that assumption against real coordinates. **Nobody has run this to confirm it either way**
— the census has never completed on this floorplan (§5) — so this is offered as the
falsifiable prediction it is, not as a settled result.

FP-SHORT, by contrast, is unconditional: `overlap >= 0` on opposite-net geometry fails at
any count above zero, on the whole die, with no macro-bbox restriction and no report-only
default. It would have failed this exact geometry the moment it existed, regardless of
whether the geometry happened to fall inside any macro's bbox or in the row space between
two of them.

**So: keep both, and do not fold FP-SHORT into the toolkit census's near-miss arm even
after promotion.** They are answering the same *question* — "is there a rail-to-rail
short" — with different scope (whole die vs. macro bbox) and a materially different
default failure mode (unconditional hard fail vs. an ungated report line). Collapsing them
into one implementation would either narrow FP-SHORT's scope to macro-adjacency (losing
the inter-macro case) or widen the toolkit census past "a macro-scoped mechanism check"
into something it was not written to be. The honest toolkit-side improvement, if and when
this is promoted, is to add a **whole-die, unconditional PG-short detector as its own
toolkit primitive** alongside `pnr_macro_stripe_census`, not to merge the two.

---

## 3. Integration robustness — which is more likely to be silently skipped

The task's framing assumes the toolkit's hard, unconditional `flow_fail` is the more
durable integration point and the project's hook is the one a future engineer might
forget. **Measured against the actual dispatch code, that assumption does not hold inside
this project today, and it inverts for a second consumer.**

**Within this project, right now, both are hard to skip by accident:**
- `hooks/post_powerplan.tcl` is deliberately fatal if its target script is missing:
  *"Deliberately fatal. A hook that cannot find its check must not look like a hook that
  ran and found nothing... do not delete the hook, which would silently remove the gate."*
- `PLACE_MACRO_PG_CHECK` defaults to `1` and fails loudly, not silently, if it cannot
  derive a layer set (`"It is NOT skipped silently"`, `2_place.tcl:1099`).

**But the two are wired into the flow by structurally different mechanisms, and that
matters for anyone besides this project:**

```tcl
proc flow_hook {name} {
    set dir [flow_env ASIC_HOOKS_DIR]
    if {$dir eq ""} { return 0 }
    set path [file join $dir ${name}.tcl]
    if {![file exists $path]} { return 0 }
    ...
}
```
(`ASIC/asic-toolkit/flow/common/flow_utils.tcl:302`)

`flow_hook post_powerplan` **returns 0 silently** — no error, no warning, nothing printed
— if `ASIC_HOOKS_DIR` is unset or if `hooks/post_powerplan.tcl` simply is not there. This
is the toolkit's documented, deliberate hook philosophy: hooks are opt-in per project.
`check_fp_pg.tcl`'s own internal fatal-if-missing guard only fires *after* `hooks/
post_powerplan.tcl` has already been found and sourced — it protects against the hook file
surviving while its target vanishes, not against the hook file itself never having been
written or copied.

`PLACE_MACRO_PG_CHECK`, by contrast, is **compiled into the toolkit's own place stage**.
Every consumer of `2_place.tcl` gets the attempt automatically; disabling it requires a
positive, greppable line in that consumer's own `design.mk` (which this project's own
comment insists should carry a written reason — a convention, not a mechanism, but at
least a visible one).

**So: within this one project, today, both checks are equally hard to lose by accident.
For the toolkit's stated mission — a second consumer — the hook-based check is the
structurally weaker delivery: a project that adopts `asic-toolkit` gets
`pnr_macro_stripe_census`'s attempt for free and has to actively disable it to lose it; it
gets FP-ISLAND/FP-CORRIDOR/FP-SHORT only if it also copies `hooks/post_powerplan.tcl` and
`checks/check_fp_pg.tcl` and wires `ASIC_HOOKS_DIR` — and if it does not, `flow_hook`
reports nothing at all.** This is itself an argument for promotion (§4), independent of
the hazard-coverage argument in §2: a check that only protects the project that happened
to write it is not doing for the toolkit's other consumers what
`PROMOTION_FROM_NANOSOC_ETH.md` says this project exists to do.

---

## 4. Applying this project's own toolkit-vs-project reasoning

Two documents already establish how this project decides what belongs in the toolkit:
`33-toolkit-legacy-decoupling.md` (file/path ownership) and
`ASIC/asic-toolkit/PROMOTION_FROM_NANOSOC_ETH.md` (which checks/scripts get promoted, and
why). The promotion document's own criteria:

> Ranking is **value to a second consumer ÷ effort**, with anything that cannot be
> published demoted regardless of value.

and its list of what stays project-side is explicitly about **design identifiers** —
`ASIC/common.mk` (41 `nanosoc` hits), pad-ring wrappers, ROM specs — content that is
*this chip's data*, not a *mechanism*.

Applying that test to the three checks in `check_fp_pg.tcl`:

| Check | Design identifiers in the algorithm | Mechanism it depends on | Verdict |
|---|---|---|---|
| FP-SHORT | none — `FP_PG_NETS` is env-configurable, no hardcoded coordinates | any design using `add_stripes`-drawn VDD/VSS special-wire geometry | **toolkit-worthy** — zero design identifiers, general P&R idiom, exactly the "what did this project learn the hard way" bar the promotion doc sets |
| FP-ISLAND | none — `FP_PG_ISLAND_MAX_W` is env-configurable | `split_row -selected` + `route_special -core_pin_target first_after_row_end`, both toolkit/Innovus idioms, not eth-chiplet netlist facts | **toolkit-worthy** |
| FP-CORRIDOR | none — `FP_PG_CORRIDOR_MIN_LEN` is env-configurable | same `split_row` mechanism | **toolkit-worthy** |

All three pass the promotion doc's own bar: general mechanism, zero design identifiers in
the code (the doc **comments** cite this project's coordinates as *proof it works*, which
is different from the check depending on them), and a defect class any Innovus design using
per-macro row splitting can hit. By the promotion document's own north star —
*"what did this project learn the hard way that the next consumer would otherwise
rediscover at the same cost"* — this is close to the textbook case: the compute chiplet (or
any future toolkit consumer with SRAM/ROM macros and per-macro row splitting) is exposed to
exactly this mechanism and has no way to know it from a paragraph in this project's
`docs/tapeout/`.

**Why not do it this week — applying `33-toolkit-legacy-decoupling.md`'s own sequencing
logic, not inventing new caution:**

1. `33-…`'s own rule is to move structural things "after the gating run streams a verified
   GDS, which is the moment genus-innovus can be frozen" — this design does not have that
   yet (`45-measured-status-2026-08-18.md`: no route gate has ever rendered a verdict on
   the promoted stream).
2. `check_fp_pg.tcl` was written **today** and has exactly one proof run behind it
   (`pgfix-A`). Moving or merging code the moment after it is first proven, before its
   sibling (the toolkit census) has even completed one successful run on this design, is
   the same "presence ≠ content ≠ provenance" trap `33-…` spent 400 lines on — a promoted
   copy that has never itself been cross-validated against a real defect is exactly the
   kind of change that *looks* safe and is not.
3. `power_plan.tcl` (which both checks ultimately measure the output of) is under active
   edit by another lane per this task's own brief. Promoting a check that reads its output
   while that file is moving is promoting a moving target.
4. Per the promotion document's own coverage bar (§4 there: "anything added here must come
   with coverage, and that coverage must be able to fail"), a toolkit promotion of these
   three checks needs planted-fault tests the way `check-pins.sh` and
   `asic-flow-calibre-capped` got them — that is real, separate work, not a `git mv`.

**Recommended posture, stated plainly so nobody later deletes one thinking it is
redundant with the other:**

- **Today: keep both running, unmerged, exactly as now wired.** `check_fp_pg.tcl` via the
  `post_powerplan` hook; `pnr_macro_stripe_census` via `PLACE_MACRO_PG_CHECK`.
- **FP-ISLAND and FP-CORRIDOR are not duplicated anywhere else in this flow.** They are
  this project's only pre-placement defence against the stranded-cell and
  legalizer-corridor defect classes. Do not retire them for any reason short of a toolkit
  promotion that actually reimplements their logic.
- **FP-SHORT overlaps in intent, not in coverage, with the toolkit census's near-miss
  arm.** Keep both. If and when FP-SHORT is promoted, promote it as its own toolkit
  primitive (a whole-die, unconditional PG-short detector), not as a change to
  `pnr_macro_stripe_census`'s macro-scoped tests.
- **When the gating run has a verified GDS and the bug-fix/power-plan lanes have both
  landed and been proven on a real run:** promote all three as new toolkit checks,
  following the same "coverage that can fail" bar the last promotion round used, and only
  then consider whether the project-side copies become thin wrappers or are retired.

---

## 5. Live status, right now — verified, not assumed

The task's premise was that today's run might have unblocked itself by setting
`PLACE_MACRO_PG_CHECK=0`. **That is not what happened, and the real state is more
interesting than that.**

- **`PLACE_MACRO_PG_CHECK` carries no override anywhere in this project.**
  `grep -rn PLACE_MACRO_PG_CHECK` across `design.mk`, every Makefile and every build log
  in the tree finds only the toolkit's own default declaration
  (`2_place.tcl:189`, `opt PLACE_MACRO_PG_CHECK 1`) and `design.mk`'s own commentary
  *about* the knob (§11d) — never a line that sets it. `PLACE_STRICT` is likewise left at
  the toolkit default of `1`.
- **The most recent real placement attempt (`build/pgfix-A`, work log `innovus.log4`,
  timestamped 22:58 today) shows the toolkit check actively firing, not disabled:**

  ```
  PLACE-FAIL: the macro/PG census could not resolve 21 of 21 macros to a placed
  object with a bounding box (e.g. ...).
  PLACE-FAIL:   Those macros were NOT examined, so this run has not shown the
  grid is clear of them.
  PLACE-FAIL: strict mode is set - stopping here.
  ```

  This is the `get_db insts` resolution bug named in this task's brief, caught live: every
  one of the 21 macro names resolved to `**ERROR: (IMPDBTCL-247): ... is not a recognized
  object or root attribute**` when looked up individually, in the same session where
  `select_obj` on the identical list of names had already worked moments earlier.
  `PLACE_STRICT = 1` converted that into a hard stop of the entire stage: `3211 warning(s),
  195 error(s)`, no placed database, no `place_manifest.txt`, only pre-placement reports on
  disk.
- **`check_fp_pg.tcl` ran and passed in that same session, minutes earlier**
  (`reports/fp_pg_check.rep`, 22:58: FP-SHORT 0, FP-ISLAND 0 of 18 candidates,
  FP-CORRIDOR 3 warning-only). It measured the real macro-placed floorplan and the real
  power-plan geometry — `floorplan.tcl` and `power_plan.tcl` had both already run — exactly
  as documented in its own header; "placement" in the sense of `place_design` (standard
  cells) had correctly not yet started, which is the check's stated scope, not a shortfall
  against it.
- **So the accurate description of today is: the toolkit check is not disabled, it is
  broken and blocking, and no standard-cell placement exists on this floorplan/power-plan
  pairing at all.** The project is not "relying solely on the project-side check because
  the toolkit one was turned off" — it is relying on the project-side check because the
  toolkit one has, on every real run so far, never produced a usable result.
- **A late finding, from this same reading session:** `pnr_utils.tcl`'s by-name macro
  resolution now reads differently than it did earlier in this analysis — it has been
  rewritten to build a fresh, unfiltered `get_db insts` index once and match by literal
  Tcl string equality, instead of passing the macro's own name back into `get_db insts
  <name>` as a pattern. That is consistent with a fix for exactly the failure quoted
  above, and it appears to have landed in the tree **while this page was being written**.
  **No run evidence exists of it having been exercised.** Nobody should read "the fix has
  landed in the file" as "the census now works on this design" until a `place` stage has
  actually completed the block and produced `place_macro_pg.rep` with real numbers in it.

**The concrete, present-tense risk, stated once and plainly:** until that re-run happens,
`check_fp_pg.tcl`'s FP-SHORT is the *only* check in this entire flow that has both (a) ever
successfully executed against this design's real geometry and (b) an unconditional hard
gate against a repeat of the four-VDD–VSS-short defect. If its `post_powerplan` hook were
ever silently absent for any reason (§3 shows exactly how quietly that can happen), or if
`FP_PG_SHORT_WAIVER` were ever set without an equivalent tightening on the toolkit side,
this design's only remaining defence against that specific, previously-realised, dead-chip
class of defect would be the manual habit `32-macro-placement-pg-short-window.md` §6
already names as a stopgap: grepping the routed DRC report for `Special Wire of Net VSS &
Special Wire of Net VDD` by hand, after every floorplan change, hours into the run.

---

## 6. Recommendation summary

1. **Do not merge or retire either check today.** They are complementary, not duplicate;
   §1–§2 show the geometric coverage they each uniquely own.
2. **FP-ISLAND and FP-CORRIDOR should be promoted to the toolkit** once the current lanes
   land and are proven — they are general Innovus-idiom checks with zero design
   identifiers and no existing toolkit equivalent, exactly the class
   `PROMOTION_FROM_NANOSOC_ETH.md` says is worth a second consumer's time.
3. **FP-SHORT should also eventually move to the toolkit, but as its own whole-die,
   unconditional primitive alongside `pnr_macro_stripe_census`, not folded into that
   proc's macro-scoped near-miss arm.** §2.2's worked geometry shows the two are not
   interchangeable even once the bug is fixed.
4. **Do not treat the toolkit's hard `flow_fail` as inherently the more durable
   integration point.** Inside this project both checks are currently equally hard to lose
   by accident; for the toolkit's own stated mission of serving a second consumer, the
   hook-based delivery (`flow_hook`'s silent no-op on a missing file) is the one more
   likely to be quietly absent on day one of a new adopter, which is itself a reason to
   promote rather than a reason the current arrangement is unsafe *here*.
5. **Re-run `place` once the `get_db insts` fix and the power-plan lane have both landed,
   and read `place_macro_pg.rep` before believing either "the toolkit gate now passes" or
   "the toolkit gate would have caught the historical short."** Neither claim has run
   evidence behind it yet; §2.2 gives the specific prediction to check it against.

---

## 7. Sources

| Claim | Source |
|---|---|
| `pnr_macro_stripe_census` algorithm | `ASIC/asic-toolkit/flow/common/pnr_utils.tcl:260-493` |
| `check_fp_pg.tcl` algorithm | `ASIC/genus-innovus/scripts/checks/check_fp_pg.tcl` (full file) |
| Hook wiring | `ASIC/eth-chiplet/hooks/post_powerplan.tcl`; `ASIC/asic-toolkit/flow/common/flow_utils.tcl:302` (`flow_hook`) |
| Toolkit gate wiring, defaults | `ASIC/asic-toolkit/flow/innovus/2_place.tcl:184-203, 858-872, 1068-1180` |
| Knob defaults, documented | `ASIC/asic-toolkit/docs/source/reference/knobs.md:205-224` |
| PG ratchet decisions for this design | `ASIC/eth-chiplet/design.mk` §11b–11d (around lines 973-1069) |
| The four historical shorts, coordinates and mechanism | `docs/tapeout/32-macro-placement-pg-short-window.md` |
| Stranded-cell defect FP-ISLAND targets | `docs/tapeout/42-stranded-cells-pg-islands.md` |
| Split-row anchoring mechanism | `docs/tapeout/36-split-row-pg-anchoring-hazard.md` |
| Island-feed fix status, shared blind spot (PG vs. macro blockage) | `docs/tapeout/47-pg-island-feed-fragility.md` |
| Toolkit/project ownership philosophy | `docs/tapeout/33-toolkit-legacy-decoupling.md`; `ASIC/asic-toolkit/PROMOTION_FROM_NANOSOC_ETH.md` |
| Boot-ROM macro size (project-generated, tracked) | `ASIC/romlibs/eth_rom/eth_rom_via.lef:20` |
| Boot-ROM macro placement | `ASIC/eth-chiplet/floorplan/floorplan.tcl:324` (`place_macro {*u_network_core*u_region_bootrom_0*rom_via*} 883.535 1538.600 MY`) |
| Live run evidence, today | `ASIC/eth-chiplet/build/pgfix-A/work/innovus.log4`, `ASIC/eth-chiplet/build/pgfix-A/reports/fp_pg_check.rep`, `place_pg_audit.rep` |
| Whole-project measured status | `docs/tapeout/45-measured-status-2026-08-18.md` |

No vendor values, deck revisions or site paths are reproduced here. The boot-ROM macro
size and placement are this project's own generated-macro data
(`ASIC/romlibs/`, tracked in this repository), quoted for the same reason
`32-macro-placement-pg-short-window.md` quotes this project's own placement coordinates —
they are the evidence the argument in §2.2 rests on.
