# 17 — Silently ineffective commands

Sweep of the P&R logs for commands that ran, printed something, and had no
effect. Method: `grep -v '^@file'` on every log below, tally by message ID,
then for each ID find the script line that issued it and decide whether the
miss matters.

Logs mined:

| Log | State |
| --- | --- |
| `baseline_2026-08-06/logs/pnr_run_core70.log` | complete run, 6.7 MB |
| `baseline_2026-08-05/logs/pnr_all.log` | complete run + synthesis, 7.0 MB |
| `logs/cts_ocvfirst.log` | current run, CTS complete |
| `logs/route_ocvfirst.log` | current run, in extraction at time of writing |
| `work/innovus.log*` | per-session |

**Scope.** Everything already recorded in `11-known-issues.md`,
`14-drc-triage.md`, `15-pg-opens-analysis.md` and `16-open-defects.md` is
excluded — that covers IMPOGDS-217/218/250/392, IMPSE-110, IMPSYT-6692/6693,
IMPSR-4058, IMPCCOPT-2248, IMPCCOPT-4144, IMPSP-9082, IMPSP-5217, IMPSP-5110,
NRDB-537, TCLCMD-917, TCLCMD-513, IMPDB-1221, IMPMSMV-3501, IMPLF-223,
IMPPP-570, IMPVFC-3, IMPCTE-337, IMPSYT-1507, IMPPP-136/193, IMPTCM-162/165 and
the Calibre `GDSFILENAME` literal. What follows is new.

The current run reproduces every finding below; these are not historical.

---

## Ranked findings

| # | ID | Effect | Sev |
| --- | --- | --- | --- |
| 1 | IMPCCOPT-4313 | All 4 clock trees built against a source driver of 0.000 slew | **Changes silicon** |
| 2 | IMPCCOPT-1033 | Root max-capacitance budget is 0.000 pF, i.e. unusable | **Changes silicon** |
| 3 | TA-1018 | 5 generated clocks timed with 0 ns source latency | **Timing validity** |
| 4 | IMPEXT-3518 | Post-route signoff extraction silently downgraded to `low` | **Signoff accuracy** |
| 5 | IMPCPF-980 | CPF power-domain → library binding never happens | Low |
| 6 | IMPESI-3095 | SI analysis skipped on 9 top-level nets incl. all 4 clocks | Low |
| 7 | IMPDC-1629 | Delay-calc fanout limit 101 instead of 1000 | Unresolved |
| 8 | IMPOPT-3564 | Isolation cells auto-`dont_use` | None (no MSV) |

Four further candidates were run down and **proven harmless** — see
"Investigated and cleared" so nobody spends the afternoon on them again.

---

## 1. IMPCCOPT-4313 — every clock tree root has no driver model

```
**WARN: (IMPCCOPT-4313):	Innovus cannot determine the drive strength of CLK, which drives the root of clock_tree clk. To time this clock tree, Innovus will assume that it is driven by a driver cell with a fixed output slew of 0.000 and a maximum driven capacitance of 0.000. It is recommended that you set the cts_clock_tree_source_driver attribute on this clock tree appropriately in order to correct this assumption.
```

Four instances, one per clock tree — `CLK`→`clk`, `SWDCK`→`swdclk`,
`TL_CLK_RX`→`D2D_RX_CLK_0`, `RMII_REF_CLK`→`rmii_ref_clk`. Present in
`pnr_run_core70.log`, `pnr_all.log` and the current `cts_ocvfirst.log`.

**Responsible script lines.** This is an omission, not a bad command. Verified
by direct count over both SDC files:

| Constraint | `inputs/constraints.sdc` | `outputs/nanosoc_eth_chiplet_pads_syn.sdc` |
| --- | --- | --- |
| `set_driving_cell` | 0 | 0 |
| `set_input_transition` | 0 | 0 |
| `set_drive` | 0 | 0 |
| `set_input_delay` | 4 | 48 |

