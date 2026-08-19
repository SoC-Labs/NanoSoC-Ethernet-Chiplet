# Lint remediation plan — fix, waive, and prove

**Basis: the full-design lint of 2026-08-08 (`verif/lint/full/`), plus a six-way
independent triage in which every finding was opened in the RTL. Supersedes the
plan section of `FULL_LINT_FINDINGS.md`, which contained three errors — see
§0.**

---

## 0. Corrections to the first-cut plan

Three P1 items in `FULL_LINT_FINDINGS.md` were wrong. Two would have caused
harm if actioned. Recorded here because the reasoning matters more than the
entries.

| Was | Actually | Evidence |
|---|---|---|
| **"Fix `bootrom_gen.py` to emit the address width from the ROM depth instead of a hardcoded 11."** | The generator **does not hardcode 11**. It renders `word_address_width` from its `-a` argument, and every caller passes `-a 9`. Its output is already 9 bits. The `11` exists only in two **hand-maintained** ASIC tech wrappers that inherited a stale header comment. Editing the generator fixes nothing. | `bootrom_gen.py:246-252`; `ASIC/common.mk`; both bootloader `CMakeLists.txt` |
| **"`!==` in synthesizable RTL — replace with a two-valued comparison."** | It is **not** synthesizable RTL. It sits inside `` `ifndef SYNTHESIS `` (lines 82–127) and Genus predefines `SYNTHESIS`. **The proposed fix would be a regression:** `!==` is load-bearing in an X-detector; with `!=` an X operand yields X, `if (X)` is false, and the assertion silently stops firing. | `dma250_ahb5_to_ahbl.v:82,121,127`; `-define SYNTHESIS` in the dofile Genus writes; zero matching cells in the shipped gate netlist |
| **"32 768-word DMA context SRAM — would infer ~1 Mib of flops."** | Off by 1024×. HAL's `LARMEM` number is **bits × width**, not words. True size is 32 words × 32 b = **1 024 flops**, ~0.3 % of core area. Calibrated against a second `LARMEM` and confirmed in the shipped netlist (1 024 `SDFQD0` cells). | `DMAC_NUM_VCH=2` → `NWORDS=32`; `u_ctx_sram_mem[0..31]` in the gate netlist |

A fourth, from the TideLink triage: the `tidelink_fifo_ahb.sv:179` floating
inputs are real but **not in the silicon hierarchy** — the module is compiled by
the ASIC flist and instantiated only by a cocotb testbench. Testbench hygiene,
not a tapeout item.

**The lesson worth keeping:** every one of these came from reading a lint message
without opening the surrounding code. A lint finding is a hypothesis.

---

## 1. Flow defects fixed first, because they changed the numbers

Four defects in the lint flow itself, all found by adversarial review of my own
buckets. All four are fixed; the report below is post-fix.

| Defect | Consequence | Fix |
|---|---|---|
| Lint did not define `SYNTHESIS`; Genus does | Lint analysed simulation-only code that never reaches synthesis. Produced the phantom `METAEQ` "error" above | `SYNTH_DEFINES` in `verilator_lint.py`. **Deliberately not `POWER_PINS`** — it guards only `inout VDD/VSS` plumbing, no logic, and defining it manufactures 20 false floating-input findings on the hard-macro black boxes Genus never reads as RTL |
| `hal_rules.tcl` silenced **9** sign-off rules, including `MLTDRV` and `CLKDMN` | The merged unit-level ruleset switched off the exact rules `make elab-strict` and `make cdc` exist to catch. Mutation-proven on two engines: `MLTDRV` 1→0, `CLKDMN` 1→0 | Removed all 9; added a sign-off invariant header. 82 → 73 rules |
| FLOW codes were passed as `-Wno-<CODE>` | Verilator never emitted them, so the report's own FLOW count was **structurally zero** while the README promised the suppression stayed visible | Classify in Python, like the WAIVED bucket. FLOW now reports **1 555** |
| `PINCONNECTEMPTY` was waived by code | `PINCONNECTEMPTY` (`.pin()`) and `PINMISSING` (pin omitted) are the same defect written two ways, and neither message states direction. Gating one and blanket-waiving the other is indefensible | Resolve the pin's direction from the module port table; waive outputs, gate inputs/inouts. **252 dangling outputs correctly waived; 3 floating inputs correctly surfaced** |

Net effect on the authored report: **195 → 168** findings, and the three that
now gate are all genuine floating inputs.

> **One correction to the write-up of the `MLTDRV` finding.** It is tempting to
> say the waiver hid a bug. It did not: `make elab-strict` runs no rule file and
> reports `MLTDRV=0`, so the chiplet genuinely is multi-driver-clean today. The
> waiver removed the **detector**, not a known defect. Say it that way — a
> reviewer will check.

---

## 2. What is worth fixing

**23 distinct code changes across 6 areas.** Nothing here is a tapeout blocker in
silicon; two items are functional holes that should not ship.

### Tier A — functional holes (fix before sign-off)

| # | Finding | Where | Why it matters | Test |
|---|---|---|---|---|
| **A1** | **DMA error reaches no interrupt controller.** `dmac_0_err_w` occurs exactly twice in the SoC top: its declaration and its port bind. It is in no IRQ bus and no event router. Firmware can only see a DMA error by polling. (A routed IRQ such as `spi_irq_w` occurs 4 times.) | `sys_desc/nanosoc_multicore_soc.yaml` | Silent loss of an error indication. **Produced no lint line at all** — see §4 | Regenerate; assert `dmac_0_err_w` reaches an IRQ bus; DMA-250 error-injection test |
| **A2** | **PTP servo lock can never latch.** `$unsigned(offset_r)` on a `logic signed [31:0]` is not absolute value — a negative offset becomes ≥2³¹ and always fails the threshold, clearing `servo_locked`. Line 586 of the same file does it correctly with a bidirectional `$signed()` compare | `tidelink_ptp_servo.sv:637` | Breaks the only lock indicator readable during chiplet bring-up. Status-only in the shipped config (`PHC_LOCK_GATE_EN=0`), a live hang if that is ever set | New: small **negative** offset, ≥`LOCK_COUNT` iterations, assert `servo_locked`. 0 before, 1 after |
| **A3** | **ROM compiler spec requests 2 048 words; the delivered macro is 512.** Confirmed: `.spec words = 2048`, `.memlib NumberOfWords : 512` | `ASIC/tech_wrappers/tsmc65/{eth_rom,nanosoc_rom}.spec:31` | Armed to detonate on the next `make tsmc_65_romlibs`: a 2 048-word macro whose LEF/GDS no longer match `floorplan.tcl`'s `place_macro` — **and the 11-bit RTL wrapper would then connect cleanly, so nothing would complain** | Regenerate; diff `.memlib` words and `.lef` bbox against the committed geometry |
| **A4** | **No preflight guard** that spec words == boot-image lines | `ASIC/common.mk`, `romlibs-preflight` | This is the guard that would have caught A3. It checks the code file exists, never its length | Set `words = 2048`, confirm preflight fails |
| **A5** | **Unvalidated peer-supplied port index.** `enum_fc_tx_port` is driven from the received packet's path field with no bounds check; at `NUM_PORTS=1` any nonzero value makes both selects out of range and no port asserts valid — the enum FSM waits forever on a handshake that cannot complete | `tidechart_crossbar.sv:239-241`, `tidechart_enum_fsm.sv` | **Silent permanent stall of the enum plane from one corrupted FC beat.** This link has a documented data-drop and framing history, so a corrupted path field is not hypothetical | New: drive a `DISCOVER_REQ` with an out-of-range hop; assert the FSM returns to idle |

### Tier B — latent, fix in this cycle

| # | Finding | Where | Note |
|---|---|---|---|
| B1 | Unguarded array read. The `TC_NEIGHBOUR_*` **write** path is bounds-checked; the **read** path is not. X in RTL sim, aliasing in gates, on a CPU-readable register | `tidechart_apb_regs.sv:597` | Mirror the write guard at line 500 |
| B2 | `NUM_PORTS[PORT_W-1:0]` truncates to 0 at `NUM_PORTS=8`, which the register map's `TC_NEIGHBOUR_0..7` puts inside the design space. At 8, enumeration discovers nothing. The file contradicts itself — line 449 already uses the correct `[PORT_W:0]` | 6 sites across `tidechart_apb_regs.sv`, `tidechart_enum_fsm.sv` | One shared `localparam [PORT_W:0] NUM_PORTS_V` per module |
| B3 | Boot ROM wrapper declares `word_addr[10:0]` and `TA(11'd0)` into a 9-bit macro port | `syn/asic/tech_wrappers/tsmc65/{nanosoc_bootrom_chip_core,eth_ss_bootrom}.sv:18,32` | Provably zero netlist delta — the truncation already selected `[8:0]`. Prove with LEC |
| B4 | Three floating inputs: `sys_remap_ctrl` (generated SoC top), `hw_credit_consume_vld`/`_val` (TideLink) | 2 sites | `sys_remap_ctrl` is +1 YAML line; the TideLink pair is testbench-only |
| B5 | `puf_rx_tready` undriven when `PUF_ENABLE=0` | `tidechart_controller.sv` | One line in the `gen_no_puf` branch |
| B6 | Dead parameters that look configurable: `FLASH_ADDR_W`/`CACHE_SIZE` are passed from the SoC top into a wrapper with no destination | `qspi_flash_ahb.v:28,29` | Plumb through or delete — a "configuration" knob that does nothing is a trap |
| B7 | `sys_scanouthclk` omitted at top level only; the subsystem emitter appends it, the toplevel emitter does not | `nanosoc_gen/soc_model/backends/toplevel.py` | +5 lines, mirroring `subsystem.py:351-356` |

### Tier C — mechanical, high volume, zero behavioural risk

| # | Finding | Count | Note |
|---|---|---|---|
| C1 | Case tags narrower than the 7-bit selector | 78 HAL + ~114 Verilator | **One file, `tidechart_apb_regs.sv`. Clears ~192 findings — roughly half the entire authored backlog.** Highest return in the plan |
| C2 | `NAUTOF` — SV function without `automatic` | 19 | All pure-combinational and non-recursive, so static storage cannot bite today; the exposure is tool-dependence |
| C3 | Reset literal `{WIDTH{1'b0}}` into a `[WIDTH:0]` reg | 2 | Correct only because the value is all-zeros |
| C4 | Orphan `wire QSPI_BUSY` | 1 | Both consumers bind other nets; no status lost |

### Tier D — structural, prevents recurrence

- **D1. Instance port-coverage check in the generator.** A1, B4 and B7 are three symptoms of one hole: neither instance emitter checks that every port of the instantiated module is classified. `check_chip_boundary.py` closes exactly this hazard for the chip wrapper and its docstring names the failure — the lesson was never carried to instance emission. Unclassified **inputs** should be a hard error. Mutation-prove it.
- **D2. `make chip-boundary` is red today**, so `make check` is red on a tapeout branch. Two I²C `_t` signals reach no pad cell because the pad ring folds open-drain onto `OEN` — silicon is correct, the spec lacks an `open_drain` pad kind. **A red gate is a gate nobody reads; fix it first.**

---

## 3. What is worth waiving

**~1 060 of the 1 230 authored findings across both tools.** Waive by *class with
a recorded justification*, never by silencing a code globally.

| Class | Count | Why waive |
|---|---|---|
| `UNUSED` | 835 | AHB `htrans[0]`, undecoded address bits, debug aliases. Fixing means 835 sites across five repos for zero silicon benefit. **Report the 4 in the integration zone separately** — 4 is reviewable, 835 is what hides them |
| `PINCONNECTEMPTY` **on outputs** | 252 | Deliberate open outputs, each commented at its instance. Waive the *output subset*; the code itself must stay direction-gated |
| HAL style rules | 11 682 | Naming, comments, packaging. Three carve-outs: `OBMEMI` (a memory index-width note is the signature of the boot-ROM class), `DNGLEL` (dangling-else is semantic, not naming), `BSINTT` |
| `UNPACKED` | 417 | **My write-up overstated this.** All 417 are in three generated `*_discovery_pkg.sv` register-descriptor packages containing zero modules. What is lost is struct type-checking in three generated files, and HAL analyses them. Scope the waiver to `*_discovery_pkg.sv` so an unpacked struct anywhere else still reports |
| Reset/clock-domain rules | 20 089 | **But not by deferring to `make cdc` — see §4** |
| Third-party in-tree | 292 V + 3 532 H | OpenCores MAC, Wlink bridges, `local_overrides/`. A patch fork costs more than the risk. Escalate upstream, record the counts |
| Generated-code style (`LOGORP` 130, `TRGGLT` 32) | 162 | From the **Arm CMSDK bus-matrix generator**, not from nanosoc_gen — there is no SoC Labs template to fix. All `LOGORP` operands verified 1-bit (`\|` ≡ `\|\|`); all 32 `TRGGLT` verified single-procedural-driver, so it is **not** the fc_shell-blocking class |
| `UASREG` ×32, `CONSTC` ×22, `TSETGV` ×13 | 67 | 32 words of unreset context RAM always written before read; `if (PARAM)` config folding; 5 tasks called from a single `always` block — not multi-driver |

**Never waive as a class:** `ULRELE` (padding produces an incorrect result — this
class changes behaviour, and TideLink's own README ties it to a real silicon
finding), any `*E` in authored RTL, and any empty-or-omitted pin on an
input/inout.

**Do not baseline a count of 1.** `URAWIR` and `UASWIR` are singletons. A
baseline of 1 is a bug you have agreed to keep.

---

## 4. Two holes that produced no lint line at all

The most valuable findings were not in the report.

**The CDC deferral points at a gate that cannot receive it.** `make cdc` runs top
`nanosoc_eth_chiplet` — the **inner** module — over the **FPGA** flist, while this
pass runs `nanosoc_eth_chiplet_chip` over the ASIC flist. The pad ring, where the
far die's `pad_clk_rx` enters, is not in the CDC scope **at all**. It passes no
`-halargs`, so of the 24 rules deferred to it, it computes exactly **one**
(`MCKDMN`). And it has no `exit` on any finding — it is a report, not a gate. All
three must be fixed or the deferral is fiction.

> Also: `CDC_FINDINGS.md` claims HAL cannot do a full `CLKDMN` analysis
> without SDC. That is wrong — a mutation pushed through the exact `make cdc`
> invocation produced `*E,CLKDMN`. So `CLKDMN=0` is a real result, not a tool
> limitation, and it was the merged ruleset that destroyed it.

**A waiver broader than its own justification hid A1.** `URDWIR` is waived with
the recorded reason *"intentional dead-end sinks routed to named `*_nc` wires"*.
`dmac_0_err_w` is not a `*_nc` wire, so it falls outside the justification —
but the waiver is by rule name, not by pattern. **Narrow it to `*_nc`-suffixed
nets and re-run.** This is the same failure as the `MLTDRV`/`CLKDMN` one: a
waiver correct for one block, wrong for the integration.

---

## 5. How we prove the fixes

The evidence base is weaker than it looks: the ASIC netlist already diverges
from the FPGA-proven configuration (ECC bypassed, CRC on, FCSM recovery
stripped) and no platform has run that combination. That argues for **structural**
proof (equivalence checking) over functional proof wherever the fix is supposed
to be behaviour-preserving.

**RTL-to-RTL LEC is feasible today.** Conformal `lec 22.10-s200` is installed and
licensed — proven by a completed 61 375-compare-point run. `ASIC/genus-innovus/scripts/lec/run_lec.sh`
already has a generic `run_compare` used by its self-test, and Genus writes a
dofile with 531 working `read_design` lines for this design. It needs an `rtl`
mode (~15 lines) and `+incdir`/`-define` plumbing.

| Fix class | Proof | Why |
|---|---|---|
| **C1 (78 mechanical width edits)** | RTL-to-RTL LEC, **must be equivalent** | The failure mode is a typo in edit 54. A directed test samples; LEC proves. Backstop: `tidechart_system` 50 tests |
| **A2, B2 (behaviour-changing)** | LEC to **classify**, then directed test | Here a LEC *pass* is the alarming result. On non-equivalence, `analyze_nonequivalent -source_diagnosis` names the diverging cone — that is the test specification |
| `ULRELE` generally | LEC per edit | **Rule: always widen the narrow side, never narrow the wide side.** `tl_addr_trans_regs.sv:168-172` is a live trap — the RHS are unsized parameters and zero-extension makes it correct; "fixing" it by sizing them down would truncate the upper bound |
| **B4 (floating inputs)** | Read the consumer, not simulate | `_val` is masked by `_vld`, so `1'b0` is the only tie preserving current behaviour |
| **C2 (synthesizability)** | `make elab-strict` + `make asic-syn` + `lec` | **Elaboration alone is not enough** — this repo has shipped a hollow GDSII when Genus exited 0 on a failed script and unused-logic removal deleted a datapath. Grep the LEC verdict, do not trust the exit code |
| **B3 (boot ROM)** | LEC + a **standing assertion** | No test simulates the ASIC ROM wrapper. Extend `check_chip_boundary.py` to assert generator `-a` == wrapper port width == macro `A` width == `ROM_ADDR_W`. **That assertion, not the width edit, is the deliverable** |

**Mandatory before any lint fix merges:** `make check`; `--verilator-only` diffed
against baseline; `run_lec.sh selftest` (9.5 s, proves the gate can still fail)
then the per-module compare; the owning unit env; `make regress`; `make elab`;
`make elab-strict`.

**Rollback on any of:** LEC non-equivalent for a fix declared behaviour-preserving;
`MLTDRV` > 0 in authored RTL; a `regress` proof dropping from PASS **or its skip
count rising**; `chip-boundary` failing; authored findings above baseline.

### Two guard rails that are themselves broken

- **`ci/signoff.yaml` requires `grep -q 'Analysis complete'`** in the elab-strict
  log. HAL 22.03 prints no such banner in this mode — the runner says so and
  asserts `^halstruct:` instead. The current log has **zero** `Analysis complete`
  and 60 493 `halstruct:` lines. `make elab-strict` passes while signoff fails it.
- **`lec-pnr` reports FAIL for a harness reason.** 61 375/61 375 equivalent, 0
  non-equivalent, tool exit 0 — failed only by a rule that rejects any
  non-tristate unreachable point. All 34 per side are `BBOX` supply pads, with
  identical name lists, which is exactly the condition the runner meant to
  accept. A gate red for the wrong reason teaches people to wave it through.

### The verification gap that matters most

**No TideChart testbench runs the shipping configuration.** All seven cocotb
environments and the UVM environment use `NUM_PORTS=2`; the chiplet ships
`NUM_PORTS=1`. Every finding waived on "the guard pins the index to 0 at
`NUM_PORTS=1`" is a reasoning result, not a simulated one — and B1 and B2 both
need a `NUM_PORTS=1` run anyway. **Parameterising `tb_top.sv` is the single
highest-value verification change here.**

---

## 6. The gate

Three tiers. Baseline the count, gate the delta.

- **Tier 1 — hard from day one.** The 16 Verilator structural codes, the 10 HAL
  sign-off rules, and any empty/omitted pin on an **input or inout**. Every one
  has **zero authored instances today**, so this tier is free and locks 26
  classes permanently. Take it immediately.
- **Tier 2 — baseline, fail on a per-`(zone, code)` increase.** `WIDTH` (161),
  `PINMISSING` on outputs, `CASEINCOMPLETE`, `CMPCONST`, `UNDRIVEN`, and the HAL
  authored set. Compare per zone, never on totals — a total masks a swap.
- **Tier 3 — report only.** Third-party and Arm IP tiers, both tools. Record the
  counts ungated: when a freeze delta is entirely third-party, being able to say
  so with numbers is what makes it defensible.

**Enforcement that makes it stick:** a 20-line mutation module with a known
multi-driver and a known unsynchronised crossing, pushed through HAL with the
*shipped* ruleset, failing if `MLTDRV` and `CLKDMN` are not reported. ~15 s on
one Xcelium seat. It is the only thing that stops the next ruleset merge from
silently re-waiving them — which is exactly how this happened the first time.

**CI:** `verif/lint/full/run.sh --verilator-only` is 90 s and licence-free, so it
belongs in `make check` — which puts it in the nightly with no workflow change.
The HAL half (~21 min) goes in the nightly after `elab-strict`, and the lint
record belongs as a stage in `asic-signoff.yml`, because that workflow produces
the artefact a reviewer signs.

---

## 7. Sequence

Risk front-loaded into cheap checks. **Nothing in steps 4+ starts before step 2
lands** — without RTL-to-RTL LEC the only evidence for a 78-edit batch is a test
suite that samples the space.

| # | Work | Effort |
|---|---|---|
| 0 | **Fix `make chip-boundary`** (open-drain pad kind). A red gate on a tapeout branch | 0.5 d |
| 1 | Flow fixes ✅ **done** — `SYNTHESIS` define, sign-off rules restored, FLOW visibility, direction-aware pins | — |
| 2 | `rtl` mode in `run_lec.sh`; prove it on a deliberately mutated file | 1 d |
| 3 | Fix the two broken guard rails (`Analysis complete`, `BBOX`); baseline harness; wire into `make check` | 1.5 d |
| 4 | **C1** — `tidechart_apb_regs.sv` case tags. Clears ~192 findings | 1 d |
| 5 | **A1** DMA IRQ routing + narrow the `URDWIR` waiver + re-run | 1 d |
| 6 | **A3/A4** ROM spec + preflight guard; **B3** wrapper widths | 1 d |
| 7 | **A2** PTP servo; **A5** TideChart bounds check — individually proven | 2 d |
| 8 | **B1/B2** + parameterise the TideChart TBs for `NUM_PORTS=1` and `=8` | 2 d |
| 9 | **B4–B7, C2–C4, D1** batched by file | 2 d |
| 10 | Repair `make cdc` (halargs, halstruct assertion, exit path), then re-defer the CDC bucket to it | 1.5 d |
| 11 | Full re-qualification | 1 d + tool time |

**≈ 15 working days**, of which the first four are flow work that makes every
later step cheap to prove and hard to fake.

**Reachable end state:** authored Verilator findings to **zero** (168 → ~0 after
C1, A/B tiers and scoped waivers), authored HAL DESIGN to a recorded baseline
with every remaining class justified. "Lint clean" is achievable for authored
RTL. It is not achievable for the third-party tier, and should not be attempted —
those get a recorded, ungated tier.

---

## 8. Executing it — one fix at a time, automated, provable

The plan above is a document. This section is the machinery that runs it.

### 8.1 The change unit

`verif/lint/full/fixes/*.yaml`. One defect, one branch, one commit, one verdict.
The rule that makes it work: **a CU declares what it expects before it is
applied.** A fix claiming to be behaviour-preserving that then fails equivalence
is not a surprise to investigate — it is a failed gate that says so itself.

```yaml
risk:  behaviour-preserving | behaviour-changing | flow-only
expect:
  lec: equivalent | non-equivalent | n/a     # the load-bearing field
  lint_delta: {WIDTH: -114, UELCIT: -78}
gates: {unit: [...], integration: [...], fpga: none | kr260-eth-chiplet}
```

| risk | expect.lec | a violation means |
|---|---|---|
| behaviour-preserving | `equivalent` | **you changed silicon behaviour by accident** — hard stop |
| behaviour-changing | `non-equivalent` | the edit was a no-op; re-classify the finding as cosmetic |

On a genuine non-equivalence, Conformal's `analyze_nonequivalent
-source_diagnosis` names the diverging cone — **that output is the specification
for the directed test**, so you do not have to invent one.

### 8.2 The gate ladder

`verif/lint/full/prove_fix.sh <cu.yaml>` — cheapest first, stops at the first
failure, so a broken fix costs 90 seconds rather than a 40-minute board slot.

| | gate | cost | needs |
|---|---|---|---|
| G0 | diff touches only the declared files | instant | — |
| G1 | lint delta per `(zone, code)` vs baseline, **and** matches the declared delta | 90 s | — |
| G2 | RTL-to-RTL LEC; verdict must match `expect.lec` | seconds/module | Conformal |
| G3 | the owning cocotb/UVM env | minutes | VCS |
| G4 | `make regress` + `elab` + `elab-strict` | ~50 min | VCS + Xcelium |
| G5 | KR260 two-board hardware regression | ~10 min + build | 2 boards |

G2 runs `run_lec.sh selftest` first: **prove the gate can still fail before
believing a pass from it.**

**G0 is base-aware, and it has to be.** A bare `git diff HEAD` in the main
checkout sees every concurrent session's uncommitted work — measured: 15
unrelated files. G0 distinguishes *dirty tree* (BLOCKED — not a verdict on this
CU) from *undeclared file changed* (FAIL). Mutation-proven both ways.

### 8.3 FPGA validation — what is real

| asset | status |
|---|---|
| `fpga/haps-sx` | builds a bitstream; **never run on hardware**. Not a gate |
| `tidelink/fpga/targets/kr260-eth-chiplet` | the real target; silicon link-up proven on it |
| `tidelink/pynq_host/scripts/kr260_eth_regress.py` | **the hardware gate.** Its own header: "run it after every design iteration to confirm the D2D link and data plane still work on silicon". Gating/non-gating per test, exits non-zero |
| `eth_sysval_board.py` | board-side primitives over the PS FPD backdoor, wedge-safe by construction |

What it proves, PS-side over the `eth_ss_0` backdoor with no firmware or SWD:
provenance → link (FCSM=4 on both dies) → backdoor → role strap → `sram_fwd` →
`sram_rtt` → `sram_rev` → mailbox → tidechart.

Three operational constraints, all of which the workflow honours:

1. **Two boards, one lease.** Hardware CUs are serialised, never parallel. A
   wedged link costs a physical power-cycle.
2. **Board management runs elsewhere.** `fpgahub` per-board endpoints are not
   reachable from this host; board ops belong on the lab host. The regression
   itself drives both boards over ssh via `KR260_DIE_A` / `KR260_DIE_B`.
3. **Only CUs that touch the D2D or ethernet datapath need G5.** Of the six
   manifests written so far, exactly one does (`A5`, the TideChart enum bounds
   check). A width fix in an APB decoder does not earn a board slot.

**The honest caveat:** the FPGA build is not the ASIC configuration. The ASIC
netlist ships ECC bypassed, CRC on and FCSM recovery stripped, and no platform
has run that combination. G5 proves a fix did not break the FPGA-proven data
plane. It does not prove the ASIC configuration works — nothing available does.
That is why G2 (equivalence) is the spine and G5 is the backstop, not the
reverse.

### 8.4 The loop

`.claude/workflows/lint-fix-loop.js`, re-invokable, skips what is already merged:

```
Survey     one agent reads the manifests, git state and baseline; returns
           ready / blocked / repo-wide-blockers. Re-checks the two known
           blockers (LEC rtl mode, red chip-boundary) every pass.
Implement  one agent per CU, each in its OWN git worktree, told to apply
           exactly one manifest and to REFUSE if the manifest is wrong.
Prove      the gate ladder; BLOCKED and FAIL are reported distinctly.
Refute     two adversarial agents per CU, distinct lenses (correctness,
           silicon impact), defaulting to refuted=true.
Report     merge / hold / rework per CU, plus manifests that turned out wrong.
```

Deliberate choices:

- **A single credible refutation holds a change.** Not a majority vote — holding
  a fix for a day costs nothing next to a bad one reaching silicon.
- **An agent may refuse a manifest.** `applied: false` with a reason is a good
  outcome. Three of the first-cut P1 items were wrong, and one proposed fix
  would have silently disabled an X-detector; forcing a manifest is how a plan
  becomes damage.
- **Worktree isolation per CU.** Concurrent CUs cannot collide, and G0 gets a
  clean base.
- **Nothing merges automatically.** The workflow produces a recommendation.

```sh
/loop  Workflow lint-fix-loop {batch: 2, allowFpga: false, dryRun: true}
```

Raise `batch` once the ladder has been through a full pass; set `allowFpga` only
when the boards are leased.

---

## 9. Found while clearing the HAL errors — a design defect, not a lint finding

Triaging the last authored HAL error (`*E,TERMST` on `tidechart_election_fsm`)
turned up something underneath it that lint cannot see and no test covers:

> **`ST_SETTLED` starves the shared FC RX channel.** One election-subtype beat
> arriving at a settled die permanently stalls that die's ENTIRE cross-die
> receive path — D2D RX data FIFO, TideChart, and the FC sideband APB, because
> `tl_fc_l2a` carries all three. Trigger is ~20 us of boot skew between two
> independently-booting dies; no fault required. No hardware-autonomous
> recovery exists, and the `eth_ss_0` backdoor used for KR260 bring-up is tied
> off in silicon.

Full write-up, with every link verified against the RTL and the recovery paths
established on the SHIPPING die: **`../debug/TC_SETTLED_RX_WEDGE.md`**.

The `TERMST` error itself was benign and is fixed
(`state_next = restart ? ST_IDLE : ST_SETTLED;`, LEC equivalent 242/242).

**The transferable point:** the lint error was not the bug, but triaging it
properly is what surfaced the bug. Three of the seven authored HAL errors turned
out to be worth fixing at source, one was genuinely unfixable and waived with its
analysis, and the last one led here. A finding dismissed as "a false positive"
without opening the surrounding code would have closed all of that off — which is
exactly what the first triage of this same error did.
