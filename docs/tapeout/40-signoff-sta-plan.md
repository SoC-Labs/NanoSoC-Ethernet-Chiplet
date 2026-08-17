# 40 — Signoff STA: the plan, the measured gaps, and what ran overnight

**Date:** 2026-08-17 (overnight into 08-18)
**Design:** `nanosoc_eth_chiplet_pads`, TSMC 65LP, Genus 21.15 → Innovus 21.11
**Branch:** `fix/tag-ram-gwen`
**Status of the subject:** no signoff-quality STA had ever been run on this
design. Every timing number in circulation — including the setup FEP 1444 /
WNS −0.759 / hold FEP 11 that is currently an accepted open item — comes from
Innovus **in-flow** analysis, which is an optimisation-side estimate, not a
signoff measurement.

That is no longer entirely true: a Tempus run set exists, it loads this
design, and it is committed. What it still cannot do is enumerated below,
honestly, rather than declared closed.

---

## 1. The split you asked for

### (a) Autonomous — no human decision needed

Done tonight, or mechanically doable from here.

| # | Item | State |
|---|---|---|
| A1 | **Measure tool availability** (Tempus / PrimeTime / StarRC), against the licence servers, with a positive control | **DONE** — §2 |
| A2 | **Build a Tempus signoff run set** that does not contend for Innovus | **DONE** — `ASIC/sta/` |
| A3 | **Prove the gate can fail** — mutation self-test over every property it claims to check | **DONE** — 20/20 mutants rejected |
| A4 | **Diagnose why Tempus would not load this design** (two separate blockers, both non-obvious) | **DONE** — §5 |
| A5 | **Generate an SI-stripped MMMC** so the DB loads, with the cost stated not buried | **DONE** — `make_sta_mmmc.py` |
| A6 | **Re-issue OCV derate in Tempus** rather than inheriting it | **DONE** — and it matters, see §4.4 |
| A7 | Unpack the five corner-specific QRC decks into the project tree and wire one per RC corner | **Ready, not run** — mechanical; §4.3 |
| A8 | Add a second, independent extraction cross-check via StarRC + PrimeTime | **Ready, not run** — §2, §4.3 |
| **A9** | **Derive the LEF→QRC layer map** and set `extract_rc_lef_tech_file_map`. This is the ONLY thing between us and real signoff parasitics | **Next action.** Mechanical, 1–2 h, no decision — §5.3(iv) |

### (b) Needs a decision from you

None of these are technical unknowns. They are all judgement calls with a
cost attached, and I have deliberately not made any of them.

| # | Decision | Why it is yours |
|---|---|---|
| **D1** | **Does STA gate the shuttle at all?** | The design does not close setup at 100 MHz. If signoff STA is a gate, the shuttle date moves. If it is advisory, say so in writing so the gate is not quietly tuned to pass. |
| **D2** | **What frequency does this chip sign off at?** | Measured: it closes setup at **≈93 MHz** with no RTL, no constraint and no P&R change. §6. This is by far the cheapest lever and only you can spend it. |
| **D3** | **Which corners sign off?** | Today exactly two are analysed: SS/1.08 V/125 °C setup, FF/1.32 V/−40 °C hold. `ss_1p08v_m40c` and `ff_1p32v_125c` libraries exist on disk, unused. Adding corners can only find more violations. |
| **D4** | **Is 0.350 ns clock uncertainty still right post-CTS?** | It is applied on every one of ~30 clocks, post-CTS, on top of propagated latency and CPPR. Some of it is pre-CTS skew allowance that the clock tree now models for real. Recovering 0.25 ns of it is worth ~0.25 ns of WNS across the board — but it is margin you are choosing to give up. |
| **D5** | **Is flat 5 %/3 % OCV the right derate at 65 nm?** | On an 11.2 ns data path the 1.05 late data derate alone costs ≈0.53 ns. AOCV/LVF would recover much of that and is more defensible than flat OCV — but needs vendor data we do not have (§ (c)). |
| **D6** | **Does signoff require SI (crosstalk)?** | Tonight's run has SI **off** — forced, see §5.2. P&R claims "SI On". Getting it back costs a restructured run (SMSC, one view per invocation). |
| **D7** | **The `-divide_by` constraint class — one decision, three instances** | See §4.7. **Pick whether the SDC describes the shipped configuration only, or every configuration the hardware can be put into.** Everything else follows mechanically, three times. |

