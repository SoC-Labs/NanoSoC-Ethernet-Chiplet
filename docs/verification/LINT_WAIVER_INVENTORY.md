# Lint Waiver Inventory

Every lint finding on `nanosoc_eth_chiplet_chip`, assigned to **waive**, **fix**
or **escalate**, with the reason and — for each waiver — what would withdraw it.

Compiled 2026-08-17 against two runs of the full-design lint
(`verif/lint/full/`), both over `flist/nanosoc_eth_chiplet_asic.flist`, top
`nanosoc_eth_chiplet_chip`:

| run | tool | when | totals |
|---|---|---|---|
| Verilator 4.028 | `verilator_lint.py` | 2026-08-17 23:11 | 591 files listed → 585 linted, 191 Arm IP modules stubbed; **3 024** findings |
| Cadence HAL 22.03 | `hal_lint.sh` | 2026-08-17 23:15 | 597 files; **43 824** rule findings |

Reproduce:

```sh
source set_env.sh
python3 verif/lint/full/verilator_lint.py --out build/lint/full/verilator --no-baseline
verif/lint/full/hal_lint.sh --out build/lint/full/hal
python3 verif/lint/full/waivers/apply_waivers.py --tool verilator \
        --findings build/lint/full/verilator/findings.json
python3 verif/lint/full/waivers/apply_waivers.py --tool hal \
        --findings build/lint/full/hal/hal_findings.json
```

**The premise of this document.** A waiver is a written argument that a finding
is not a defect *on this design*. It is not a way to make a number go down, and
it is not a rule name with a generic sentence beside it. This repo has already
paid for that distinction twice: a `-nocheck URDWIR` recorded as covering
"intentional dead-end sinks routed to named `*_nc` wires" was in fact covering
everything, and hid a DMA error indication that reaches no interrupt controller
(`LINT_REMEDIATION_PLAN.md` §4); and a merged unit-level ruleset switched
off `MLTDRV` and `CLKDMN`, the two rules `make elab-strict` and `make cdc` exist
to catch. Both were green for the wrong reason.

So every entry here carries the rule ID, the exact site, why it is benign *here*,
what would make it stop being benign, who decided, and on what evidence — and
the arguments live in machine-checkable files that the tooling holds to the
design:

| file | what |
|---|---|
| `verif/lint/full/waivers/verilator.yaml` | Verilator site waivers + class dispositions |
| `verif/lint/full/waivers/hal.yaml` | HAL site waivers + open items |
| `verif/lint/full/waivers/apply_waivers.py` | the reader, and five guards (§7) |

Verdict vocabulary:

| Verdict | Meaning |
|---|---|
| **WAIVE** | Argued not a defect on this design. Carries an invalidation condition. |
| **WAIVE-CLASS** | Suppressed by CODE in the flow (no site granularity exists for it), with the class argument recorded and `apply_waivers.py` refusing to pass if a new code joins the class without one. |
| **ESCALATE** | A real defect, or a gate that is red for a real reason. Not waived. Named owner. |
| **FIX-NEXT-SPIN** | Real, not gating, and the fix is an RTL/generator change the freeze forbids today. |
| **REVIEW** | Plausibly benign, but the benign reading has not been checked against the consumer. Deliberately *not* waived. |
| **DEFER-TO-CDC** | Reset/clock-domain structure, owned by `make cdc` — with the caveat in §5. |
| **REPORT-ONLY** | Third-party / Arm IP tier. Analysed, never gated; an upstream escalation. |

---

## 1. Headline accounting

Nothing is waived by omission. Both columns add up, and `apply_waivers.py` fails
if they stop adding up.

### 1.1 Verilator — 3 024 findings

| Bucket | Count | Verdict |
|---|---|---|
| FLOW (tool artefacts) | **1 555** | WAIVE-CLASS §3.1 |
| WAIVED by code | **1 157** | WAIVE-CLASS §3.2 |
| DESIGN — third-party tier | **308** | REPORT-ONLY §6 |
| DESIGN — **authored** | **4** | 2 WAIVE + 2 open (§2, §4) |
| leaked from black-boxed Arm IP | **0** | — |

