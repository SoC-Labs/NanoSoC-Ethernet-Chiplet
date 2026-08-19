<!-- ci/fixtures/gls-netlist -- provenance. Fold into ci/fixtures/README.md's
     provenance table when this stage lands; that file is shared and is not
     edited here. -->
# `gls-netlist` fixtures — where the bytes come from

**Regenerated 2026-08-19 (afternoon), reconciled to the SHIPPED BENCH.** The
previous set was built around a 34-key verdict shape that
`ASIC/gls-netlist/bench/eth_chiplet_fp1505_cc.json` does not produce — it
carried the handshake rungs a *corrected* bench would emit. Twelve of those keys
do not exist in the shipped bench, so a check that graded them failed for a
reason that was not the design, and several `fail-*` fixtures proved clauses
that could never fire on a real run.

The shipped bench emits **exactly 22 keys**: `cc_rom`/`eth_rom` ×
{`.nonx`,`.content`}; `cc_rom_port`, `eth_rom_port`, `cpu1_dmem_write`,
`cpu1_imem_write`, `cpu1_imem_fetch` × {`.accessed`,`.data_nonx`}; and 8
`expects`. It has **no `forces` key** and `run_cycles` **250000**. Every fixture
below is built from that shape.

Three sets, because a `check:` can only be proved in the ONE mode its manifest
declares, and the modes it does not declare are the ones reached the day
something regresses:

* `pass*`, `fail-*` — the **declared** mode, `MODE=full_handshake`.
* `mode-unforced/*` — `MODE=unforced_fetch`: no force, but the bench does not
  yet assert the handshake, so the RTL leg is still load-bearing.
* `mode-fetch/*` — `MODE=fetch_path_only`, for `bench/eth_chiplet_fp1505_forced.json`.
  That bench is **not retired** — it is still on disk and still reachable via
  `make -C ASIC/gls-netlist forced-fallback` — it is simply not in `GLSN_ITEMS`
  and not what ships. The mode stays proven and stays undeclared.

Neither rehearsal set is reachable from `check_proof`;
`ASIC/gls-netlist/docs/proposed/prove_draft.py` substitutes `MODE` in the check
text (and **asserts the substitution took**) and runs them. 39 cases, 3 modes.

## The source runs

| tag | run | what it is |
|---|---|---|
| **S** | shipped bench, `ASIC/eth-chiplet/build/fp1505/reports/gls/fp1505_cc/`, 2026-08-19 12:46 | the real unforced boot. `FORCES 0`, run complete at 6,039,990,000 ps. Every `accesses=` and every `at=` in `pass`, and in every `fail-*` derived from it, is **measured from this run** |
| **N** | `build/gls-netlist-negative/fp1505_cc/verdict.txt`, 2026-08-19 12:28 | the ERASED-IMAGE negative control `make -C ASIC/gls-netlist negative-control` produces. Copied **verbatim** into `fail-blank-flash` |
| **X** | `ASIC/eth-chiplet/build/full-20260814/reports/gls/full0814_cc/verdict.txt`, 2026-08-18 17:34 | the published `RESULT FAIL pass=10 fail=4` the in-tree check passes today. Copied **verbatim** into `fail-full0814-published` |
| **P** | probe run, 2026-08-19 12:19, 20 ms | the handshake-probe run whose `at=` values are reused for the rungs a corrected bench would add. `docs/tapeout/evidence/57-cpu0-boot-verdicts.md` §A |

### A note on run S and the live evidence path

Run S's verdict was **overwritten in place at 16:19** by the CPU0-boot
diagnosis session, which re-ran with two extra green diagnostic probes
(`ipc_slot1_warm_word_published`, `ipc_slot1_clobbered_by_banner`) and published
`RESULT FAIL pass=24 fail=5`. The reconciled check was run against that live
file and **passes it** — extra *green* rungs are allowed; only *red* ungraded
rungs fail. `pass-known-open-eth` deliberately freezes the **12:46 snapshot**
(27 rows, `RESULT FAIL pass=22 fail=5`), because a fixture that tracks a file
another session is rewriting is not a fixture.

## Row by row

