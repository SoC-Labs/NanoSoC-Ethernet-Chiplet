# Full-design lint — results and remediation plan

**Run 2026-08-08 on `fix/tag-ram-gwen`. Scope: `flist/nanosoc_eth_chiplet_asic.flist`
(the ship configuration), top `nanosoc_eth_chiplet_chip`, 590 files. Arm IP
black-boxed. Two tools: Verilator 4.028 and Cadence HAL 22.03.**

Runner: `verif/lint/full/run.sh` (see its README for the mechanism). This is the
pass `docs/LINT_FINDINGS.md` §5 described and did not attempt; `make lint`
covers three modules, this covers the elaborated chiplet.

## 1. Headline

| | Verilator | HAL |
|---|---|---|
| exit | 0 | 0 |
| raw findings | 1 629 | 36 223 |
| **flow noise** | **0** | **0** (11 682 style suppressed) |
| waived by unit-level policy | 1 142 | — |
| reset/clock-domain (owned by `make cdc`) | — | 20 089 |
| **design findings — authored RTL** | **195** ⚠ | **920** ⚠ |
| design findings — third-party in-tree | 292 | 3 532 |

> **⚠ THESE COUNTS ARE STALE — flagged 2026-08-18, NOT re-measured here.**
> This table is a snapshot of the 2026-08-09 full-chip pass. The lint remediation work
> since then has reduced the authored-RTL count by roughly two orders of magnitude — the
> figure quoted elsewhere tonight is **3** authored DESIGN findings, and the checked-in
> baseline `verif/lint/full/baseline/verilator.json` is now a **single** entry
> (`soc-generated|CMPCONST: 2`, file dated 2026-08-17 18:09), which is not consistent with
> 195 surviving.
>
> **I did not re-run the full-chip lint, so I am not asserting a replacement number.**
> Re-run `verif/lint/full/run.sh` and update this table before quoting any figure from it.
> Treat 195 / 920 as historical. `docs/LINT_FINDINGS.md` was corrected separately and is
> the better starting point.

Zero hard errors in authored RTL from Verilator. Two from HAL (`METAEQ`,
`TERMST`). The report contains no flow-related error or warning: every
remaining line is a statement about the RTL.

## 2. Flow defects found and fixed to get there

The first run of a full-design lint is a test of the *filelist*, not the design.
Six flow defects stood between "run the tool" and "read a report". Each is fixed
in the runner; three want an upstream fix as well.

