# B8 — scoped run plan: un-black-boxing `axi_chiplet_controller`

**Date:** 2026-08-17 · **Status:** PLAN — the SpyGlass B8 run has **not** been executed
**Predecessors:** `CDC_B7_BASELINE.md`, `CDC_B7_ROUND2.md` (neither modified)
**Reads:** `docs/tapeout/24-d2d-link-physical-handover.md` §7

---

## 0. THE RECOMMENDATION, UP FRONT

**Do not fund B8 to answer the ICG question. B8 cannot answer it — not because it is
expensive, but because the hazard does not exist in the RTL that SpyGlass reads.**

The alternative in §6 was investigated as instructed. It did more than look promising:
**it was run, it terminated, and it returned an answer.** The hazard is CONFIRMED, it is
larger than `docs/tapeout/24` describes, and it cost no licence and no triage.

| | |
|---|---|
| **The hazard** | **CONFIRMED PRESENT** in the tapeout netlist |
| Instances | **36** integrated clock gates on `WavMultibitSync` ping-pong mailboxes whose enable is a raw register from the other clock domain, gating **174** flops. Plus **32** on the replay-FIFO memories (752 flops) that are a *related but lower-severity* class — §6c |
| `docs/tapeout/24` said | one instance, on the a2l mailbox. It understates by ~36× |
| Cost of the answer | **~1 hour**, zero licences, zero triage, no tool run |
| Method | read the already-existing gate netlist (`scripts/cdc/icg_enable_domain_audit.py`) |
| What B8 would have added | the RTL shadow of the hazard (`rptr` as an unsynchronised crossing), buried in a report that also grows by an estimated 60–110 new findings |

**Fund instead:** the §7 mitigation (a three-line Genus change, costed below) and a
re-synthesis to prove it took. Book B8 itself as a separate, later, *coverage* exercise
with its own justification — it has one, but it is not this one.

---

## 1. The question B8 was to answer, and why B8 is the wrong instrument

`docs/tapeout/24-d2d-link-physical-handover.md:206-222` records that Genus converted the
mailbox's RTL enable `if (we && ~rptr)` into an integrated clock gate whose enable is
`rptr` — a register from the **other** clock domain, used raw. A `CKLNQD1` is glitch-free
only if its enable meets setup/hold to its low-phase latch; an asynchronous enable cannot.
On violation the ICG emits a runt pulse, and a runt pulse does not clock a multi-bit bank
atomically — a subset captures, the rest hold. **That is a torn word.** On FPGA the same
RTL maps to an `FDRE` **CE pin**, a data input, where a marginal enable resolves per-flop
and cannot produce a partial clock edge. The hazard is ASIC-only.

Prior analysis had already established the complementary point: a CDC tool would **not**
have caught the a2l self-latch itself, which is a liveness bug in a single-clock
expression. The ICG hazard was the part that looked genuinely structural and genuinely
catchable — hence B8.

### Why a CDC tool cannot catch it either

**There is no clock gate in the RTL.** `WavMultibitSync_18.v` describes a plain
synchronous enable inside an `always @(posedge w_clk)` block. The `CKLNQD1`, the latch,
and the enable's setup relationship to the low phase are all created by `syn_generic`.
SpyGlass reads RTL. It cannot report a cell that the source does not contain.

This is not a configuration problem that a better `.sgdc` would fix. Three independent
confirmations:

1. **The rule that covers this hazard is not in the goal B7/B8 uses.** The installed rule
   reference (`SPYGLASS_HOME/doc/policy_guides/SpyGlass_ClockResetRules_Reference.pdf`)
   defines exactly two relevant rules:
   - `Clock_glitch02` — *"Reports clocks that are gated without latching their enable
     signal properly … the enable signal is not latched in the inactive half of clock
     cycle."*
   - `clock_glitch07` — *"Flags safe and unsafe clock gating structures … an enable signal
     with no clock domain information is merging with a clock. Therefore, it is considered
     as an unsafe clock gating … reports the violation with ERROR severity."*

   Neither appears in `GuideWare/2021.09-EarlyAdopter/soc/initial_rtl/cdc/cdc_verify_struct.spq`,
   the goal B7 ran and B8 would inherit. That file runs `Clock_glitch05` only
   (`:223`). Both live in the `clock_reset_integrity` goal instead.

2. **The goal already sets the parameter that would arm the check, and it is inert
   without the rule.** `cdc_verify_struct.spq:236` reads
   `-clock_reduce_pessimism=latch_en,mux_sel_derived,check_enable_for_glitch,ignore_same_domain`.
   Per the rule reference, `check_enable_for_glitch` exists precisely *"to enable the
   `Clock_glitch02` rule to check for the enable condition of a CGC cell. If you do not
   specify this value, only structure correctness of a CGC cell is checked."* The setup
   is configured for a check it does not run.

3. **Even with both rules added, they would find nothing at RTL**, because they fire on
   *gated clocks*, and the mailbox in RTL has no gated clock. `Clock_glitch02` explicitly
   scopes to *"a clock signal gated by using the normal AND/OR/NOR/NAND gate"*.

**The most B8 could produce is the RTL shadow:** `rptr` reported as an unsynchronised
crossing into the mailbox write path, most likely as `Ac_unsync01`, indistinguishable in
the report from the other ~100 Wlink crossings and carrying no information about whether
a clock gate was built. That is a true statement, but it is not the decision the tapeout
needs, and it is not worth the schedule risk in §4.

---

## 2. The exact `.prj` / `.sgdc` delta — if B8 is funded for its own reasons

### 2a. `.prj` — one token, and the file already says so

`cdc/nanosoc_eth_chiplet.prj:117-120`:

```tcl
set_option stop_module {axi_chiplet_controller \
                        xhb500_ahb_to_axi_bridge_chiplet_slv \
                        xhb500_axi_to_ahb_bridge_chiplet_mst \
                        rf_01k rf_08k rf_16k rf_32k}
```

Delete the token `axi_chiplet_controller`. The block comment at `:96-107` pre-authorises
exactly this and nothing else.

### 2b. That comment is over-optimistic, and this is the part to budget for

`cdc/nanosoc_eth_chiplet.prj:100-101` claims *"Nothing else changes — the §7a
`abstract_port` block becomes inert."* The first clause is false. Evidence from the
tapeout netlist, which is the only place the controller's internal clocking is visible
today:

| Clock root inside the elaborated controller | Flops it drives | Declared in `cdc/nanosoc_eth_chiplet.sgdc` today? |
|---|---:|---|
| `user_hsclk` | 5,263 | yes — as `user_ref_clk` (`:225`), at top scope |
| `phy_link_rx_rx_link_clk_o` | 2,757 | only as the **black-box port** `link_rx_clk_o` (`:663`) |
| `phy_link_tx_tx_link_clk` | 1,451 | **NO — no clock object anywhere in this flow** |

(9,471 flops in the `Wlink` module itself; 12,952 across its whole 724-module cone.)

`phy_link_tx_tx_link_clk` is the TX **word** clock, generated inside the PHY. Its absence
is already on the record — `docs/tapeout/24` §9 item 1 is "declare RX **and** TX word
clocks", still open. Un-black-boxing without declaring it hands SpyGlass 1,451 flops on an
undeclared clock, which it will either infer or default. Per `CDC_B7_BASELINE.md` §1,
the B7 run's cleanliness signal was *"No clock failed to bind and no inferred or virtual
clocks were created"*. B8 forfeits that unless the declaration is written first.

**Therefore the honest `.prj`/`.sgdc` delta is three changes, not one:**

1. `.prj:117` — remove `axi_chiplet_controller` from `stop_module`.
2. `cdc/nanosoc_eth_chiplet.sgdc` §1 — add a `clock` object for the TX word clock, with a
   period derived the same way `link_rx_clk_o` was (`:663-666` records `160.0 = 16 × 10.0`
   against `ASIC/genus-innovus/inputs/tidelink_constraints.sdc:124-125`). Confirm the
   divide from RTL before writing it; do not infer it from the RX side.
3. `cdc/nanosoc_eth_chiplet.sgdc` §7a — the ~250 `abstract_port` lines (`:632-906`) do go
   inert, but the two `clock` declarations in that block (`app_clk` at `:650`,
   `link_rx_clk_o` at `:663`) do **not**: they sit under `current_design
   axi_chiplet_controller` and will now resolve against a real elaborated module. Re-verify
   both bind, rather than assuming.

**Do not delete §7a.** `CDC_B7_ROUND2.md` §4d turns on it: findings 32/33
(`hresetn`/`poresetn`) were deliberately left unconstrained because two `abstract_port`
lines would have collapsed a real multi-domain reset question. Once the module is
elaborated those findings resolve honestly — which is the single best *coverage* argument
for B8 — and §7a becomes the record of what was asserted before. Comment it out with a
dated note; do not remove it.

### 2c. Can `tidelink/cdc/axi_chiplet_controller.sgdc` be composed in? **No — and it is the wrong shape anyway**

The file exists (365 lines) and was reconciled to the RTL on 2026-08-17 by
`scripts/cdc/sgdc_port_drift.py` (179 of 206 ports declared, zero stale). It is good work.
It is still not reusable here, for three reasons the two files already document
themselves:

1. **It is a black-box constraint file.** Every one of its ~120 declarations is an
   `abstract_port`, and `cdc/nanosoc_eth_chiplet.prj:82-83` states the semantics: SpyGlass
   applies port constraints only to stopped or undefined units. Reading it into a run where
   the module is elaborated makes the entire file inert. It solves the problem B8 removes.
2. **It carries a contradictory period set.** `cdc/nanosoc_eth_chiplet.prj:65-72` gives the
   reason this project reads ONE sgdc: the TideLink files declare `hclk 4.0` and
   `link_rx_clk_o 64.0` against this build's `10.0` and `160.0`. `cdc/nanosoc_eth_chiplet.sgdc:663-670`
   spells out the same divide-by-16 reached from two different base clocks. Composing them
   puts two period sets in one run.
3. **Its build-conditional block would be fatal here.** `axi_chiplet_controller.sgdc:270-305`
   deliberately omits `obs_epoch_anchored_o`, `obs_epoch_span_o`, `xhb_sub_obs_word_i`
   because its default flow does not define `TIDELINK_PHY_V2`. This flow does
   (`.prj:50-53`). The two files are each correct for their own default build; that is why
   the constraint lives in the chiplet file.

**What IS reusable is its evidence, and it is worth taking.** Its §(f) cross-check records
that 69 ports are declared in both files with **zero domain disagreements** — two
independent derivations agreeing. And its "NOT YET CONSTRAINED" block (`:305-365`) is a
ready-made worklist of what B8 must establish from RTL: `pad_clk_tx` flagged **OPEN, no
clock object anywhere in this flow** at `:318-319`, which is independent confirmation of
the gap measured in §2b above.

**Verdict: compose in nothing; harvest the block file's OPEN list as B8's input worklist,
and run `scripts/cdc/sgdc_port_drift.py --only axi_chiplet_controller` first so the port
census is current before anything is deleted.**

---

## 3. Realistic expected finding count

**Estimate: 60–110 new deduplicated findings, of which 5–15 are likely REAL.
This is an estimate. Here is exactly what it is based on, so you can discount it.**

### The evidence

