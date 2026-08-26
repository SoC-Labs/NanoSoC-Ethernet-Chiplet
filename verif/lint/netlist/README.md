# Netlist lint — the post-synthesis gate netlist, HAL, report-only

```sh
verif/lint/netlist/selftest.sh    # ~30 s, no netlist, proves the flow discriminates
verif/lint/netlist/run.sh         # the real pass; reports land in build/lint/netlist/
```

Every other lint and CDC flow in this tree reads an **RTL filelist**:
`verif/lint/full`, `verif/cdc`, `verif/elab_strict`, `tidechart/lint`,
`tidelink/lint`, and the per-block units under `nanosoc-multicore-system`. This
one reads the **mapped netlist**.

## Why a netlist pass exists at all

There is one defect class that no RTL tool and no LEC run can see: **a hard
macro pin left unconnected by synthesis.**

LEC compares the RTL and the netlist up to the pins of `rf_01k` and stops — the
macro is a black box on *both* sides of the comparison. So a floating memory
enable passes LEC, passes STA, passes DRC, and reaches silicon. `check_design`
in Genus does look at this, and does report it (see "What this duplicates"),
but nothing reads its output.

## Scope

| | |
|---|---|
| netlist | `ASIC/eth-chiplet/build/gdsrun-20260823-rzG/outputs/nanosoc_eth_chiplet_pads_gate.v` |
| md5 | `a7076071823c7bbe096885d70dcb2e18` |
| top | `nanosoc_eth_chiplet_pads` |
| tool | HAL 22.03-s005, via `xrun -hal -elaborate` |
| licence | `Xcelium_Single_Core` — there is no separate HAL feature |
| gating | **none.** Report-only, baselined |

The netlist is pinned **by path, not by `ls -t`**, so a new `gdsrun-*` dir
appearing mid-tapeout cannot silently move the target. That one `gate.v` is
byte-identical across nine `gdsrun-*` dirs, so "newest synthesis" and "what the
shipping GDS was placed from" are currently the same file. Override with
`NETLIST=... TOP=... verif/lint/netlist/run.sh`.

## Models, not stubs

All **399** black-box types in this netlist have a real simulation model on
disk — 382 stdcells, 9 IO pads, 6 SRAM/RF macros, 2 ROMs — so the flow reads the
real ones rather than generating stubs. Real headers cannot drift from the cells
the netlist actually instantiates; a generated stub can.

