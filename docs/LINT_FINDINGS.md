# Structural lint of the ethernet-chiplet integration RTL

**Status: stood up 2026-07-10. Runner: `scripts/lint.sh` (→ `verif/lint/run.sh`).
Result: our three integration modules are structurally clean; every finding is a
waived by-design item. The lint's ability to catch the `D2D_HREADY_LOOP` class is
proven by a sanity harness.**

This pass exists because `make elab` links a netlist but never evaluates it, so it
is blind to the class of defect that motivated this work: combinational loops,
unintended latches, width truncation in expressions, and undriven / multiply-driven
nets. The peer-aperture HREADY cycle (`docs/D2D_HREADY_LOOP.md`) passed elaboration
and only bit when a transaction ran through it. Lint is the missing gate.

## 1. Tooling situation (what is actually installed)

| Tool | Status | Notes |
|---|---|---|
| **Verilator** | **4.028** (2020-02-06) | The pass is built on this. `--lint-only -Wall` gives combinational-loop detection via **UNOPTFLAT**, plus latch/width/undriven/multidriven checks. Old, but adequate. |
| Cadence **HAL** | **22.03** at `/eda/cadence/xcelium/tools/bin/hal` | Real flist-native structural+CDC lint. License-gated; not wired up here (would be the tool for a full-integration pass — see §5). |
| verible-verilog-lint | absent | style linter (no comb-loop detection anyway) |
| slang | absent | |
| SpyGlass / `sg_shell` | absent | no `which` hit; do not assume it exists |

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
| 6 | noise | PINCONNECTEMPTY ×20 | `nanosoc_eth_chiplet.sv` :376, :535, :564, :565, :568, :742, :747–750, :761–766, :809, :810, :812, :815 | Deliberately open outputs | By design — clock-gate hints (`APBACTIVE`), unused reduced-slave `hmastlock`, TideChart-APB `PSTRB`/`PPROT` it does not carry, the idle I2C-AXI slave responses, and the absent IRQC stream. Each is commented at its instance. |

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