### (c) Blocked on something absent

| # | Blocked item | What is missing |
|---|---|---|
| **B1** | **Corner-correct extraction** | Both the Cadence QRC deck and the StarRC deck on site are built from the **typical** ICT. Corner-specific QRC tarballs exist (A7) and will improve this, but the *cap tables* remain modelled on the wrong metal stack (`1p9m_6x2z`, M9 at 0.9 µm) versus the real 6X1Z1U (M9 at 3.4 µm). No 6X1Z1U cap table exists in the ARM set and the TSMC PDK ships none. **Vendor collateral request.** |
| **B2** | **AOCV / SOCV / LVF derating** | No statistical-derate data in any library on site. Flat OCV is the only option until the vendor package includes it. |
| **B3** | **SI with concurrent MMMC** | The noise libraries here are Celtic `.cdb`, which Tempus supports only in SMSC. ECSM/CCS-noise data would remove the restriction entirely. Vendor request. |
| **B4** | **Hold sign-off on the D2D word clocks** | Not a tool gap — a *constraint* gap, §4.5. Until source latency covers those domains, hold on them is fiction regardless of which STA tool runs. |

---

## 2. Tool availability — measured, not assumed

Three separate repo documents have previously declared a tool absent that was
in fact installed and idle (Voltus, SpyGlass, and now Tempus). So this was
measured against the licence servers, and a positive control was run each
time: a server that refuses a connection looks identical to a tool that does
not exist.

**Both signoff STA tools are installed, version-appropriate, and completely idle.**

| Tool | Path | Version | Seats | In use |
|---|---|---|---|---|
| **Tempus** | site Cadence SSV tree | 21.11 | **41** × `Tempus_Timing_Signoff_XL`, `_MP`, `_TSO`, `_PI_opt`, `tempus_advanced_analysis` | **0** |
| **PrimeTime** | site Synopsys tree, `PT_2022.12` | 2022.12 | **200** (+4 on the second server); `PrimeTime-SI` 200; `PrimeTime-ADV` 200 | **0** |
| **StarRC** | same Synopsys tree | 2022.12 | **150** `STAR-RC2-*` (+42) | **0** |

Positive control: on both vendors the licence query reported the server and
its vendor daemon up, and enumerated hundreds of other features — so an empty
Tempus line would have been meaningful. It was not empty.

**Tempus is version-matched to the Innovus 21.11 that built the database.**
That matters: it can read the routed database directly.

### Extraction technology — both vendors, both present

| Deck | Stack | Corner | Note |
|---|---|---|---|
| Cadence QRC `qrcTechFile` | 6X1Z1U | typical only | 178 MiB, readable. **Already wired** into `nanosoc_eth_chiplet_pads.mmmc`. |
| Cadence QRC corner packs | 6X1Z1U | cbest / cworst / rcbest / rcworst / typical | 5 read-only tarballs, ~90 MB each. Unpack into the project tree (A7). |
| Synopsys StarRC `.nxtgrd` | **6x1z1u** | typical only | 22 MB. Matches the real stack — unlike the cap tables in use. |

> **A flow comment is now stale and should not be trusted.**
> `4b_pnr_route_eval.tcl:736-744` states *"there is no Quantus/QRC technology
> file installed anywhere on this site"*. There is. It is 178 MiB, dated 2012,
> readable by the PDK group we are already in, and the `.mmmc` already
> references it. Whoever reads that comment next will otherwise
> re-request collateral that is on disk.

