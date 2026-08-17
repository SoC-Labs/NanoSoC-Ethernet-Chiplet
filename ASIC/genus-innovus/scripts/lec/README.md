# `scripts/lec` — logical equivalence checking that reads the shipped netlist

Conformal LEC harness for `nanosoc_eth_chiplet_pads`. Project-owned, in `scripts/`,
**not** generated into `work/`.

Full reasoning, measurements and limits: [`docs/tapeout/13-lec.md`](../../../../docs/tapeout/13-lec.md).
This file is the operating manual.

---

## The two problems this replaces

**1. `make lec` never read the netlist we ship.** Genus auto-writes `work/lec.dofile`
during `syn_map`. It compares Genus's internal `fv/…/fv_map.v.gz` against
`outputs/…_gate.v`, and RTL against `fv_map`. It never opens `outputs/…_pnr.v`.
Post-route CTS, optimisation and hold repair add **45,745 instances** to the netlist
that becomes GDS (185,997 → 231,742), including **10,555 `DEL*` hold-repair delay
cells** and **22,046 `CKBD0` clock buffers** that do not exist in the synthesis netlist
at all. None of it was verified by anything in this repository.

**2. The verdict could not fail.** The recipe was

```make
lec:
	cd $(WORK_DIR)/; lec -xl -Dofile ./lec.dofile
```

`exit -f` at the end of the generated dofile *does* return Conformal's status word, but
the recipe discards it, so a NON-EQUIVALENT result reported success. The dofile even
defines `proc is_pass {}` and then never uses it on the exit path.

There is also a third, quieter problem: `work/lec.dofile` only exists after `make syn`
and is destroyed by `make clean`. The current `work/` — from a run resumed at
`pnr_place` — has no `lec.dofile` at all, so `make lec` in that tree fails on a missing
file rather than checking anything.

---

## Usage

From `ASIC/genus-innovus/`:

```sh
scripts/lec/run_lec.sh selftest   # ~15 s.  Mutation-tests the harness itself.
scripts/lec/run_lec.sh pnr        # HOURS.  gate_power.v -> pnr.v. The real check.
scripts/lec/run_lec.sh gate       # HOURS.  gate.v -> gate_power.v. Closes the chain.
```

Exit status is `0` only if the comparison ran to completion and every key point is
equivalent. **Run `selftest` first on any new host** — it needs the same libraries and
the same licence the production run needs, and it proves the gate can still bite.

| Path | What |
|---|---|
| `logs/lec_<tag>.log` | full transcript (this is what CI greps) |
| `reports/lec/<tag>/verdict.txt` | machine-readable verdict block |
| `reports/lec/<tag>/inputs.txt` | size + mtime + **sha1** of both netlists compared |
| `reports/lec/<tag>/lec_<tag>_noneq_*` | non-equivalence evidence, on failure only |
| `reports/lec/<tag>/lec_<tag>_unmapped_*` | unmapped-point evidence, on failure only |

`logs/` and `reports/` are gitignored (`ASIC/*/logs`, `ASIC/*/reports`).

---

## Files

| File | Role |
|---|---|
| `pnr_lec.do` | The dofile. Parameterised entirely by environment; decides PASS/FAIL itself and `exit 0` / `exit 1`. |
| `run_lec.sh` | The runner. Builds the environment, checks the library list against `config.tcl`, runs `lec`, and re-derives the verdict from the transcript independently. |
| `bondpad_stubs.v` | Empty `PAD70GU` / `PAD70NU` declarations. Physical-only cells with no model anywhere in the PDK. |
| `selftest/` | Four small netlists that assert the harness passes what it should and fails what it should. |

---

## How the verdict is enforced

Twice, from two independent sources, and they must agree.

**In the dofile,** after `compare`, the final state is read back out of the tool:

```tcl
get_compare_points -NONequivalent -COunt      get_unmap_points -EXTRA       …
get_compare_points -ABort        -COunt       get_unmap_points -UNReachable …
get_compare_points -NOtcompared  -COunt       get_unmap_points -NOTmapped   …
get_exit_code
```

and PASS/FAIL is decided from those numbers plus the decoded Conformal status bits.
`exit 0` / `exit 1` follows. Measured on `lec 22.10-s200`: `exit 7` from `tclmode`
returns 7, so the status is genuinely ours to set. `set_dofile_abort exit` is on, so a
setup failure cannot reach the compare — a failed `read_design` leaves the process with
6.

**In the runner,** the transcript is re-read and must satisfy *all* of:

- it exists, and is at least `LEC_MIN_LOG_LINES` (default 50) lines;
- no line starts with `LEC-PREFLIGHT-FAIL`;
- no `is aborted at line` / `Error exit from dofile`;
- `LEC-VERDICT: RESULT=PASS` is present;
- Conformal's own `Compare Results:   PASS` is present *(not a bare match on
  `Equivalent` — that is a row **label** in the summary table, printed pass or fail,
  which is what made an earlier version of this check vacuous)*;
- `lec` exited 0, and that does not contradict the `LEC-VERDICT` line;
- the golden and revised **unreachable key-point lists are identical by name**.

Any failure names itself in the output.

---

## Libraries

