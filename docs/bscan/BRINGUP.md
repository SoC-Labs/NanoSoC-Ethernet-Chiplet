# Boundary-scan bring-up — nanoSoC ethernet chiplet

**This structure has never been used by a human.** Everything below is either
measured in gate-level simulation against the routed netlist, read directly out of
the RTL / pad table / BSDL, or explicitly marked **not established**. Where a number
appears, the file it came from is named. Nothing here is inferred from what a
1149.1 device "usually" does.

**What has been proven, and where:** `verif/bscan/run_gate.sh` drives the routed
netlist `ASIC/eth-chiplet/build/bscan-probe/outputs/nanosoc_eth_chiplet_pads_pnr.v`
at its **48 package pads and nowhere else** — no hierarchical references into the
design. Last run: `BSCAN_GATE_SUMMARY: PASS checks=5063 fails=0 tests=7/7`,
4,418 TCK cycles (`verif/bscan/build_gate/sim.log:96` and its summary line).

**What has not been proven:** anything on silicon. This is a simulation result at
zero delay against an older cell revision than the sign-off Liberty
(`verif/bscan/README.md`, "Two traps that had to be measured"). It says the chain
shifts. It says nothing about timing.

---

## ⚠ READ THIS BEFORE YOU CONNECT ANYTHING

### Raise `SE` first. Then drive TDI. Never the other way round.

`HOSTIO4_P1[0]` — the pad that becomes **TDI** — is a functional bidirectional pad
whose **output driver is enabled while `SE` is low**. A JTAG master that drives TDI
onto it before `SE` goes high is fighting a 16 mA output.

**Measured**, not reasoned: the pad model prints `++BUS CONFLICT++` on every TDI
edge, which is exactly what the gate bench did until it was changed to take that pin
on `SE` and not a moment sooner (`verif/bscan/README.md`, "One operational trap,
found the hard way"; `verif/bscan/tb_bscan_gate.sv:205`,
`assign HOSTIO4_P1[0] = se_r ? tdi_r : 1'bz;`).

The mechanism, from the routed netlist: the pad's output enable is
`OEN = SE ? 1 : ~bsp_host_io_0_oe` (gate `IND2D0 g64__3680`, netlist line 1319218,
matching `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:623`). Only `SE = 1`
forces that pad input-only. And `HOST_IO_0_core_oe` is **unconnected** in the routed
netlist (`UNCONNECTED_HIER_Z1600`, netlist line 1316379) — the core never drives it,
so with `SE = 0` there is no defined-safe enable value to fall back on.

**`SWDIO` (TMS) has no such problem** — reset leaves its driver tri-stated
(`verif/bscan/tb_bscan_gate.sv:195–204`). It is safe to take before `SE`. TDI is not.

### One more: `0100` is not BYPASS on this die

The BSDL declares opcode `0100` as one of the codes that map to BYPASS
(`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:215`). **The silicon decodes `0100`
as HIGHZ** (`src/rtl/bscan/bscan_ir.sv:139` `INSN_HIGHZ = 'h4`, and `:206`
`INSN_HIGHZ : dec = 5'b10001` — BYPASS in the chain, `highz` asserted). The DR is
BYPASS either way, so shifting behaves as the BSDL says, **but issuing `0100` also
tri-states the 13 bidirectional and 2 open-drain pads.**

**Use `1111` for BYPASS. Never `0100`.** See §9 for why the BSDL says what it says.

---

## 1. The TAP, and where it lives

There are **no dedicated TAP pads on this die.** The TAP is muxed onto four
functional pads and is gated by the `SE` pad
(`src/rtl/bscan/INTERFACE_CONTRACT.md` §7;
`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:350–360`).

| TAP signal | Package pad | Note |
|---|---|---|
| **TCK** | `SWDCK` | pure input pad (`OEN` tied high) — always safe to drive |
| **TMS** | `SWDIO` | bidir; reset leaves its driver off, so safe to take before `SE` |
| **TDI** | `HOSTIO4_P1[0]` | bidir; **driver enabled while `SE`=0 — see the warning above** |
| **TDO** | `HOSTIO4_P1[1]` | bidir; output enabled by the TAP only while shifting |
| **TRST** | *(none)* | `SE` serves this role — see below |

`bscan_en = bsp_se_i_in` is taken **pad-side**
(`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:350`), so it works with the
core completely dead.

**`SE` is `trst_n`, not `~trst_n`.**
`SE = 0` holds the TAP asynchronously in Test-Logic-Reset, resets the instruction to
IDCODE, forces `mode = 0` and leaves every boundary cell transparent — normal
operation is bit-identical to a die without boundary scan
(`src/rtl/bscan/INTERFACE_CONTRACT.md` §7). `SE = 1` releases it.

**`SE` is a pure input pad** (`OEN` tied high, `.I` tied low —
`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:518–524`), so driving it from
the board contends with nothing.

**Raising `SE` does not put the core into a scan mode.** `SE` also feeds the SoC's
`sys_scanenable` port, but that port's net was verified unconnected inside the SoC
in the shipping netlist (`uPAD_SE_I ... .C (UNCONNECTED2828)`) and **there is no scan
chain anywhere on this die**. Note the caveat: that verification was against
`ASIC/eth-chiplet/build/full-20260814/`, the pre-boundary-scan shipping netlist, not
against the bscan-probe build.