| element | derived from | confidence |
|---|---|---|
| `FORCES 0 …` / `FORCES n …` / `FORCE …` line text | **verbatim** from run S, and byte-identical to the `$fdisplay` format strings in `ASIC/asic-toolkit/flow/verify/gls/gen_netlist_tb.py` (lines 440–462; re-read during this reconciliation) | high — the tool's own bytes |
| `GLSN-FORCES:` / `GLSN-FORCE: declared` / `GLSN-EVENT: <t> run complete` in every `sim.log` | same generator, lines 320–345 and 464–470 | high |
| every `accesses=` and `at=` in `pass` | **measured**, run S | high |
| `pass-known-open-eth` | run S's 12:46 verdict, **byte-for-byte**, with its real `inputs.txt` | high |
| `fail-blank-flash` | run N, **byte-for-byte** | high |
| `fail-full0814-published` | run X's 14 rows, **byte-for-byte**, with a `FORCES 0` line prepended and the standard fp1505 `inputs.txt`/`sim.log` beside it — see "one fixture, one clause" below | high for the rows |
| the seven handshake rows in `pass-extra-rungs` and the `fail-probe-*`/`fail-*strobe*` fixtures | **measured**, run P | high |
| `results.xml`, `eth_ss_bootrom.{sv,bintxt}` (mode-* sets) | unchanged from the previous set: trimmed extracts of the real files; `fail-bootrom-pin` flips word `0x003` to `0x0800048c`, a real divergence miniaturised | high |
| every `inputs.txt` | trimmed from run S's: the `netlist:` line and its sha256 (`ac04899a…`) are the real ones. `fail-wrong-tree` rewrites only the build-tag in that path | high |
| the compressed timeline in `fail-release-too-early` | **synthetic on purpose**: the whole chain in microseconds, ordering intact, so that ONLY the release-time floor can reject it | n/a — a constructed negative |
| `2000000000 ps` in `fail-window-too-short` and the missing `run complete` line in `fail-late-red-unknown-window` | **synthetic on purpose**: the two shapes of "the clock ran out" | n/a |

## One fixture, one clause — and where that was deliberately relaxed

The previous set recorded a correction: *a fixture that fails for the wrong
reason proves the wrong clause and reads as coverage.* Each `fail-*` here was
run and its FAIL text read, to confirm it names the clause it exists for. Three
places where more than one clause fires, on purpose:

* **`fail-full0814-published`** — run X predates most of the bench, so besides
  its five eth reds it is missing ten keys this stage requires. Both failures
  are correct and both are printed. Its `inputs.txt` names the fp1505 tree, so the
  wrong-tree clause does *not* also fire and muddy it.
* **`fail-window-too-short`** — the Tier-B reds and the budget both fire. That
  is the point: the check says **which** it is, and the OUTCOME is
  `SW WINDOW TOO SHORT - NOT CLASSIFIABLE`, not `S1 NO RELEASE`.
* **`fail-release-without-strobe`** — `remap_write_strobe` red is both "the
  bootgate rose with nothing writing it" and "a red rung this stage does not
  grade". Both are true statements about the same row.

## What changed in the fixture set, and why

| fixture | was | now |
|---|---|---|
| `pass` | 34-key corrected-bench shape | **the shipped bench's 22 keys**, `RESULT PASS pass=22 fail=0` |
| `pass-known-open-eth` | *new* | the 27-row published verdict; must PASS with five KNOWN-OPEN warnings |
| `pass-extra-rungs` | *new* (was the old `pass`) | 22 + the 7 handshake rungs, all green — keeps the probe-pair, strobe-proximity and extended-ordering clauses live |
| `fail-full0814-published` | *new* | the live false green, verbatim |
| `fail-ungraded-rung-red` | *new* | a red row this stage does not grade — the generalisation of the defect |
| `fail-known-open-closed` | *new* | the open item went green and nobody promoted it |
| `fail-window-too-short`, `fail-late-red-unknown-window` | *new* | the cycle-budget trap, both shapes |
| `fail-probe-pair-orphan` | *new* | one half of a pinned pair declared |
| `fail-cpu0-not-gated` | *new* | S0: CPU0 fetching long before CPU1 could have let it go |
| `fail-result-miscount` | *new* | `RESULT` does not foot against its own body |
| `fail-blank-flash` | synthetic 34-key | **the real erased-image negative control** |
| `fail-tierc-missing` | dropped `eth_sysctrl_remap_set` | drops `cpu1_imem_fetch.accessed` — the old key is now on the KNOWN_OPEN register, so the fixture would have gone green |
| `fail-tierc-red` | `ipc_slot1_warm_word` red (a key the bench never emits) | `cpu1_imem_write.data_nonx` red — a copy that landed with X in it |
| `fail-crc-rejected` | `eth_sysctrl_remap_set` red (now KNOWN_OPEN) | `cpu1_imem_fetch.*` red — CPU1 copied and never executed |
| `fail-order-violated` | violated on `ipc_slot1_warm_word` | violated on `cpu1_main_entered` vs `qspi_flash_addressed` |
| `mode-unforced/fail-tierc-red` | `eth_sysctrl_remap_set` red | `qspi_flash_addressed` red — same reason |
| everything else | 34-key shape | rebuilt on the 22-key (or 22+7) shape; clause unchanged |

**Three of those rewrites are the same bug.** `eth_sysctrl_remap_set` moved from
"a required rung" to "a tolerated known-open red", and three fixtures were
proving a clause by reddening exactly that key. Left alone they would have gone
**green** the moment the check was corrected — a proof that quietly stops
proving. That is the failure mode `prove_draft.py` exists to catch, and it
caught it here only because every fixture's FAIL text was read, not just its
exit code.

## What these do NOT prove

They prove the check **discriminates**, in three modes, 39 cases, 0 problems.
They do not prove the eth-side open item is a design bug rather than a firmware
one — see `docs/tapeout/evidence/57-cpu0-boot-verdicts.md` and the KNOWN_OPEN
register in the check itself. And they say nothing about timing: the run they
describe is zero-delay with no SDF.