---

## 3. What signoff STA needs, and what we have

| Requirement | State | Gap |
|---|---|---|
| **Netlist** | Post-route `_pnr.v`, 42 MB, plus a restorable routed DB | none |
| **SDC** | `_syn.sdc` (127,672 lines) + per-view `latency.sdc` inside the DB | see §4.5 — the SDC alone is **not** sufficient |
| **Parasitics** | **Zero SPEF existed anywhere in the repo.** Verified: `find` for `*.spef*` returned 0 files; no `write_spef` anywhere in the flow | Tempus now extracts and writes them (A2) |
| **Extraction tech** | QRC deck present and wired | typical-ICT only (B1); cap tables model the wrong stack (B1) |
| **Corners / MMMC** | 3 library sets, 3 RC corners, 4 delay corners, 5 views defined | only **2 views active** at signoff (D3); 2 views defined but never activated anywhere — dead |
| **Derates** | flat OCV 0.95/1.05 data, 0.97/1.03 clock | does **not** survive `read_db` (§4.4); no AOCV/LVF (B2) |
| **CPPR** | `timing_analysis_cppr both`, confirmed active (`Cppr Adjust: +0.163` on the worst path) | none |
| **I/O timing models** | 48 `set_input_delay`, 30 `set_output_delay`, 9 `set_driving_cell`, 39 `set_input_transition`, 62 `set_load` over 41 top-level port bits | coverage looks complete; **not yet independently confirmed** — `check_timing` in tonight's run is the check |
| **Modes** | exactly **one** `create_constraint_mode` (`default_constraint_mode`) | no separate test/scan or low-power mode. If scan is timed, it is timed in the functional mode. |
| **SI / crosstalk** | Celtic `.cdb` present | off in Tempus (D6/B3) |

---

## 4. The gaps that will bite, in priority order

### 4.1 There was no SPEF — at all

Not "an old one", not "one per corner": **zero**. In-flow extraction lived
only in memory. Nothing downstream — no independent STA, no third-party
check, no correlation — was possible. Tonight's run writes one SPEF per RC
corner.

### 4.2 The in-flow number and a signoff number are not the same measurement

The flow extracts with `extract_rc_effort medium` and supplies *both* a cap
table and a QRC deck, which Innovus flags (`IMPEXT-6202`) with a
recommendation to drop the cap table so the QRC engine is used throughout.
Whatever setup FEP the flow reports carries that ambiguity. Expect the
signoff number to **differ** from 1444 in both directions on different paths.

### 4.3 Extraction is not corner-correct

One typical-ICT deck is applied to the worst, best and typical RC corners.
That is better than a wrong-stack cap table, and it is not signoff. A7 fixes
the QRC half mechanically. The cap-table half is B1 and needs the vendor.

### 4.4 Derate does not survive `read_db` — and this one is dangerous

Measured on the routed DB: it persists a `timingderate.sdc` for
`typical_delay_corner` **only**. There is none for `default_delay_corner_max`
or `default_delay_corner_min` — that is, **neither of the two corners that
actually sign off**. Earlier-stage DBs carry none at all, and
`report_timing_derate` at CTS listed only 2 of the 4 delay corners.

A Tempus run that trusts `read_db` therefore analyses both signoff corners
with **no OCV derate** and reports *better* timing than the flow did. Silent
optimism, in the one direction nobody audits. The run set re-issues derate
explicitly and the gate fails if the manifest cannot prove it.

### 4.5 The clock-coverage hole is real and is not a tool problem

- `_syn.sdc` defines **33 clocks** (4 `create_clock` + 29 `create_generated_clock`).
- It contains **zero `set_clock_latency`** and **zero `set_propagated_clock`**.
- The CTS source-latency writeback lives only inside the DB, as three per-view
  `latency.sdc` files, and covers **5 of 33 clocks** — none of the 16 D2D word
  clocks.

