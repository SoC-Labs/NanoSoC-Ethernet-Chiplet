# Clean syn -> GDS run: multi-agent plan and launch gates

Goal: one clean synthesis -> place -> cts -> route -> GDS on the CURRENT codebase,
with all DRC-reducing flow and floorplan work landed first, and every gate that
judges it proven able to fail.

Baseline being replaced: fp1505 route, 2026-08-19 00:24 — the first route verdict
this project has produced. It FAILED on 3 rail-to-rail M4 shorts, and its
provenance records `git_dirty yes`, so it is not reproducible.

---

## Phase 0 — Investigation (RUNNING, read-only, 5 lanes)

No lane may edit, commit, or hold an EDA licence. Output is findings only.

| Lane | Question | Feeds |
|---|---|---|
| A | The 3 M4 rail-to-rail shorts: coordinates, mechanism, which script made the geometry, and whether they share a cause with the other PG defects | Lane 1 |
| B | PG cluster: 575 missing vias (M4->M5 = 475), 64 opens, 889 dangling wires. One mechanism or several? State of the "PG island feed" fix | Lane 1 |
| C | Floorplan DRC precursors: corner rotation, CSR.R.1 ESD keepout, the five-macro edge mechanism. What is landed vs dirty vs proposed | Lane 2 |
| D | Synthesis blocker: C2 `set_max_delay`, SDC-202 / TIM-303 / TUI-66. Minimal correct fix as a timing-intent decision | Lane 3 |
| E | Can the gates fail? Vendor guard, LVS preflight contradiction, route budgets, METAL_FILL ownership, signoff.py prove coverage | Gate G6 |

---

## Phase 1 — Remediation (4 lanes, ONE owner each)

The hard rule, learned today: **one owner per file**. Five sessions edited
`power_plan.tcl` in a single day and produced a retracted fix, a collision, and
an unreduced verdict.

**Lane 1 — Power grid.** Owns `power_plan.tcl`, nothing else touches it.
Lands the M4 short fix and whatever Phase 0 A+B conclude about vias/opens/dangling.
Must screen on the PG probe and REDUCE THE RESULT TO A VERDICT before claiming it
— the last island-feed screen was launched and never reduced.

**Lane 2 — Floorplan and pad ring.** *** NO WORK TO DO — audited and closed. ***
Lane C found the floorplan frozen and clean at HEAD: all seven floorplan/pad
scripts byte-identical to HEAD, nothing dirty, nothing half-applied.
  - Corner rotation ALREADY LANDED at `d93331f`, and now confirmed on real
    geometry: `check_padring_gds.py` on the fp1505 stream parses 2,346,912
    placements and reports all four corners 180 degrees out, observed matching
    expected under exactly the rotation `d93331f` applies.
  - CSR.R.1 is **56 results, not 40**, and `floorplan.tcl:219-223` is a COMMENT,
    not code. The keepout that exists (`CSR_CORNER_KEEPOUT`, lines 224-232) is
    already committed and in the flow. The real fix is deleting the four
    PCORNER_G cells, which breaks pad-ring bus continuity at all four corners and
    is BLOCKED ON AN ESD RULING we cannot supply. Broker item, not agent work.
  - The **40** figure belongs to the macro-edge item (M4.S.2.1 28 + M4.S.1 12),
    not to CSR.R.1. The two were conflated in the earlier draft of this plan.
  - Macro-edge DRC (40 M4-spacing + 10 G.4, five macros) is root-caused but has
    NO fix in tree, and the one variant ever measured came back three times
    worse. DO NOT attempt it before this run.

**DO NOT NUDGE A MACRO TO IMPROVE ANYTHING.** The PG phasing hazard has no
locality: a 0.52um move of `rf_32k` at x=290.8 changed the short count 550um away
at x=883.5. `floorplan.tcl:256-273` describes the current coordinates as "LUCKY,
not safe", with four more macro pairs inside half a micron of the same window.
Any screening must read the rail-to-rail short count from `probe_pg_build.tcl`,
never `check_drc` — which disagrees with Calibre IN SIGN on this design.

