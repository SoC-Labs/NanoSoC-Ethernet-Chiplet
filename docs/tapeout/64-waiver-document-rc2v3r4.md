# Waiver document — nanoSoC Ethernet Chiplet, submission candidate rc2v3r4

    status      DRAFT. PARTIALLY SIGNABLE — see §0 and §9. Not signable whole.
    project     TMWB45_10042, imec mini@sic via Europractice
    submission  1 September 2026
    node        TSMC 65 nm LOGIC-MS-RF G-LP-ULP, 9M_6X1Z1U, wire bond, 1P2V/2P5V
    die         1600 x 2000 um, 3.200 sqmm

    stream      ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260827_rc2v3r4.gds
                ** NOT YET COPIED THERE. ** As of this document the bytes are at
                ASIC/eth-chiplet/build/rc2-20260827/outputs/nanosoc_eth_chiplet_pads_rc2v3r4_logo.gds
    md5         6d64126c80b86497c015774cb71c3bb4
    sha256      69a8d1ef9d0dcfe7a725b8cfa060aade6a02c4abbd6db34fe637dcfdbabe2d17
    size        302,840,564 bytes
    topcell     nanosoc_eth_chiplet_pads

    predecessor _DRYRUN_20260826_rc1v3r4, md5 acd2b93e1ac7ac2c672f236d50b3444c

    full record ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260827_rc2v3r4.md

---

## 0. What this document is, and the one way it differs from rc1's

rc1's waiver (`docs/tapeout/60-waiver-document-rc1v3r4.md`) had a foundry-side
basis: imec CheckAll+ 7.02 ran on 26 Aug 2026 17u29 against a merged database
built from rc1's exact bytes, and imec's report records rc1's md5 verbatim.
Every finding in that document is a position on a number imec actually produced.

**This document has no such basis.**  The most recent imec archive on this site
is that same 26 Aug run on rc1
(`ASIC/imec_results/Archive_nanosoc_eth_chiplet_pads_DRYRUN_20260826_rc1v3r4_merged_dummyWithSealRing_26Aug26_17u29/`).
No imec run has seen rc2's bytes.

So this document does two separate things and keeps them separate:

  * **§1–§5** carry rc1's imec findings forward, each with an explicit statement
    of **why it should transfer to rc2's bytes**, backed where possible by a
    measurement on rc2's own stream.  These are positions we are asking imec to
    accept *when they run*, not positions on results we hold.
  * **§6–§9** state what we measured ourselves on rc2, including three things
    rc1's waiver did not cover at all: a rail run, an LVS limitation that
    invalidates a previous line of argument, and an unanalysed IO ring.

A reviewer should be able to check every sentence against a named file.  Where a
figure was carried rather than re-derived, it says so.  Where rc1's waiver is
**wrong**, it is corrected here rather than repeated — three corrections, in
§1, §6 and §8.

---

## 1. Findings inside vendor IP we do not author

From imec's own final report on rc1
(`design/reports/Final_Report_..._26Aug26_17u29.rpt`), main DRC section, deck
`_CLN65S_<stack>.<rev>_`, `#DEFINE LP`:

| rule | count `N (M)` | resident cell | what the rule tests |
|---|---:|---|---|
| `ESD.23g` | 468 (5616) | `SBC331_POSTVDD2POC_G` | poly-to-contact space, source side |
| `ESD.22g` | 28 (1344) | `SBC331_POSTP` | RPO width, drain side, PMOS |
| `ESD.21g` | 2 (144) | `SBC331_MOS_ESDN01_VDD2_RPO_095` | RPO width, drain side, NMOS |
| `RM.WARN.2` | 100 (600) | `SBC331_RES_04X22D11X47` | contact overlap on resistor head |
| `RM.WARN.2` | 14 (168) | `SBC331_POSTVDD2POC_G` | as above |
| `DRM.R.1` | 1 (1) | `nanosoc_eth_chiplet_pads_dummy_WithSealRing` | *a reminder to read the DRM* |

`N` is hierarchical, `M` is placement-expanded; imec's own
`How_to_read_the_final_report` defines the format and the 1000 cap applies to
`N` only.

    ** CORRECTION TO rc1's WAIVER. **  It stated "five rulechecks, 612 results"
    and "four of the five, totalling 611 results".  Both are one short.  The
    main deck reports FIVE rulechecks and 613 results
    (114 + 2 + 28 + 468 + 1); 612 of those sit in the four SBC331_* cells and
    ONE is the DRM.R.1 reminder in the topcell.  imec's own BY CELL section
    sums the same way: 2 + 482 + 28 + 100 + 1 = 613.

**Measured, not assumed.**  imec's by-cell statistics attribute every one of the
612 to a named `SBC331_*` cell.  **Zero main-DRC results are attributed to our
top cell** other than the `DRM.R.1` reminder.

**Why it transfers to rc2.**  This geometry arrives through imec's own library
replacement (`tphn65lpgv2od3_sl.gds`, `tcbn65lp.gds`, `tpbn65v.gds`, named in
the report).  rc2 changed 292 standard cells inside the core; it changed no pad,
no ESD cell and no IO instance.  Independent check on our own stream: the
foundry DRC deck executes the same 1,926 rulechecks on rc1's and rc2's
submission streams and **zero of them differ** — see §6.

