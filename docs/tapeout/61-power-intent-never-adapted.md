# 61 — The power intent was never adapted from the project it was copied from

[index](00-index.md) · [04 Power plan](04-power-plan.md) · [09 Signoff checklist](09-signoff-checklist.md)

**Status: ROOT CAUSE ESTABLISHED, NOT FIXED. A working downstream workaround is
neutralising the visible symptom, which is why this has survived 33 days.**

`ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf` describes a **different
design**. Not a stale version of this one — a different one. `check_cpf` has been
reporting it on every synthesis run since, into a log nobody reads, because
`SYN_SOFT_CPF` defaults to 1.

---

## 1. The evidence, in one place

```
git log --follow -- ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf
  97f7fe6  2026-07-16  ASIC: copy initial genus-innovus flow from nanosoc-multicore-system
  (1 commit, total)

git diff 97f7fe6 -- <that file>        -> empty
```

**One commit. Byte-identical to it today.** The file was copied out of
`nanosoc-multicore-system` on 2026-07-16 and has not been edited since.

That single fact explains everything below, and it is why the dead hierarchy is
spelled the way it is: **`u_nanosoc_multicore_soc` is the source project's own
top-level instance name.**

| symptom | measurement |
|---|---|
| 34 `connect_supply_net` address `u_nanosoc_multicore_soc/...` | `grep -ac u_nanosoc_multicore_soc <gate.v>` → **0**; same on `src/rtl/nanosoc_eth_chiplet.sv` → **0** |
| control, so the zero is not a broken pattern | `grep -ac u_chip_core <same netlist>` → **10,619** |
| the declared top does not exist | `set_design_top nanosoc_chip_pads`; `grep -acE '^module +nanosoc_chip_pads\b'` → **0**. Real top is `nanosoc_eth_chiplet_pads` (→ 1). `read_power_intent -module $block_name` scopes over it, which is why it never hard-fails. |

## 2. It is not a rename, and a path rewrite is the wrong fix

The file encodes the **source project's memory configuration**:

| UPF says | this design has | mismatch |
|---|---|---|
| `u_cpu_ss_1/u_region_imem_0/…/gen_rf_32k` | `u_chip_core/u_region_imem_0/…/gen_rf_16k` | size |
| `u_cpu_ss_1/u_region_dmem_0/…/gen_rf_32k` | `u_chip_core/u_region_dmem_0/…/gen_rf_08k` | size |
| `u_eth_ss_0/u_region_eth_scratch_{rx,tx}_0/…/gen_rf_16k` | `…/gen_rf_08k` | size |
| `u_eth_ss_0/u_region_imem_0/…/gen_banked.gen_bank[0]`, `[1]` | a single `gen_rf_32k` | banking |

and **three real macros appear nowhere in it**, because they postdate the copy:
`u_network_core/u_ethmac_0/…/bd_ram/u_sram/u_rf`, `u_shared_sram_0/…`, and
`u_tidelink/u_tidelink_fifo/…`.

> **Predicted before running, so it is a test and not a story:** a prefix-and-rename
> rewrite clears **22 of 34** (the 20 QSPI statements plus the 2 whose leaf happens to
> match), leaves **12** failing, and leaves **6 macro pins** with no statement at all.
> If anyone runs that and reports "34 → 12, good progress", it is being over-read.

### A framing of mine that was wrong, corrected here

I first described this as a **half-completed migration** — 6 bootrom connections
migrated to the correct hierarchy, 34 SRAM ones left behind — and asked why someone
would stop there. **There was no migration.** `git show 97f7fe6:<file>` contains
**6** correct lines and **34** dead lines *at creation*. Both halves arrived in the
copy. Nobody stopped half-way, so there is no missing knowledge to recover, and the
question "why did they stop" has no answer because it has no subject.

## 3. What the check actually says, and why nobody has read it

`check_cpf` runs and writes **122,899 bytes** to `<build>/logs/syn_cpf_check.log`
every run. Census of that file:

| severity | count | rule |
|---|---:|---|
| Error | **34** | `1801_REF_OBJ_NOT_FOUND` |
| Error | **54** | `1801_LIB_NO_PG_PIN` |
| Error | **1** | `1801_LIB_MISSING_LP_CELL` |
| Warning | 38 | `1801_SUPPLY_CSN_MISSING_FOR_MACRO` |
| Warning | 274 | `1801_MACRO_PORT_ATTR_MISSING` |
| Note | 2 | `1801_LOGIC_CONN_CTRL_UNDEF_MACRO` |

The 34 errors and the 38 warnings are **one defect from two sides**: the UPF connects
supplies on instances that do not exist, so the instances that *do* exist end up with
no `connect_supply_net`.

**Why it is invisible:** `SYN_SOFT_CPF 1`
(`asic-toolkit/flow/genus/1_synthesis.tcl:67`) swallows the call *and* allowlists
`RCLP-203`/`RCLP-208` in the end-of-run message census. The script's own comment says
"Turn `SYN_SOFT_CPF` off to get the abort back once the power intent is clean." It has
never been clean.