**TDO shares a bonded functional output driver**, so its enable matters. It is driven
**only** in Shift-IR and Shift-DR and tri-state in every other TAP state — checked
over all 4,372 `SE=1` TCK cycles of the gate run (`verif/bscan/README.md`, gate T6).
Do not read a level off TDO outside a shift; there is not one. The gate bench
deliberately leaves TDO with **no pull-up**, unlike every other bidir, so that
"undriven" and "driving 0" stay distinguishable
(`verif/bscan/tb_bscan_gate.sv:186–188`).

---

## 2. What you need on the bench

- A JTAG master able to drive TCK/TMS/TDI and sample TDO, and able to issue raw
  IR/DR scans of arbitrary length. OpenOCD's `irscan` / `drscan` is sufficient.
- Independent control of **`SE`** and **`NRST`** as static levels.
- A **`CLK`** source (see §3 step 2).
- The BSDL: `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl`.

**The BSDL is not yet fit to hand to a board-test house.** Its own banner says so
(`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:30–50`) and so does its
`DESIGN_WARNING`:

- **Pin numbers are placeholders.** Every port maps to a `TBD_*` token (32 of them);
  no bond map exists yet.
- **No power, ground or analog pins are declared.** The pad table covers the 48
  signal pads only.
- You will bind BSDL to a device position manually. Because the manufacturer field
  is `0x000`, no tool will select it from an IDCODE-keyed library —
  see `docs/bscan/IDCODE_DECISION.md` §5.

**Maximum TCK frequency is NOT ESTABLISHED.** The BSDL declares 10.0 MHz and says in
the line above it that this is a placeholder and TCK is not yet characterised
(`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:195–196`). The gate bench ran at
20 MHz (`verif/bscan/tb_bscan_gate.sv:99`) but it is a **zero-delay** run
(`+nospecify +notimingcheck`), so that number sets simulation cost and is not a
timing claim. **Start slow — of the order of 1 MHz — and characterise upward.**

Board pull-ups: the gate bench models weak pull-ups on `QSPI_IO[3:0]`,
`HOSTIO4_P1[6:2]`, `RMII_MDIO`, `I2C_SCL` and `I2C_SDA`
(`verif/bscan/tb_bscan_gate.sv:206–209`). The I²C pull-ups are **required** by the
open-drain scheme, not optional (`src/rtl/bscan/INTERFACE_CONTRACT.md` §1). Whether
your board has the rest is a board property and is not established here.

---

## 3. Power-up and TAP-enable sequence

Follow this order. It is the order the gate bench uses
(`verif/bscan/tb_bscan_gate.sv:931–975`), which is the only order that has been run.

**Step 0 — connect.** Wire TCK to `SWDCK` and TMS to `SWDIO`. **Leave TDI
disconnected or tri-stated.** Wire TDO to `HOSTIO4_P1[1]`.

**Step 1 — hold everything inert.**
`SE = 0`, `NRST = 0`, `TEST = 0`. The bench holds `TEST` low for the entire run
(`verif/bscan/tb_bscan_gate.sv:172`); `TEST` drives `CGBYPASS`/`RSTBYPASS` and is
deliberately left alone by the boundary-scan design
(`src/rtl/bscan/INTERFACE_CONTRACT.md` §7).

**Step 2 — apply `CLK`, in reset, then park it.**
The bench runs the functional clock for **256 cycles** at a 20 ns period with `NRST`
low, then parks it (`verif/bscan/tb_bscan_gate.sv:107`, `:249`, `:952–958`). Its
stated purpose is to let the core's own reset settle the pad enables the core owns.

> **Not established:** whether the warm-up is *necessary* or merely hygiene. It has
> never been run without. Do it — it costs 5 µs.

After the warm-up the clock may be parked. The bench parks it by default and the
whole 7/7 result is with a parked clock and a dead core. It also accepts `+clk` to
leave it running, but **no result is quoted here for a running clock.**

**Step 3 — `NRST` stays low. For the whole session.**
This is the entire point of the structure: boundary scan exists to test a chip that
will not boot. The gate bench holds `NRST = 0` for every one of its 4,418 TCK cycles
(`verif/bscan/tb_bscan_gate.sv:173`, `wire NRST = 1'b0; // THE CORE IS DEAD FOR THE
WHOLE RUN`) and passes 7/7. Everything that appears on a pad in EXTEST came out of
an update flop clocked by TCK; nothing in the core could have produced it.

**Step 4 — take TMS.** Drive `SWDIO`. Park TMS high.

**Step 5 — raise `SE` to 1.** Allow settling (the bench waits 100 ns —
`verif/bscan/tb_bscan_gate.sv:971–972`). `SE` must stay high for the whole session: it
is the BSDL's compliance-enable pin, `COMPLIANCE_PATTERNS` is `"(SE) (1)"`
(`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:201–202`), and the device is **not a
1149.1-compliant device at all** while it is low.

**Step 6 — NOW connect and drive TDI.** Not before.

**Step 7 — reset the TAP.** Five consecutive `TMS = 1`, then one `TMS = 0` to reach
Run-Test/Idle (`verif/bscan/tb_bscan_gate.sv:432–435`). There is no TRST pin; five
TMS=1 is the only in-band route to Test-Logic-Reset.

**Shutdown, in reverse:** stop driving TDI → `SE = 0` → release TMS. The bench leaves
the chip in exactly this state (`verif/bscan/tb_bscan_gate.sv:993–995`).

---

## 4. Step A — confirm you have a live TAP (IDCODE)

Do this first, every session. It is the one check that proves the TAP, the
instruction register's reset-to-IDCODE, and the whole TDO path in one go.

