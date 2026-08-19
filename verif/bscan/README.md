# `verif/bscan` — IEEE 1149.1 boundary-scan verification

Self-checking VCS bench for `nanosoc_eth_chiplet_bscan`, the boundary-scan
wrapper that sits between the SoC core and the 48-pad chiplet padring. Written
against `src/rtl/bscan/INTERFACE_CONTRACT.md` and `src/rtl/bscan/pad_table.json`,
not against the RTL.

```
source ../../set_env.sh
./run.sh                       # ~6 s, exit 0 = pass
```

| file | what it is |
|---|---|
| `run.sh` | the gate. Regenerates the pad header, compiles, runs, and decides whether the bench's verdict is allowed to mean anything. |
| `tb_bscan.sv` | the bench. 11 tests, ~40,000 comparisons. |
| `gen_tb_pads.py` | emits `build/tb_bscan_pads.svh` from `pad_table.json`: signal arrays, DUT instantiation, chain map. Also carries the **static** half of the open-drain rule. |
| `build/` | destroyed and rebuilt on every run (gitignored). |

Exit codes: `0` pass · `1` test failure · `2` setup problem (no RTL, generator
refused, no VCS) · `3` compile failure.

Useful env / args:

```
BSCAN_RTL_DIR=<dir>     run against another tree (default src/rtl/bscan)
BSCAN_BUILD=<dir>       relocatable output, so two lanes cannot collide
BSCAN_MIN_CHECKS=<n>    comparison floor (default 30000)
./run.sh +seed=7                       # different random stimulus
./run.sh +idcode=100005a1              # expect a different IDCODE
./run.sh +nrand=2                      # short debug run — WILL trip the floor, by design
```

---

## Why the port names are not written down here

`nanosoc_eth_chiplet_bscan` is generated, and its port list is 152 pad ports
wide. A TB that hand-wrote the matching connections would be a second,
independently wrong copy of the pad table: the first time a pad moved it would
either fail to compile or — far worse — silently test the wrong ring order.

