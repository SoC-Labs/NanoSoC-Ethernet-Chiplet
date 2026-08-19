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
   **`32'h1000_05A1`**, which is what this bench expects (override with
   `+idcode=`). The RTL as landed uses `32'h1000_05A1` — correct — but the
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