and `grep -rn 'cts_clock_tree_source_driver' scripts/ ../asic-flows/` returns
nothing, so `scripts/cts_setup.tcl` does not supply it either. The four clocks
are created at `inputs/constraints.sdc:33-34` and the equivalents at
`nanosoc_eth_chiplet_pads_syn.sdc:15-21`, on `[get_ports ...]` — top-level
ports, which is what makes the port itself the tree root.

**What it was trying to do.** `ccopt_design` (`3_pnr_clock.tcl:28`) builds and
times each clock tree from its root. The root here is the chip input port; the
receiving IO cell (`uPAD_CLK_I` etc.) is the first element *inside* the tree.

**Actual effect.** The external driver into the pad is unmodelled, so CCOpt
timed the pad receiver with a 0 ns input transition. The pad's own output slew
and delay are therefore optimistic, and that error sits at the root of every
clock tree — it propagates into insertion delay, into the skew that CTS
balanced against, and into the hold profile. The clock tree that was built is a
real, physical tree built to a slightly wrong target.

**Recommended fix.** Add to `inputs/constraints.sdc`, next to the
`create_clock` block, a `set_driving_cell` for the four clock ports naming the
actual off-chip driver (or, if unknown, the board-level worst case), plus a
`set_input_transition` for the remaining inputs. Alternatively set
`cts_clock_tree_source_driver` per tree in `scripts/cts_setup.tcl`. The SDC
route is preferable: it also fixes item 2 and applies to timing analysis, not
just CTS.

**Not determined from logs.** The magnitude. Quantifying it needs a
`report_clock_timing` before/after on the `_cts` snapshot, which needs a seat.

---

## 2. IMPCCOPT-1033 — max-capacitance constraint of 0.000 pF

```
**WARN: (IMPCCOPT-1033):	Did not meet the max_capacitance constraint of 0.000pF below the root driver for clock_tree D2D_RX_CLK_0 at (84.815,564.500), in power domain PD_TOP. Achieved capacitance of 1.593pF.
**WARN: (IMPCCOPT-1033):	Did not meet the max_capacitance constraint of 0.000pF below the root driver for clock_tree swdclk at (482.500,1915.185), in power domain PD_TOP. Achieved capacitance of 1.530pF.
```

Four instances, one per clock tree. Same root cause as item 1: the
`maximum driven capacitance of 0.000` that IMPCCOPT-4313 announces becomes the
constraint CCOpt then checks against.

**Actual effect.** A constraint of 0.000 pF cannot be met by any physical net,
so CCOpt had no usable capacitance budget below any clock root, and the check
reports a failure on every run regardless of the design. Two costs: the root
driver is never sized against a real limit, and a genuine max-cap violation on
a clock tree would be indistinguishable from this permanent noise.

**Recommended fix.** Fixing item 1 fixes this. Do not "fix" it by setting
`set_max_capacitance` on the clock ports — that masks the missing driver model
rather than supplying it.

---

## 3. TA-1018 — five generated clocks analysed with zero source latency

```
**WARN: (TA-1018):	A source latency path to the generated clock mii_tx_clk through source pin RMII_REF_CLK to target pin u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_rmii_to_mii/mtx_clk in view typical_analysis_view cannot be found. Timing analysis will use 0 ns source latency for the generated clock and will interpret the master clock based on the polarity at the master clock source pin. Additional details for this message are available using 'man TA-1018'.
```

Five distinct generated clocks affected:

| Generated clock | Declared source pin |
| --- | --- |
| `QSPI_SCLK` | `CLK` |
| `QSPI_SCLK_o` | `.../u_qspi_clock_div/QSPI_SCLK_i` |
| `mii_rx_clk` | `RMII_REF_CLK` |
| `mii_tx_clk` | `RMII_REF_CLK` |
| `D2D_TX_CLK_0` | `.../u_wlink/pad_clk_tx` |

**Why this matters here specifically.** This is the same failure class as the
clock-source-latency bug documented at length in `scripts/cts_setup.tcl` — a
latency term that silently resolves to zero and is never questioned because the
tool "only warned". That one cost ~37,000 hold buffers. This one is still live
and is not the same instance: that bug was a missing `-max` side on a
*written-back* latency; this is a source-latency *path* that cannot be traced at
all, on five clocks the earlier fix does not touch.