So **hold on those domains is fiction**, and the existing gate reads 20/20
green because it checks internal consistency and never checks coverage.

Two consequences worth being blunt about:

1. Rebuilding constraints for STA from `_syn.sdc` alone would silently drop
   the latency writeback entirely. Any STA must restore the DB or take the
   per-view `latency.sdc`. Tonight's run set does the former.
2. The right instrument already exists and has never been pointed at this
   design: Tempus `report_analysis_coverage` reports *untested* checks
   directly. The gate treats any non-zero untested count as a failure, and an
   unparseable coverage report as a failure too.

### 4.6 No pre-P&R timing number from either flow is quotable

This constrains what "closure cost" can even mean, so it belongs in the plan
rather than in a footnote:

- The **legacy lineage synthesised against `ZeroWireload`** — zero interconnect
  capacitance. Every net is free. A setup number from that flow is not
  pessimistic or optimistic, it is meaningless.
- The **toolkit run hit `SYN_PLE` without `SYN_MMMC`** and silently fell back
  to generic PLE, i.e. estimates from a default layer stack rather than this
  design's.

**Only post-route timing is quotable at all.** Any plan that proposes to
"check the improvement in synthesis first" is proposing to measure with a
broken instrument. It also means the 100 MHz target has never once been
validated by a trustworthy pre-layout number — the first honest measurement of
this design's speed is the post-route one, and it says the design is ~0.7 ns
short (§6).

### 4.7 The `-divide_by` defect class — one decision, three instances

The same defect appears in three places. They want one ruling, not three
arguments.

| # | Instance | Status |
|---|---|---|
| 1 | **QSPI** `create_generated_clock … -divide_by 2` on `QSPI_SCLK` | The ratio is a *register reset value*, i.e. software, not silicon. Already flagged in-file as `[C3] OPEN DECISION, FOR THE OWNER`. |
| 2 | **SGDC period** (`cdc/nanosoc_eth_chiplet.sgdc`) | Same family: a declared period that describes one configuration. |
| 3 | **D2D link-clock divider** | `link_clk_div_ratio_i` is now **tied to `3'd0`** at `nanosoc_eth_chiplet.sv:792`, i.e. explicitly pinned to the /1 bypass leg rather than left to X-propagation. |

Instance 3 has **improved since this investigation began** and the improvement
is worth being precise about, because it is easy to over-read:

- **What the tie-off fixes:** the clock topology is now unambiguous. At ratio
  0 the divider is combinational passthrough, the tie makes that explicit, and
  the constraints' `-divide_by` values are *correct for the design as it will
  be taped out*. There is no X-propagation ambiguity for STA to trip over.
- **What it does not fix:** at any non-zero ratio `clk_out` is a genuinely
  different, *registered* clock, and every `-divide_by` in
  `tidelink_constraints.sdc` still describes the /1 case only. If the divider
  is ever reachable in silicon — through a strap, a register write, or a
  respin — those constraints describe hardware that no longer exists.

So the decision is not "is the tie-off enough" (for tapeout, it is). It is:
**does this project's SDC describe the shipped configuration, or the
configuration space?** Answer once, apply to all three.

A related trap, already recorded but relevant to any frequency sweep:
`tidelink_constraints.sdc:38` does `set D2D_LINK_PERIOD $EXTCLK_PERIOD`. A
`CLK_PERIOD` sweep therefore silently retargets the D2D link as well as the
core. Anyone exploring **D2** must pin `D2D_LINK_PERIOD` independently or the
experiment measures two changes at once.

### 4.8 One constraint mode

Everything is timed in `default_constraint_mode`. There is no test/scan mode.
Whatever scan configuration exists is either timed as functional logic or not
timed at all; sibling work on scan should be reconciled against this.

---

## 5. What was actually built and run overnight

