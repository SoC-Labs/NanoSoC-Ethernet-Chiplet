# Chiplet-level SpyGlass CDC

Structural clock-domain-crossing setup for the **integrated** ethernet chiplet.

Nine blocks below this level each ship a `.sgdc` and a `waiver.swl`. The
integrated chiplet shipped none. The crossings this repository actually *owns*
are the ones at the seams **between** those nine blocks — SoC fabric ↔ D2D link,
fabric ↔ RTC/PTP, fabric ↔ RMII/MII, fabric ↔ QSPI, fabric ↔ SWD — and no block
file can see them, because every one of them stops at its own port list. Until
this directory existed, that boundary had never been analysed by a tool that
understands asynchronous clock relationships.

**Status: run twice.** The first (B7 baseline) run is recorded in
`docs/verification/CDC_B7_BASELINE.md`; the declaration-fix round that followed it is in
`docs/verification/CDC_B7_ROUND2.md`. Read §7 (what this does not cover) and §8 (what the two
runs changed) before quoting any result. It is still written to be *reviewed*
before it is believed — the same posture as
`constraints/nanosoc_eth_chiplet_cdc.sdc`.

> **The count fell from 152 unsynchronised crossings to 137, and that fall is
> the SETUP converging, not bugs being fixed.** No RTL changed. Do not report it
> as progress on the design.

### The rule this setup is written to

> **An absent declaration over-reports. A wrong declaration masks.**

A port left unconstrained gets a virtual clock and shows up as a crossing you
then have to explain — noisy, but every real crossing is still in the report. A
port bound to the *wrong* clock is silently made same-domain, and a real
crossing disappears from the report entirely. These two failure modes are not
symmetric and must never be traded off as if they were. Where a port's launch
clock could not be established from the RTL, it is left in the explicit
"not yet constrained" block or carries a `TODO(cdc)` — never a guess.

---

## 1. The top is `nanosoc_eth_chiplet`, not `nanosoc_eth_chiplet_chip`

Two tops exist. The lint flow uses the generated pad-facing wrapper
`nanosoc_eth_chiplet_chip`; the HAL CDC flow (`verif/cdc/run.sh:38`) uses the
inner `nanosoc_eth_chiplet`. This setup uses the **inner** top. That is a
deliberate choice, and it is the single most consequential decision in the
directory.

**The wrapper aliases three clocks onto one.**
`build/chip/rtl/nanosoc_eth_chiplet_chip.v:101-103`:

```verilog
.idelay_ref_clk (1'b0),      // tied
.rtc_clk        (sys_fclk),  // tied
.user_ref_clk   (sys_fclk),  // tied
```

`rtc_clk` and `user_ref_clk` — the RTC/PTP timebase and the Wlink PLL reference —
*are* `sys_fclk` at that level. Elaborating there would make the fabric↔RTC and
fabric↔Wlink-reference crossings **same-domain by construction**, and SpyGlass
would report nothing at two of the boundaries this analysis exists to examine.
That is not a clean result; it is a result that cannot be dirty. The chip SDC
says the same thing about itself, at
`ASIC/genus-innovus/inputs/constraints.sdc:64-71` and `:145-149`: *"what used to
be a genuine asynchronous crossing inside the Wlink controller is synchronous in
this build."*

**`role_locked_o` has nothing to bind to at the wrapper.** It is left open
(`nanosoc_eth_chiplet_chip.v:175`), so the reset declaration in §3 of the SGDC —
which is what makes the a2l replay CDC and the whole recovered-RX-clock domain
analysable at all — is only expressible at the inner top.

**The DFT pins and straps are ports at the inner top.** At `_chip` they are
internal tie constants (`:113-123`), so `set_case_analysis` and `quasi_static`
have no object to attach to.

**Coverage.** 111 ports versus 37. The port census that §5 of the SGDC turns
into `abstract_port` declarations is meaningful at the inner top and largely
vacuous at the wrapper.

**Same top as the existing HAL run**, so the two CDC flows compare like for like
(`verif/cdc/run.sh:38`).

### The wrapper run is still worth doing — later, and separately