**Ask:** accept as vendor-IP-resident, consistent with the library set imec
substitutes at merge.  `DRM.R.1` accepted as informational; the rule's own text
is *"a warning message to remind the users to check the related DRMs."*

---

## 2. `IM.FLOAT.AP` — 91 results on rc1. It is the chip logo.

Rule text: *"IMEC WARNING: No net connected between AP and top metal. Possibly
it's a logo."*  It is a logo.

**Measured on rc1's stream, with a control** (carried from rc1's waiver): all 91
error polygons parsed out of imec's RVE file, all 91 inside the logo cell bbox
(x 320.0–1047.8, y 859.9–1180.1 in imec's enlarged 1640x2040 frame; that is our
(300.0,839.9)–(1027.8,1160.1) shifted by the 20 um seal-ring band).  Zero
outside.  The pinfix control gave 85 of 85 inside.

**The artwork is unchanged in rc2, measured on both shipped streams.**  A
structure walk over the GDS records of each submission stream returns, for both:

    structure `Logo`, 28 boundaries, ALL on the AP top-metal artwork layer, nothing else
    cell-local bbox  (-363.875,-160.125) - (363.875,160.125)   727.75 x 320.25
    one SREF in nanosoc_eth_chiplet_pads at (663.875, 1000.000)
    => absolute bbox (300.000, 839.875) - (1027.750, 1160.125)

Source artwork `ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds`,
md5 `fbc370caa2f6ac252cc12cd96f7c81cc`, worktree and HEAD identical (committed at
`62a0a5f`).

**But the COUNT may move, and here is the evidence bearing on that.**  The rule
fires on AP with no connection to top metal, so the count depends on how much M9
sits beneath the artwork.  rc2 is a re-routed database.  What we can say:

    Of 158 per-window density files written by the foundry DRC deck on each of
    the two submission streams, NINE differ - M1.DN.1 (19 rows of 780),
    M2.DN.1 (23 of 837), M3.DN.1 (29 of 864), M3.DN.4 (1 of 8), M4.DN.1 (8 of
    957), M5.DN.1 (17 of 1227), M6.DN.1 (52 of 1972), M7.DN.1 (16 of 2162),
    M8.DN.1 (2 of 1861).
    M9.DN.1, M9.DN.2 and AP.DN.1 differ in ZERO rows.

**Read that with its limit.**  A density file records an area fraction per
window; a small M9 change can round to the same printed value.  So this is
evidence that M9 and AP geometry is unchanged *at density-window resolution*,
not proof that no M9 polygon moved.  Our position is that `IM.FLOAT.AP` should
read 91 again and that any change is an interaction between fixed artwork and
routing, not new floating metal — but the count is imec's to produce and we are
not predicting it.

**One thing about the artwork imec should know.**  Our own geometry lint
(`python3 ASIC/logos/logo_gds_lint.py ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds`)
reports:

    polygons=28  offgrid_vertices=0  nonsimple_polygons=5  angled_edges=0

Off-grid vertices are **0** — the two that once produced `G.1:APi` results were
repaired and the repair is committed.  The five self-overlapping outlines are
real: same-direction collinear overlaps on polygons 2, 3, 10, 11 and 12, worst
26,000 nm.  Calibre prints these as `Non-simple boundary ... in cell Logo on
layer 74 datatype 0` **runtime warnings**, not as rulecheck results, which is why
no DRC count moves.  We are flagging them anyway, because how a self-overlapping
outline resolves is tool-dependent and the importer at the foundry is not our
Calibre.

**Ask:** accept as intentional unconnected AP artwork.  If your importer objects
to the five non-simple boundaries, tell us — we would rather fix the artwork than
discover it at mask.

---

## 3. `IM.LOGO.R.1:WARN` — 1 result. Deliberate, and the rule says it is optional.

Rule text: *"Missing Logo layer. Make sure chip has visible logo top metal or AP.
Logo recognition layer is not a must have."*

A visible AP logo is present — it is what generates §2.  The logo *recognition*
the logo recognition layer is deliberately omitted.  We are not re-adding it: on a
placed-and-routed die it has no legal placement, and restoring the marker takes
two capped rulechecks back over 25,000 results with no legal position available.

**Transfers unchanged:** the artwork and the `make logo` invocation are
byte-identical between rc1 and rc2 (§2).

**Ask:** accept.  The rule declares itself non-mandatory.

---

## 4. `IM.POLYIMIDE.1` — 82 results, one per bond pad. Conditional on bumping.

Rule text: *"Polyimide not found on chip core passivation openings. **If bumping
is required** ... polyimide may be a must have."*

This part is **wire bond, no bumping**, as declared in the BEOL option and
confirmed by imec's own run configuration: `bnd BEOL_option Wirebond`,
`custom_drc BEOL_option Wirebond`, `bump_drc BEOL_option Wirebond`.  The rule's
precondition does not hold.

**Transfers unchanged:** rc2 changed no pad and no passivation opening.  The pad
ring instance list is identical — the rail run's out-of-scope set, which is
exactly the IO ring, is **byte-identical** between rc1 and rc2
(md5 `c6e3a8a2fc097345cc47deaf08bf5949`, 493 names, §9.2).

**Ask:** accept as not applicable to a wire-bond part.

---

## 5. Seal-ring-side findings — imec's geometry, not ours