All new files, under `ASIC/sta/`. **Nothing under `ASIC/genus-innovus/scripts/`,
`ASIC/eth-chiplet/design.mk` or `inputs/*.sdc` was touched**, and no Innovus
licence was taken — Tempus reads the saved database, so a live route is
unaffected.

| File | Purpose |
|---|---|
| `ASIC/sta/run_signoff_sta.tcl` | The Tempus run: `read_db` → derate → `extract_parasitics` → SPEF per corner → `check_timing`, `report_analysis_coverage`, `report_timing_summary`, per-view timing |
| `ASIC/sta/run_sta.sh` | Launcher. Refuses a DB modified in the last 20 minutes, so it cannot read a live route mid-write |
| `ASIC/sta/make_sta_mmmc.py` | Derives an SI-stripped MMMC from the DB (§5.2), with a self-check |
| `ASIC/sta/sta_gate.py` | The gate, plus `--selftest` |

Run outputs land in `ASIC/sta/{work,outputs,reports}`, already covered by the
existing `ASIC/*/work` and `ASIC/*/outputs` ignore rules.

### 5.1 Two non-obvious blockers, diagnosed

Both would cost someone half a day, and both produce error messages that point
away from the cause.

**(i) `read_db` needs `-physical_data`.** Without it Tempus reads the LEFs for
*pin direction only*, never creates the physical cell masters, and the netlist
read dies on the first macro:

```
ERROR (IMPSER-513): Failed to create instance 'BuPAD_TL_RX_0'.
                    Master cell 'PAD70GU' for instance not found in DB.
                    One possible reason could be that lef/lib have been
                    modified and this cell is deleted ...
```

The suggested cause is wrong. `PAD70GU` is present in the DB's own
the DB's own bond-pad LEF and was read seconds earlier.

**(ii) The `.cdb` noise libraries abort the load.**

```
ERROR (IMPESI-3490): cdB based analysis is not supported with CMMMC
                     configuration. ... Configure and run analysis in SMSC
```

This **aborts the design load**, and every subsequent command then fails with
the far less informative `Design must be in memory`, which is what you would
spend the half-day chasing.

### 5.2 The cost of the fix, stated rather than buried

`make_sta_mmmc.py` strips the three `-si` sections. **Crosstalk analysis is
therefore OFF**, while the P&R post-route header claims `Signoff Settings: SI
On`. Tonight's run is *not* like-for-like with the in-flow number on
SI-sensitive paths. Recorded in the manifest as `si_analysis = off`, so no
future reader can mistake it for a full signoff. Restoring SI is **D6**.

### 5.3 Blockers three and four: extraction

Extraction failed twice, for two *different* reasons, and the second one is
the only thing now standing between this repo and real signoff parasitics.

**(iii) Tempus does not ship its own extractor.**

```
ERROR (IMPEXT-5016): Command qrc failed with error message:
                     failed to run: No such file or directory
```

Tempus shells out to `qrc` and does not resolve it from its own install.
Quantus is a **separate package** — `QUANTUS_21.11.000`, version-matched to
both this Tempus and the Innovus that built the database. `run_sta.sh` now
puts it on `PATH` explicitly, and that is **fixed and verified**: Quantus
21.1.1-s329 now launches, loads all 346,456 components, and runs.

The trap for anyone re-deriving this: three *older* installs (`EXT_15.26`,
`EXT_17.12`, `EXT_18.12`) also carry a `qrc`, and a stale `PATH` finds one of
them first. A 2015-vintage extractor against a 21.11 database is a
silent-wrong-answer risk, not a crash.

**(iv) THE REMAINING BLOCKER — the QRC deck's layer names do not match the LEF.**

```
ERROR (EXTSNZ-127): The layer name "AP" is used in the LEF/DEF file ... but the
                    definition for it cannot be found in the tech file.
        ... same for "M9", "M6", "M3", "M2"
ERROR (EXTGRMP-103): Current job number 0 failed.
        Cadence Quantus Extraction completed unsuccessfully.  Exit code 2.
```