1. Reset the TAP (five `TMS=1`, one `TMS=0`).
2. After Test-Logic-Reset the instruction is **already IDCODE** — the IR resets to
   IDCODE (`src/rtl/bscan/INTERFACE_CONTRACT.md` §4). You do **not** need to load it.
3. Shift **64 bits** through the DR, not 32.

**Why 64.** The first 32 bits are the captured IDCODE. The second 32 must echo back
whatever you shifted in — which is what proves the ID register is a real 32-stage
shift register and not a constant sat on TDO. Shifting only 32 cannot tell those
apart. This is exactly what gate T1 does
(`verif/bscan/tb_bscan_gate.sv:561–615`).

**Expected value — read this carefully, it depends on which die you have:**

| Built from | IDCODE | Where |
|---|---|---|
| RTL after commit `61aa090`, and the current BSDL | **`0x10001001`** | `src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv:110`, `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:233` |
| the `bscan-probe` routed netlist (written 18:57, 2026-08-19) | `0x100005A1` | measured, `verif/bscan/build_gate/sim.log:71` |

The `bscan-probe` netlist predates the IDCODE fix and **still carries the retired
value**. `scripts/bscan_bsdl_crosscheck.py` flags the divergence. If your die came
from that stream, `0x100005A1` is the correct answer and is not a fault. See
`docs/bscan/IDCODE_DECISION.md` §7d.

In both values: version `0x1`, bit 0 = `1`, manufacturer `0x000`. **A tool reporting
`mfg: 0x000 (<invalid>)` or "unknown manufacturer" is behaving correctly** — that is
a deliberate decision, recorded in `docs/bscan/IDCODE_DECISION.md`. Do not chase it.

**Also check** that Capture-IR loads `...01` in the low two bits — 1149.1 mandates
it, the BSDL declares `INSTRUCTION_CAPTURE = "0001"`
(`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:217–218`), and it comes out free on
any IR scan.

### If IDCODE is wrong, the bench's own diagnoses apply

From `verif/bscan/tb_bscan_gate.sv:604–613`:

| What you read | What it means |
|---|---|
| your shifted-in data, left-shifted by one | The DR behaved as a 1-bit BYPASS — **five TMS=1 did not reach Test-Logic-Reset.** |
| `0x0000_05A1` | Something is using the truncated 36-bit literal `32'h1_0000_05A1`, which SystemVerilog silently cuts to 32 bits and loses the version nibble. |
| all-`0` or all-`1` | A constant — TDO is not connected to the ID register. |
| `X` / no transitions | The chain never left reset, or **TCK is not arriving.** |
| nothing at all, TDO never driven | Check `SE` is actually high, and that you did not take TDI before `SE`. |

---

## 5. Step B — chain integrity

### B1. BYPASS: prove the DR is exactly one stage

1. Load IR = **`1111`** (BYPASS). *(Not `0100` — see the warning at the top.)*
2. Shift 32 bits through the DR.
3. Capture-DR must load **0**, so the first bit out is `0`.
4. Every subsequent bit must reappear **delayed by exactly one TCK**.

**A trap worth knowing at 2am:** if your master holds TDI steady across the whole TCK
high phase, it **cannot distinguish a real BYPASS flop from a plain wire**. TDO is
retimed onto the falling edge, so the retiming flop supplies the one cycle of delay
on its own and a zero-stage bypass produces a bit-identical stream. This was
**measured**, not reasoned — mutation M4b passed until the bench started moving TDI
10 ns after the rising edge (`verif/bscan/README.md`, "Why T2 moves TDI after the
rising edge"; `verif/bscan/tb_bscan_gate.sv:396–420` and `:628`). 1149.1 specifies TDI only *at*
the rising edge, so moving it in the high phase is legal for a master and invisible
to anything that samples TDI where it should.

### B2. The boundary register is exactly 76 cells

1. Load IR = **`0001`** (SAMPLE/PRELOAD).
2. Shift a 76-bit pseudo-random pattern followed by **96 more bits** — 172 total.
3. Search **every alignment from 1 to 96** for where the pattern re-emerges.
4. Require **exactly one** match, **at 76**.

**Do not just look at offset 76.** That test passes for a 75-cell chain too, because
the loop never looks anywhere else (`verif/bscan/README.md`, gate T3). Repeat with
**three independent patterns**, because one PRBS that happens to be periodic will
match at several alignments and that must not be read as a broken chain.

`BOUNDARY_LENGTH` is 76 (`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:239`;
`src/rtl/bscan/pad_table.json` `design.boundary_length`), composed as
`18 input × 1 + 15 output × 1 + 13 bidir × 3 + 2 opendrain × 2 = 76`
(`src/rtl/bscan/INTERFACE_CONTRACT.md` §1).

**If the pattern re-emerges at delay *d* ≠ 76**, the chain has *d* cells: `d > 76`
means extra cells, `d < 76` means cells dropped. If it never re-emerges at any
alignment, the chain is broken, not merely mis-sized.

---

## 6. Step C — SAMPLE

1. Load IR = **`0001`**.
2. Hold known values on the input pads.
3. Shift 76 bits out and compare each cell against what it should have captured.

Shift order is the BSDL convention: **cell 0 is nearest TDO and is the first bit
out**; the first bit you shift in is destined for cell 0 as well. On this die BSDL
cell 0 is `TL_TX(7)` (§8, and `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:272`).

**Do a per-pin walk, not just vectors.** Drive one pin at a time and require exactly
one cell to move, and that it is that pin's own cell. Four vectors alone (all-0,
all-1, two random) can be slipped past by two swapped neighbouring cells; the walk
cannot (`verif/bscan/README.md`, gate T4).