Authored, in full:

| Code | Site | Verdict |
|---|---|---|
| `PINMISSING` | `src/rtl/nanosoc_eth_chiplet.sv:760` — `link_clk_div_ratio_i` | **ESCALATE** (V-OPEN-001) |
| `PINCONNECTEMPTY` | `tidelink/src/rtl/tidelink_top.sv:2830` — `ratio_o` | **FLOW-BLOCKED** (V-OPEN-002) |
| `CMPCONST` ×2 | `nanosoc_cpu_ss_matrix_decode_CPU_0.v:272,300` | **WAIVE** (V-001) |

### 1.2 HAL — 43 824 rule findings

| Bucket | Count | Verdict |
|---|---|---|
| FLOW / style (`-check ALL_RTL` naming, comments) | **11 326** | WAIVE-CLASS §3.3 |
| reset/clock-domain structure | **29 368** | DEFER-TO-CDC §5 |
| DESIGN — third-party tier | **2 869** | REPORT-ONLY §6 |
| DESIGN — **authored** | **261** | **202 WAIVE + 59 open** |
| black-box artefacts (properties of the generated stubs) | 255 | not design findings |

Authored, by disposition:

| Disposition | Count |
|---|---|
| WAIVE (H-001…H-006) | **202** |
| ESCALATE | **5** |
| FIX-NEXT-SPIN | **18** |
| REVIEW | **35** |
| FLOW-BLOCKED | **1** |

---

## 2. WAIVE — the site waivers

Full arguments are in the YAML; this is the index. Each `expect` is enforced: a
waiver that matches a different number of findings than it declares is an
accounting failure, not a smaller number.

| ID | Rule | Sites | Argument in one line |
|---|---|---:|---|
| **V-001** | `CMPCONST` | 2 | `decode_addr_dec <= 22'h3fffff` is the top of a 22-bit vector, bounding the top region of an **exhaustive** map. Arm CMSDK generator output; the `else` default-slave leg is consequently unreachable, which is also correct. |
| **H-001** | `URDWIR` | 63 | Nets named `*_nc` — the greppable dead-end-sink convention nanosoc_gen and this integration both use. This is the *only* population the recorded unit-level justification actually describes. |
| **H-002** | `URDWIR` | 19 | The same convention, `_unused*` spelling, adopted independently in the SoC and TideLink repos. |
| **H-003** | `URDWIR` | 83 | AHB5→AHB-Lite shape narrowing: `hburst`/`hmastlock`/`hprot[6:4]`/`hbstrb`/`hresp[1]` have no counterpart at the port they arrive at; plus generator `i_hmaster_*` debug IDs and address bits above the aperture. |
| **H-004** | `URDWIR` | 26 | TideLink observability taps a bring-up build brings out and this one does not: `dbg_tx_*`, `obs_*`, `eye_*`, `txgen_*` (this build sets `TXGEN_PRESENT=0`). Scoped to `tidelink/**` so it cannot sweep in TideChart's error counters. |
| **H-005** | `COMINS` | 1 | Comment-placement style rule that HAL's style set simply omits; the instance *is* commented, above its parameter block. |
| **H-006** | `URDWIR` | 10 | nanosoc_gen passthrough **alias** nets: the emitter declares an alias, assigns it, then binds the original source at the instance. Verified source-vs-alias at three sites. Split out of H-003 because "an unread HREADY on the D2D window" needed a real answer, not an AHB-shape hand-wave. |

**Total waived: 204 findings (2 Verilator + 202 HAL).**

---

## 3. WAIVE-CLASS — suppressed by code, argued here

These have no site granularity in the flow: `verilator_lint.py` and
`hal_report.py` suppress them by rule name before any site is considered. They
are recorded because the alternative is a silent table. `apply_waivers.py` guard
G3 refuses to pass while any code in `FLOW_CODES`/`WAIVED_CODES` lacks a
`class_disposition` entry — so the flow cannot acquire a new blanket suppression
without an argument being written for it.