**(a) TideLink's own block-level waiver file is the strongest single input.**
`tidelink/cdc/waiver.swl` is 118 `waive` statements — 108 design-unit scoped, 21
rule-scoped. Its generation note at `:95-96` states: *"104 vendor modules in these
namespaces, 82 waived below, 22 withheld (locally modified), 1 locally authored."*

That is a direct measurement of how much of the Wlink hierarchy produced findings someone
felt obliged to suppress at block level. B8 inherits **none** of it: `cdc/waiver.swl`
contains zero `waive` statements and `CDC_B7_ROUND2.md` §1 keeps it that way on
purpose. **So B8 surfaces, at chiplet level, everything those 82 design-unit waivers
currently hide at block level — plus the 23 that were never waived.**

**(b) The 23 unwaived units are the ones that will matter.**
`waiver.swl:176-219` lists them under *"DELIBERATELY NOT WAIVED — locally modified, so the
vendor justification does not apply. If any of these reports a CDC violation it is a
finding about SoC Labs logic and must be read, not suppressed."* It includes
`WavMultibitSync_18`, `WlinkGenericFCReplayAddrSync_18`, `WlinkGenericFCReplayV2_12`/`_13`
(carry the a2l fix) and `_1`/`_3`/`_5` (**fix NOT ported**), the five `WlinkGenericFCSM`
variants, and `wlink_wlink_ptp_tl_a2l_48x4` (SoC-Labs-authored, no vendor original).

**(c) Scale of what enters the analysis.**

| | |
|---|---:|
| `local_overrides/axi_chiplet_controller.sv` | 6,853 lines |
| Wlink dependency RTL in the ASIC flist | 100 files, 26,128 lines |
| Controller-subtree files in `build/chip/flist/tidelink_asic.flist` | 93 |
| Post-synth flops in the controller cone (netlist-measured) | ≥12,952 of 58,620 = **22%** |
| Modules in that cone | 724 |

**(d) The B7 calibration point.** 597 source files and 212,065 flat instances produced 885
messages → 152 crossings → 50 findings → 37 after the round-2 declaration fixes, of which
**10 REAL**. Runtime 48 s, 1.93 GB.

### The arithmetic

Adding ~22% more flops, concentrated in a block that is *entirely* multi-clock (three
clock roots, all crossing) rather than the mostly-single-clock SoC around it, should not
scale linearly — it should scale worse. Taking B7's ratio (50 findings / 212k instances)
and weighting ×2–3 for crossing density gives **60–110 findings**. Taking B7's REAL rate
(10 of 37, 27%) but discounting heavily because much of the Wlink set is genuinely
vendor-synchronised and *was* waived for a reason gives **5–15 REAL**.

### Confidence, stated honestly

- **Reasonably confident in the order of magnitude** (tens, not hundreds or thousands),
  because the black box is 22% of a design whose full report was 50 findings.
- **Not confident in the split.** B7 taught the opposite lesson twice: the baseline called
  26 findings "setup artefact" and round 2 reclassified 5 of them as REAL
  (`CDC_B7_ROUND2.md` §0), and the baseline's flagship prediction — "one declaration
  retires 33 crossings" — **retired zero** (§3c). Predictions about this report's
  composition have a poor track record in this project.
- **The floor is more reliable than the estimate.** At minimum B8 produces findings on the
  23 unwaived locally-modified units, and resolves baseline findings 32/33 honestly.
- **Runtime is not the risk.** B7 structural took 48 s; B8 should be minutes. The cost is
  entirely triage. B7's own §5 records 3 min 42 s of *agent* wall-clock for 50 findings
  with the RTL pre-indexed, and immediately caveats that a human doing the same
  adjudication would be slower and that the RTL evidence lookups do not compress.

---

## 4. The targeted greps — what to search the output for

If B8 runs, these are the searches that bear on the ICG question. **Read §1 first: the
expected result of every one of them is a miss, and a miss is not evidence of safety.**

### 4a. Rules that must be ADDED before any of this is meaningful

`cdc/cdc_verify_struct` does not run the two relevant rules. Add to the run-local `.prj`
or switch goal:

```tcl
-rules Clock_glitch02   ;# clocks gated without latching the enable properly
-rules clock_glitch07   ;# safe vs UNSAFE clock gating structures; unsafe = Error
```

`check_enable_for_glitch` is already in `clock_reduce_pessimism`
(`cdc_verify_struct.spq:236`), so no parameter change is needed. Consider also
`-report_all_clockgate_enables=yes` (a `Clock_glitch02` parameter, default `no`) which
*"reports all the enable nets that are directly merging with a clock signal"* — the
closest thing to a census the RTL flow can produce.

### 4b. The searches

| # | Search | What a HIT means | What a MISS means |
|---|---|---|---|
| 1 | `grep -E 'Clock_glitch02\|clock_glitch07' <reports>/*.rpt` | SpyGlass found a gating structure with a foreign-domain or unlatched enable. Cross-check the instance against §6's netlist list | **Expected.** Proves nothing — the RTL has no gate. Do NOT record as clean |
| 2 | `grep -iE 'WavMultibitSync(_3\|_15\|_18)?' <reports>/*.csv` | the mailbox primitive is producing findings. `_18` is the a2l variant and is **not** waived at block level | the mailbox produced no crossing — worth a second look, since `rptr` genuinely is one |
| 3 | `grep -iE 'WlinkGenericFCReplay(AddrSync\|V2)' <reports>/*.csv` | the replay path is reporting. Split `V2_12`/`_13` (carry the a2l fix) from `V2_1`/`_3`/`_5` (**fix not ported**) — a difference in their finding sets is itself the result | the replay path is silent under a structural goal |
| 4 | `grep -E 'rptr\|wptr' <reports>/clock-reset/Ac_unsync0*.csv` | **the RTL shadow — this is the realistic best case.** `rptr` crossing into the `w_clk`-domain mem write is real and should appear | the tool accepted the crossing as qualified. Check the "reason" column, not just presence |
| 5 | `grep -E 'link_addr_to_app_clk\|fifo_addr_to_tx' <reports>/*.csv` | the specific mailbox instances by their Chisel-generated names | — |
| 6 | `grep -c 'Ac_unsync0[12]' <reports>/*.csv` before/after | the headline crossing delta vs B7's 137 | — |

