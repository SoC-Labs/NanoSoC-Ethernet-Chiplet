# G2 SoC pair — status

**"Full G2": two real `nanosoc_multicore_soc` dies, each behind its own
`chiplet_d2d_decode` + `tidelink_top`, cross-wired through the PHY pads, proving
a transaction crosses from die A's D2D window into die B's real `shared_sram_0`.**

Environment: `verif/g2_soc_pair/` (`tb_g2_soc_pair.sv`, `Makefile`,
`test_g2_soc_pair.py`). Nothing under `verif/g2_peer_aperture/` or
`verif/chiplet_d2d_decode/` was touched. No git commits made.

---

## TL;DR

| Milestone | State |
|---|---|
| **1 — structural elaboration, firmware-free, 0 VCS errors** | **DONE — 0 errors, 206 modules, `simv_g2` built** |
| **2 — cocotb: link bring-up + a peer write from die A lands in die B's real `shared_sram_0`** | **DONE — `test_peer_write_crosses_to_die_b` PASSES.** Link brought up between two real SoCs; die A's peer write to `0x2F00_1000` lands in die B's real `shared_sram_0` at `0x2D00_1000` = `0xC0FFEE01`, CAM-off control confirms translation. The payload drop found on the first pass (below) was **root-caused and FIXED** — see "Milestone 2 finding: RESOLVED". |
| **2b — peer READ round-trip** | **DONE — `STAGE 2b` reads `0x2F00_1000` back across the link = `0xC0FFEE01`. The data plane crosses BOTH ways** (read pipe-offset fix, below). |
| **2c — back-to-back burst** | **DONE — `STAGE 2c` 8-word write+read sequence, every beat intact.** The fixes hold across consecutive beats. |
| **3 — blocker list / skeleton** | No blockers remain. |

> **Full G2: a memory transaction crosses from one real `nanosoc_multicore_soc`
> to another over the die-to-die link — address translated `0x2F`→`0x2D`, payload
> intact, landing in the far die's real SRAM — and back again (read + 8-word
> burst). Reproduce the whole set with `make regress` (or just this env with
> `make -C verif/g2_soc_pair sim`).**

---

## Design choice: instantiate the shipping wrapper twice

The task frames G2 as "two SoCs, each behind its own decode + TideLink". The
repo already has exactly that per die, wired and hready-loop-fixed, in the
shipping integration top **`nanosoc_eth_chiplet`** (`src/rtl/nanosoc_eth_chiplet.sv`):

```
nanosoc_multicore_soc  ->  chiplet_d2d_decode  ->  tidelink_top
                                                       | ahb_mng
                                                       v
                                   (this die's own) d2d_ahb_s -> shared_sram_0
```

So `tb_g2_soc_pair` **instantiates `nanosoc_eth_chiplet` twice** and joins the
pads, rather than re-deriving the SoC↔decode↔TideLink wiring inline. This:

* reuses the proven `dph_peer`/`hready_to_peer` fix (`docs/D2D_HREADY_LOOP.md`) —
  the tb does **not** re-introduce the combinational HREADY loop;
* gives the **stronger** observation point for free. `g2_peer_aperture` hangs the
  far die's `ahb_mng` on an `ahb_probe_mem`; the wrapper hangs it on that die's
  **own `d2d_ahb_s`**, so the far end is a real SoC's real `shared_sram_0`. That
  is the milestone the task called out as the harder second step — it is the
  default here, not an add-on.

The pad cross-wire, `pad_skid`, I2C wired-AND, POR-gated RX pads and the master/
slave straps are lifted from `verif/g2_peer_aperture/tb_pair.sv`.

### The addressing lines up with the existing CAM rule

`soc_d2d_loopback` establishes that the inbound `d2d_ahb_s` port reaches
`shared_sram_0` at **0x2D000000**. `g2_peer_aperture` establishes the CAM rewrite
**0x2F → 0x2D**. Composing them, die A's peer write to `0x2F00_1000` is rewritten
to `0x2D00_1000` and routed by die B's SoC into `shared_sram_0` — no new CAM rule
is needed. `RULE_0 = 0x002D2F01`, unchanged from `g2_peer_aperture`.

### Firmware-free stimulus