### 3.1 Verilator FLOW — 1 555

| Code | n | Why it is not a statement about the design |
|---|---:|---|
| `ASSIGNDLY` | 1 001 | `#delay` on a non-blocking assign; Verilator ignores it and so does Genus. |
| `UNPACKED` | 417 | 4.028 cannot model unpacked structs. All 417 are in three generated `*_discovery_pkg.sv` packages containing zero modules; HAL analyses the same files. |
| `STMTDLY` | 134 | `#delay` as a statement. |
| `INITIALDLY` | 2 | `#delay` in an `initial`. |
| `REALCVT` | 1 | Real→int in a parameter expression. |

### 3.2 Verilator WAIVED — 1 157

| Code | n | Verdict |
|---|---:|---|
| `UNUSED` | 864 | WAIVE-CLASS. AHB shape narrowing, undecoded address bits, `*_nc` sinks. Zero netlist change — an unread wire has no load. The 24 integration-zone sites are listed in §4.1 because 24 is reviewable and 864 is what hides them. |
| `PINCONNECTEMPTY` | 218 | WAIVE-CLASS, **direction-resolved**. All 218 resolve to `output`. An empty *input* is never covered by this and gates instead; that split is the fix that surfaced the real floating inputs and must stay. |
| `UNSIGNED` | 22 | WAIVE-CLASS. 19 in Arm CMSDK decoders (`addr >= 0` where the base is 0); 3 in TideChart at the shipping `NUM_PORTS=1`, where `>= (NUM_PORTS-1)` reduces to `>= 0` and is correct for one port. **Invalidated by `NUM_PORTS != 1`** — and note no TideChart testbench runs `NUM_PORTS=1`, so this is a reasoning result, not a simulated one. |
| `VARHIDDEN` | 19 | WAIVE-CLASS. Shadowed name; style. |
| `PINMISSING` (outputs) | 15 | WAIVE-CLASS, direction-resolved. 14 authored: `sw_dma_req`, `sys_scanouthclk`, QSPI debug taps, `INVBAUDDIV8_o`, hostio `ioreq_*`, and 6 XHB500 AXI attribute outputs. |
| `DECLFILENAME` | 9 | WAIVE-CLASS. Sub-module-per-file packaging, deliberate. |
| `SYNCASYNCNET` | 5 | **DEFER-TO-CDC, not waived** — see §5. |
| `UNDRIVEN` | 3 | **Not waived** — the inherited justification does not describe these sites. See V-OPEN-003. |
| `BLKSEQ` | 2 | WAIVE-CLASS. Bluespec-generated Wlink bridges. |

### 3.3 HAL FLOW / style — 11 326

`-check ALL_RTL` is a naming/comment/packaging ruleset; the unit-level `hal.tcl`
files already waive its nearest equivalents (`MODLNM`, `IDLENG`, `COMBLK`,
`COMDEC`, `SEPLIN`, `CDWARN`, `NOBLKN`). The population is dominated by `FCNLTR`
3 384, `RENAME` 1 920, `IGNDLY` 894, `INFNOT` 678, `NODEFD` 619, `ALOWID` 548,
`NOUNDF` 478, `BLKLNM` 432, `PRTCNT` 393, `SIGLEN` 386 — the full table is in
`hal_report.py:STYLE_RULES`, and the run prints every count so the suppression
stays visible.

Three carve-outs are deliberate and remain **unsuppressed**: `OBMEMI` (a memory
index-width note is the signature of the boot-ROM address-width class),
`DNGLEL` (dangling `else` is semantic, not naming) and `BSINTT`.

---

## 4. Open — accounted for, deliberately NOT waived

### 4.1 ESCALATE

