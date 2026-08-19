# C2 — the D2D transmit clock group: the two options, priced

**Status:** the decision is OPEN. Both options exist as validated patches under
`ASIC/genus-innovus/inputs/patches/`; neither has been applied. **Date:**
2026-08-17.

Every number here was measured on this host today, against
`ASIC/eth-chiplet/build/full-20260814` and the current working tree. Where a
measurement contradicts something already written in the tree, the contradiction
is called out rather than quietly fixed.

---

## 0. The finding, in one paragraph

`ASIC/genus-innovus/inputs/constraints.sdc` puts `D2D_TX_CLK_0` and
`D2D_TX_WORD_CLK_0..7` in a `set_clock_groups -asynchronous` group of their own,
against `$EXTCLK`. They are not asynchronous to it — they are generated from it.
The pad wrapper aliases `user_ref_clk` onto the `sys_fclk` pad, so the whole
Wlink transmit chain hangs off the `CLK` pad. The group therefore false-paths a
boundary the timer can see is synchronous, and it does so silently.

---

## 1. The evidence, and why it is not arguable

**The tool's own resolution, exhaustively.** From
`build/full-20260814/logs/pnr_qor_after_opt_design_post_cts.rep`:

| | lines | resolving to `clk` | resolving to anything else |
|---|---|---|---|
| `D2D_TX_*` (9 clocks × 3 views) | 27 | **27** | **0** |
| `D2D_RX_*` (16 clocks × 3 views) | 48 | **0** | 48 (all `D2D_RX_CLK_0`) |

Receive is the control experiment. `D2D_RX_CLK_0` is a `create_clock` on the
`TL_CLK_RX` pad — an off-die clock from the peer die — and its word clocks
correctly resolve their own master. The RX group is right. Only the TX group
asserts asynchrony against a clock it is generated from.

**Objection, and its answer.** The 08-14 run had the TX word clocks anchored on
`$WL/pad_clk_tx`, which drew 24 `TA-1018` "source latency path cannot be found"
warnings, and the tool then fell back to interpreting the master from the source
pin's polarity. Does that make the 27 lines an artefact of the broken anchor?
No. `pad_clk_tx` and `user_hsclk` both trace back to the same `CLK` pad, so the
master is `clk` either way. The `-source` correction of 2026-08-17 (now
`$WL/user_hsclk`) changes *how* the trace is made, not *where it ends*.

**The netlist says it more plainly than the timer does.** Inside the
synthesised Wlink, the two "domains" that each `a2l` flow-control replay buffer
synchronises between are clocked by `user_hsclk` and `phy_link_tx_tx_link_clk` —
and `phy_link_tx_tx_link_clk` is `user_hsclk` divided by 16. `user_hsclk` is
also the same physical net as the Wlink's `app_clk`, because `tidelink_top`
wires `.app_clk(hclk)` and this SoC's `hclk` is `sys_fclk`. Genus merged them
into one net. The RTL builds a demet pair across a boundary that, on this die,
is one net and its own divider.

---

## 2. What the cut is hiding — measured

| quantity | value | source |
|---|---|---|
| flops on the TX word clock (structural, synthesised Wlink) | 1451 | gate netlist fan-in |
| flops in the `D2D_TX_WORD_CLK_0` CTS tree | 1495 | `reports/cts_clock_trees.rep` |
| endpoints capturing **from** `clk` | **1003** | gate netlist fan-in |
| endpoints launching **into** `clk` | **181** | gate netlist fan-in |
| **total newly timed if the groups merge** | **1184** | |
| demet (synchroniser) instances under the Wlink | 176 | `reports/syn_hierarchy.rep` |
| of those, on the `clk` ↔ TX-word boundary | 69 | `.CP` net of each `f1` flop |

Two corrections to the `[C2]` block's own framing, both worth having:

- **"~2k flops"** is the right order but the wrong quantity. 1451 flops sit in
  the domain; 1184 endpoints are actually exposed by the merge.
- **Only `D2D_TX_WORD_CLK_0` matters.** `phy_link_tx_tx_link_clk` is driven from
  `gpiotx_0` alone (`WavD2DGpio_v2.v:1961`). `D2D_TX_WORD_CLK_1..7` clock only
  per-lane serialiser flops and have no `clk`-domain fan-in. CTS agrees: it built
  exactly one transmit word-clock tree.

---

## 3. Option A — merge the transmit clocks into the `$EXTCLK` group