`POWER_PINS` is deliberately **not** defined. The memory models guard a second,
wider module header behind `` `ifdef POWER_PINS ``; defining it declares VDD/VSS
ports that this non-PG netlist does not connect, manufacturing 42 false
`UNCONN` hits.

## The rule set, and the trap it avoids

`UNCONN,UNCONI,UNCONO,SIZMIS,MLTDRV,MLTDIO,MULWIR,UNDRIV,TIESUP,BUSREV,PRTDUP`

**Not `-check ALL_NETLIST`.** That category name is the obvious choice and it is
wrong. It expands to `DFT + STRUCTURAL + CLOCKDOMAIN + SCANCHAIN` and contains
**no connectivity rule at all** — `UNCONN`/`UNCONI`/`UNCONO`/`SIZMIS` live under
`RTL_CODINGSTYLE_*`. Measured on the fixture: `ALL_NETLIST` found **0 of 3**
planted defects, exit 0. `selftest.sh` re-proves this every run.

**Not `-check ALL` either** — that adds the naming and comment rulesets, which on
190,110 instances buries the signal.

**Comma is the only separator HAL accepts.** `UNCONN+SIZMIS` and space-separated
forms produce a `*W,BADCAT` warning, `rc=0`, and a near-empty report. Guarded.

Two flags are load-bearing, not tidiness:

- **`-BB_CELLDEFINE`** blackboxes everything between `` `celldefine ``/`` `endcelldefine ``
  — the whole stdcell and IO library. It keeps the real port declarations while
  dropping the specify blocks that would stall `halsynth`. It is also what
  promotes `UNCONI` from silent to **ERROR**: HAL assumes a *blackboxed* module
  uses every formal input, and only then can an unconnected input be an error.
  Against a plain empty-body module, `UNCONI` says nothing and only the
  Warning-level `UNCONN` fires. Both directions are asserted in `selftest.sh`.
- **`-BB_NONSYNTH`** — without it `halsynth` hits its error threshold, emits
  `*E,BLDSTP`, and stops **before `halstruct` runs**. `MLTDRV` and `UNCONI` are
  `halstruct` rules, so a grep returns 0 and the run looks clean having never
  checked. Guarded.

## Guards — what actually fails this script

Findings never fail it. What fails it is a run that did not measure what it
claims to. Each of these produces a zero-finding report indistinguishable, by
count alone, from a clean design:

| guard | catches |
|---|---|
| `not-timed-out` | a killed run — every not-yet-run rule reports zero |
| `all-modules-resolved` (`CUVMUR`) | macro models missing; HAL then reports zero `UNCONN` and zero `SIZMIS` and exits 0 |
| `fully-elaborated` (`PRTSNP`) | HAL's own admission that connectivity info is incomplete — it says so and reports zero anyway |
| `rules-recognised` (`BADCAT`) | a mistyped or wrongly-separated rule list |
| `halstruct-ran` | structural rules never evaluated |
| `no-bldstp-abort` (`BLDSTP`) | the specific abort that silently skips `halstruct` |

A guard failure exits 1 with `RESULT=INVALID`. Findings exit 0 with `RESULT=OK`.

## What this duplicates, and what it adds

**Duplicates.** Genus `check_design -all` already enumerates this and its report
is current: `gdsrun-20260821-slpads/reports/syn_check_design.rep` (4.1 MB) —
0 unresolved references, 0 empty modules, 0 undriven ports, 20 undriven
combinational leaf pins, 6 undriven hierarchical pins, 4 multidriven ports,
34 multidriven leaf pins. The 20 is a genuine enumeration, not a print cap: the
section lists exactly 20 pins and totals 20. (The `ELABUTL-125` count in
`syn.log` *is* capped at 20 by `MESG-11` — a different mechanism, same number,
coincidentally.)

**Adds.** Three things:

1. **Something reads the result.** Of those counts, only `unresolved` can fail a
   run (`asic-toolkit/flow/genus/1_synthesis.tcl:535`), and it measures 0. The
   rest are written and never opened.
2. **An independent front end.** Genus checking its own output is a weaker claim
   than a second tool agreeing — the same argument `verif/lint/full` makes for
   running Verilator and HAL over one filelist.
3. **Classes `check_design` does not report** — port width mismatch on an
   instance (`SIZMIS`), reversed bus order (`BUSREV`), supply tie-offs
   (`TIESUP`), duplicate port names (`PRTDUP`).

## What it will NOT find

Genus does not leave macro ports open — it wires dangling outputs to explicitly
named `UNCONNECTED<N>` nets (20 bits on this netlist, all on the two ROMs:
`CENY` ×1 and `AY[8:0]` on each). Those pins are *connected*, to a real net with
one driver and no load, so `UNCONN` and `UNCONO` will not fire on them. The
searchable signature for that class is the net-name convention, and the
authoritative count is `check_design`'s "Unloaded" rows — not this flow.

## Known state

There are no unconnected macro ports on this netlist. Measured three
independent ways before the flow was written: a structural parse, an
empty-paren regex over the raw file, and the same regex over the
newline-flattened file (to catch Genus's wrapped continuation lines) — all zero,
with a positive control confirming the regex fires on a synthetic `.CK()`. All
19 memory and 2 ROM instances have every functional port connected.

So this flow's first job is to hold that, not to find it.

## First run — 2026-08-24, rzG `gate.v` (md5 `a7076071…`)

233 s, `xrun rc=0`, all six guards pass, `RESULT=OK`.

| rule | count | reading |
|---|---:|---|
| `UNCONO` | 2165 | 2143 are library cells with an unused `QN` — noise. **22** are not. |
| `UNDRIV` | 221 | undriven module outputs; see the ownership split the report prints |
| `MULWIR` | 37 | multi-driven wires, same four supply buses as below |
| `MLTDRV` | **4** | `VDD`, `VSS`, `VDDIO`, `VSSIO` — **benign** |
| `UNCONN` | **0** | no unconnected instance port anywhere |
| `UNCONI` | **0** | no unconnected input on a blackboxed cell or macro |
| `SIZMIS` | **0** | no port width mismatch |

`UNCONN`/`UNCONI`/`SIZMIS` at zero is the headline: the class this flow was
built for is clean, measured by a tool whose ability to report it is proven by
`selftest.sh` rather than assumed.

The 4 `MLTDRV` are the padring supply buses, multiply driven by construction —
every supply pad drives the bus. They match Genus's own "Multidriven Port(s) 4"
exactly, and they are the same four nets as the IMEC pad-short report.

`TRNNOP` (34) and `DSEMEL` (1) also appear. Neither is in the requested rule
list — they are `xmelab` messages that print regardless: `TRNNOP` is the
bidirectional primitive in the TSMC IO library, `DSEMEL` is an SV-2009 semantics
notice. Both are FLOW, not design.

Note the library-cell filter used for the `UNCONO` split is a **cell-name prefix
match**, not a library lookup — `BENCD1` and `EDFCND1` fall through it and land
in the "look here" bucket. Tighten the prefix list before reading that 22 as a
count of design defects.

### Finding: boundary scan is output-only

**All 33 `*_core_in` outputs of `nanosoc_eth_chiplet_bscan` are declared and
driven by nothing.** Confirmed in the netlist, not inferred from the rule: the
module declares them `output`, declares them again as `wire`, and contains no
`assign` and no instance pin driving any of them across its 362 instances.

The pad direction *is* built — `TL_TX_0_pad_out` is driven through a mux
(`.S (n_104), .Z (TL_TX_0_pad_out)`), i.e. the observe/control cell exists on
the output side. The input side has no such cell.

At the one top-level instantiation (`gate.v:591173`) every one of those outputs
goes to a dangling net — `.I2C_SCL_core_in (UNCONNECTED2645)` — while the core
takes `I2C_SCL` from the pad directly. So the chip functions, and nothing else
in the flow flagged it: the dead half is bypassed rather than in the path.

Affected pins: `NRST_I`, `CLK_I`, `SWDCK_I`, `SWDIO_IO`, `TEST_I`, `SE_I`,
`HOST_IO[6:0]`, `RMII_{CRS_DV,MDIO,RXD1,RXD0,REF_CLK}`, `QSPI_IO[3:0]`,
`TL_RX[7:0]`, `TL_CLK_RX`, `I2C_{SCL,SDA}`.

Consequence: JTAG `EXTEST` cannot drive the core through these cells, and
`SAMPLE`/`PRELOAD` cannot observe an input as seen by the core. This generalises
the existing `SE`-pad note — it is not one pad, it is the entire input half.

**Caveat on scope:** this describes the 2026-08-21 synthesis that the rzG
lineage was placed from. It is not a statement about current
`feat/padring-boundary-scan` RTL. Re-run against a fresh synthesis before
treating it as the state of that branch.

## Sibling-flow defect noted while building this

`verif/lint/full/hal_lint.sh:56` and `hal_report.py:221` both list **`NODRIV`**
in their never-waive sign-off set. That mnemonic does not exist in HAL 22.03 —
zero occurrences in `hal.def`, `old_hal.def`, `slint.def`, `JRDRS.def`, or
anywhere under `doc/halref/`. The real rule is **`UNDRIV`**
(`hal.def:579`, `RTL_CODINGSTYLE_MIXED`, level 2, Warning).

Consequence over there: the undriven-output class is in the never-waive list
under a name HAL can never emit, so it is neither gated nor waivable, and the
`-nocheck` guard at `hal_lint.sh:58` would not notice someone waiving the real
`UNDRIV`. Spelled correctly in this flow. Not fixed in the sibling — that file
belongs to the full-design pass and other sessions are active in it.

## A note on reading these logs

HAL echoes its own command line into the logfile, and that line contains the
rule list. A bare `grep -c UNCONI` therefore matches the echo and reads 1 on a
design with zero findings. Every grep in `run.sh` and `selftest.sh` anchors on
the message prefix (`\*[A-Z],RULE`) for that reason. This bit the selftest
during development.
