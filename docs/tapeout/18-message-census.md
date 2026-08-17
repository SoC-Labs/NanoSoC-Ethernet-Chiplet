# 18 — Complete message census: every ERROR / WARN / INFO class in the TSMC65 flow

Scope: every distinct Cadence message ID emitted by the Genus + Innovus tapeout flow,
tallied, quoted, explained and triaged.

Sources (read-only; nothing was re-run — a P&R run was live while this was written):

| Log | What it is |
|---|---|
| `ASIC/genus-innovus/baseline_2026-08-05/logs/pnr_all.log` | full `pnr_all`: Genus synthesis → place → CTS → route. `CORE_TO_IO = 50`. |
| `ASIC/genus-innovus/baseline_2026-08-06/logs/pnr_run_core70.log` | place → CTS → route, no synthesis (SDC/netlist reused). `CORE_TO_IO = 70`. |
| `ASIC/genus-innovus/logs/cts_ocvfirst.log` | current CTS-only session (OCV-first experiment). |

Supporting artefacts used as *evidence*, not as message sources:
`baseline_2026-08-06/reports/conn_uncapped.rep`, `.../nanosoc_eth_chiplet_pads_imp_drc.rep`,
`baseline_2026-08-0{5,6}/work/design.sdf`, `baseline_2026-08-05/logs/syn_cpf_check.log`,
`ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads_syn.sdc`.

---

## 0. How these numbers were counted, and four ways the count lies

Read this before trusting any number below.

**Trap 1 — sourced-script echo.** The logs echo every line of every sourced Tcl file
prefixed `@file NNN:`. Those lines contain the words ERROR and WARN inside *comments*.
Everything here was counted after `grep -v '^@file'`. (Example of the damage: the string
`NRDB-51` appears in `pnr_run_core70.log` three times, and **all three are the comment in
`scripts/config.tcl:144`** — NanoRoute never emitted NRDB-51 on 2026-08-06. It emitted it
8 times on 2026-08-05.)

**Trap 2 — the `man` hint line.** Most messages are followed by
`Type 'man <MSGID>' for more detail.`, which repeats the ID. `grep -c '<MSGID>'`
double-counts. Only lines that *begin* a message were counted:
`^\*\*(WARN|ERROR|INFO): *\(<ID>\)`. Verified: `IMPLF-119` gives raw 125, message-starts
60, hint lines 60, and 5 stray meta-lines.

**Trap 3 — the display limit. This is the big one and it is not in the brief.**
Innovus prints **at most 20 instances of any one message ID per limit window** and then
stops. It says so in one of two forms, both of which are themselves messages:

```
**WARN: (EMS-27):	Message (IMPLF-119) has exceeded the current message display limit of 20.
Message <TECHLIB-302> has exceeded the message display limit of '20'. Use 'set_message -no_limit -id list_of_msgIDs' to reset the message limit.
```

So **any printed count of exactly 20 is a floor, not a count.** IDs capped at least once:

* 2026-08-06: `IMPLF-119`, `IMPLF-223`, `IMPPP-531`, `IMPPP-532`, `IMPPP-570`,
  `IMPPP-4500`, `IMPESI-3086`, `IMPESI-3095`, `IMPCCOPT-2169`, `IMPCCOPT-2171`,
  `IMPCCOPT-2332`, `IMPCCOPT-2406`, `IMPOGDS-217`, `IMPOGDS-4004`, `TECHLIB-302`,
  `TCLCMD-513`, `TCLCMD-917`, `TCLCMD-1005`, `SDF-802`
* 2026-08-05: all of the above except `TCLCMD-513`/`TCLCMD-917`, plus `IMPDB-2078`
  and `IMPDC-348`

**Trap 4 — the summary tables are windowed, not per-session.** Innovus prints
`*** Summary of all messages that are not suppressed in this session:` followed by an
itemised table of *true* counts, then `*** Message Summary: N warning(s), M error(s)`.
The itemised table only covers messages since the last internal reset, so it is *not* a
session census. The bare `*** Message Summary:` printed just before
`--- Ending "Innovus"` **is** the session total — and it is vastly larger than anything
printed. Place stage, 2026-08-06: **57,018 warnings / 178 errors**, of which the log
prints ~250 warning lines. Less than 0.5 % of the warnings in that stage were ever
visible.

**Counting convention used below.** `true=` means an authoritative count from a summary
table, from the message text itself (e.g. `IMPOGDS-218`), or from an independent artefact.
`≥20` means capped. `derived=` means obtained by subtracting known quantities from a
session total; those are reasoned estimates and are labelled as such.

**Stage boundaries** (line ranges, verified against the `innovus -stylus -files <script>`
banners):

| Stage | Script | 08-05 lines | 08-06 lines |
|---|---|---|---|
| SYNTH | `1_synthesis.tcl` (Genus) | 231–4953 | *not run* |
| PLACE | `2_pnr_setup.tcl` | 4954–7443 | 1–2589 |
| CTS | `3_pnr_clock.tcl` | 7445–33609 | 2590–28971 |
| ROUTE+FILL | `4_pnr_route.tcl` | 33611–124522 | 28972–119859 |

**Neither "complete" run completed.** Both route sessions died at the same place — the
`exec calibre -drc` block at the end of `4_pnr_route.tcl` (`ERROR: Failure to open input
file GDSFILENAME`, ×3 in each log) raises a Tcl error that aborts the script before its
`exit`. On 08-05 Innovus sat at an interactive prompt and never wrote a session total; on
08-06 `make` was `Terminated` (`rc=2`). All deliverables (GDS, netlist, SDF, reports) were
written before that point. This is documented in `12-calibre-drc.md` and
`09-signoff-checklist.md` item 13, and is now fixed project-side (`Makefile` runs
`pnr_route` under `env -u CALIBRE_HOME`) — the fix postdates both baselines.

---

## 1. Census — SYNTHESIS (Genus, 2026-08-05 only)

Counts are `true=`, taken from the two Genus `Message Summary` tables
(`pnr_all.log:3384` and `:4623`); where an ID appears in both, the counts are summed.
Genus format is `Warning : <text> [ID]`, not `**WARN: (ID)`.

### Errors

| ID | true | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|
| `RCLP-203` | 1 | `Error   : Low Power rule check did not finish successfully. [RCLP-203] [check_cpf]` / `: This may result in design errors.` | The CPF low-power rule check aborted; Genus is telling you the power-intent has not been validated. | **REAL-BUT-KNOWN** — `11-known-issues.md` §(f). `config.tcl` deliberately wraps `check_cpf` in a `catch` so it cannot abort the `-f` script. Underlying error counts, from `logs/syn_cpf_check.log`: **34 + 1 + 54 + 2 = 91 errors** and 312 warnings. Those 91 have never been enumerated in a doc. |

### Warnings

