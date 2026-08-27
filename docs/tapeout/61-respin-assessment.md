# Respin assessment — nanoSoC Ethernet Chiplet, 27 August 2026

    status        ANALYSIS. No tool was run for this document; no build directory
                  was written. Every number is read from a file already on disk
                  and cited to it.
    question      Should we re-run the eth chiplet from RTL before the 1 September
                  submission, and if not, what should we ship?
    candidate     ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260826_rc1v3r4.gds
                  md5 acd2b93e1ac7ac2c672f236d50b3444c
    window        Thu 27 Aug (today) -> Tue 1 Sep. Three working days:
                  Fri 28, Mon 31, Tue 1, plus a weekend usable for compute but
                  not for foundry turnaround or human decisions.

---

## 0. The answer

**Do not respin.** Not because a respin is expensive — it is only about four and a
half hours of tool time — but because there is no residual violation a respin
would reliably fix, one of the two it targets is provably unexciteable in the
shipped netlist, and the other is already closed by a 38-cell ECO that has been
measured in the signoff tool.

The decision that actually matters is narrower, and it has to be made **today**:

| | |
|---|---|
| **(a)** | ship `rc1v3r4` as it stands, with the derate declared |
| **(b)** | ship the hold-ECO stream (`holdeco-20260827` iteration 2) |
| **(b′)** | ship the hold-ECO stream **with the setup ECO folded in** — the option that is not on anyone's list and is strictly better than (b) |
| **(c)** | full respin from RTL |

**Recommended: (b′), gated.** Fold the measured setup ECO onto the hold-ECO
database, close the Calibre and VIA3.R.4 loop, re-stream and re-submit **today or
tomorrow morning**. If a foundry result on the new md5 is not in hand by Monday
31 August, fall back to (a) unconditionally — `rc1v3r4`'s bytes, its foundry
report and its waiver are all on disk and nothing in this plan touches them.

(c) is not viable in the window and would not buy what it is being asked to buy.
(a) is a defensible choice and I say where its case is strongest in §5.4.

**Why today and not Friday.** Two asks against `rc1v3r4` are still open with the
broker — the wire-bond deck ran at the wrong pad pitch, and the ERC / pad-short
package we hold describes a stream two revisions back
(`docs/tapeout/60-waiver-document-rc1v3r4.md` §4 and §5). Both need broker action
and broker action takes calendar days. They should run **once**, on whatever
bytes are final. So the re-stream decision gates the asks, not the other way
round, and the asks cannot wait.

---

## 1. What I verified, and three places the brief is wrong

### 1.1 The foundry result — confirmed, with one qualification

Read from `ASIC/imec_results/Archive_*rc1v3r4*/`:

| claim | verdict | evidence |
|---|---|---|
| bound to our exact bytes | **CONFIRMED** | the report prints `md5sum(.gds*) : acd2b93e1ac7ac2c672f236d50b3444c` verbatim |
| antenna 0 | **CONFIRMED** | the antenna deck's by-cell statistics block is empty; all 207 `ant/*.rep` files contain nothing but the one-line cap header. 17-minute run |
| padring 0 errors / 0 warnings | **CONFIRMED** | `padring/Padring_check.rpt`: `Total number of errors : 0`, `Total number of warnings : 0`, all four sides correct, 1 power domain, no PRCUT cells |
| metal density passing | **CONFIRMED** | 161 per-layer density datasets written and **not one `DN.*` rulecheck reported**. The main DRC report fires exactly five rulechecks and none is a density rule |
| zero main-DRC in our own geometry | **CONFIRMED** | 613 results total. 612 attributed by the report's own by-cell table to four vendor ESD/IO library cells; the remaining 1 is `DRM.R.1`, whose own rule text calls it *"a warning message to remind the users to check the related DRMs"* |
| `VIA3.R.4:M4` cleared | **CONFIRMED** | absent from this report; present as 1 result on the previous stream |

Nothing is saturated: the results cap is 1000 and the largest count is 468.

**The qualification.** "Padring 0 errors, 0 warnings" is true of the *padring
checker*. The **wire-bond deck is not zero** — it reports 943 results
(`PM.W.1` 893, `AP.S.4` 46, `CB.W.1` 2, `CB.W.2` 2). The waiver document
dispositions all of them, correctly in my reading, as seal-ring-side geometry the
broker adds after we ship plus two rules that ran at the wrong pad-pitch switch.
But those dispositions are **asks, not answers**: §3 and §4 of the waiver both
request written confirmation, and neither has come back. Around 939 results
therefore stand unexplained against our design in the only document a reviewer
will read. That is open on option (a) exactly as much as on (b) or (c) — it is not
a reason to respin, but it should not be described as a clean sheet.

### 1.2 The hold ECO — confirmed, and it is better than the brief says

`ASIC/eth-chiplet/build/holdeco-20260827/RESULT_ITER2.txt`, two Tempus
`opt_signoff -hold` passes on the `rc1` routed database:

|  | rc1 | iter1 | iter2 |
|---|---|---|---|
| hold WNS / TNS / FEP | −0.053 / −2.309 / **394** | −0.013 / −0.042 / 12 | **−0.011 / −0.011 / 1** |
| setup WNS / TNS / FEP | −0.049 / −0.137 / 4 | −0.049 / −0.136 / 4 | −0.049 / −0.136 / 4 |

279 ECO cells, **+232 instances (+0.063%)**, **cell area delta exactly 0.000 µm²**
(the rows were already full, so inserted logic displaces its own area of fill),
`check_drc` clean, connectivity counts byte-identical to `rc1`, antenna clean.
Hold TNS falls 99.5%. Setup never moved by a picosecond across two passes.

The only cost the run introduces is **3 max_capacitance endpoints at −0.001 ns**
where `rc1` had none, and it did not grow between passes.

The brief says "279 cells, +0.06% instances" — correct. It says hold went to
"−0.011/−0.011/1" — correct.

### 1.3 The hold endpoint — verified, and the case is far stronger than stated