The aliasing is a real property of the taped-out part, not an artefact. A run at
`SG_TOP=nanosoc_eth_chiplet_chip` would confirm the *aliased* build and is a
one-variable change (§2). It answers a different question — "is the bonded chip
consistent?" — and it must not be mistaken for boundary coverage.

---

## 2. How to run it

SpyGlass **is** installed and licensed on this host, despite what
`docs/verification/LINT_FINDINGS.md` §1 ("SpyGlass / `sg_shell`: absent") and
`docs/verification/CDC_FINDINGS.md` say. Both are wrong; `docs/verification/CDC_FINDINGS.md` already
carries a correction to that effect at the top. The binary is:

```
${SPYGLASS_HOME}/bin/spyglass
```

### Prerequisites — render the generated collateral first

The filelist `-f`-includes two **generated** sub-flists and one generated
wrapper. Render them or the read fails on a missing file, which looks nothing
like a CDC problem:

```bash
cd $CHIPLET
make asic-flist      # -> build/chip/flist/{soc,tidelink_asic}.flist
make chip-wrapper    # -> build/chip/rtl/nanosoc_eth_chiplet_chip.v
```

`make asic-flist` needs the `deps/tidelink-phy` submodule (SSH remote — a plain
`git submodule update --init` over https will not fetch it; `make bootstrap`
covers it). See `Makefile:310-329`.

### Run

```bash
export CHIPLET=$(git rev-parse --show-toplevel)

# Set SPYGLASS_HOME to your SpyGlass install's SPYGLASS_HOME directory.
# tidelink/cdc/Makefile already carries this site's default and is a working
# driver — read it rather than re-deriving the path here. Deliberately not
# hardcoded: this repository is public.
: "${SPYGLASS_HOME:?set to your SpyGlass install (see tidelink/cdc/Makefile)}"

# Environment for the flist, in dependency order — the same three scripts and
# the same order `make elab` uses (Makefile:10-16). Order matters: TideLink
# defaults CMSDK_DIR with `:=`, so the SoC's choice must be set first.
source $CHIPLET/set_env.sh
source $CHIPLET/nanosoc-multicore-system/set_env.sh
source $CHIPLET/tidelink/set_env.sh

export FLIST=$CHIPLET/flist/nanosoc_eth_chiplet_asic.flist
export SG_TOP=nanosoc_eth_chiplet
export SGDC=$CHIPLET/cdc/nanosoc_eth_chiplet.sgdc
export SWL=$CHIPLET/cdc/waiver.swl

$SPYGLASS_HOME/bin/spyglass -batch \
    -project $CHIPLET/cdc/nanosoc_eth_chiplet.prj \
    -goals "cdc/cdc_verify" < /dev/null
```

`< /dev/null` is not decoration. Genus, Innovus and the SpyGlass shell all hold
a licence seat at an interactive prompt if stdin stays open.

With `-goals` and no `-work_dir`, SpyGlass writes to
`<top>/<top>/cdc/cdc_verify/spyglass_reports/` — the same layout
`tidelink/cdc/Makefile:31-33` documents.

### Variants

| Want | Change |
|---|---|
| The bonded-wrapper run (§1) | `export SG_TOP=nanosoc_eth_chiplet_chip` |
| The FPGA/sim netlist instead of ASIC | `export FLIST=$CHIPLET/flist/nanosoc_eth_chiplet.flist` — **but read §6 first**, three SGDC ports exist only under `+define+TIDELINK_PHY_V2` |
| Un-black-box the D2D controller (step **B8**) | delete `axi_chiplet_controller` from the `set_option stop_module` line in the `.prj` — one token, nothing else |

### Why there is no Makefile here

`tidelink/cdc/Makefile` is the model for the flow above, but this directory
deliberately ships only the four reviewable inputs. The commands are above; wire
them into the top-level `Makefile` (next to the existing `cdc:` target, which
drives the Cadence HAL pass) when someone owns running this regularly.

---

## 3. Which period set, and why

**Chosen: the ASIC chip SDC set**, i.e. `CLK_PERIOD = 10.0`
(`ASIC/common.mk:183`) and everything derived from it.

