# 20 — Genus synthesis audit (baseline 2026-08-05)

[index](00-index.md) · [11 Known issues](11-known-issues.md) · [13 LEC](13-lec.md) · [16 Open defects](16-open-defects.md)

Audit of the **Genus** stage only — elaboration through `write_hdl`. Motivated by the
prior build that lost a datapath to Genus unused-logic removal (`GLO-34`) and shipped a
hollow GDSII.

**Method: entirely static.** No Genus, Innovus, Calibre or LEC session was opened; a P&R
run held the seats throughout. Nothing under `work/`, `outputs/`, `reports/`, `logs/` or
`baseline_*/` was modified. Every claim below is traceable to a file already on disk.

| Source | Path |
|---|---|
| Synthesis logs (8 runs) | [`baseline_2026-08-05/logs/syn_logs.log{,1..7}`](../../ASIC/genus-innovus/baseline_2026-08-05/logs/) |
| Low-power checks | [`syn_cpf_check.log`](../../ASIC/genus-innovus/baseline_2026-08-05/logs/syn_cpf_check.log), [`syn_pow_check.log`](../../ASIC/genus-innovus/baseline_2026-08-05/logs/syn_pow_check.log), [`syn_lib_check.log`](../../ASIC/genus-innovus/baseline_2026-08-05/logs/syn_lib_check.log) |
| Reports | [`syn_{area,gates,power,timing}.rep`](../../ASIC/genus-innovus/baseline_2026-08-05/reports/) |
| Flow | [`ASIC/asic-flows/Cadence/1_synthesis.tcl`](../../ASIC/asic-flows/Cadence/1_synthesis.tcl), [`scripts/config.tcl`](../../ASIC/genus-innovus/scripts/config.tcl), [`ASIC/common.mk`](../../ASIC/common.mk) |
| Netlists | `outputs/nanosoc_eth_chiplet_pads_gate.v` (38 MB), `_gate_power.v` (43 MB) |

`syn_logs.log7` (Aug 05 11:21 → 12:56) is the run that produced the shipped
`reports/` and `outputs/`. Logs echo sourced TCL prefixed `@file NNN:`; all greps below
filter those out.

---

## Verdict summary, worst first