Ten Liberty files, **the same ten `config.tcl` gives Genus and Innovus**. `run_lec.sh`
greps `config.tcl` for `*.lib` basenames and **refuses to run** if the two lists have
drifted, so a memory-corner swap cannot silently turn a macro into an accidental
blackbox.

Conformal reads **Liberty, not Verilog**: `tcbn65lpwc.lib` carries a `function` on every
combinational output and a full sequential description on every flop, which is exactly
what LEC consumes.

> **Corrected 2026-08-17.** That sentence used to end "and the TSMC packages on this site
> are Front_End-only — there is no standard-cell Verilog to read." False. `Front_End` *is*
> the simulation package (`Back_End` — the GDS and layout views — is what this site lacks).
> Both the standard-cell and the IO simulation models are present, in the very same `_FE`
> packages `SC_LIB_DIR` / `IO_LIB_DIR` below already resolve for the NLDM: look one level up
> from the NLDM directory and take the sibling `verilog/` subtree instead (3.7 MB / 844
> modules for the standard cells, plus a `…_pwr.v` PG-pin variant; 26 KB / 58 modules for the
> IO). Liberty remains the right input **for LEC** — a choice, not a forced move — but the
> false version of this claim was being cited elsewhere as proof that gate-level simulation
> is impossible on this site, which it is not.
>
> Before relying on those models, note the revision skew: inside each package the `verilog/`
> subdirectory carries an **older release revision** than the `NLDM/` one, so the simulation
> models are not the same release as the Liberty. `ls` both subdirectories and compare the
> names. See `docs/tapeout/13-lec.md` §3.

### `-PG_PIN` is load-bearing

The supplies in `tcbn65lpwc.lib` are `pg_pin()` groups, not `pin()` groups. Without
`-PG_PIN`, Conformal creates no pins for them and every `.VDD(VDD)` in the netlist is a
connection to a pin that does not exist:

```
// Error: HRC3.3: Undefined named port connection
//  Cannot find pin u_inv/VDD. No pin VDD is defined in module INVD1
```

and `elaborate_design` aborts. `gate_power.v` has 159,692 such connections and `pnr.v`
has 182,399. **This is why "just point `work/lec.dofile` at `pnr.v`" does not work** —
that dofile reads these libraries without `-PG_PIN` and only survives because `gate.v`,
the netlist it was written for, has 6 PG connections in the whole file.

`LEC_PG_PIN` selects the side: `both` (default, for `pnr`), `revised` (for `gate`),
`golden`, or `none`.

### Memories are blackboxed — say so out loud

`rf_01k` `rf_08k` `rf_16k` `rf_32k` `rom_via` `eth_rom_via` `flash_cache_data`
`flash_cache_tag` are `add_notranslate_modules`'d, exactly as Genus's own generated
dofile does. Liberty gives them pins and arcs but no logic function, so the array
contents are **out of scope**.

Memory *connectivity* is fully verified: every address, data, write-enable, chip-enable
and clock pin is a compare point, and every `Q` output drives compared logic. A swapped
address bit or a dropped write enable fails. Memory *behaviour* is not verified, and no
reasonable setup on this site would verify it — the Arm PIP behavioural models exist
(`/research/precompiled_mems/TSMC65/<macro>/<macro>.v`) but putting the same model on
both sides can only prove the model equals itself.

Consequence, visible in every run: each blackboxed macro contributes a `VDD_outputZ` and
a `VSS_outputZ` **unreachable tri-state key point** per side. 21 macro instances → expect
42 per side on the real design. `pnr_lec.do` reports these and does not fail on them
(an unreachable point provably cannot influence any compared output), but it *does* fail
if the counts differ between sides, and `run_lec.sh` *also* diffs the two lists by name.
`LEC_STRICT_UNREACHABLE=1` restores a blanket fail.

---

## Environment knobs

| Variable | Default | Effect |
|---|---|---|
| `LEC_MODE` | `-xl` | Conformal licence tier |
| `LEC_THREADS` | `1,4` | `set_parallel_option` / `set_compare_options` |
| `LEC_PG_PIN` | `both` | which side reads Liberty with `-PG_PIN` |
| `LEC_DIALECT` | `-VERILOG2K` | `read_design` dialect |
| `LEC_DIAG` | `1` | run `analyze_nonequivalent -source_diagnosis` on failure |
| `LEC_STRICT_UNREACHABLE` | `0` | fail on *any* unreachable point |
| `LEC_MIN_LOG_LINES` | `50` | short-transcript guard |
| `BLOCK` | `nanosoc_eth_chiplet_pads` | design top |
| `TSMC_65_HOME`, `MEM_BASE`, `NANOSOC_ETH_CHIPLET_HOME` | as `ASIC/common.mk` | library roots |

---

## Two rules for editing this directory

**Everything Conformal parses must be pure ASCII.** Its Tcl parser rejects non-ASCII
bytes inside a command — an em dash in a quoted string produced
`// Error: Incomplete command: if {$LIBS eq ""} { …` and aborted the run. That applies to
`pnr_lec.do` and to every `.v` here, comments included.

**`tclmode` must be line 1 of the dofile, with nothing above it, not even a comment.**
Until it runs, the file is parsed in Conformal's native command mode where a leading `#`
is an *unknown command*, and the run dies at line 1 with
`// Error: Unknown command #-----…`. Genus's generated dofile has `tclmode` on line 1
for the same reason.