**Lane 3 — Timing intent.** Owns the SDC. Lands the C2 fix so `make syn`
completes at HEAD. NOT by waiving SDC-202/TIM-303/TUI-66. Also resolves the
latent inert-catch at `tidelink_constraints.sdc:617`.

**Lane 4 — Gate repair.** Owns `ci/` and the toolkit gate scripts. Fixes the
vendor guard's exit-0-on-skip, resolves the LVS preflight contradiction, and
removes any budget set to "whatever the last run produced".

Lanes 1 and 2 both feed the pre-place stages and must both land before launch.
Lanes 3 and 4 are independent and can land in any order.

---

## RETRACTED: the "3 M4 rail-to-rail shorts"

**There is no rail-to-rail short in fp1505. The gate's hard failure is a parser
false positive, and fp1505 is BETTER than the shipping stream.**

    fp1505 record-class census   43 spacing, 10 minstep, 4 nsmetal,
                                 3 minwidth, 2 minhole, 1 mar
    grep -ci '^SHORT' fp1505     0
    grep -ci '^SHORT' full-20260814 (SHIPPING)   4
                                 SHORT: ( Metal Short ) VSS & VDD ( M5 )  x4

The three records the gate called shorts are
`SPACING: ( ParallelRunLength Spacing )`. The metal does not touch — the smallest
gap is 135 nm of dielectric. The gate arm at `4_route.tcl:~296` matches only the
net names and never tests the record class; `SHORT` appears zero times in that
block. `docs/tapeout/36` section 5 predicted exactly this and the guidance was
never landed in the toolkit.

The irony is recorded in the toolkit's own comment above that regex: it explains
that counting violations instead of KINDS is what let four real shorts through —
and the fix for that introduced a class-blind regex that now makes the opposite
error, hard-failing the first build in the project's history to have **zero**
rail-to-rail shorts. The `rf_32k = 1505.60` change worked.

**GATING ACTION, one line, before the fresh run:** require the `SHORT:` class
before counting a record as rail-to-rail, and route different-net `SPACING`
records to a separate named arm — they are real DRC and must not vanish, but they
are 20 nm of margin on a wide-metal rule, not a dead die. Without this the fresh
run hard-fails for the same false positive.

**The real mechanism, and it is a different defect.** `route_special` lays a
top-level M4 tap on the vendor SRAM's own supply pin but WIDER than the pin
(0.200 -> 0.505, 0.350 -> 0.445). Crossing the 0.400 um wide-metal breakpoint
steps required parallel-run spacing from 0.120 to 0.160, while the neighbouring
gap is the vendor's own pin pitch of 0.140 — legal for the pin, 20 nm short for
the widened tap. The over-width IS the defect; at <=0.399 um all three pass with
margin. Five physical sites exist, not three: whether a site is called a "rail
short" depends only on whether `route_special` also drew a top-level copy of the
VSS pin (the other two are labelled "Pin of Cell" and land in a budgeted class).
The class is a week old — byte-identical coordinates in `knobs-live`,
`macro-move` and `full-20260814`.
Untested cheap lever: `EVP_NO_G4_FIX=1` on `probe_pg_build.tcl`, ~3 min, no P&R
licence, never run on this design.