### 4c. Instance and module names to filter on

Established from the tapeout netlist, so these are the names that actually exist:

- **RTL / SpyGlass names:** `WavMultibitSync`, `WavMultibitSync_3`, `WavMultibitSync_15`,
  `WavMultibitSync_18`; `WlinkGenericFCReplayAddrSync{,_3,_15,_18}`;
  `WlinkGenericFCReplayV2_{2,4,8,10,12}` (the five that survive to the netlist).
- **Signal names inside them:** `rptr`, `wptr`, `mem_0`, `mem_1`, `we`,
  `rptr_wclk_demet_io_out`, `wptr_rclk_demet_io_out`.
- **Netlist instance-path fragments:** `link_addr_to_app_clk_addrsync_`,
  `fifo_addr_to_tx_addrsync_`, `_a2l_fc_replay_`, `_l2a_fc_replay_`,
  `axi2wl_wlink_axi{aw,w,b,ar,r}FC_`, `tl2wl_wlink_tidelinktl_`.

**One trap, measured:** filtering ICG *instance names* on `addrsync` returns 16 of the 36
mailbox gates, because Genus dropped the hierarchical prefix on
`WlinkGenericFCReplayV2_4`'s two (plain `cg_RC_CG_HIER_INST499/500`) and on others in the
ungrouped `Wlink` top. Their *enable nets* still carry
`link_addr_to_app_clk_addrsync_`. **Filter on nets, not instance names** — or use the
domain-based audit in §6, which compares clock roots and does not depend on naming at all.

---

## 5. The stopping rule

**B8 is scoped to one question. These are the conditions to stop, in priority order.
Any one of them fires and the run is declared finished — not triaged, finished.**

### Stop conditions (measurable)

| # | Condition | Then |
|---|---|---|
| **S1** | **The §6 gate-level check has already answered the ICG question.** | **This condition is ALREADY MET as of 2026-08-17** (§6). B8 stops before it starts, for this purpose. |
| S2 | `Clock_glitch02` + `clock_glitch07` are added and both return zero rows on the Wlink hierarchy | Question answered *negatively at RTL*, which §1 predicts. Record the null result **with §1's explanation attached**, and stop. Do not open a second front. |
| S3 | Searches 2–5 of §4b have been run once, and every hit either (a) names a module in the §6 netlist list, or (b) has been classified into one of B7's nine mechanism groups | Stop. Everything unclassified goes to §7's backlog **unread** |
| S4 | 4 hours of triage wall-clock elapsed | **Hard stop.** Write what is known, book the rest. B7 triaged 50 findings in under 4 minutes of agent time with pre-indexed RTL; if B8 is still open after 4 hours it has become a signoff exercise |
| S5 | The report grows past ~150 deduplicated findings | Stop and re-scope. Beyond the §3 estimate the run is measuring the SGDC, not the design — exactly what `CDC_B7_BASELINE.md` §7 warns of ("A first run against a fresh SGDC is mostly measuring the SGDC") |

### What "stop" explicitly does NOT mean

- It does **not** mean adding declarations until the count falls. `CDC_B7_ROUND2.md` §0 is
  unambiguous: the count falling *"measures the setup converging on the design — nothing
  else"*. B8 must not repeat round 2 on a bigger report against a tapeout date.
- It does **not** mean writing waivers. `cdc/waiver.swl` has zero and B8 does not change
  that. `tidelink/cdc/waiver.swl:221-247` already removed the
  `-du axi_chiplet_controller` "safety net" for precisely this run, on the grounds that
  *"an inert waiver whose only live case is the wrong answer is worse than none."*
- It does **not** mean triaging `Ac_coherency06`, `Reset_sync04`, `Ac_conv01/02/04` or
  `Ac_glitch03`. Those were counted-not-triaged in B7 and B8 inherits that boundary.

### Definition of done

One paragraph appended to this file stating: (i) which rules ran, (ii) the hit/miss result
for each of the six §4b searches, (iii) whether the §6 netlist finding was corroborated,
contradicted, or invisible at RTL, and (iv) the new finding count with the un-triaged
remainder declared per §7. **No SGDC edits. No waivers.**

---

## 6. THE ALTERNATIVE — investigated, costed, and RUN. It answers the question.

**This is the most valuable section of this document.**

### 6a. Why it works

The hazard is a **synthesis artefact**, not an RTL property (§1). The artefact that
carries it already exists on disk:

```
ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_gate.v
  35,133,748 bytes · Genus 21.15-s080_1 · 2026-08-14 13:56
```

It is a hierarchical netlist: 3,029 module definitions, 58,620 flops, 3,002 integrated
clock gates (all `CKLNQD1`), 50,754 flops gated (86.58%) — the last three independently
confirmed by the flow's own `reports/syn_clock_gating.rep`, which the run already wrote
and nobody read.

### 6b. The method, and the one idea that makes it sound

Naively comparing an ICG's `ck_in` net name against its enable-source flop's `CP` net name
flags **1,187 of 1,556** — useless, because clock buffering renames the same clock. The
fix is to resolve both back through buffers/inverters/ICGs to a **clock root** before
comparing. That drops it to **179** — a real, reviewable number.