Both CPU0 are boot-gated secondaries, never released; both CPU1 run stage-0,
find no BOOT magic in the unprogrammed flash model (`sst26vf064b`, one per die)
and halt — leaving both buses free, exactly as `soc_d2d_loopback`. All stimulus
is an **external AHB master on each die's `eth_ss_0` port**, which reaches the
0x2E/0x2F D2D window (and 0x2D shared SRAM) through the eth-subsystem `system`
passthrough. Link bring-up is issued as AHB writes to `0x2E03_xxxx`, which the
chiplet decode's tlapb bridge turns into TideLink APB writes — so no directly
exposed APB port is needed on the wrapper.

---

## Milestone 1 — ELABORATION: DONE, 0 errors

```
cd verif/g2_soc_pair
source ../../set_env.sh        # (the Makefile re-sources all three set_env.sh itself)
make elab
```

Result (`build/elab/elab.log`):

```
All of 206 modules done
CPU time: 17.3 s to compile + 0.8 s to elab + 0.4 s to link
```

* **VCS errors: 0** (`grep -cE 'Error-\[' build/elab/elab.log` → `0`).
* `build/elab/simv_g2` is produced and links.
* Two full die instances elaborate: `tb_g2_soc_pair.u_dieA` and `.u_dieB`, each a
  complete `nanosoc_multicore_soc` + `chiplet_d2d_decode` + `tidelink_top`
  (+ `tidechart_shim`), cross-wired through two `pad_skid`.

### The flist merge

The Makefile assembles the union of three component flists + the integration RTL,
identical to the repo's top-level `make elab`:

* **SoC** — `flist/flatten_soc_flist.py` flattens the generated in-sync flist to
  VCS-readable absolute paths (the generator emits `$()`-paths VCS cannot expand).
* **TideLink** — `flist/resolve_tidelink_flist.py` drops the shadowed `deps/`
  `WlinkGenericFCReplayAddrSync_18` (which lacks the a2l reset-skew fix) and
  appends the override, so exactly one definition reaches VCS regardless of tool
  ordering. **Do not** feed VCS the raw `tidelink_fpga.flist`.
* **TideChart** — `tidechart/flist/tidechart.flist`.
* **Integration** — `chiplet_d2d_decode.sv`, `tidechart_shim.sv`,
  `nanosoc_eth_chiplet.sv` (via `flist/nanosoc_eth_chiplet.flist`).
* Plus this env's `pad_skid.sv`, the QSPI flash VIP, and `tb_g2_soc_pair.sv`.

**One flist gotcha found and fixed in the Makefile.** `resolve_tidelink_flist.py`
passes `+incdir` switches through **unexpanded**, so the resolved flist still
contains `+incdir+${TIDELINK_HOME}/deps/tidelink-gpio-phy/rtl` (which holds
`tidelink_training_patterns.svh`). VCS must therefore see `TIDELINK_HOME` in its
environment. The repo's top-level `make elab` gets this because it sources the
env in VCS's own shell; a cocotb/standalone Makefile that only prepares the
flists in a sub-shell does not. The Makefile now `export`s `TIDELINK_HOME` (and
`NANOSOC_ETH_CHIPLET_HOME`, `TIDECHART_HOME`, `CHIPLET_SOC_VCS_FLIST`,
`CHIPLET_TL_VCS_FLIST` — the only vars the merged flist references at VCS time;
the SoC/TideLink source paths are already absolute after the prep step).

### Flist collisions (duplicate module definitions)

**11 `Warning-[OPD]` "Override previous declaration", all pre-existing and
benign, resolved by VCS last-wins. Doubling the SoC introduced ZERO new
collisions** — the two-die build's OPD set is byte-identical to the single-die
`make elab` (`diff` of the two collision lists is empty). This is expected:
instantiating a module twice duplicates *instances*, not *definitions*.

The colliding definitions:

| Module | Colliding sources |
|---|---|
| `cmsdk_ahb_to_apb` | BP210 (SoC) vs the same cell reused by the two integration AHB→APB bridges / TideLink |
| `cmsdk_ahb_to_sram` | BP210 (SoC) vs TideLink FIFO |
| `cmsdk_apb_slave_mux` | BP210 vs Corstone-101/latest copy |
| `cmsdk_fpga_sram` | BP210 memory model, SoC vs TideLink FIFO SRAM |
| `xhb500_flop` / `_or` / `_sync` / `_xor` | TideLink's `xhb_chiplet_mst` vs `xhb_chiplet_slv` generated copies (generic cells, identical) |
| `ahb3lite_to_wb` | pre-existing self-collision inside the SoC eth-subsystem flist |

None is introduced by this env; all are documented in
`flist/nanosoc_eth_chiplet.flist`. No `Error-[UPIMI-E]`, no `Error-[OPD]`.

---