### Four cells read a constant, and that is not a fault

**BSDL cells 49, 52, 54 and 55** capture a constant under SAMPLE, because the core
never drives the nets behind them:

| BSDL cell | chain index | pad | cell role | net the core never drives |
|---:|---:|---|---|---|
| 49 | 26 | `HOSTIO4_P1[0]` | control | `soc_hostio4_p1_outen[0]` |
| 52 | 23 | `HOSTIO4_P1[1]` | control | `soc_hostio4_p1_outen[1]` |
| 54 | 21 | `HOSTIO4_P1[2]` | data | `soc_hostio4_p1_out[2]` |
| 55 | 20 | `HOSTIO4_P1[2]` | control | `soc_hostio4_p1_outen[2]` |

**This is a pre-existing property of the SoC's hostio4 controller, not something the
boundary-scan insertion caused.** Verified: zero references to those nets in the
`bscan-probe` netlist **and** in the `full-20260814` control netlist, which has no
boundary scan at all (commit `6c82edb`). **EXTEST still drives those pads** — only
the SAMPLE readback of those four bits is uninformative.

Two of those pads are TDI and TDO, so their cells are doubly uninformative while
`SE = 1` — see §9.

---

## 7. Step D — EXTEST

### ⚠ PRELOAD FIRST. On this die it is not a formality.

1149.1 requires PRELOAD before EXTEST so that the pads never carry an undefined
pattern at the moment `mode` goes high. On this die there is a specific consequence:

**Every update flop resets to 0** (`src/rtl/bscan/bscan_cell.sv`, `bscan_cell_ctl`:
`always_ff @(negedge tck or negedge trst_n) if (!trst_n) update_q <= 1'b0;`).

**The two I²C cells hold the wired-AND bus LOW in that state.** `I2C_SCL` and
`I2C_SDA` are open-drain built from a push-pull cell: `.I` is hard-tied `1'b0` and
the data is folded onto `.OEN`
(`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:909–922`;
`src/rtl/bscan/INTERFACE_CONTRACT.md` §1). Their control cells take
**`OEN = pad_oe` directly**, so `0` *enables* the driver and `1` tri-states it —
the opposite polarity to the 13 bidirs, which take `OEN = ~pad_oe`
(`verif/bscan/tb_bscan_gate.sv:143–146`).

So an update flop at its reset value of `0` on those two cells means: driver on,
driving the tied-low `.I`, **bus pulled low**. `I2C_SCL`/`I2C_SDA` are the
**TideLink I²C sideband** (`docs/design/PIN_MAP.md:352`). **Entering EXTEST without
preloading parks the D2D sideband bus low.**

> The reset value and the pad polarity are both read directly from the RTL and the
> pad ring, and the gate bench's `safe_chain()` sets those two cells to `1`
> specifically to avoid this. **A deliberate drive-the-bus-low case has not been
> simulated**; the hazard is derived from those two files, not measured.

**Two more consequences of an unpreloaded EXTEST**, from the same all-zero state:

- The **13 bidirs** are safe by accident: `pad_oe = 0` gives `OEN = ~0 = 1`,
  tri-state.