**Related, same area.** `TCLCMD-1531` reports `create_generated_clock` applied
on a hierarchical pin (`.../u_qspi_clock_div/QSPI_SCLK_i`,
`nanosoc_eth_chiplet_pads_syn.sdc:17-18`), and the already-documented
IMPCCOPT-2248 reports CCOpt relocating those same module-port clock sources to
`g611/Z`. The three messages describe one underlying problem: several generated
clocks are declared on pins that are not real drivers.

**Recommended fix.** Re-declare the affected generated clocks on the driving
*output* pin rather than the module port / input pin, in the source SDC. Then
confirm `TA-1018` no longer appears.

**Not determined from logs.** Whether 0 ns source latency is optimistic or
pessimistic on any given path — that needs a path report per clock, i.e. a
seat. Do not assume it is safe because the design currently closes.

---

## 4. IMPEXT-3518 — signoff extraction silently downgraded

```
**WARN: (IMPEXT-3518):	The lower process node is set (using command 'set_design_mode') but the technology file for TQuantus extraction not specified. Therefore, going for post_route (extract_rc_effort_level low) extraction instead of recommended extractor 'TQuantus' for lower nodes. Use command 'set_analysis_view/update_rc_corner' to specify the technology file for TQuantus extraction to take place.
```

Innovus states the rule itself elsewhere in the same log:

```
	Default value for EffortLevel(extract_rc_effort_level option of the set_db) in post_route extraction mode will be 'medium' if Quantus QRC technology file is specified else 'low'.
```

**Responsible script lines.** `2_pnr_setup.tcl:44` sets
`set_db design_process_node $process_node` (65, from `scripts/config.tcl:3`),
which puts Innovus into lower-node mode. The three `create_rc_corner` blocks in
`scripts/nanosoc_eth_chiplet_pads.mmmc:60-90` then supply **only**
`-cap_table` — `rcworst.captbl` / `rcbest.captbl` / `typical.captbl` — and no
`-qrc_tech_file`.

**Actual effect.** Final post-route parasitics, and therefore the signoff
timing and the SDF, are extracted at `extract_rc_effort_level low` on a 65 nm
design. Not a no-op — it produces numbers — but not the accuracy the tool
considers correct for the node, and nothing in the flow says so.

> ### ⚠ CORRECTED 2026-08-18 — THE QRC FILE **DOES** EXIST; THE EVIDENCE BELOW WAS WRONG
>
> The paragraph below concludes "procurement, not engineering". **That conclusion does not
> follow, because its premise is false.** A Quantus/QRC technology file ships with this
> PDK: `<PDK>/…/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile`, **186,639,161 bytes**
> (178 MiB), readable from this host. A StarRC deck for the same stack is present too
> (`.nxtgrd` + `.itf` under `<PDK>/…/pdk/CCI/online/1p9m_6X1Z1U/`).
>
> **The original search missed it because it looked only under `CMOS/util/`** — the file
> lives under `pdk/Assura/`, which is a directory name that does not contain "qrc".
>
> Quantus itself is also installed and idle: `qrc` under `QUANTUS_21.11.000`, with
> `QRC_Advanced_Analysis` **41 issued / 0 in use** (measured 2026-08-18).
>
> **So this IS fixable by editing a script.** Adding `-qrc_tech_file` to the three
> `create_rc_corner` blocks is a real, local change — not a procurement item. The bullets
> below are retained to show what was searched, and the ARM-tech-tree bullet remains
> correct (that tree genuinely has no QRC directory; it is simply not where the file is).
>
> Corroborated independently by `26-plan-to-submittable-gds.md:60`,
> `25-what-remains-explained.md` item 20, and `40-signoff-sta-plan.md`.