| ID | true | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|
| `PI-407` | 356 | `Warning : A pin related to backup power does not have explicit supply in power intent. [PI-407]` | 356 pins that the CPF/UPF does not give a supply for. | **UNTRIAGED** (low). Same family as the `PD_TOP` power-intent gaps. |
| `CDFG-472` | 232 | `Warning : Unreachable statements for case item. [CDFG-472]` | Dead case branches in the RTL. | BENIGN — dead RTL, synthesises away. |
| `VLOGPT-37` | 121 | `Warning : Ignoring unsynthesizable construct. [VLOGPT-37]` | Simulation-only constructs skipped. | BENIGN. |
| `CDFG-508` | 122 | `: Removing unused flip-flop register 'reg_50' in module 'rgs' in file '.../ethernet-mac-ahb/src/rtl/ha1588_patches/reg.v' on line 117.` | 122 registers deleted because nothing reads them. | **UNTRIAGED (high)** — see §6.4. Modules hit: `rgs` ×7 (the ha1588 PTP register file), `cm0p_core` ×6, `cm0p_dbg_if` ×5, `eth_registers` ×1 (`ResetTxCIrq_sync1` — a **synchroniser stage**), `cmsdk_ahb_to_apb` ×1. Same failure family as the documented `GLO-34` hollow-TX-datapath incident (`11-known-issues.md` §(i)). |
| `LBR-9` | 48 | `Warning : Library cell has no output pins defined. [LBR-9]` / `: Library cell 'PENDCAP_G' must have an output pin.` | Physical-only IO cells have no logic function, so Genus marks them unusable. | BENIGN — endcap/cut/clamp cells are not meant to be mapped to. |
| `PI-402` | 34 | `Warning : Could not find an object. [PI-402]` | A power-intent rule names something that does not exist. | **UNTRIAGED** (low). |
| `ELABUTL-125` | 30 | `Warning : Undriven signal detected. [ELABUTL-125]` / `: Undriven bits of signal 'early_exit_en_w' in module 'tidelink_phy_align_calibrator_VAL_TIMEOUT_TO_DONE1'.` | Signals with no driver; Genus ties them per `hdl_unconnected_value`. | **UNTRIAGED** (medium) — one of them is inside the TideLink PHY align calibrator. |
| `VLOGPT-506` | 24 | `Warning : Unused attribute. [VLOGPT-506]` | Synthesis attribute ignored. | BENIGN. |
| `VLOGPT-35` | 23 | `Warning : Ignoring unsynthesizable delay specifier (#<n>)…` | `#delay` in RTL ignored. | BENIGN. |
| `CDFG2G-622` | 18 | `Warning : Signal or variable has multiple drivers. [CDFG2G-622]` / `: 'CLK' in module 'nanosoc_eth_chiplet_pads'.` | 18 top-level signals have more than one driver. Named: `CLK`, `NRST`, `RMII_REF_CLK`, `TL_CLK_RX`, `TL_RX[0..n]`. | **BENIGN (with a caveat)** — all 18 are in the pad wrapper `nanosoc_eth_chiplet_pads`, where a bidirectional pad's `PAD` net is legitimately driven from two sides. No occurrence is in core RTL. Worth one confirming read of the wrapper. |
| `CDFG-464` | 13 | `Warning : Connected signal is wider than module port. [CDFG-464]` | Port width mismatch, upper bits dropped. | **UNTRIAGED** (low-medium) — silent truncation. |
| `HPT-76` | 10 | `: Replacing Verilog description 'tidelink_phy_sync_detect' with Verilog module in file '.../tidelink/deps/tidelink-phy/rtl/tidelink_phy_sync_detect.sv' on line 87` | A module was defined twice in the filelist; the later read **replaces** the earlier. | **UNTRIAGED (high)** — see §6.2. |
| `VLOGPT-6` | 10 | `Warning : Replacing previously read Verilog description. [VLOGPT-6]` | Same event, parser-side. | **UNTRIAGED (high)** — see §6.2. |
| `CDFG-236` | 8 | `Warning : Detected non-positive value for replication prefix. [CDFG-236]` | `{0{...}}` replication; result depends on `hdl_zero_replicate_is_null`. | BENIGN. |
| `ELABUTL-127` | 6 | `: Undriven bits of port 'CTRL_APB_pprot' of instance 'u_regs_0' of module 'tl_addr_trans_regs_…'` | 6 module input ports left undriven. | **UNTRIAGED** (low) — `pprot` tie-off is normal; the others are not audited. |
| `ELABUTL-123` | 5 | `: Undriven bits of output port 'SCANOUTHCLK' in module 'eth_ss_ahb_interconnect'` | 5 module output ports never driven. | BENIGN — all five are `SCANOUT*` DFT ports; `DFT 0`. |
| `LBR-101` | 4 | `Warning : Unusable clock gating integrated cell found…` / `: Clock gating integrated cell name: 'CKLHQD20'` | `CKLHQD20/24`, `CKLNQD20/24` are ICGs marked `dont_use`. | BENIGN — deliberate high-drive `dont_use` list; smaller ICGs remain available. |
| `CDFG-466` | 4 | `Warning : Connected signal is wider than libpin. [CDFG-466]` | Width mismatch onto a library pin. | BENIGN. |
| `ELABUTL-124` | 3 | `Warning : Unconnected instance input port detected. [ELABUTL-124]` | Instance input left dangling. | **UNTRIAGED** (low). |
| `CDFG-360` | 3 | `Warning : Referenced signals are not added in sensitivity list. This may cause simulation mismatches…` | Incomplete sensitivity list. | **UNTRIAGED** (low) — sim/synth mismatch risk only. |
| `VLOGPT-21` | 3 | `Warning : Suspicious implicit wire declaration. [VLOGPT-21]` | Implicit 1-bit net from a typo'd name. | **UNTRIAGED** (low-medium) — classic source of a silently 1-bit-wide bus. |
| `VLOGPT-502` | 3 | `Warning : Unrecognized Synthesis pragma_name found in HDL. [VLOGPT-502]` | A pragma Genus does not know — so it did nothing. | **UNTRIAGED** (low). |
| `CDFG-465` | 2 | `: Signal width (9) does not match width of input port 'word_addr' (11) of instance 'u_bootrom' of module 'nanosoc_bootrom_chip_core'` | Boot ROM address port is 11 bits, only 9 are driven. | **UNTRIAGED** (medium) — top 2 address bits of the boot ROM are undriven. Cross-check with `ELABUTL-127` on the same port. |
| `LBR-146` | 2 | `: Pin 'VSSE' used in pg_function function is not an input pin` | Malformed `pg_function` in a vendor `.lib`. | BENIGN — vendor library defect, analysis-only cells. |
| `CDFG2G-608` | 1 | `Warning : Accessed non-constant signal during asynchronous set or reset operation. [CDFG2G-608]` / `: in file '.../tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv' on line 784, column 39.` / `: This may cause simulation mismatches between the original and synthesized designs.` | An asynchronous set/reset in the AXI chiplet controller is driven from something that is not a constant — the gate netlist may not behave like the RTL. | **UNTRIAGED — #1, see §6.1.** |
| `LBR-38` | 1 | `Warning : Libraries have inconsistent nominal operating conditions…` / `: The libraries are 'tcbn65lpwc' and 'tphn65lpgv2od3_slwc'.` | Core lib nominal 1.08 V, IO lib nominal 3.0 V. | BENIGN — expected for a core+IO library pair; MMMC sets real PVT. |
| `TIM-316` | 1 | `: Provided from_point is 'pin:nanosoc_eth_chiplet_pads/uPAD_VDDIO_T_0/VDDPST'.` | A timing exception starts on a *supply* pin. | **REAL-BUT-KNOWN** — the Genus-side twin of `TCLCMD-917`; see §3 and `16-open-defects.md` §5. |
| `TIM-317` | 1 | `Warning : At least one of the provided to-point is not a…` | Same, the `-to` side. | REAL-BUT-KNOWN, as above. |

### Informational (Genus) — recorded, not triaged

`CWD-19` 6636, `CDFG-738`/`739` 3079 each, `GLO-12` 2503, `CDFG-500` 1875, `CDFG-372` 848,
`ELAB-2` 623, `GB-6` 529, `PA-7` 482, `CDFG-771` 409, `LBR-162` 329, `ELABUTL-132` 321,
`CDFG-250` 306, `LBR-41` 287, `CDFG-769` 232, `LBR-40` 155, `CDFG-772` 93, `CDFG-286` 79,
`GLO-51` 56, `GLO-34` 40, `GLO-13` 33, `LBR-72` 32, `ST-110` 36, `LBR-518` 34, `ST-112` 35,
`CDFG-479`/`CDFG-893` 29 each, `CDFG-361`/`CDFG-373` 17 each, `LBR-412` 9, `ST-128` 6,
`ELABUTL-130` 7, `ELABUTL-131` 6, `ELABUTL-128`/`ST-120` 5/1, `TIM-501`/`TUI-58` 4 each,
`CDFG2G-616` 2, `CDFG-773`/`CDFG-780`/`CFM-1`/`CFM-5`/`CPI-502`/`CPI-503`/`CPI-517`/`CPI-518`/
`LBR-3`/`LBR-109`/`PBS-1`/`PHYS-752`/`SYNTH-1`/`SYNTH-2`/`SYNTH-4`/`SYNTH-5`/`SYNTH-7`/
`TIM-1000`/`TUI-296` 1 each.

Two of these deserve a flag despite being `Info`:

* **`GLO-34` ×40** — `Deleting instances not driving any primary outputs.` Already triaged
  (see brief) and already the cause of one shipped-hollow GDSII (`11-known-issues.md` §(i)).
  Recorded here with its true count.
* **`CDFG2G-616` ×2** — `Latch inferred. Check and revisit your RTL if this is not the
  intended behavior.` **Two latches were inferred somewhere in this design.** The
  individual messages do not appear in `pnr_all.log` or `syn_logs.log7`; only the summary
  table row survives, so the location is **unknown**. UNTRIAGED, medium — see §6.5.

---

## 2. Census — PLACE (`2_pnr_setup.tcl`)

Session totals: **08-06 → 57,018 W / 178 E**; **08-05 → 56,885 W / 132 E**.

### 2a. The LEF/library read block (identical in every Innovus session)

These fire once per Innovus invocation, so a full run emits each of them **three times**.
True counts from the post-load summary table (`core70:3468`, `pnr_all:8317`,
`cts_ocvfirst:930` — all three agree).