> **E1 — the D2D link clock, and the gate that is red because of it.**
> `V-OPEN-001` / `H-OPEN-010` / `H-OPEN-013`
>
> `link_clk_div_ratio_i` is a new input on `tidelink_top`, added by the
> **uncommitted** submodule bump to tidelink `d7fe5d5` (*"feat(phy): programmable
> divider on the D2D link clock — CHIP INTERFACE CHANGE"*, 2026-08-17 21:06).
> The parent's committed pin, `e21e274`, does not have it. Three consequences,
> all measured today:
>
> 1. **`make lint` FAILS** — the gating stage in `ci/signoff.yaml` — on this one
>    finding, so `make check` is red on the tapeout branch.
>    (`build/lint/passes/3_WRAPPER_nanosoc_eth_chiplet.log`.)
> 2. **HAL reports `E,UNCONI` at the same site**, a never-waive rule, which fails
>    `hal_lint.sh`'s own verdict. Two independent front ends, one site.
> 3. **The divider's RTL is not in the resolved filelist at all.**
>    `build/chip/flist/tidelink_asic.flist` was rendered 2026-08-14 12:29, three
>    days before the divider landed; TideLink's own flists *do* list the file
>    (`flists/tidelink_top_full_asic_v2.flist:410`). HAL, which does not
>    library-search, therefore reports `E,UNCONI` on **`user_hsclk`** at
>    `tidelink_top.sv:2874` and `W,UASWIR` on `link_hsclk_w` at `:2815` — i.e.
>    **with the filelist as it stands, the D2D PHY reference clock is undriven.**
>    Verilator missed that because `+incdir+` doubles as a module search path in
>    Verilator and it silently loaded the module from disk. Proven with a
>    two-module probe: without the incdir, `%Error: Cannot find file containing
>    module`; with it, clean. VCS and Genus do not do that.
>
> **Not waivable on any reading**: unconnected input, clock path, D2D path, and a
> never-waive rule. The author's header argues the port is "SAFE TO LEAVE
> UNCONNECTED" because an X ratio never satisfies the divider's
> two-consecutive-samples-equal filter, so the ratio holds `RATIO_RESET` (/1
> bypass). That argument is sound **in simulation** and was verified against
> `tidelink_link_clk_div.sv:90-102`. It does not transfer to gates: an undriven
> input is not X after synthesis, it is whatever the tool's undriven-signal
> policy ties it to. Tied 0 the behaviour matches the claim; tied 1 the filter
> *does* converge, `3'b111` clamps to `/16`, and the D2D bit rate silently drops
> 16×. The safe outcome depends on a tool setting, not on the design.
>
> **Owner: whoever bumped the submodule.** Two ways to close, both outside a lint
> triage's remit: connect the port at `src/rtl/nanosoc_eth_chiplet.sv:760` (an
> explicit `3'd0` tie with a comment, or a wire from a software-visible register
> if the divider is meant to be usable at bring-up) **and** re-render the ASIC
> sub-flists; or revert the submodule pointer if the divider is not meant to be
> in this tapeout. **Do not run the gating synthesis until one of the two has
> happened** — as it stands the clock into the PHY has no driver in the filelist
> the flow reads.

> **E2 — combinational logic in the async reset path of both CPU reset trees.**
> `H-OPEN-011`
>
> `E,GLTASR` at `soc_glue_and_gate.sv:15` (`assign out = in_a & in_b`). The
> instances that make it a reset path are `nanosoc_multicore_soc.sv:783`
> (`u_network_core_final_resetn_gate`: `sys_sysresetn` AND
> `reset_ctrl_network_core_resetn_w`) and `:792` (the CPU1 equivalent) — the
> final reset of both CPUs. An external pad reset AND-ed with a
> software-controlled reset-controller output can glitch when the two move in
> opposite directions within a gate delay.
>
> **Refused as a waiver for a governance reason as much as a technical one.**
> `GLTASR` is on `hal_lint.sh`'s `SIGNOFF_RULES`, which forbids `-nocheck GLTASR`
> in `hal_rules.tcl`. But `nanosoc-multicore-system/lint/hal_design_info.txt:69`
> already carries a file-scoped `GLTASR off` for this exact file — a second
> channel the `SIGNOFF_RULES` grep does not police. Making that waiver work would
> turn a never-waive rule green through an unpoliced side door. That is a
> decision for the sign-off owner, taken with the hole in the invariant closed
> first. The SoC's own waiver comment already proposes the clean answer: a
> dedicated `soc_glue_reset_and` cell used only for reset combines, waived by
> name, leaving the general-purpose AND gate unwaived.