**Recommended fix — and the honest caveat.** ~~This is **not** fixable by editing
a script today. There is no Quantus/QRC technology file installed:~~
*(struck 2026-08-18 — see correction above. The search evidence follows.)*

- nothing matching `*qrc*` or `*.tch` under `$TSMC_65_HOME`;
- `$TSMC_65_HOME/.../PRTF_EDI_65nm_<rev>/` ships `GdsOutMap`, `LefHeader`
  and the `.tlef` only;
- the ARM tech tree the cap tables come from,
  `$PHYS_IP/arm/tsmc/cln65lp/arm_tech/<rev>/`, contains
  `cadence_captable`, `synopsys_tluplus`, `magma_parasitic_rules`, `milkyway`,
  `volcano`, `voltagestorm`, `lef` — no QRC directory.

So this belongs with the `_BE` package request in
`docs/TSMC_BACKEND_PACKAGE_REQUEST.md`: it is procurement, not engineering.
Add `-qrc_tech_file` to the three `create_rc_corner` blocks the day the
collateral lands. Until then, treat post-route timing margins as carrying an
extraction-accuracy allowance.

---

## 5. IMPCPF-980 — power domain never bound to a library

```
**WARN: (IMPCPF-980):	Power domain PD_TOP is not bound to any library. Power domain library binding is through 'update_delay_corner -power_domain' in the MMMC file viewDefinition.tcl. Please make sure that 'update_delay_corner -power_domain PD_TOP' is specified for each delay corner in the MMMC file.
```

**Responsible script lines.** `scripts/nanosoc_eth_chiplet_pads.mmmc` defines
four delay corners (`create_delay_corner` at lines 166, 171, 176, 181) and
contains **zero** `update_delay_corner` commands. Emitted by
`commit_power_intent` (`2_pnr_setup.tcl:42`).

**Actual effect.** The CPF domain-to-library binding does not happen. Benign on
this design — single power domain, `DFT 0`, and the already-documented
IMPMSMV-3501 confirms the CPF carries no power modes or states — so there is
only one library set and nothing to disambiguate. It becomes real the moment a
second domain or a retention/shutdown mode is added.

**Recommended fix.** Add `update_delay_corner -name <corner> -power_domain
PD_TOP` for each of the four corners. Low priority, but it is one line each and
it removes a message that would otherwise be ignored when it starts mattering.

---

## 6. IMPESI-3095 — SI analysis skipped on all top-level input nets

```
**WARN: (IMPESI-3095):	Net: 'SE' has no receivers. SI analysis is not performed.
```

Nine nets: `CLK`, `NRST`, `RMII_CRS_DV`, `RMII_REF_CLK`, `SE`, `SWDCK`,
`SWDIO`, `TEST`, `TL_CLK_RX` — the port-to-pad segments, including all four
clocks.