The brief says the endpoint "CANNOT FIRE" because the divider ratio is tied off.
That is right, and the shipped netlist proves it structurally rather than by
argument. From `ASIC/eth-chiplet/build/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_gate.v`,
the module as synthesis specialised it:

    module tidelink_link_clk_div_RATIO_RESET0(...)
      DFNCND1 div_en_r_reg (.CDN (rst_n), .CPN (clkdiv_r), .D (1'b0), ...)
      CKND1   g132          (.I (div_en_r), .ZN (n_12))
      DFNSND1 byp_en_meta_r_reg (.SDN (rst_n), .CPN (clk_in), .D (n_12), ...)
      DFNSND1 byp_en_r_reg      (.SDN (rst_n), .CPN (clk_in), .D (byp_en_meta_r), ...)

Read that chain: `div_en_r_reg`'s data input is a hard constant and its clear
forces it low, so `div_en_r` is 0 for all time. `n_12` is its inverse, so
constant 1. `byp_en_meta_r_reg` is **set** by reset and its data input is that
constant 1. `byp_en_r_reg` is **set** by reset and its data input is
`byp_en_meta_r`. The net feeding the failing pin is 1 out of reset and can never
change value. **A hold check needs a transition; this one has none available.**

Three independent confirmations that nothing can re-enable the ratio:

* `.link_clk_div_ratio_i (3'd0)` — hard-tied at the chiplet top
  (`tidelink/imp/fpga/eth_chiplet_ip/src/nanosoc_eth_chiplet.sv:960`).
* `parameter bit LINK_RATE_REGS_PRESENT = 1'b0`
  (`tidelink/imp/fpga/eth_chiplet_ip/src/tidelink_top.sv:261`) with **no override
  anywhere in the source tree**, so the software-writable rate bank that could
  otherwise drive the ratio is not built.
* The shipped netlist contains **zero** instances of that bank — the flops that
  would hold a non-zero ratio do not exist, which is why synthesis named the
  module `..._RATIO_RESET0`.

This is stronger than the case-analysis argument in the brief. A case analysis is
an assumption the analysis makes; this is a property of the gates.

**And there is a mechanism fact the brief gets wrong in our favour.** The brief
says the flops "sit on ONE clock net inside a module carrying `set_dont_touch`".
Both halves check out — `set_dont_touch [get_cells .../u_link_clk_div]` is at
`syn.sdc:127091`, one of 83 — but the consequence is sharper than "an ECO cannot
reach it". In **both** the synthesised and the placed-and-routed netlists the two
flops read `.CPN(clk_in)`: the same net, direct from the module's clock port,
with no buffer between them. That is not a clock tree with two branches of
unequal depth. It is **one net with two sinks**, and the 199 ps of divergence is
pure RC along it. See §2.1 for why that closes off the CTS answer entirely.

### 1.4 The setup paths — verified, plus one finding and one correction

Read from `ASIC/sta/work/gdsrun-20260826-rc1/reports/timing_setup_default_analysis_view_setup.rpt`:

| path | endpoint | data path | slack |
|---|---|---:|---:|
| 1 | `...u_adp_control_adp_addr_reg[30]/SI` | 9.442 | **−0.049** |
| 2 | `...u_core_iq_branch_q_reg/D` | 9.539 | −0.044 |
| 3 | `...u_dma250_u_data_biu_hwdata_reg[0]/D` | 9.598 | −0.027 |
| 4 | `...u_dma250_u_data_biu_hwdata_reg[3]/D` | 9.600 | −0.016 |
| 5 | (first passing) | | **+0.009** |

All four are `reg2reg`; every other path group passes with margin
(`reg2out` +5.103, `in2reg` +2.431). Uncertainty 0.350 on every one. The
"next endpoint at +0.009" in the brief is exact.

**THE FINDING THE BRIEF DOES NOT HAVE: all four violators launch from the same
flop.** Startpoint on paths 1, 2, 3 and 4 is
`...u_chip_core_u_cpu_0_...u_core_offset_q_reg[0]/CP`. This is not four
independent critical paths at a frequency wall. It is one launch flop and its
first-stage fan-out costing the design 49 ps across four cones — which is
precisely why a 38-cell ECO closes all four (§2.2).

**THE CORRECTION: the 0.350 uncertainty is not an oscillator jitter spec.** The
brief calls it "a real external oscillator jitter spec — NOT reducible". The
constraint file says the opposite, at length, and it was written to stop exactly
this reading. `ASIC/genus-innovus/inputs/constraints.sdc:21-39`:

* the one-line comment claiming it comes from oscillator jitter is flagged in the
  file itself as **misleading**;
* the datasheet RMS phase jitter is **0.85 ps** — *"even converted to
  peak-to-peak at BER 1e-12 that is only ~0.012 ns. JITTER IS NOT WHERE 0.35 ns
  COMES FROM — it is roughly 1/29th of it"*;
* the dominant term is duty-cycle distortion, computed **at 250 MHz**, giving
  ±0.2 ns — but this design runs at **100 MHz** (`ASIC/common.mk:262`,
  `CLK_PERIOD ?= 10.0`);
* duty-cycle distortion only reaches checks that use the negative edge, and the
  file notes that *"if this design is genuinely posedge-only, most of the 0.35 ns
  is buying margin against a mechanism that cannot reach it — which is safe, but
  it is not free."*

The file's own verdict is *"a signoff margin and it is CONSERVATIVE"*, deliberately
left as it is. That is a good decision and I am not proposing to change it. But it
changes what the 49 ps means: **the four setup violations sit inside a
conservatively-set margin, not inside the silicon.** They are a policy artefact
before they are a design defect.

### 1.5 The context both of those sit in: the derate is a documented guess

`ASIC/eth-chiplet/evidence/gdsrun-20260826-rc1.json`, `known_bad[4]`:

> *There is no AOCV, SOCV or LVF data for this technology anywhere on site*
> (865 library files searched for the relevant keys, zero hits, with a
> contrastive control showing the same site does ship that data for two finer
> nodes and that the memory compilers here cannot regenerate it).
> *The flow's own scripts call the 0.95/1.05/0.97/1.03 factors a GUESS in as many
> words.*

Matched four-point control on the same database, same extraction, changing only
the four derate lines:

| | setup WNS / FEP | hold WNS / FEP |
|---|---|---|
| derate off | **+0.287 / 0** | −0.014 / 6 |
| derate on (the guess) | −0.049 / 4 | −0.053 / 394 |

**Every violation under discussion in this document exists only at a derate
nobody can source.** That does not make them safe to ignore — an unsourceable
derate is a reason for conservatism, not against it — but it does mean the
question "would a respin close them" is partly a question about a number we chose.

---

## 2. Q1 — what a respin would actually fix, mechanism by mechanism

### 2.1 The hold endpoint: a respin would not fix it, and there is no CTS lever

**Is a CTS skew balance achievable?** No, and the reason is structural rather than
about the fence.

Useful skew and skew groups work by inserting or resizing buffers on **distinct
branches** of a clock tree so that two sinks see different insertion delays. Here
there are no distinct branches. Both flops take `.CPN(clk_in)` directly, in the
placed-and-routed netlist as well as the synthesised one. The 199 ps
(capture net latency 0.866 vs launch 0.667, per `RESULT_ITER2.txt`) is RC delay
from one driver to two pins on one net. There is no object for a skew directive to
act on. `set_ccopt_property` and friends have nothing to grip.

The levers that do exist, and what each costs:

| lever | would it work | cost | verdict |
|---|---|---|---|
| CTS skew group / useful-skew directive | **no** — one net, no branch | — | not available |
| buffer on the clock into one flop | yes, creates a branch | breaches the fence on a clock path; the module's negedge structure is its glitch-free proof | **must not** |
| delay cell on the data path `byp_en_meta_r → byp_en_r` | yes | breaches the fence, but on a **data** path — structurally benign to the glitch-free argument | possible if the fence were scoped, but see below |
| place the two flops adjacent | yes — this is the real mechanism | a placement guide on `u_link_clk_div`, at pre-place | **the only clean fix** |
| RTL change | yes | reopens everything | no |

So a respin *could* fix it — but **only if it carries a placement constraint that
does not exist today.** The flow has a `pre_place` hook point
(`flow_hook pre_place` in the toolkit flow scripts) and no `pre_place.tcl` in
`ASIC/eth-chiplet/hooks/`. There is no `create_guide`, `create_region`,
`place_instance` or relative-floorplan machinery anywhere in the flow or the
project hooks — I searched. That is new, unproven, untested work, written and
first executed inside the last three working days before submission, on the one
module whose structure is a correctness proof.

**A respin that does not carry it would reproduce the violation exactly.** This is
measured, not assumed. `gdsrun-20260825-resynth` and `gdsrun-20260826-rc1` are a
true re-roll pair: both ran their own synthesis from RTL, the two 40 MB gate
netlists differ by **one line — the `Generated on:` timestamp comment** — every
provenance hash on the place manifest matches, and the timing is **identical at
all seven reported stages**, down to the picosecond, ending at setup
+0.010 / 0 FEP and hold −0.005 / 13 both times. The post-fill figures the route
manifests carry — setup +0.009, hold −0.012 / 16 — are likewise identical
between the two. (Those two hold numbers are different stage snapshots of the
same run, not a disagreement: the manifest records post-fill and the stage report
records post-route-optimisation, which the `known_bad` entry on hold spells out.)
This flow is deterministic on identical inputs. A bare re-roll buys nothing.

And four independent optimisation attempts have already declined this endpoint:
the shipped run's own post-route hold pass, two heavy Innovus hold experiments
(`derate-feas-20260826` arms B and D, 12,831 and 12,853 buffers, hold WNS
unmoved at −0.012 in both), and both Tempus `opt_signoff -hold` passes, which
fixed 11 of the 12 around it and refused this one twice.

**But the right answer is that it does not need fixing.** §1.3 shows the pin's
data input is a constant in the shipped gates. Spending a placement constraint,
a fence exception, or a respin on a check that cannot be excited is spending real
risk to buy a number in a report.

**Disposition:** waive it, on the netlist argument in §1.3 rather than on the
case-analysis argument. That argument is checkable by anyone with the gate
netlist and does not depend on an SDC being read.

### 2.2 The four setup paths: already closed by ECO — a respin is the wrong tool

The design is **not** at its frequency limit in the sense that would justify a
respin, and this is measured rather than inferred.

`ASIC/eth-chiplet/build/derate-feas-20260826/RESULTS.md`, experiment **A** —
`opt_design -post_route` at `opt_setup_target_slack 0.075`, then the ordinary
hold pass — judged in **Tempus with the derate applied and Quantus extraction**,
i.e. the tool and the conditions that report the failure:

| database | setup WNS / TNS / FEP |
|---|---|
| control (= what shipped, pre-fill) | −0.048 / −0.135 / **4** |
| A — 38 cells, 18 minutes | **+0.016 / 0.000 / 0** |

**The four failing signoff endpoints go to zero with +16 ps to spare, for 11 added
cells and 27 resizes.** `check_drc` clean, DRV bit-identical, density +0.002
percentage points, hold unharmed, area +20.9 µm². The pre-fill substrate is
validated as a stand-in in both directions on both checks in the same document.

So: would a re-synthesis close them? Very likely yes — but only by doing the same
optimisation, at fifteen times the cost, with everything else re-rolled. A bare
re-roll would reproduce them exactly (the determinism result above). A respin with
a raised setup target would close them, and so does an ECO that takes 18 minutes.

**Is the design at its limit?** Close to it, and this is the one genuine argument
*against* touching anything. Of the 50 worst setup paths in the signoff report,
**22 sit below +50 ps and 15 below +25 ps**, with the cluster
+0.009 / +0.014 / +0.016 / +0.017 / +0.022 ×5 / +0.023 ×2. The design closes on a
dense wall. That is a reason to prefer a 38-cell ECO that touches 38 things over a
respin that touches 366,000.

### 2.3 The three max_capacitance at −0.001

These do not exist in `rc1`; the hold ECO introduced them. A respin would not
"fix" them because it would not inherit them — it would roll this class afresh.
The relevant measurement is that experiment A's setup pass is the thing that
*removes* this class: in the `derate-feas` E arm, a setup-recovery pass on a
hold-repaired database took real `max_capacitance` from 6 back to **0** and real
`max_transition` from 2 back to **0**. So the fix for the 3 is the same setup ECO
that closes the 4 — which is the whole argument for option (b′).

At −0.001 ns they are, in any case, at the resolution of the report.

---

## 3. Q2 — what a respin would let us fold in, and what each is worth

A full inventory was taken across the docs tree, the hooks directory, every
unmerged branch and the tidechart submodule. The complete list is long; what
follows is everything that both **requires a rebuild** and has a case for being
done. Nothing in it must land before 1 September.

| # | item | needs | buys | risks | verdict |
|---|---|---|---|---|---|
| 1 | **TideChart APB address width** — `next/tidechart-apb-width` (2 commits) plus `next/apb-addr-w-9` in the submodule | **re-synthesis + full P&R.** An RTL parameter that changes the decode cone and restores 189 deleted flops. No ECO path | Real functional gain: the bridge slices `paddr[7:0]` into a decoder that reads `[8:2]`, so 10 registers at `0x100-0x124` are unreachable and the region **aliases 16-fold across the whole 4 KB window** with ready tied high and error tied low. 780 byte addresses land on a writable register; one stray word clears the route table and re-arms root election on a live link | Re-opens the submission. Explicitly triggers two `withdraw_when` clauses on the accepted LEC finding — the acceptance is bound to a specific gate netlist hash. The commit is honest that it does **not** help the live dual-root question: in the failing case the newly-readable registers read all-zero on both dies | **The strongest functional case, and still no.** It buys observability we cannot use before submission and costs the whole evidence chain |
| 2 | **VSS pad-feed electromigration** — `known_bad[9]` | pad-feed widening (power-plan → full P&R) **or** a fifth supply pad (padring **and board** change) | 49 VSS grid elements over the derated limit, worst J/Jmax **1.432** on the second metal, 1.129 on the first. First EM analysis ever run on this design, on this build's own database. Reliability | — | **Probably a false red — and testable without a respin.** See below |
| 3 | **Extraction tier** — `docs/asic/EXTRACTION_CORRELATION.md` (untracked) | a new route stage | Makes the P&R tool optimise the **right set of paths**: measured today, switching extraction effort on the same database takes hold failing endpoints 16 → 136 and macro-input endpoints 2 → 86, with overlap against the signoff worst-50 going 0 → 21 | +12% on a route stage. Its own §7 says the risk *"is not the extraction, it is the re-run"* | Its own recommendation is **"land it now, off; enable it after submission"**. Do that. The "off" half costs nothing and has not been done |
| 4 | **OCV derate hook** — `ASIC/eth-chiplet/hooks/pre_route.tcl`, committed today, **never executed** | a new route stage | Auditability only. It states the derate per corner and records it in the manifest, which today records none | Its own header, in capitals: *"THIS HOOK DOES NOT FIX THAT AND MUST NOT BE CITED AS FIXING IT."* Measured at the shipped defaults it leaves worst setup and worst hold **bit-identical** | Zero timing benefit. Note the trap in §4.4 |
| 5 | **D2D transmit clock group (option A/B)** — `docs/asic/C2_TRANSMIT_GROUP_OPTIONS.md` | A: re-synthesis + full P&R (~1,184 newly-timed endpoints). B: new pad → new floorplan → everything, **plus a board change** | A: honesty in the constraints. B: removes a recorded silicon liability | A leaves the design asserting a false synchrony. B risks the board defeating it one buffer further out | Both documents say post-submission. The doc's own line: *"after submission the choice collapses to A by default"* |
| 6 | **Clock-gating exclusion for the multi-bit sync banks** | one re-synthesis | Removes an async signal from 36 clock-gate enables covering 174 flops | Module-scoped attribute may bind to a module that no longer exists; must be re-audited after | Costed in its own doc at *"174 of 50,754 gated flops, 0.34%, one re-synthesis, fully reversible."* Cheap, but not free of a full P&R behind it |
| 7 | **Tag-RAM write-mask fix** | submodule commit + pin bump + re-synthesis | One-line functional correctness fix; would take a power-intent check from 2 to 0 | Pin roll drags in whatever else moved | The fix exists in a submodule **working tree, uncommitted**. Commit it now so it is not lost; land it next revision |
| 8 | **CTS transition target / clock route type** | new CTS + route | Closes 126 allowlisted clock-tree check errors; marginal QoR | The tree will change | Worth knowing: this **did land** on 20 Aug and was **backed out** — not because the value was wrong, but because a vendor-collateral scan caught two unrelated literals in the same commit block. The number exists |
| 9 | **UPF power intent describes a different chip** | re-synthesis, and a rewrite not a rename | Nothing today: one power domain, no always-on requirement | Becomes blocking the moment anyone splits the link into its own domain | Its own doc pre-registers the trap: a prefix rewrite clears 22 of 34 and leaves 6 macro pins with no statement at all |
| 10 | **Scan / DFT** | full respin; and stitching is impossible here because the scan-looking cells are not a chain — the mux was reused as a load-enable | Yield screening, die-level attribution | — | Not affordable. Five items are marked tape-out blockers in the DFT plan and the stream was produced anyway; that decision is already made |
| 11 | **Standard-cell library swap** | full respin from synthesis, new timing closure | Real cell geometry for the physical decks | Total re-closure | Recorded in the flow scripts as *"an option with a known price, not a pending fix"* |

**Item 2 deserves a paragraph, because it is the only entry whose technical case
for a respin is genuinely strong — and it is very likely wrong.** The current in
that analysis is not measured: there is no switching-activity file in the rail
flow, so the demand is the power tool's default toggle assumption, and J/Jmax
scales linearly with it. As of today that assumption has been measured against
real workloads (`docs/asic/POWER_FLOW_PLAN.md` §1.1, §6.2, 100% net annotation on
every arm, and a control that reproduces the candidate's own power report to the
last digit):

| arm | total | supply-rail demand |
|---|---|---|
| default toggles (what the EM number used) | 80.66 mW | 50.24 mA |
| real dual-core workload, at the rated clock | 15.02 mW | **13.05 mA** |

That is a **3.85× reduction in the quantity the EM solve consumes**, against a
1.43× overage. Re-running the rail solve with the activity file that already
exists needs **zero additional simulation** — the same database, byte-identical —
but four coupled edits to the rail scripts, one of which fixes a live defect where
a stale power report is silently reused. That is a day of work and it is not a
respin. **Do that before anyone proposes a pad-feed change.** I have not proven
the red clears: current could redistribute under a real workload, and the honest
statement is that the 3.85× margin makes it very likely and only the re-run
settles it.

**And three "parked" items are already landed** — worth stating so nobody re-opens
them: the transmit word-clock source fix (a doc still says no run has consumed it;
`rc1`'s own synthesis SDC carries it), the punchlist item that says no synthesis
has run since a constraint change (two have), and the link-clock divider itself
(described elsewhere as another session's uncommitted work; it is in the shipped
gates).

---

## 4. Q3 — what a respin costs and risks

### 4.1 Tool time is the small part

Measured `runtime_s` from the stage manifests of five full runs:

| run | syn | place | cts | route | total |
|---|---:|---:|---:|---:|---|
| `full-20260814` | 5582 | 2497 | 3489 | 3134 | 4 h 05 m |
| `gdsrun-20260821-slpads` | 6052 | 2513 | 3144 | 3798 | 4 h 18 m |
| `gdsrun-20260825-resynth` | 6022 | 2623 | 3093 | 4091 | 4 h 23 m |
| `gdsrun-20260826-rc1` | 6318 | 2790 | 3243 | 4200 | **4 h 35 m** |
| `bscan-probe` | 6451 | 4159 | 3669 | 3182 | 4 h 51 m |

**~4 h 20 m ± 30 m from RTL** on 14 local CPUs; **~2 h 35 m ± 10 m** for
place/CTS/route from a seeded netlist. The brief's 4 h 38 m is right for `rc1`.

### 4.2 The costs that are not tool time

**The manual VIA3.R.4 repair does not re-derive.** The script
(`ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl`) takes a Calibre marker
as its **only** positional input, and it has to: the offending cut is inside a
merged macro, so the P&R tool has no object there — the header records
`get_obj_in_area` over the marker box returning zero vias. The loop is therefore
stream → Calibre → parse marker → run script on a copy of the database →
re-stream → Calibre to confirm, with a human deciding at the marker step. Local
Calibre signoff DRC is cheap (409 s real, 1,926 rulechecks) but the loop is not
automatable and there is **no in-flow arm for this rule** — the `known_bad` entry
that closed it says so explicitly and says it re-opens the moment a run streams
without the ECO.

**The signoff pack is pinned, and not to one build.** 17 of the 29 stages in
`ci/signoff.yaml` carry a hard run-tag pin, and those pins span **six different
builds**: ten point at a stream from 23 Aug, three at `rc1`, and one each at four
others. A respin means editing and re-running all seventeen. That is not just
labour — it is exactly the shape of failure this project has already produced four
times, where a green verdict turned out to have read a superseded stream.

**The LEC acceptance is hash-bound.** `known_bad[8]` accepts a 96-flop
RTL-to-gate finding as parameterisation-bounded dead code, and its
`withdraw_when` clause (e) reads: *"the design is re-synthesised, in which case
re-run all three legs: the acceptance is bound to gate.v sha1 5872..."*.
A respin withdraws it and all three legs must run again.

**The waiver document dies on contact.** Its §7: *"This document is a statement of
position on findings in a specific stream. It is valid only for md5
`acd2b93e...`; any re-stream invalidates it and it must be re-issued."* That is
true of options (b) and (b′) as well, and it is the single largest shared cost of
re-streaming at all.

**A new foundry submission.** Measured turnaround from stream mtime to broker
report, across three runs: ~19 h, ~19 h, and **~9 h** for `rc1v3r4` (written
08:08, checked from 17:45). So roughly one working day, and it has been done
same-day once.

**The XOR reference.** `rc1v3r4` and the `v3r4` candidate are a proven-identical
pair — geometric XOR reports no differences on all 49 layer and datatype pairs.
This is the arbiter the canonical-hash tool defers to, because that hash is
order-sensitive in a way the stream writer does not preserve. Losing it is a
**modest** cost, not a large one: re-establishing it means writing the stream
twice and running the arbiter, which is hours not days. I would not weight this
heavily.

### 4.3 Probability a fresh run comes back worse — and the honest correction

The intuition "a respin re-rolls the dice on placement and CTS" is **measurably
false on this flow**, and I want to correct it because it leads to the wrong
mitigations.

The `resynth`/`rc1` pair (§2.1) is a genuine re-execution with identical inputs
and it reproduced timing **exactly at every stage**. n = 1, and the synthesis
audit elsewhere in the tree records that multi-threaded optimisation is not
bit-reproducible in general, so this should not be over-trusted. But it is the
only direct evidence and it points one way.

The real risk is different and worse. **This design is reproducible under
identical inputs and unstable under small ones**, and a respin worth doing carries
a change by definition. Across 16 predecessor→successor transitions in the build
tree:

* **setup WNS came back worse in 7** (44%)
* **hold WNS came back worse in 6** (38%)
* **worse on at least one of setup WNS / hold WNS / DRC in 11** (69%)

and every one of those has a design change attached with a named mechanism, not
tool noise. The instructive ones:

| change | intended | actual |
|---|---|---|
| route halo 1.0 → 2.0 µm (one number) | fewer shorts | setup +0.019 → **−0.072**, 101 failing endpoints; shorts 1 → **3**. Reverted. The halo made the band *outside* the macro expensive, so the router pushed the via stack 0.06 µm **down**, where a halo has no jurisdiction, and two vias landed in the same track |
| via centre-snap + a checker enable | less DRC | Innovus DRC 24 → **4096**, of which 4,082 are one min-step class. Reverted next run |
| hold uncertainty applied to both checks | correctness | hold repair inserted **62,729 instances** and drove setup WNS from +0.001 to **−0.729** |
| a post-route DRC repair step | fewer violations | **deleted three macro pins**, making a cache data bit unwritable — and the step's own success metric scored it a pass |

Separately, roughly **11 of ~30 build directories contain no usable routed
result** — three distinct abort classes (constraint gates, a missing-file hook,
strict message gates), plus one route that crashed and was promoted as the
shipping stream anyway.

**And the largest variance is not in the layout at all.** Measured on one
unchanging database: the tool, extraction and derate choices are worth
**226–336 ps of setup and 8–39 ps of hold**, and switching extraction effort alone
moves hold failing endpoints 16 → 136. The placer re-roll measured 0 ps. We are
proposing to re-run the thing that does not vary in order to fix numbers produced
by the things that do.

### 4.4 One trap specific to a respin now

The moment `pre_route.tcl` exists on disk during a route run — whether or not it
changes the derate — the run's `hooks_run` field changes, and the toolkit's own
equivalence checker lists that field as voiding a route comparison: *a hook that
ran on one side only is a difference in the flow*. So **the first run that
includes today's committed hook is not comparable to `rc1`** by the flow's own
rule. A respin would therefore lose the A/B against the shipping candidate as well
as the foundry binding.

### 4.5 The schedule, concretely

Best case, starting this evening: run completes Friday morning; Calibre, marker,
repair, re-stream and confirm through Friday afternoon; submit Friday evening;
broker result Saturday or Monday. Then seventeen signoff re-pins, three LEC legs
and a re-issued waiver, on Monday and Tuesday.

That is the *best* case, and it assumes nothing in the 69% column happens. If
Friday slips, the submission goes Monday and the broker answers on the deadline
with no time to react. The fallback to `rc1v3r4` remains available throughout —
which is the one genuinely reassuring thing about the whole plan, and also the
reason not to spend the window discovering you need it.

---

## 5. Q4 — the comparison, and the recommendation

### 5.1 The four options side by side

| | (a) ship rc1 as-is | (b) ship hold ECO | **(b′) hold ECO + setup ECO** | (c) full respin |
|---|---|---|---|---|
| **at the signoff derate: setup** | −0.049 / 4 | −0.049 / 4 | **+0.016 / 0** (projected) | unknown |
| **at the signoff derate: hold** | −0.053 / **394** | **−0.011 / 1** | **−0.011 / 1** | unknown |
| **underived** | +0.287 / 0 and −0.014 / 6 | ~0 hold endpoints | ~0 both | unknown |
| cells changed vs rc1 | 0 | +279 | ~+290 | 366,000 |
| cell area delta | 0 | **0.000 µm²** | ~0 | full re-roll |
| foundry result on these bytes | **YES** | no | no | no |
| waiver valid | **YES** | must re-issue | must re-issue | must re-issue |
| Calibre signoff DRC on these bytes | **YES** (738 → 737 after the repair) | **NOT RUN** | not run | not run |
| VIA3.R.4:M4 | **0** | **1** — repair not applied | must be re-derived | must be re-derived |
| signoff stage re-pins | 0 | some | some | **17** |
| LEC legs to re-run | 0 | 1 — the post-P&R leg only; the RTL-to-gate leg is unaffected because the synthesised netlist is unchanged and the ECO acts on the routed database | 1, same | **3** |
| tool time | 0 | done | ~20 min + verify | 4 h 20 m |
| calendar to a foundry answer | 0 | ~1 day | ~1 day | ~2 days if nothing slips |
| **leaves unresolved** | 394 hold endpoints at the derate; 4 setup; the two open broker asks | 4 setup; 3 max-cap; the two broker asks | 1 unexciteable hold check; the two broker asks | everything above, plus a new roll of the 69% |

**Read the "signoff stage re-pins: 0" cell carefully — it does not mean option (a)
has a complete signoff pack.** It means (a) adds no *new* staleness. The pack is
already incoherent: ten of its seventeen pinned stages point at a stream from
23 August and only three at `rc1`, so the post-P&R equivalence leg and the
physical decks do not cover the shipping candidate today either. What covers
`rc1v3r4` is the **foundry run on its own bytes**, which is stronger evidence than
any of our local decks and is exactly what a re-stream gives up until the next
one comes back. That, not the pack, is the thing being weighed here.

**Note the row that decides it.** Option (b) as it stands has *neither* a foundry
result *nor* a local Calibre result *nor* the VIA3.R.4 repair. Its stream is
verified by the P&R tool's own `check_drc`, and the flow's route gate says in as
many words that this *"IS NOT SIGNOFF DRC"*. So (b) is not a shippable position
today — it is a database that needs the same closure loop as (b′), and since the
loop is the cost, there is no reason to run it without the setup ECO.

### 5.2 Why (b′) and not (b)

The setup ECO has been measured at signoff on this exact lineage: 38 cells,
18 minutes, four failing endpoints to zero with +16 ps to spare, DRC clean, DRV
bit-identical, density +0.002 pp. And the ordering is already known: applying the
setup pass **after** the hold repair is the order that works — the `derate-feas`
E arm restored setup to better than the shipped stream, kept the hold repair, and
cleaned up the DRVs the hold pass had introduced.

**What is not measured, and I want to be plain about it:** experiment A was run on
a pre-fill copy of the `rc1` route database, not on the `holdeco` iteration-2
database, and the hold repair underneath it in the E arm was Innovus's 12,831
buffers, not Tempus's 279. The Tempus repair targeted zero slack, so the hold
margin it leaves is thin by construction and a setup pass could eat some of it.
**The projected +0.016 / 0 in the table is an inference, not a measurement.**
What settles it: run the setup pass on the iteration-2 database and re-verify both
checks in Tempus at the same derate — about 20 minutes of optimisation plus a
verification run, on a database that already exists.

If it does not hold, ship the hold ECO alone. That is option (b) and it is still
better than (a) on the axis that matters most.

### 5.3 The recommendation, and why hold outranks setup

**Ship (b′). Gate it. Decide today.**

The asymmetry between the two residual classes is the core of the argument:

* **A setup shortfall is recoverable and is sitting inside a chosen margin.**
  49 ps against a 350 ps uncertainty whose measured physical basis is ~12 ps of
  jitter plus a duty-cycle term computed at 2.5× this design's clock rate. And if
  the part is 49 ps slow, you clock it 0.5% slower. There is a knob after tapeout.
* **A hold shortfall is not recoverable by anything.** There is no knob. The 394
  endpoints are dominated by macro inputs, whose hold requirements are
  0.177–0.189 ns against a flop's 0.024 — an order of magnitude larger, so they
  sit closest to the cliff and a uniform shift tips them first. And the number is
  worse the more accurately you extract: the least accurate extraction gives 6
  endpoints, the tool's own better one gives 136, and full signoff extraction
  with the derate gives 394. **The direction of the measurement error is against
  us.**

Against that, the fix costs 279 cells, **zero area**, zero setup regression,
`check_drc` clean, connectivity byte-identical, antenna clean, and 28 more diodes.
It is about as small a perturbation as a hold fix can be, and it is 46× smaller
than the Innovus route to the same outcome.

**The gate, so the decision does not rest on judgement:**

1. Fold the setup ECO onto the iteration-2 database and verify **both** checks in
   Tempus at the signoff derate. If setup does not close or hold regresses, drop
   it and carry the hold ECO alone.
2. Run local Calibre signoff DRC. Derive and apply the VIA3.R.4 repair from that
   run's own marker. Re-stream. Re-run Calibre to confirm the rule went to zero
   and that nothing else moved — the previous application moved 1 → 0 with **not
   one of the other 1,925 rulechecks changing in either direction**, and that is
   the bar.
3. Submit to the broker, and send the two open asks (correct pad-pitch switch,
   ERC / pad-short package) **against the new md5** in the same message.
4. **Hard fallback:** if a broker result on the new md5 is not in hand by end of
   Monday 31 August, ship `rc1v3r4` and its existing waiver. Do not ship bytes
   that have no foundry result — this project has four documented instances of a
   green verdict that had read the wrong stream, and the deadline is not a reason
   to make it five.
5. Preserve `rc1v3r4` untouched throughout. The hold-ECO work has already
   demonstrated it can do this: all 63 database hashes and the shipping GDS were
   verified identical before and after.

### 5.4 The strongest counter-argument, and my answer

> *"`rc1v3r4` is the only position in this project's entire history where a
> foundry result is bound to the exact bytes we intend to ship. Every other green
> this repo has produced was read off a superseded stream — four documented
> instances, in one day. You are proposing to give that up, three working days
> from the deadline, to fix a population of violations that exists only at a
> derate the flow's own scripts call a guess, using a stream that has never seen
> Calibre, never seen LVS, and still carries a known DRC violation."*

Every clause of that is true and it is the argument I would make against myself.
Three answers.

**First, the fallback is unconditional and costs nothing to preserve.** Attempting
(b′) does not degrade (a) by a single byte. The bytes, the broker report and the
waiver stay on disk. The only thing spent is attention in the window, and the gate
in step 4 caps that at Monday.

**Second, the derate cuts both ways and the counter-argument only uses one edge.**
Yes, 394 is a number at a guessed derate. But underived, hold is still 6 failing
endpoints at −14 ps, and the guess exists precisely because there is no
characterised data for this node — searched and confirmed absent, with a
contrastive control. When you cannot source the variation data, the conservative
reading is the one you sign off at, and 0.95/1.05 is not an aggressive guess. To
ship (a) is to bet that the unsourceable margin is too pessimistic. To ship (b′)
is to bet 279 buffers that it might not be. The second bet is cheaper and the
downside is bounded.

**Third — and this is the part that actually changes the schedule — the
counter-argument assumes the two open broker asks can be settled independently of
the stream. They cannot.** The wire-bond deck has never been run at the pitch that
applies to this part, on any stream. The ERC and pad-short package we hold
describes a stream two revisions back. Both asks need broker calendar time and
both must run on the **final** bytes to be worth anything. So a re-stream is not
purely additive risk: if it is going to happen, it has to happen before those asks
go out, and if it is not going to happen, the asks should go out this afternoon.
Either way the decision is due today, and "wait and see" is the one option that is
definitely wrong.

**Where (a) is genuinely the right call.** If the team's judgement is that a
foundry-bound stream is worth more than the hold margin — a defensible position
given this repo's history of misread verdicts — then take (a), and take it
*cleanly*: send the two asks today against `acd2b93e`, sign sections 1–4 and 6 of
the waiver now, and record the hold and setup positions as declared, measured
conditions of the part rather than as open items. What must not happen is (a) by
default, arrived at on Monday because the (b′) loop was started late and did not
close.

---

## 6. What I am uncertain about, and what would settle each

| # | uncertainty | what would settle it | cost |
|---|---|---|---|
| 1 | Whether the setup ECO holds on the hold-ECO database. The +0.016 / 0 in §5.1 is inferred from a different substrate with a different hold repair underneath | Run `opt_design -post_route` at a raised setup target on the iteration-2 database, then re-verify **both** checks in Tempus at the signoff derate | ~20 min opt + one verification run, on an existing database |
| 2 | Whether the EM red is real. J/Jmax 1.432 was computed at default toggle rates; the real workload is 3.85× lower on the supply rail, but current could redistribute | Re-run the rail solve with the activity file that already exists, after the four coupled script edits | ~1 day, **zero additional simulation** |
| 3 | Whether the seal-ring-side results (939 of them) are the broker's geometry. Our reasoning is measured and I find it convincing, but we cannot check it locally — our stream carries none of those layers, so every local zero on those rules is produced by absent geometry rather than by compliance | Written confirmation from the broker | one email, already drafted |
| 4 | Whether the part passes the wire-bond rules that actually apply. Every run so far used the 80 µm staggered switch; the ring is 67 µm, which selects the 60 µm family. Our opening passes that family with 5 µm of margin on paper | Broker re-run at the correct switch | one email, already drafted |
| 5 | Whether the 0.350 uncertainty is right for a 100 MHz part when its dominant term was computed at 250 MHz. It is conservative in one direction and possibly under-conservative in another, and the file says so | The clocking spec, and a decision about whether any check on the primary clock uses the negative edge | analysis, not a run — and **not before submission** |
| 6 | How reproducible synthesis really is. One re-roll pair matched exactly; a synthesis audit elsewhere records that multi-threaded optimisation is not bit-reproducible and that *which* logic gets deleted is not stable | A second re-roll pair with identical inputs | 4 h 20 m, and there is no reason to spend it |
| 7 | Whether a placement guide on the divider would actually close the hold endpoint. The mechanism is right — one net, two sinks, RC-limited — but no such constraint has ever been written for this flow and there is no guide machinery in it | Write a `pre_place` hook and measure. **Only worth doing after submission**, and arguably not then, since the check cannot be excited | a run, plus new code on a correctness-critical module |

---

## 7. Appendix — the numbers this document rests on

Every figure below was read from a file during this assessment. Paths are relative
to the repository root.

| fact | source |
|---|---|
| foundry result bound to `acd2b93e`; antenna 0; 613 main-DRC results, 612 in vendor cells; no density rulecheck | `ASIC/imec_results/Archive_*rc1v3r4*/design/reports/Final_Report_*.rpt` |
| padring 0 errors / 0 warnings | `ASIC/imec_results/Archive_*rc1v3r4*/padring/Padring_check.rpt` |
| wire-bond deck: 943 results, 4 rulechecks | same archive, `bnd/` |
| waiver valid only for `acd2b93e`; both broker asks open | `docs/tapeout/60-waiver-document-rc1v3r4.md` §3, §4, §5, §7 |
| hold ECO: 279 cells, 0.000 µm², setup unmoved, hold 394 → 1 | `ASIC/eth-chiplet/build/holdeco-20260827/RESULT_ITER2.txt` |
| engine gap: signoff extraction computes ~4.5% less data-path delay | `ASIC/eth-chiplet/build/holdeco-20260827/ENGINE_GAP_FINDING.txt` |
| experiment A: 38 cells close setup at signoff; E: hold-then-setup is the order that works | `ASIC/eth-chiplet/build/derate-feas-20260826/RESULTS.md` |
| 4 setup violators, all from one launch flop; 22 of 50 paths below +50 ps | `ASIC/sta/work/gdsrun-20260826-rc1/reports/timing_setup_default_analysis_view_setup.rpt` |
| setup summary −0.049 / −0.137 / 4, all reg2reg | `ASIC/sta/work/gdsrun-20260826-rc1/reports/timing_summary.rpt` |
| the divider's data input is a constant; module specialised for ratio 0 | `ASIC/eth-chiplet/build/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_gate.v` |
| both flops still on one clock net after P&R | `ASIC/eth-chiplet/build/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_pnr.v` |
| the fence: `set_dont_touch` on the divider, one of 83 | `ASIC/eth-chiplet/build/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_syn.sdc:127091` |
| ratio tied to zero at the chiplet top | `tidelink/imp/fpga/eth_chiplet_ip/src/nanosoc_eth_chiplet.sv:960` |
| rate-register bank defaults absent, no override | `tidelink/imp/fpga/eth_chiplet_ip/src/tidelink_top.sv:261` |
| the glitch-free interlock and why it is fenced | `tidelink/imp/fpga/eth_chiplet_ip/src/tidelink_link_clk_div.sv:161-205` |
| the 0.350 is duty-cycle margin, not jitter; jitter is ~1/29th of it | `ASIC/genus-innovus/inputs/constraints.sdc:21-39` |
| 100 MHz, 10.0 ns | `ASIC/common.mk:262` |
| derate is a guess; no characterised variation data on site; underived numbers | `ASIC/eth-chiplet/evidence/gdsrun-20260826-rc1.json`, `known_bad[4]` |
| EM: 49 elements, worst J/Jmax 1.432, current is assumption-driven | same file, `known_bad[9]` |
| LEC acceptance bound to a gate netlist hash; re-synthesis withdraws it | same file, `known_bad[8]` |
| no in-flow arm for VIA3.R.4; repair is marker-driven | same file, `known_bad[0]`, and `ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl` header |
| real-workload power, 100% annotation, control reproduces the candidate exactly | `docs/asic/POWER_FLOW_PLAN.md` §1.1, §6.2 |
| extraction tier moves hold endpoints 16 → 136 on one database | `docs/asic/EXTRACTION_CORRELATION.md`, and `ASIC/eth-chiplet/build/extract-corr-20260827/reports/manifest.txt` |
| the derate hook is a measured no-op at shipped defaults | `ASIC/eth-chiplet/hooks/pre_route.tcl` header |
| post-route optimisation mode, and the 14-run table behind it | `ASIC/eth-chiplet/design.mk` (post-route optimisation mode section) |
| 17 of 29 signoff stages pinned, across six builds | `ci/signoff.yaml` |
| stage wall-clock for five full runs | `ASIC/eth-chiplet/build/*/reports/{syn,place,cts,route}_manifest.txt` |
| the re-roll pair: identical timing at all seven stages | `ASIC/eth-chiplet/build/gdsrun-2026082{5-resynth,6-rc1}/reports/timing_summary_*.rep` |
| local Calibre signoff DRC: 409 s, 1,926 rulechecks | `ASIC/eth-chiplet/build/rc1-signoff-20260826/logs/drc_sign.console` |
| the XOR arbiter and why the canonical hash defers to it | `scripts/ci/gds_canonical_hash.py`, `scripts/ci/gds_xor_arbiter.py` |