Structural CDC (`cdc_verify`) does not use the period to decide whether a
crossing *exists* — it is a structural analysis over clock domains. But a single
self-consistent set is still required, for two reasons: the domain names must
mean the same thing they mean in synthesis, and the ratio-sensitive rules
(`Ac_conv*`, data-hold checks) must not be fed contradictory numbers. The block
files could not simply be merged: **they disagree with each other and with the
chip.**

### The reconciliation

| Clock / role | Block-level `.sgdc` | Chip SDC | This setup |
|---|---|---|---|
| System / fabric | **4.0** — `tidelink_top.sgdc:28` (hclk), `axi_chiplet_controller.sgdc:22` (app_clk), `xhb500.sgdc:17,24` (clk), `phc.sgdc:21`, `phc_ahb.sgdc:24`, `ethernet_ss_ahb.sgdc:26` (sys_fclk)<br>**10.0** — `ethmac_ahb.sgdc:24`, `ethmac_subsystem_apb.sgdc:25`, `top_ahb_qspi.sgdc:53,56`<br>**40.0** — `nanosoc_multicore_soc.sgdc:40` (sys_fclk) | `clk` **10.0**<br>`constraints.sdc:61` | `sys_fclk` **10.0**<br>`sys_hclk` **10.0** |
| SWD probe | **333.0** `nanosoc_multicore_soc.sgdc:53` | `swdclk` **40.0** (4 × EXTCLK)<br>`constraints.sdc:20,62` | **40.0** |
| RMII reference | *not declared anywhere* | `rmii_ref_clk` **20.0**<br>`ethernet_constraints.sdc:19,23` | **20.0** |
| MII rx / tx | **40.0**, as **two** async domains — `ethmac_ahb.sgdc:27,30`, `ethmac_subsystem_apb.sgdc:28,31`, `ethernet_ss_ahb.sgdc:32,35`, `nanosoc_multicore_soc.sgdc:44,45` | ÷2 → **40.0**, **one** group with `rmii_ref_clk`<br>`constraints.sdc:192` | **40.0**, **one** domain (§4.6) |
| RTC / PTP | **10.0** — `ethernet_ss_ahb.sgdc:29`, `ethmac_subsystem_apb.sgdc:34`, `nanosoc_multicore_soc.sgdc:48` | *not created* (aliased onto CLK) | **30.518** `[OWNER]` |
| QSPI serial | **40.0** `top_ahb_qspi.sgdc:60`<br>**80.0** `nanosoc_multicore_soc.sgdc:60` | `QSPI_SCLK` = clk ÷ 2 = **20.0**<br>`qspi_constraints.sdc:2` | **20.0** |
| Wlink PLL ref | **8.0** `tidelink_top.sgdc:34` | *not created* (aliased onto CLK) | **8.0** `[OWNER]` |
| D2D RX pad | **4.0** `tidelink_top.sgdc:37` | `D2D_RX_CLK_0` **10.0**<br>`tidelink_constraints.sdc:38-39` | **10.0** |
| D2D RX **word** | **64.0** (= 16 × 4.0) `axi_chiplet_controller.sgdc:30` | `D2D_RX_WORD_CLK_n` ÷16 → **160.0**<br>`tidelink_constraints.sdc:124-125` | **160.0** |
| PHC | **10.0**, own `phc_domain` `tidelink_top.sgdc:31` | n/a | *no separate object* (§4.5) |
| IDELAY ref | **5.0** `tidelink_top.sgdc:103` | *none* (ASIC ties off) | **5.0** |

The two `[OWNER]` values are the only numbers **not** from the chip SDC, because
the chip SDC does not create them at all — the pad wrapper aliases both onto the
system clock. They are carried from `constraints/nanosoc_eth_chiplet_cdc.sdc:32`
and `:42`, and marked with the same `[OWNER]` convention that file uses.

Note the ×10 spread on the system clock (4.0 / 10.0 / 40.0) for one physical
net, and the ×8 spread on SWD (333.0 vs 40.0). None of this changes a structural
verdict; all of it would change a ratio-sensitive one.

---

## 4. Inconsistencies found between the existing files