`PM.W.1` = 893 (971) and `AP.S.4` = 46 (46) on rc1.  Both arise from the seal
ring and polyimide imec adds after we ship, and neither is actionable by us.

Our reasoning, so it can be checked rather than taken (measured on rc1's stream,
carried unchanged — rc2 changed no die-edge geometry):

- **The `PM.W.1` results sit in the 20 um perimeter band imec adds at merge**,
  measured by parsing every error polygon out of imec's own RVE file.  All 893
  are within 30 um of the merged-die edge.

      ** OUR TWO EXISTING RECORDS DISAGREE ON WHICH FIGURE IS 884, AND THIS
      MUST BE RE-DERIVED BEFORE SIGNATURE. **
      docs/tapeout/59-imec-round-trip-2026-08-27.md §2 says 884 of 893 lie
      WHOLLY INSIDE the band and that every result bbox has one dimension of
      exactly 20.000 um.
      docs/tapeout/60-waiver-document-rc1v3r4.md §3 says 893 of 893 lie wholly
      inside the band and that 884 of them have the 20.000 um dimension.
      Both cannot be right.  Neither was re-parsed for this document.  The
      argument below does not depend on which is correct -- 884 or 893, the
      population is the band -- but the sentence sent to imec should be the
      measured one, so re-run the parse against the 26 Aug RVE file and quote
      the result.
- **26 of them are in `CORNER_B`**, a cell that does not exist in our GDS and
  that we never instantiate.  imec's own by-cell table attributes them there:
  `CELL CORNER_B ... TOTAL Result Count = 26 (104)`.  The other 867 are
  attributed to `nanosoc_eth_chiplet_pads_dummy_WithSealRing`, imec's wrapper.
- The rule's own seal-ring exclusion is derived from holes in the CB layer.  Our
  CB openings are simple octagons with no holes, so that exclusion evaluates
  empty and the rule fires across the ring itself.
- **`PM.W.1` has read 889 / 919 / 903 / 893 / 893 / 893 across six runs on six
  materially different streams**, including one that carried no CB at all.  A
  count that barely moves across six different designs is not measuring our
  design.
- **All 46 `AP.S.4` results sit at exactly 20.000 um from the merged-die edge**
  (min and max both 20.000) — the die/seal-ring interface, i.e. our original die
  boundary inside imec's enlarged frame.  The AP side comes from the pad masters
  imec substitutes at merge; the PM side is imec's seal ring.

**We cannot check any of this locally.**  Our stream contains no PM, CB, CB2 or
UBM geometry at all, so every local result on these rules is a zero produced by
absent layers rather than by compliance.  Our local wire-bond deck also resolves
to a 2009 rule set — a different document from the one imec runs, with a
different `PM.W.1` threshold — so a local run is not evaluating imec's rule at
all.

**Worth watching:** `PM.W.1` at 893 is the closest approach to the 1000 cap in
the whole report (89%).  Nothing is capped, but on the final run it is the number
most likely to become a truncation rather than a count.

**Ask:** written confirmation that these are expected for the seal-ring flow.
Without it, roughly 939 results stand unexplained against our design.

---

## 6. Pad pitch — the checks ran at P80 and our ring is 67 um

`CB.W.1:P80_ST` = 2 (82) and `CB.W.2:P80_ST` = 2 (82), both under
`'#DEFINE PITCH_80_STAGGER'` (the run's own switch line in the `bnd` section;
the report's configuration table reads `bnd Pad_Pitch Pitch_80_STAGGER`).

Measured from imec's own ERC pad table in the 24 August archive: outer row at
x = 56, inner row at x = 158, pads alternating every **67 um** (same-row spacing
134 um).  On the wire-bond deck's own switch definitions — "IO cell (>= 70 um
pitch)" versus "(>= 60 um pitch)" — a 67 um ring selects `PITCH_60_STAGGER`,
which is also the deck's shipped default.

| switch | CB width needs | CB length needs | our 66 x 58 opening |
|---|---|---|---|
| `PITCH_80_STAGGER` (what has run, every time) | 65 | 75 | **both fail** |
| `PITCH_70_STAGGER` | 58 | 66 | passes, zero margin |
| `PITCH_60_STAGGER` (deck-correct) | 53 | 66 | passes, 5 um margin |

    ** CORRECTION OF RECORD, ours not imec's. **  Our 19 August Q7 stated our
    parts are 70 um staggered.  That was wrong.  It is 67 um, and the
    consequence is that the P60 rule family HAS NEVER BEEN RUN AGAINST THIS
    DESIGN.  The four results are not the point; holding no clean result for
    the switch that actually applies is.

**Ask:** re-run the wire-bond checks with `PITCH_60_STAGGER`.  This is the one
item in this document that could still change a number we sign off on.

---

## 7. What rc1's run cleared, and what of it we can claim for rc2

Recorded because a waiver that lists only problems misrepresents the state of the
design.  Every row is imec's result **on rc1's bytes**; the right-hand column is
what we hold for rc2 and is deliberately weaker.