| ID | Sev | true | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|---|
| `TECHLIB-302` | WARN | 111 | `No function defined for cell 'PVSS3DGZ_G'. The cell will only be used for analysis. (File /tsmc65pdk/.../tphn65lpgv2od3_slwc.lib)` | 111 IO/physical cells have no logic function, so they are timing-analysis-only. | BENIGN — supply, ESD, clamp and cut cells genuinely have no function. |
| `IMPLF-223` | **ERROR** | 105 | `The LEF via 'VIA12_1cut' definition already exists in the database. The current definition will be ignored. Ensure that you have not specified duplicate LEF files or LEF files with duplicate via definition.` | 105 via definitions appear in more than one LEF; the first wins and the rest are dropped. | **REAL-BUT-KNOWN** — `08-debugging.md` §3, `16-open-defects.md`. Note the existing doc records it as 60×; the true count is **105**, and it is the single largest contributor to the "106 errors" every session reports. The open question in `16-open-defects.md` (*"worth confirming the ignored ones are identical to the kept ones"*) is still open. |
| `IMPLF-119` | WARN | 22 | `LAYER 'PO' has been found in the database. Its content except ANTENNA* data will be ignored.` | The antenna LEF redefines layers already in the tech LEF; only its ANTENNA data is used. | BENIGN — documented, `06-fill-antenna-bondpads.md` §5. That is the intent of an antenna LEF. |
| `IMPLF-200` | WARN | 15 (08-06) / 16 (08-05) | `Pin 'TAVSS' in macro 'PVSS3A_G' has no ANTENNAGATEAREA value defined. The library data is incomplete and some process antenna rules will not be checked correctly.` | Some antenna rules cannot be checked on those pins. | REAL-BUT-KNOWN — `06-fill-antenna-bondpads.md` §5. |
| `IMPLF-151` | WARN | 9 | `The viaRule 'VIAGEN12' has been defined, the content will be skipped.` | Duplicate generate-via rule; second copy skipped. | BENIGN — same duplicate-LEF root cause as `IMPLF-223`. |
| `IMPFP-3961` | WARN | 8 | `The techSite 'corner' has no related standard cells in the LEF/OA library. The calculations for this site type cannot be made unless standard cell models of this type exist…` | 8 SITE definitions in the tech LEF have no cells of that site. | **UNTRIAGED (low)** — but see `IMPOPT-3564` below, which is the *consequence* of a site with no rows, and that one is not benign. |
| `IMPTS-282` | WARN | 6 | `Cell 'PCLAMPAC_G' is not a level shifter cell but has 'input_signal_level' and 'output_signal_level' specified on pins…` | 6 IO cells look like level shifters to the tool but are not tagged as such. | **UNTRIAGED (low)** — single-voltage core, so no level shifting is required; the risk is only mis-modelled IO delay. |
| `IMPMSMV-3501` | **ERROR** | 1 | `Input power intent (CPF/UPF) does not define power_mode/power_state. The always-on buffering is not supported since the tool needs the power_mode/power_state information to calculate the domain coverage.` | No power modes declared, so always-on buffering is unavailable. | REAL-BUT-KNOWN, low severity — `11-known-issues.md` §(d). One core domain. |
| `TECHLIB-459` | WARN | 3 | `Appending library 'USERLIB_ss_1p08v_1p08v_125c' to the previously read library of the same name and nominal PVT. Cell definitions from the previously read library will not be overridden. (File .../eth_rom_via_ss_1p08v_1p08v_125c.lib)` | Three memory `.lib`s share a library name; later cells do **not** override earlier ones. | **UNTRIAGED (low-medium)** — same "first definition wins" hazard as `IMPLF-223`, on *timing* data. Benign only if no cell name collides across the three ROM/RF libs. |
| `EMS-27` | WARN | 6–7 per session | `Message (IMPLF-119) has exceeded the current message display limit of 20.` | Meta-message: an ID was capped. | BENIGN as a message; **not** benign as a signal — see Trap 3. |
| `IMPSYT-1507` | WARN | 1 | `The display is invalid and will start in no window mode` | Batch run, no X display. | BENIGN (already triaged). |

### 2b. SDC read

| ID | Sev | count | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|---|
| `TCLCMD-917` | **ERROR** | ≥20 printed; **derived 70 (08-06) / 22 (08-05)** | `Cannot find 'pins' that match 'uPAD_VDDIO_B_0/VDDPST' (File ../outputs/nanosoc_eth_chiplet_pads_syn.sdc, Line 696).` | An SDC object pattern matched nothing. | **REAL-BUT-KNOWN, count is new** — `16-open-defects.md` §5. The count **changed between runs**; see §4. |
| `TCLCMD-513` | WARN | ≥20 printed; derived same as above | `The software could not find a matching object of the specified type for the pattern 'uPAD_VDDIO_B_0/VDDPST' (File …, Line 696).` | Warning twin of the above; always paired 1:1. | REAL-BUT-KNOWN. |
| `TCLCMD-1531` | WARN | 5 | `'create_generated_clock' has been applied on hierarchical pin 'u_…/u_qspi_clock_div/QSPI_SCLK_i' (File …sdc, Line 17).` | A generated clock is defined on an internal hierarchical pin rather than a cell output. | **UNTRIAGED (low)** — pairs with `IMPCCOPT-2248`, which is documented. |
| `TCLCMD-1461` | WARN | 2 | `Skipped unsupported command: set_units (File …sdc, Line 9).` | `set_units` ignored. | BENIGN — Innovus uses library units. |
| `TCLCMD-1005` | — | ≥20, capped 3× | (capped before any instance is visible in this log) | Unknown — every instance was suppressed. | **UNTRIAGED (unknown)** — an ID that fired >20 times in each of three sessions and whose text we have never seen. Cheapest possible fix: `set_message -no_limit -id TCLCMD-1005`. |

**The `TCLCMD-917` mechanism, restated with the numbers.** `outputs/nanosoc_eth_chiplet_pads_syn.sdc`
lines 148–696 are **one** `set_multicycle_path -from [list … ] -setup -end 2` with 548
`get_pins` entries. Of those, 480 are real signal pins (`REN`/`PAD`/`OEN`/`I`/`C`, 96 each)
and **68 are supply pins** (`VSSPST` 24, `VDDPST` 24, `VDD` 12, `VSS` 8). `get_pins` does
not return supply pins. Derived count 70 ≈ those 68 plus 2. Traced by `16-open-defects.md`
to `inputs/constraints.sdc:79` — `set_multicycle_path 2 -from uPAD*/* -to uPAD*/*`.

### 2c. Power plan — the hidden bulk of this stage

| ID | Sev | count | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|---|
| `IMPPP-570` | WARN | ≥20, capped | `The power planner detected cut layer obstruction(s) and cannot create via on the VIA1 layer at (1020.534973, 246.235001) (1020.864990, 246.565002).` | A PG via could not be cut because something blocks the cut layer. | REAL-BUT-KNOWN — headline of `15-pg-opens-analysis.md`. |
| `IMPPP-531` | WARN | ≥20, capped | `ViaGen Warning: Due to SPACING rule violation, viaGen fail to generate via on layer VIA7 at (728.47, 244.50) (728.80, 248.10).` | A PG via was not generated because it would violate spacing. | REAL-BUT-KNOWN — `15-pg-opens-analysis.md` §5. |
| `IMPPP-532` | WARN | ≥20, capped | `ViaGen Warning: The top layer and bottom layer have same direction but only orthogonal via is allowed between layer M4 & M8 at (244.55, 1210.00) (244.90, 1495.25).` | M8 (vertical) cannot via onto macro M4 (vertical) PG pins. | REAL-BUT-KNOWN — `15-pg-opens-analysis.md` H4. |
| `IMPPP-4500` | WARN | ≥20, capped | `Extended number of geometries exist around 784.760000, 246.300000 between the M4 and M9 layers. This may increase the run time.` | Very dense geometry in the PG stack at that point. | REAL-BUT-KNOWN — `15-pg-opens-analysis.md` §5. |
| `IMPPP-4055` | WARN | 3 | `The run time of add_stripes will degrade with multiple cpu setting…` | Multi-CPU ignored for `add_stripes`. | BENIGN — runtime note. |

**New quantification.** `15-pg-opens-analysis.md` states the true counts are unknown
because all four are capped at 20. They can now be bounded from the session total:

| | 08-06 | 08-05 |
|---|---|---|
| PLACE session total warnings | 57,018 | 56,885 |
| minus `SDF-802` (counted independently, §2d) | −53,605 | −53,606 |
| **remaining warnings in the place stage** | **3,413** | **3,279** |
| minus everything else itemised in §2a–2f (≈250–320) | ≈3,100 | ≈2,970 |

So **the four `IMPPP-*` power-plan via classes together account for roughly 3,000–3,100
warnings per place run**, against the 80 lines the log prints. That is the real size of
the PG-via problem and it has never been stated. (Caveat: this is subtraction, not a
count; it assumes no other large capped class hides in the place stage. `TCLCMD-1005` is
the one candidate that could eat into it.)

### 2d. SDF write

| ID | Sev | count | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|---|
| `SDF-802` | WARN | ≥20 printed; **true ≈ 53,605 (08-06) / 53,606 (08-05)** | `The sum of the Setup and Hold sides of the SETUPHOLD check on pin u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink/u_chiplet_controller/u_wlink/phy_gpio/gpiorx_2_link_data_reg_reg\[0\]/D is negative - which is illegal in SDF V3.0. The negative side of the SETUPHOLD will be postively adjusted so that the resulting sum is zero. This will result in a more conservative analysis of the adjusted check.  Negative SETUPHOLD sums maybe an indication of a characterization problem in your timing libraries.` | setup+hold < 0 on a flop D pin; the SDF writer clamps the sum to zero. | **BENIGN for signoff, with a caveat** — see below. |

Independent evidence for the count: `baseline_2026-08-06/work/design.sdf` contains 766,050
`SETUPHOLD` entries, of which **53,605** have the two sides summing to exactly zero — the
fingerprint of the clamp the message describes. The 08-05 SDF gives 53,606. This is 94 %
of the entire place-stage warning total.

Why benign: every `SDF-802` in both runs is in the **place** session only (all 20 printed
instances lie at `core70:2485–2505`, inside `write_sdf design.sdf -ideal_clock_network`).
The **route**-stage `write_sdf`, which produces the signoff SDF
`outputs/…_pnr.sdf`, emits `SDF-808` and **zero** `SDF-802`. Negative setup+hold sums are
what you expect from pre-CTS timing on an ideal clock network; they disappear once the
clock tree is real. The caveat: all 20 printed instances name **TideLink
`phy_gpio/gpiorx_{2,3,4}_link_data_reg_reg[*]`** — 19 on `/D`, one on `/CDN` — i.e. the
die-to-die *receive* capture flops and one of their async clears. Those 20 are the first
20 of ~53,605, not a random sample, so this does not prove the population is
TideLink-only; but it does mean the very first negative-sum checks the tool encountered
were all in the D2D receive path. Worth one look given the open cross-die wedge, even
though the signoff SDF is clean.