## Milestone 2 — cocotb data-plane test

`test_g2_soc_pair.py` contains two tests:

* **`test_smoke_eth_ss0_reaches_sram`** — *fast, no link.* Resets both dies, then
  writes+reads each die's own `shared_sram_0` (0x2D......) through its `eth_ss_0`
  master. Proves the harness: the AHB master, the SoC matrix passthrough, and the
  SRAM. Run it first.

* **`test_peer_write_crosses_to_die_b`** — *the full G2 experiment.* Brings both
  links up over each die's `eth_ss_0` → 0x2E03xxxx APB (role-lock, calibrator sim
  bypass, `cal_done`, LL bootstrap), programs die A's CAM (0x2F→0x2D), writes
  `0x2F00_1000` on die A, and asserts the payload lands in die B's real
  `shared_sram_0` at `0x2D00_1000` — with a CAM-off control stage proving the
  translated byte came from the CAM, not the harness. Staged as one test (a second
  bring-up in the same sim does not re-converge `cal_done`).

```
make sim TESTCASE=test_smoke_eth_ss0_reaches_sram        # fast harness proof
make sim TESTCASE=test_peer_write_crosses_to_die_b       # full G2 (slow — see below)
make sim WAVES=1                                          # both, with waves.vcd
```

### Validation state — what actually ran

* **Harness — PASSES.** `test_smoke_eth_ss0_reaches_sram`: `TESTS=1 PASS=1 FAIL=0`,
  *"SMOKE ok: both dies' eth_ss_0 masters reach their own shared_sram_0"*. Confirms
  the whole cocotb path — the merged flist compiles under cocotb's own VCS
  invocation, both dies' `eth_ss_0` AHB masters drive, both SoC matrices pass
  through to their `shared_sram_0`, and the reset / calibrator-bypass plumbing is
  correct. (`results_smoke.xml` kept alongside `results.xml`.)
  * One env fix applied: the installed `cocotbext-ahb` takes an **int** for
    `AHBLiteMaster.write` (not `bytes`) and `read` returns `[{'data':'0x…'}]`.
    `Die.write/read` corrected to match `soc_d2d_loopback`.

* **Full link crossing — `test_peer_write_crosses_to_die_b`, ran in ~3 s (not the
  feared minutes — the calibrator sim-bypass makes bring-up quick). Result:**
  * **STAGE 1 PASS — the D2D link came up between two real `nanosoc_multicore_soc`
    dies.** Role-lock over `eth_ss_0`→0x2E032080, `cal_done` on both dies, LL
    bootstrap, and `cr`+`crack` seen on die B. This alone is the crux of "full G2":
    two whole SoCs train the die-to-die link with no firmware.
  * **The peer write's ADDRESS crosses correctly.** Die B's inbound `d2d_ahb_s`
    presents `0x2D00_1000` — the CAM rewrote `0x2F`→`0x2D` and the far die routes
    `0x2D` to `shared_sram_0`. The CAM-off control still needs the write to land to
    be exercised, but the address translation itself is confirmed live.
  * **STAGE 2 FAIL — the write DATA is dropped (the finding below).**

### Milestone 2 finding — peer-write payload is zeroed in the link data phase

> **RESOLVED 2026-07-10 — fixed in `nanosoc_eth_chiplet.sv`.** Root cause: TideLink's
> `ahb_sub` XHB500 bridge pipelines the *address* one cycle (`tidelink_top.sv:1156`,
> `pipe_haddr_r`) but samples write data **live** (`u_xhb_sub .hwdata(ahb_sub_hwdata)`),
> and sequences the AXI **AW** beat then the **W** beat one cycle later. A compliant AHB
> master drives `HWDATA` for the single data-phase cycle and releases it, so the bridge's
> W beat — one cycle after AW — samples `0`. A cycle trace on die A confirmed it exactly:
> at the address-pipeline cycle `s_axi_wdata` momentarily held `0xC0FFEE01` but `wvalid`
> was low (AW beat); on the next cycle `wvalid` asserted but the SoC had already released
> `HWDATA`, so `s_axi_wdata=0`. **Fix:** a one-cycle delay register on the write data fed
> to `ahb_sub` (`d2d_ahb_m_hwdata_q`), so the data is still valid on the bridge's W cycle.
> Under wait states the SoC holds `HWDATA` stable, so the register is harmless. This is a
> TideLink `ahb_sub` timing *contract* the integration must satisfy — **not** the
> `hready_to_peer` fix, which is doing its job. `g2_peer_aperture`'s hand-timed master held
> `HWDATA` across the whole data phase and masked it; two real SoCs exposed it — exactly
> what full G2 is for. Now `test_peer_write_crosses_to_die_b` PASSES end to end.