So the bench body is written generically over arrays indexed by **ring order**,
and `gen_tb_pads.py` emits the one file that knows names. One table, one
derivation. It also **auto-detects the naming convention** from the wrapper's
actual ports (see ambiguity #3 below), and refuses to emit a header at all if
any expected port is missing — a clear message beats 150 elaboration errors.

Two index spaces, and they are easy to confuse:

* **pad index** `0..47` — ring order, ascending `ring_index`, i.e. the order TDI
  meets the pads.
* **chain index** `0..75` — TDI-first: cell 0 is the one TDI enters, cell 75 the
  one TDO leaves. Within a pad: `oe ctl → data ctl → obs`.
  **BSDL numbers these the other way round** (0 nearest TDO), per contract §6.

`18×1 + 15×1 + 13×3 + 2×2 = 76`.

## Timing discipline — no `#` races

TMS/TDI are driven on the **falling** edge of TCK, exactly as a TAP master
drives them; the DUT samples them on the rising edge. TDO — and, where a
cycle-accurate view is needed, `pad_out`/`pad_oe` — are read through clocking
block `cb` with a `#1step` (preponed) input skew at the rising edge: the value
the DUT held for the whole of that cycle.

That sample point is correct **whether or not** the wrapper retimes TDO onto the
falling edge. If it does (1149.1 style, which the current RTL does), the
preponed value at posedge *k* is what the negedge flop loaded. If it drove TDO
combinationally from the shift flop, the preponed value at posedge *k* is the
flop content set at posedge *k-1* — the same bit. Neither races.

The only `#` in a checking path is `COMB_SETTLE = 1ns`, used in T1/T7/T8 where
there is deliberately **no** clock edge to synchronise to. It is a settle for a
purely combinational, clockless path, parked 4 ns clear of any TCK edge. T1 goes
further and runs a batch of vectors with TCK **stopped dead**, which is the only
way to prove the functional path is not accidentally clocked.

---

## What each test proves

| # | test | what it proves |
|---|---|---|
| **T1** | **functional transparency, `trst_n=0`** | **The chip still works.** 200 random vectors on every `*_core_out`/`*_core_oe`/`*_pin_in`, plus all-0/all-1 corners, plus 32 vectors with **TCK stopped**. `pad_out`/`pad_oe`/`core_in` must follow combinationally and bit-exact, while TMS/TDI wiggle randomly (a disabled TAP must be unwakeable). Also: `tdo_oe` must stay 0 — TDO is muxed onto the bonded `HOSTIO4_P1[1]` driver (contract §7), so a stuck enable is pad contention. 76 signal comparisons per vector. |
| **T2** | TAP reset | From **Pause-DR** (deliberately awkward), 5×TMS=1 reaches Test-Logic-Reset, and the instruction is IDCODE afterwards. BYPASS is loaded first, so "the DR is now 32 bits of IDCODE" can only be explained by a real reset. Also checks Capture-IR loads `…01` (1149.1 mandatory). |
| **T3** | IDCODE shift-out | Shifts **64** bits, not 32: the first 32 are the captured IDCODE (compared bit-exact, LSB asserted to be 1, version nibble checked separately); the second 32 must echo what we shifted in, which proves the ID register is a real 32-stage shift register and not a constant muxed onto TDO. |
| **T4** | BYPASS | 24 bits through the bypass stage. Capture-DR must load 0, every bit must reappear delayed by **exactly** one TCK, and the output must not equal the input (a zero-delay bypass). |
| **T5** | chain integrity / length | (a) A 76-bit PRBS followed by 96 more bits, then a **search over every alignment 1..96** for where the pattern re-emerges. Demands **exactly one** match, **at 76**. Asserting only "it comes back at 76" is weak — that passes for a 75-cell chain too if you only look at offset 76. (b) A walking-1 through all 76 positions (5,776 bit comparisons), which catches a single stuck or crossed cell. |
| **T6** | SAMPLE | 6 random vectors. Every one of the 76 cells is checked **individually** against what it should have captured — `pin_in` for obs, `core_out` for data ctl, `core_oe` for oe ctl — at its exact position in the shift-out stream. This is the test that pins the **ring order**; a mismatch names the pad, the cell kind and the chain index. |
| **T7** | EXTEST drive | Preload a pattern that differs from the functional value on **every** controllable pad. While still in SAMPLE_PRELOAD the pads must not move at all (PRELOAD that disturbs a live system is a hazard). After loading EXTEST, all 43 driven signals must come from the update flops; then a **fresh random core vector** is driven and the pads must not move — the core is ignored. `core_in` must still follow `pin_in` (INTEST is not supported). Leaving EXTEST via TLR must hand the pads straight back. |
| **T8** | open-drain safety | Contract §1, the cross-die-short guard. Structural: each I²C pad contributes exactly 2 cells, an obs and an oe ctl, and **no data cell**, and owns no `core_out`/`pad_out` port group. Dynamic: two EXTEST preloads differing **only** in the I²C obs bits must leave `pad_oe` identical (the observe cell has no drive path), and inverting only the oe bits must flip it. The **absence of the ports** is gated statically — see below. |
| **T9** | TAP hygiene | `tdo_oe` walked through all 16 states: 1 in Shift-IR/Shift-DR only. Matters because TDO shares a functional output driver. |
| **T10** | "exactly five" | Completes T2 with the only observable that can tell a real TLR from four TMS=1: with EXTEST active the pads are driven from the update flops, and TLR drops `mode`. After 0,1,2,3,**4** TMS=1 the pads must still be driven; after the **5th** they must be released. No DR/IR read can show this, because every route back to a DR read passes through TLR itself. Parks in **Pause-DR**, not Shift-DR — Pause-DR is equally 5 steps from TLR but holds the chain still, whereas in Shift-DR the first TMS=1 tick is itself a shift cycle and Update-DR would then load a shifted pattern for reasons that have nothing to do with the reset. |
| **T11** | closing state | `trst_n` back low: pads transparent, `tdo_oe` low. Leaves the bench in the state the chip ships in. |

### The half of T8 that cannot live in the testbench

A running TB **cannot see a port it does not connect** — an extra port on a
named-port instantiation is legal and silent. So "there is no data path on the
I²C pads" is enforced statically by `gen_tb_pads.py`, which scans the whole
wrapper (ports *and* internal nets) for `I2C_SCL_pad_out` / `I2C_SCL_core_out` /
`I2C_SDA_*` under every candidate naming convention and **exits 2**, stopping
`run.sh` before compile. Verified both ways: a wrapper that treats the I²C pads
as `bidir` is rejected by the generator *and*, if forced through, fails T5
(78 cells), T6, T7, T8 and T10.

Note this is the *wrapper*'s half of the rule. The padring's half — that `.I`
remains a structural tie-low on `uPAD_I2C_SCL`/`uPAD_I2C_SDA` — is
`scripts/check_chip_boundary.py`'s job (contract §1) and is not re-checked here.

### Why the verdict is not just `$?`

`simv` exits 0 on `$finish` whatever the bench decided, so the simulation's exit
code says nothing about the design. The failure modes that actually happen are
the silent ones. `run.sh` therefore requires all four of:

1. the machine-readable `BSCAN_SUMMARY:` line **exists** — a run that vanished
   cannot be a pass;
2. `fails=0` and the verdict is `PASS`;
3. `tests=N/N` with `N ≥ 11` — every test ran;
4. `checks` ≥ `BSCAN_MIN_CHECKS` (default 30,000; a full run is 40,136) — *a
   zero that measured nothing is not a zero*. Demonstrated: `./run.sh +nrand=2`
   reports `PASS checks=9842 fails=0 tests=11/11` and the gate **fails it**.

The bench also carries a 50 ms sim-time watchdog that prints a `FAIL` summary,
and `run.sh` treats a wall-clock kill as a failure. The build directory is
destroyed on every run — there is no incremental mode, because VCS will happily
re-run yesterday's `simv`.

---

## Mutation tests

A gate is only real if it can fail. Every mutation below is a **single-line**
change; all were applied to a scratch copy of the RTL and run through `./run.sh`
(the repository RTL was never modified). Column 3 is measured, not predicted.

| # | file | single-line mutation | caught by |
|---|---|---|---|
| M1 | `bscan_cell.sv` | `assign func_out = update_q;` (drop the `mode ?` mux) | **T1**, T7, T10, T11 |
| M2 | `bscan_cell.sv` | insert a flop: `func_out = mode ? update_q : fr;` where `fr` is `func_in` registered on `tck` | **T1**, T11 |
| M3 | wrapper | `assign NRST_I_core_in = 1'b0;` (break one observe path to the core) | **T1**, T11 |
| M4 | wrapper | `assign SWDIO_IO_pad_oe = … ~SWDIO_IO_pad_oe_int;` (fold the OE polarity into the wrapper) | **T1**, T7, T10, T11 |
| M5 | wrapper | `assign tdo_oe = 1'b1;` | T1, **T9**, T11 |
| M6 | `bscan_tap.sv` | `ST_SEL_IR : state_d = tms ? ST_SEL_DR : ST_CAP_IR;` (the only TMS entry to TLR) | **T2**, T3, T4, T5, T6, T7, T8, T9, T10 |
| M7 | wrapper | `wire ir_trst_n = trst_n;` + drop `~tlr` from `bsr_mode` (TLR no longer resets the instruction) | **T2**, T3, T7, **T10** |
| M8 | wrapper | `IDCODE_VALUE = 32'h1000_05A0` (LSB 0) | T2, **T3** |
| M9 | wrapper | `IDCODE_VALUE = 32'h1_0000_05A1` — the literal the contract prints, i.e. ambiguity #1 | T2, **T3** |
| M10 | wrapper | `bypass_q <= 1'b1;` on Capture-DR | **T4** |
| M11 | wrapper | add a second stage to the bypass path | **T4** |
| M12 | wrapper | bypass one boundary cell (`.si(bsr_chain[1])`, `.so()`) — chain becomes 75 | **T5**, T6, T7, T8, T10 |
| M13 | generator | treat the two open-drain pads as `bidir` — chain becomes 78 | `gen_tb_pads.py` (**exit 2**); forced through: T5, T6, T7, **T8**, T10 |
| M14 | wrapper | swap two neighbouring obs cells' `pin_in` (ring order) | **T6** |
| M15 | `bscan_cell.sv` | `wire dr_d = shift_dr && si;` (obs cell captures 0) | **T6** |
| M16 | `bscan_cell.sv` | `else if (1'b0) update_q <= dr_q;` (update flop never loads) | **T7**, T8, T10 |
| M17 | wrapper | add `I2C_SCL_core_out`/`I2C_SCL_pad_out` and wire them | `gen_tb_pads.py` (**exit 2**) |

### What this bench deliberately does **not** prove

* **Shift-vs-capture priority inside a cell.** The contract says shift wins.
  With a conforming TAP, `capture_dr` and `shift_dr` are never both high, so the
  priority is unobservable — a mutation that swaps them passes, and should. It
  is a synthesis-QoR property (one mux-D flop), not a behavioural one.
* **HIGHZ and CLAMP.** Decoded by `bscan_ir` per contract §4 and implemented in
  the wrapper (`bsr_highz`), but outside the eight tests this bench was scoped
  to. `run.sh` will not catch a broken HIGHZ.
* **The padring side of the open-drain rule** — see above.
* **BSDL.** Contract §6 requires the generator to emit RTL and BSDL from one
  ordering. This bench pins the RTL ordering (T5/T6); nothing here reads the BSDL.
* **Anything post-synthesis.** RTL only.

---

## Contract ambiguities

Raised, not silently resolved. Nothing in `src/rtl/` was changed by this work.

1. **The IDCODE literal is a 36-bit constant truncated into 32 bits.** §5 says
   *"version 1, part `0x0000`, manufacturer `0x2D0>>1`"* over placeholder base
   `32'h0000_05A1`, and then prints
   `parameter logic [31:0] IDCODE_VALUE = 32'h1_0000_05A1;`. That literal has
   **nine** hex digits; SystemVerilog truncates it to `32'h0000_05A1` and the
   **version nibble is silently lost**. The intended value is
   **`32'h1000_05A1`** for the netlist vintage under test, which is what this
   bench expects (override with `+idcode=`). **The RTL as landed has since moved
   to `32'h1000_1001`** — commit `61aa090`, because `0x2D0` turned out to be
   JEDEC bank 6 code 0x50, assigned to Neterion Inc, so the die was
   impersonating a real company. The netlist in `build/bscan-probe` predates
   that fix and still answers the old value; rebuild it and this bench's default
   becomes correct again. The
   contract text should be fixed before anyone regenerates from it. (The prose
   is also confusing: `0x5A1 >> 1 = 0x2D0` is the 11-bit manufacturer field, so
   "manufacturer `0x2D0>>1`" reads one shift too many.)
   **And the substantive point stands: SoC Labs has no JEDEC manufacturer ID.
   `0x2D0` is a placeholder and must be assigned before tapeout.**

2. **Nothing in the contract lets the instruction register reset on entering
   Test-Logic-Reset.** IEEE 1149.1 requires TLR to force the instruction to
   IDCODE. But §4's `bscan_ir` port list has **no `tlr` input** — only `trst_n`
   — so a module built to the letter of §4 cannot do it. §3 gives the TAP a
   `tlr` output with no stated consumer, which strongly implies the wrapper is
   meant to gate the IR's reset with it (`ir_trst_n = trst_n & ~tlr`). That is
   what the landed RTL does, and T2/T10 pass. It should be stated in §3/§4
   rather than inferred, because a regenerated wrapper that drops it fails
   1149.1 and this bench (M7).

3. **§6 never says what `P` is.** *"For every pad P: `P_pin_in` …"* — but the
   pad table offers three candidates: `pad` (`HOSTIO4_P1[6]`, not a legal
   identifier; flattened, `HOSTIO4_P1_6`), `inst` (`uPAD_HOST_IO_6`), and
   `inst` minus the `uPAD_` prefix (`HOST_IO_6`). Rather than guess,
   `gen_tb_pads.py` defaults to the flattened pad name and **auto-detects** the
   convention from the wrapper when it exists. The landed RTL uses
   **`inst`-minus-`uPAD_`** (`NRST_I_pin_in`, `SWDIO_IO_pin_in`, `HOST_IO_6_pin_in`),
   which for the I²C pads happens to coincide with the pad name (`I2C_SCL_pin_in`).
   Worth pinning in §6 — a BSDL consumer will care.

4. **§6 does not say whether `oe_inv` is folded into the wrapper.** The pad table
   carries `oe_inv` per pad (true for all 13 bidirs, false for the two
   open-drains), and §6 says `P_pad_oe` goes "to the pad's OEN logic". §2b's
   `func_out = mode ? update_q : func_in` has no inversion, so this bench asserts
   `pad_oe === core_oe` in the transparent case, i.e. **the inversion stays
   outside the wrapper, in the padring**. That matches the landed RTL. If a
   future generator folds it in, T1 fails loudly (M4) — which is the right
   outcome for an unstated assumption, but the assumption should be written down.

5. **§3 does not say when TDO changes.** 1149.1 mandates the falling edge; §2
   describes `so` as combinational from the shift flop and §3 lists no TDO
   retiming flop. The bench is written to be correct either way (see "Timing
   discipline"). The landed RTL retimes on the negedge, which is right.

6. **§1's cell counts make HIGHZ non-conformant, and the contract does not say
   so.** §1 gives a plain `output` pad 1 ctl cell and no OE cell — standard, and
   it is what makes the chain 76 — but it means the 15 plain outputs have **no
   output-enable cell to tri-state**, so `HIGHZ` cannot do what 1149.1 says it
   does. The landed RTL applies HIGHZ as a wrapper-level override downstream of
   each OE cell and documents the deviation in its own header, including in the
   BSDL. That is the right call; the point here is that the contract states the
   cell counts and the HIGHZ instruction independently and never notes that the
   first makes the second partial. Worth adding to §1 or §4, because the next
   person to regenerate from §1 will not re-derive it. (This bench does not
   exercise HIGHZ or CLAMP — see "What this bench deliberately does not prove".)

---

# Gate-level — the same TAP, shifted through the routed netlist

Everything above tests `nanosoc_eth_chiplet_bscan` as RTL, at its 152 wrapper
ports. This section is a second bench that tests the **routed netlist of the
whole chip**, contacted at its **48 package pads and nowhere else**.

```
source ../../set_env.sh
./run_gate.sh                  # ~85 s, exit 0 = pass
```

| file | what it is |
|---|---|
| `run_gate.sh` | the gate. Re-derives the chain map, refuses a netlist that shadows the cell library, PG-completes a copy, compiles, runs, and decides whether the verdict may mean anything. |
| `tb_bscan_gate.sv` | the bench. 7 tests, 5,063 comparisons, 4,418 TCK cycles. |
| `build_gate/` | destroyed and rebuilt on every run (gitignored). |

Exit codes and the env-var conventions match `run.sh`: `0` pass · `1` test
failure · `2` setup problem · `3` compile failure;
`BSCAN_GATE_NETLIST`, `BSCAN_GATE_BUILD`, `BSCAN_GATE_MIN_CHECKS`,
`BSCAN_GATE_TIMEOUT`, `VCS`, and extra args passed through to `simv`
(`./run_gate.sh +seed=7 +idcode=10001001 +clk`).

## The DUT and the contact surface

`ASIC/eth-chiplet/build/bscan-probe/outputs/nanosoc_eth_chiplet_pads_pnr.v`,
top `nanosoc_eth_chiplet_pads` — 42 MB, ~200 k instances, post-place, post-CTS,
post-route. **There are no hierarchical references into the design anywhere in
`tb_bscan_gate.sv`.** A probe at `u_dut…u_bsc_75_TL_TX_7_data_update_q` would
prove the flop exists; it would not prove it is reachable from the package.

The TAP is reached exactly as contract §7 says a bench-top JTAG master reaches
it: `SE=1` releases `trst_n`, `SWDCK`→TCK, `SWDIO`→TMS, `HOSTIO4_P1[0]`→TDI,
`HOSTIO4_P1[1]`←TDO. **`NRST` is held low for the whole run and the functional
clock is parked** after a 256-cycle warm-up in reset. Boundary scan exists to
test a chip that will not boot, so this bench never lets the core be alive:
everything that appears on a pad in EXTEST came out of an update flop clocked by
TCK, and nothing in the core could have produced it.

`HOSTIO4_P1[1]` is deliberately left with **no pull-up**, unlike every other
bidir. An un-enabled TDO is then a real `z`, so "TDO is driven" and "TDO reads
0" are distinguishable and every tick carries a free 1149.1 enable check (T6).

## Two traps that had to be measured, not assumed

**1. `..._pnr_pg.v` cannot be simulated as written, and fails silently.**
The same P&R run writes the routed netlist twice. The `_pg` variant carries
supply pins on every instance — and, because Innovus wrote it with
`-write_supply0_supply1`, it *also opens with 375 empty module declarations for
library cells* (`module BUFFD1 (I,Z,VSS,VDD); … endmodule`, no body). Given to
VCS after the vendor library, each one **overrides the real model**. Measured
here 2026-08-19: VCS reports it only as `Warning-[OPD]`, 375 times, then
compiles, elaborates, links and runs — and the entire design simulates as `z`,
every pad reads `z`, and the bench reports 52 failures that say nothing about
the design at all. It is the cleanest instance of *a zero that measured nothing*
this bench could have produced.

Counted, both files, against the two libraries actually compiled:

| file | modules | that shadow a library cell |
|---|---:|---:|
| `..._pnr.v` | 3064 | **0** |
| `..._pnr_pg.v` | 3449 | **375** |

`run_gate.sh` step 2 now refuses **any** netlist that shadows a library cell,
by name, against the libraries in that run's own compile line — so the trap
cannot be re-entered by pointing `BSCAN_GATE_NETLIST` somewhere else.

**2. The plain netlist needs PG completion, and it is a declared deviation.**
`..._pnr.v` writes 186,490 instances with `.VDD()/.VSS()` and 18,833 without —
and the 18,833 are everything P&R inserted, i.e. the whole clock-tree buffering
(`CKBD0` ×5551, `CKBD1` ×4052) that TCK itself travels through. Against the
power-aware library, an unconnected supply routes that cell's output through the
`u_power_down` UDP (`? x ? : x`) and it drives X. So `run_gate.sh` runs the
toolkit's own transform, `flow/verify/gls/pg_complete.py`, over a **copy** in
`build_gate/` (`ASIC/` is never written) and simulates the copy — the same file
`ASIC/gls-netlist`'s `fp1505_cc` item simulates, and the configuration that
already boots CPU1 out of a mask ROM. **The file simulated is therefore not
byte-identical to the file being taped out**; `build_gate/pg_dut.txt` names
every instance touched. A zero from that transform is refused, because
`pg_complete.py` returns a cheerful 0 when it resolved no cells: on this netlist
the answer is 18,833.

Two further caveats travel with any result quoted from this gate:

* the simulation Verilog for both libraries is an **older cell revision** than
  the Liberty the design was timed against, so this is a **functional** check
  and says nothing about timing closure;
* it is a **zero-delay** run (`+nospecify +notimingcheck`). `..._pnr.sdf`
  (362 MB) sits beside the netlist; an SDF-annotated run is a separate exercise
  and a separate claim.

## The chain map, and why it is hard-coded here

At the package there is no generated header to hand the bench names — the DUT is
a netlist with 48 pins. So `tb_bscan_gate.sv` carries the chain indices it
checks as literals, derived from `pad_table.json` by contract §6, and
`run_gate.sh` **re-derives all of them on every run** (`OUT_CELL`, `IN_CELL`,
`BIDIR_OE_CELL`, `I2C_OE_CELL`, `QSPI_OE_CELL`, `QSPI_DATA_CELL`, `N_CELLS`,
and the 15 pad names `out_name()` prints) and refuses to compile if any has
drifted. Verified both ways: perturbing one index, or one printed pad name,
stops the run with exit 2 and names the disagreement.

The OE polarities in that map are not decoration. The 13 bidirs take
`OEN = ~pad_oe`, so **0** tri-states them; the two open-drain I²C pads take
`OEN = pad_oe` **directly** (contract §1, the wired-AND rule), so **1**
tri-states those. Every EXTEST preload this bench builds starts from
`safe_chain()`, which sets each OE cell to the value that releases its pad —
getting that backwards would put a 16 mA push-pull driver onto a wired-AND bus.

## What each test proves

| # | test | what it proves |
|---|---|---|
| **T0** | `SE=0`: the TAP is inert | 40 Shift-DR cycles driven at a chip whose `SE` is low must not move `HOSTIO4_P1[1]`. `trst_n = SE`, so a TAP that answered would have taken a bonded functional output driver. |
| **T1** | **TAP reset + IDCODE** | BYPASS is loaded first, then the TAP is parked in **Pause-DR** and given 5×TMS=1, so "the DR is now 32 bits of IDCODE" can only be explained by a real Test-Logic-Reset. **64** bits are shifted, not 32: the first 32 are the ID (compared bit-exact against `32'h1000_05A1`, LSB asserted to be 1, version nibble checked separately), the second 32 must echo TDI — which proves a real 32-stage shift register rather than a constant sat on TDO. Capture-IR is checked to load `…01`. |
| **T2** | BYPASS | 32 bits. Capture-DR must load 0, every bit must reappear delayed by **exactly** one TCK, and it must be neither zero- nor two-stage. See the note below on what makes the zero-stage case visible at all. |
| **T3** | chain length == **76** | A 76-bit PRBS followed by 96 more bits, then a **search over every alignment 1..96**, demanding **exactly one** match, **at 76**. Three independent patterns. Asserting only "it comes back at 76" is weak — that passes for a 75-cell chain too, if the loop never looks anywhere else. |
| **T4** | SAMPLE | The 16 reachable input-pad obs cells are checked **individually** at their own positions in the shift-out stream over four vectors (all-0, all-1, two random), and then a **per-pin walk**: driving one pin must move exactly one cell, and it must be that pin's own. The vector loop alone can be slipped past by two swapped neighbours; the walk cannot. |
| **T5** | **EXTEST drive** | Preload P → EXTEST → all 15 output pads read P; then ~P → all 15 read ~P; then a **walking-1 through all 15**. Doing both polarities is what makes this impossible to pass by accident — with the core dead a stuck pad reads the same thing whatever is loaded. Also: PRELOAD under SAMPLE_PRELOAD must move **no** pad; the drive must survive 200 ns of idle TCK; the **OE cells** must reach the real pad OEN logic (`QSPI_IO` driven to `4'b1010`, then released to the bench's pull-ups); and Test-Logic-Reset must hand the pads back. |
| **T6** | TDO enable hygiene | Accumulated over all 4,372 ticks taken with `SE=1`: TDO driven in Shift-IR/Shift-DR, tri-state everywhere else. TDO shares the bonded `HOSTIO4_P1[1]` driver, so a stuck enable is pad contention on a real board. |

### Why T2 moves TDI after the rising edge

1149.1 specifies TDI only **at the rising edge** of TCK, and TDO is retimed onto
the **falling** edge. A bench that holds TDI steady across the high phase
therefore **cannot tell a BYPASS flop from a plain wire**: the retiming flop
supplies the one cycle of delay on its own, and a zero-stage bypass produces a
bit-identical TDO stream. This was measured, not reasoned — mutation M4b below
passed T2 until the bench started moving TDI 10 ns after the rising edge, which
is legal for a master and invisible to anything that samples TDI where it should.

## Mutation tests — measured, on the netlist

A gate is only real if it can fail. Each mutation below is a **single-token**
edit applied to a **scratch copy** of the routed netlist and fed back through
`./run_gate.sh` with `BSCAN_GATE_NETLIST=` (`ASIC/` was never written, and no
RTL was touched). Column 3 is measured.

| # | single-token edit on `..._pnr.v` | caught by |
|---|---|---|
| M1 | `u_bsc_41_QSPI_SCLK_data_dr_q_reg .SI(bsr_chain[41])` → `.SI(bsr_chain[40])` — one boundary cell bypassed, chain becomes 75 | **T3** (`delay 75`, one alignment), T4, T5 |
| M2 | swap `.D(TL_RX_0_pin_in)` and `.D(TL_RX_1_pin_in)` — two neighbouring obs cells look at each other's pad | **T4 only** |
| M3 | `MUX2D0 g4795__4319 .I0(u_bsc_75_TL_TX_7_data_update_q)` → `.I0(TL_TX_7_core_out)` — one pad's mode mux never takes the update flop | **T5 only** |
| M4 | `MUX2ND0 g3124__8246 .I0(bypass_q)` → `.I0(tdi)` | **nothing — a genuine no-op.** That node is not on the observable path; recorded so the next reader does not repeat it |
| M4b | `AO31D1 g4794__6260 .A1(bypass_q)` → `.A1(tdi)` — the DR output takes TDI instead of the bypass flop, i.e. a zero-stage bypass | **T2 only** |
| M5 | `\idcode_q_reg[0]`: swap `.Q`/`.QN`, inverting the ID register's LSB | **T1 only** |

Four of the five required tests are discriminated by **exactly one** test each.

**T0 and T6 are not mutation-proven.** T6 did, unprompted, catch a real defect —
in this bench, not the design: one tick in T1 that leaves Shift-DR was tagged as
a non-shift cycle, and T6 reported `1 driven`. T0 would be proven by a mutation
that removes `bscan_en` from the `HOSTIO4_P1[1]` output mux; that gating is
spread over several gates in the netlist and no single-token edit was found for
it. Neither is one of the five tests this bench was commissioned to run.

## Why the verdict is not just `$?`

Same three-part rule as `run.sh`, for the same reason, and the first run of this
script is the argument for it: the `_pnr_pg.v` trap above produced a clean
compile, a clean elaboration, a clean link and a completed run over a design
that was entirely `z`. `run_gate.sh` requires the `BSCAN_GATE_SUMMARY:` line to
**exist**, to say `PASS` with `fails=0`, to report `tests=N/N` with `N ≥ 7`, and
to report `checks ≥ BSCAN_GATE_MIN_CHECKS` (default 4000; a full run is 5,063).

Read that last number honestly: **4,372 of the 5,063 are T6's per-tick enable
checks**, so the floor is in practice a "the bench reached the end" test rather
than a stimulus-depth test. The per-test work is gated by `tests=7/7`, and the
depth by the mutation table above. The bench also carries a 500 ms sim-time
watchdog that prints a `FAIL` summary, and `run_gate.sh` treats a wall-clock kill
as a failure. `build_gate/` is destroyed on every run.

## The IDCODE this bench expects belongs to the netlist

The netlist under test was built with `IDCODE_VALUE = 32'h1000_05A1` and answers
`32'h1000_05A1` — measured, T1. `src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv` has
since moved to `32'h1000_1001` (commit `61aa090`: `0x2D0` is Neterion's assigned
JEDEC ID and this project has none, so the placeholder was retired). Expecting
the RTL's new value against this netlist would turn a design that is answering
correctly into a red. `run_gate.sh` compares the two and prints both whenever
they differ; when a netlist built after `61aa090` arrives, run it with
`+idcode=10001001` and move the constant in the TB.

## What this bench deliberately does **not** prove

* **Timing.** Zero-delay, and against an older cell revision than the sign-off
  Liberty. It says the boundary register shifts. It says nothing about closure.
* **Functional transparency with `SE=0`.** At the package, with the core in
  reset, the transparent-mode value of a pad is not specified by anything —
  there is no core side to compare against. `tb_bscan.sv`'s T1 owns that
  property and is the reason it is the one test that matters there. T0 only
  proves the TAP is *inert*, not that the pads are *transparent*.
* **41 of the 76 cells are not individually observable from the package.** T5
  reaches the 15 plain-output data cells and the 4 `QSPI_IO` oe/data pairs; T4
  reaches 16 obs cells. The rest are covered only by T3, which proves they shift
  — not what they are connected to. `tb_bscan.sv`'s T6/T7 check all 76.
* **The open-drain I²C rule.** `safe_chain()` never drives those pads, by
  construction; the dynamic half of the rule is `tb_bscan.sv`'s T8 and the
  structural half is `scripts/check_chip_boundary.py`.
* **HIGHZ and CLAMP**, as above.
* **The `_pnr_pg.v` file itself.** It is refused, not fixed. If a future flow
  needs it, strip the 375 stub declarations first — and prove the strip worked
  by re-running the shadow check.

## One operational trap, found the hard way

`HOSTIO4_P1[0]` (TDI) is a **functional bidir whose driver the netlist's own
reset value enables**. A JTAG master that drives TDI onto it before `SE` goes
high is fighting a 16 mA output — the pad model prints `++BUS CONFLICT++` on
every TDI edge, which is exactly what this bench did until it was changed to
take that pin on `SE` and not a moment sooner. `SWDIO` (TMS) has no such problem:
reset leaves its driver tri-stated. That is a **board sequencing rule**, not a
bench detail: raise `SE` first, then drive TDI.