| | Finding | Verdict | Impact |
|---|---|---|---|
| [A](#a-the-glo-34-defect-class-is-not-auditable-from-these-logs--and-removal-is-not-reproducible) | `GLO-34`/`GLO-12` removal is unlogged **and non-deterministic** | **REAL — process defect** | the one control that failed last time is still absent; counts move run-to-run |
| [B](#b-the-power-intent-is-inert-end-to-end) | UPF resolves against **zero** objects; emitted CPF is empty | **REAL — flow defect** | every macro/pad PG connection in the UPF is dead; downstream gets no intent |
| [C](#c-34-pad-ring-pg-pins-sit-on-unconnected-nets-2-boot-rom-pgen-undefined) | 34 pad PG pins on `UNCONNECTED*`; both boot-ROM `PGEN` undefined | **REAL — electrical** | consequence of B; two Error-severity checks agree |
| [A′](#one-casualty-is-visible--in-the-netlist-not-the-log) | `sync_obs_rxcap0_0` lost bits 19,21,24-30; bit 31 tied `1'b1` | **REAL — debug visibility** | a *named* casualty of the removal class, found in the netlist not the log |
| [J1](#j1-ema-is-inconsistent-across-the-three-sram-wrappers) | `EMA` read-margin differs between SRAM wrappers: 19 macros at `3'b010`, 2 at `3'b000` | **SUSPECTED — silicon margin** | behavioural models ignore `EMA`, so no sim or LEC can ever catch it |
| [J2](#j2-the-ethmac-buffer-descriptor-ram-has-cen-tied-active) | ethmac bd_ram `CEN` tied `1'b0` (permanently enabled) | **REAL — power/robustness** | only macro in the design whose chip-enable is a constant |
| [D](#d-the-low-power-checks-never-ran--a-false-green) | No low-power cells loaded → isolation/level-shifter/`VDDACC` checks impossible | **REAL — false green** | absence of crossing violations is not evidence of none |
| [E](#e-rc-cap-tables-are-for-the-wrong-metal-stack) | mmmc cap tables are ARM `1p9m_6x2z`; tech LEF is TSMC `9M_6X1Z1U` | **REAL — signoff quality** | affects all P&R timing/SI, not synthesis |
| [F](#f-the-local_overrides-silent-substitution-hazard-is-live-but-did-not-fire) | 24/30 `local_overrides` files have same-named `deps/` twins | **LATENT — did not fire** | last-read-wins would discard an override with only an Info-grade warning |
| [G](#g-rom-spec-says-2048-words-the-delivered-macro-is-512) | ROM specs say `words = 2048`; macros are 512 words | **LATENT — currently benign** | regenerating `romlibs/` yields an incompatible 11-bit macro |
| [H](#h-synthesis-timing-is-zerowireload-one-path-1-ps) | `syn_timing.rep` = 1 path, +1 ps, ZeroWireload | **WEAK EVIDENCE** | not a closure claim; no hold, no wire RC |
| [I](#i-no-clock-gating-anywhere) | Zero integrated clock-gating cells inserted | **REAL — power** | registers are 51.95% of total power |

**Cleared on inspection** — eight things that look alarming and are not; reasons in
[Cleared findings](#cleared-findings). Most important: **no black boxes, no unmapped
cells, and no lost datapath was found.** TideLink, the ethernet MAC, the PTP block, both
CPUs and all 21 macro instances are present in the netlist.

---

## A. The GLO-34 defect class is not auditable from these logs — and removal is not reproducible

**VERIFIED (as an evidence gap). Whether anything was wrongly removed: CANNOT BE
DETERMINED without re-running synthesis or running LEC.**

This is ranked first because it is the exact control that failed last time, and it is
still not in place.

### What the log does say

`syn_logs.log7:1190` and the summary table at `:3317`:

```
Info    : Deleting instances not driving any primary outputs. [GLO-34]
        : Deleting 4 hierarchical instances.
        : Optimizations such as constant propagation or redundancy removal could change
          the connections so a hierarchical instance does not drive any primary outputs
          anymore. To see the list of deleted hierarchical instances, set the
          'information_level' attribute to 2 or above. If the message is truncated set
          the message attribute 'truncate' to false to see the complete list.
```

```
| GLO-12      |Info    | 2502 |Replacing a flip-flop with a logic constant 0.  |
| GLO-13      |Info    |   32 |Replacing a flip-flop with a logic constant 1.  |
| GLO-34      |Info    |   39 |Deleting instances not driving any primary      |
| GLO-51      |Info    |   56 |Hierarchical instance automatically ungrouped.  |
| CDFG-508    |Warning |  122 |Removing unused register.                       |
```

**2,502 flip-flops were replaced by a logic constant 0.** Against 58,121 sequential cells
surviving in `syn_gates.rep`, that is ~4% of all inferred state deleted.

### Why it cannot be checked

Three independent reasons, all VERIFIED:

1. **The objects are not named.** `information_level` is never raised in
   [`1_synthesis.tcl`](../../ASIC/asic-flows/Cadence/1_synthesis.tcl) or `config.tcl`, so
   GLO-34 prints only counts, never instance paths.
2. **Output is truncated at 20.** `syn_logs.log7:1231`:
   ```
   Warning : Maximum message print count reached. [MESG-11]
           : Maximum print count of '20' reached for message 'GLO-34'.
   ```
   The same cap fires for `GLO-12`, `GLO-13`, `CDFG-508` and `CDFG-472`. Of 2,502
   constant-0 flops, **20 were printed and none by name.**
3. **The command that would name them was never run.** The GLO-12 message text itself
   says `report sequential -deleted` gives the complete list "(on Reason 'constant0')".
   `1_synthesis.tcl:69-73` writes only `report_area`, `report_timing`, `report_gates`,
   `report_power`.

### The removal is not reproducible run-to-run

Comparing the message-summary tables of the five complete runs in the same baseline:

| Log | GLO-12 | GLO-13 | GLO-34 | ELABUTL-132 | CDFG-508 | CDFG2G-616 | CDFG2G-622 |
|---|---|---|---|---|---|---|---|
| `syn_logs.log3` | 2494 | 33 | **41** | 322 | 122 | 2 | 18 |
| `syn_logs.log4` | 2496 | 32 | **39** | 323 | 122 | 2 | 18 |
| `syn_logs.log5` | 2499 | 32 | **41** | 321 | 122 | 2 | 18 |
| `syn_logs.log6` | 2502 | 32 | **39** | 321 | 122 | 2 | 18 |
| `syn_logs.log7` | 2502 | 32 | **39** | 321 | 122 | 2 | 18 |

The RTL-derived counts (`CDFG-508`, `CDFG2G-616`, `CDFG2G-622`) are **identical** in every
run. The optimiser-derived counts are **not**: GLO-12 drifts 2494→2502 and GLO-34
alternates 39/41. The cause is almost certainly `set_multi_cpu_usage -local_cpu 14`
(`config.tcl:257`, via `soclabs_setup_multi_cpu` called at `1_synthesis.tcl:18`) — Genus
multi-threaded optimisation is not bit-reproducible.

**Consequence:** *which* logic is deleted is not stable, so a clean review of one run does
not certify the next. Only LEC against the shipped netlist can close this.

### What the evidence does support

The GLO-34 events are **not** whole-block deletions. All 20 printed events occur inside a
single stage — `Stage: pre_early_cg` (`:1183`) — immediately after
`Completed mux data reorder optimization (accepts: 32, rejects: 0)` (`:1233`), and the
counts are powers of two (4, 4, 4, 8, 16, 16, 32×13). That is the signature of temporary
datapath bit-slice hierarchies created and discarded by Genus's own datapath
restructuring, consistent with `GB-6 | 529 | A datapath component has been ungrouped`.
Only one GLO-34 event touches state, at `:3701`:

```
Info    : Deleting instances not driving any primary outputs. [GLO-34]
        : Deleting 2 sequential instances.
Time taken by ConstProp Step: 00:00:25
```

This is **SUSPECTED-benign, not verified.** The interpretation rests on stage placement
and count shape, not on any named object.

### One casualty *is* visible — in the netlist, not the log

**VERIFIED.** The logs never name a removed object, but the netlist does, if you look for
surviving registers with missing bits. `nanosoc_eth_chiplet_pads_gate.v:503520`, inside
`axi_chiplet_controller_…`:

```verilog
DFCNQD1 \sync_obs_rxcap0_0_reg[31] (.CDN (hresetn), .CP (user_hsclk),
     .D (1'b1), .Q (sync_obs_rxcap0_0[31]));
```

The surviving bits of `sync_obs_rxcap0_0` are **0-18, 20, 22, 23, 31**. Bits **19, 21 and
24-30 are gone** — nine bits removed by unused-logic optimisation — and **bit 31 is hard
driven to `1'b1`**, a `GLO-13` constant-1 replacement caught in the act.

`obs_rxcap0` is a TideLink receive-capture **observability** register. If firmware reads it
back over APB for eye/window-scan debug, 9 of its 32 bits carry no information and one
reads as a constant. **SUSPECTED impact: chiplet-link bring-up and margining debug only,
not datapath function** — the APB readback mux was not traced, so this is not confirmed as
a software-visible defect.

It is included here because it is the **proof of concept for item A**: this is exactly the
class of silent bit-level loss that the logs cannot show you, found only by inspecting the
netlist. Nothing guarantees `sync_obs_rxcap0` is the only one.

### Recommended (cheap, no re-spin)

Add to `1_synthesis.tcl` before `syn_generic`, and re-run once when a seat frees:

```tcl
set_db information_level 2
set_db message:GLO-34 .truncate false
set_db message:GLO-12 .truncate false
```
and after `syn_opt`:
```tcl
report sequential -deleted > $REPORT_DIR/syn_deleted_seq.rep
```
`write_do_lec` is already emitted at `1_synthesis.tcl:82` — **running that dofile is the
only thing that actually proves no function was lost.** See [13-lec](13-lec.md).

---

## B. The power intent is inert end-to-end

**VERIFIED.** The hand-written UPF addresses a design that does not exist, and the CPF
Genus emits for downstream is empty of everything that matters.

### The UPF names the wrong top

[`ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf`](../../ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf), line 1:

```tcl
set_design_top nanosoc_chip_pads
```

The actual top is `nanosoc_eth_chiplet_pads` (`config.tcl:114`). `nanosoc_chip_pads` is a
**different, older design** — it exists only under
`nanosoc-multicore-system/ethernet-subsystem-ahb/nanosoc_arch_tech/asic/ASIC/nanosoc_chip_pads/tsmc65lp/`.
The UPF was copied from that project and the top was never updated.

### Every macro path in the UPF is wrong

The UPF uses two mutually inconsistent hierarchy prefixes. The bootrom lines use
`u_nanosoc_eth_chiplet_chip/u_soc/u_soc/...` (correct). **All 30 SRAM and cache-RAM lines
use `u_nanosoc_multicore_soc/...`, which is a module name, not an instance name.** The
real instance is `u_nanosoc_eth_chiplet_chip` (`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:140`):

```verilog
nanosoc_eth_chiplet_chip u_nanosoc_eth_chiplet_chip (
```

and `syn_area.rep` confirms the flattened instance is
`u_nanosoc_eth_chiplet_chip_u_soc_u_soc` of module `nanosoc_multicore_soc`.

Sub-blocks were renamed underneath the UPF as well — `u_cpu_ss_1` → `u_chip_core`,
`u_eth_ss_0` → `u_network_core` — and the memory configuration drifted:

| Function | UPF expects | Netlist has |
|---|---|---|
| chip-core dmem | `gen_rf_32k` | `gen_rf_08k` |
| chip-core imem | `gen_rf_32k` | `gen_rf_16k` |
| eth scratch rx/tx | `gen_rf_16k` | `gen_rf_08k` |
| network-core imem | `gen_banked.gen_bank[0..1]` | `gen_rf_32k` (unbanked) |

Three macros have **no UPF entry at all** (17 covered, 19 present) — the ethmac
`bd_ram`, `u_shared_sram_0`, and `u_tidelink/u_tidelink_fifo/u_fifo_mem` (TideLink was
added after the UPF was written).

> **This reclassifies the triaged `34x 1801_REF_OBJ_NOT_FOUND`.** The note at
> `config.tcl:35-37` explains them as "UPF `connect_supply_net` naming macro PG ports …
> that the liberty models do not expose". That explanation is wrong: the liberty exposes
> the PG pins fine — `1801_SUPPLY_CSN_MISSING_FOR_MACRO` reads them and reports
> `pg_type: 'primary_power'` for the same cells. The objects are not found because
> **the paths do not exist.**

### The emitted CPF is empty

`syn_logs.log7:4538` onward — **76 UPF commands failed to translate**, out of 81
non-comment lines in the file:

```
Unable to translate command 'set_design_top' at line '1' ... from 1801 to CPF format.
Unable to translate command 'create_supply_port' at line '7' ...
Unable to translate command 'connect_supply_net' at line '9' ...
```

Breakdown: `connect_supply_net` ×48, `add_port_state` ×12, `create_supply_net` ×4,
`create_supply_port` ×4, `add_pst_state` ×3, `create_supply_set` ×2, `create_power_domain`
×1, `create_pst` ×1, `set_design_top` ×1.

The resulting `outputs/nanosoc_eth_chiplet_pads_gate1.cpf` is 730 bytes **in its entirety**:

```tcl
set_cpf_version 2.0
set_hierarchy_separator "/"
set_design nanosoc_eth_chiplet_pads
create_power_domain -name PD_TOP -default
create_ground_nets -nets VSS
create_power_nets -nets VDD
update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS
end_design
```

**`VDDIO` and `VSSIO` do not appear. No pad supplies, no PST, no macro PG connections.**
Anything downstream consuming this CPF sees a single-rail design.

The re-emitted UPF (`_gate2.upf`) faithfully propagates the bad top:
`set_design_top nanosoc_chip_pads`.

Note also that `config.tcl:125` declares `set power_nets {VDD VDDACC VDDIO}`, but
**`VDDACC` is created nowhere in the UPF** and appears zero times in either check log.

---

## C. 34 pad-ring PG pins sit on UNCONNECTED nets; 2 boot-ROM PGEN undefined

**VERIFIED.** Untriaged, and two independent Error-severity checks corroborate.

`syn_pow_check.log:331-366` — a rule absent from the triage note entirely:

```
PG_CONN_SUPPLY_PIN_CSN_CONFLICT: Instance supply pin connection conflicts with the power
intent supply connection setting
    Severity: Error      Occurrence: 34
    1: Supply port 'uPAD_VDDIO_B_0/VDDPST' is connected to supply net 'UNCONNECTED2676',
       but power intent specifies it should be connected to 'VDDIO' (./.clp/RC.upf:70)
   13: Supply port 'uPAD_VDD_B_0/VDD' is connected to supply net 'UNCONNECTED2688',
       but power intent specifies it should be connected to 'VDD' (./.clp/RC.upf:67)
   31: Supply port 'uPAD_VSS_B_0/VSS' is connected to supply net 'UNCONNECTED2694',
       but power intent specifies it should be connected to 'VSS' (./.clp/RC.upf:73)
```

That is **100% of the pad ring** — 12 VDDIO, 6 VDD, 12 VSSIO, 4 VSS. The same 34 objects
reappear under a second rule, `syn_pow_check.log:371-408`:

```
STRUCT_UNDRIVEN_PIN_MACRO: Macro cell input/inout direction pin with receiver(s) does not
have an external driver
    Severity: Error      Occurrence: 36
    1: 'uPAD_VDDIO_B_0/VDDPST' is inout direction without an external driver
   35: 'u_nanosoc_eth_chiplet_chip/.../u_way0_cache_ram/tag_ram_0_i/GWEN' is undriven
```

> **The triaged "2× `STRUCT_UNDRIVEN_PIN_MACRO`" undercounts this by 34.** The count of 2
> was taken from `syn_cpf_check.log`; `syn_pow_check.log` reports **36**. Only entries
> 35-36 are the known QSPI `GWEN` pair ([16-open-defects item 3](16-open-defects.md)).

### Both boot ROM power-switch enables are undefined

`syn_cpf_check.log:412-415`, filed as severity **Note**, which badly understates it:

```
1801_LOGIC_CONN_CTRL_UNDEF_MACRO
    1: Switch enable pin '.../u_chip_core/u_region_bootrom_0/u_bootrom/u_rom_via/PGEN'
       (module: 'rom_via') has no connect_logic_net setting
    2: Switch enable pin '.../u_network_core/u_region_bootrom_0/u_bootrom/u_rom_via/PGEN'
       (module: 'eth_rom_via') has no connect_logic_net setting
```

Both boot ROMs — the one the chip core boots from and the one the network core boots
from. In the RTL wrapper `PGEN` is tied off (`nanosoc_bootrom_chip_core.sv:32`,
`.PGEN(1'b0)`), so the silicon is probably fine; but **the power intent does not know
that**, so no tool has checked it.

### Other untriaged classes in the same two files

| Rule | Severity | cpf | pow | Note |
|---|---|---|---|---|
| `1801_MACRO_PORT_ATTR_MISSING` | Warning | 274 | 274 | 48 signal pads × 5 ports + 34 supply pads × 1. **This** is the "no `create_supply_port`" class, not the "54+1" in the triage note |
| `1801_SUPPLY_CSN_MISSING_FOR_MACRO` | Warning | 38 | 38 | all 19 macros × 2 pins; benign only because one domain exists |
| `1801_LIB_NO_PG_PIN` | Error | 54 | **9** | same rule, same library, **different counts between the two runs** — the two checks did not see the same library scope |
| `1801_LIB_MISSING_LP_CELL` | Error | 1 | 1 | see [D](#d-the-low-power-checks-never-ran--a-false-green) |

---

## D. The low-power checks never ran — a false green

**VERIFIED.** `syn_cpf_check.log:77-79`:

```
1801_LIB_MISSING_LP_CELL: No low power cells exist
    Severity: Error      Occurrence: 1
    1: ... there are no low power cells (including standard low power cells and macro
       cells) in the library database. This could be due to no low power cells are
       defined or missing -lp option to extract the low power cell attributes from Liberty.
```

Corroborated by `syn_lib_check.log`, which reports for `domain1(1.08)`:

```
Library Domain   Total cells   LS cell   ISO cell   Combo (LS+ISO)   SR Flops
domain1(1.08)    739           0         0          0                0
```

**Zero level shifters, zero isolation cells, zero state-retention flops were loaded.**
Genus duly reports `CPI-502 No isolation rules defined` and `CPI-503 No level shifter
rules defined` and inserts none (`CPI-517`/`CPI-518` "Completed … insertion").

Three consequences, all of which make a clean log misleading:

1. **`VDDACC` is never checked.** It appears **zero times** in either check log; the only
   domain referenced anywhere is `PD_TOP` (76 references). The UPF never creates it. An
   absence of domain-crossing violations here means *no crossing check existed*, not that
   the crossings are safe.
2. **The core↔IO boundary is uncheckable.** With no `-related_power_port` on any of the 82
   pads (the 274 `MACRO_PORT_ATTR_MISSING` above), nothing tells the tool that pad I/O is
   on VDDIO (2.97-3.63 V per the UPF `add_port_state`) while the core is on VDD
   (1.08-1.32 V). A 1.08 V ↔ 3.3 V boundary with no level-shifter check is the single
   most consequential gap in this section.
3. `739` usable library cells against `143` unusable — the unusable set is the LBR-9
   no-output-pin cells (`PENDCAP_G`, `PRCUT_G`, `ANTENNA`, `DCAP*`), which is expected.

---

## E. RC cap tables are for the wrong metal stack

**VERIFIED.** Affects P&R, not synthesis (synthesis ran ZeroWireload), but it is a
library-setup defect and belongs with this audit.

- `config.tcl:131` — tech LEF:
  `PRTF_EDI_65nm_001_Cad_V24a/PRTF_EDI_N65_**9M_6X1Z1U**_RDL.24a.tlef`
- `scripts/nanosoc_eth_chiplet_pads.mmmc:65,74,83` — all three RC corners:
  `${tech_path}/cadence_captable/**1p9m_6x2z**/{rcworst,rcbest,typical}.captbl`
  where `tech_path = /research/AAA/phys_ip_library/arm/tsmc/cln65lp/arm_tech/r2p0`

`6X1Z1U` (6 thick + 1 Z + 1 U) and `6X2Z` (6 thick + 2 Z) are **different back-end
stacks**. Extraction is being done against a stack the design is not routed in.

The available ARM cap-table directories are `1p6m_4x1z`, `1p7m_4x2z`, `1p7m_5x1z`,
`1p8m_5x2z`, `1p8m_6x1z`, `1p9m_6x2z` — **none matches `9M_6X1Z1U`.** No correct table
exists in that tree; the right one has to come from the TSMC PRTF `PR_tech` release.

This is the residue of an incomplete migration: `config.tcl:132` shows the ARM
`sc12_tech.lef` was deliberately commented out in favour of the TSMC tech LEF, but the
mmmc's ARM cap tables were never migrated with it.

---

## F. The `local_overrides` silent-substitution hazard is live but did not fire

**VERIFIED that it did not fire in this run. The hazard itself is real and unguarded.**

`read_flist.tcl` reads every file with `read_hdl`, and Genus resolves duplicate module
names by **last read wins**, announcing it only at Warning grade. It fired 10 times here
(`HPT-76`), e.g. `syn_logs.log7:408`:

```
Warning : Replacing previously read Verilog module or VHDL entity. [HPT-76]
        : Replacing Verilog module 'cmsdk_ahb_to_apb' in library 'default' with newly read
          Verilog module 'cmsdk_ahb_to_apb' in the same library in file
          '/research/AAA/ip_library/BP210/.../cmsdk_ahb_to_apb.v' on line 31.
```

All 10 are **same-file re-reads** caused by duplicate flist entries (`cmsdk_ahb_to_apb`
appears in 6 distinct flist entries, `cmsdk_apb_slave_mux` 5, `cmsdk_ahb_to_sram` 4,
`xhb500_flop` 3, `ahb3lite_to_wb` 2). Replacing a file with itself is harmless.

**The risk is what this mechanism could do.** `tidelink/src/rtl/local_overrides/` holds 30
files, and **24 of them have same-named twins under `tidelink/deps/`** — `Wlink.v`,
`WlinkGPIOPHY.v`, `WavD2DGpio.v` (4 twins), `axi_chiplet_controller.sv`,
`i2c_master.v`, all seven `WlinkGenericFCSM*.v`, and more. If a flist ever reads the
`deps/` copy after the override, the override is discarded with nothing louder than an
`HPT-76`.

Positive evidence the overrides won **this** time: the only log references to these
filenames point at `local_overrides/`, never at a `deps/` twin — e.g.
`syn_logs.log7:553` (`local_overrides/tidelink_lane_deskew_v2.sv`) and `:784`
(`local_overrides/axi_chiplet_controller.sv`); and no `deps/` twin path appears in any
`HPT-76`/`VLOGPT-6` message.

**Recommendation:** this deserves a guard, not vigilance. Either assert on `HPT-76` where
the two paths differ, or give the override modules distinct names.

---

## G. ROM spec says 2048 words; the delivered macro is 512

**VERIFIED. Currently benign — the boot images are 512 words — but a live regeneration
trap.**

Both spec files request 2048 words:

- `ASIC/tech_wrappers/tsmc65/nanosoc_rom.spec` → `words = 2048`
- `ASIC/tech_wrappers/tsmc65/eth_rom.spec` → `words = 2048`

Every delivered view says 512:

```
ASIC/romlibs/cc_rom/rom_via.memlib:
//      Words:                      512
        NumberOfWords : 512;
        Port (A[8:0]) { Function : Address; ... }

ASIC/romlibs/cc_rom/rom_via_ss_1p08v_1p08v_125c.lib:281
  type (rom_via_ADDRESS) { bit_width : 9; bit_from : 8; bit_to : 0 ; }

ASIC/romlibs/cc_rom/rom_via.v:91
  parameter WORDS = 512;
```

The LEF agrees — exactly 9 address pins, `A[0]`..`A[8]`, in both ROMs.

Genus reports the truncation, `syn_logs.log7:745`:

```
Warning : Connected signal is wider than libpin. [CDFG-466]
        : Signal width (11) does not match width of input port 'A' (9) of instance
          'u_rom_via' of libcell 'domain1_rom_via' in file
          '.../syn/asic/tech_wrappers/tsmc65/nanosoc_bootrom_chip_core.sv' on line 22.
```

**Why it is benign today:** the chain is self-consistent at 9 bits. The region drives only
9 bits into the wrapper's 11-bit port (`CDFG-465`, `nanosoc_region_bootrom.v:44`), the
wrapper's top two bits are undriven, and Genus drops exactly those two. The real address
reaches `A[8:0]` intact. Both boot images are exactly **512 lines**
(`.../stage0_bootrom_chip_core/nanosoc_bootrom_chip_core.bintxt`,
`.../stage0_bootrom/eth_ss_bootrom.bintxt`), so nothing is lost.

Confirmed in the netlist: both ROMs are instantiated, and **all 9 address bits are
connected to real logic with zero tied bits** — `eth_rom_via` takes `.A (i_bootrom_0_haddr[10:2])`
and `rom_via` takes `.A ({…haddr[10] … haddr[2]})`, each with `CEN` driven by real logic
and `Q[31:0]` going to `hrdata`. 9 word-address bits × 32 bits = 512 words = 2 KB per ROM.
The `TA=9'b0` / `TQ=32'b0` / `TCEN=1'b0` group are **test** inputs, correctly disabled by
`TEN=1'b1`; `CENY`/`AY` are outputs left unconnected, which is normal.

**Why it is a trap:** `make tsmc_65_romlibs` regenerates from the spec. That would produce
a 2048-word macro with an 11-bit `A` bus whose LEF, GDS and liberty no longer match the
9-bit region address or the current floorplan — silently, because the RTL wrapper already
declares 11 bits and would then connect cleanly. Either fix the specs to `words = 512` or
widen the region decode deliberately.

---

## H. Synthesis timing is ZeroWireload, one path, +1 ps

**VERIFIED.** `syn_timing.rep` is not a closure result and should not be read as one.

```
Path 1: MET (1 ps) Setup Check with Pin .../u_ha1588_servo/offset_sec_reg[47]/CP->D
          Group: clk
     Required Time:=    9524
         Data Path:-    9523
             Slack:=       1
```

The file contains **exactly one path** (`grep -c '^Path'` = 1) and zero `VIOLATED`.
`1_synthesis.tcl:71` calls bare `report_timing`, which reports only the single worst path.
So the only claim supported is: *the worst setup path has +1 ps slack on a 10 ns clock* —
0.01% margin, effectively zero.

Two caveats that make it weaker still, both from the report header and `syn_area.rep`:

- `Wireload mode: segmented` / `ZeroWireload (S)` — **no wire RC at all.** Real
  post-route delay is strictly worse.
- **No hold analysis, no `-early`, no multi-corner.** Hold is where this design is known
  to be in trouble ([16-open-defects item 1](16-open-defects.md): post-route hold WNS
  −1.167 ns, 96,545 violating paths).

The worst path being inside `u_ha1588_servo` (the PTP servo, a 48-bit `offset_sec`
accumulator) is consistent with a wide arithmetic path, not with a constraint error.

---

## I. No clock gating anywhere

**VERIFIED.** Zero integrated clock-gating cells appear in `syn_gates.rep` — no
`CKLNQ*`, `CKLHQ*`, `CKLD*` of any drive strength. The four cells Genus did examine are
all `dont_use` in the liberty (`LBR-101` ×4):

```
Warning : Unusable clock gating integrated cell found at the time of loading libraries.
        : Clock gating integrated cell name: 'CKLHQD20'   (also CKLHQD24, CKLNQD20, CKLNQD24)
```

But that only covers the D20/D24 variants — lower-drive ICGs are usable, and none were
used either, because **clock gating was never enabled**: `1_synthesis.tcl` sets only
`syn_generic_effort`/`syn_map_effort` and never `lp_insert_clock_gating`.

The cost is visible in `syn_power.rep`: `register` internal power is **51.95%** of the
total 74.05 mW, against `clock` at 0.08%. Enables are instead implemented in the datapath
by reusing the scan mux of `SDF*` flops — see
[Cleared findings](#7-scan-flops-used-as-functional-enable-muxes).

---

## J. Macro tie-off scan — all 21 macro instances

The brief asked whether any pin **other** than the known QSPI tag-RAM `GWEN` was wrongly
tied off. I extracted every macro instantiation from
`outputs/nanosoc_eth_chiplet_pads_gate.v` and listed every input pin bound to a constant.
**21 macro instances found**, matching `syn_gates.rep` exactly (8 `flash_cache_data`,
2 `flash_cache_tag`, 4 `rf_08k`, 3 `rf_16k`, 1 `rf_32k`, 1 `rf_01k`, 1 `rom_via`,
1 `eth_rom_via`).

Expected and correct on every macro: `EMAW = 2'b00`, `RET1N = 1'b1` (retention disabled),
and on both ROMs the BIST/test group `TEN=1'b1, BEN=1'b1, TCEN=1'b0, TA=9'b0, TQ=32'b0,
PGEN=1'b0, KEN=1'b1`. **No address, clock, or byte-write pin is tied on any macro.**
`GWEN`/`WEN` are driven by real logic everywhere except the two known tag RAMs.

> **"Tied to TIEL" and "tied to `1'b0`" are the same fact at two flow stages.** There are
> **zero tie cells in either synthesis netlist** — `grep -oE '\bTIE[A-Z0-9]*\b'` returns 0
> on both. Genus leaves constants as Verilog literals; `TIEL`/`TIEH` cells appear only
> after P&R (28× `TIEL`, 17× `TIEH` in `baseline_2026-08-0{5,6}/outputs/…_pnr.v`). The
> full synthesis-stage constant inventory is **223 constant-driven pin connections**:
> 101×`1'b1`, 78×`1'b0`, 19×`3'b10`, 19×`2'b0`, 2×`9'b0`, 2×`32'b0`, 2×`3'b0`.

Confirming the known defect — both tag RAMs, not one:

```verilog
flash_cache_tag  u_qspi_flash_0_..._u_way0_cache_ram_tag_ram_0_i   .GWEN = 1'b0
flash_cache_tag  u_qspi_flash_0_..._u_way1_cache_ram_tag_ram_0_i   .GWEN = 1'b0
```

> ### ⚠ Open contradiction on the GWEN verdict — needs an owner
>
> [16-open-defects item 3](16-open-defects.md) records this as **REAL — RTL defect**:
> "both tag RAMs stuck in write mode; cache never reads a tag". A close read of the
> netlist does **not** obviously support that, and the two readings should be reconciled
> before anyone acts on either.
>
> `flash_cache_tag` has **both** a scalar `GWEN` *and* an 11-bit `WEN` bus (both
> `direction: input` in `flash_cache_tag_ss_1p08v_1p08v_125c.lib`). In the netlist all 11
> `WEN` bits are driven by a single **real logic** net, and `CEN` is real logic too:
>
> ```verilog
> flash_cache_tag …u_way0_cache_ram_tag_ram_0_i
>     (.CLK (rtc_clk), .CEN (n_52671),
>      .WEN ({n_52670, n_52670, n_52670, n_52670, n_52670, n_52670,
>             n_52670, n_52670, n_52670, n_52670, n_52670}),
>      …, .GWEN (1'b0), .RET1N (1'b1), …);
> ```
>
> On that reading write control simply lives in `WEN[10:0]` + `CEN` rather than `GWEN`,
> writes remain gated, and the tie is redundant rather than harmful — **INFERRED, not
> verified.** Deciding this needs the `flash_cache_tag` datasheet's stated `GWEN`/`WEN`
> precedence, which is not in `/research/precompiled_mems/TSMC65/flash_cache_tag/`.
> **Do not downgrade the existing defect on the strength of this note** — but do not
> assume the original verdict is right either. One of the two is wrong.

Two further items fell out that were **not** previously reported.

### J1. `EMA` is inconsistent across the three SRAM wrappers

**VERIFIED as an inconsistency. Which value is correct: CANNOT BE DETERMINED** without the
Arm memory-compiler datasheet, which is not present in `/research/precompiled_mems/TSMC65/`.

`EMA` is the Extra Margin Adjustment — it trims the internal read/write timing margin of
the compiled RAM. Three wrappers set it independently and they disagree:

| Wrapper | Value | Macros affected |
|---|---|---|
| `.../src/rtl/asic_lib/sram/sl_sram.v:40` — `localparam TIE_EMA = 3'b010` | `3'b010` | 17 SoC SRAMs |
| `.../syn/asic/tech_wrappers/tsmc65/{nanosoc_bootrom_chip_core,eth_ss_bootrom}.sv:28` | `3'b010` | 2 ROMs |
| `.../ethernet-mac-ahb/src/rtl/asic/ethmac_sram.v:59` — `.EMA (3'b000)` | **`3'b000`** | ethmac `bd_ram` (`rf_01k`) |
| `tidelink/src/rtl/fifo/asic/tidelink_sram.sv:56` — `.EMA (3'b000)  // Default extra margin` | **`3'b000`** | TideLink FIFO (`rf_16k`) |

Confirmed in the netlist: 19 macros carry `.EMA = 3'b10`, and exactly two carry
`.EMA = 3'b0` — `u_ethmac_0_u_inner_u_eth_top_wishbone_bd_ram_u_sram_u_rf` and
`u_tidelink_fifo_u_fifo_mem_u_sram_u_rf`.

**Why nothing has caught this and nothing will.** The Arm behavioural models declare the
pin unused — `/research/precompiled_mems/TSMC65/rf_16k/rf_16k.mdt`:

```
  input (EMA) (array = 2 : 0; used=false;fault=none;)
```

`used=false` means RTL simulation, gate simulation and LEC all ignore `EMA` entirely. An
incorrect setting is invisible until silicon, and then only at voltage/temperature
corners. Two identical `rf_16k` instances in the same design running different read
margins is not defensible either way — one of the two settings is wrong.

**Action:** get the recommended `EMA` for `rf_sp_hdf` at this corner from the Arm compiler
datasheet and make all three wrappers agree. Cheap to fix now, untestable later.

### J2. The ethmac buffer-descriptor RAM has `CEN` tied active

**VERIFIED.**

```verilog
rf_01k u_ethmac_0_u_inner_u_eth_top_wishbone_bd_ram_u_sram_u_rf( .CLK ...
      .CEN  = 1'b0
```

`CEN` is the active-low chip enable. Tied to `1'b0`, the RAM is **selected on every clock
edge for the life of the chip** — it never idles. This is the only macro in the design
whose chip-enable is a constant; all other 20 have `CEN` driven by real logic.

Functionally this is survivable (`GWEN` *is* driven, so writes remain gated, and reads
just happen unconditionally), so it is not a correctness defect. But it is a continuous
dynamic-power draw on the ethernet datapath and it defeats any downstream clock- or
power-gating of that RAM. Given `EMA` on the same instance is also the odd one out, the
`ethmac_sram.v` wrapper is worth a focused review as a whole.

---

## Cleared findings

Eight items examined and found benign. Recorded so the next audit does not re-derive them.

### 1. No black boxes, no unmapped cells

`syn_power.rep` reports the `bbox` category as **exactly zero** in leakage, internal,
switching and total. `syn_gates.rep` accounts for every one of the 185,969 instances:
185,866 `tcbn65lpwc` + 82 `tphn65lpgv2od3_slwc` + 21 macros. The `timing_model` type
(103 instances, 54.7% of area) is the 82 IO pads + 21 hard macros — expected, since hard
macros have no logic function. `physical_cells` is 0 at synthesis, as it should be.

Confirmed independently at the netlist level by parsing every instantiation statement
(a plain `grep` histogram undercounts, because Genus wraps long instantiations across
lines). **319 distinct cell types / 185,997 instances**, cross-checked against
`grep -c '));$'` = 185,997. Every type was validated against the actual liberty files
rather than by name pattern:

| Bucket | Distinct types | Instances |
|---|---|---|
| `tcbn65lp` standard cells (of 816 in the liberty) | 274 | 185,866 |
| `tphn65lpgv2od3` IO pads (of 58 in the liberty) | 9 | 82 |
| Known macros | 8 | 21 |
| Hierarchical modules defined in-file | 28 | 28 |
| **Unaccounted / candidate black box** | **0** | **0** |

(185,997 vs `syn_gates.rep`'s 185,969 differs by exactly the 28 hierarchical module
instances, which `report_gates` does not count as cells.)

Tell-tale unmapped constructs — `CDN_`, `DP_OP`, `GTECH`, `unmapped`, `undefined`,
`blackbox` — return **zero** hits in both netlists. Two near-misses are benign: the 41,724
`CDN` hits are the `.CDN` clear-bar *pin* on `DFCNQD1`/`DFCND1`, not a `CDN_*` generic
cell; and `DUMMY` hits are net names only (`WALLACE_CSA_DUMMY_OP_*` from Genus's
carry-save adder naming, plus real QSPI dummy-cycle registers). The datapath is genuinely
mapped: 1,165× `FA1D0`, 29× `HA1D0`, 198× `CMPE42D1`.

**The power netlist is structurally identical** — same 29 modules, same 319 types, same
185,997 instances, zero count differences on any type. It differs only by PG annotation,
so `write_hdl` and `write_hdl -pg` did not diverge.

### 2. No datapath was lost

Every major block is present in `syn_area.rep` with a plausible cell count:

| Block | Module | Cells |
|---|---|---|
| `u_nanosoc_eth_chiplet_chip_u_soc_u_soc` | `nanosoc_multicore_soc` | 88,646 |
| `u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink` | `tidelink_top_NUM_PHY_LANES8_…` | **80,936** |
| `u_network_core` | `ethernet_ss_ahb_rmii_…` | 39,608 |
| `u_ethmac_0_…_u_ha1588` | `ha1588` | 11,493 |
| `u_dmac_0` | `dma_250_ahb_…` | 7,685 |
| `u_cc_periph_0` | `cc_periph_subsystem_…` | 4,315 |

TideLink alone is 26% of the design, with `phy_gpio` (`WavD2DGpio`, 15,007 cells),
`axi_chiplet_controller`, `Wlink` and the `WavFIFO`/`WlinkGenericFCReplayV2` set all
intact. `grep -c -i tidelink` on the gate netlist returns 10,741 hits.

The netlist defines **29 modules** (`grep -c '^module'` = `grep -c '^endmodule'` = 29) and
**every one is reachable from the top** — no orphans. The surviving hierarchy is
`nanosoc_eth_chiplet_pads` → `nanosoc_multicore_soc` → {`ethernet_ss_ahb_rmii_…` →
{7 `eth_*` blocks, `ha1588`, `ha1588_servo`, 2 `cm0p_dbg_*`, `rmii_to_mii`},
`cc_periph_subsystem_…`, `dma_250_ahb_…`, `qspi_clock_div`} and
`tidelink_top_…` → `axi_chiplet_controller_…` → `Wlink_…` → {5 `WavFIFO*`,
2 `WlinkGenericFCReplayV2_*`, `WavD2DGpio_…`}.

> **Caveat — do not use the module list as a deletion check.** Genus flattened the
> overwhelming majority of the design into four modules. **Absence of a module name here
> does not mean the block was deleted.** A blocks-present check must run on flattened
> *instance* names. Doing that confirms every expected block: `u_ethmac` 18,265 name hits,
> `wlink` 36,285, `cortexm0` 25,838, `d2d` 17,503, `u_i2c` 11,638, `u_qspi_flash` 10,107,
> `u_dma` 7,002, `u_phc` 5,481, `u_spi` 3,058, `u_tidelink` 3,299, `u_gpio` 2,218,
> `u_chip_core` 12,500, `u_region_imem`/`u_region_dmem` ~1,000 each, `swd` 354, `jtag` 593.

**All macro bus widths were resolved against the liberty `bit_width` and compared: 112
checks, 112 correct, zero mismatches** (`rf_32k` A=13, `rf_16k` A=12, `rf_08k` A=11,
`rf_01k` A=8, `flash_cache_*` A=8, and all D/Q/WEN widths). Byte-enable granularity is
intact on every `rf_*` — each 32-bit `WEN` is 4 distinct byte-lane drivers × 8
replications; no macro collapsed to a single write enable.

### 3. The PTP register removals are correct

The scariest-looking entries in `CDFG-508` are seven PTP registers:

```
Removing unused flip-flop register 'reg_50' in module 'rgs' in file
'.../ethernet-mac-ahb/src/rtl/ha1588_patches/reg.v' on line 117.
   (also reg_54, reg_58, reg_5c, reg_70, reg_74, reg_78)
```

`reg_50..5c` are the RX timestamp queue and `reg_70..7c` the TX timestamp queue. They are
genuinely dead: they are written (`reg.v:168-177`) but **the read path never reads them**
— it reads the FIFO output directly (`reg.v:214-224`):

```verilog
if (rd_in && cs_50) data_out_reg <= rx_q_data_int[127: 96];
if (rd_in && cs_70) data_out_reg <= tx_q_data_int[127: 96];
```

Software still reads correct timestamps. **No PTP function is lost.** The remaining
`CDFG-508` entries are disabled-feature latches in Cortex-M0+ (`IOP0`, `AHBSLV0` config
options) and a `REGISTER_WDATA0` register in `cmsdk_ahb_to_apb` — all expected.

### 4. The unconnected `sys_remap_ctrl` is harmless

`syn_logs.log7` reports (`ELABUTL-124`):

```
Unconnected input port 'sys_remap_ctrl' of instance 'u_interconnect' of module
'multicore_interconnect_SYS_ADDR_W32_SYS_DATA_W32' in file
'.../build_soc/rtl/nanosoc_multicore_soc.sv' on line 1666
```

The port is genuinely omitted from the instantiation, and the file is auto-generated
(`// AUTO-GENERATED FILE - DO NOT EDIT DIRECTLY`), so this is a generator omission that
will recur. **But `REMAP` is a dead port in that particular bus matrix.** In
`multicore_ahb_interconnect.v` it appears only in the port list and declarations (lines
58, 476, 892) and is never used. Compare `eth_ss_ahb_interconnect.v`, where it *is* used —
`.remapping_dec(REMAP[0])` at lines 1247, 1406, 1501 — and where it *is* correctly wired
from the APB sysctrl register (`ethernet_ss_ahb_rmii.sv:724,785`). The chip-core
interconnect is likewise wired (`nanosoc_multicore_soc.sv:1007`). Worth fixing in the
generator for hygiene; no functional impact.

### 5. The `USERLIB` library-name collision is benign

Both ROM liberty files declare the **same** internal library name — `libname = USERLIB` in
both specs produces `library(USERLIB_ss_1p08v_1p08v_125c)` at line 65 of each — and
`syn_lib_check.log` lists only one `USERLIB_ss_1p08v_1p08v_125c`, with
`Appending library. [LBR-3]: 1`. Genus **merged** rather than overwrote: both cells
survive as distinct libcells (`domain1_rom_via` and `domain1_eth_rom_via` both appear in
the log), and `syn_gates.rep` confirms `USERLIB_ss_1p08v_1p08v_125c | 2 instances |
19672.527`. Both ROMs are in the netlist. Still worth giving the two ROMs distinct
`libname` values, since the merge is a Genus behaviour, not a guarantee.

### 6. The ARM sc12 library is not used by this flow — but check the mmmc

The `TARGET_LIB` in `common.mk:113` is an ARM `sc12_cln65lp_base_rvt` `.db`, and
`common.mk` *is* included by the Genus/Innovus makefile (`genus-innovus/Makefile:25`), so
`TARGET_LIB`/`LINK_LIBS`/`DB_SS`/`MW_REF_LIB`/`TF_FILE` are exported into the tool
environment. **Nothing reads them.** No Genus or Innovus TCL in this flow references any
of them; `config.tcl` builds `syn_lib_list` from TSMC and memory-compiler `.lib` files
only, and `1_synthesis.tcl:22-23` loads exactly that list into `domain1`.

The netlist proves it: 185,866 of 185,969 cells are `tcbn65lpwc`, and the cells named in
the brief (`SDFCNQD1`, `AOI22D1`, `CKND1`) are all TSMC tcbn65lp. **Zero ARM sc12 cells.**

Those variables serve the separate Synopsys flow under
`nanosoc-multicore-system/syn/asic/{design-compiler,rtl-architect}/` — note `MW_REF_LIB`,
`TF_FILE` and `TLUPLUS_PATH` are Milkyway/ICC/FC concepts with no Genus equivalent.

**So the mismatch in the brief is not real for the target library** — but it *is* real one
level down, in the mmmc cap tables. See [E](#e-rc-cap-tables-are-for-the-wrong-metal-stack).
That is the genuine ARM-vs-TSMC inconsistency, and it is the one worth fixing.

On the brief's reference to `create_library_domain:21` — the call is actually at
**line 22** (line 21 is `set_db init_lib_search_path`):

```tcl
21  set_db init_lib_search_path $lib_search_path_list
22  create_library_domain domain1
23  set_db -verbose [get_db library_domains domain1] .library $syn_lib_list
```

It creates exactly **one** domain, `domain1`, holding all 10 libraries, and
`syn_lib_check.log` confirms that is what was loaded. The mmmc's `default_libset_max`
names the same 10 files — consistent. One library domain for a design with three declared
power rails is itself the root of
[D](#d-the-low-power-checks-never-ran--a-false-green).

### 7. Scan flops used as functional enable muxes

~37,000 `SDF*` cells (`SDFCNQD1` 23,831, `SDFQD0` 9,196, `SDFND1` 4,096) appear despite
`set DFT 0` (`config.tcl:123`), which skips `convert_to_scan`/`connect_scan_chains`
(`1_synthesis.tcl:62-65`). They are not scan logic — Genus reused the scan mux as a
load-enable mux, which is what it does when clock gating is off:

```verilog
SDFCNQD1 Pause_reg(.CDN (n_19), .CP (MTxClk), .D (Pause), .SI (n_38), .SE (n_99), .Q (Pause));
```

`.D` and `.Q` are the **same net** (hold), `.SI` carries new data and `.SE` is the enable.
Already documented as a false positive in
[16-open-defects item 6](16-open-defects.md). It does mean the design cannot be
scan-stitched later without resynthesis, and that no scan chain report was produced.

### 8. Two inferred latches

`CDFG2G-616 | Info | 2 | Latch inferred`. The instances are not named in the log (no
`-detail`), but `syn_power.rep` bounds the impact: total `latch` power is
**6.18e-07 W**, i.e. 0.00% of 74.05 mW. Two latches in a 58,121-flop design. Not worth a
re-run on its own; fold into the item-[A](#a-the-glo-34-defect-class-is-not-auditable-from-these-logs--and-removal-is-not-reproducible)
re-run by setting `hdl_error_on_latch` to surface them.

---

## Also noted, not ranked

- **18× `CDFG2G-622` "Signal or variable has multiple drivers"**, every one a top-level
  pad net in `nanosoc_eth_chiplet_pads`: `CLK`, `NRST`, `RMII_REF_CLK`, `TL_CLK_RX`,
  `TL_RX[7:0]`, `SWDCK`, `SE`, `TEST`, `RMII_RXD[1:0]`, `RMII_CRS_DV`. All are **inputs**,
  and the pattern is the usual pad-wrapper one (`.PAD(CLK)` on the pad cell plus the port
  declaration). **SUSPECTED benign** — but it includes the primary clock and reset, so it
  deserves one explicit confirmation against the pad wrapper rather than an assumption.
- **`CDFG2G-608`**, non-constant signal in an async set/reset, at
  `tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv:784`. Flagged as a
  simulation/synthesis mismatch risk; in a reset path that is worth a look.
- **1,875× `CDFG-500` unused module input port** and **321× `ELABUTL-132` unused instance
  port**. Large but unremarkable for a heavily parameterised SoC; worth a skim only if
  something else points at a specific block.
- **5× `ELABUTL-123` undriven module output port**, all `SCANOUT*` on the three
  interconnects and PL022 `Ssp` — consistent with DFT off.
- **`LBR-38`**: `tcbn65lpwc` (nom 1.08 V) and `tphn65lpgv2od3_slwc` (nom 3.0 V) have
  inconsistent nominal operating conditions. Expected for core+IO, but it is the same
  boundary that [D](#d-the-low-power-checks-never-ran--a-false-green) cannot check.
- **`UNCONNECTED_HIER_Z` drives a functional input — benign, but expect an LVS/DRC
  warning.** At `…_gate.v:48158`, `eth_receivecontrol` has
  `.TxReset (UNCONNECTED_HIER_Z)`, and that net has **no driver** (it occurs exactly twice
  in the file: its declaration at `:41998` and this one use). The RTL uses `TxReset` as an
  async reset. **Resolved as benign:** `eth_top.v:568-569` drives
  `.TxReset(wb_rst_i), .RxReset(wb_rst_i)` — the *same* net — so Genus merged them and the
  flops are correctly reset from `RxReset`; the redundant port was left dangling. Of 7,607
  `UNCONNECTED*` nets, 7,573 appear exactly twice and 34 once; **none fans out to a second
  load.**
- **The netlist contains exactly one `assign`**, at `…_gate.v:41182` inside `rmii_to_mii`:
  `assign mrx_clk = mtx_clk;`. The MAC RX and TX MII clocks are the same physical net,
  which is correct for a 50 MHz single-clock RMII design — but confirm CTS and the SDC
  treat it as one clock, and that LEC/LVS tolerate a bare net alias in a gate netlist.
- **`rtc_clk` as the SRAM clock is a naming artifact, not a slow clock.** Every macro
  except the TideLink FIFO is clocked by a net named `rtc_clk`, which reads alarmingly; at
  top level that port is driven by `soc_sys_fclk`, the system free-running clock. The
  TideLink `rf_16k` is on `user_ref_clk` (separate domain, expected).
- **Pad strap audit is clean**, checked against the vendor model rather than assumed:
  `tphn65lpgv2od3_sl.v:307` has `not (RE, REN)`, so **`REN` is active-LOW — `REN=0`
  enables the pull.** On that polarity `TEST_I`, `SE_I`, `SWDCK_I`, `RMII_CRS_DV`,
  `RXD0/1` have pull-**downs** enabled (safe for test/scan pins) and `I2C_SCL`, `I2C_SDA`,
  `SWDIO` have pull-**ups** enabled. One asymmetry to confirm against the intended pinout:
  `uPAD_HOST_IO_0`/`_1` are output-only, `_2` is **input-only**, `_3`..`_6` bidirectional.
- **Core power pad asymmetry** — **VERIFIED** by counting instances in
  `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`:

  | Pad | B | L | R | T | Total |
  |---|---|---|---|---|---|
  | `uPAD_VDDIO_*` | 3 | 3 | 3 | 3 | 12 |
  | `uPAD_VSSIO_*` | 3 | 3 | 3 | 3 | 12 |
  | `uPAD_VDD_*` | 3 | — | — | 3 | **6** |
  | `uPAD_VSS_*` | 2 | — | — | 2 | **4** |

  The IO rails are populated on all four edges; **the core rails are on top and bottom
  only**, and core ground is under-provisioned 4:6 against core power. Nothing in this
  flow does IR/EM analysis, so no check has ever looked at this. Worth an explicit
  IR-drop review before signoff.

  This also confirms the arithmetic elsewhere in this document: 12+12+6+4 = **34** supply
  pads, exactly the 34 objects in `PG_CONN_SUPPLY_PIN_CSN_CONFLICT`; and 82 total `uPAD`
  instances, matching the 82 `tphn65lpgv2od3_slwc` cells in `syn_gates.rep`, leaving 48
  signal pads (48 × 5 + 34 × 1 = 274 `MACRO_PORT_ATTR_MISSING`).

---

## What would actually close this

In priority order, none of which needs a re-spin:

1. **Run the LEC dofile.** `1_synthesis.tcl:82` already writes `lec.dofile`. It is the
   only check that proves RTL ≡ netlist and therefore the only thing that retires
   item [A](#a-the-glo-34-defect-class-is-not-auditable-from-these-logs--and-removal-is-not-reproducible).
2. **Re-run synthesis once with `information_level 2`, `truncate false`, and
   `report sequential -deleted`** — and diff the deleted-object list against the previous
   run to quantify the non-determinism.
3. **Rewrite the UPF against the real hierarchy** (`u_nanosoc_eth_chiplet_chip/u_soc/u_soc/…`),
   fix `set_design_top`, add the three missing macros, correct the drifted memory names,
   and decide whether `VDDACC` exists. Then confirm the emitted CPF is no longer empty.
4. **Point the mmmc at a `9M_6X1Z1U` cap table** from the TSMC PRTF release.
5. **Load low-power cells** (`-lp`) so isolation/level-shifter checks can run at the
   1.08 V ↔ 3.3 V boundary at all.
6. **Settle `EMA`** ([J1](#j1-ema-is-inconsistent-across-the-three-sram-wrappers)) from the
   Arm compiler datasheet and make `sl_sram.v`, `ethmac_sram.v` and `tidelink_sram.sv`
   agree. No simulation will ever tell you this is wrong.
7. **Fix or pin the ROM specs** to 512 words before anyone regenerates `romlibs/`.

---

*Audited 2026-08-07 against `baseline_2026-08-05`. A newer `baseline_2026-08-06/` exists
and was **not** examined; its synthesis logs should be diffed against this baseline before
any of the above is assumed to still hold.*
