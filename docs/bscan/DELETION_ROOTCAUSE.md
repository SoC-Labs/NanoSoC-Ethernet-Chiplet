# The boundary-scan "logic deletion" of 2026-08-20 — root cause

**Status:** diagnosed from the two netlists on disk. No new synthesis run required to
reach the verdict; one run is proposed only to confirm the *cause of the ungrouping*,
which is a flow question, not a correctness question.

**Analyst note:** analysis only. No RTL, SDC or flow file was modified in producing this.

---

## VERDICT, up front

**117 of 119 boundary cells were not deleted. They are all in `bscan-probe2`.**

The reported census — 119 → 2 — is **96.6 % a measurement artefact and 3.4 % a real,
correct optimisation.** The true figure is:

| | probe | probe2 | delta |
|---|---|---|---|
| `u_bsc_*` flops in the boundary register | **119** | **115** | **−4** |
| — shift/capture stages | 76 | **76** | 0 |
| — update stages | 43 | **39** | −4 |
| fixed stages (IDCODE 32 + IR 8 + TAP 4 + bypass 1 + TDO 2) | 47 | **47** | 0 |
| **total flops in the register** | **166** | **162** | **−4** |
| `bsr_chain[1..76]` bits with exactly 1 driver and ≥1 load | 76/76 | **76/76** | 0 |

The 76-bit shift chain is **structurally complete and connected end to end in probe2**,
bit for bit, including the final update flop hanging off `bsr_chain[76]`. The BSDL's
declared register length is still correct.

**Two independent things happened, and they were conflated:**

1. **The module `nanosoc_eth_chiplet_bscan` was auto-ungrouped** (dissolved into
   `nanosoc_eth_chiplet_pads`). This renamed every instance inside it and broke the
   census. It deleted nothing.
2. **Four update flops really were removed** — and their removal is *provably correct*.
   They could never have driven their pads. See §4.

**Your HIGHZ change is not the cause.** See §5. That is stated plainly because you asked
for it, and because it matters: the real trigger is a constraints file that is invisible
to the run manifest.

---

## 1. The register is intact — direct evidence

The census that produced "119 → 2" is line-oriented. Netlist instance statements are
*not* line-oriented: Genus wraps them at ~80 columns. Parsing whole statements instead
of lines gives:

```
PROBE  bscan module (lines 575605..576576), parsed as statements:
    327 instances, 166 flops, 119 named u_bsc_*  (76 shift + 43 update)
    bsr_chain[1..76]: 76/76 exactly 1 driver, >=1 load
    bsr_chain[76] loads: u_bsc_75_TL_TX_7_data_update_q_reg/D , CKND1 g4798/I

PROBE2 top module nanosoc_eth_chiplet_pads (flattened), parsed as statements:
    115 instances named *u_bsc_*  (76 shift + 39 update)
    bsr_chain[1..76]: 76/76 exactly 1 driver, >=1 load
    bsr_chain[76] loads: u_nanosoc_eth_chiplet_bscan_u_bsc_75_TL_TX_7_data_update_q_reg/D , CKND1 g2237/I
```

All 76 distinct `u_bsc_NN` indices (`u_bsc_00` … `u_bsc_75`) are present in **both**
netlists. `bsr_chain[0]` is absent in both — it is the chain input, not a flop output.

---

## 2. Why the census read 2 — the artefact, measured

Ungrouping prefixed every instance name inside the register with
`u_nanosoc_eth_chiplet_bscan_` — **28 characters**. Genus then wraps the instantiation
so the cell type and the instance name land on **different lines**:

```verilog
// probe — fits, name on the same line as the cell type:
  SDFCNQD1 u_bsc_27_HOST_IO_0_data_dr_q_reg(.CDN ...

// probe2 — wrapped, the name is on its own line:
  SDFCNQD1
       u_nanosoc_eth_chiplet_bscan_u_bsc_27_HOST_IO_0_data_dr_q_reg(.CDN ...
```