**The PG cluster is TWO families, not one — no single fix closes it:**
  1. Macro-tap family: the 3 false "shorts" + 2 more real sites + ~368 of the 575
     missing vias that sit INSIDE macro footprints (M4->M5 is 475 of 575; ViaGen
     refuses the cut in the vendor's own pin lattice). Root: `split_row -selected`
     plus per-region M5 anchoring, plus the over-width tap.
  2. Island/open family: all 64 PG opens are OUTSIDE every macro, 62 of them in a
     narrow corridor at x ~ 1030-1059 — the channel left of the right-hand macro
     column. 803 of 889 dangling wires are also macro-free, mostly M1/M2/M3.
     This is the class the PG island feed in HEAD was written for, and it DID NOT
     RUN in fp1505.

**CRITICAL PROVENANCE WARNING:** `power_plan.tcl` at HEAD is NOT the file that
built fp1505's grid — 60,858 bytes now versus the 36,789 the log records. HEAD has
since gained the PG island feed (~180 lines, plus an M8 `add_stripes` per island)
and the VDDIO/VSSIO `route_special` (`c7e488f`). Neither ran for fp1505. **Any
re-run produces a different power grid and every number above must be
re-measured.**

## RETRACTED: "575 missing power vias" is a SCOPE CHANGE, not a regression

    build            layer_range      route-gate total
    fp1505           {M1 AP}          575     <- only build ever measured this wide
    full-20260814    {M8 AP}            4
    knobs-live       {M8 AP}            2
    m5off5/6         {M8 AP}          2-3
    macro-move       {M8 AP}            2

Control, from fp1505's own by-pair line: M8->M9 3 + M9->AP 1 = **4** — identical to
the shipping stream's total over the same scope. fp1505 did not regress; it is the
first build to look below M8. The tech pack documents this exact trap at
`tech/tsmc65/tech.tcl:640` (`pg_via_check_layer_bottom`): same database, 2 vs 556.

Also: the gate's by-pair line sums to 569, not 575. `route_power_via_census`
(`4_route.tcl:382`) regexes `Missing N Via(s)` and silently drops
`Missing N Stacked Via(s)`. Reporting bug, no geometry implication.

**Why M4->M5 is 475 of them:** there is no M4 in our power grid at all — the power
plan adds stripes on M5, M8, M9 only. M4 is where the VENDOR puts macro PG pins.
474 of 475 sit within 5 um of a hard-macro bbox against a 41.7% null baseline, and
their x-coordinates match the vendor LEF pin columns to three decimals. The tool
said so 592 times at power-plan time: `IMPPP-610 ... no via was created between
layer M4 & M5, size 0.35 x 0.35`.

## The opens and dangling are BORN AT POWER-PLAN TIME

`work/innovus.log3` line 777693, written 2026-08-17 18:22:34, already reads
**64 (IMPVFC-200)** and **889 (IMPVFC-94)**. The route gate 30 hours later reports
64 and 889. Place, place_opt, CTS, CTS_opt, route, route_opt, filler and diode
insertion changed NOTHING. Only `power_plan.tcl` can move these numbers — which
means they are A/B-able on the licence-free PG probe in minutes, not via a 4.5-hour
route.

  - 34 of the 62 orphan open pieces land on the five doc-42 island sites -> this IS
    the stranded-cell defect, appearing in a route gate for the first time.
  - 28 of 62 sit on a macro edge. Zero are anywhere else.
  - 889 dangling: 882 within 5 um of a macro bbox; M5 366, M2 196, M1 173. Only
    ~180 are in an island x-span, so the island feed cannot be the whole answer.

The "893 vs 889" question is closed: 893 appears nowhere in the tree. The probe
figures are 883 and 1432, measured on a PAD-LESS database the file itself says not
to quote. fp1505's own `place_conn_special.rep` is the exact baseline.

## The island feed: provenance RESOLVED, verdict still NOT measured

The dead session's scratchpad is still alive, and
`md5sum pgfix-wt/.../power_plan.tcl` = `07aa704a...` = `git show bfbccf6:...`
exactly. Diff against HEAD is ONE hunk — the VDDIO/VSSIO block. **So pgfix-A's
reports are valid evidence about current code.** What they contain:
  - the feed ran: 2223 row segments, 220 vertical stripes, 8 islands at risk ->
    feed sets at x=877.000 and x=1049.000 -> islands at risk 8 -> 0
  - `fp_pg_check.rep`: FP-SHORT 0, FP-ISLAND 0 of 18, FP-CORRIDOR 3 warn, PASS
  - `place_pg_audit.rep` is ONE LINE — the header. No numbers.
That is a FLOORPLAN-GEOMETRY pass. The pre-registered prediction — functional
stranded 55 -> 0 — was **never measured**, and there is zero measurement of the
feed's effect on 575/64/889. It also adds M8 sets off the 60 um grid, and M8
already carries 85 IMPPP-531 VIA8 failures.

## R1 IS FREE AND CHANGES THE ECONOMICS OF EVERYTHING ELSE

`ASIC/genus-innovus/scripts/probe_pg_build.tcl:177` hard-codes
`check_power_vias -layer_range {M8 AP}` — the same blindness that made 575 read as
4. Point it at `pg_via_check_layer_bottom` and every option below becomes a
3-minute A/B on the probe instead of a 4.5-hour route. Do this first.
Also fix `route_power_via_census` to count `Stacked Via` lines.

Then, in order: **R2 (primary)** `EVP_NO_G4_FIX=1` — the flag already exists,
targets the measured over-width cause, and the file itself records it UNMEASURED.
**R3** macro route-blockages on M1-M3 to push the row-end riser out one track
(doc 15 H1, never executed). **R4** keep the island feed but A/B it with
`EVP_NO_PG_ISLAND_FEED=1`, both to route, both at `{M1 AP}`.
**DO NOT** re-try `EVP_M5_ABS_START` (stranded 55->305 + a new M1 short), and do
not chase the M5 start offset (`y mod 15` over the 475 sites is flat).

## Phase 2 — LAUNCH GATES

Every one must be green. Any red blocks the run.

- **G1 Synthesis works at HEAD. *** GREEN — was never the blocker I claimed. ***
  Fixed by revert `c94306c` (ancestor of HEAD). The C2 `set_max_delay` block is
  GONE: 0 hits in `constraints.sdc` at HEAD, only two comment mentions elsewhere.
  Proven by run `gate1r` (18 Aug 18:22), whose emitted verdict at syn.log:8124 is
  ` Status    : OK`, with 0 SYN-FAIL lines, no `Total failed commands during
  read_sdc`, and real outputs (gate_power.v 40 MB, syn.sdc 16.7 MB). Lane D
  verified gate1r's synthesis inputs are byte-identical to HEAD's — same SDC md5,
  same flist sha256, empty diff on the gate script — so a fresh `make syn` is
  expected to reach OK.
  CAUTION WHEN RE-CHECKING THIS: the flow echoes its own Tcl into the log, so
  `grep " Status    :"` matches `puts` statements in the script source. Only the
  line with no `puts` prefix is the emitted verdict. I mis-confirmed this once.

- **G1b Do NOT re-open C2 for this run.** Its own acceptance criteria need a first
  run to NAME ~200 endpoints before the exceptions for them can be written, so
  folding it in re-creates the blocker. What is needed instead is a RATIFIED
  timing-intent line, because the status quo is defensible only as one specific
  claim — see Decisions.
- **G2 Tree is clean and pushed.** The last run recorded `git_dirty yes` and is
  therefore unreproducible. `git status --porcelain` empty; HEAD == live remote
  by `git ls-remote`, not the tracking ref. Submodule pins recorded, not drifted
  — currently tidelink is checked out 1 ahead of its pin.
- **G3 Floorplan work landed and committed** (Lane 2 complete).
- **G4 PG work landed, screened, and REDUCED TO A VERDICT** (Lane 1 complete).
- **G5 Metal fill — ALREADY DECIDED AND ENCODED, not an open question.**
  `design.mk:1117` sets `METAL_FILL_OWNER ?= foundry`, and `design.mk:1096`
  states "ROUTE_METAL_FILL stays 0 and that is the CORRECT setting rather than a
  gap". `4b_pnr_route_eval.tcl:134` has `EVR_METAL_FILL 0`. So this flow inserts
  NO dummy metal, by design.
  What remains is NOT the knob but the HANDOFF: declaring an owner does not
  remove ~38,000 density violations, it reassigns them. Confirm the fill party
  really is doing it, and that the declaration is backed by something. Also note
  a consequence: because we run no fill pass, any "fill keepout margin" fix is
  NOT a knob we can turn — it would have to be fill-blockage geometry we place in
  the floorplan and ship in the stream, and the downstream pass would have to
  honour it. Establish which before treating such a fix as cheap.
- **G6 Gates proven able to fail.** Lane E audited all of them. Six concrete
  repairs, in priority order:
  1. **The local vendor gate has NEVER run its verbatim half.** The root
     `Makefile` has ZERO `include` lines and never sets `TSMC_65_HOME` (only
     `ASIC/common.mk` does), so `make check` and the nightly always take the
     skip-and-exit-0 path. Route `vendor-check` through `ASIC/common.mk` or
     through `vendor_guard_report.sh`.
  2. **`make -C ASIC/genus-innovus lvs-preflight` is a standing FALSE GREEN.**
     `lvs_project.mk:83` pins `LVS_RUN ?= 20260810T065131Z_honest-full-pnr2` — an
     8-day-old artefact. It never looks at the current design. The eth-chiplet
     entry point is the correct one; its FAIL is a true statement about
     `build/default`. Repin `ci/signoff.yaml:1490` and `ci-pipeline.conf:183-188`
     to the new tag, or retire the genus-innovus target.
  3. **`gls-netlist` has a `check:` but no `check_proof`,** and its glob matches
     EVERY build tag — so a new run whose GLS never ran still passes on fp1505's
     old verdict. Pin the glob to the run tag.
  4. **`erc`, `bnd`, `logo` have never produced real tool output** — no
     `erc_run`/`bnd_run`/`drc_logo_run` exists anywhere. Their green `prove` is
     100% hand-written fixture. Read the first real log against the fixture by
     hand before trusting a green.
  5. `ROUTE_MIN_GDS_MB = 1` against a 312 MB stream cannot discriminate. Ratchet
     it toward 300. Confirm nobody launches with `ROUTE_STRICT=0` — `make route`
     prints the budget section without gating on it.
  6. `ci-pipeline.conf:198` drives the `metal-fill` stage with `EVR_METAL_FILL=1`,
     the RETIRED knob (zero occurrences in the toolkit). That block gate re-runs
     route with fill still off and would go green having inserted nothing. The
     working knob is `ROUTE_METAL_FILL`.

  GOOD NEWS, measured: all eight `ROUTE_BUDGET_*` are honest absolute zeros, none
  ratcheted to a last-run value. `ROUTE_EXPECT_UNROUTED = 2` is derived from a run
  but compares by EQUALITY, so it catches improvement as well as regression —
  that one is done right.

- **G13 Fixture retag must be ATOMIC with the check repoint. THIS WILL BITE.**
  30+ fixture directories bake a run tag into their PATHS — 20 on `fp1505`
  (`drc`, `erc`, `bnd`, `logo`, `lec-pnr`) and 10+ on `full-20260814` (`lec`,
  `lec-selftest`). `signoff.py`'s sandbox symlinks any build dir not overlaid by
  a fixture straight back into the REAL tree. So if a `check:` is repointed at the
  new tag while the fixtures still say `fp1505`, every case of that stage grades
  the real new directory and `prove` stops discriminating while still printing
  green. **This has already happened once** — `ci/signoff.yaml:1600-1617` records
  it. `git mv` the fixture dirs to the new tag in the SAME commit that repoints
  `check:`, preserving each `.__exclusive__` marker.
- **G7 Predictions registered BEFORE launch.** Write the expected number for
  each route-gate line to a tracked file first. A run that cannot disappoint you
  has not tested anything.
- **G8 One owner, one seat.** No concurrent P&R. Confirm with `ps` immediately
  before launch, not from a status report.
- **G9 The place stage can actually start.** THIS IS THE TOP LAUNCH RISK, ahead
  of anything DRC. `pnr_macro_stripe_census` hard-failed 0-of-21 macros on the
  `pgfix-A` run and, with `PLACE_STRICT=1`, stopped the stage before
  `place_design` ran at all — which is why pgfix-A died after 4m25s with only
  place_* reports and no cts or route. The fix (toolkit `1b2b6fd`, resolve macros
  by exact name rather than a `get_db insts` pattern) IS an ancestor of the
  pinned toolkit at HEAD, but has ZERO run evidence on this design. Exercise it
  before committing a full run to it.
- **G11 Commit on the right branch.** The shared checkout is currently on
  `feat/padring-boundary-scan`, NOT `fix/tag-ram-gwen`. Both point at `ff9b36f`
  today so nothing is wrong yet, but the next commit lands on the feature branch.
  Run `git branch --show-current` before committing. (A prior mis-landing was
  already repaired by a verified fast-forward `git branch -f`; nothing was lost.)
- **G12 The tidelink submodule is not reproducible.** Its worktree is at
  `3620af3` while HEAD records `e6aaa82`, so a fresh clone will NOT reproduce
  gate1r's netlist. Resolve before the run or the provenance is fiction.
- **G10 The build consumes the .io at HEAD, not a scratchpad copy.** `pgfix-A`'s
  `inputs/` and `scripts/` were symlinks into a session scratchpad, so a build
  can silently consume different sources than HEAD. Verify the build's own
  `scripts/` resolves into the repo before launch. If `padring-gds` does not flip
  green on the fresh stream, this is the first thing to check.

---

## Phase 3 — The run

Single owner. Full flow from synthesis, not a checkpoint resume:

    make -C ASIC/eth-chiplet all RUN_TAG=<fresh-tag>

Report at stage boundaries. Do not reuse a `SYN_RUN_TAG` — the point is that
synthesis is current. Do not resume from an existing place/cts database — that is
what made the 00:24 run carry none of the fixes.

## Phase 4 — Verdict and evidence

- Route gate, DRC census, LEC (all three legs — the RTL->`_gate.v` leg has never
  existed and must be built), ROM at the reticle.
- Evidence must be COLLECTABLE: ROM and LEC proof are currently gitignored and
  outside `$ASIC_DIR`, so a bundle collects none of it.
- State plainly what the stream does and does not contain. "Route passed" is not
  "clean".

---

## Standing rules for every lane

1. One owner per file. Announce before editing a shared file.
2. Measure at the level that matters: HEAD for what a clone gets, the submodule
   pin for coherence, `ps` for whether a run is alive. A worktree read is not a
   commit fact.
3. After every commit: `git diff --cached --name-status -- <paths just committed>`.
   If your paths appear, the shared index has primed a revert — repair with
   `git reset -q HEAD -- <paths>`.
4. Never `git add -A`.
5. A green result must be interrogated: what did the check actually run over?
   A zero often means nothing was measured.
6. Report MEASURED separately from INFERRED, with the command for each.

---

# AGENT DIVISION TO CLOSE THE CHIPLET

Six lanes. The allocation is by FILE OWNERSHIP, not by topic, because the failure
this project actually suffers is two agents editing one file — five edited
`power_plan.tcl` in a single day and produced a retracted fix, a collision, and a
screening run nobody reduced to a verdict.

**Each file below has exactly one owner. No exceptions, no "just a comment fix".**

| Lane | Owns (exclusively) | Job | Blocks |
|---|---|---|---|
| **1. PG** | `power_plan.tcl`, `probe_pg_build.tcl` | The only unsolved technical defect. R4 island-feed A/B first, then R3 macro blockages. Pre-register every prediction. | the run's content |
| **2. Gates** | `ci/signoff.yaml`, `ci-pipeline.conf`, `scripts/ci/*`, toolkit gate scripts | Six repairs (below). Nothing else may touch these files. | the run's verdict |
| **3. Evidence** | `package_submission.sh`, evidence `.gitignore` rules, the LEC leg | Make proof collectable; build the RTL->gate LEC leg that has never existed. | submission |
| **4. Timing** | the SDCs, `ASIC/sta/*` | Not a fix lane — a documentation lane. SI, the 60x hold gap, corner-correctness. | nothing |
| **5. Run** | `ASIC/eth-chiplet/build/<newtag>/` | Owns NO source file. Launches once, watches stages, collects. | — |
| **6. Hygiene** | git refs, submodule pins | SERIAL, never parallel. Branch, pins, commits, push. | everyone |

## Lane 1 — Power grid (the critical path)
Two levers remain; both are ~4-minute probe runs on the now-working harness.
  - **R4 first**: `EVP_NO_PG_ISLAND_FEED=1` vs on. The feed is ALREADY COMMITTED and
    will be in the run whether or not anyone measures it — this is the one place
    where not testing means shipping an unmeasured change.
  - **R3 next**: `create_route_blockage -inst <m> -layers {M1 M2 M3} -spacing 0.4`
    before the final `route_special`. Targets the OPENS branch. Doc 15 H1, never run.
  - **REFUTED, do not retry**: `EVP_M5_ABS_START` (stranded 55->305, +1 M1 short)
    and `EVP_NO_G4_FIX` (opens 60->283, dangling 761->1185, null test flat at 22).
  - Judge on the RELATIVE change against a same-session baseline. The probe is a
    pre-placement DB: it reproduced 415 against the route's 475, so it is valid for
    A/B and is NOT a predictor of absolute route counts.

## Lane 2 — Gate integrity (six repairs, all measured)
  1. `make check` has NEVER run the vendor scan's verbatim half — the root Makefile
     has zero `include` lines so `TSMC_65_HOME` is always unset and the script exits 0
     on the skip path. Route through `ASIC/common.mk` or `vendor_guard_report.sh`.
  2. `make -C ASIC/genus-innovus lvs-preflight` is a standing FALSE GREEN, pinned to
     `LVS_RUN ?= 20260810T065131Z_honest-full-pnr2`. Repin or retire; repin
     `ci/signoff.yaml:1490` and `ci-pipeline.conf:183-188` to the new tag.
  3. `gls-netlist` has a `check:` but no `check_proof`, and its glob matches every
     build tag — a run whose GLS never ran passes on fp1505's old verdict.
  4. `erc`, `bnd`, `logo` have never produced real tool output. First real run is the
     validation; read the log against the fixture by hand.
  5. `ROUTE_MIN_GDS_MB = 1` against a 312 MB stream. Ratchet toward 300.
  6. `ci-pipeline.conf:198` drives metal-fill with the RETIRED `EVR_METAL_FILL`; the
     working knob is `ROUTE_METAL_FILL`. That block gate currently cannot fail.
  ALSO: the route-gate class guard is landed but UNCOMMITTED — see Hygiene.

## Lane 6 — Hygiene, and why it is serial
  - The shared checkout is on `feat/padring-boundary-scan`, HEAD `a1e4758`, **9 ahead
    of the remote**. Anyone committing now lands on the feature branch.
  - `ASIC/asic-toolkit` is dirty with FOUR sessions' work mixed together
    (`4_route.tcl` mine, plus `gen_netlist_tb.py`, `mk/drc.mk`, `mk/help.mk`,
    `flow/power/`). Untangle before anything is pinned.
  - tidelink is 1 commit ahead of its pin; the divider CDC fix does not reach a clone.
  - Never `git add -A`. After every commit:
    `git diff --cached --name-status -- <paths just committed>`.

## Standing protocol, learned the hard way tonight
  1. One owner per file. Announce before touching a shared one.
  2. Pre-register predictions AND a kill criterion before any run. Tonight's A/B
     looked like a win (check_drc 69->60) and was a refutation.
  3. Measure at the level that matters: HEAD for what a clone gets, the submodule
     pin for coherence, `ps` for whether a run is alive. A worktree read is not a
     commit fact; `rc=0` is not "it ran".
  4. Beware the log echo: this flow prints its own Tcl, so `grep " Status :"`
     matches `puts` statements. Only the un-prefixed line is the verdict.
  5. Status decays in minutes. Re-measure; never relay.