| check | imec, on rc1 | what we hold for rc2 |
|---|---|---|
| **Antenna** | **0 results.** 17-minute run, by-cell block empty. | See §8. A local foundry-deck run bound to rc2's md5 was still executing at 23:25 on 27 Aug. **Not yet a result.** |
| **Padring** | **0 errors, 0 warnings.** All pad orientations correct; bondpads correctly placed on all four sides; 1 power domain, DIGITAL; 0 power-check errors; no PRCUT cells. (`padring/Padring_check.rpt`) | The pad ring is untouched by rc2 — identical 493-name IO instance set, md5-equal (§9.2). Strong transfer, but not a run on these bytes. |
| **Metal density** | **Passes** on the filled die: 158 per-layer density datasets and **no `DN.*` rulecheck reported** at all, with imec's dummy fill applied. | Unfilled, ours: 6,117 failing core windows of 12,770. Declared, not fixed (§8). |
| **`VIA3.R.4:M4`** | **Cleared, foundry-confirmed** — present as 1 on the previous stream, absent on rc1. | Cleared again on rc2, by the same marker-driven edit against a matched control that still shows the violation. Our deck: base 738 → submission 737, that rulecheck 1 → 0, all 1,925 others unmoved. |
| **Main DRC in our own geometry** | **0 results**, `DRM.R.1` excepted. | Same deck, same 1,926 rulechecks, **zero differ from rc1's stream** (§6 of the submission record). |

    ** CORRECTION TO rc1's WAIVER. **  It recorded "161 per-layer density
    datasets".  imec's drc/ folder holds 158 *.density files, which is also
    exactly the number our own deck writes.  Use 158.

### The A/B that made rc1's row meaningful, and why it does not exist for rc2

The 25 and 26 August imec runs used byte-identical configuration — same deck
versions, same switches, same three replacement libraries — so the only
differences between the two result sets were attributable to the streams:
`VIA3.R.4:M4` 1 → 0 and `IM.FLOAT.AP` 85 → 91, **two changes across the entire
report**.

For rc2 we hold the equivalent A/B only on *our* deck: 1,926 rulechecks, zero
differing, with the per-window density files proving the two streams really are
geometrically distinct (§2).  That is a strong result and it is not the same
result.  Our deck does not run `PM.*`, `CB.*`, `IM.*`, `ESD.*g` or `RM.WARN.*` —
those layers are not in our data.

---

## 8. What has NOT been measured on these bytes

Every row here would read as an improvement if it were simply omitted.  None of
it is.

### 8.1 Antenna — in flight, not passed

The router-level `check_process_antenna` on rc2's database reports
`No Violations Found`
(`build/rc2-20260827/eco/reports/nanosoc_eth_chiplet_pads_imp_antenna.rep`).
**That is not the foundry deck** and must not be quoted as one.

rc1's local foundry-deck run `ASIC/genus-innovus/calibre_runs/ant_rc1v3r4_0826`
is bound to rc1's submission GDS by its own `Layout Path(s)` line.  It executed
721 rulechecks and reports 7 non-zero, **all of them `ANTCTL.*.POPULATION`** —
the deck's own population counters, not violations — of which **five are
saturated at the 1000 cap**, so those five are truncation and not counts.  The
honest reading is *714 substantive antenna rulechecks, zero results*.

A run bound to **this** candidate's md5 was launched at 23:12 on 27 Aug into
`ASIC/genus-innovus/calibre_runs/ant_rc2v3r4_0827/{logo,sign}/` and was still
executing at 23:25 with no `.summary` written.  Its `prerun_md5.txt` names
`6d64126c80b86497c015774cb71c3bb4`.

> **SLOT — foundry antenna on rc2.**  Fill from that run's own `.summary`.
> Record: rulechecks executed, non-zero rulechecks, the `Maximum Results/RuleCheck`
> cap, and whether any check saturated.  Do not fill it from rc1's numbers.

### 8.2 Power intent (CLP) — not re-run, and rc1's result was a FAIL

    ** CORRECTION TO rc1's SUBMISSION RECORD. **  It said "check_cpf DOES NOT
    RUN - the Conformal Low Power licence is not available on this site."  That
    is false.  Conformal 22.10-s200 with -LPGXL ran on 26 Aug at 12:03.

Measured, on rc1's `gate_power.v` (md5 `4f0043247e0088ccd651f1f1dd899502`),
`build/gdsrun-20260826-rc1-clp/{cpf,upf}/clp_manifest.txt`:

    CPF leg   intent_elaborated yes, checks_ran yes
              commit step: ERRORS 23, first "Domain 'PD_TOP' not found"
              21 macro models with no domain
              rules_reported 15, rules_error 3, violations_error 138
                  PDM1 72, ISO7 64, PG_CON1 2
    UPF leg   intent_elaborated NO, checks_ran NO
              violations_error 4, both CPF_HIER_MAP classes
              i.e. the smaller count is an elaboration failure, not a cleaner
              result

**Nothing CLP ran on rc2.**  The input netlist md5 is unchanged, so the 138 are
as true of rc2 as of rc1.  Not re-running a failing check does not clear it.
`..._gate1.cpf` and `..._gate2.upf` ship UNVERIFIED.