Everything here was verified against RTL, not inferred from a sibling constraint
file. **None of these files was edited** — other agents own them.

### 4.1 `nanosoc_multicore_soc.sgdc` declares CPU ports that do not exist

Lines 98-103 declare `cpu_0_nmi`, `cpu_0_rxev`, `cpu_1_nmi`, `cpu_1_rxev`,
`cpu_0_pmuenable`, `cpu_1_pmuenable`. The generator renamed the cores: the real
ports are `network_core_*` and `chip_core_*`
(`src/rtl/nanosoc_eth_chiplet.sv:77-92`, mirroring the SoC top 1:1). Six
declarations matching nothing.

### 4.2 `nanosoc_multicore_soc.sgdc` puts the PHC outputs in the wrong domain — *this one masks*

Lines 125-127 declare `phc_pps_out`, `phc_pps_irq` and `phc_alarm_irq`
`-clock rtc_clk`. They are **fabric** signals:

```
nanosoc_multicore_soc.sv:1036-1038   phc_ahb ... u_phc_0 ( .HCLK(u_network_core_sys_hclk) ...
nanosoc_multicore_soc.sv:1074                              .pps_out (phc_pps_out)
```

and the PHC's own block file agrees — `phc_ahb.sgdc:24`, *"all logic runs on
hclk"*. This is the dangerous kind of error: at the chiplet level `phc_pps_out`
feeds `u_tidelink.phc_pps` (`nanosoc_eth_chiplet.sv:855`), so declaring it
`rtc_clk` **invents** a crossing there that does not exist, and simultaneously
implies the real rtc→fabric handoff has already happened when it has not (it is
upstream, inside the HA1588 servo). This setup declares all four PHC/servo
outputs on `sys_hclk`. `ha1588_servo_locked` likewise: `u_ha1588_servo` is
clocked by `pclk` (`ethmac_subsystem_apb.v:620-623,653`), not `rtc_clk`.

### 4.3 `ethernet_ss_ahb.sgdc` is scoped to a top this chip does not build

`current_design ethernet_ss_ahb` (line 19). The SoC instantiates
**`ethernet_ss_ahb_rmii`** (`nanosoc_multicore_soc.sv:834`). Every constraint and
waiver in that file applies to a design unit this chip does not contain, and it
carries `mtx_clk_i` / `mrx_clk_i` port-clock names that the RMII top does not
have. Nothing was copied from it.

### 4.4 `axi_chiplet_controller.sgdc` has fallen eleven ports behind the RTL

The file documents this exact hazard in its own comments (`:60-81`): three ports
renamed by a local override went unmatched, SpyGlass **defaulted** them to
`user_ref_clk` and manufactured two spurious `Ac_unsync01` crossings. The same
drift has recurred. Re-deriving the port list from the source this build
compiles — `tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv`, per
`build/chip/flist/tidelink_asic.flist:187` — turns up **eleven** ports the block
file does not enumerate:

| Port | Why it matters |
|---|---|
| `apb_ctrl_reg_rf` | Region-F select, declared at `axi_chiplet_controller.sv:254`, *"exactly mirroring"* its `apb_ctrl_reg_rd` (`:247`) and `apb_ctrl_reg_r10` (`:242`) siblings, which the block file *does* declare. Driven from `u_tidelink_fifo` on hclk (`tidelink_top.sv:2017,2863`). **The identical omission that caused the two documented spurious crossings, recurring on a third port of the same interface.** |
| `data_mode_o` | The FCSM≥4 strobe gating TideChart's root election (`nanosoc_eth_chiplet.sv:897,985`). Verified **apb_clk**, from `sync_obs_fcsm_state_1` (`:6404`, the far side of an apb_clk 2-FF sync at `:1985`; the port comment states the domain at `:504`). Had it been link-domain, the path into `u_tidechart` would be an unsynchronised crossing — and a careless `app_clk` guess would have hidden it. |
| `generalbus_in`, `sb_reset_in`, `sb_wake` | Tied / open at the instance (`tidelink_top.sv:2971,2822,2824`), so benign today — but an unbound port on a stopped module is a default waiting to happen. |
| `interrupt`, `nego_error_irq`, `train_fail_irq_o` | All three reach the `d2d_irq` vector (`nanosoc_eth_chiplet.sv:1033-1035`). |
| `obs_a2l_replay_link_valid_o`, `obs_fe_rx_credit_max_o`, `obs_fe_rx_is_full_o`, `obs_a2l_replay_app_valid_o` | Bug-A FCSM taps; all four are the far side of the same apb_clk 2-FF chain (`:6394-6398`). Dangling in this build (`tidelink_top.sv:805-809` declare the receiving wires; nothing reads them). |