`ASIC/genus-innovus/inputs/patches/c2-option-a-merge.patch`

**What it changes.** One file. `constraints.sdc` only. Five clock groups become
four; the transmit clocks join the system group; 69 named synchroniser
first-stage endpoints are false-pathed by name; 22 named FIFO/address-sync
hierarchies get a `set_max_delay -datapath_only` bound.

**Counts.**

| | before | after |
|---|---|---|
| clocks (`create_clock` + `create_generated_clock`) | 4 + 29 = 33 | 4 + 29 = 33 |
| clock groups | 5 (3/9/17/3/1) | **4 (12/17/3/1)** |
| `set_false_path` | 7 | **9** |
| `set_max_delay` | 0 | **2** |
| `set_multicycle_path` | 1 | 1 |

**What the false paths actually cut, and why they are not a blanket.** Every
exception ends at the *first stage* of one named synchroniser instance,
qualified `-from` a clock in one of the two merging groups. A blanket
`set_false_path -from clk -to [get_clocks D2D_TX_WORD_CLK_*]` would restore
exactly the hole the merge was made to close, in a different shape.

Three mechanics had to be established before those anchors could be written, and
each was a place the patch could have failed silently:

1. **The demet's first stage is `f1_reg`, not `u_f1`.** `WavDemetReset` carries
   two implementations behind `` `ifdef ASIC_TSMC65 ``: a structural
   `SDFCNQD1` pair named `u_f1`/`u_f2`, and a behavioural pair on regs `f1`/`f2`.
   `ASIC_TSMC65` belongs to TideLink's Fusion Compiler flow and is **not defined
   here**, so this design synthesises the behavioural branch. Measured: `u_f1`
   appears **0** times in the gate netlist; `f1_reg` and `f2_reg` appear **282**
   times each.
2. **The demet instances are dissolved.** There is no `WavDemetReset` module in
   the gate netlist — Genus ungroups it and the instance survives as
   `enable_link_clk_demet_f1_reg` in the parent, hierarchy underscore-joined. The
   SDC is read *after elaborate and before mapping*, so the hierarchical spelling
   is the correct one to write, and `write_sdc` re-expresses it. That is the same
   translation that turns `.../u_wlink/phy/gpio/...` into
   `.../u_wlink/phy_gpio/...` in the written syn SDC. Do not "fix" these anchors
   to the flattened spelling.
3. **Capture domain was read off the netlist, not inferred.** Each demet's `f1`
   flop `.CP` net gives its capture domain directly. This matters because the
   naming misleads: `l2a_fc_replay` has its `app_clk` port wired to the RX clock
   and its `link_clk` port to the app clock, so every demet inside it is
   `clk`↔RX, not `clk`↔TX. Cutting those here would be the two-mechanism defect
   the `[C5]` block at the top of `constraints.sdc` spends seventy lines
   condemning.

Deliberately excluded, each for a stated reason: `l2a_fc_replay/*` (clk↔RX,
already cut by the RX group); `ack_nack_fifo/*`, `cr_pkt_seen_tx_demet`,
`crack_pkt_seen_tx_demet` (RX word → TX word, both ends outside the merge);
`phy/gpio/*` (reset synchronisers on `io_clk`, in the `$EXTCLK` group before and
after); `txrouter/en_ff2_demet` (on the TX clock, but Genus tied its `D` pin to
`1'b1` — there is no arc to cut); `en_ff2_tx_demet`/`en_ff2_rx_demet` (CSE'd onto
a shared `swi_enable` driver, gone by mapping).

Included, and easy to miss: **`u_fcemit_obs`**. SoC Labs' own observability
block, not Wav IP, so it uses `<signal>_s0` rather than `f1` and matches no
`*demet*` pattern. Its 41 flops are the single largest TX→`clk` group in the
design and all of them are synchroniser stages. Left timed, they would be the
loudest false alarm in the first Option A report.

### 3.1 Option A's honest gap

**The synchronisers are not the crossing.** They are the pointers and enables
that make the crossing safe. The payload itself — the FIFO memory array, the
`WavMultibitSync` address memories, and everything downstream of them — crosses
with no synchroniser on it at all, by design: the gray-coded pointer is demet'd,
and the pointer's value is what guarantees the data is stable.

The patch handles the bulk of that with `set_max_delay -datapath_only` at one
`$EXTCLK_PERIOD` on 22 named hierarchies, `catch`-wrapped with a plain
`set_max_delay` fallback (stricter, never looser) because `-datapath_only`
support in Genus 21.15 is **unconfirmed and was not tested** — no Genus session
was opened.

That still leaves roughly 200 endpoints that are neither synchroniser nor FIFO
payload: `lltx/link_data_reg` (128 bits), `lltx/byte_count_reg`,
`txpstate/count_reg`, `sp2wl/tx_data_reg`, `txrouter/curr_ch_reg`. Those are
genuinely timed `clk` → TX-word paths. They should close — the effective budget
is a full `$EXTCLK_PERIOD`, because a `/16` generated clock with aligned edges
puts the tightest launch edge one source period before each capture edge, not a
sixteenth of one — but "should" is not "did", and no run has been made.

**So Option A is landable but not finished.** Its acceptance gate is written
into the patch and is deliberately *not* "zero violations":

1. `check_timing`'s `master_clk_edge_not_reaching` stays at 0;
2. the violating endpoints that remain are enumerated, and each is either closed
   by optimisation or given its own named exception;
3. no exception added in step 2 is expressed clock-to-clock.

An Option A run read as "1184 new violations, revert" has learned nothing.

---

## 4. Option B — bond `user_ref_clk` to its own pad

`ASIC/genus-innovus/inputs/patches/c2-option-b-bond.patch`

**Be clear what this is: a hardware change.** The patch is the constraint half
only. Applied alone it declares a clock on a port that does not exist and will
not elaborate.

### 4.1 The `[C2]` block is wrong about one thing, and it matters

It says Option B makes the group "TRUE AS WRITTEN, with no SDC edit at all."
That is wrong. Every transmit clock is a `create_generated_clock` whose
`-source` is an **internal pin** (`$WL/user_hsclk`, `$WL/pad_clk_tx`) that
traces back to whatever primary clock feeds the Wlink. Remove the alias without
adding a `create_clock` on the new pad and the trace terminates at an unclocked
port: `D2D_TX_CLK_0` and `D2D_TX_WORD_CLK_0..7` lose their master, ~1.5k
transmit-word flops go back to having no waveform, and the run still reports
success. That is the same class of silent hole as the original 16,653.

A second, subtler one: `set_clock_groups` cuts only *between* groups. A clock in
no group is not "asynchronous to nothing" — it stays fully timed against
everything. The new clock must join the transmit group, and the patch changes the
group's length guard from 9 to 10 so that stays checked.

### 4.2 The pad-budget answer: there is room, and it is not close

This is the question the decision was deferred on, and it has a measured answer.

| | |
|---|---|
| pad cells in the ring | 82 (48 signal + 34 power/ground) + 4 corners + 325 fillers |
| width of every signal pad | 25.000 µm (patched vendor LEF) |
| IO filler inserted, all four sides | **4,070 µm** |
| smallest single contiguous gap anywhere | **42 µm** (left side); 55 µm on the other three |
| spare already-instantiated signal pad | **none** — all 48 are bound |

A 42 µm gap holds a 25 µm driver with 17 µm left, and 17 = 10+5+1+1 is
filler-legal. The `.io` file uses relative `space=` values, so adding a top-side
pad is a one-number edit: 17 pads at `space=55` become 18 at `space=50`
(18×25 + 17×50 + 30 = 1330 exactly, and 50 = 20+20+10 is filler-legal).

**The "v1 pad budget" is a scope decision, not a geometric limit.** Commit
`e809fbf` — *"back to the intended 23-pad budget — tie/open, do not float
(46 → 23)"* — reverted a previous change that had bonded all 46. Nothing in
`pads.v`, the `.io` file, `floorplan.tcl` or `place_bondpads.tcl` claims the ring
is physically full. `pads.v:26-33` says the budget "gives up the scan chain,
both UARTs, the PL022 SPI, the JTAG TAP and the PTP 1PPS, and it shares one pad
between sys_fclk / rtc_clk / user_ref_clk" — a list of things not bonded, not a
statement that they could not be.

The two pads that *could* be repurposed without adding one, `SE` and `TEST`, are
explicitly reserved by the boundary spec (`nanosoc_eth_chiplet.yaml:131-132`) for
a future muxed scan chain. Adding a pad is cheaper than taking either.

### 4.3 What Option B actually costs

1. **`nanosoc_eth_chiplet_pads.v`** — remove the alias at `:137-139`, add a
   `PDDW04DGZ_G` input pad (same cell and tie pattern as `uPAD_CLK_I` at
   `:266-273`), add the port.
2. **`sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml`** — delete
   `- { soc_port: user_ref_clk, const: "sys_fclk" }` from the ALIASED CLOCKS
   block; add `user_ref_clk` as a bonded `chip_port`. **`rtc_clk` stays aliased.**
   Regenerate; `make chip-boundary` then reports 24 pad cells / bonded 36.
3. **`scripts/nanosoc_eth_chiplet_pads.io`** — the spacing edit above.
4. **`scripts/place_bondpads.tcl`** — its eight name lists hand-encode the
   outer/inner bond-pad parity of the `.io` ring order. **Append at the end of a
   side rather than inserting mid-side**, or every pad after the insertion point
   reparents. Nothing in the tree enforces this and `make chip-boundary` will not
   catch it.
5. **The board** — a clock source for the new pin, and a *distinct* one.

**A distinct pad is necessary but not sufficient.** If the board feeds the new
pad from a buffered copy of the oscillator that drives `CLK`, the two clocks
share a source again and `-asynchronous` is a fiction one buffer further out.
The constraint asserts a distinct *source*, not merely a distinct *pin*.

6. **A full backend re-run.** New pad, new floorplan, new CTS (a second clock
   tree, since `$USRCLK` now drives the Wlink reference and through it the whole
   transmit domain), new route, new signoff.

### 4.4 The link-rate trap in Option B

`constraints/nanosoc_eth_chiplet_cdc.sdc:29-33` — the chiplet-level CDC input,
which describes the inner top where `user_ref_clk` is a real distinct port —
declares it at **8.000 ns (125 MHz)** and calls it *"the Wlink PLL reference …
the D2D unit interval; TideLink's SDC parameterises it as T_UI_NS."* So 125 MHz
is what the link was specified at, and 100 MHz is what the pad alias silently
imposed.

**The patch deliberately does not take that.** `$USRCLK_PERIOD` defaults to
`$EXTCLK_PERIOD`, making Option B a change of *phase relationship only*. Raising
it to 8.0 would make this die transmit at 125 MHz into a compute chiplet whose
constraints still say 10.0 and whose pad ring is a separate tapeout — our
forwarded `pad_clk_tx` *is* the peer's `pad_clk_rx`
(`tidelink_constraints.sdc:3-19`). It would also break the symmetry argument
that licenses `D2D_LINK_PERIOD == $EXTCLK_PERIOD` on the receive side, since the
two dies would no longer share a source. Whether the link layer tolerates a
per-direction rate difference is a PHY/flow-control question this repo cannot
answer. The rate change is a separate decision; the patch says so in place.

---

## 5. The `-source` anchor claim — verified

The `[C2]` block asserts that the TX word clocks' `-source` was deliberately
anchored at `$WL/user_hsclk` rather than `[get_ports CLK]` "so that it stays
correct under either option", and asks for `D2D_TX_CLK_0`'s own `-source` and
the group to be checked at the same time. All three parts check out:

| | `-source` | under Option A | under Option B |
|---|---|---|---|
| `D2D_TX_WORD_CLK_0..7` | `$WL/user_hsclk` (internal pin) | master resolves `clk` | master resolves `user_ref_clk` |
| `D2D_TX_CLK_0` | `$WL/pad_clk_tx` (internal pin) | master resolves `clk` | master resolves `user_ref_clk` |

Both anchors are internal pins downstream of whatever primary clock feeds the
Wlink, so both re-resolve by themselves. **`tidelink_constraints.sdc` needs no
edit under either option** — verified, and it is the reason both patches touch
exactly one file. Had the word clocks been anchored at `[get_ports CLK]` — which
would also have resolved, and which `tidelink_constraints.sdc:288-301` explicitly
rejected — Option B would leave them sourced on a clock that no longer reaches
them, and it would still elaborate and still report clean.

**The one qualification.** The anchors survive Option B only *because* the patch
adds the `create_clock` (§4.1). The claim is true of the anchor, not of the file.

The `[C2]` note's third request — "check … this group at the same time" —
resolves to: the group *is* the only thing that needs editing. That is the whole
decision.

---

## 6. A risk that arrived today

`tidelink/src/rtl/tidelink_top.sv` in the working tree now instantiates
`tidelink_link_clk_div` between `user_ref_clk` and the Wlink's `user_hsclk` — a
programmable divider, `RATIO_RESET = 3'd0` (/1 bypass out of reset).

**It is not committed.** `tidelink_link_clk_div.sv` is untracked (`??`),
`tidelink_top.sv` is modified, and neither is in `build/full-20260814` (zero
occurrences of `link_clk_div` in the gate netlist or the hierarchy report). The
submodule checkout (`9e4a401`) is also not the commit the parent repo records
(`e21e274`). This is another session's work in flight; it may or may not land.

**Why it matters, if it lands.** `[C2] EVIDENCE 2` says of the transmit chain
"note there is no PLL and no divider anywhere on it. It is assigns and one scan
mux." That would no longer be true. Under Option A the merged group asserts a
fixed 1:1 relationship between `clk` and the Wlink reference, which holds only
while the divider is at `/1`; no `create_generated_clock` declares the divider,
so at any other ratio the SDC would be wrong on ~1.5k flops and would not say
so. Under Option B the divider simply divides the new pad and nothing breaks.

If that change lands, **Option A acquires a prerequisite**: declare the divider
output as a generated clock, or constrain the merge to the reset ratio in
writing. Option B does not.

---

## 7. Recommendation

**Take Option B.** Conditionally, and the condition is satisfied today.

The decision was deferred on one question — is there a spare pad — and the
answer is yes, with 4,070 µm of filler in the ring and every gap wider than a
pad cell. That was the only thing making Option B expensive in the way the
`[C2]` block feared. The remaining cost is real (a wrapper edit, a spec edit, an
`.io` edit, a bond-pad list edit, a board clock source, and a full backend
re-run) but it is *bounded and enumerable*, which is the itemised list in §4.3.

Option A's cost is not bounded in the same way. It is one file and it validates
cleanly, but landing it correctly means 1184 newly-timed endpoints, of which
~200 need either closure or their own named exceptions that cannot be written
until a run names them. That is at least two backend iterations of constraint
archaeology, and it ends with the design still asserting that a link reference
which was specified as asynchronous is synchronous — a claim that is true only
because of an alias nobody intended.

Three further reasons, in decreasing order of weight:

1. **Option B removes a recorded silicon liability, not just a constraint bug.**
   The boundary spec says it outright: *"user_ref_clk : the Wlink PLL reference
   is no longer independent of sys_hclk … the link rate is now tied to the
   system clock and inherits its jitter. Bond them separately if either cost
   bites."* Option A makes the SDC honest about a design compromise; Option B
   removes the compromise.
2. **The window is open.** No shuttle seat is booked and the GDS is not
   submitted, so the pad ring can still change. This is the cheapest this option
   will ever be. After submission the choice collapses to A by default.
3. **The in-flight link-clock divider (§6) pushes the same way.** It adds a
   prerequisite to A and none to B.

**If the pad ring is frozen for a reason not visible in this repo** — a package
commitment, a bonding diagram, a partner constraint — then Option A is the only
honest option, and it should be landed *with* its part-3 work planned, not as a
one-line group edit. What must not happen is the third thing: leaving the group
as it is. `-asynchronous` on a boundary the tool resolves as synchronous is not
a conservative default. It is a false-path on ~1184 endpoints that no one
decided to false-path.

---

## 8. What was validated, and what was not

**Validated.** Both patches `git apply --check` clean against
`constraints.sdc` sha256 `90b776a9…`, and each round-trips: applied to a fresh
copy it reproduces the tested file byte for byte. Applying B on top of A is
refused, confirming they are alternatives. Both patched files were sourced under
`tclsh` with every SDC command stubbed, so the `foreach` loops and `error`
guards genuinely executed — Option A built and resolved 69/69 synchroniser
anchors and 22/22 datapath anchors. Counts before/after are in §3 and §4.

**Not validated.** No Genus and no Innovus session was opened; this is
syntax-and-intent checking only. In particular: `set_max_delay -datapath_only`
support in Genus 21.15 is unconfirmed (hence the `catch`); whether the demet
anchors resolve at Genus read time is inferred from the fact that
`count_reg[3]/Q` demonstrably does (`tidelink_constraints.sdc:181-185`), not
measured; and the 1003/181 endpoint split is structural fan-in, not a
`report_timing` path count, so a real run may differ where case analysis or
existing exceptions prune paths.

**The gate for either option is the next run's `check_timing`, not this
document.**
