# Structural lint of the ethernet-chiplet integration RTL

**Status: stood up 2026-07-10. Runner: `scripts/lint.sh` (→ `verif/lint/run.sh`).
Result: our three integration modules are structurally clean; every finding is a
waived by-design item. The lint's ability to catch the `D2D_HREADY_LOOP` class is
proven by a sanity harness.**

**Update 2026-08-09.** Re-checked at FULL-CHIP scope (`verif/lint/full/`, Verilator
+ HAL over the whole 590-file ASIC flist, with the real submodules rather than
blackboxes). Every §4 verdict below still holds, with one change: the 20 open
outputs in row 6 are no longer left as `.port()` — they are closed properly in
**§4.1**. Integration-zone DESIGN findings: Verilator **0 → 0** (measured), HAL
**21 → 0** (~~expected; HAL is licence-gated and re-runs centrally~~ — **corrected
2026-08-18: there is no "central" re-run host.** HAL runs here, in
`verif/lint/full/run.sh`, on an Xcelium seat. If this 21 → 0 was recorded as *expected*
rather than *measured*, re-measure it before relying on it — see §1).

This pass exists because `make elab` links a netlist but never evaluates it, so it
is blind to the class of defect that motivated this work: combinational loops,
unintended latches, width truncation in expressions, and undriven / multiply-driven
nets. The peer-aperture HREADY cycle (`docs/D2D_HREADY_LOOP.md`) passed elaboration
and only bit when a transaction ran through it. Lint is the missing gate.

## 1. Tooling situation (what is actually installed)

| Tool | Status | Notes |
|---|---|---|
| **Verilator** | **4.028** (2020-02-06) | The pass is built on this. `--lint-only -Wall` gives combinational-loop detection via **UNOPTFLAT**, plus latch/width/undriven/multidriven checks. Old, but adequate. |
| Cadence **HAL** | **22.03** at the Cadence Xcelium `hal` binary | Real flist-native structural+CDC lint. ~~License-gated; not wired up here~~ **CORRECTED 2026-08-18: HAL IS wired up and runs on this host.** `verif/lint/full/run.sh` runs Verilator **and** HAL — see `verif/lint/full/hal_lint.sh:30` and `:136` (`"$XRUN" -sv -hal -elaborate`). "Licence-gated" is true only in the trivial sense that it takes an `Xcelium_Single_Core` seat from the same pool the flow already uses (41 issued, 1 in use, measured 2026-08-18). |
| verible-verilog-lint | absent | style linter (no comb-loop detection anyway) |
| slang | absent | |
| **SpyGlass** | **T-2022.06-SP2**, installed **and licensed** | ~~absent — no `which` hit; do not assume it exists~~ **CORRECTED 2026-08-17 — see §1.1.** `${SPYGLASS_HOME}/bin/`. Off `$PATH`, reached by absolute path. |

### 1.1 Correction 2026-08-17 — SpyGlass was recorded absent on bad evidence

The row above said **absent**, on the evidence "no `which` hit". That was wrong.
SpyGlass is installed on this host and its CDC licence checks out:

```sh
ls ${SPYGLASS_HOME}/bin/
# sg_shell  sg_ame  spyglass  spyglass_main  spyencrypt  sgsat  … (18 entries)
```

Proven live, not merely present on disk — SpyGlass was run on a deliberately
planted unsynchronised crossing and caught it:

```
Technology Summary: CDC( Advance CDC )
    Unsynchronized crossings= 1
Ac_unsync01  Error  cdc_probe.v:13  Unsynchronized Crossing: destination flop
  cdc_probe.q_b, clocked by cdc_probe.clk_b, source flop cdc_probe.d_a_r,
  clocked by cdc_probe.clk_a. Reason: Qualifier not found
```

**The methodological error matters more than the row.** `which` searches `$PATH`
and nothing else, so **a `which` miss is evidence about `$PATH`, not about the
machine.** Every EDA tool on this host that is invoked by absolute path — which is
most of them — will fail that test while being perfectly available. Note the
contrast in the same table: HAL is recorded present *because* its absolute path
was quoted (the Cadence Xcelium `hal` binary). SpyGlass got the opposite
verdict from the weaker test.

The repo already contained the refutation. `tidelink/cdc/Makefile:12` is a
working, checked-in SpyGlass CDC driver that hardcodes the exact install:

```make
SPYGLASS_HOME ?= ${SPYGLASS_HOME}
```