| ID | Sev | count | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|---|
| `SDF-808` | WARN | 1 per `write_sdf` (2 per run) | `The software is currently operating in a high performance mode which optimizes the handling of multiple timing arcs between input and output pin pairs. With the current settings, the SDF file generated will contain the same delay information for all of these arcs. To have the SDF recalculated with explicit pin pair data, you should use the option '-recompute_delay_calc'. This setting is recommended for generating SDF for functional simulation applications.` | Per-arc delays are collapsed; the SDF is coarser than it could be. | **UNTRIAGED (low-medium)** — matters only if this SDF is used for gate-level simulation. It is: `outputs/…_pnr.sdf` is 580 MB and is the handoff artefact. |

### 2e. Placement / DFT / floorplan

| ID | Sev | count | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|---|
| `IMPSP-9099` | **ERROR** | true 2 | `Scan chains exist in this design but are not defined for 30.55% flops. Placement and timing QoR can be severely impacted in this case!` | Innovus thinks scan chains exist but 30.55 % of flops are not in one. | REAL-BUT-KNOWN → **BENIGN**. `16-open-defects.md` §6: false positive, `DFT 0`, the heuristic mis-reads `.SI(BlockTxDone)` feedback. **⚠ NO LONGER EMITTED — last seen 2026-08-07 14:21. Zero occurrences in every build from 08-08 onward, including current. See note below the table.** |
| `IMPSP-9025` | WARN | ~~true 1 (per session)~~ **52** in `full-20260814`, **23** in `fp1505` | `No scan chain specified/traced.` | No scan chain was given. | BENIGN — consistent with `DFT 0`. ~~it is the *counterpart* to 9099~~ — **it is now the only scan message this design raises.** |
| `IMPDC-1629` | WARN | true 2 | `The default delay limit was set to 101. This is less than the default of 1000 and may result in inaccurate delay calculation for nets with a fanout higher than the setting.  If needed, the default delay limit may be adjusted by running the command 'set delaycal_use_default_delay_limit'.` | Delay calc will be inaccurate on nets with fanout > 101. | **UNTRIAGED (medium)** — a fanout-101 delay limit is unusually low and nothing in the flow scripts sets `delaycal_use_default_delay_limit`, so this is a tool default reacting to something. Every high-fanout net (reset, scan-enable, test) is timed approximately. |
| `IMPSP-196` | WARN | true 1 | `User sets both -place_global_uniform_density and -place_global_initial_padding_level options. Overriding -place_global_initial_padding_level to 5.` | Two conflicting placement options; one wins. | BENIGN — tool states the resolution. |
| `IMPFP-325` | WARN | 1 | `Floorplan of the design is resized. All current create_floorplan objects are automatically derived based on specified new create_floorplan. This may change blocks, fixed standard cells, existing routes and blockages.` | The floorplan was re-created, invalidating derived objects. | BENIGN — expected, `create_floorplan` runs once from scratch. Documented in `03-floorplan.md`. |

> **⚠ `IMPSP-9099` retired — added 2026-08-18.** This census is a snapshot of the
> **2026-08-06** run and is accurate for it. Since then `IMPSP-9099` has stopped being
> emitted entirely: last occurrence **2026-08-07 14:21**
> (`runs/20260807T150304Z_gwen-sdc-i2c-m7/prev_logs/pnr_m7.log`), zero occurrences in
> `full-20260814`, `m5off5` and `fp1505`.
> *Positive control:* nine other `IMPSP-*` IDs are present in those same logs — `9025`
> (75), `5217` (47), `5534` (37), `5110` (31), `2021` (30), `5224` (27), `196` (22),
> `9082` (16), `2040` (12) — so this is a real absence, not a failed grep.
>
> The likely reason: the scan-cell population that made Innovus believe chains existed
> collapsed in the same window, from **37,834 of 58,120 flops (65.1%)** to
> **3,715 of 58,620 (6.34%)**. The two events are correlated; **the cause of the collapse
> is not established** — see `16-open-defects.md` §6, where one candidate explanation was
> tested and refuted. A census that still lists `IMPSP-9099` as a live ERROR will make
> this design look scan-populated when it has no chain at all.
| `IMPSP-5534` | WARN | 3 | `'add_endcaps_left_edge' and 'add_endcaps_right_edge' are using the same endcap cells` | The same cell is used on both row edges. | **UNTRIAGED (low)** — TSMC endcaps are usually orientation-specific; if the wrong one is on one edge it is a DRC issue, and this flow's DRC cannot see std-cell geometry. |
| `IMPSP-5224` | WARN | 2 | `Option '-preCap' for command add_endcaps is obsolete and has been replaced by 'setEndCapMode -rightEdge cell_name'.` | Deprecated option. | BENIGN — deprecation. |
| `IMPSR-4058` | WARN | 6 | `Route_special option: blockPinTarget should be used in conjunction with option: -connect blockPin.` | An option was passed that the command is not using. | BENIGN — `15-pg-opens-analysis.md` calls it cosmetic. |
| `IMPSR-4302` | WARN | 4 | `Cap-table/qrcTechFile is found in the design, so the same information from the technology file will be ignored.` | Cap table takes precedence over tech-file RC. | BENIGN — expected precedence. |
| `IMPCPF-980` | WARN | 1 | `Power domain PD_TOP is not bound to any library. Power domain library binding is through 'update_delay_corner -power_domain' in the MMMC file viewDefinition.tcl. Please make sure that 'update_delay_corner -power_domain PD_TOP' is specified for each delay corner in the MMMC file.` | `PD_TOP` has no library binding in any delay corner. | **UNTRIAGED (medium)** — no ID match in docs. Almost certainly the same MMMC/power-intent gap as the documented `IMPSP-5110` "no supply-net names for PD_TOP" trap (`06-fill-antenna-bondpads.md` §4), which was fixed; this one says the *delay-corner* binding is still missing. Needs a direct check of `viewDefinition.tcl`. |

### 2f. 08-05 only (removed by the LEF override — see §4)

| ID | Sev | true | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|---|
| `IMPDC-348` | WARN | 144 | `The output pin uPAD_VSSIO_T_2/VSSPST is connected to power/ground net VSSIO. This can compromise the delay calculation. Fix the issue by correcting the netlist and rerun.` | A pin the tool believes is a signal *output* drives a PG net. | **RESOLVED** on 08-06. |
| `IMPDB-2078` | WARN | 48 (place) + 24 (per later session) | `Output pin VDDPST of instance uPAD_VDDIO_T_2 is connected to power net VDDIO.  Usually it is not right to connect an output signal pin to a P/G net, unless the pin is meant to be the driver of the net. This can create a short circuit if the output is ground.  Check the connectivity in the netlist.` | Same, stated as a short-circuit risk. | **RESOLVED** on 08-06. |
| `IMPDB-1221` | **ERROR** | 2 | `A Global Net Connection (GNC) is specified to connect the power pins with the 'VDDIO' name pattern to a global net.  Unable to establish connection because the 'power' pin with the name pattern doesn't match in any cell.` | `connect_global_net -type pg_pin` matched nothing, because the pads' supply pins were not classified as power. | **RESOLVED** on 08-06 (already triaged; `16-open-defects.md` §4 correctly calls the old report stale). |

---

## 3. Census — CTS (`3_pnr_clock.tcl`)

Session totals: **08-06 → 478 W / 108 E**; **08-05 → 524 W / 108 E**;
current `cts_ocvfirst` → **502 W / 108 E**. The 108 errors are the LEF block (§2a) plus
`IMPSP-9099`-free; no new error class appears in CTS. The LEF block from §2a repeats here
in full and is not restated.

True counts from the post-CTS summary tables (`core70:27674`, `pnr_all:32304`,
`cts_ocvfirst:25278`).