Any regex of the form `^\s+CELLTYPE\s+\S*u_bsc_\S*\s*\(` now matches **only the
instances whose name is short enough not to wrap.** Measured in probe2:

```
bscan-prefixed instances rendered with celltype+name on ONE line : 49
   ... of which are u_bsc_ boundary cells                        :  2
       len=54  u_nanosoc_eth_chiplet_bscan_u_bsc_04_SE_I_obs_dr_q_reg   (col 65)
       len=55  u_nanosoc_eth_chiplet_bscan_u_bsc_02_CLK_I_obs_dr_q_reg  (col 66)
WRAPPED (name pushed to the next line)                           : 115
   shortest wrapped would-be column                              : 67
       u_nanosoc_eth_chiplet_bscan_u_bsc_00_NRST_I_obs_dr_q_reg
```

**The two "survivors" are the two shortest names in the register.** `SE_I` and `CLK_I`
are the shortest pad names on the die. The wrap threshold sits between column 66 (fits)
and column 67 (wraps).

**This is the falsification of the deletion hypothesis on its own.** Constant
propagation has no mechanism that spares cells by *name length*. If Genus had swept the
register, the survivors would have been selected by connectivity — not by being 54 and
55 characters long while the other 115 are ≥56.

The same threshold explains the rest of the reported table exactly. IDCODE (44–45 ch),
IR (47–48 ch), TAP (49 ch), bypass (40 ch) and TDO (37/40 ch) all fit on one line and
were reported "surviving"; every update stage (`..._data_update_q_reg`,
`..._oe_update_q_reg`) is long and wraps, so all 43 were reported gone. The reported
per-function breakdown is a **name-length histogram**, not a functional one.

### The check that produced it

`scripts/bscan_syn_verdict.py` is wrap-sensitive in three places, and the first one is
fatal on its own:

```python
mm = re.search(r"\nmodule\s+%s\s*\(.*?\nendmodule" % re.escape(module), src, re.S)
if not mm:
    fails.append("module %s is not defined in the netlist -- the register was "
                 "optimised away entirely" % module)
```

Once the module is ungrouped there is no `module nanosoc_eth_chiplet_bscan` block, so
the script reports `bsr module : ABSENT` and emits the sentence *"the register was
optimised away entirely"* — which is what the register looks like from inside a check
that can only see hierarchy. Lines 97, 140 and 152 (`^\s+(?:S?DF|EDF|QDF)...\s+\S+\s*\(`,
the instantiation count, and the anchored pad-survival test) share the same assumption.