**Consequence.** `docs/CDC_FINDINGS.md` carried the same error and used it to
defer the `CLKDMN` CDC sign-off to another host. That deferral is void — the
sign-off can run here. See `docs/CDC_FINDINGS.md` §"SpyGlass availability".

Before recording any tool as absent, check the site EDA install trees and
grep the repo for an absolute path to it. `which` alone does not settle it.

Verilator is the right free tool for *this* job: UNOPTFLAT is exactly a
combinational-loop finder. Caveats of 4.028 that shaped the harness:
- it cannot parse the sim guard `tb_hready_loop.sv` (event controls inside tasks /
  `initial`), so the sanity check uses a **synthesizable** probe instead;
- it does not know the newer `UNUSEDSIGNAL` code (only `UNUSED`);
- it is duplicate-module-is-an-error (relevant for a full pass — see §5).

## 2. How to run

```sh
cd nanosoc-ethernet-chiplet
scripts/lint.sh            # four passes; exits non-zero on any non-waived finding
```

No `set_env.sh` sourcing needed. The runner regenerates blackbox stubs for the SoC
/ TideLink / TideChart / CMSDK submodules (`verif/lint/gen_bbox.py`, into the
git-ignored `build/lint/bbox/`) so it lints **our** wrapper logic in isolation, not
the vendor forest. Passes whose generated inputs are absent on a fresh clone
(the SoC top lives under generated `build_soc/`) skip with a clear note rather than
failing.

## 3. Sanity check — does the lint actually catch the bug we fixed?

`verif/lint/hready_loop_probe.sv` is a pure-structural harness that closes the same
peer HREADY feedback the integration top closes. `tl_sub_stub` inside it reproduces
the one property of TideLink's `ahb_sub` that creates the hazard: its `hreadyout`
is a **combinational** function of its `hready` (`tidelink_top.sv:1119,1169`). Three
wirings, selected by `+define`:

| wiring | `hready_to_peer` | UNOPTFLAT | meaning |
|---|---|:---:|---|
| `+define+NO_HREADY_FIX` (the bug) | `= hready` | **fires** | **the loop is detected** ✔ |
| default (the shipped fix) | `= dph_peer ? 1'b1 : hready` | fires | see note |
| `+define+STRUCT_TIE` | `= 1'b1` | clean | no `hready` fan-in at all |

**The lint catches the bug: UNOPTFLAT fires on the broken wiring.** That is the
result that matters.

**Subtlety worth recording:** UNOPTFLAT *also* fires on the shipped fix. The fix is
a **dynamic** break — when the peer owns the data phase (`dph_peer==1`)
`hready_to_peer` is forced to a constant `1'b1`, and when it doesn't the peer's own
`hreadyout` is not selected into `hready`; the two registered selects are mutually
exclusive, so the loop never closes *at run time*. But `hready` is still a
**static** fan-in of `hready_to_peer` (it is literally in the `else` arm — and it
has to be, or the peer would latch an uncommitted address; see
`D2D_HREADY_LOOP.md` option 2). A conservative static loop-finder cannot see the
mutual exclusion, so it still reports the cycle. Only the structural tie, which
removes `hready` from the fan-in entirely, goes clean.

Consequences for how to use this:
- UNOPTFLAT is a sound **detector / tripwire** for this bug class.
- It is **not** a clean pass/fail regression gate for *this particular* fix — it
  cannot distinguish the correct dynamic break from the bug. The authoritative
  regression remains the **simulation** guard
  `verif/chiplet_d2d_decode/tb_hready_loop.sv` (which runs transactions and proves
  they land). To use Verilator UNOPTFLAT in CI over the real integration you would
  waive it on `hreadyout_peer` with a documented `lint_off`, so a *new* loop
  elsewhere still trips it.

## 4. Triage — every finding on our RTL, most-severe first

**Bottom line: zero real defects.** All findings are by-design and waived by the
runner (`WAIVE_RE = UNUSED | PINCONNECTEMPTY`). Ranked by how much they matter:

| # | Sev | Code | File:line | Finding | Verdict |
|---|---|---|---|---|---|
| 1 | none (real) | — | — | No combinational loop, latch, width-truncation, undriven or multiply-driven net in any of the three modules. | The design is structurally clean. |
| 2 | low | UNUSED | `nanosoc_eth_chiplet.sv:311` | `tcapb_paddr[11:8]` unused | **By design, mild over-provisioning.** The TideChart AHB→APB bridge is instantiated `ADDRWIDTH(12)` (4 KB) but the shim consumes only `[7:0]` (`APB_ADDR_W=8`, line 796). Harmless (upper bits ignored). *Optional cleanup:* `ADDRWIDTH(8)` would match the consumer and drop the warning. |
| 3 | noise | UNUSED | `nanosoc_eth_chiplet.sv:271` | `d2d_ahb_s_hprot[6:4]` unused | By design — TideLink drives AHB5 `hprot[6:0]`; the SoC consumes `[3:0]` (line 386). Deliberate AHB5→AHB-Lite narrowing. |
| 4 | noise | UNUSED | `chiplet_d2d_decode.sv:68` | `haddr[31:25,23:20,15:0]` unused | By design — the decoder decodes only `haddr[24]` and `haddr[19:16]`; the full address fans out to the slaves at the top level, not through the decoder (module-header CONSTRAINT). |
| 5 | noise | UNUSED | `chiplet_d2d_decode.sv:69` | `htrans[0]` unused | By design — the decoder qualifies on `htrans[1]` only ("a real transfer"). |
| 6 | ~~noise~~ **CLOSED 2026-08-09** | ~~PINCONNECTEMPTY ×20~~ | `nanosoc_eth_chiplet.sv` | Deliberately open outputs | Verdict unchanged (all 20 re-verified by-design at full-chip scope), but they are no longer left as `.port()`. Each now drives a **named `*_nc` sink** — see §4.1. |

### 4.1 The 20 open outputs — re-verified at full-chip scope, and closed

At the three-module scope these were `.port()` and waived. At **full-chip** scope
(`verif/lint/full/`, both tools) the same 20 came back as **21 HAL `*W,UNCONN`**
lines that nothing waived, because the merged integration ruleset waives HAL's
`UNCONO` (a module's own undriven output) but **not `UNCONN`** (a dangling output
at an *instance*) — `verif/lint/full/hal_rules.tcl:67`. Verilator's
`PINCONNECTEMPTY` was waived; HAL's exact analogue was not. So the class was
half-waived and accumulating.

**Re-verified.** All 21 opened in the RTL, all still deliberate:

| # | Instance | Port(s) | Why it is a dead end |
|---|---|---|---|
| 1 | `u_soc` | `d2d_ahb_m_hmastlock` | No slave in the D2D window has an `HMASTLOCK` port: TideLink's `ahb_sub`/`ahb_tx`/`ahb_fifo`/`ahb_ptp` declare none (`tidelink_top.sv` has no `*_hmastlock` port at all), and BP210 `cmsdk_ahb_to_apb.v:41-72` has no `HMASTLOCK` input. Nowhere to route it. |
| 2–3 | `u_tlapb_bridge`, `u_tcapb_bridge` | `APBACTIVE` ×2 | Clock-gating hint. Both bridges run `PCLKEN=1` at HCLK with no APB clock gate in this build. |
| 4–5 | `u_tcapb_bridge` | `PSTRB`, `PPROT` | `tidechart_shim`'s APB port is `paddr/psel/penable/pwrite/pwdata` only — it carries neither. |
| 6 | `u_tidelink` | `tl_data_mode_o` | **No longer open.** Connected 2026-08-09 by the TideChart data-mode gate fix; it now drives `u_tidechart.link_active`. This is the one entry whose *verdict* changed. |
| 7–17 | `u_tidelink` | 11 × `s_i2c_axi_*` response outputs | Every request-side input of that AXI slave is tied inactive at the same instance (`awvalid`/`wvalid`/`arvalid` = 0), so no transaction can start and no response can ever be produced. Tied off as a block. |
| 18–21 | `u_tidechart` | 4 × IRQC AXI-Stream outputs | The `ahb-chiplet-irqc` block is not instantiated in this chiplet. The matching *inputs* are tied idle at the same instance. |

**How they are closed.** Not by a new waiver: each unused output now drives a
**named `*_nc` wire** declared in one commented block in
`src/rtl/nanosoc_eth_chiplet.sv`, one line of reason each. That is:

- the convention **nanosoc_gen already emits** in the generated SoC top
  (`cc_periph_uart_txen_nc`, `dmac_0_apb_bridge_pstrb_nc`, `dap_ss_0_jtagnsw_nc`, …);
- the pattern the **recorded HAL waiver actually names** — "intentional dead-end
  sinks routed to named `*_nc` wires", `-nocheck URDWIR`,
  `nanosoc-multicore-system/lint/hal.tcl:117`;
- **empirically zero-finding**: the generated SoC top declares >100 `_nc` wires
  and contributes exactly **two** HAL DESIGN findings, neither of them about an
  `_nc` net.