| ID | Sev | 08-05 | 08-06 | current | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|---|---|---|
| `IMPESI-3086` | WARN | 95 | 90 | **113** | `The cell 'PDDW04DGZ_G' does not have characterized noise model(s) for 'tphn65lpgv2od3_slwc' lib(s). Missing noise information could compromise the accuracy of analysis.` | Cells with no CCS-noise data; SI analysis on them is approximate. | REAL-BUT-KNOWN — `scripts/06-cts-and-route.md` calls it extraction/delay-calc noise. Count is drifting; see §4. |
| `IMPCCOPT-2406` | WARN | 60 | 60 | 60 | `Clock halo disabled on instance 'uPAD_SWDCK_I'. Clock halo defined by attributes 'cts_cell_density' and 'cts_adjacent_rows_legal'. Physical cell width = '25.000um' and height = '135.000um'.` | 60 clock instances are too large for a halo, so none is applied. | BENIGN — all 60 are IO pads (135 µm tall); a halo is meaningless there. |
| `IMPCCOPT-2169` | WARN | 58 | 50 | 50 | `Cannot extract parasitics for non-ILM net 'TL_CLK_RX' in RC corner default_rc_corner_worst.` | No parasitics available for that clock net. | **UNTRIAGED (medium)** — pairs with 2171/2220/2276; see §6.3. |
| `IMPCCOPT-2171` | WARN | 58 | 49 | 50 | `Unable to get/extract RC parasitics for net 'TL_CLK_RX'. Using estimated values, based on estimated route, as a fallback.` | The clock is timed on *estimated* RC, not real RC. | **UNTRIAGED (medium)** — see §6.3. |
| `IMPCCOPT-1304` | WARN | 8 | 8 | 8 | `Net SWDCK unexpectedly has no routing present after clock post-route optimization. Net will be implemented by a later routing step.` | 8 clock nets are unrouted after clock post-route opt. Nets named: `CLK`, `RMII_REF_CLK`, `SWDCK`, `TL_CLK_RX`. | **UNTRIAGED (medium)** — see §6.3. |
| `IMPCCOPT-1023` | WARN | **1** | **5** | **5** | `Did not meet the skew target of 0.097ns for skew group D2D_RX_CLK_0/default_constraint_mode in half corner default_delay_corner_max:setup.late. Achieved skew of 0.116ns.` | The CTS skew target was missed on 5 skew groups. | **UNTRIAGED (medium-high)** — **got worse between runs**; see §4 and §6.3. Groups: `D2D_RX_CLK_0` (0.116 vs 0.097 ns), `clk` (0.102 ns), and 3 QSPI register-file generated clocks. |
| `IMPCCOPT-1007` | WARN | **8** | **3** | 3 | `Did not meet the max transition constraint. Found 95 slew violations below cell u_…/CTS_ccl_a_buf_00302 (a lib_cell CKBD16) at (1129.800,1198.600) … The worst violation was at the pin u_…/u_network_core/u_network_core_u_stclkctrl_reg_clk_divider_reg…` | Clock-tree transition violations, counted per sub-tree. | **UNTRIAGED (medium)** — the *message* count fell 8→3 but each message carries its own violation total: 08-06 sums to **283** slew violations (101 + 87 + 95); 08-05 sums to **622** across its 8 messages. Improved, still large. Cross-reference the documented post-route DRV counts in `11-known-issues.md` §(g) and `16-open-defects.md` §2. |
| `IMPCCOPT-1033` | WARN | 4 | 4 | 4 | `Did not meet the max_capacitance constraint of 0.000pF below the root driver for clock_tree D2D_RX_CLK_0 at (84.815,564.500), in power domain PD_TOP. Achieved capacitance of 1.593pF.` | Max-cap target is **0.000 pF** — i.e. no real constraint exists, so it can never be met. | **UNTRIAGED (medium)** — the "0.000pF" is the tell: it is the same missing-driver-model problem as `IMPCCOPT-4313`. See §6.3. |
| `IMPCCOPT-4313` | WARN | 4 | 4 | 4 | `Innovus cannot determine the drive strength of TL_CLK_RX, which drives the root of clock_tree D2D_RX_CLK_0. To time this clock tree, Innovus will assume that it is driven by a driver cell with a fixed output slew of 0.000 and a maximum driven capacitance of 0.000. It is recommended that you set the cts_clock_tree_source_driver attribute on this clock tree appropriately…` | The die-to-die RX clock tree is timed as if driven by an ideal, infinitely strong driver. | **UNTRIAGED — #2, see §6.3.** |
| `IMPCCOPT-2276` | WARN | 4 | 4 | 4 | `CCOpt/PRO found clock net 'SWDCK' is not routed.` | Same four clock nets as 1304. | UNTRIAGED (medium) — §6.3. |
| `IMPCCOPT-2248` | WARN | 3 | 3 | 3 | `Clock QSPI_SCLK has a source defined at module port u_…/u_qspi_clock_div/QSPI_SCLK_i. CCOpt does not support module port clocks and will consider the clock to be sourced at u_…/g611/Z. This may lead to clock latency differences between CCOpt and timing analysis.` | CCOpt and STA disagree about where this clock starts. | REAL-BUT-KNOWN — `scripts/01-stage-scripts-and-makefile.md`. |
| `IMPCCOPT-4144` | WARN | 2 | 2 | 2 | `The SDC clock D2D_TX_CLK_0 has source pin TL_CLK_TX, which is an input pin. Clock trees for this clock will be defined under the corresponding output pins instead.` | The D2D TX clock is declared on an input pin. | REAL-BUT-KNOWN — `scripts/01-…`. |
| `IMPCCOPT-2220` | WARN | — | **1** | **1** | `CCOpt/PRO cannot construct a Route/RC graph for unrouted net 'TL_CLK_RX'.` | New on 08-06. | **UNTRIAGED (medium)** — **appeared between runs**; §4, §6.3. |
| `IMPCCOPT-2245` | WARN | — | **1** | **1** | `Cannot perform post-route optimization on net driven by pin 'TL_CLK_RX'.` | New on 08-06; the D2D RX clock net is excluded from post-route optimisation. | **UNTRIAGED (medium-high)** — **appeared between runs**; §4, §6.3. |
| `TA-1018` | WARN | 5 | 5 | 5 | `A source latency path to the generated clock mii_tx_clk through source pin RMII_REF_CLK to target pin u_…/u_rmii_to_mii/mtx_clk in view typical_analysis_view cannot be found. Timing analysis will use 0 ns source latency for the generated clock and will interpret the master clock based on the polarity at the master clock source pin.` | 5 generated clocks are timed with **0 ns** source latency because no path to their source could be traced. Affected: `mii_tx_clk`, `mii_rx_clk`, `QSPI_SCLK`, `QSPI_SCLK_o`, `D2D_TX_CLK_0`. | **UNTRIAGED (medium-high)** — part of the clock-source-modelling cluster in §6.3; `D2D_TX_CLK_0` is one of the five. |
| `IMPOPT-3564` | WARN | 1 | 1 | 1 | `The following cells are set dont_use temporarily by the tool because there are no rows defined for their technology site, or they are not placeable in any power domain, or their pins cannot be snapped to the tracks.` / `Cell ISOHID1, site core.` | Isolation cells `ISOHID1/2/4` are unusable. | BENIGN — single power domain, no isolation needed. Related to `IMPFP-3961`. |
| `IMPDBTCL-321` | WARN | 4 | 4 | 4 | `The attribute 'route_design_exp_deterministic_multi_thread' still works but will be obsolete in a future major release.` | Deprecation. | BENIGN. |
| `IMPTCM-77` | WARN | 1 | 1 | 1 | `Option "-routeExpDeterministicMultiThread" for command setNanoRouteMode is obsolete and will be removed in a future release.` | Deprecation. | BENIGN. |
| `IMPCTE-337` | WARN | 1 | 1 | 1 | `An unsupported Liberty attribute: max_clock_tree_path - was found on pin CLK of cell: rf_01k in library: RF_LIB_01K_ss_1p08v_1p08v_125c. This attribute is not supported by timing analysis and will be ignored.` | A memory `.lib` attribute is ignored. | BENIGN (already triaged). |
| `NRDB-2106` | WARN | 2 | 2 | 1 | `#WARNING (NRDB-2106) Ignoring layer M9 MINIMUMCUT rule with WIDTH (<redacted>) <= the layer's MINWIDTH (<redacted>).` (rule values elided — TSMC licence) | A DRC rule in the tech LEF is self-inconsistent and is dropped. | **UNTRIAGED (low-medium)** — a *foundry* rule is being ignored on M9. It cannot be checked here (this flow's Calibre run is invalid), so it must be checked by whoever runs real signoff DRC. |

---

## 4. Census — ROUTE + FILL (`4_pnr_route.tcl`)

Session total, 08-06: **3,462 W / 113 E** (count taken at the abort, not a clean end).
08-05: **no session total exists** — the session hung at the Calibre block and was never
allowed to print one. The LEF block from §2a repeats here in full.

True counts from the post-load table (`core70:29950`, `pnr_all:34583`) where available.

| ID | Sev | count | Representative line (verbatim) | What it means | Class |
|---|---|---|---|---|---|
| `IMPESI-3095` | WARN | ≥60, capped 3× | `Net: 'SE' has no receivers. SI analysis is not performed.` | Nets with no load are skipped by SI analysis. Nets named include `SE`, `TEST`, `CLK`, `NRST`, `SWDIO`, `SWDCK`, `TL_CLK_RX`, `RMII_*`, `QSPI_IO[*]`, `HOSTIO4_P1[*]`. | **UNTRIAGED (low as SI, medium as a symptom)** — a net with *no receivers* at all is a functional statement, not an SI one. `SE`/`TEST` are expected (`DFT 0`). `QSPI_IO[*]`, `RMII_RXD[*]`, `HOSTIO4_P1[*]`, `SWDIO`, `TL_CLK_RX` having no receivers is not obviously expected and is worth one pass. |
| `IMPCCOPT-2332` | WARN | true 29 | `The attribute locked_originally is deprecated. It still works, but it may be removed in a future release.` | Deprecation. | BENIGN. |
| `IMPOGDS-217` | WARN | ≥20 printed; **true 424** (see `IMPOGDS-218`) | `Master cell: DFSND2 not found in merged file(s) and will therefore not be included in the resulting write_stream file. Verify the file names specified with the -merge option are correct and that they contain a definition of this cell.` | A cell used in the design has no GDS to merge, so it is written as an **empty reference**. | REAL-BUT-KNOWN, **tapeout-blocking** — `00-index.md` point 3, `09-signoff-checklist.md` items 10/13/16, `TSMC_BACKEND_PACKAGE_REQUEST.md`. `write_stream … -merge $gds_merge_list` merges **only the 8 memory macros**; standard cells, IO drivers and bond pads have no geometry. |
| `IMPOGDS-218` | WARN | 1 | `Number of master cells not found after merging: 424` | The true total for the above. | Same. **421 on 08-05 → 424 on 08-06** (§4). |
| `IMPOGDS-4004` | WARN | ≥20, capped | `Ignoring duplicate structure 065_LP_M3_v1d1_corner_edge_ARM found in /research/precompiled_mems/TSMC65/rf_16k//rf_16k.gds2. To avoid the warning message, use the option -uniquifyCellNames to disable cells duplication.` | Two merged memory GDS files define the same structure name; the second is dropped. | **UNTRIAGED (medium)** — no ID match in docs. If two RF macro GDS files define the *same-named but different* sub-structure, the merged GDS silently uses one of them for both. See §6.5. |
| `IMPOGDS-392` | WARN | 1 | `Unknown layer M11` | The GDS out-map names a layer this 9-metal stack does not have. | BENIGN — documented harmless in `scripts/07-filler-and-bondpads.md` §6.2. |
| `IMPOGDS-250` | WARN | 1 | `Specified unit is smaller than the one in db. You may have rounding problems` | `-unit 1000` vs a 2000 dbu database — coordinates are halved. | REAL-BUT-KNOWN, documented as an expected consequence of `-unit 1000` (`scripts/07-…`). Note the log states the scaling explicitly: `unit scaling factor = 0.5`. |
| `IMPVFC-97` | WARN | **2 (08-06 only)** | `IO pin VDDIO of net VDDIO has not been assigned. Please make sure it is assigned and rerun check_connectivity.` | The `VDDIO` and `VSSIO` top-level pins are not attached to anything. | **UNTRIAGED — appeared between runs.** §4, §5b. |
| `IMPVFC-3` | WARN | 1 | `Verify Connectivity stopped: Number of errors exceeds the limit 1000` | Connectivity checking gave up at 1000 problems. | REAL-BUT-KNOWN — `14-drc-triage.md` §6(c). |
| `IMPVFC-98` | (summary) | 2 (08-06) | `2 Problem(s) (IMPVFC-98): Net has no global routing and no special routing.` | `VDDIO` and `VSSIO` have **no routing at all**. | REAL-BUT-KNOWN — `16-open-defects.md` §4. |
| `IMPVFC-200` | (summary) | 329 (08-05) → 318 (08-06 capped) → **350 uncapped** | `350 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected together.` | PG opens. | REAL-BUT-KNOWN — `15-pg-opens-analysis.md`. |
| `IMPVFC-94` | (summary) | 671 (08-05) → 680 (08-06 capped) → **1,518 uncapped** | `1518 Problem(s) (IMPVFC-94): The net has dangling wire(s).` | PG dangling wires. | REAL-BUT-KNOWN. **The uncapped numbers here come from `baseline_2026-08-06/reports/conn_uncapped.rep`, which already exists in the tree.** Total real problems: **1,870**, not 1,000. |
| `IMPCTE-104` | WARN | 6 | `The constraint mode of this inactive view 'typical_analysis_view_setup' has been modified and may need to be reanalyzed to ensure proper timing results.` | An inactive view's constraints changed and were not re-analysed. | **UNTRIAGED (low-medium)** — if `typical_analysis_view` is a signoff view, its reported timing may be stale. |
| `IMPEXT-3518` | WARN | 4 | `The lower process node is set (using command 'set_design_mode') but the technology file for TQuantus extraction not specified. Therefore, going for post_route (extract_rc_effort_level low) extraction instead of recommended extractor 'TQuantus' for lower nodes.` | Extraction ran at **low effort** with the cap-table engine, not the signoff extractor. | **UNTRIAGED (medium-high)** — see §4. Topic (but not the ID) documented in `scripts/03-mmmc-sdc-and-power-intent.md`: no `-qrc_tech` is supplied. |
| `IMPEXT-3503` | WARN | 1 | `The corner setup has changed in the MMMC flow. New RC corners 'default_rc_corner_worst default_rc_corner_best' have been added, therefore, no parasitic data exists for them. As a result, the parasitic data in the tool from the previous setup is deleted.` | All extracted parasitics were thrown away mid-flow when corners changed. | **UNTRIAGED (medium)** — needs confirmation that a re-extraction happened before the final timing reports were written. |
| `IMPEXT-3493` | WARN | 1 | `The design extraction status has been reset by set_analysis_view/update_rc_corner or set_db command. The parasitic data can be regenerated either by extracting the design using the extract_rc command or by loading the SPEF or RCDB file(s).` | Same event, stated as a status reset. | UNTRIAGED (medium) — same question. |
| `IMPUDM-33` | WARN | true 3 | `Global variable "timing_enable_separate_device_slew_effect_sensitivities" is obsolete and will be removed in a future release.` | Deprecation. | BENIGN. |
| `IMPCTE-107` | WARN | true 1 | `The following globals have been obsoleted since version . They will be removed in the next release.` | Deprecation list (with an empty version string). | BENIGN. |
| `IMPOPT-7077` | WARN | 1 | `Some of the LEF equivalent cells have different ANTENNAGATEAREA/ANTENNADIFFAREA/PINS etc... attributes. They will not be swapped for fixed instances and for lefsafe operations like opt_leakage_power in postroute mode.` | Some cell swaps are blocked because "equivalent" cells are not antenna-equivalent. | **UNTRIAGED (low)** — restricts optimisation only; adjacent to the documented `IMPLF-200` antenna gap. |
| `IMPSP-5217` | WARN | 2 | `add_fillers command is running on a postRoute database. It is recommended to be followed by eco_route -target command to make the DRC clean.` | Filler insertion after routing can create DRCs that were not fixed. | BENIGN / already triaged. |
| `IMPSP-9082` | WARN | 1 | `verifyGeometry needs to be executed before -fixDRC option could be used.` | `-fixDRC` did nothing. | BENIGN / already triaged. |
| `TCLCMD-1531` | WARN | 10 | `'create_generated_clock' has been applied on hierarchical pin '…QSPI_SCLK_i' (File /tmpdir/innovus_temp_…/default_constraint_mode.sdc, Line 15).` | Same as §2b, re-read from the MMMC temp SDC. | UNTRIAGED (low). |
| `NRDB-537` | WARN | 1 | `#WARNING (NRDB-537) Cannot find net clk` | NanoRoute was told about a net named `clk` that does not exist. | Already triaged. |
| `NRDB-1028` | WARN | 1 | `#WARNING (NRDB-1028) Some option affecting pin access calculation is set by the user. Pin access is to be recalculated. This incurs runtime.` | Runtime note. | BENIGN. |
| `IMPSE-110` | **ERROR** | 3 | `File '/eda/mentor/calibre/shared/pkgs/icv/tools/queryenc/encounter.tcl' line 47: can't find package Tk 8.0.` | The Calibre-in-Innovus integration needs Tk, which is absent in batch. | REAL-BUT-KNOWN — `16-open-defects.md`; fixed by `env -u CALIBRE_HOME`. |
| `IMPSYT-6692` | **ERROR** | 1 | `Invalid return code while executing '.../4_pnr_route.tcl' was returned and script processing was stopped.` | The route script aborted. | REAL-BUT-KNOWN — the Calibre `exec` failure. |
| `IMPSYT-6693` | **ERROR** | 1 | `Error message: .../4_pnr_route.tcl: //  Calibre v2023.1_18.8 …` | The abort's message text. | Same. |
| (Calibre, no Cadence ID) | ERROR | 3 | `ERROR: Failure to open input file GDSFILENAME for read access.` | The foundry deck's `LAYOUT PATH "GDSFILENAME"` placeholder was never overridden. | REAL-BUT-KNOWN — `12-calibre-drc.md`, `09-signoff-checklist.md` item 13. |
| `IMPESI-3140` | WARN | 1 (08-05 only) | `Bumpy transitions may exist in the design which may lead to inaccurate delay computation. To report/analyze the nets having bumpy transition, please enable delay report and use command 'report_noise -bumpy_waveform -threshold 0' after timing analysis.` | Non-monotonic waveforms may be corrupting delay numbers. | **UNTRIAGED (low-medium)** — printed mid-line (`Dumping Information for Job 532801 **WARN: …`), which is why a line-anchored grep misses it. Absent from the 08-06 log. |
| `NRDB-51` | WARN | 8 (08-05 only) | `#WARNING (NRDB-51) SPECIAL_NET VDDIO has no instance pin or special wire in its connectivity definition. NET with the same name will be routed but will not be connected to the empty SPECIAL_NET.` | `VDDIO`/`VSSIO` were routed as **ordinary signal nets**. | **RESOLVED** on 08-06 by the LEF override — replaced by `IMPVFC-97`/`98`. Documented in `scripts/config.tcl:144`. |

---

## 5. What changed between the two complete runs

The brief expected floorplan-driven movement. There is some — but the dominant change is
**not** the floorplan. Between 2026-08-05 and 2026-08-06 two independent things changed:

1. `CORE_TO_IO` 50 → 70 (the core box moved in 20 µm on every side).
2. A **local override LEF** was introduced (`scripts/config.tcl` `IO_PAD_DRIVER_LEF` →
   `ASIC/tech_wrappers/tsmc65/local_overrides/tphn65lpgv2od3_sl_9lm.lef`) adding
   `USE POWER ;` / `USE GROUND ;` to three IO supply pins that TSMC ships as plain
   `INOUT` signal pins.

Change 2 explains almost every class delta.

> **Path note (2026-08-14).** The two paths in this section are recorded as they stood on
> 2026-08-06 and are correct for that run. The three-line delta is unchanged, but the file
> is no longer a committed copy under `local_overrides/` — since `bf619f1` it is generated
> from the read-only PDK into `ASIC/tech_wrappers/tsmc65/generated/`, and the
> `scripts/config.tcl:144` line reference above has moved. Retiring the patch altogether is
> planned and not yet done. See
> [29-private-tsmc-tech-repo](29-private-tsmc-tech-repo.md) §2a. **Nothing in the 08-05 vs
> 08-06 comparison changes** — it is a record of two runs that happened.

### 5a. Classes that DISAPPEARED (all caused by change 2 — genuine fixes)

| ID | 08-05 | 08-06 | Why |
|---|---|---|---|
| `IMPDC-348` | 144 | **0** | Pad supply pins are no longer seen as signal outputs on a PG net. |
| `IMPDB-2078` | 48 + 24/session | **0** | Same. This was the "can create a short circuit" warning. |
| `IMPDB-1221` | 2 (ERROR) | **0** | `connect_global_net -type pg_pin` now matches. |
| `NRDB-51` | 8 | **0** | `VDDIO`/`VSSIO` are no longer empty SPECIAL_NETs. |
| `IMPESI-3140` | 1 | 0 | Not explained; may simply not have been reached before the abort. |

Corroborating outcome: **Innovus DRC dropped from 580 to 102 violations** (`reports/…_imp_drc.rep`).
The 08-05 report is full of `SHORT: Regular Wire of Net VDDIO & Blockage of Cell BuPAD_VDDIO_L_0 (M8)`
— exactly what `NRDB-51` predicted. Those are gone.

### 5b. Classes that APPEARED

| ID | 08-05 | 08-06 | Reading |
|---|---|---|---|
| `IMPVFC-97` | 0 | **2** | `VDDIO`/`VSSIO` now have **no routing at all**, where before they had (wrong) signal routing. The fix converted "routed wrongly" into "not routed". |
| `IMPVFC-98` | 0 | **2** | Same event, from the summary block. |
| `IMPCCOPT-2220` | 0 | **1** | `TL_CLK_RX` unrouted → no Route/RC graph. |
| `IMPCCOPT-2245` | 0 | **1** | `TL_CLK_RX` excluded from post-route optimisation. |

### 5c. Classes whose COUNT changed

| ID | 08-05 | 08-06 | current | Reading |
|---|---|---|---|---|
| `TCLCMD-917` / `TCLCMD-513` | ~22 | **~70** | — | The pads' supply pins are now *power* pins, so `get_pins` fails on **all 68** of them instead of ~20. The SDC file is byte-identical (mtime 2026-08-05 12:56, read by both runs). This is a direct, mechanical consequence of change 2, and it is what pushes the place-session error total 132 → 178. |
| `IMPOGDS-218` | 421 | **424** | — | Three more standard-cell masters used by the margin-70 build have no GDS. Direction of travel is wrong; magnitude is trivial next to 421. |
| `IMPCCOPT-1023` | 1 | **5** | 5 | **Skew targets missed on 5 groups instead of 1.** The new offender is `D2D_RX_CLK_0` (0.116 ns achieved vs 0.097 ns target). This one *is* plausibly the floorplan: a 20 µm tighter core box on a die-to-die clock whose source driver is unmodelled. |
| `IMPCCOPT-1007` | 8 msgs / 622 viols | 3 msgs / **283 viols** | 3 | Clock-tree slew violations more than halved. Genuine improvement. |
| `IMPCCOPT-2169` | 58 | 50 | 50 | Fewer clock nets without parasitics. |
| `IMPCCOPT-2171` | 58 | 49 | 50 | Same. |
| `IMPESI-3086` | 95 | 90 | **113** | Cells missing noise models. The *current* CTS run is worse than either baseline — 113. Worth knowing before the OCV-first experiment is adopted. |
| `IMPLF-200` | 16 | 15 | 15 | Noise. |
| `IMPVFC-200` / `IMPVFC-94` | 329 / 671 | 318 / 680 (capped) | — | Both capped at 1000 total, so the comparison is meaningless. The **uncapped** 08-06 figure is 350 / 1,518 = 1,870 problems. No uncapped 08-05 figure exists. |
| PLACE session errors | 132 | **178** | — | Entirely explained by `TCLCMD-917` +48, `IMPDB-1221` −2. |
| Innovus DRC | 580 | **102** | — | The headline improvement. |

### 5d. Classes that are stable across all three logs

The whole LEF block (`TECHLIB-302` 111, `IMPLF-223` 105, `IMPLF-119` 22, `IMPLF-151` 9,
`IMPFP-3961` 8, `IMPTS-282` 6, `TECHLIB-459` 3, `IMPMSMV-3501` 1), `SDF-802` (~53.6 k),
`IMPCCOPT-2406` 60, `IMPCCOPT-1304` 8, `IMPCCOPT-2276` 4, `IMPCCOPT-4313` 4,
`IMPCCOPT-1033` 4, `IMPCCOPT-2248` 3, `IMPCCOPT-4144` 2, `TA-1018` 5, `IMPSP-9099` 2.
The `cts_ocvfirst` run has **exactly the same ID set** as the 08-06 CTS stage — the
OCV-first change introduced no new message class.

---

## 6. What to chase next — top 5 untriaged, ranked by plausible silicon impact

Ranking is by *plausible impact on working silicon*, not by count. Everything already
covered by `11-known-issues.md`, `15-pg-opens-analysis.md`, `16-open-defects.md` or
`TSMC_BACKEND_PACKAGE_REQUEST.md` is excluded — those are known, and the GDS being
merge-incomplete (424 empty masters) remains the single largest tapeout blocker
regardless of anything below.

### 6.1 — `CDFG2G-608`: asynchronous reset driven from a non-constant signal in the AXI chiplet controller

```
Warning : Accessed non-constant signal during asynchronous set or reset operation. [CDFG2G-608]
        : in file '/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv' on line 784, column 39.
        : This may cause simulation mismatches between the original and synthesized designs.
```

Count 1. Genus is saying the synthesised gates may **not behave like the RTL** on an
asynchronous set/reset path inside `axi_chiplet_controller` — the block at the centre of
the unresolved cross-die write wedge. Every wedge investigation so far has been conducted
against RTL simulation. If the gate-level reset behaviour differs from the RTL, the entire
simulation-based investigation is looking at a different circuit from the one on the die.
That possibility has not been on the table.

*Impact if real:* a reset/init path in the D2D controller that behaves differently in
silicon than in every simulation ever run against it.

*Evidence that would settle it:*
1. Read `tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv` around line 784 and
   identify the async set/reset expression and what drives it.
2. Diff the RTL against the mapped netlist for that flop group:
   `grep` the reset net in `outputs/nanosoc_eth_chiplet_pads_gate.v` and check whether the
   mapped flop uses `CDN`/`SDN` driven by the same expression or by a synthesised gate.
3. LEC (`make lec`) already runs; check whether that specific instance group is in the
   mapped/equivalent set or was dropped as a non-mapped point.
4. Gate-level sim of the wedge sequence against `outputs/…_pnr.sdf` — that is the only
   test that has never been run and is the direct test of the hypothesis.

### 6.2 — `HPT-76` / `VLOGPT-6`: nine modules silently replaced by a later filelist entry

```
: Replacing Verilog description 'tidelink_phy_sync_detect' with Verilog module in file '.../tidelink/deps/tidelink-phy/rtl/tidelink_phy_sync_detect.sv' on line 87, column 31.
```

Ten replacement events across **nine distinct modules** — each defined twice (three times
for `cmsdk_ahb_to_apb`) with the **later read winning**: `ahb3lite_to_wb`,
`cmsdk_ahb_to_apb` (×2 events), `cmsdk_ahb_to_sram`, `cmsdk_apb_slave_mux`,
`tidelink_phy_sync_detect`, `xhb500_flop`, `xhb500_or`, `xhb500_sync`, `xhb500_xor`.

`PHYSICAL_HANDOFF.md` §4.5 documents this hazard in the abstract ("the filelist must not
depend on tool declaration order", resolved by `flist/resolve_tidelink_flist.py`) but does
not record that nine modules are still hitting it, nor which copies won. Two of the nine —
`tidelink_phy_sync_detect` and `xhb500_sync` — are **clock-domain-crossing synchronisers on
the die-to-die link**. Silently taking the wrong copy of a CDC synchroniser is exactly the
shape of a defect that passes every simulation and wedges in silicon.

*Impact if real:* the taped-out netlist contains a different synchroniser (or bridge) from
the one that was verified.

*Evidence that would settle it:*
1. Extract all ten `HPT-76`/`VLOGPT-6` pairs from `baseline_2026-08-05/logs/syn_logs.log7`
   with both the replaced and replacing file paths (the `pnr_all.log` copy is truncated).
2. `diff` each winning file against the loser. If they are identical, this is BENIGN and
   can be closed permanently.
3. If any differ, check which one the elaborated netlist actually contains
   (`outputs/nanosoc_eth_chiplet_pads_gate.v`).
4. Set `set_attribute hdl_error_on_replacement true` (or equivalent) so the next synthesis
   fails loudly instead of picking silently.

### 6.3 — The die-to-die RX clock tree is built on invented numbers (`IMPCCOPT-4313` + `1033` + `2169`/`2171` + `1304`/`2276`/`2220`/`2245` + `1023`)

These are one defect wearing eight message IDs. In order:

```
**WARN: (IMPCCOPT-4313): Innovus cannot determine the drive strength of TL_CLK_RX, which drives the root of clock_tree D2D_RX_CLK_0. To time this clock tree, Innovus will assume that it is driven by a driver cell with a fixed output slew of 0.000 and a maximum driven capacitance of 0.000.
**WARN: (IMPCCOPT-1033): Did not meet the max_capacitance constraint of 0.000pF below the root driver for clock_tree D2D_RX_CLK_0 … Achieved capacitance of 1.593pF.
**WARN: (IMPCCOPT-2171): Unable to get/extract RC parasitics for net 'TL_CLK_RX'. Using estimated values, based on estimated route, as a fallback.
**WARN: (IMPCCOPT-1304): Net SWDCK unexpectedly has no routing present after clock post-route optimization.
**WARN: (IMPCCOPT-2245): Cannot perform post-route optimization on net driven by pin 'TL_CLK_RX'.   [NEW on 08-06]
**WARN: (IMPCCOPT-1023): Did not meet the skew target of 0.097ns for skew group D2D_RX_CLK_0/… Achieved skew of 0.116ns.   [1 → 5 between runs]
```

The chain: `TL_CLK_RX` has no source driver model → CTS assumes **slew 0.000 ns, max cap
0.000 pF** → the clock tree is built and timed as if driven by an ideal infinite-strength
driver → its RC is estimated, not extracted → it ends up unrouted at clock post-route → it
is skipped by post-route optimisation → its skew target is missed. Every one of these is
optimistic in the same direction, on the **incoming die-to-die clock**.

A ninth ID belongs to the same cluster from the STA side:

```
**WARN: (TA-1018): A source latency path to the generated clock mii_tx_clk through source pin RMII_REF_CLK to target pin u_…/mtx_clk … cannot be found. Timing analysis will use 0 ns source latency for the generated clock…
```

×5, one of which is `D2D_TX_CLK_0`. Five generated clocks are timed with **0 ns** source
latency because STA could not trace a path to their source — the transmit-side counterpart
of the receive-side modelling gap above.

`scripts/06-cts-and-route.md` notes that no `cts_target_*` is set at all, but none of these
nine IDs appears in any doc, and the 08-06 regression (2220/2245 new, 1023 1→5) is new.

*Impact if real:* the D2D receive clock is faster/cleaner in the timing model than on the
die. That is a direct candidate mechanism for a link that trains but wedges under traffic.

*Evidence that would settle it:*
1. Set `cts_clock_tree_source_driver` on `D2D_RX_CLK_0` / `D2D_TX_CLK_0` to a real pad
   driver and re-run CTS **only** (`make pnr_cts` — one seat, ~50 min); compare
   `reports/timing_summary_03_cts_opt.rep` and the `IMPCCOPT-1023` skew numbers.
2. Report the actual routed state of `TL_CLK_RX`, `SWDCK`, `CLK`, `RMII_REF_CLK` in the
   final DB (`report_route -net TL_CLK_RX`) — "not routed at clock post-route" may be
   corrected by the later signal-route pass, or may not.
3. Extract the post-route `D2D_RX_CLK_0` insertion delay and skew from
   `reports/timing_summary_05_route_opt.rep` and compare against the KR260 silicon
   measurement — the link is up on silicon (FCSM=4), so a real number exists to compare to.

### 6.4 — `CDFG-508` ×122: registers deleted as unused, including a synchroniser stage and the PTP register file

```
: Removing unused flip-flop register 'reg_50' in module 'rgs' in file '.../ethernet-mac-ahb/src/rtl/ha1588_patches/reg.v' on line 117.
: Removing unused flip-flop register 'ResetTxCIrq_sync1' in module 'eth_registers'
```

This project has already shipped one hollow GDSII to Genus unused-logic removal
(`11-known-issues.md` §(i), `GLO-34`). `CDFG-508` is the elaboration-time sibling and it is
not tracked anywhere. Two of the hits are alarming on their face:

* `ResetTxCIrq_sync1` in `eth_registers` — the **first stage of a reset synchroniser**.
  If stage 1 is deleted because stage 2 is the only reader and stage 2 was also optimised,
  the synchroniser is gone.
* `reg_50`, `reg_54`, `reg_58`, `reg_5c`, `reg_70`, `reg_74` in `rgs`
  (`ha1588_patches/reg.v`) — the **PTP hardware clock register file**. Registers a driver
  is supposed to be able to read should not be "unused".

*Impact if real:* software-visible registers that read as constants, or a missing reset
synchroniser on the Ethernet TX path.

*Evidence that would settle it:*
1. `grep -A2 '\[CDFG-508\]' baseline_2026-08-05/logs/syn_logs.log7` and enumerate all 122
   with module + file + line.
2. For the `rgs` hits: check whether those addresses are in the PTP register map
   (`ptp-hardware-clock-ahb` / `ethernet-mac-ahb/src/rdl`) and are expected to be readable.
3. For `ResetTxCIrq_sync1`: read `eth_registers` and confirm whether the second stage
   survives; check `report sequential -deleted` output if it was captured.
4. Cross-check against the existing CDC results (`docs/CDC_FINDINGS.md`) — a deleted sync
   stage should show up there too, and if it does not, that is a gap in the CDC flow.

### 6.5 — The un-countable classes: `TCLCMD-1005`, `CDFG2G-616`, `IMPESI-3095`

Three classes where the flow is actively hiding information from us:

* **`TCLCMD-1005`** — capped at 20 in **all three** Innovus sessions of both runs, and
  *not one instance is visible in any log*. We do not know what this message says. It is
  the only ID in the census whose text is unknown.
* **`CDFG2G-616` ×2** — `Latch inferred. Check and revisit your RTL if this is not the
  intended behavior.` Two latches exist in this design. The individual messages are absent
  from both `pnr_all.log` and `syn_logs.log7`; only the summary-table row survives, so we
  do not know **where**.
* **`IMPESI-3095` ≥60** — `Net: 'SE' has no receivers.` Capped three times, so the true
  count is unknown. Named nets include `QSPI_IO[0..3]`, `RMII_RXD[0..1]`, `RMII_CRS_DV`,
  `SWDIO`, `HOSTIO4_P1[0..6]` and `TL_CLK_RX` — top-level I/O with **no loads**. `SE`/`TEST`
  are explained by `DFT 0`; the rest are not.
* **`IMPOGDS-4004` ≥20** — `Ignoring duplicate structure 065_LP_M3_v1d1_corner_edge_ARM
  found in .../rf_16k.gds2.` Capped, so we do not know how many structures were dropped
  from the merged GDS, nor whether any same-named structure differs between the four RF
  macro GDS files. `-uniquifyCellNames` would remove the ambiguity.

*Evidence that would settle all three, cheaply:* add to the flow, once —

```tcl
set_message -no_limit -id {TCLCMD-1005 TCLCMD-917 TCLCMD-513 SDF-802 \
                          IMPPP-531 IMPPP-532 IMPPP-570 IMPPP-4500 \
                          IMPESI-3095 IMPESI-3086 IMPOGDS-217 IMPCCOPT-2169 IMPCCOPT-2171}
set_attribute hdl_error_on_latch true   ;# Genus — turns CDFG2G-616 into a hard stop
```

and for the latches, re-run elaboration only. This costs one synthesis run and converts
five unknowns into counts. It is the single highest-value change in this document, because
**the flow currently prints under 0.5 % of the warnings it generates** and every triage
above is working from a 20-instance sample.

---

## 7. Honest limits of this census

* **Suppressed messages are invisible.** The summary tables say "all messages that are not
  suppressed". Anything under `set_message -suppress` appears nowhere, including in the
  session totals. No `set_message -suppress` was found in the flow scripts, but a suppressed
  ID is by construction undetectable from a log.
* **Derived counts are arithmetic, not observation.** `TCLCMD-917` ≈70/≈22, and the
  ~3,000–3,100 figure for the `IMPPP-*` family, come from subtracting known quantities from
  session totals. They are consistent with independent evidence (68 supply-pin references
  in the SDC; the 08-05/08-06 totals differing by the expected amount) but they are not
  counts. The `SDF-802` figure (~53,605) *is* independently corroborated, against the SDF
  file itself.
* **The 08-05 route session has no total.** It hung before printing one, so no
  route-session warning/error total exists for the margin-50 run and that row of the
  comparison is missing rather than zero.
* **Genus ran only on 08-05.** The 08-06 run reused the netlist and SDC, so every synthesis
  class in §1 is dated 2026-08-05 12:56 and has not been re-checked since.
* **`cts_ocvfirst.log` is a partial run** (CTS only) and was still being written from a
  live session when this was compiled; its counts are a snapshot.
* **This census covers messages, not results.** A clean message log would not make this
  design tapeout-ready: the GDS still contains 424 empty cell masters, PG connectivity
  still shows 1,870 real problems, and the in-flow DRC has never produced a valid result.
