# 34 — Content gates for `gate1`: ROM bits and LEC, ready to run

> **Status — runbook, ready to run; the `gate1` run it was written for aborted in synthesis ([46](46-why-gate1-aborted.md)).** Commands were exercised on `full-20260814`; only `RUN` changes for a new build.

[← 33 Toolkit/legacy decoupling](33-toolkit-legacy-decoupling.md) · [index](00-index.md)

Two gates make a stream **verified** rather than merely produced: the boot ROMs
must hold the firmware *in the shipped GDS*, and the netlist that became that
GDS must be logically the netlist synthesis wrote. Both are prepared here so
they are minutes after `gate1` streams, not an afternoon.

> Everything below was measured on `full-20260814`. The commands are the same
> for `gate1`; only `RUN` changes.

---

## 1. ROM content, at the reticle

```sh
RUN=ASIC/eth-chiplet/build/gate1/outputs/nanosoc_eth_chiplet_pads.gds

python3 scripts/ci/rom_gds_bits.py --gds "$RUN" \
    --struct-prefix eth_rom_via --words 512 --bits 32 --out /tmp/eth.bits
diff <(tr -d ' \r' < /tmp/eth.bits) \
     <(tr -d ' \r' < nanosoc-multicore-system/build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom/eth_ss_bootrom.bintxt)

python3 scripts/ci/rom_gds_bits.py --gds "$RUN" \
    --struct-prefix rom_via --words 512 --bits 32 --out /tmp/cc.bits
diff <(tr -d ' \r' < /tmp/cc.bits) \
     <(tr -d ' \r' < nanosoc-multicore-system/build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom_chip_core/nanosoc_bootrom_chip_core.bintxt)
```

Or through the gate, which asserts the same thing and records evidence:
`make -f ASIC/common.mk rom-gate-gds ROM_GDS="$RUN"`.

**Pass criterion.** Both diffs empty, exit 0 from the extractor, and every word
recovered — a partial extraction is not a measurement and exits non-zero.

**Expected values**, from `full-20260814`. A `gate1` that differs from these
without a firmware change is a finding, not noise:

| | programmed cells | non-zero words | placed |
|---|---:|---:|---:|
| `eth_rom_via` | 3216 / 16384 | 277 / 512 | 1 |
| `rom_via` (cc) | 4715 / 16384 | 400 / 512 | 1 |

**`placed` must be 1.** The extractor reports how many times the macro's top
cell is instanced. **0 means you are reading the standalone macro and have
proven nothing about the reticle** — the single easiest way to get a
false green here.

**Negative control, keep it.** The same extraction against the superseded
`ASIC/genus-innovus/runs/20260812T144334Z_route-baseline-gds-nonstrict/outputs/eval/nanosoc_eth_chiplet_pads_keepobs.gds`
gives 8128/16384 cells (49.6 %, the random-fill signature), 512/512 words
non-zero and 512/512 words differing from the firmware. That stream is dead and
is not a live risk, but it proves the gate can fail on a real artefact.

### The trap that produced a wrong conclusion twice

**The live tree is `ASIC/eth-chiplet/build/`. It is not
`ASIC/genus-innovus/runs/`.** Two sessions independently concluded "no re-stream
since the ROM rebuild, so the ROMs are dead" by searching only `runs/`, whose
name suggests it holds the current work. It holds superseded evaluation streams.
Compare the timestamp of the stream against the macro rebuild
(`ASIC/romlibs/*/*.gds2`) before believing any staleness argument, and check
which tree you are in first.

Those dead `runs/**/eval/*.gds` are **marked here rather than deleted** — they
are evidence for other questions, and removing them mid-week is a bigger change
than this note.

---

## 2. LEC with the joint closed

Run both legs against **one** `_gate_power.v`, and record its hash.

```sh
G=ASIC/eth-chiplet/build/gate1/outputs
sha1sum $G/nanosoc_eth_chiplet_pads_gate.v \
        $G/nanosoc_eth_chiplet_pads_gate_power.v \
        $G/nanosoc_eth_chiplet_pads_pnr.v          # pin these in the manifest

make -C ASIC/genus-innovus lec-gate    # gate.v      -> gate_power.v
make -C ASIC/genus-innovus lec-pnr     # gate_power.v -> pnr.v
```

Then **assert the joint**, which is the step that has never been performed:

```sh
diff <(grep gate_power ASIC/genus-innovus/reports/lec/gate/inputs.txt) \
     <(grep gate_power ASIC/genus-innovus/reports/lec/pnr/inputs.txt)
```

The two records must name the same file with the same sha1.

### Why this is not optional

The 2026-08-08 evidence is **void**, and not because either leg failed. Both
passed perfectly — 61,534/61,534 and 61,375/61,375 compare points equivalent,
0 non-equivalent, 0 abort, Conformal printing `Compare Results: PASS`. They
passed about **two different middle files**:

| leg | role | size | sha1 | mtime |
|---|---|---:|---|---|
| `lec-gate` | revised | 40,690,594 | `664d76d7…` | 08-08 17:14 |
| `lec-pnr` | golden | 41,061,573 | `431c06a5…` | 08-07 17:43 |

A day and 371 KB apart. `A ≡ B` and `B ≡ C` give `A ≡ C` only when the two `B`s
are the same file. [13 §2](13-lec.md) states exactly this and is why
`run_lec.sh` records size, mtime and sha1 into `inputs.txt` on every run — the
mechanism worked, the check was never run.

**Expect PASS with accepted exceptions, not a bare PASS.** The runner accepts
34 symmetric supply-pad unreachable points per side, and on the gate leg the 4
extra revised primary inputs `VDD/VDDIO/VSS/VSSIO`, which *are* the difference
between those two netlists. The dofile's own line still reads `RESULT=FAIL` in
that case; `LEC-RUNNER: RESULT=PASS` is the verdict. Any CI check that greps
only for `^LEC-VERDICT: RESULT=PASS` will fail every good run.

Budget: **412 s CPU, 874 MB** per leg, measured. Not the multi-hour job the
older text feared.

Still true, and separate: **RTL → `_gate.v` has never completed.** Its one
attempt aborted at dofile line 104 on `FIL1.2`, because Genus's generated dofile
hardcodes an absolute path into `outputs/` and the run archiver had relocated
the netlist. Closing that needs a `syn` mode that survives relocation — out of
scope this week.

---

## 3. Available and deliberately unused: gate-level simulation

Recorded so the next spin does not re-derive it.

`docs/tapeout/13-lec.md` §3 used to say no standard-cell or IO Verilog ships
here. It does — `Front_End` **is** the simulation package. Standard cells, IO
drivers and all six RAM macros have models, both ROMs have models plus content
files, and VCS, Xcelium and Verilator are installed. Gate-level simulation of
this chip is achievable.

It is **out of scope for this tapeout** and nothing here depends on it. Two
things to know before anyone starts:

- the cost is dominated by X-propagation bring-up, not by collateral — a gate
  netlist powers up all-X with no initial blocks, and RTL simulation hides that;
- the simulation Verilog carries an **older release revision than the Liberty**
  in both the standard-cell and IO packages, so a GLS run exercises a slightly
  different cell revision than was timed. Check with the two `ls -d` commands in
  13 §3 before trusting a result.

What *is* in use is the ROM readback gate built on the same collateral:
`make gls-rom` reads each ROM back through its own behavioural model and proves
the simulated contents are the firmware. That closes the `$readmemb`-relative-
path hole, and it is independent of everything above — no netlist, no PDK.

---

[← 33 Toolkit/legacy decoupling](33-toolkit-legacy-decoupling.md) · [index](00-index.md)