### 8.3 Logic equivalence — one of three legs does not cover rc2

    syn   RTL -> gate.v          5,433 / 5,433 equivalent, 0 non-equivalent,
                                 0 abort.  Tool exit 40 with flags
                                 unmapped-or-extra-PO and abort-any-compare;
                                 96 unmapped extra golden points, all
                                 .../u_enum/root_port_cursor_r_reg[*][*].
    gate  gate.v -> gate_power.v 61,599 / 61,599 equivalent, exit 0.
    pnr   gate_power.v -> pnr.v  61,599 / 61,599 equivalent, exit 0 -- but the
                                 revised netlist is md5
                                 fd6284fcda9ac0a079a3a6d30f1142ee, which is
                                 rc1's pnr.v.  rc2's is
                                 d1ab844dd7e8897ccfd07acd4186df30.

    build/lec{,gate,pnr}-rc1-0826/reports/lec/*/verdict.txt

**No LEC covers rc2's P&R netlist** — not the 292 inserted cells, not the one
deleted repeater, not the 26 resized cells, and not the buffer inserted inside
the fenced clock divider (§8.5).

### 8.4 The OCV derate is a declared guess, and rc2 does not answer it

Both rc1's and rc2's signoff timing were taken at a flat derate of
**data 0.95/1.05, clock 0.97/1.03**, confirmed in each run's own
`report_timing_derate` and recorded in each run's `sta_manifest.txt`.

The flow's own tracked source calls it a guess, at
`ASIC/genus-innovus/scripts/3b_pnr_cts_eval.tcl:127`:

    # THE VALUES BELOW ARE A GUESS: the 65 nm norm, not a characterisation of
    # this part.

and the toolkit's tech pack refuses to register any derate at all, for the same
reason (`ASIC/asic-toolkit/tech/tsmc65/tech.tcl:449`, "`# --- OCV derate:
deliberately NOT set ---`", "*a number in a pack reads as measured*").  The
0.95/1.05/0.97/1.03 are the hard-coded fallbacks reached when the pack registers
nothing — `flow/innovus/3_cts.tcl:106-109`, `hooks/pre_route.tcl:233-236`,
`ASIC/sta/run_signoff_sta.tcl:212-215`.

**There is no characterised alternative anywhere on this site.**  Re-measured for
this document, read-only:

    865 .lib files under the 65 nm PDK searched for ocv_sigma_cell_rise,
    ocv_sigma_cell_fall, ocv_std_dev, ocv_table_template, early_late,
    default_ocv_derate_factor, ocv_derate_factors        -> ZERO hits
    name search for *aocv* *socv* *lvf* under the same tree -> ZERO
    135 .lib files across the ARM 65 nm physical-IP tree and the precompiled
    memory tree                                          -> ZERO hits, ZERO names
    the 14 timing_power_noise packages ship NLDM, ECSM and CCS.  No AOCV,
    SOCV or LVF sibling anywhere.

    CONTRASTIVE CONTROL: the same site DOES ship advanced-OCV data for 28 nm --
    543 files, 536 of them .aocv3, in a directory literally named aocv/.
    So this is a node-era gap, not an installation error.

**What changed with rc2, and what did not.**  rc1 failed the guess (setup
-0.049, hold -0.053); rc2 meets it (setup +0.022, hold 0.000) over an identical
analysis population — 2,377 untested checks on both runs, so endpoints were fixed
and not excluded.  That is a real improvement and it is on the conservative side.
It is **not** an answer.  Setup margin is +0.022 ns on a design whose critical
path is around 82 logic levels; widen the late data derate from 1.05 to 1.06 and
that margin is gone several times over.  Hold margin is 0.000.  The result is
correct **at** the guess and is not robust **to** it, and those are different
statements.

**Ask (to imec / Europractice, repeating §5 of
`docs/tapeout/59-imec-round-trip-2026-08-27.md`):** does TSMC provide
on-chip-variation guidance for this node through the MPW programme —
characterised derate data, a recommended flat figure, or the reference-flow
sign-off guidelines the standard-cell application note points at?  **If it does
not exist for this node, a sentence saying so is just as useful**: it lets us
record the figure we chose as a declared engineering assumption with a stated
basis rather than a number with no provenance.

**Internal action, and it is not imec's:** the derate needs an owner.  Nobody has
ruled on it.  rc2 moved the design to the safe side of an unanswered question;
that is not the same as closing it.

### 8.5 A change inside a deliberately fenced block

One of the eleven cells in rc2's final hold pass lands inside `u_link_clk_div`,
the D2D link-clock divider.  `ASIC/genus-innovus/scripts/protect_link_clk_div.tcl`
fences that hierarchy because its glitchless handover is a property of one exact
boolean — `clk_out = (clk_in & byp_en_r) | (clkdiv_r & div_en_r)`,
`tidelink/src/rtl/tidelink_link_clk_div.sv:203` — which synthesis or P&R
re-association would destroy silently.  The fence was cleared for that one
session, with an abort if the clear did not take, and no tracked file was edited.

**Measured: the module's netlist differs from rc1's by exactly three lines** — a
new wire, one `CKBD8`, and `byp_en_r_reg`'s `.D` re-pointed at it.  The AND-OR
is untouched; `g131` and `g142` remain `size_ok` and were never resized.

**Not established:** no functional re-verification of the divider was run on
rc2's netlist, and the LEC pnr leg does not cover it (§8.3).  This is recorded as
a change made inside a protected block, not as a change proven harmless.

### 8.6 Other rows carried unchanged

    PO.R.8 post-merge     691 on our deck, as on every stream in this lineage:
                          the stream carries LEF abstracts, not real
                          standard-cell polysilicon.  Only a foundry run closes
                          it, and imec's 24-Aug run on the rzG lineage found
                          14 REAL post-merge floating gates -- a separate
                          finding, still open, NOT covered by this row.
    metal density         METAL_FILL is 0, METAL_FILL_OWNER is foundry.  6,117
                          failing core windows of 12,770 are MEASURED and
                          DECLARED, not fixed.  Re-derived on rc2's own
                          submission rundir for this document, not carried.
    BND / seal ring       not in the design data; our local BND deck runs over
                          empty layers, so a local run reports a zero produced
                          by absent layers.
    GDS layout identity   no geometric arbiter (KLayout XOR) was run, and
                          deliberately: rc2 is a single-lineage ECO chain with
                          no sibling it is meant to be identical to.
    evidence bundle       NOT COLLECTED.  ASIC/eth-chiplet/build/evidence/ does
                          not exist.  The spec ASIC/eth-chiplet/evidence/
                          rc2-20260827.json is written but untracked.

---

## 9. LVS, power connectivity, and the check that does not exist

**This section replaces §5 of rc1's waiver and reverses part of it.**  rc1's
waiver said: *"LVS is ours and we hold it: the `lvs-missing-connection` gate
PASSES on this candidate."*  Two things are now known that make that sentence
unsafe to repeat.

### 9.1 The gate flipped on rc2, and the flip is a matcher artefact

    committed gate (HEAD)   rc1  PASS, required 0, got 0
                            rc2  FAIL, required 0, got 2

Both rows are one net — DISC 43, report lines 2429 and 2431 —
`Xu_.../Xu_network_core/XFE_DBTC206_network_core_dbgahb_slvaddr_2/VSS`.

The mechanism, measured:

  * The cell is **pre-existing**, not an ECO cell.  Its declaration is
    byte-identical in both P&R netlists and both carry exactly 284 `FE_DBTC*`
    instances.  It **did not move** — both reports place it at
    (1100.800, 1184.035) and match it as an instance, `CKND1 <-> CKND1`.
  * `CKND1` has **no VSS signal pin**, so Calibre creates a per-instance implicit
    `<inst>/VSS` net.  The source CDL's first line reads exactly
    `.GLOBAL VDD VDDIO VSSIO` — **VSS is absent**, deliberately
    (`ASIC/eth-chiplet/design.mk:366-383`: `.GLOBAL VSS` would short the ROM
    power gate).  Result: **18,321** one-pin orphan `<inst>/VSS` source nets in
    rc2, 18,031 in rc1, +290 for the 292 inserted cells.
  * Calibre pairs leftovers arbitrarily and says so: both reports carry the
    identical line `1036 nets and 46 instances were matched arbitrarily.`
  * **rc1 does not carry the same row.**  In rc1 the same two objects appear as
    two *separate unpaired* entries (`Net 25058 ** no similar net **` and
    `** no similar net ** Xu_.../XFE_DBTC206_..._2/VSS`).  In rc2 the matcher
    paired them, and a pairing emits missing-connection rows on both sides.  One
    net of eighteen thousand changed bucket.  The net did not change; the
    tie-break did.
  * **Discriminator.**  A pairing whose two sides share zero connections is a
    tie-break, not a correspondence.  Across the 20 LVS reports on this site and
    their **1,385** paired discrepancies, exactly one object has zero shared
    connections and it is this one.  rzG's genuine below-top defect
    (DISC 62, `RAMCLD0RDATA[123]`) has **shared = 1** and is not set aside.

    A NUMBER TO CORRECT.  The patch prose and an earlier write-up give "1,024
    paired discrepancies".  That could not be reproduced; the census re-run for
    this document counts 1,385 over the same 20 reports.  The conclusion is
    unaffected.  Quote 1,385, or re-derive it.

**Status: a candidate fix exists and is NOT committed.**  The gate of record
(HEAD) still FAILS rc2.  A modified `scripts/ci/lvs_missing_connection.py` in the
working tree returns PASS with the reason
`SET ASIDE, VACUOUS PAIRING DISC 43 ... share 0 of 1/1 connections`; it is
unstaged, its selftest fixtures under `ci/fixtures/lvs-missing-connection/` are
untracked, and its file hash changed twice while this document was being written.
**A gate that passes only in an uncommitted working-tree edit is a candidate fix,
not a disposition.**

### 9.2 THE LIMITATION THAT MUST BE IN THIS WAIVER

**This LVS cannot detect a stranded PG pin at all, and for that failure mode its
sign is inverted.**

Proven with positive controls.  Two deliberately-stranded databases exist, built
by cutting the VSS rail under this exact cell (`build/lvsadv-20260827/fals/` and
`fals5/`; `BREAK_PG5.txt` records `removed special_wire VSS 1102.52 1176.625
1102.87 1214.85`, `rail cut: kept [205.0..1099.4] and [1103.8..1395.0]`).
Running the committed gate on their LVS reports:

    fals        lvs-missing-connection: PASS   required 0, got 0
    fals5       lvs-missing-connection: PASS   required 0, got 0
    rc2 intact  lvs-missing-connection: FAIL   required 0, got 2

On the broken stream the cell **vanishes from the report entirely** — zero
occurrences of its name in fals5's report, against six in rc2's.  Independent
confirmation the geometry really was cut: Innovus on the broken database reports
`1 Problem(s) (IMPVFC-96): Terminal(s) are not connected`, which rc2 does not.

    THEREFORE: LVS MUST NOT BE CITED AS EVIDENCE THAT POWER CONNECTIVITY IS
    SOUND ON THIS DESIGN.  It is not merely silent on the failure mode -- it
    reports the healthy case and passes the broken one.

A claim that has circulated and should be dropped: a KLayout pin-coverage probe
is sometimes quoted as showing the pin "100% covered by a 1248 um M1 polygon on
the shipping GDS, and 0.600 um uncovered on a stranded control".  That
measurement was never made in that direction.  The script
(`build/lvsadv-20260827/gds_pin_cover.py`) was invoked exactly once, on the
**broken** stream, and returned *fully covered, 0.000000 um² uncovered* — because
the cell's own pin stub survives a rail cut.  The "0.600 um" is the containing
polygon's width; "1248" is a Calibre progress counter.  There is **no run of that
probe on the shipping GDS**.

### 9.3 What DOES answer power connectivity: the rail run

A Voltus static rail analysis on `db_eco_final` — the database the submission
stream was written from — is the check LVS cannot be.

    run     ASIC/eth-chiplet/build/rail-rc2-20260827/railwork/rc2-20260827/
    method  static, era=false, no stream file, techonly PGV, hd accuracy,
            125 C, 10 voltage sources against 10 core supply pads
            (6 x PVDD1DGZ_G, 4 x PVSS1DGZ_G)

    0 FUNCTIONAL instances have no path to a supply rail      (gate limit 0)
    365,740 of 366,233 instances analysed = 99.8654%          (floor 99.00%)
    solver current 50.1435 mA vs demand 50.2674 mA, ratio 0.9975

**18 instances are genuinely disconnected and none is a logic cell** — six
`DCAP4` endcaps and twelve `FILL4/8/16/32`, in one contiguous island:
x ∈ {1042.0, 1042.8, 1049.2, 1052.4, 1054.0, 1054.8}, y ∈ {277.0, 278.8, 280.6},
i.e. 12.8 x 5.4 um across three standard rows; 6 floating and 12 single-rail-open.
**rc1's island is at exactly the same 18 coordinates with the same master at each
position**, verified by joining rc1's disconnected list against rc1's own
`inst_xy.txt`.  The six endcap instance *names* are identical; the twelve filler
names differ because refill renumbers fillers.  It predates the ECO.

**The LVS-flagged cell, fifth independent measurement:** effective resistance
**10.918 ohms** (VDD 55.75%, VSS 44.25%) against a die median of **11.3550** over
365,732 finite entries and a healthy maximum of **71.5580**; disconnected
instances read 2.1475e+09 or 4.295e+09.  It is absent from both
`pg_integrity.rpt` disconnected tables.  It is slightly better connected than the
median instance on the die, on both rails, and it draws real current.  It is not
stranded.

### 9.4 The rail run's two FAIL_HARD results, stated as failures

`verdict.json` reads `status FAIL_HARD`, 29 checks, three not OK.  **Neither
failing check is connectivity, and both are identical to rc1.**

    check                    rc2        rc1        budget     verdict
    em.current_density        49         49          0        FAIL_HARD
    budget.eff_mean_pct    1.1491%    1.1486%      1.0%       FAIL (budget)
    coverage.demand_vs_flow_power                             FAIL (advisory)

    passing, for context:
    eff_worst_pct (co-located) 1.3324%  (rc1 1.3315%)  budget 3.0%   OK
    eff_p99_pct                1.3046%  (rc1 1.3046%)  budget 2.0%   OK
    vdd_droop_worst            0.5537%  = rc1                        OK
    vss_rise_worst             0.7806%  = rc1                        OK
    pad current spread, worst  12.62% (VDD)           limit 40%      OK

**The 49 EM elements are all outside the core.**  Parsed from
`Reports/VSS/VSS.rj.avg.rpt` (rows with I/Ilimit > 1.0, worst 1.43281):

    by layer     metal1 28, metal2 21
    by y         134.22 (14 rows), 1822.92 / 1823.15 (35 rows)
    core box     205.0,205.0 - 1395.0,1795.0
    INSIDE CORE  0 of 49

    four x-clusters 314.6-330.4, 394.6-410.4, 954.6-970.4, 1354.6-1370.4
    the four VSS pads at x = 322.5, 402.5, 962.5, 1362.5 (VSS_vsrcs.rpt)

Every over-limit element is a metal1/metal2 stub directly under a VSS bond pad.

**How conservative these numbers are — measured.**  The run is static at the
tool's default toggle assumption, 80.68 mW.  The activity-annotated power study
(`build/power-saif-20260827/SUMMARY.txt`, 100% annotation coverage on
209,738/209,738 nets, with the default arm reproducing `imp_power.rep` to the
last digit) measures the real workload at 7.692 mW (dual-core), 8.342 mW (the
busiest window) and 15.022 mW at twice the clock rate.  So the busiest real
window draws **0.103** of the assumed current, and the double-rate arm **0.186**:
the rail numbers above are conservative by roughly **5.4x to 9.7x**, not
optimistic.  Two caveats — the SAIF study ran on **rc1's** routed database, and
the budgets these two checks fail are the project's own conventions, not foundry
limits.

**These are not waived here.**  They are stated so that "the rail run answered
power connectivity" cannot be read as "the rail run passed".  It did not.

### 9.5 The check that does not exist: the IO ring

**The rail flow does not analyse the IO ring at all.**  `VDDIO` and `VSSIO` are
excluded by name — `coverage.nets_excluded = VDDIO VSSIO`, with the reason
recorded in the run's own `census.txt`: absent from the CPF power intent, so no
domain, no routing to analyse, and including them "returns ~0 mV by
construction".  The 493 instances outside the solve are exactly that ring, and
the name list is **byte-identical** between rc1 and rc2
(md5 `c6e3a8a2fc097345cc47deaf08bf5949`).

    NOTHING IN THIS PROJECT ESTABLISHES THAT ANY IO CELL REACHES A VDDIO OR
    VSSIO PAD.

    - LVS is blind to it and inverted for it (§9.2).
    - The rail run excludes it by name (this section).
    - Innovus check_connectivity -type special reports 51 opens and 727 dangling
      PG wires and is not a reachability check.
    - imec's ERC would answer it, and imec's ERC has never produced a result on
      this design: every archive returns the 13-line bail "No labels found in
      topcell", because that deck runs against imec's wrapper cell which carries
      no labels while ours sit one level down.

**Its absence must not be read as a pass**, and §9.3's "0 functional instances
disconnected" is a statement about the **core** domain only.

**Ask:** run the ERC / pad-short / floating-pad package on this candidate, and
tell us explicitly whether it covers IO-cell-to-IO-pad supply reachability.  This
is the single largest hole in our own verification and we cannot close it from
here.

---

## 10. Scope note: LVS and ERC are not imec DRC checks

LVS is not in scope for the CheckAll+ archive and its absence there is correct,
not a gap.  ERC and pad shorts arrive as a **separate** deliverable.  The
13-line `erc/` bail in the archive — *"No labels found in topcell. At least
power/ground labels are required."* — is an artefact of that deck running against
imec's wrapper cell `nanosoc_eth_chiplet_pads_dummy_WithSealRing`, and it is
expected, not a finding.

**The pad-short package we hold is bound to a stream three revisions behind.**

    held      PadShorts/, dated 24 Aug 2026
    lineage   DRYRUN_20260823_rzG  -- rzG -> pinfix -> rc1 -> rc2

Its findings, for reference only and **not carried into this waiver** because
they do not describe these bytes: 0 floating pads (*"NO FLOATING PAD DETECTED"*);
shorted pads all domain-pure, every pair on one of the four supply buses, which
is by construction for a multi-pad supply; `mnpg` 10 and `mppg` 28, ESD clamp
structures.

---

## 11. Signature

This document is a statement of position on findings in a specific stream.  It is
valid only for md5 `6d64126c80b86497c015774cb71c3bb4`; any re-stream invalidates
it and it must be re-issued.

### What is signable now

**§1, §3, §4, §5 and §6 are complete and signable on their own terms.**  Each is
a position on a rule whose behaviour is determined by geometry rc2 did not
change, each carries the measurement behind it, and each transfers from rc1's
imec run with a stated reason.

**§2 is signable as a position** (the results are the logo, the artwork is
unchanged, measured on both streams) **but not as a count.**  We do not know what
`IM.FLOAT.AP` will read on rc2 and we are not predicting it.

### What is NOT signable, and why

| item | why it cannot be signed | §  |
|---|---|---|
| Foundry antenna on these bytes | The run is executing. There is no result to sign. | 8.1 |
| CLP / power intent | The last result was a **FAIL** (138 errors) and it has not been re-run. A waiver cannot waive a failure by not repeating it. | 8.2 |
| LEC over rc2's netlist | No leg covers the 292 inserted cells, the deleted repeater, or the buffer inside the fenced clock divider. | 8.3, 8.5 |
| OCV derate | The signoff condition is a number nobody owns. rc2 meets it; that is not the same as it being right. | 8.4 |
| LVS below-top missing connection | The gate of record FAILS. The fix is uncommitted and its hash was changing during drafting. | 9.1 |
| Rail `em.current_density` = 49 | FAIL_HARD against a budget of 0. Mitigated (all outside the core box, all under VSS pads, conservative by 5–10x on measured activity) — **mitigated is not waived**. | 9.4 |
| Rail `budget.eff_mean_pct` 1.1491% | FAIL against a 1.0% budget. Same mitigation, same conclusion. | 9.4 |
| IO-ring supply reachability | **No check for it exists anywhere in this project.** Nothing to sign, in either direction. | 9.5 |
| ERC / pad shorts on these bytes | Held package is three streams behind. | 10 |

### The honest summary

rc2 is the first stream on this design where setup and hold both close, over an
identical analysis population, with the endpoints fixed rather than excluded —
and it reaches that without moving a single one of the 1,926 foundry rulechecks
that decide whether it can be built.  Those two facts are measured, controlled
and signable.

Everything else on this page is either a position awaiting imec's run, or a check
that failed and has not been re-run, or a check that does not exist.  Nine rows
in the table above are the second and third kinds.  **This document is issued
with them stated rather than withheld.**

| | |
|---|---|
| Prepared by | _______________________ |
| Date | _______________________ |
| Design authority | _______________________ |
| Date | _______________________ |

Signing this document signs §1–§6 and the §2 position.  It does **not** sign the
table above, and no row in it is closed by signature — only by a measurement or
by a separate, named waiver.