_The original analysis, preserved:_

Localised with two hierarchical bus catchers in the test (kept in, they log every
outbound/inbound write beat):

```
die A OUTBOUND d2d_ahb_m peer writes = [(0x2f001000, 0xc0ffee01)]
die B INBOUND  d2d_ahb_s write beats = [(0x2d001000, 0x0, hresp=0x0)]
```

The payload `0xC0FFEE01` **leaves die A on `d2d_ahb_m` intact**, and arrives at die
B's inbound port as **`0x0`** — address correct, `hresp`=OKAY, data gone. So the
loss is in the link's peer-write path (die A `tidelink.ahb_sub` → packetiser → PHY
→ die B `ahb_mng` → `d2d_ahb_s`), NOT in either SoC's fabric.

**Why `g2_peer_aperture` did not catch it.** That env drives `ahb_sub` with a
hand-timed master that *holds `hwdata` across the whole data phase* — its own code
warns "Getting this wrong ships the payload as zero and the test still 'passes' its
address check." A real SoC's `d2d_ahb_m` does **not** hold that long: the
`hready_to_peer = dph_peer ? 1'b1 : …` fix (docs/D2D_HREADY_LOOP.md, added to break
the comb loop) forces the peer beat to *complete* as soon as it is the outstanding
data phase, so the SoC fabric advances `hwdata` (to the next beat / IDLE = 0) on
the very cycle TideLink's `ahb_sub` latches it. The hand-timed master masks this
one-cycle capture skew; a real SoC exposes it.

This is a genuine integration bug that only the two-real-SoC path surfaces — i.e.
exactly what "full G2" is for. It is a *data-phase capture* defect, orthogonal to
the *address/CAM* path (proven here) and the *link data path for held data* (proven
in `g2_peer_aperture`).

**Suggested next step (not done here — it is a shipping-RTL change, out of this
env's scope):** on waveforms, line up `nanosoc_eth_chiplet`'s `d2d_ahb_m_hwdata`
against TideLink's internal `ahb_sub` hwdata capture strobe for a peer write. The
fix is likely one of: (a) have TideLink's `ahb_sub` register `hwdata` on the beat
it asserts `hreadyout` rather than the following cycle; or (b) in the integration,
hold `d2d_ahb_m_hwdata` to the peer for one extra cycle after `dph_peer` completes.
Option (b) keeps the change inside this repo (`nanosoc_eth_chiplet.sv`) and does
not touch TideLink's frozen pin.

### Notes / residual risks

* **`COCOTB_RESOLVE_X=ZEROS`** is set (the MAC wishbone slave drives X on hrdata
  during unrelated APB writes). With it, an inbound `hwdata` of X and of 0 both read
  as 0 — but the *outbound* value is a clean `0xC0FFEE01`, so the drop is real
  regardless of X-vs-0 at the inbound.
* **Clock ratio.** The tb sets `sys_fclk`=50 MHz, `ref_clk`=125 MHz, matching
  `test_peer_aperture`'s hclk:ref. The successful bring-up confirms `sys_hclk`
  tracks `sys_fclk` closely enough for the link to train, so this earlier-feared
  risk did not materialise.

None of this affects milestone 1 (elaboration links a netlist; it does not evaluate
the link).

---

## The READ round-trip — RESOLVED

**Status: FIXED 2026-07-10. The full data plane crosses both ways.** `STAGE 2b`
now asserts and passes: `die A read 0x2F00_1000 -> 0xC0FFEE01 (link round-trip)`.

> **The fix** is a one-cycle read pipe-offset mask in TideLink's `ahb_sub`
> (`tidelink_top.sv`). TideLink's `ahb_sub` XHB500 bridge read FSM is itself
> correct — it holds `hreadyout` low until `r_done` (`rvalid & rready`) in
> `RESP_FSM_SEQ_NSEQ`. The bug is a **phase offset**: the `ahb_sub` address
> pipeline presents the address to the bridge one cycle late, so on the master's
> first data-phase cycle the bridge is still in `RESP_FSM_IDLE_BUSY`, where
> `hreadyout = 1` ("ready to accept an address"). A real master reads that as its
> read completing and captures stale data one cycle before the bridge issues the
> AXI read. A cycle trace showed it exactly: `sub_hrdyout=1` with `rvalid=0` on the
> AR-accept cycle. The fix holds `ahb_sub_hreadyout` low for that single
> pipe-offset cycle on a read (a registered `rd_pipe_r` flag), so the master waits
> for the bridge's genuine `r_done`. It masks only the master-facing `hreadyout`,
> not the bridge's internal `hready`, so there is no desync; writes never set it.
>
> **Packaging (TideLink pin stays frozen).** The fix lives as a chiplet-local
> override — `src/rtl/local_overrides/tidelink_top.sv` — which
> `resolve_tidelink_flist.py` swaps in for the frozen submodule's copy (one
> definition per module, no submodule edit). The minimal diff is
> `patches/0003-tidelink-ahb_sub-read-pipe-offset.patch`, ready to apply upstream
> when TideLink rolls forward, after which the override can be deleted.