The script's own header comment anticipates the *child* modules being ungrouped
("Genus ungroups by default, so after mapping there are no `bscan_cell_obs` /
`bscan_cell_ctl` instantiations left"). It does not anticipate the **parent** being
ungrouped. That is the gap.

---

## 3. Why the module was ungrouped — the real change

**It was not an RTL change. It was `ASIC/genus-innovus/inputs/bscan_constraints.sdc`,
which is `source`d from `constraints.sdc` and is therefore never size-asserted, never
hashed in `syn_provenance.txt`, and invisible to the run manifest.**

Commit `a2ca938` (2026-08-19 **16:44**) commented out two constraints:

```tcl
-    set_multicycle_path -setup 2 -from [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*] \
-    set_multicycle_path -hold  1 -from [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*] \
```

Timeline — the commit falls exactly between the two runs:

```
probe   started 2026-08-19 12:25   (before a2ca938)
a2ca938         2026-08-19 16:44
probe2  started 2026-08-20 08:52   (after  a2ca938)
```

Confirmed in the `read_sdc` statistics of each log — this is measured, not inferred:

| | probe (L2570–2591) | probe2 (L2568–2583) |
|---|---|---|
| `"get_pins"` successful | **40** | **36** (−4 = 2 per MCP) |
| `"set_multicycle_path"` successful | **3** | **1** (−2) |
| `"get_cells"` successful | 2 | 2 |
| `"set_false_path"` successful | 8 | 8 |

And the effect, from the Message Summary of each log:

| Genus msg | probe | probe2 |
|---|---|---|
| **GLO-51** *Hierarchical instance automatically ungrouped* | **45** | **47** |

Two more hierarchies were auto-ungrouped in probe2, and one of them is the register.
The netlist confirms it directly — note the separator:

```
probe  L4107 : Target path end-point (Pin: u_nanosoc_eth_chiplet_bscan/u_bsc_01_SWDCK_I_obs_dr_q_reg/d)
probe2 L4094 : Target path end-point (Pin: u_nanosoc_eth_chiplet_bscan_u_bsc_01_SWDCK_I_obs_dr_q_reg/d)
                                                                     ^ slash -> underscore
```

`reports/syn_area.rep` carries the row `u_nanosoc_eth_chiplet_bscan
nanosoc_eth_chiplet_bscan 327 1971.360` in probe and **has no bscan row at all** in
probe2.

### The mechanism

`get_pins <inst>/*` attaches the exception to the instance's **hierarchical boundary
pins** (`hpin:`). Genus will not auto-ungroup a hinst whose boundary pins carry SDC
exceptions, because ungrouping destroys the `hpin` objects those exceptions are anchored
to. The multicycle was therefore acting as an **accidental `ungroup_ok false`**.

This is the sharp edge: the SDC file removed the multicycle *for entirely correct
reasons* — it documents that the exception was bogus (`TIM-316/317`, applied to some
points and silently skipped on others) and unnecessary (`r2r_swdclk` slack **+17838 ps**,
zero failing endpoints). Both of those are true. The constraint was worthless **as
timing**. It was load-bearing **as hierarchy pinning**, and nobody knew, because that
effect is undocumented and invisible.

`DONT_TOUCH_PATTERNS` is `{uPAD*}` in both runs and never covered the register. The only
`ungroup_ok false` set anywhere is on `u_link_clk_div`, identical in both runs.

> **Confidence.** The *what* (ungrouping) is measured. The *why* (MCP-as-hierarchy-pin)
> is the leading hypothesis: it is the only input delta touching the bscan hierarchy, and
> the mechanism is a documented Genus behaviour. §6 states the run that confirms or kills it.

---

## 4. The 4 flops that really were removed — and why that is correct

Absent in probe2, present in probe (name and net both gone, 0 occurrences):

```
u_bsc_05_SWDIO_IO_oe_update_q_reg
u_bsc_23_HOST_IO_1_oe_update_q_reg
u_bsc_24_HOST_IO_1_data_update_q_reg
u_bsc_26_HOST_IO_0_oe_update_q_reg
```

These are not a random four. The TAP shares three functional pads, and the pad ring
overrides them (`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`):

```verilog
wire bscan_en = bsp_se_i_in;                                        // L350
wire bsp_host_io_1_out_muxed = bscan_en ? bscan_tdo    : bsp_host_io_1_out;  // L351  TDO
wire bsp_host_io_1_oe_muxed  = bscan_en ? bscan_tdo_oe : bsp_host_io_1_oe;   // L352  TDO
  .trst_n (bscan_en),                                               // L358
  .OEN ((bscan_en ? tiehi : ~bsp_swdio_io_oe)),                     // L556  TMS
  .OEN ((bscan_en ? tiehi : ~bsp_host_io_0_oe)),                    // L623  TDI
```

and in the register wrapper, `bsr_mode = ir_mode & trst_n & ~tlr` with `trst_n = bscan_en`.

So `mode` can only be 1 when `bscan_en` is 1. Then for each affected pad:

| pad | role | override when `bscan_en=1` | consequence |
|---|---|---|---|
| **HOST_IO_1** | TDO | **both** `out` and `oe` muxed to `bscan_tdo`/`bscan_tdo_oe` | **both** update flops unobservable → **2 deleted** |
| **HOST_IO_0** | TDI | `OEN` forced `tiehi` (driver off) | **oe** update flop unobservable → **1 deleted**; `data` kept |
| **SWDIO** | TMS | `OEN` forced `tiehi` (driver off) | **oe** update flop unobservable → **1 deleted**; `data` kept |

**Total: exactly 4 — precisely the four observed.**

When `bscan_en=0`, `mode=0`, so every ctl cell is transparent and `update_q` is unused.
When `bscan_en=1`, the pad ring overrides the cell's output. **There is no input
combination in which those four `update_q` values reach a pad.** Genus is right.

The two `data` flops (SWDIO, HOST_IO_0) survive because only the pad's `OEN` is forced;
their value still reaches the pad cell's `I` pin, and proving it unobservable would
require reasoning *inside* the pad model (that `OEN=1` blocks `I`), which Genus does not
do. That asymmetry is itself strong confirmation of the mechanism — it is exactly what
boundary-pin constant propagation predicts, and nothing else predicts it.

**In probe these four flops existed but were equally dead.** The module boundary blocked
the propagation, so they were built and never removed. **probe2 is the more correct
netlist, not the more damaged one.**

### The one thing worth acting on

This is a genuine, pre-existing **DFT limitation, not a regression**: the boundary cells
on TDI, TDO and TMS **cannot drive their pads under EXTEST**, in either netlist. Their
*shift* stages work (the chain length and BSDL cell count are right), but their *update*
stages are inert. If the BSDL declares those three pads as EXTEST-drivable, the BSDL is
overstating the silicon. Worth a cross-check in `scripts/bscan_bsdl_crosscheck.py`.

**Also note:** the register's own clock gate `cg_RC_CG_HIER_INST5` is gone in probe2
(`POPT-71`, `lp_clock_gating_min_flops`); the two IR clock gates survive. That is a power
optimisation, functionally neutral, but it does change the register's clock structure
between the two netlists.

---

## 5. Your HIGHZ change is NOT the cause

Stated plainly, as requested.

Removing the `INSN_HIGHZ` arm has exactly one logical effect: **`highz` becomes a
constant 0.** Every remaining arm drives it low —
EXTEST `5'b00110`, SAMPLE `5'b00100`, IDCODE `5'b01000`, CLAMP `5'b10010`,
BYPASS `5'b10000`, default `5'b10000`. So `bsr_highz` folds away and the
`bsr_highz ? 1'b0 : ..._pad_oe_int` mux collapses on 13 bidir + 2 open-drain pads.

That is real, it is intended, and it is **not** capable of deleting the register:

- **`sel_boundary` did not become constant.** It is 1 for EXTEST and SAMPLE_PRELOAD and
  0 elsewhere — unchanged by the edit. The HIGHZ arm had `sel_boundary=0`, and so does
  `default`. The decode's behaviour on that bit is *bit-identical* before and after.
- **`mode` did not become constant.** It is 1 for EXTEST and CLAMP, unchanged.
- **The TDO mux is not stuck on bypass.** `tdo_q_reg` is present in both netlists, and
  the DR path still selects the chain — all 76 `bsr_chain` bits are driven and loaded.
- **The decode did not collapse.** `insn_q[3:0]` is 4 flops in both netlists.
- The `default` arm already returned `5'b10000` for opcode `4'b0100`'s neighbours, so the
  don't-care structure barely moved.

The IDCODE change is likewise visible and harmless: `0x100005A1` → `0x10001001` drops
the set-bit count 6 → 3, and the netlist shows exactly that — `DFSNQD1` (set-type
flops) in the register go **6 → 3**. It confirms both RTL edits landed, and neither
touches the chain.

Could the two edits have shrunk the module below an auto-ungroup size threshold?
Possible in principle, and it cannot be excluded from the evidence on disk — which is
precisely what §6 tests. But the SDC change is the far stronger candidate: it removed an
exception *anchored to the exact hierarchical boundary that dissolved*, and it landed
between the two runs.

---

## 6. Falsifiable predictions

### Prediction A — costs **zero** synthesis runs. Do this first.

Re-run the census on the **existing** `bscan-probe2` netlist with a statement-aware
parser (join lines until `;`, then match `^CELLTYPE\s+instname\s*\(`), or simply count
`u_bsc_` instances ignoring line breaks.

**It will report 115, not 2** — 76 shift + 39 update — and all 76 `bsr_chain` bits
driven and loaded.

*Falsified if* a statement-aware count of probe2 returns anything below 115, or if any
`bsr_chain[1..76]` bit has 0 drivers or 0 loads.

This alone settles the question the run was launched to answer. **No 1.5 h Genus run is
needed to establish that the boundary-scan register survived.**

### Prediction B — costs **one** synthesis run. Only for the flow question.

Restore **only** the two `set_multicycle_path` lines in
`ASIC/genus-innovus/inputs/bscan_constraints.sdc`. Change nothing else — keep the HIGHZ
removal, keep the new IDCODE, same toolkit commit, same flist.

If the MCP-as-hierarchy-pin mechanism is right, that run will show **all** of:

| observable | predicted value | probe2 was |
|---|---|---|
| `"set_multicycle_path"` successful in `read_sdc` stats | **3** | 1 |
| `"get_pins"` successful | **40** | 36 |
| `GLO-51` auto-ungrouped count | **45** | 47 |
| `module nanosoc_eth_chiplet_bscan` in `..._gate.v` | **present** | absent |
| bscan row in `reports/syn_area.rep` | **present, 327 insts** | absent |
| `u_bsc_*` flops (statement-aware) | **119** (76 + 43) | 115 |
| the 4 update flops of §4 | **back** | gone |
| `TIM-316` / `TIM-317` warnings | **3 / 3** | 1 / 1 |

*Falsified if* the module stays ungrouped (`GLO-51` = 47, no bscan row in `syn_area.rep`)
while the multicycles are back. **That outcome would mean the ungrouping is driven by
module size** — i.e. your HIGHZ/IDCODE edits after all — and the correct fix is the
explicit pin, not the constraint.

Either way the actionable fix is the same and does **not** depend on the outcome:

```tcl
# pre_synth.tcl — same idiom already used for u_link_clk_div (log L2749/L2741)
set_db [get_db hinsts -if {.name == *u_nanosoc_eth_chiplet_bscan}] .ungroup_ok false
```

Pin the hierarchy **deliberately** rather than as a side effect of a timing exception
that the file itself documents as bogus. Note this is a *legibility* fix, not a
correctness one: ungrouping cost 4 provably-dead flops and nothing else.

---

## 7. Two holes this exposed

1. **`bscan_constraints.sdc` is invisible to provenance.** It is `source`d from
   `constraints.sdc` (line 248), so `flow_assert_input` never logs its size and
   `syn_provenance.txt` hashes only the **output** `syn_sdc`, never an input SDC. A
   constraint edit that restructured the register's hierarchy left **no trace** in the
   manifest. `prov.design.git_sha` (`8c287ff` → `587c3e3`, both `dirty`) is far too
   coarse to localise it. *Hash every sourced SDC.*

2. **The register-survival check runs at the wrong time and at the wrong altitude.** The
   `error` in `bscan_constraints.sdc` §4 fires at `read_sdc` — after elaborate, before
   mapping — so it can never see a post-synthesis deletion. It correctly did not fire.
   The post-synthesis check is `bscan_syn_verdict.py`, and it counts hierarchy, which
   optimisation is licensed to remove. The existing `SYN: pad ring intact` and
   `SYN: link-clk-div: SURVIVED synthesis` post-synth hooks are the right pattern; the
   register needs the equivalent, written against **connectivity** (76 driven, loaded
   `bsr_chain` bits from `bsr_si` to the TDO mux) rather than against **names**.

The general lesson is the one this repo keeps relearning: *a name-shaped census cannot
survive an optimisation that renames.* The tell was in the data from the first
look — the two survivors were the two shortest names.