The same nine appear under IMPCCOPT-2169/2171 ("Cannot extract parasitics for
non-ILM net", "Using estimated values ... as a fallback") and IMPCCOPT-1304 /
IMPCCOPT-2276 ("unexpectedly has no routing", "is not routed").

**Actual effect.** `set_db route_design_with_si_driven 1`
(`scripts/route_setup.tcl:24`) is in force, but has nothing to act on for these
nets. Largely expected for a pad-ring design — the port *is* the pad, so there
is no routable segment and no receiver in the timing sense. Recorded here so
the cluster is not mistaken for a routing failure: it is four separate message
IDs all describing the same benign topology. Note it does mean crosstalk on the
clock inputs is never analysed, which is worth remembering when reading SI
results.

**Recommended fix.** None. Do not chase these.

---

## 7. IMPDC-1629 — delay-calculation fanout limit set to 101

```
**WARN: (IMPDC-1629):	The default delay limit was set to 101. This is less than the default of 1000 and may result in inaccurate delay calculation for nets with a fanout higher than the setting.  If needed, the default delay limit may be adjusted by running the command 'set delaycal_use_default_delay_limit'.
```

Twice per run.

**Not determined from logs.** `grep -rn 'delaycal\|default_delay_limit'
scripts/ ../asic-flows/Cadence/` returns nothing, so no script in this flow
sets it — the 101 is derived by the tool from something else. I could not
establish what, nor whether any net in the design exceeds fanout 101, from the
logs alone. Listed so it is not lost; needs a `report_net -fanout` sweep or
`set delaycal_use_default_delay_limit` echoed on a live session.

---

## 8. IMPOPT-3564 — isolation cells auto-`dont_use`

```
**WARN: (IMPOPT-3564):	The following cells are set dont_use temporarily by the tool because there are no rows defined for their technology site, or they are not placeable in any power domain, or their pins cannot be snapped to the tracks. To avoid this message, review the create_floorplan, msv setting, the library setting or set manually those cells as dont_use.
	Cell ISOHID1, site core.
	Cell ISOHID2, site core.
	Cell ISOHID4, site core.
	Cell ISOHID8, site core.
	Cell ISOLOD1, site core.
	Cell ISOLOD2, site core.
```

**Actual effect.** None. These are multi-voltage isolation cells; this design
has one power domain, so they were never going to be used. Related and equally
benign: `IMPFP-3961` names techSites `corner`, `pad`, `ccore`, `dcore` as
having no standard cells — those are the IO and memory sites, correctly unused
by the core row structure.

**Recommended fix.** Optionally set them `dont_use` explicitly to silence the
message. No functional change.

---

## Investigated and cleared

These four look like silent no-ops and are not. Each was checked to a
conclusion; recorded so the work is not repeated.

**TECHLIB-459 — "Cell definitions from the previously read library will not be
overridden."**

```
**WARN: (TECHLIB-459):	Appending library 'USERLIB_ss_1p08v_1p08v_125c' to the previously read library of the same name and nominal PVT. Cell definitions from the previously read library will not be overridden. (File .../ASIC/romlibs/eth_rom/eth_rom_via_ss_1p08v_1p08v_125c.lib)
```

Both ROM libraries genuinely share a library name — `library(USERLIB_ss_1p08v_1p08v_125c)`
at line 65 of *both* `romlibs/cc_rom/rom_via_ss_1p08v_1p08v_125c.lib` and
`romlibs/eth_rom/eth_rom_via_ss_1p08v_1p08v_125c.lib`. But each declares
exactly one cell, and the names differ: `cell(rom_via)` vs `cell(eth_rom_via)`.
Nothing collides, so nothing is overridden. **Benign — proven.** Worth renaming
the eth ROM's library string anyway to stop the warning recurring.

**IMPOGDS-4004 — "Ignoring duplicate structure ..."**

```
**WARN: (IMPOGDS-4004):	Ignoring duplicate structure 065_LP_M3_v1d1_corner_edge_ARM found in $MEM_BASE/rf_16k//rf_16k.gds2. To avoid the warning message, use the option -uniquifyCellNames to disable cells duplication.
```

This one would change silicon if the ignored copies differed. They do not. All
four memory GDS files in `gds_merge_list` (`config.tcl:198-207`) were parsed and
every structure MD5'd over its full record stream:

| File | Structures | Duplicate names vs earlier files |
| --- | --- | --- |
| `rf_32k.gds2` | 91 | — |
| `rf_16k.gds2` | 86 | 13 |
| `rf_08k.gds2` | 86 | 13 |
| `rf_01k.gds2` | 79 | 11 |

37 duplicate-named structures, **0 with conflicting geometry**. They are shared
ARM memory-compiler leaf cells from the same compiler version
(`065_LP_M3_v1d1_*` edge/strap cells, `co_d09`, `via1_d10`, `via2_d10`).
Dropping the later copies is correct. **Benign — proven.**

**IMPSP-5224 / IMPSP-5534 — obsolete `add_endcaps` options**

```
**WARN: (IMPSP-5224):	Option '-preCap' for command add_endcaps is obsolete and has been replaced by 'setEndCapMode -rightEdge cell_name'. 
**WARN: (IMPSP-5534):	'add_endcaps_left_edge' and 'add_endcaps_right_edge' are using the same endcap cells
```

From `scripts/power_plan.tcl:164`
(`add_endcaps -start_row_cap DCAP4 -end_row_cap DCAP4 -prefix ENDCAP`). Reads
like a classic deprecated-and-ignored pair, but the same log says otherwise:

```
Inserted 2223 pre-endcap <DCAP4> cells (prefix ENDCAP_PD_TOP).
Inserted 2223 post-endcap <DCAP4> cells (prefix ENDCAP_PD_TOP).
```

4,446 endcaps inserted. The obsolete spelling still works, and using DCAP4 on
both edges is deliberate. **Not a no-op — cosmetic only.**

**TCLCMD-1461 — `set_units` skipped**

```
**WARN: (TCLCMD-1461):	Skipped unsupported command: set_units (File ../outputs/nanosoc_eth_chiplet_pads_syn.sdc, Line 9).
```

Innovus discards the SDC's unit declarations, which would corrupt every
numeric constraint in the file if the units differed from the library's. They
do not: `nanosoc_eth_chiplet_pads_syn.sdc:9-10` requests `1000fF` and `1000ps`,
i.e. 1 pF and 1 ns, which is already what the TSMC libraries use and what
`inputs/constraints.sdc:16,18` declares (`ns`, `pF`). **Benign — proven.** Had
Genus emitted `fF`/`ps`, every capacitance and delay constraint in the flow
would have been wrong by 1000x with only this one warning to show for it, so
this is worth re-checking if the synthesis library set ever changes.

---

## Also seen, no action

Deprecation notices with no behavioural change, confirmed by the message text
itself ("still works in this release"): `IMPUDM-33`
(`timing_enable_separate_device_slew_effect_sensitivities`), `IMPDBTCL-321`
(same, plus `route_design_exp_deterministic_multi_thread`), `IMPTCM-77`
(`-routeExpDeterministicMultiThread`), `IMPCCOPT-2332` (`locked_originally`),
`IMPCTE-107`. Worth a cleanup pass before the next tool upgrade, since these
become hard errors at the next major release.

Library-completeness notices, all vendor-side and none actionable here:
`TECHLIB-302` (no function on IO supply/analog cells — analysis-only, correct),
`IMPLF-200` (missing `ANTENNAGATEAREA` on IO pins), `IMPESI-3086` (no noise
models for IO cells), `IMPTS-282` (IO clamp cells not marked
`is_level_shifter`), `IMPLF-119` / `IMPLF-151` (LEF `LAYER`/`viaRule` content
ignored in favour of the tech LEF — expected).

`IMPCCOPT-2406` disables the clock halo on `uPAD_CLK_I`, `uPAD_SWDCK_I`,
`uPAD_TL_CLK_RX`, `uPAD_RMII_REF_CLK`. These are 25 x 135 um IO cells; a
density-derived halo is meaningless on them. No action.

`SDF-802` (negative SETUPHOLD sums adjusted to zero, 20 pins in
`u_tidelink/.../gpiorx_2_link_data_reg_reg[*]/D`) and `SDF-808` (one delay per
pin-pair unless `-recompute_delay_calc` is given) affect
`outputs/${block_name}_pnr.sdf` only, written at `4_pnr_route.tcl:71`. They do
not touch the implemented database. Relevant to anyone doing gate-level
simulation from that SDF; not to the silicon.

---

## What could not be determined from logs alone

- The magnitude of the IMPCCOPT-4313 / IMPCCOPT-1033 error. Needs
  `report_clock_timing` before and after supplying a driver model, on the
  `_cts` snapshot. Needs a licence seat.
- Whether TA-1018's 0 ns source latency is optimistic or pessimistic on any
  specific path. Needs per-clock path reports.
- The origin of the 101 in IMPDC-1629, and whether any net exceeds that fanout.
- Whether `route_eco -target` (added to `scripts/filler.tcl:148` on 2026-08-06,
  still carrying its own "UNVERIFIED" note) executes cleanly. The current run
  had not reached the filler stage when this sweep was taken.