The second idea: walk backward from the enable through **combinational cells only** and
stop at the **first** sequential cell on each branch. If the enable had been resynchronised
into the gate's own domain, the first flop reached would be the last stage of that
synchroniser and would carry the ICG's own clock — so it would not flag. **A flag therefore
means the enable reaches a foreign-domain register with no intervening resynchronisation.**
That is the hazard, stated structurally.

Implemented as `scripts/cdc/icg_enable_domain_audit.py` (new, this change).

```bash
scripts/cdc/icg_enable_domain_audit.py \
    ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_gate.v \
    --filter 'addrsync|addr_to_tx' --coverage --live-only \
    --top nanosoc_eth_chiplet_pads --gate
```

### 6c. THE RESULT — the hazard is confirmed, and it is bigger than documented

| Class | ICGs | Flops behind them | Enable toggles |
|---|---:|---:|---|
| **`WavMultibitSync` ping-pong mailboxes** (the documented hazard) | **36** | **174** | **every transaction** |
| Replay-FIFO memories (`*_fc_replay_fifo_mem_cg_*`, RTL `wlink_WavFIFOMem`) | 32 | 752 | only on a config write — see below |
| Other (rmii/eth/ptp/Wlink misc — outside the B8 question, see §7) | 111 | — | not triaged |
| **Total flagged** | **179** | of 1,556 ICGs walked | |

**The 32 FIFO-memory gates are a genuinely different risk and must not be quoted with the
36.** Their foreign-domain enable is not a pointer — it traces to
`axi2wl_wlink_axi*FC_swi_data_id_1_reg[1]` and
`axi2wl_wlink_axi*FC_out_prepend_swi_disable_crc_reg`, both `user_hsclk`, feeding an ICG
on `phy_link_rx_rx_link_clk_o`. Those are APB-programmed **software-interface
configuration** registers. The structure is the same — a raw foreign-domain enable on an
ICG — but the exposure window is a *configuration write*, not every transaction. If
firmware writes `swi_data_id` / `swi_disable_crc` only before link-up, the practical risk
is near nil; if anything rewrites them on a live link (the SWI recalibration path is the
obvious candidate), it is real. **That is a firmware question this plan does not answer.**

The mailbox set, by domain pair:

| Gated clock | Enable sourced from | ICGs | Path |
|---|---|---:|---|
| `phy_link_tx_tx_link_clk` | `user_hsclk` | 12 | a2l — **the documented one** |
| `user_hsclk` | `phy_link_tx_tx_link_clk` | 12 | l2a return |
| `link_clk` | `app_clk` | 8 | `WlinkGenericFCReplayV2_{2,4,8,12}` |
| `user_hsclk` | `phy_link_rx_rx_link_clk_o` | 4 | RX-side |

A representative finding, verbatim:

```
[Wlink_USE_CLKBUF1h0_USE_T3A1h0_EPOCH_ANCHOR_EN1h0]
  ICG        : axi2wl_wlink_axirFC_a2l_fc_replay_link_addr_to_app_clk_addrsync_cg_RC_CG_HIER_INST1098
  gated clock: phy_link_tx_tx_link_clk
  ENABLE <-  axi2wl_wlink_axirFC_a2l_fc_replay_link_addr_to_app_clk_addrsync_rptr_reg
             clocked by user_hsclk
  gated flops: 6   e.g. \..._addrsync_mem_0_reg[0]
```

and the same structure in a hierarchical instance, where the two clocks are module ports
and the comparison is therefore exact:

```
[WlinkGenericFCReplayV2_8]                        (l2a, instantiated once inside Wlink)
  ICG        : link_addr_to_app_clk_addrsync_cg_RC_CG_HIER_INST582
  gated clock: link_clk
  ENABLE <-  link_addr_to_app_clk_addrsync_rptr_reg   clocked by app_clk
  gated flops: 6   e.g. \link_addr_to_app_clk_addrsync_mem_0_reg[0]
```

`DFCNQD1 \..._addrsync_rptr_reg` has `.CP(app_clk)`; the ICG has `.ck_in(link_clk)`. Two
different module ports. No inference involved.

### 6d. Corroborated in the RTL, and the RTL shows the fix is one line

`tidelink/src/rtl/local_overrides/WavMultibitSync_18.v` — the copy this build compiles
(`build/chip/flist/tidelink_asic.flist:109`; the other three variants come from `deps/`):

```verilog
:100   assign w_ready = ~(rptr_wclk_demet_io_out ^ wptr);   // SYNCHRONISED rptr — correct
...
:112     end else if (we) begin
:113       if (~rptr) begin            // <-- RAW rptr. This is the enable Genus gates on.
:114         mem_0 <= w_data;
:122       if (rptr) begin             // <-- and again
:123         mem_1 <= w_data;
```