Quantus ran to completion and reported `Nets: 0` — it could not map a single
net, because the physical layer names in the design's LEF (`M1`…`M9`, `AP`)
have no counterpart in the QRC technology file, which was built from the typical ICT for this stack, under a different naming
convention.

**This is a name-mapping problem, not a missing-collateral problem**, and the
fix is a documented one-file input: the `extract_rc_lef_tech_file_map`
attribute (`tempusCUI/extract_rc_Category_Attributes.html`) takes a LEF-layer →
tech-file-layer map. Deriving it needs the QRC deck's own layer list, which is
a `qrcTechToRcx` / `qrcui` query against the deck — mechanical, an hour or two,
**no decision required**. It is item **A9** in §1(a).

Worth noting for whoever picks it up: a sibling investigation hit the same
class of defect from the other end — see `35-drc-layer-map-blindness.md`. A
layer map that is wrong rather than missing fails silently in both tools.

### 5.4 The first signoff STA numbers ever produced on this design

Produced **before** extraction was working, so these are the design's own
stored parasitics, SI off. **They are not yet the signoff number** — they are
the first independent measurement, and they already disagree with the in-flow
result substantially:

| | Innovus in-flow (`full-20260814`) | **Tempus** (no QRC, SI off) |
|---|---|---|
| Setup WNS | −0.715 | **−0.368** |
| Setup TNS | −354.123 | **−60.572** |
| Setup FEP | 1429 | **462** |
| `reg2reg` FEP | 1299 | **421** |
| `ClockGate` FEP | 130 | **41** |
| max_transition FEP | 72 | 59 |

Tempus is reporting roughly **a third** of the failing endpoints and **half**
the WNS. Do not bank that yet — SI is off (removes crosstalk pessimism) and
extraction had failed (so parasitics are not signoff-grade), both of which bias
optimistic. But it is now clear that **the 1444/−0.759 figure is a
tool-and-setup artefact as much as a design property**, and the true signoff
number needs the corrected run before anyone plans work against it.

Also measured: the loaded database has **66 clocks**, not the 33 the SDC
defines. That gap is unexplained and worth ten minutes in the morning — the
gate flags it rather than quietly accepting either number.

### 5.5 The coverage hole, measured for the first time

`report_analysis_coverage`, setup/late side. This is the instrument that the
in-flow gates do not have, and it says the coverage problem is **much larger
than the "5 of 33 clocks" framing suggested**:

| Check type | Checks | Met | Violated | **Untested** |
|---|---:|---:|---:|---:|
| ClockPeriod | 42 | 4 (9 %) | 0 | **38 (90 %)** |
| DataCheckSetup | 69 | 0 | 0 | **69 (100 %)** |
| Library Clock Gating Setup | 6 004 | 2 961 (49 %) | 41 | **3 002 (50 %)** |
| PulseWidth | 169 686 | 120 151 (70 %) | 0 | **49 535 (29 %)** |
| Recovery | 43 399 | 40 558 (93 %) | 0 | **2 841 (6 %)** |
| Setup | 68 318 | 65 598 (96 %) | 421 | **2 299 (3 %)** |
| ExternalDelay (Late) | 15 | 7 (46 %) | 0 | **8 (53 %)** |
| Clock Gating Setup | 2 | 2 (100 %) | 0 | 0 |
| TimeBorrow | 1 | 1 (100 %) | 0 | 0 |

**≈57 800 timing checks are untested.** Points worth flagging specifically:

- **90 % of clock-period checks are untested.** Only 4 of 42 clocks have their
  period checked at all.
- **100 % of data checks are untested** — every one of the 69.
- **`ExternalDelay (Late)` has only 15 checks for 41 top-level port bits, and 8
  of those 15 are untested.** This corrects the optimistic reading in §3: the
  raw count of 48 `set_input_delay` / 30 `set_output_delay` statements in the
  SDC does **not** translate into I/O timing coverage. Interface timing is
  substantially unconstrained.