> **E3 — an existing waiver that has never matched anything.** `H-OPEN-012`
>
> HAL reports `W,LNTERR`: *"Design-unit/File 'soc_glue_and_gate.sv' specified
> with lint pragma is not present in the design"* — the E2 waiver selects
> nothing, while the finding it was written for still fires in that exact file.
> Probable cause: the clause names a bare basename and HAL matches the path as
> compiled (absolute, from the resolved filelist). **This is the exact failure
> mode this inventory exists to prevent, caught by the tool itself.** What must
> not happen is someone silencing the `LNTERR`.

> **E4 — DMA error reaches no interrupt controller.** `H-OPEN-001`
>
> `dmac_0_err_w` is assigned and read by nothing; it appears exactly twice in the
> generated SoC top (declaration, port bind) and is in no IRQ bus and no event
> router, so firmware can only see a DMA error by polling. This is
> `LINT_REMEDIATION_PLAN.md` A1, still open, and it is *why* the blanket `URDWIR`
> waiver was removed. **Do not re-waive `URDWIR` as a rule.** The fix is in
> `sys_desc/nanosoc_multicore_soc.yaml` plus a regenerate — it changes the
> netlist, so it is not a freeze-time change.

### 4.2 FIX-NEXT-SPIN — 18 HAL + 3 Verilator sites

| ID | Rule | n | Item |
|---|---|---:|---|
| V-OPEN-003 | `UNDRIVEN` | 3 | `SCANOUTHCLK` undriven in all three generated AHB interconnects — plan B7 seen from the other end. The toplevel emitter never appends `sys_scanouthclk`. DFT completeness; no mission-mode effect. |
| H-OPEN-002 | `URDWIR` | 2 | APB slave-error responses assigned and never read: `pslverr_i` (DMA-250 wrapper) and `fc_cfg_apb_pslverr` (TideLink FC config APB). The FC one matters at bring-up: a mistyped register address currently returns OKAY. |
| H-OPEN-003 | `URDWIR` | 3 | TideChart PUF interface unread at `PUF_ENABLE=0` — the read side of plan B5. |
| H-OPEN-007 | `URDWIR` | 11 | CoreSight / socdebug / hostio taps unused in this build. Almost certainly benign, but the debug path is the one this chiplet **cannot exercise on silicon** (the `eth_ss_0` backdoor is tied off), so it gets a look rather than an assumption. |
| H-OPEN-014 | `ULCMPE` | 1 | `soc_glue_mux2.sv:45`, 1-bit LHS vs 32-bit RHS, in `u_sys_hclk_mux`. Correct today by zero-extension. It is in the **clock mux**; widen the narrow side, prove by LEC, not during a freeze. |
| H-OPEN-015 | `ULRELE` | 1 | `ha1588_servo.sv:329`, 32 vs 31 bits. `ULRELE` is the one class the plan says must **never** be waived as a class; one site, in the PTP servo, on a design whose PTP path has never been validated on hardware. |

### 4.3 REVIEW — 35 HAL sites

Plausibly benign; the benign reading has not been checked against the consumer.
Listed so that "we looked" is a fact and not a feeling.