That is why the black-box constraints live in the chiplet SGDC rather than being
read from `tidelink/cdc/*.sgdc` — that, and the period conflict in §3.

**The upstream fix wanted:** `tidelink/cdc/axi_chiplet_controller.sgdc` needs
these eleven added, and its `app_clk` / `link_rx_clk_o` periods re-based.

### 4.5 `phc_clk` / `phc_resetn` do not exist as separate objects here

`tidelink_top.sgdc:31,45` declare a `phc_domain` and a `phc_resetn`. Correct for
standalone TideLink, where both are ports. At this integration they are tied to
the fabric:

```
nanosoc_eth_chiplet.sv:765   .phc_clk    (sys_hclk),   // PHC shares the AHB clock in this build
nanosoc_eth_chiplet.sv:766   .phc_resetn (sys_hresetn),
```

Likewise `tidelink_top.hresetn ← sys_hresetn` (`:763`) and `poresetn ←
sys_poresetn` (`:764`). So the six resets named in the brief collapse to four
declarable objects plus `role_locked_o`.

### 4.6 The two MII clocks are **one** domain in this build — *the separate-domain declaration masks nothing but manufactures much*

Four block files declare `mtx_domain` and `mrx_domain` as separate asynchronous
domains. That is **correct at their own scope**: `ethmac_ahb` takes
`mtx_clk_pad_i` / `mrx_clk_pad_i` as ports from a real MII PHY, which sources two
genuinely independent clocks. It is **wrong here.** This chiplet is RMII — one
50 MHz reference generates both halves. Verified in the source this build
compiles (`build/chip/flist/soc.flist:163` →
`.../amba_wb_bridges/src/rtl/rmii_to_mii.v`):

```verilog
:277-283  always @(posedge rmii_ref_clk or negedge rstn_sync)
              if (!rstn_sync) mrx_clk <= 1'b0; else if (tick) mrx_clk <= ~mrx_clk;
:320-326  always @(posedge rmii_ref_clk or negedge rstn_sync)
              if (!rstn_sync) mtx_clk <= 1'b0; else if (tick) mtx_clk <= ~mtx_clk;
```

Same launch edge, same async reset, same enable (`tick`, `:152`), same reset
value. The two waveforms are bit-identical *by construction* — they cannot drift
or skew relative to one another, and cannot present a metastability window to
each other. Declaring them as two async domains would manufacture mtx↔mrx
crossings that are physically impossible and bury the real fabric↔MII findings
underneath them. Both sit in `rmii_domain` here, together with `rmii_ref_clk`
(deterministic ÷2 off the same edge) — which is exactly how the chip SDC groups
them: `-group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}]`
(`constraints.sdc:192`).

Neither the MII clocks nor QSPI appear in `constraints/nanosoc_eth_chiplet_cdc.sdc`
at all; that file declares `rmii_ref_clk` and stops.

### 4.7 `constraints/nanosoc_eth_chiplet_cdc.sdc` names a port that does not exist

Lines 49 and 53 do `create_clock ... [get_ports swd_clk]` and
`[get_ports scan_clk]`. The chiplet port is **`dap_swclktck`**
(`nanosoc_eth_chiplet.sv:94`); there is no `swd_clk` port at any level. `scan_clk`
does exist (`:196`). That file is consumed by no tool today, which is how the
stale name survived — worth fixing when someone wires it into STA.

### 4.8 DFT: `quasi_static` where `set_case_analysis` belongs — **resolved**