- The log also shows `TA-1018` warnings naming `D2D_TX_WORD_CLK_2/5/7` and
  siblings directly — the D2D word-clock source-latency hole is visible in the
  tool's own output, not just inferred.

None of these are *violations*. They are checks nobody has ever performed, and
they cannot be assumed to pass. Closing coverage will find real failures; the
462 figure above is a lower bound on a partially analysed design.

### 5.6 The gate is proved able to fail

Four gates were found on this project that could not fail. The failure modes
were always the same family: check internal consistency but never coverage;
set the budget to the day's number; treat a missing or unparseable report as
"nothing to complain about".

`sta_gate.py --selftest` mutates a known-good artefact set one property at a
time and asserts rejection. **20/20 mutants rejected, baseline passes:**

```
ok    baseline PASSES
ok    rejects: missing manifest                      [MANIFEST_MISSING]
ok    rejects: run did not finish                    [RUN_INCOMPLETE]
ok    rejects: a step failed                         [STEP_FAILED]
ok    rejects: CPPR off                              [CPPR]
ok    rejects: derate not re-issued (read_db trap)   [DERATE_MISSING]
ok    rejects: derate silently weakened              [DERATE_VALUE]
ok    rejects: an RC corner lost its QRC deck        [QRC_MISSING]
ok    rejects: SPEF truncated                        [SPEF_TOO_SMALL]
ok    rejects: clocks vanished between P&R and STA   [CLOCK_COUNT]
ok    rejects: setup view silently dropped           [VIEW_ABSENT]
ok    rejects: untested checks present               [UNTESTED_CHECKS]
ok    rejects: coverage report unreadable            [COVERAGE_UNPARSED]
ok    rejects: timing summary format drifted         [SUMMARY_UNPARSED]
ok    rejects: setup does not close                  [SETUP_FEP]
ok    rejects: hold does not close                   [HOLD_FEP]
                                     (16 of 20 shown)
```

Design rules, enforced by that self-test:

- **R1** Missing, empty or unparseable evidence is a **failure**, never a pass.
- **R2** Budgets come from a committed policy, never from the run being judged.
  A budget exactly equal to the measured value is reported as back-fitted.
- **R3** Coverage is checked separately from quality.
- **R4** The tool's exit code is never consulted — only artefacts.

R4 earned itself immediately: the first Tempus attempt printed
`STA COMPLETE` and **exited 0** having failed to load the design at all.

**The gate is expected to FAIL on today's design**, because the design does
not close timing. Budgets are set to what a signed-off chip must satisfy
(zero failing endpoints), not to today's numbers. A gate tuned to pass today
would be the fifth gate that cannot discriminate.

---

## 6. What it costs to close setup FEP ~1444 and hold FEP ~11

Measured from `full-20260814` (setup WNS −0.715 / FEP 1429; hold WNS −0.001 /
FEP 7) and the newer `fp1505` route (−0.759 / 1444; −0.021 / 11). The two
runs differ; both are in-flow numbers.

### The critical path is not a TideLink problem

Worst setup path, verbatim from the routed design:

```
Startpoint: …u_cpu_0…u_cortexm0plus_u_top_u_sys_u_core_fault_q_reg/CP
Endpoint:   …u_cpu_0…u_cortexm0plus_u_top_u_sys_u_nvic_event_q_reg/E
Clock: clk (10.000 ns)     Group: reg2reg
   Uncertainty: − 0.350      Cppr Adjust: + 0.163
   Data Path:   + 11.231     Slack: − 0.716
```

**The data path alone is 11.231 ns against a 10 ns period.** This is a Cortex-M0+
NVIC path — CPU and fabric, consistent with ~82 of ~100 logic levels sitting
outside TideLink. No amount of TideLink retiming touches it. Of 1429 failing
endpoints, 1299 are `reg2reg` and 130 are `ClockGate`.