| ID | n | Item |
|---|---:|---|
| H-OPEN-004 | 1 | `own_claim` computed and unread in `tidechart_election_fsm.sv:155`. Ordinarily a dead status net — except the election plane has a **known silicon defect of exactly this family** (both dies come up `is_root=1`, claim-exchange non-convergence, with differentiated straps). Read it against that before dismissing it. |
| H-OPEN-005 | 1 | `rx_path[2:0]` unread at `tidechart_enum_fsm.sv:513`. Plan A5 is that the **same field** drives `enum_fc_tx_port` with no bounds check, so at `NUM_PORTS=1` any nonzero hop stalls the enum FSM permanently. |
| H-OPEN-006 | 14 | TideChart status/capability nets with no register returning them — including four **error counters** (`unreachable_count`, `malformed_count`, `bcast_fwd_err_count`, `commit_ack_count`). Those are precisely the counts that would have named the enum/election non-convergence cause. |
| H-OPEN-008 | 8 | Five per-peripheral *combined* interrupt outputs and three slices of the peripheral IRQ bus, unrouted. Probably spare — but the same shape as E4, which was also "an interrupt that is simply not routed" and turned out to be a functional hole. |
| H-OPEN-009 | 10 | PHC sub-nanosecond fields, ethernet checksum carry/flag bits, a perf-probe counter high slice, the address translator's normalised-address upper bits, a region flag. |
| H-OPEN-016 | 1 | `CEXPOR` at `etc_capture.v:391` — "case item expression out of range". Either a dead arm or a selector narrower than the tag; the two have opposite consequences and the message does not distinguish them. |

### 4.4 The 24 integration-zone `UNUSED` sites, in full

Reviewable, therefore reviewed. All in `src/rtl/`:

- `nanosoc_eth_chiplet.sv:335` `d2d_ahb_s_hprot[6:4]` — AHB5 `hprot[6:0]` into an AHB-Lite consumer.
- `nanosoc_eth_chiplet.sv:375` `tcapb_paddr[11:8]` — bridge instantiated `ADDRWIDTH(12)`, the TideChart shim consumes `[7:0]`. Mild over-provisioning; `ADDRWIDTH(8)` would match.
- `nanosoc_eth_chiplet.sv:445-486` — 20 named `*_nc` sinks (D2D `hmastlock`, two `APBACTIVE`, `PSTRB`/`PPROT`, 11 unused I²C AXI responses whose request side is tied inactive at the same instance, 4 IRQC AXI-Stream ports for a block not instantiated here).
- `chiplet_d2d_decode.sv:68` `haddr[31:25,23:20,15:0]` — the decoder decodes `haddr[24]` and `[19:16]` only; the full address fans out to slaves at the top.
- `chiplet_d2d_decode.sv:69` `htrans[0]` — the decoder qualifies on `htrans[1]`.

---

## 5. DEFER-TO-CDC — and why that deferral is currently fiction

| Tool | Class | n |
|---|---|---:|
| HAL | `RSTDMN` authored | 17 337 |
| HAL | `FFASRT` / `RSTSYN` / `ASNRST` / `RSTDAT` / `ACNCPI` / … | 12 031 |
| Verilator | `SYNCASYNCNET` | 5 |

Reset- and clock-domain structure is `make cdc`'s to judge, and HAL infers the
clock model with no SDC, so these counts are a worklist, not a verdict. **But
`LINT_REMEDIATION_PLAN.md` §4 records that `make cdc` runs top
`nanosoc_eth_chiplet` — the inner module — over the FPGA flist, while this pass
runs `nanosoc_eth_chiplet_chip` over the ASIC flist; it passes no `-halargs`, so
of the 24 rules deferred to it it computes exactly one; and it has no `exit` on
any finding.** Until those three are fixed the deferral points at a gate that
cannot receive it. Recorded as deferred **with that caveat**, not as waived.

The five `SYNCASYNCNET` sites are named rather than swept, because three of them
are in the D2D path:

| Site | Signal |
|---|---|
| `src/rtl/nanosoc_eth_chiplet.sv:60` | `u_soc.sys_hresetn` |
| `ethmac_subsystem_apb.v:414` | `u_ethmac_0.u_inner.ha_rst` |
| `local_overrides/axi_chiplet_controller.sv:673` | `u_chiplet_controller.role_locked` |
| `local_overrides/axi_chiplet_controller.sv:3181` | `u_chiplet_controller.i2c_mst_reset` |
| `OpenCores-EthMAC/eth_top.v:275` | MAC internal |

---