`ethernet_ss_ahb.sgdc:54-55` declares `sys_testmode` and `sys_scanenable`
`quasi_static`, with an honest comment: without them SpyGlass heuristically
assigns the ports to `mrx_clk_i` and reports three false unsync crossings into
the Cortex-M0+ PRMU clock-enable logic.

The symptom is real; the cure is under-strength. Both are **tied constants** in
this build, not merely slow-moving:
`build/chip/rtl/nanosoc_eth_chiplet_chip.v:119-123` ties the five `scan_*` pins
to 0, and `:40-41,83-84` bond `sys_scanenable`/`sys_testmode` to pads strapped inactive
in mission mode. `set_case_analysis` propagates the constant and **deletes** the
scan-only logic from the analysis; `quasi_static` only says "this does not change
often", which leaves the scan muxes in the netlist carrying paths between domains
that mission mode can never take. All seven DFT pins are case-analysed here. The
SoC-level file had already reached the same conclusion for those two
(`nanosoc_multicore_soc.sgdc:80-81`) — the block file is the outlier.

### 4.9 `dap_swj_enable`: deliberate divergence the other way

`nanosoc_multicore_soc.sgdc:86` uses `set_case_analysis -value 1`. Here it is
`quasi_static`. It is a **configuration strap**, not a DFT tie: a multi-chiplet
package pins it 0 on inactive dies to quiesce the SWD line. Case-analysing it to
1 would constant-propagate the SWD path permanently on and delete the muxing that
build depends on.

### 4.10 `apb_debug_unlock_i` / `puf_ready`: deliberate divergence from TideLink

`tidelink_top.sgdc:98-99` and `axi_chiplet_controller.sgdc:83-84` declare both
hclk-launched. Correct in the standalone TideLink bench, where they come from
SoC-clocked logic. Not correct here: at the chiplet boundary they arrive from the
pad ring with no launch clock at all (`nanosoc_eth_chiplet.sv:184,186`; tied 0 at
`nanosoc_eth_chiplet_chip.v:115,128`). Claiming an hclk launch would assert a
synchronous relationship the package does not provide. Both are `quasi_static`
here.

### 4.11 `tidechart.sgdc` declares no clock at all

Three lines of constraint: `current_design tidechart_controller` and
`reset -name resetn -async -value 0`. No `clock`, no `abstract_port`. That is
adequate for a single-clock block analysed alone; it contributes nothing at
integration. TideChart's clock is `sys_hclk` here (`nanosoc_eth_chiplet.sv:971`).

### 4.12 The docs claim SpyGlass is not installed

`docs/verification/LINT_FINDINGS.md` §1 lists *"SpyGlass / `sg_shell` — absent: no `which`
hit; do not assume it exists"*. `docs/verification/CDC_FINDINGS.md` defers the step to another
machine. Both are wrong (the latter already carries a correction at the top); the
binary is at the path in §2 and the licence checks out.

---

## 5. What is black-boxed, and what deliberately is not

`set_option stop_module` in the `.prj`. Stopping a module is **not free**: every
port without an `abstract_port` gets a default domain, and a defaulted port on a
black box is how you manufacture a crossing that does not exist. So a module
goes on the list only when its port set has been enumerated against the RTL, or
when it is genuinely single-clock and can be wildcarded honestly.

**Stopped:**

| Module | Basis |
|---|---|
| `axi_chiplet_controller` | Full port set enumerated and verified against `tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv`. **Kept stopped for now on purpose** — see B8 below. |
| `xhb500_ahb_to_axi_bridge_chiplet_slv`, `xhb500_axi_to_ahb_bridge_chiplet_mst` | Single `clk` input each (`..._slv.sv:26`, `..._mst.sv:28`); `abstract_port -ports "*"` onto one domain is honest, not a shortcut. |
| `rf_01k` / `rf_08k` / `rf_16k` / `rf_32k` | TSMC65 compiled register files (`sl_sram.v:57,77,97,117,154`; `ethmac_sram.v:51`). Their Verilog models are in **no** filelist this build reads — Genus takes them from `.lib` — so SpyGlass already treats them as undefined. Listing them makes that explicit and stable. |