**The licence warning is a separate, smaller thing.** `RCLP-208 "Could not launch
Conformal Low Power with default license"` fires with 41 licences free because this
site issues **`Conformal_Low_Power_GXL` only — there is no plain `Conformal_Low_Power`
feature on the server at all**. Genus requests the base tier, which is not licensed
here. Selection, not scarcity. It blocks the *deep* CLP analysis; it did not stop the
89 errors above from being found.

## 4. Downstream: the symptom is already patched, the cause is not

`power_plan.tcl:8-32` documents the consequence from the other end — Genus's
`write_power_intent -cpf` cannot translate the UPF's supply commands, so the emitted
CPF carries only `create_power_domain -name PD_TOP -default`, and Innovus then fails
every filler pass (`IMPSP-5110`, "For 0 new insts"). **The 2026-08 run shipped a GDSII
with zero filler cells and 95,568 free-site gaps.** `make syn` now repairs the CPF via
a `cpf-patch` target (`ASIC/genus-innovus/Makefile:242`), and it works — fillers
measure **41,853** (`full-20260814`) and **43,083** (`fp1505`), not zero.

So this is **a live root cause underneath a working workaround**: not an emergency,
and exactly the state that bites six months later when someone removes the patch.

## 5. The fix, and what has been done

Regenerate rather than repair. A corrected file has been built **in scratch, not
landed**, against **`check_cpf`'s own resolved macro list** (19 macros / 38 pins) —
the tool verified those targets, so they are not a list derived by inspection.

Verification of the regenerated file:

```
executable statements referencing the dead hierarchy   : 0
set_design_top                                         : nanosoc_eth_chiplet_pads
hierarchical macro-pin statements found in the netlist : 44   (38 regenerated + 6 bootrom)
                                             not found : 0
top-level supply ports / pad wildcards                 : 4 / 4
```

The already-correct bootrom and pad lines were left untouched.

## 6. Does it change what P&R BUILDS? No — measured 2026-08-18

**It cannot, and the reason is that the UPF is not the binding artefact.** Synthesis
writes *two* power-intent outputs:

```
1_synthesis.tcl:1180   write_power_intent -cpf ...  ->  gate1.cpf   (what P&R reads)
1_synthesis.tcl:1181   write_power_intent      ...  ->  gate2.upf   (a UPF round-trip)
```

| | input UPF | `gate2.upf` round-trip | `gate1.cpf` P&R reads |
|---|---:|---:|---:|
| `create_supply_port` | 4 | 4 | **0** |
| `create_supply_net` | 4 | 4 | **0** |
| `create_supply_set` | 2 | 2 | **0** |
| `create_pst` | 1 | 1 | **0** |
| `connect_supply_net` | 48 | **14** | **0** |
| correct bootrom refs | 6 | 6 | **0** |
| dead-hierarchy refs | 34 | **0** | 0 |
| size | | 3,733 B | **730 B** |

**The round-trip is the control, and it refutes the obvious theory.** One might assume the
34 errors degraded the CPF emission and took the good constructs with it. They did not:
Genus ingested the UPF correctly and kept exactly `48 − 34 = 14` connections, with all six
correct bootrom paths present and zero dead-hierarchy references. It resolved precisely the
valid statements and discarded precisely the invalid ones.

So the CPF drops constructs that Genus demonstrably holds internally — **including four
top-level `create_supply_port` statements that no instance-path error could affect.**
`write_power_intent -cpf` simply does not translate them.

> **Prediction, logged before any run:** regenerating the UPF takes `gate2.upf` from 14 to 52
> `connect_supply_net` and leaves `gate1.cpf` byte-identical apart from its header timestamp.
> If the CPF changes, this section is wrong.

### Two consequences that matter more than the grid

- **`cpf-patch` is not a workaround for a broken UPF.** It is a workaround for a translation
  that emits nothing regardless of input quality. **Repairing the UPF does not make the patch
  redundant** — anyone who fixes the UPF and then removes the patch returns the design to zero
  fillers and 95,568 free-site gaps.
- **The UPF is not a trustworthy description of what was built**, and never has been. That is
  the durable risk here. The PG grid is fine; the *document* of it is fiction.

---

## 7. What is NOT established

- The **54 `LIB_NO_PG_PIN`** errors may simply be the expected consequence of reading
  libraries without PG pins. Not investigated. Do not add them to the 34 as if they
  were the same finding.
- **Repairing the UPF may not change the grid actually built**, because `cpf-patch`
  is already supplying what the broken CPF omitted.
- **Whether `check_cpf` passes under the GXL tier is unmeasured.** Nobody has run it.
- The regenerated file has been **statically** verified only. It has not been through
  `read_power_intent`.