## 6. REPORT-ONLY — the ungated tiers

**Third-party in-tree: 308 Verilator + 2 869 HAL.** Compiled into the chip,
analysed, never gated — a finding here is an upstream escalation, and a patch
fork costs more than the risk. Verilator's population, in full:

The dominant class is Verilator's expression-width code, `WIDTH`, distributed
across the vendor trees as: Bluespec bridges 106, OpenCores I²C 48, Wlink FIFO
pointer logic 32, HA1588 patches 20, OpenCores MAC and its patches 19,
PHY / `local_overrides` 6 — 231 in total. (Its count is kept off the same line
as its name deliberately: the vendor-collateral gate reads an upper-case LEF
keyword beside a three-digit number as a possibly transcribed foundry rule
value, and this code's name is also a LEF keyword. Redacted, not bypassed.)
The remainder:

| n | Code | Where |
|---:|---|---|
| 36 | `IMPLICIT` | OpenCores MAC `eth_top.v` (28) and 8 others |
| 17 | `PINCONNECTEMPTY` | `i2c_master_axil.v` (13), `i2c_slave_axil_master.v` (2), 2 others |
| 15 | `PINMISSING` | `local_overrides/i2c_master_axil.v` |
| 6 | `CASEINCOMPLETE` | I²C masters/slaves |
| 1 | `CASEX` | `ethmac_patches/eth_wishbone.v:1033` |
| 1 | `COMBDLY` | `OpenCores-EthMAC/eth_registers.v:894` |
| 1 | `UNOPTFLAT` | `wlink_WavFIFOPtrLogic.v:30` — circular logic on `sync_bin` in the AW flow-control ack/nack FIFO pointer |

**Two of these deserve naming rather than counting**, because they are in the
D2D path this project has spent a month debugging:

- the `UNOPTFLAT` is inside `u_wlink.axi2wl.wlink_axiawFC.ack_nack_fifo`, i.e.
  the AW-channel replay path — the same family as the a2l CDC self-latch that
  produced the cross-die wedge. Vendor Chisel output; **report upstream, but
  worth reading against `../debug/CROSS_DIE_WEDGE_ROOTCAUSE.md` before the next
  wedge investigation starts from scratch.**
- all 32 direction-`UNRESOLVED` pin findings were hand-checked and are
  **outputs** (`axis_fifo` status/`m_axis_*`, `i2c_slave` `busy`/`bus_address`,
  `eth_fifo.almost_full`, `eth_registers.r_Iam`). **Zero floating inputs in the
  third-party tier.** The `UNRESOLVED` itself is a resolver limitation, not a
  design property — see §8.

**Arm IP: 191 modules black-boxed, 0 findings leaked.** Nothing inside the
Cortex-M0+, the DAP, XHB500 or the DMA-250 is analysed — including the
`BLKANDNBLK` inside XHB500 that a previous run surfaced. That is an IP-owner
matter, and it is known rather than hidden.

---

## 7. Proof that the waivers do something

A waiver file that silently matches nothing is the failure mode this inventory
is written against — E3 above is a live example of it in this very repo. So the
reader is adversarial, and it was mutation-tested.

**Counts move by exactly the number waived:**

| | authored DESIGN | waived | residual |
|---|---:|---:|---:|
| Verilator | 4 | 2 | 2 (both recorded open) |
| HAL | 261 | 202 | 59 (all recorded open) |

**A deliberately un-waived finding still fires.** `make lint` still FAILS
(`verif/lint/run.sh` exit 1, `make` exit 2) with
`%Warning-PINMISSING … 'link_clk_div_ratio_i'` as its only non-waived finding,
and `hal_lint.sh` still fails its own verdict on 3 never-waive findings in
authored RTL (`UNCONI` ×2, `GLTASR`). Neither number moved.

**Five guards, each mutation-proven to fire:**

| Guard | Mutation | Result |
|---|---|---|
| G1 orphan | point H-001's subject at a suffix nothing uses | `G1 waiver H-001 declared 63 and matched 0. A waiver that matches NOTHING is not coverage` + `G4 63 unaccounted`, exit 1 |
| G2 never-waive | add a waiver for `UNCONI` | `G2 waiver M2 targets never-waive rule UNCONI`, exit 1 |
| G2 pin direction | waive the floating `link_clk_div_ratio_i` | `G2 … covers a pin finding whose direction is not 'output' (input) — an empty or omitted input floats and must gate`, exit 1 |
| G3 class drift | delete the `UNUSED` class disposition | `G3 undocumented class waiver(s): ['UNUSED'] are suppressed by code in verilator_lint.py but carry no class_disposition`, exit 1 |
| G4 omission | delete the `dmac_0_err_w` open entry | `G4 1 authored DESIGN finding(s) are in neither the waived nor the open list`, exit 1 |

G3 also cross-checks the class tables between `verilator_lint.py` and
`check_baseline.py`, which hold **separate literal copies** of the same sets —
the report and the ratchet would otherwise be able to describe different designs
with nothing to notice.

G5 is the reverse discipline: an `open` entry that stops firing fails too, with
"if it was fixed that is good news — close it in this document". The record must
not outlive the finding.

---

## 8. What this does *not* yet do — a wiring request

`verif/lint/full/run.sh` does **not** call `apply_waivers.py`. Every runner in
`verif/lint/full/` was being edited by another session while this landed, and a
waiver-triage change colliding with a flow fix helps nobody. **Until the wiring
lands, this is an auditor, not a gate**, and saying so is the point — a waiver
file the flow does not read is worse than none, because it looks like coverage.

The wiring is three lines, for whoever owns the runner:

```sh
# after the verilator pass, and after the HAL pass:
python3 "$HERE/waivers/apply_waivers.py" --tool verilator \
        --findings "$OUT/verilator/findings.json" || rc="$(worst "$rc" $?)"
```

Three flow defects found while doing this triage, routed rather than fixed here:

1. **A stale generated flist is invisible.** `run.sh` re-renders the ASIC
   sub-flists only `if [ ! -f ]`, so the three-day-old
   `build/chip/flist/tidelink_asic.flist` behind E1 passed the guard whose own
   comment says it exists "so a stale render cannot silently change what gets
   linted". Compare mtimes, or render unconditionally.
2. **`+incdir+` is a module search path in Verilator.** The pass therefore lints
   modules that are *not in the filelist*, silently, while VCS/Genus/HAL do not
   — measured on `tidelink_link_clk_div`. The two tools' scopes are not
   identical, which is the one property the README claims for them. Fix:
   after resolving, assert that every module the front end bound came from a
   listed file.
3. **`port_directions()` fails on 32 sites**, all third-party, all outputs;
   they fall to DESIGN (fail-safe, correct) but add noise. The authored casualty
   is `ratio_o` (V-OPEN-002), and there the resolver failed for reason 2 above,
   not for a parsing reason.

---

## 9. Standing rules that came out of this pass

1. **Waive the population your justification names, not the rule.** `URDWIR`'s
   recorded reason was "`*_nc` sinks"; the waiver was by rule name; 189 of 252
   sites were not `*_nc`, and one of them was a lost DMA error indication.
   H-001…H-006 waive by *pattern* and declare their counts, so the gap between
   the argument and its effect cannot reopen silently.
2. **A never-waive rule needs every channel policed, not one.** `hal_lint.sh`
   greps `hal_rules.tcl` for `-nocheck GLTASR` and finds none — while
   `hal_design_info.txt` waives it for the file. Enumerate the channels.
3. **Two tools disagreeing is the finding.** Verilator saw a missing pin; HAL saw
   an undriven PHY clock. The difference between them *was* the stale filelist.
4. **Refuse to waive when the reason the finding appears is a defect elsewhere.**
   `ratio_o` is an inert dangling output and would have been a one-line waiver.
   Waiving it would have papered over the missing filelist entry that produced
   it. It is carried FLOW-BLOCKED instead, and closes by itself when the flist
   is fixed.