So the justification now applies to the thing it is waiving, which is the failure
mode `docs/LINT_REMEDIATION_PLAN.md` §4 records: a rule-name waiver whose recorded
reason was narrower than its effect is what hid the `dmac_0_err_w` DMA-error hole.

**Zero silicon change** — a driven-but-unread wire has no load and is removed by
synthesis; `.port()` and `→ *_nc` are the same netlist. **Measured** (Verilator,
`verif/lint/full/verilator_lint.py`, integration zone): 20 `PINCONNECTEMPTY`
became 20 `UNUSED`, both waived; DESIGN findings **0 → 0**.

**Standing rule, now stated in the RTL itself:** never omit a pin (an omitted
*input* floats — `PINMISSING`/`UNCONI`, and both gate); for an unused *output*,
do not stop at `.port()` — give it a named `*_nc` sink with its reason, because
`_nc` is greppable and a bare `()` is not.

Notes:
- `tidechart_shim.sv` linted **completely clean** — the flatten/unpack generate
  loop and its indexed part-selects (`[gi*W +: W]`) have no width or driver issue.
- The `assign d2d_irq = {…}` concat (`nanosoc_eth_chiplet.sv:822`) drew **no**
  width warning — it is exactly 16 bits into `d2d_irq[15:0]`, confirmed.
- One finding appears only against the probe, not the real RTL: `SYNCASYNCNET` on
  `hresetn`. It is an artifact of the harness stub using `hresetn` synchronously
  while the decoder uses it asynchronously; the standalone decoder is consistent.
  The runner suppresses it in the sanity pass.

## 5. What a full-integration lint would require (reported, not attempted)

Linting the *whole* elaborated chiplet (SoC + TideLink + TideChart + Arm IP)
instead of our three modules is a separate, larger effort:

- **Duplicate modules.** The SoC and TideLink flists both compile
  `cmsdk_ahb_to_apb`, `cmsdk_ahb_to_sram`, `cmsdk_apb_slave_mux`. VCS keeps the
  last (`Warning-[OPD]`); **Verilator errors** on the redefinition. The flist's
  `resolve_tidelink_flist.py` dedup would have to be extended to the CMSDK trio for
  a Verilator front-end. (This is the same "which module actually binds" hazard the
  flist header warns about — a lint front-end picking differently from the
  simulator is not a debugging session anyone wants.)
- **Read-only vendor + generated collateral.** Needs `CMSDK_DIR`, `XHB500`, the
  generated XHB500 (`tidelink/set_env.sh` builds it on first run), and the
  generated SoC top (`build_soc/`). Reading these is fine; none may be written.
- **Noise.** Vendor IP (Corstone/BP210, XHB500, Wlink) throws thousands of style
  warnings. A full pass needs `-Wno-*` blanket-suppression scoped to vendor dirs
  and `-Wall` kept only on `src/rtl/` — otherwise the signal drowns.
- **Unpacked-array ports** on `tidechart_controller` — Verilator handles these, but
  a flist→Verilator adapter must pass `+incdir` and the SoC's `$()`-syntax paths
  (the Makefile already flattens those for VCS; the same flattened flists feed
  Verilator).
- **The better tool for it is already installed:** Cadence **HAL** (§1) is
  flist-native and does structural + CDC lint over the exact VCS filelist, so it
  sidesteps the dedup/adapter work. It is license-gated; standing it up on the full
  flist is the recommended next step if a whole-SoC structural/CDC sign-off is
  wanted.

## 6. The transferable lesson

The stub-based wrapper lint (pass 3) is, by construction, **unable to see the very
bug that motivated this** — a body-less blackbox has no `hreadyout`-from-`hready`
behaviour, which is exactly why the loop survived elaboration. The cycle is visible
only when a submodule's behavioural dependence is present. So the rule for this
integration:

> For every edge where a submodule's ready/response depends **combinationally** on
> an input this wrapper drives, add a small **behavioural-stub** harness (like
> `hready_loop_probe.sv`) that reproduces that dependence, and lint it for
> UNOPTFLAT. Structural elaboration and blackbox lint will not find it for you.

## Files

- `scripts/lint.sh` — entry point (forwarder).
- `verif/lint/run.sh` — the four-pass driver; gates on non-waived findings.
- `verif/lint/gen_bbox.py` — extracts a Verilator blackbox from a real module
  header (read-only; used for the SoC/TideLink/TideChart/CMSDK stubs).
- `verif/lint/hready_loop_probe.sv` — the synthesizable UNOPTFLAT sanity harness.