**The synchronised copy already exists in the same module and is already used two lines
above.** `w_ready` uses `rptr_wclk_demet_io_out`; the slot select uses raw `rptr`. That is
exactly `docs/tapeout/24` §7 option 1 ("drive the mailbox slot-select from the
*synchronised* `rptr`"), and it is a same-file, same-module, one-identifier change.

Note also: this local override was created to fix a **reset-coherency** bug (its header
block at `:52-78`). It did not touch the slot select. **All four variants — `_18` and the
three `deps/` copies — carry the raw-`rptr` enable.**

### 6e. Cost, and honest limits

| | |
|---|---|
| **Cost** | **~1 hour, already spent.** No licence, no tool, no seat, no triage queue |
| Reproducible | yes — `scripts/cdc/icg_enable_domain_audit.py`, pure Python, ~90 s on the 35 MB netlist |
| Gateable | yes — `--gate` exits 1; §7 proposes wiring it into `ci/signoff.yaml` |

**Limits, which must travel with the number:**

1. **Coverage is 1,556 of 3,002 ICGs (51.8%).** The other 1,446 sit inside
   `cg_RC_CG_MOD*` wrappers — Genus cascaded/multi-stage gating — and are not walked. The
   mailbox question is unaffected (all 36 are in the walked set); a *design-wide* claim is
   not available from this run.
2. **The backward walk is module-local.** An enable arriving through a module input port
   has no driver in scope and the walk stops silently. This under-reports. It never
   over-reports in that direction.
3. **Cell classification is by name prefix**, tuned to TSMC65 `tcbn65lp`.
4. **A flag is structural, not a proven failure.** It says the enable is asynchronous to
   the gated clock. Whether it *violates* needs STA on the ICG enable pin — and per
   `ci/signoff.yaml:238` there is no signoff STA here, and per `docs/tapeout/24` §1 the
   word clocks are not fully in the timing graph anyway. **On this flow the violation
   cannot be measured, only the structure. That argues for mitigating, not measuring.**
5. **Provenance discrepancy, unresolved.** `docs/tapeout/24:209` quotes
   `eval_cg_RC_CG_MOD_355_16386`, but this netlist's gates are `cg_RC_CG_MOD_*` with no
   prefix — although `ASIC/genus-innovus/scripts/1b_synthesis_eval.tcl:194` sets
   `lp_clock_gating_prefix eval_cg`. Either doc-24 quotes a different run, or the prefix
   was added after 2026-08-14. **Greps must match both spellings** (`--icg-module-re`
   defaults to `^\w*cg_RC_CG_MOD`, which does).

### 6f. If a tool result is wanted anyway — the third option

SpyGlass CDC runs on **netlists**: `Clock_glitch02` documents a `report_instance_pin`
parameter *"to report the name of instance pin of a netlist design"*, and GuideWare ships
`soc/netlist_handoff/cdc/clock_reset_integrity.spq`, which **does** run `Clock_glitch02`.
Pointed at `nanosoc_eth_chiplet_pads_gate.v` with the library, that goal would see the
`CKLNQD1` cells and fire on them properly. This is a real option and strictly better than
B8-on-RTL for this question — but it needs a `.lib`/`.sglib` setup that does not exist
yet, so it is **more** expensive than §6b, not less. Book it only if an
independently-tooled confirmation is required for the record.

---

## 7. What goes in the backlog, declared not dropped

This repo declares coverage gaps in `ci/signoff.yaml`'s `unsupported:` block, where each
entry carries an `id`, a prose `reason`, and a `refuted_by` shell test that **passes only
once the gap is genuinely closed** (`ci/signoff.yaml:493` onward). The comment above that
block records that the mechanism found three stale declarations on the day it landed. Two
entries follow that pattern. **Both are proposals in this plan — `ci/signoff.yaml` is not
edited by this change.**

### 7a. Proposed `unsupported:` entry — the CDC coverage hole

```yaml
  - id: cdc-controller-internals
    reason: >
      axi_chiplet_controller is black-boxed (set_option stop_module,
      cdc/nanosoc_eth_chiplet.prj:117) in every CDC run this project has done.
      Roughly 6,850 lines of controller plus 26,100 lines of Wlink dependency
      RTL - 724 modules and at least 12,952 of the design's 58,620 post-synth
      flops, 22% - have never been through a CDC tool at chiplet level,
      including the a2l replay CDC and the recovered-RX-clock domain. Block
      level does not cover it either: tidelink/cdc/waiver.swl waives 82 of the
      104 Wav*/Wlink* design units by name, and its own header lists 23 more
      as locally modified and DELIBERATELY unwaived, i.e. never adjudicated
      anywhere. Separately, the TX word clock phy_link_tx_tx_link_clk (1,451
      flops) has no clock object in this flow at all, so un-black-boxing
      without declaring it would trade one gap for another.
    refuted_by: >
      grep -q 'stop_module' cdc/nanosoc_eth_chiplet.prj &&
      ! grep -A4 'stop_module' cdc/nanosoc_eth_chiplet.prj |
        grep -q 'axi_chiplet_controller'
```

### 7b. Proposed `unsupported:` entry — the ICG hazard, until mitigated

```yaml
  - id: icg-async-enable
    reason: >
      36 integrated clock gates in the tapeout netlist gate a WavMultibitSync
      ping-pong mailbox on an enable driven raw from a register in the OTHER
      clock domain, gating 174 flops. (32 more on the replay FIFO memories,
      gating 752, share the structure but are enabled from quasi-static SWI
      config registers - tracked separately, not covered by this entry.)
      A CKLNQD1 is glitch-free only if its enable meets
      setup/hold to the low-phase latch, which an async enable cannot; on
      violation it emits a runt pulse and tears the multi-bit word. This is a
      SYNTHESIS artefact - there is no clock gate in the RTL - so no RTL CDC
      run can see it, and SYN_CLOCK_GATING is on by default with no exclusion
      for these banks. Measured 2026-08-17 by
      scripts/cdc/icg_enable_domain_audit.py against
      ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_gate.v.
      Whether any instance actually VIOLATES cannot be established here: there
      is no signoff STA (see sta-signoff) and the word clocks are not fully in
      the timing graph (docs/tapeout/24 section 1). Structure is the only
      available evidence, which is why the fix is a directive and not a
      measurement.
    # One netlist, named explicitly: the script takes a single positional and a
    # glob over build/*/outputs would silently pass several. Re-point this at
    # the current run directory whenever the tapeout netlist is re-cut.
    refuted_by: >
      scripts/cdc/icg_enable_domain_audit.py
        ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_gate.v
        --filter 'addrsync|addr_to_tx' --live-only
        --top nanosoc_eth_chiplet_pads --gate
```

`--gate` exits 1 while any instantiated mailbox ICG has a foreign-domain enable and 0 once
the §8 mitigation lands, so the declaration retires itself on the evidence.

**A naming trap that this gate had to be built around**, recorded because it would
otherwise be rediscovered as a false pass: Genus does not always carry the hierarchical
prefix onto the ICG *instance* name. Two of the thirty-six mailbox gates are bare
`cg_RC_CG_HIER_INST499/500` inside `WlinkGenericFCReplayV2_4`, and an instance-name-only
filter silently reported 16 instead of 36 — a 56% under-count that looked like a clean
subset. The script therefore matches `--filter` against the instance name **or the enable
net**, and the enable net always carries the mailbox name. Verified: the filter above
returns 36 and exits 1.

### 7c. Un-triaged remainder, recorded here rather than silently dropped

| Item | Count | Status |
|---|---:|---|
| Flagged ICGs outside the mailbox/replay-FIFO classes (`rmii_to_mii` 9, `eth_receivecontrol` 2, Wlink misc ~100) | **111** | **NOT TRIAGED.** Outside the B8 question. Some are certainly benign (`rmii_to_mii` sits on a genuine MII boundary); none has been looked at |
| ICG instantiations not walked (inside `cg_RC_CG_MOD*` wrappers) | **1,446 of 3,002** | **NOT ANALYSED.** Cascaded gating stages; §6e limit 1 |
| Enables arriving through module ports | unknown | **UNDER-REPORT of unknown size**; §6e limit 2 |
| Whether any flagged ICG actually violates setup/hold | — | **UNMEASURABLE HERE**; §6e limit 4 |
| `Ac_coherency06` (41), `Reset_sync04` (14), `Ac_conv01/02/04` (24), `Ac_glitch03` (9) at chiplet level | 88 | Counted-not-triaged since B7; unchanged, inherited |
| B7 round-2 open items | 10 REAL + 8 owner-decision | Unchanged; see `CDC_B7_ROUND2.md` §7 |

---

## 8. The mitigation, now that the hazard is confirmed

`docs/tapeout/24` §7 lists three options. Establishing the mechanics for each:

### 8.1 Preferred — the RTL fix (§6d)

Drive the mailbox slot-select from `rptr_wclk_demet_io_out` instead of raw `rptr` in
`WavMultibitSync{,_3,_15,_18}.v`. The synchronised signal already exists in the module and
is already used for `w_ready` one line above. This removes the async signal from the ICG
enable **at source**, so no synthesis directive is needed and the fix survives any future
re-synthesis.

**Not this plan's to make** — `WavMultibitSync_18.v` is TideLink's, and the change alters
mailbox handshake timing by a cycle, which needs the owner's analysis and a sim. Requested
in the TideLink RTL handover. **Note the scope correction: doc-24 frames this as an a2l
fix; the measurement in §6c shows all four variants and both directions are affected.**

### 8.2 Interim, synthesis-side — EXACT MECHANICS

`docs/tapeout/24:228` suggests *"a targeted `set_clock_gating_style` exclusion or
`set_dont_touch`"*. **Neither is the right command in Genus.** The correct one, from the
locally installed attribute reference
(`$CDS_INSTALL/genus/doc/genus_attref/lps.html`, "Low Power Synthesis"):

> **`lp_clock_gating_exclude {false | true}`** — Default: `false`. Read-write **module**
> attribute. *"Determines whether to insert clock-gating logic for this module. If you set
> this attribute to true, no clock-gating logic is added to this module and all its
> submodules. **This attribute applies to all instances of this module.**"* Affects
> command: `syn_generic`.

The attribute also exists on `design`, `inst` and `hinst`. **The module form is the one to
use**, because the `inst`/`hinst` forms carry a trap the docs state outright: *"You can
only set this attribute on a unique instance… If a hierarchical instance is instantiated
multiple times, first use the `dedicate_module` command."* The mailbox modules are
instantiated many times; the module attribute sidesteps `dedicate_module` entirely.

**It is a synthesis attribute, not SDC and not a Tcl `set_*` command.** It must be set
**after `elaborate` and before `syn_generic`** — the same window
`ASIC/genus-innovus/scripts/1b_synthesis_eval.tcl:361-370` already uses for
`lp_clock_gating_min_flops` / `_max_flops`. Insert alongside those:

```tcl
# --- ICG exclusion on the Wlink ping-pong mailboxes -------------------------
# B8_SCOPED_RUN_PLAN.md section 6 / docs/tapeout/24 section 7.2.
# These banks' RTL enable is `we && ~rptr`, and rptr is a register from the
# OTHER clock domain. Genus turns that into a CKLNQD1 whose enable is async to
# ck_in; on a setup/hold violation it emits a runt pulse and tears the word.
# Excluding the module reverts the enable to a mux on the D pin, where a
# marginal enable resolves per-flop. Remove once the RTL fix (drive the slot
# select from rptr_wclk_demet_io_out) has landed upstream.
if {$EVAL_CLOCK_GATING} {
    try_step "mailbox ICG exclusion" {
        set n 0
        foreach m [get_db modules -if {.name =~ "*WavMultibitSync*"}] {
            set_db $m .lp_clock_gating_exclude true ; incr n
        }
        if {$n == 0} { die "no WavMultibitSync modules matched - name drift" }
        say "excluded $n WavMultibitSync module(s) from clock gating"
    }
}
```

The `die` on zero matches is load-bearing: a silently-matching-nothing `foreach` is exactly
how this mitigation would appear to be in place while doing nothing.

**Cost:**

| | |
|---|---|
| Flops that lose clock gating | **174** of 50,754 gated = **0.34%** |
| Expected power delta | negligible. `reports/syn_clock_gating.rep` puts average toggle saving at 89.62% on gated flops; losing 174 of them is within noise |
| Area | small increase — each bank regains a recirculation mux on D |
| Timing | a mux delay added to the mailbox D path; these are 4–6-bit banks, not a critical path (`docs/.../tidelink-critical-path-is-cpu-plus-fabric` records ~82 of ~100 levels are outside TideLink) |
| Flow cost | **one re-synthesis**, and everything downstream of it |
| Reversibility | full — one `if` block |

**Do NOT bundle the 32 replay-FIFO-memory ICGs into this change.** Their RTL module is
`wlink_WavFIFOMem` (`:32`, `if (wclken & ~wfull)`), waived as unmodified vendor IP at block
level (`tidelink/cdc/waiver.swl:164`), and their foreign-domain enable is a quasi-static
SWI config register rather than a per-transaction pointer (§6c). Excluding them would cost
752 flops of gating — 1.5% of the design's gated flops, 4× the mailbox fix — to close a
window that may not open at all. **Resolve the firmware question first** ("is
`swi_data_id` / `swi_disable_crc` ever written on a live link?"). If the answer is yes,
add `*WavFIFOMem*` to the same `foreach` and re-cost. If no, declare it in §7 and leave it.

**A risk to verify, not assume.** The flow sets no `auto_ungroup`, so Genus's default
applies, and the netlist shows heavy ungrouping (the a2l mailboxes were dissolved into the
`Wlink` top module while the l2a ones stayed hierarchical). The module attribute is
consumed by `syn_generic`, which is also where ungrouping happens. **Prove it took** — do
not infer it:

```bash
# after re-synthesis, must print 0
scripts/cdc/icg_enable_domain_audit.py <new>_gate.v \
    --filter 'addrsync|addr_to_tx' --live-only --top nanosoc_eth_chiplet_pads --gate
```

`reports/syn_clock_gating.rep`'s "Total Gated Flip-flops" should also drop by ~174, and
"Register bank width too small" or an equivalent ungated bucket should rise
correspondingly.

**What NOT to do:** raise `lp_clock_gating_min_flops` above 6 to starve these banks. The
mailboxes are 4–6 bits, so a threshold of 7 would exclude them — and would simultaneously
ungate every other narrow bank in a 58,620-flop design. `1b_synthesis_eval.tcl:363` sets it
to 4 today. Do not touch it.

### 8.3 Third option — same clock tap

`docs/tapeout/24:230-232` notes `wptr_reg` and the `mem_*_reg` bits are on different taps
(`wptr_reg` ungated, data bits behind the ICG on a different replica). §6c confirms it:
`..._addrsync_wptr_reg` has `.CP(link_clk)` directly, while `mem_*_reg` sit on
`..._addrsync_cg_rc_gclk`. **§8.2 resolves this as a side effect** — removing the gate puts
every bit of the mailbox back on one tap. No separate action needed if §8.2 lands.

---

## 9. Provenance and the limits of this plan's own evidence

Everything asserted here was measured on 2026-08-17 against this working tree, or read
from a locally installed tool document. Nothing is quoted from memory.

| Claim | Source |
|---|---|
| ICG hazard confirmed, 36 mailbox + 32 FIFO instances | `scripts/cdc/icg_enable_domain_audit.py` over `ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_gate.v` |
| 3,002 ICGs / 58,620 flops / 86.58% gated | the flow's own `ASIC/eth-chiplet/build/full-20260814/reports/syn_clock_gating.rep`, agreeing with the script's independent count to within one flop |
| `Clock_glitch02` / `clock_glitch07` semantics; `check_enable_for_glitch` | `SPYGLASS_HOME/doc/policy_guides/SpyGlass_ClockResetRules_Reference.pdf` |
| Neither rule is in the B7/B8 goal | `SPYGLASS_HOME/GuideWare/2021.09-EarlyAdopter/soc/initial_rtl/cdc/cdc_verify_struct.spq` |
| `lp_clock_gating_exclude` semantics and object classes | `$CDS_INSTALL/genus/doc/genus_attref/lps.html` |
| Raw `rptr` in the slot select | `tidelink/src/rtl/local_overrides/WavMultibitSync_18.v:100,113,122` |
| Which mailbox copy compiles | `build/chip/flist/tidelink_asic.flist:107-110` |
| 82 waived / 23 unwaived Wlink units | `tidelink/cdc/waiver.swl:95-96,176-219` |
| Clock roots and flop counts inside the controller | netlist traversal, same script's resolver |

### What this plan did NOT do

- **The SpyGlass B8 run was not executed.** No licence was taken; no seat was held.
- `cdc/*.{prj,sgdc,swl}`, `verif/**`, all SDC files and all submodules are **unmodified**.
  `ci/signoff.yaml` is **unmodified** — §7's entries are proposals.
- This change adds exactly two files: this plan and `scripts/cdc/icg_enable_domain_audit.py`.
- **No re-synthesis was run**, so §8.2 is costed but not proven. The `--gate` command in
  §8.2 is how it gets proven.
- The 111 non-mailbox flagged ICGs were **not** triaged (§7c).

### One correction to the record

`docs/tapeout/24-d2d-link-physical-handover.md` §7 describes the hazard as a single ICG on
the a2l mailbox. The measurement in §6c finds **36 mailbox ICGs across both directions and
four domain pairs, plus 32 on the replay FIFOs**. The mechanism doc-24 identified is
correct in every particular; its **scope** is understated by roughly 36×. §8.2's module-
scoped exclusion covers all of them, so the fix does not change — but the risk assessment
should.