**B8 — un-black-boxing the D2D controller is a one-token change.** Delete
`axi_chiplet_controller` from the `stop_module` line. Nothing else changes: the
§7a `abstract_port` block goes inert (port constraints apply only to
stopped/undefined units) and ~6800 lines enter the analysis, including the a2l
replay CDC and the recovered-RX-clock domain. Expect a much longer run and a much
bigger report. **Do it as its own change**, or you will not be able to tell new
crossings from new constraints.

**NOT stopped — and this is where this setup departs from its brief.** Arm
CMSDK/CoreSight were named as black-box candidates. They are left elaborated:

- **`CM0PDAP`** is genuinely **two-domain** — SWD probe clock one side, fabric
  the other. `abstract_port -ports "*" -clock <one clock>` would collapse the
  `swclktck ↔ sys_hclk` boundary into a single domain and delete the most
  important debug-path crossing in the design from the report. Its port list has
  not been enumerated here, so the honest alternative (a verified per-port split)
  is not available yet. Per the rule at the top of this file, **absent beats
  wrong.**
- **`CORTEXM0PLUS`** has FCLK/HCLK/DCLK/SCLK plus debug pins whose domain
  membership has not been checked.
- The single-clock CMSDK leaf cells (`cmsdk_ahb_to_apb`, `cmsdk_ahb_to_sram`,
  `cmsdk_apb_slave_mux`) carry the real APB/AHB paths of this repository's own
  two integration bridges; black-boxing them would put a defaulted-domain
  boundary in the middle of the logic under test.

The cost is runtime and extra INFO lines. The benefit is that the DAP's vendor
CDC cells (`cm0p_dap_ap_cdc.v`, `cm0p_dap_dp_cdc.v`, `cm0p_dap_cdc_capt_sync.v`)
come back as **recognised synchronisers** — which is the result a first pass
should produce. If runtime turns out intractable, the fix is to enumerate
`CM0PDAP`'s ports and add a verified two-domain block, **not** to wildcard it
onto one clock.

---

## 6. Waivers: the file is empty on purpose

`cdc/waiver.swl` contains no waivers. You cannot waive findings you have not
seen, and a blanket waiver is exactly how a real crossing hides. Three things
were deliberately **not** carried over:

1. **`waive -du "Wlink" / "Wav*" / "Wlink*" / "wlink_*"`**
   (`tidelink/cdc/waiver.swl:43-45,51`),
   justified in-file as covering untouched Chisel-generated vendor IP. That
   justification is **false for this build**: `tidelink/src/rtl/local_overrides/`
   holds 33 locally-modified module copies and **24 of them match those exact
   patterns** — including `wlink_wlink_ptp_tl_a2l_48x4.v` (the a2l mailbox
   itself), `WlinkGenericFCReplayV2_12.v` / `_13.v` (which carry the a2l CDC fix
   never ported to their AW/W/B siblings — also waived), and
   `WavMultibitSync_18.v`, a locally-modified **synchroniser primitive** waived
   as a "verified CDC cell". The blanket patterns suppress locally-modified logic
   sitting on the exact path with a known open bug.
2. **`waive -rule checkSGDC_05`** — global and unscoped at
   `tidelink/cdc/waiver.swl:133-134`. That rule is the **unmatched-`abstract_port`
   detector**: the tree's only automatic guard against the §4.4 failure mode.
   Waiving it switches off the alarm for the failure. It stays **active** here,
   along with `SGDC_abstract_port02` and `checkSGDC_01`. If one fires, a port
   name has drifted — fix the name, do not silence the check.
3. **The legitimate synchronisers**, which should come back as *results*:
   `WavMultibitSync` / `WavDemetReset*` / `WavDemetSet`
   (`tidelink/deps/axi-chiplet-controller/logical/wlink/`); the OpenCores MAC
   chains `TxRetrySync1` / `TxAbortSync1` / `TxDoneSync1`
   (`eth_wishbone.v:458-460`), `BlockingTxStatusWrite_sync1/2` (`:770-788`),
   `TxStartFrm_sync1` (`:1215-1254`); and the `eth_rx_cksum` MII↔fabric chains
   `rptr_gray_mrx_s0/_s1`, `mode_mrx_s0/_s1` (`eth_rx_cksum.v:409-417`),
   `ovf_tog_pclk_s0/_s1/_s2` and `push_tog_pclk_s0/_s1/_s2` (`:482-491,512-515`).
   Expect these as recognised/informational. **If any appears as
   *unsynchronised*, that is a finding, not a waiver candidate.**