| # | Defect | Symptom | Fix in the runner | Upstream fix wanted |
|---|---|---|---|---|
| 1 | `eth_cop.v` (OpenCores WISHBONE arbiter) is in the flist but instantiated nowhere. Carries a malformed `synopsys_full_case` meta-comment and an expression inside an `always @(...)` sensitivity list. | 2 hard Verilator parse errors, which abort before the analysis stage. VCS tolerates both. | Excluded, with a proven-unreferenced check. | Drop it from the ethernet-subsystem flist — it is testbench-only. |
| 2 | Eight compiled hard macros (`rf_01k/08k/16k/32k`, `flash_cache_data/tag`, `rom_via`, `eth_rom_via`) have no RTL in the ASIC flist, by design — synthesis binds `.lib`/`.lef`. | 12 `Cannot find file containing module` errors; analysis stops. | Black boxes generated read-only from the vendor models, with a port-coverage assertion. | None — this is correct ASIC practice. The lint flow has to know it. |
| 3 | Five modules defined twice (`cmsdk_apb_slave_mux` from both Corstone-101 and BP210; four `xhb500_*` cells from both XHB500 instances). | VCS keeps the last with `Warning-[OPD]`; Verilator and Xcelium treat a redefinition as an error. | Last-wins dedup, matching VCS, after asserting all five pairs are byte-identical. | None; the dedup makes the bound netlist a property of the *filelist*, not the tool. |
| 4 | `nanosoc_gen` and the CMSDK/Arm RTL omit `` `timescale ``. | HAL died at 5 s with `xmelab: *F,CUMSTS`, before any rule ran. | `-timescale 1ns/1ps -nowarn CUMSTS` + the `lint/timescale.v` preamble — the fix `nanosoc-multicore-system/lint/Makefile` already documents. | — |
| 5 | Verilator 4.028 applies a config file's `lint_off -file` filter at **parse time only**. | 10 findings from Arm IP survived a `lint_off -file` over those exact paths — including a `BLKANDNBLK` **error** inside XHB500 that set the exit status. `UNOPTFLAT`, `COMBDLY` and `BLKANDNBLK` are emitted after the filter. | Real black boxes: 191 Arm IP modules replaced by generated header-only stubs. | — |
| 6 | One stub file holds every module from its source, so its name matches at most one. | 191 self-inflicted `DECLFILENAME` warnings. | `lint_off DECLFILENAME` inside the generated stubs. | — |

### A finding about the waivers themselves

The merged unit-level HAL ruleset (`hal_rules.tcl`, 82 rules from six
`lint/hal.tcl` files) contains `-nocheck MLTDRV` and `-nocheck CLKDMN`, waived
by the SoC's shared ruleset under its "generated-top" and "third-party IP"
headings.

**Those are exactly the rules `make elab-strict` and `make cdc` exist to catch.**
With the merged set applied, `MLTDRV` and `CLKDMN` both report **0** across the
whole chiplet — not because the design is clean, but because the rules are off.
`verif/elab_strict/run.sh` passes no rule file at all, which is why it still
works.

A waiver that is correct for one block is not automatically correct for the
integration. `hal_report.py:NEVER_WAIVE` records the rules that must survive any
merge: `MLTDRV`, `CLKDMN`, `INSYNC`, `SIZMIS`, `GLTASR`, `LATINF`, `NODRIV`,
`UNCONI`, `RSTSCB`, `CMBCDC`.

## 3. Design findings — remediation plan

Ordered by consequence, not by count.

### P1 — real defects, fix before tapeout signoff

| Finding | Where | Evidence | Action |
|---|---|---|---|
| **Two module inputs left unconnected.** `hw_credit_consume_vld` and `hw_credit_consume_val` are `input wire` on `tidelink_fifo` and are omitted at the instance. Unconnected inputs float; synthesis ties them arbitrarily. | `tidelink/src/rtl/fifo/tidelink_fifo_ahb.sv:179` | Verilator `PINMISSING` ×16 at one instance; 14 of the 16 are outputs (harmless), these 2 are inputs. | Tie both explicitly (`1'b0` / `'0`) with a comment, or connect them. TideLink's own gate already promotes `PINMISSING` to an **error** — this instance is outside that gate's module list. |
| **Boot-ROM address width is a lie.** `nanosoc_bootrom_chip_core` declares `word_addr [10:0]` and drives `.TA(11'd0)`, but `rom_via.A` is `[8:0]` — 512 words. The top two bits are silently dropped. Harmless today only because the region happens to supply 9 bits. | `nanosoc-multicore-system/syn/asic/tech_wrappers/tsmc65/nanosoc_bootrom_chip_core.sv:25,32` and `eth_ss_bootrom.sv:25,32` | Verilator `WIDTH` ×4: `Input port connection 'A' expects 9 bits … generates 11 bits`. | Fix `bootrom_gen.py` to emit the address width from the ROM depth instead of a hardcoded 11. Until then the ROM aliases every 512 words if anyone grows the region. |
| **`!==` in synthesizable RTL.** | `nanosoc-multicore-system/src/rtl/dma250/dma250_ahb5_to_ahbl.v:121` | HAL `*E,METAEQ` (an **error**, not a warning). | Replace with a two-valued comparison, or guard it in `// synopsys translate_off`. |
| **Wire unassigned but driving logic.** `puf_rx_tready`. | `tidechart/src/rtl/tidechart_controller.sv` | HAL `*W,UASWIR`. | Drive it or remove the consumer. |
| **32 memory words read but never assigned.** `mem[0]`…`mem[31]` in the DMA-250 context SRAM. | `nanosoc-multicore-system/.../dma250_ctx_ahb5_sram.v` | HAL `*W,UASREG` ×32, plus `LARMEM` (32 768 words, over HAL's 16 384 limit). | Confirm this model is only a simulation stand-in for a compiled macro; if it reaches synthesis it will infer 1 Mib of flops. |
| **`QSPI_BUSY` neither read nor assigned.** | `nanosoc-multicore-system/ahb_qspi/.../top_ahb_qspi.v` | HAL `*W,URAWIR`. | Remove, or wire to the intended source. |

### P2 — width discipline, concentrated in TideChart

Both tools independently converge on the same files. This is the single largest
block of authored findings and the cheapest to clear.

| File | Verilator | HAL |
|---|---|---|
| `tidechart/src/rtl/tidechart_apb_regs.sv` | 122 `WIDTH` | 78 `UELCIT` |
| `tidechart/src/rtl/tidechart_enum_fsm.sv` | 8 `WIDTH` | 18 `UELOPR`, 12 `ULRELE`, 10 `POOBID`, 3 `SHFTNC` |
| `tidechart/src/rtl/tidechart_route_table.sv` | — | 14 `UELOPR`, 10 `POOBID` |
| `tidechart/src/rtl/tidechart_crossbar.sv` | 6 `WIDTH` | 5 `CONSTC` |
| `tidechart/src/rtl/tidechart_controller.sv` | 3 `WIDTH` | 4 `ULRELE`, 3 `UELOPR` |

Three distinct sub-classes, in descending severity:

1. **`ULRELE` — "unequal length operands in relational operator (padding
   produces incorrect result)", 30 in authored RTL.** This one can change
   behaviour. TideLink's own lint README calls out `ULRELE` as the class behind
   a real silicon finding. **Review each individually.**
2. **`UELCIT` — case-item narrower than the selector, 78, all in
   `tidechart_apb_regs.sv`** (selector 7 bits, tags 6). Mechanical: size every
   case tag to the selector. Clears 78 HAL + a large share of the 122 Verilator
   `WIDTH` in one pass.
3. **Indexed part-select index width** ("Bit extraction of `array[N:N]`
   requires N bit index, not 32 bits"). Cosmetic in Verilator, but `POOBID`
   ("index/range selection may be out of bounds", 35) is the same expressions
   seen by HAL and is worth a bounds check.

**Suggested order:** fix `tidechart_apb_regs.sv` case tags first (one file,
largest count, zero risk), then triage the 30 `ULRELE` by hand, then the rest.

### P3 — synthesizability

| Finding | Count | Where | Action |
|---|---|---|---|
| `NAUTOF` — SV function without `automatic`, may be unsynthesizable | 19 | `socdebug_adp_control.v` ×10, `tidechart_enum_fsm.sv` ×3, `apb_qspi_regs.v` ×2 | Add `automatic`. Trivial, and Genus behaviour on a static function is tool-dependent. |
| `TSETGV` — task assigns a module-global variable | 13 | `socdebug_adp_control.v` | Review: this is a hidden multi-driver pattern. |
| `TRGGLT` — variable assigned multiple times with different values in one block | 32 | generated `*_matrix_decode_*.v` | Generated interconnect; confirm the generator's intent, then waive at source. |
| `CASEINCOMPLETE` | 1 authored, 6 third-party | `apb_qspi_regs.v` | Add a `default`. |
| `RTLINI` — `initial` block initialising a register | 104 | third-party (Wlink/Bluespec) | Upstream escalation; note in the vendor-IP register. |

### P4 — flow work to make this a gate

1. **Wire it into CI.** `verif/lint/full/run.sh --verilator-only` is 90 s and
   needs no licence — it belongs in `make check` next to the existing lint.
   The HAL half (~35 min) belongs in the nightly, beside `make cdc`.
2. **Baseline, then gate on the delta.** 195 authored findings is too many to
   gate on today. Record them as a baseline (the pattern
   `ethernet-subsystem-ahb/lint/baseline/` already uses) and fail on anything
   new. Convert to an absolute gate as P1–P3 close.
3. **Split `hal_rules.tcl`.** Keep the merged unit-level set for style, but
   subtract `NEVER_WAIVE` so the integration ruleset cannot silence
   `make elab-strict` and `make cdc`.
4. **Re-run when Verilator ≥ 5.x lands.** 4.028 has no `LATCH` or `MULTIDRIVEN`
   class and cannot model unpacked structs (417 `UNPACKED` suppressed as flow
   noise — that is 417 constructs the tool did not analyse). TideLink's
   `lint/verilator/Makefile` already carries the upgrade note.

## 4. What this pass still does not cover

- **Third-party in-tree RTL is reported, never gated** (292 Verilator + 3 532
  HAL findings). The OpenCores MAC, the Wlink bridges and `local_overrides/` are
  compiled into the chip but are not ours to edit.
- **Arm IP is black-boxed**, so nothing inside the Cortex-M0+, the DAP, XHB500
  or the DMA-250 is analysed — including the `BLKANDNBLK` in XHB500 that flow
  defect #5 surfaced. That is an IP-owner matter, but it is now *known*.
- **CDC/RDC is deferred to `make cdc`.** HAL's 20 089 reset/clock-domain
  findings are computed from an inferred clock model with no SDC; treat them as
  a worklist for the CDC pass, not a verdict.