### The levers, cheapest first

| Lever | Effect | Cost | Type |
|---|---|---|---|
| **Accept ≈93 MHz** | Closes setup **entirely**. WNS −0.715 on a 10 ns period ⇒ required period ≈10.72 ns ⇒ **93.3 MHz** | **Zero engineering.** No RTL, no constraints, no re-route | **D2 — your call** |
| **Re-budget clock uncertainty** | 0.350 ns is applied post-CTS on ~30 clocks, on top of propagated latency *and* CPPR. Reclaiming 0.25 ns moves WNS to ≈−0.47 and removes a large share of the 1429 | Hours (constraint edit + one re-run) | **D4 — margin you are spending** |
| **Re-examine flat OCV** | The 1.05 late data derate costs ≈0.53 ns on an 11.2 ns path | Hours, but only defensible with AOCV/LVF data | **D5 + B2** |
| **Fix hold** | Buffer-insertion ECO. Hold does **not** scale with period, so it is orthogonal to D2 | Hours of P&R | Autonomous *once* §4.5 is fixed |
| **Physical/RTL work on the CPU+fabric paths** | The only route to 100 MHz at current margins | **Weeks.** Useful skew, restructuring, possibly RTL pipelining in vendor CPU integration | Last resort |

### The honest caveats on that estimate

0. **There is no trustworthy pre-layout baseline to compare against** (§4.6).
   The legacy flow synthesised against `ZeroWireload`; the toolkit run fell
   back to generic PLE. So the ~0.7 ns shortfall cannot be attributed between
   "the RTL was always this slow" and "layout cost us". That attribution
   matters for choosing between the levers above, and getting it needs a
   correctly-constrained synthesis run, not an archaeology exercise on
   existing reports.

1. **The ≈93 MHz figure is a first-order inference**, valid for single-cycle
   same-clock `reg2reg` paths, which dominate here (1299/1429). Inter-clock
   and multicycle paths do not scale with the period identically. Tonight's
   Tempus run is the instrument to confirm it properly.
2. **Hold FEP 7–11 is not trustworthy yet.** With source latency covering 5 of
   33 clocks and none of the 16 D2D word clocks, the true hold count is
   *unknown* — and hold violations are the ones that cannot be fixed by
   slowing the clock. **§4.5 must be closed before any hold number is quoted,
   including a small one.** A small wrong number is more dangerous than a
   large one.
3. **The signoff number will not equal 1444.** Different extraction, different
   derate handling, SI off. Expect movement in both directions.

---

## 7. Recommended order of work

1. **D2 first.** The frequency decision changes the size of everything below it.
2. **Close §4.5** — source-latency coverage across all 33 clocks. Until then no
   hold number means anything, and no amount of STA tooling helps.
3. **A7** — unpack the corner-specific QRC decks, wire one per RC corner.
4. **D7** — one decision on the `-divide_by` class, then apply it three times.
5. **D3/D4/D5** — corners and margin, together, since they trade against each other.
6. **D6/B3** — SI, once the rest is stable.

---

## 8. Reproducing this

```bash
cd ASIC/sta
python3 sta_gate.py --selftest                 # 20/20, proves the gate can fail
python3 make_sta_mmmc.py \
    --db ../eth-chiplet/build/full-20260814/work/nanosoc_eth_chiplet_pads_routed \
    --out work/mmmc_sta.tcl
./run_sta.sh                                   # Tempus; no Innovus licence
python3 sta_gate.py --reports reports          # expected: FAIL, design does not close
```

`run_sta.sh` defaults to the completed `full-20260814` route and **refuses**
`fp1505`-style live routes (any DB with files younger than 20 minutes),
because reading a database that is still being written produces corruption
reports that look exactly like design bugs.