### One build-conditional hazard

Three `axi_chiplet_controller` ports — `obs_epoch_anchored_o`,
`obs_epoch_span_o`, `xhb_sub_obs_word_i` — exist **only** under
`+define+TIDELINK_PHY_V2` (`axi_chiplet_controller.sv:522-534`). The default ASIC
filelist defines it (`build/chip/flist/tidelink_asic.flist:3`). Point the `.prj`
at a V1 filelist without deleting that SGDC block and you get
`SGDC_abstract_port02` **fatal → exit 7 → a run that reports "0 clocks / 0
crossings"** and looks like a tool failure. The block is fenced and labelled in
the SGDC.

---

## 7. What this setup does **not** cover

Read this before treating any output as coverage.

1. **It has never been run.** No baseline, no violation count, no evidence the
   filelist elaborates under SpyGlass. Every claim here is about the *inputs*.
2. **`axi_chiplet_controller` is black-boxed** — so the a2l replay CDC, the
   recovered-RX-clock domain and the whole Wlink datapath are outside the
   analysis until B8. Given that TL-009 (`docs/`, the a2l CDC self-latch) lives
   exactly there, this is the largest single hole and B8 is the first follow-up.
3. **The PL022 SPI serial clock is not declared.** The PL022 divides the fabric
   clock to SSPCLKOUT internally; the correct model is a generated clock on that
   divider, as QSPI gets. The anchor has not been verified in RTL, so it is not
   declared — guessing a hierarchical pin is how §4.4 starts. `spi_sclk`,
   `spi_mosi` and `spi_ss` are declared fabric-domain as a conservative interim
   and `spi_miso` is left unbound: **a clean SPI result is not SPI coverage.**
   `TODO(cdc)` in the SGDC.
4. **Four pads are deliberately unconstrained** — `uart_rxd`,
   `chip_core_uart_rxd`, `spi_miso`, `hostio4_p1_in`. They have no launch clock;
   binding them to the fabric would make them same-domain and hide real
   crossings. They will appear as `SG_VCLK_*` crossings, which the receiving IP's
   synchroniser (e.g. `cmsdk_apb_uart.v:499`, `rxd_sync_1 <= RXD`) should answer.
   If they bury the real findings, declare the PL022 clock — **do not** bind them
   to `sys_hclk`.
5. **The memory macros are unconstrained black boxes.** Single-clock, so they
   cannot create a cross-domain path *through* one. If the first run reports
   crossings **at** a memory boundary, add `current_design rf_*` blocks with the
   domain set **per instance site** — the ethmac RX FIFO memories are in the MII
   domain, not the fabric.
6. **`sys_hclk`'s divide ratio from `sys_fclk` is still `[OWNER]`.** They are put
   in one domain because they are synchronous, which is not in doubt; the ratio
   is (`constraints/nanosoc_eth_chiplet_cdc.sdc:65-71`).
7. **The `rtc_clk` and `user_ref_clk` periods are placeholders** carried from the
   integration SDC. The real D2D unit interval is a link-budget question that has
   no owner yet (`ASIC/genus-innovus/inputs/tidelink_constraints.sdc:30-38`).
8. **This is structural CDC only** — `cdc/cdc_verify`. No functional/formal
   verification of the synchronisers, no reset-domain-crossing goal
   (`cdc/cdc_verify_struct` + RDC is a separate goal worth adding), no glitch
   analysis, and nothing about the *protocol* correctness of a handshake that is
   structurally well-formed.
9. **The bonded-wrapper build is not analysed** (§1). The aliasing is real
   silicon behaviour; confirming it needs its own run.
10. **Nine block-level setups remain un-reconciled upstream.** §4 lists what is
    wrong with them; none was edited. Until those are fixed, a block-level green
    and a chiplet-level green are not the same claim.