### Burst hardening — `STAGE 2c`

A single write and a single read prove the pipe-offset fixes, but the fixes must
also hold **across consecutive beats** — the `hready_to_peer` comb-loop break and
the `rd_pipe_r` read mask both key off per-transfer state, so back-to-back traffic
is where a stale-state bug would surface. `STAGE 2c` writes an 8-word sequence
(`0x2F00_1000..1C`, values `0x5EED_00i i`) across the aperture, then reads all
eight back and asserts each beat: `8-word write+read sequence across the aperture,
all beats intact`. This is the guard against a fix that works once but corrupts a
burst (a memcpy across the aperture, the realistic access pattern).

_Original finding, preserved:_

Found 2026-07-10 by adding a read-back stage (`STAGE 2b`) to
`test_peer_write_crosses_to_die_b`.

After the write lands (Stage 2), die A reads `0x2F00_1000` back and gets `0x0`
instead of `0xC0FFEE01`. A cycle trace on die A's read pins it:

```
RTRACE +0  m_hready=1 selp=1 | tl: sub_hrdyout=0 pipe_v=0 arv=0 rv=0 r_rdata=0
RTRACE +1  m_hready=1 selp=0 | tl: sub_hrdyout=1 pipe_v=1 arv=1 arr=1 rv=0 r_rdata=0
```

At `+1` TideLink's `ahb_sub` asserts `hreadyout=1` (the master takes it as "read
done") on the cycle it **accepts the AXI read address** (`arvalid&arready`), while
the read **data** channel is still empty (`rvalid=0`, `r_rdata=0`). The read data
only returns after the multi-cycle link round-trip, but the transfer has already
completed with a stale `0`.

**Why `g2_peer_aperture` did not catch it.** Its far side is an `ahb_probe_mem`
with **zero-latency** (combinational) read data — the data was valid the instant
the address was accepted, so "complete on AR-accept" happened to be correct. A
real SoC across a real link returns read data many cycles later, which exposes it.

**Why this is not a same-day fix like the write.** The write drop was fixed by a
one-cycle `hwdata` delay in the integration (`nanosoc_eth_chiplet.sv`) — the data
was present, just one cycle early. The read needs the transfer to **wait** until
`rvalid`, and the "read data valid" signal lives **inside frozen TideLink**. A
clean fix is a TideLink `ahb_sub` change (hold `hreadyout` low for a read until the
AXI R beat returns). A chiplet-side workaround would have to withhold the master's
`hready` until read data is valid without re-introducing the combinational loop —
possible but not obviously safe, and it wants its own analysis + guard.

**Impact.** The peer aperture's primary direction is **write** (push data to the
remote die's SRAM; signal arrival with the native doorbell IRQ), which is proven.
Remote **reads** (die A reading die B's memory) are the affected, less-common
direction. Firmware that only writes across the aperture is unaffected.

**Next step for the verification/physical team:** decide TideLink-side hold-until-
`rvalid` vs a chiplet-side read-completion gate; add a `g2_soc_pair` read assertion
once fixed; consider a focused fast env (real SoC master → decode → TideLink →
a **latency-injecting** far-side memory) so the read fix does not need the full
two-SoC bring-up to iterate.

---

## Files

| Path | What |
|---|---|
| `verif/g2_soc_pair/tb_g2_soc_pair.sv` | tb: two `nanosoc_eth_chiplet`, pad cross-wire, straps, flash models |
| `verif/g2_soc_pair/Makefile` | `make elab` (milestone 1) + `make sim` (cocotb, milestone 2) |
| `verif/g2_soc_pair/test_g2_soc_pair.py` | smoke + full-G2 cocotb tests |
| `docs/G2_SOC_PAIR_STATUS.md` | this file |