- The **15 pure outputs are all driven to 0** — including the 9 TideLink TX pads,
  and including **`QSPI_nCS`** (BSDL cell 35). If a QSPI flash is attached, that
  asserts its chip select. Hold BSDL cell 35 at `1` in every preload unless you mean
  to select it. *(Derived from the pad's name and direction, not measured.)*

### The safe skeleton to build every preload on

Set these first, then overlay only what you intend to drive
(`verif/bscan/tb_bscan_gate.sv:508–514`):

| cells | value | effect |
|---|---|---|
| the 13 bidir **control** cells — BSDL **70, 67, 64, 61, 58, 55, 52, 49, 45, 33, 30, 27, 24** | **0** | `OEN = ~0 = 1` → tri-state |
| the 2 I²C **control** cells — BSDL **12** (`I2C_SCL`), **10** (`I2C_SDA`) | **1** | `OEN = 1` → tri-state, bus released to its pull-up |
| `QSPI_nCS` data — BSDL **35** | **1** | de-asserts a flash chip select |
| everything else | 0 | |

**Getting the I²C polarity backwards puts a 16 mA push-pull driver onto a wired-AND
bus** — a cross-die short that no tool warns about
(`src/rtl/bscan/INTERFACE_CONTRACT.md` §1).

### The EXTEST sequence

1. Load IR = **`0001`** (SAMPLE/PRELOAD). `mode` is still 0 — the pads do not move.
2. Shift the full 76-bit pattern through the DR and pass through **Update-DR**.
   *Confirm no pad moved.* A preload that disturbs a live system is a hazard, and
   gate T5 asserts this explicitly (`verif/bscan/tb_bscan_gate.sv:838–847`).
3. Load IR = **`0000`** (EXTEST). `mode` goes to 1 on **Update-IR**, and the pads
   take the values already in the update flops.
4. To change the drive: shift a new 76-bit pattern under EXTEST and pass through
   Update-DR again. The new values take effect at Update-DR.
5. To release: **five `TMS = 1`** to Test-Logic-Reset. The instruction resets to
   IDCODE, `mode` drops, and the pads go back to the core
   (`verif/bscan/tb_bscan_gate.sv:893–906`).

**Do both polarities.** Drive pattern P, then `~P`. With the core dead a stuck pad
reads the same value whatever you load, so a single pattern proves nothing. Then walk
a 1 through every driven cell (`verif/bscan/README.md`, gate T5). Measured: the
EXTEST drive survives 200 ns of idle TCK, so a value that decays was never latched
(`verif/bscan/tb_bscan_gate.sv:853`).

### What EXTEST cannot do on this die

- **It cannot tri-state the 15 pure-output pads.** Their `OEN` is tied low in the pad
  ring and they have no control cell, so no instruction can release them
  (`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:41–46`;
  `scripts/gen_bscan.py:107–119`). They are declared `output2` in the BSDL for this
  reason. **This is why HIGHZ is not offered** — see §9.
- **It cannot independently drive the four TAP pads** (`SWDCK`, `SWDIO`,
  `HOSTIO4_P1[0]`, `HOSTIO4_P1[1]`). Their cells are in the chain — the length stays
  76 — but while `SE = 1` the pad ring overrides those pads: `HOSTIO4_P1[1]` is
  forced to TDO, and `SWDIO` / `HOSTIO4_P1[0]` are forced input-only. **Treat their
  nets as untestable from this die** (BSDL `DESIGN_WARNING`).
- **It must never drive the `SE` cell.** `SE` is the compliance-enable pin *and* has
  a boundary cell (BSDL cell 71), which BSDL does not expect. The cell is
  observe-only, so it cannot drive — but hold `SE` at its compliance value
  throughout regardless. Observing it is useful: it confirms the pin you are holding
  high is the pin the die sees.

---

## 8. Step E — EXTEST continuity on the 18 TideLink D2D pads

**This is the case the whole structure exists for.** The 18 D2D pads are 8 TX + 8 RX
+ 1 TX clock + 1 RX clock (`docs/design/PIN_MAP.md:89`). All 18 are on the **left**
side of the ring (`src/rtl/bscan/pad_table.json`, `side` field, ring indices 56–81).

### The 18 cells

**9 driven (pure outputs, data cells):**

| BSDL cell | chain | pad |
|---:|---:|---|
| 0 | 75 | `TL_TX[7]` |
| 1 | 74 | `TL_TX[6]` |
| 2 | 73 | `TL_TX[5]` |
| 3 | 72 | `TL_TX[4]` |
| 4 | 71 | **`TL_CLK_TX`** |
| 5 | 70 | `TL_TX[3]` |
| 6 | 69 | `TL_TX[2]` |
| 7 | 68 | `TL_TX[1]` |
| 8 | 67 | `TL_TX[0]` |

**9 observed (pure inputs, observe cells):**

| BSDL cell | chain | pad |
|---:|---:|---|
| 13 | 62 | `TL_RX[7]` |
| 14 | 61 | `TL_RX[6]` |
| 15 | 60 | `TL_RX[5]` |
| 16 | 59 | `TL_RX[4]` |
| 17 | 58 | **`TL_CLK_RX`** |
| 18 | 57 | `TL_RX[3]` |
| 19 | 56 | `TL_RX[2]` |
| 20 | 55 | `TL_RX[1]` |
| 21 | 54 | `TL_RX[0]` |

**Note the clock sits in the middle of the bus in ring order, not at either end.**
`TL_CLK_TX` is BSDL cell 4, between `TL_TX[4]` and `TL_TX[3]`; `TL_CLK_RX` is BSDL
cell 17, between `TL_RX[4]` and `TL_RX[3]`. A loop written over "cells 0..8 = TX[7:0]
plus a clock somewhere" will silently mislabel five lanes. These numbers come from
`src/rtl/bscan/pad_table.json` and agree cell-for-cell with
`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:272–293`.

### What is on the other end — three cases

**(a) With a loopback fixture** wiring this die's TX pads back to its own RX pads:
the full test runs from the TAP alone. This is the procedure below.

**(b) Bare die or probe card, nothing attached:** EXTEST drives the 9 TX pads and
you measure them with a probe; the 9 RX pads must be driven externally by the tester
and read back through the capture step. Same DR mechanics, external instrumentation.

**(c) Assembled two-die package, tested against the compute chiplet:**
**NOT ESTABLISHED.** Whether the compute die has a TAP at all, whether the two dies
share a scan chain, and how the two chains would be ordered are all outside this
repository — the compute chiplet is a separate repo. Do not assume a two-die chain.

**The cross-die lane mapping is NOT ESTABLISHED either.** `docs/design/PIN_MAP.md`
§"TX group"/"RX group" establishes that `d2d_clk_tx` forwards this die's clock
alongside `d2d_tx[7:0]` and that `d2d_clk_rx` is the far die's forwarded clock — but
nothing in this repo states that `TL_TX[n]` lands on the far die's `TL_RX[n]`.
**Take the pairing from the fixture or interposer drawing, not from the bit index.**

### The procedure (loopback case)

The capture is **one scan behind** the drive. This is the standard EXTEST pipeline
and it is the off-by-one most likely to cost you the morning:

> Update-DR of scan *k* applies pattern *k* to the pads.
> Capture-DR at the **start of scan *k+1*** samples the pins.
> The captured values shift out **during scan *k+1***, while pattern *k+1* shifts in.

So a run of *N* patterns takes *N+1* scans, and the last scan's shift-in is a
throwaway (use the safe skeleton).

1. **Reset the TAP**, then run §4 (IDCODE) and §5 (chain integrity). Do not skip
   them — a continuity failure and a broken chain look identical from the outside.
2. **Preload the safe skeleton** under IR `0001`, then load IR `0000` (EXTEST). All
   9 TX pads are now driven to 0; the I²C bus is released; `QSPI_nCS` is high.
3. **Pattern 0 — all TX low.** Already applied by step 2.
4. **Scan 1:** shift in *pattern 1 = all TX high* (BSDL cells 0–8 = 1, rest =
   skeleton). Read out the capture of pattern 0: **BSDL cells 13–21 must all read
   the level your fixture produces for a low TX**, and no other cell may have moved
   from its expected value.
5. **Scan 2:** shift in *pattern 2 = walking-1, TX bit 0*. Read out the capture of
   pattern 1: **cells 13–21 must all read high.**
   Steps 4 and 5 together are the both-polarities check. Skipping one leaves a stuck
   pad indistinguishable from a working one.
6. **Scans 3..11 — the walking 1.** For *k* = 0..8, drive exactly one of BSDL cells
   0..8 high and the rest low. Each capture must show **exactly one** of BSDL cells
   13..21 at the driven level, and it must be the one the fixture pairs with the
   driven TX pad.
   - **Exactly one** is the assertion, not "the expected one is set". A short between
     two TX lanes sets two RX cells and passes the weaker test.
   - Include `TL_CLK_TX` (cell 4) and `TL_CLK_RX` (cell 17) in the walk. They are
     ordinary boundary cells here; nothing clocks during EXTEST.
7. **Scan 12:** shift in the safe skeleton and read out the last walk step.
8. **Release:** five `TMS = 1` to Test-Logic-Reset.

**Interpreting failures:**

| Symptom | Reading |
|---|---|
| one RX cell never changes across the whole walk | open on that net, or a stuck pad |
| two RX cells move together on one TX step | short between those two nets |
| all RX cells follow every TX step | shorted bus, or a fixture wiring all TX to all RX |
| all RX cells constant, both polarities | the fixture is not connected, or EXTEST never took effect — re-check that Update-IR happened after the preload |
| RX cells match but offset by one step | you read the capture from the wrong scan — see the pipeline note above |

**These 18 pads are fully covered by the two RTL-level benches** (`tb_bscan.sv` T6/T7
check all 76 cells) and by the gate bench's T4 (9 of the RX cells among its 16) and
T5 (all 9 TX cells among its 15). Nothing about these 18 cells is unproven in
simulation.

---

## 9. Deviations from 1149.1 a tester must know

All of these are declared in the BSDL rather than discovered on a tester
(`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:30–50`, `:166–191`, and its
`DESIGN_WARNING`).

1. **Not a compliant 1149.1 device with `SE = 0`.** There is no TAP at all until `SE`
   is high. `COMPLIANCE_PATTERNS` is `"(SE) (1)"` — the standard mechanism for
   saying so, and the only reason the description may claim conformance.
2. **The TAP pins carry boundary cells.** 1149.1 does not permit that for a dedicated
   TAP pin and a BSDL rule checker will say so. The cells are in the silicon; hiding
   them would be the worse lie. See §7 for what it means operationally.
3. **`SWDIO`, `HOSTIO4_P1_0`, `HOSTIO4_P1_1` are declared `inout`**, and
   `HOSTIO4_P1` bits 0 and 1 are split out of the bus as scalar ports so that VHDL
   attributes can name them. `PIN_MAP` binds them to the same physical pins either
   way and the remaining bits are **not** renumbered (`HOSTIO4_P1` keeps `6 downto 2`).
4. **`SE` is the compliance-enable pin AND has a boundary cell** (cell 71), which
   BSDL does not expect. Reported, not hidden.
5. **HIGHZ is not offered.** The BSDL maps opcode `0100` to BYPASS along with every
   other unassigned code (`:215`), and `HIGHZ` appears in no `INSTRUCTION_OPCODE`
   entry. The reason is recorded in `scripts/gen_bscan.py:107–119`: 15 of the 48 pads
   are pure outputs with no control cell, so nothing can tri-state them, and
   *"declaring HIGHZ while 15 system outputs keep driving is a conformance claim the
   silicon does not honour, and a tester would trust it."*

   **But the silicon still decodes `0100` as HIGHZ** (`src/rtl/bscan/bscan_ir.sv:139`,
   `:206`) and the wrapper still drives every control cell from it
   (`src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv:434`, `bsr_highz`). Issuing `0100`
   therefore tri-states the 13 bidir and 2 open-drain pads while the BSDL says you
   asked for BYPASS. **Use `1111`.**

   *(To make HIGHZ real: give the 15 pure-output pads a control cell each — chain
   76 → 91 — and route their `OEN` from the register. `scripts/gen_bscan.py:115–119`
   describes the change. It is scoped work, not a redesign.)*
6. **CLAMP is implemented and declared** (`0011`) but is **not exercised by either
   bench** (`verif/bscan/README.md`, "What this bench deliberately does not prove").
   Its behaviour on this die is **not established** by simulation. Note that CLAMP
   selects BYPASS as the DR while the boundary register **holds** its preloaded drive
   values, so it must be preloaded exactly as EXTEST must
   (`src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv:84–91`).
7. **The IDCODE does not identify a manufacturer.** Deliberate — see
   `docs/bscan/IDCODE_DECISION.md`.
8. **Pin numbers are `TBD_*` placeholders and no supplies are declared.** §2.

---

## 10. Instruction reference

`INSTRUCTION_LENGTH` is 4 (`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:204`).
Opcodes are written MSB-first below, as the BSDL writes them; the TAP shifts the IR
LSB-first, which is what every JTAG tool does for you — give your tool the hex value.

| Instruction | Opcode | Hex | DR selected | Pads |
|---|---|---|---|---|
| `EXTEST` | `0000` | `0x0` | boundary (76) | **driven from the update flops** |
| `SAMPLE` / `PRELOAD` | `0001` | `0x1` | boundary (76) | functional / transparent |
| `IDCODE` | `0010` | `0x2` | ID register (32) | functional |
| `CLAMP` | `0011` | `0x3` | BYPASS (1) | **driven from the update flops** (§9.6) |
| `BYPASS` | `1111` | `0xF` | BYPASS (1) | functional |
| *(HIGHZ — do not use)* | `0100` | `0x4` | BYPASS (1) | **bidir + open-drain tri-stated** (§9.5) |
| all other codes | — | — | BYPASS (1) | functional |

`INSTRUCTION_CAPTURE` = `0001`. On Test-Logic-Reset the instruction resets to
**IDCODE**. Sources: `src/rtl/bscan/INTERFACE_CONTRACT.md` §4,
`verif/bscan/tb_bscan_gate.sv:69–74`,
`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:204–218`.

---

## 11. Full chain reference — 76 cells

Derived from `src/rtl/bscan/pad_table.json` by
`src/rtl/bscan/INTERFACE_CONTRACT.md` §6: **TDI enters the cell of the pad with the
lowest `ring_index`**, TDO leaves the highest, and within one pad the order from TDI
is `control → data → observe`. **BSDL numbers cells the other way round — 0 nearest
TDO** — so `BSDL = 75 − chain`.

`verif/bscan/run_gate.sh` re-derives its own copy of these indices from the pad table
on every run and refuses to compile if any has drifted, and
`scripts/bscan_bsdl_crosscheck.py` confirmed **76 of 76 register positions match by
pad and role against the routed netlist** — the chain *order* survived place and
route, not merely its length (commit `6c82edb`).

**Use the BSDL column when talking to a tool. Use the chain column when reading RTL,
netlist instance names or bench code.**

| chain (TDI=0) | BSDL (TDO=0) | pad | kind | cell role | side |
|---:|---:|---|---|---|---|
| 0 | 75 | `NRST` | input | observe | top |
| 1 | 74 | `SWDCK` | input | observe | top |
| 2 | 73 | `CLK` | input | observe | top |
| 3 | 72 | `TEST` | input | observe | top |
| 4 | 71 | `SE` | input | observe | top |
| 5 | 70 | `SWDIO` | bidir | control | top |
| 6 | 69 | `SWDIO` | bidir | data | top |
| 7 | 68 | `SWDIO` | bidir | observe | top |
| 8 | 67 | `HOSTIO4_P1[6]` | bidir | control | right |
| 9 | 66 | `HOSTIO4_P1[6]` | bidir | data | right |
| 10 | 65 | `HOSTIO4_P1[6]` | bidir | observe | right |
| 11 | 64 | `HOSTIO4_P1[5]` | bidir | control | right |
| 12 | 63 | `HOSTIO4_P1[5]` | bidir | data | right |
| 13 | 62 | `HOSTIO4_P1[5]` | bidir | observe | right |
| 14 | 61 | `HOSTIO4_P1[4]` | bidir | control | right |
| 15 | 60 | `HOSTIO4_P1[4]` | bidir | data | right |
| 16 | 59 | `HOSTIO4_P1[4]` | bidir | observe | right |
| 17 | 58 | `HOSTIO4_P1[3]` | bidir | control | right |
| 18 | 57 | `HOSTIO4_P1[3]` | bidir | data | right |
| 19 | 56 | `HOSTIO4_P1[3]` | bidir | observe | right |
| 20 | 55 | `HOSTIO4_P1[2]` | bidir | control | right |
| 21 | 54 | `HOSTIO4_P1[2]` | bidir | data | right |
| 22 | 53 | `HOSTIO4_P1[2]` | bidir | observe | right |
| 23 | 52 | `HOSTIO4_P1[1]` | bidir | control | right |
| 24 | 51 | `HOSTIO4_P1[1]` | bidir | data | right |
| 25 | 50 | `HOSTIO4_P1[1]` | bidir | observe | right |
| 26 | 49 | `HOSTIO4_P1[0]` | bidir | control | right |
| 27 | 48 | `HOSTIO4_P1[0]` | bidir | data | right |
| 28 | 47 | `HOSTIO4_P1[0]` | bidir | observe | right |
| 29 | 46 | `RMII_CRS_DV` | input | observe | right |
| 30 | 45 | `RMII_MDIO` | bidir | control | right |
| 31 | 44 | `RMII_MDIO` | bidir | data | right |
| 32 | 43 | `RMII_MDIO` | bidir | observe | right |
| 33 | 42 | `RMII_TX_EN` | output | data | right |
| 34 | 41 | `RMII_TXD[1]` | output | data | right |
| 35 | 40 | `RMII_TXD[0]` | output | data | right |
| 36 | 39 | `RMII_RXD[1]` | input | observe | right |
| 37 | 38 | `RMII_RXD[0]` | input | observe | right |
| 38 | 37 | `RMII_REF_CLK` | input | observe | right |
| 39 | 36 | `RMII_MDC` | output | data | right |
| 40 | 35 | `QSPI_nCS` | output | data | bottom |
| 41 | 34 | `QSPI_SCLK` | output | data | bottom |
| 42 | 33 | `QSPI_IO[3]` | bidir | control | bottom |
| 43 | 32 | `QSPI_IO[3]` | bidir | data | bottom |
| 44 | 31 | `QSPI_IO[3]` | bidir | observe | bottom |
| 45 | 30 | `QSPI_IO[2]` | bidir | control | bottom |
| 46 | 29 | `QSPI_IO[2]` | bidir | data | bottom |
| 47 | 28 | `QSPI_IO[2]` | bidir | observe | bottom |
| 48 | 27 | `QSPI_IO[1]` | bidir | control | bottom |
| 49 | 26 | `QSPI_IO[1]` | bidir | data | bottom |
| 50 | 25 | `QSPI_IO[1]` | bidir | observe | bottom |
| 51 | 24 | `QSPI_IO[0]` | bidir | control | bottom |
| 52 | 23 | `QSPI_IO[0]` | bidir | data | bottom |
| 53 | 22 | `QSPI_IO[0]` | bidir | observe | bottom |
| 54 | 21 | `TL_RX[0]` | input | observe | left |
| 55 | 20 | `TL_RX[1]` | input | observe | left |
| 56 | 19 | `TL_RX[2]` | input | observe | left |
| 57 | 18 | `TL_RX[3]` | input | observe | left |
| 58 | 17 | `TL_CLK_RX` | input | observe | left |
| 59 | 16 | `TL_RX[4]` | input | observe | left |
| 60 | 15 | `TL_RX[5]` | input | observe | left |
| 61 | 14 | `TL_RX[6]` | input | observe | left |
| 62 | 13 | `TL_RX[7]` | input | observe | left |
| 63 | 12 | `I2C_SCL` | opendrain | control | left |
| 64 | 11 | `I2C_SCL` | opendrain | observe | left |
| 65 | 10 | `I2C_SDA` | opendrain | control | left |
| 66 | 9 | `I2C_SDA` | opendrain | observe | left |
| 67 | 8 | `TL_TX[0]` | output | data | left |
| 68 | 7 | `TL_TX[1]` | output | data | left |
| 69 | 6 | `TL_TX[2]` | output | data | left |
| 70 | 5 | `TL_TX[3]` | output | data | left |
| 71 | 4 | `TL_CLK_TX` | output | data | left |
| 72 | 3 | `TL_TX[4]` | output | data | left |
| 73 | 2 | `TL_TX[5]` | output | data | left |
| 74 | 1 | `TL_TX[6]` | output | data | left |
| 75 | 0 | `TL_TX[7]` | output | data | left |

---

## 12. Not established — do not fill these in from memory

Every item here is a real gap. None of them is "probably fine".

- **Maximum TCK frequency.** Not characterised. The BSDL's 10.0 MHz is explicitly a
  placeholder (`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:195`); the gate bench's
  20 MHz is a zero-delay simulation number. Start ~1 MHz.
- **Any timing property at all.** The gate run is zero-delay
  (`+nospecify +notimingcheck`) against an **older cell revision** than the Liberty
  the design was timed with. An SDF-annotated run is a separate exercise and a
  separate claim (`verif/bscan/README.md`, "Two further caveats").
- **Behaviour on silicon.** Nothing here has been run on a die.
- **Whether the 256-cycle `CLK` warm-up is necessary**, or merely what the bench
  happens to do.
- **Behaviour with the functional clock left running.** The bench supports `+clk` but
  no result is quoted for it; all 7/7 results are with the clock parked.
- **CLAMP.** Implemented and declared, exercised by neither bench.
- **HIGHZ's actual effect on silicon.** Decoded by the RTL, not declared in the BSDL,
  exercised by neither bench.
- **The compute chiplet's TAP**, and whether a two-die scan chain exists or in what
  order. Separate repository.
- **The cross-die D2D lane mapping** (`TL_TX[n]` → which far-die `TL_RX`).
- **Which board pull-ups exist.** The bench models them; your board is your board.
  The two I²C pull-ups are required by the design, not optional.
- **The I²C-parks-low hazard as a simulated case.** The reset value and the pad
  polarity are read from `src/rtl/bscan/bscan_cell.sv` and
  `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`; the gate bench avoids the
  state rather than demonstrating it.
- **Whether `SE = 1` is inert inside the SoC on *this* build.** The
  `UNCONNECTED2828` / no-scan-chain verification was against the pre-boundary-scan
  `full-20260814` netlist.
- **Bond/pin numbers.** All `TBD_*`.

---

## 13. Sources

Every claim above traces to one of:

| | |
|---|---|
| `src/rtl/bscan/INTERFACE_CONTRACT.md` | pin strategy (§7), cell counts (§1), instruction map (§4), chain order (§6) |
| `src/rtl/bscan/pad_table.json` | the 48 pads, ring order, `oe_inv`, the 76-cell derivation |
| `src/rtl/bscan/bscan_cell.sv`, `bscan_ir.sv`, `nanosoc_eth_chiplet_bscan.sv` | reset values, opcode decode, HIGHZ override |
| `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v` | the `SE` mux, pad `OEN` polarities, the I²C tie-low |
| `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl` | tester-visible declarations, opcodes, deviations, `DESIGN_WARNING` |
| `verif/bscan/README.md`, `tb_bscan_gate.sv`, `build_gate/sim.log` | the measured gate-level results, the TDI sequencing trap, the BYPASS TDI-timing trap, the diagnoses |
| `scripts/gen_bscan.py`, `scripts/bscan_bsdl_crosscheck.py` | why HIGHZ is not declared; the BSDL-vs-netlist cross-check |
| `docs/design/PIN_MAP.md` | the 18 D2D pads, the I²C sideband's role |
| `docs/bscan/IDCODE_DECISION.md` | the IDCODE and what it does and does not tell a tool |

Line numbers were verified against the working tree on branch
`feat/padring-boundary-scan` on 2026-08-20.
