# Boundary-scan "deletion" between bscan-probe and bscan-probe2 — SETTLED STATICALLY

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

Contributors: David Mapstone (d.a.mapstone@soton.ac.uk)

Copyright 2026, SoC Labs (www.soclabs.org)

**Status: NO GENUS RUN IS REQUIRED. The premise is false.**
Written 2026-08-20 against the two netlists already on disk. Every number below is
re-derivable with the commands given; nothing here is inferred from a log summary.

---

## 1. THE HEADLINE

> "117 of 119 boundary-scan cells were deleted."

**They were not.** `bscan-probe2` contains **115 of the 119** boundary flops.
The register is intact: all **76 shift/capture stages are present**, so the scan
chain is still 76 cells long and the BSDL `BOUNDARY_LENGTH` is still correct.

What actually changed is two separate things, neither of them an RTL delta:

| | bscan-probe (08-19 14:06) | bscan-probe2 (08-20 10:36) |
|---|---|---|
| `module nanosoc_eth_chiplet_bscan` in netlist | **present** (972 lines, 166 seq) | **ungrouped into top** |
| boundary flops (`u_bsc_*`) | **119** (76 `_dr_q` + 43 `_update_q`) | **115** (76 `_dr_q` + 39 `_update_q`) |
| total instances | 187,642 | 186,782 |

1. **The hierarchy was dissolved.** Genus auto-ungrouped
   `u_nanosoc_eth_chiplet_bscan` into `nanosoc_eth_chiplet_pads`. Instance names
   survive with a flat prefix (`u_nanosoc_eth_chiplet_bscan_u_bsc_27_...`).
2. **Exactly 4 update stages were deleted**, correctly, as provable dead logic —
   see §4. This is real but small, and it is a *design* fact, not a tool accident.

The "2 cells" figure is a **measurement artefact of counting inside a module
scope that no longer exists**. The repo's own gate reproduces it: run
`scripts/bscan_syn_verdict.py --build .../bscan-probe2` and it prints
`bsr module : ABSENT` / `bsr inst : 0`, because it anchors on
`re.search(r"\nmodule\s+nanosoc_eth_chiplet_bscan\s*\(")`. Its own comment warns
about precisely this class one level down ("COUNT FLOPS, NOT SUBMODULE
INSTANCES. Genus ungroups by default") — and then repeats the mistake for the
parent module. This is the `[[a-zero-that-measured-nothing]]` class: the check
did not measure a deletion, it measured its own missing scope.

---

## 2. WHAT ACTUALLY CHANGED BETWEEN THE RUNS — and it is not RTL

The discriminating input delta is in the **SDC**, not in either RTL commit.

`ASIC/genus-innovus/inputs/bscan_constraints.sdc` used to carry:

```tcl
if {[llength [get_cells -quiet u_nanosoc_eth_chiplet_bscan]]} {
    set_multicycle_path -setup 2 -from [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*] \
                                 -to   [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*]
    set_multicycle_path -hold  1 -from [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*] \
                                 -to   [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*]
}
```

Removed by **`a2ca938` — 2026-08-19 16:44:33** ("bscan: first synthesis PASSES
-- and two of my own checks were wrong").

```
git merge-base --is-ancestor a2ca938 8c287ff  -> NOT an ancestor  (bscan-probe's SHA)
git merge-base --is-ancestor a2ca938 587c3e3  -> IS  an ancestor  (bscan-probe2's SHA)
```

The removal lands **2h38m after bscan-probe's netlist was written** and before
bscan-probe2 started. Three independent traces in the logs confirm the two runs
saw different SDC:

| evidence (`logs/syn.log`) | bscan-probe | bscan-probe2 |
|---|---|---|
| `read_sdc` stats: `set_multicycle_path` successful | **3** | **1** |
| `read_sdc` stats: `get_pins` successful | **40** | **36** |
| `TIM-316/317` on `hpin:…/u_nanosoc_eth_chiplet_bscan/tck` | **4 warnings** | **absent** |

The arithmetic closes exactly: 2 removed MCP commands × (`-from` + `-to`) = 4
`get_pins`; `constraints.sdc:236` supplies the one surviving MCP.

**Mechanism.** `auto_ungroup` defaults to `both` and is never overridden by this
toolkit (`genus_attref` p.1175: *"Default: both … Aggressive ungrouping of user
hierarchies happens during RTL optimization—syn_generic … Technology
mapping—syn_map"*). So **ungrouping is the default behaviour and bscan-probe was
the exception**. The only input that was scoped specifically to that hierarchy
was the MCP pair, which bound timing exceptions to its hierarchical boundary
pins — Genus must keep an hpin that carries an exception, which pins the hinst
against auto-ungroup. Remove the exception, and the hierarchy dissolves like
every other unprotected module in this design (cf. `WlinkGenericFCSM*`, already
absorbed in the shipping netlist).

*Honesty note:* the hpin-pins-the-hierarchy step is inferred from Genus behaviour
plus the evidence above, not quoted from the manual. It does not change the
conclusion or the fix — §6's single run tests it directly if anyone wants it
nailed.

---

## 3. BOTH RTL CANDIDATES ARE EXONERATED — with a positive control

**Neither RTL delta can make the boundary chain unreachable or unobservable.**

* **IDCODE `0x100005A1` → `0x10001001`.** A parameter on a parallel-load shift
  register in the wrapper. It touches no select, no chain path, no enable.
  `sel_boundary` is not a function of it.
* **`INSN_HIGHZ` arm removed from `bscan_ir.sv`.** Read the decode table
  (`src/rtl/bscan/bscan_ir.sv:200-231`): `sel_boundary` is bit 2 of `dec` and is
  asserted **only** by `INSN_EXTEST` (`5'b00110`) and `INSN_SAMPLE_PRELOAD`
  (`5'b00100`). The deleted arm was `INSN_HIGHZ : dec = 5'b10001` — `sel_bypass`
  and `highz`, with `sel_boundary` **already 0**. Deleting it moves opcode
  `4'b0100` from one `sel_boundary=0` row to another `sel_boundary=0` row
  (`default : dec = 5'b10000`). The only signal that changes is `highz`, which
  becomes a constant 0 and collapses the 15 `assign X_pad_oe = bsr_highz ? … `
  muxes. **`sel_boundary` is bit-identical before and after.**

**Positive control — the new RTL really is in bscan-probe2.** The 32 `idcode_q`
flops take their reset value from the async set/clear pin, so the count of
set-style flops *is* the IDCODE popcount:

```
bscan-probe   : 6 set-style / 26 clear-style   popcount(0x100005A1) = 6  ✓
bscan-probe2  : 3 set-style / 29 clear-style   popcount(0x10001001) = 3  ✓
```

bscan-probe2 was built from the post-`61aa090` RTL (`project_git_sha 587c3e3`,
which contains both commits) and the register survived anyway. That is a
measurement, not an assumption, and it is what makes a bisect run redundant.

---

## 4. THE REAL 4-CELL DELTA — provable dead logic on the three TAP-muxed pads

The four flops that genuinely disappeared:

```
u_bsc_05_SWDIO_IO_oe_update_q_reg     DFNCND1
u_bsc_23_HOST_IO_1_oe_update_q_reg    DFNCND1
u_bsc_24_HOST_IO_1_data_update_q_reg  DFNCND1
u_bsc_26_HOST_IO_0_oe_update_q_reg    DFNCND1
```

All four sit on the three pads the TAP is muxed onto — **SWDIO_IO = TMS,
HOST_IO_0 = TDI, HOST_IO_1 = TDO** — and all four are killed by the same
override in the pad ring (`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`):

```
:350  wire bscan_en = bsp_se_i_in;
:351  wire bsp_host_io_1_out_muxed = bscan_en ? bscan_tdo    : bsp_host_io_1_out;
:352  wire bsp_host_io_1_oe_muxed  = bscan_en ? bscan_tdo_oe : bsp_host_io_1_oe;
:358    .trst_n  (bscan_en),          // the TAP's reset IS bscan_en
:556  uPAD_SWDIO_IO  .OEN ((bscan_en ? tiehi : ~bsp_swdio_io_oe))
:623  uPAD_HOST_IO_0 .OEN ((bscan_en ? tiehi : ~bsp_host_io_0_oe))
```

and, in the wrapper, `nanosoc_eth_chiplet_bscan.sv:433`:

```
wire bsr_mode = ir_mode & trst_n & ~tlr;      // trst_n == bscan_en
```

So `mode` ⇒ `bscan_en`. The update value can only reach a pin while `mode=1`,
i.e. while `bscan_en=1` — and in exactly that branch the pad ring throws the
value away (`OEN=tiehi`, or the TDO mux takes over). **The BSR drive value can
never reach those pins, under any input.** Deleting the flops is correct.

The asymmetry confirms the mechanism precisely — 4/4, no residue:

| pad | top-level override | oe update | data update |
|---|---|---|---|
| HOST_IO_1 (TDO) | out **and** oe muxed on `bscan_en` | **deleted** (u_bsc_23) | **deleted** (u_bsc_24) |
| HOST_IO_0 (TDI) | OEN only | **deleted** (u_bsc_26) | kept (u_bsc_27) |
| SWDIO_IO (TMS) | OEN only | **deleted** (u_bsc_05) | kept |

The two surviving data cells drive the pad's `.I` pin, which Genus treats as a
real load — it does not reason through a library IO cell's tristate to prove `I`
unobservable when `OEN=1`. The `oe` paths, by contrast, share the *same select
net* as the override and collapse by plain constant folding.

**This deletion requires seeing across the module boundary**, which is only
possible once the hierarchy is ungrouped. That is why the same RTL produced 119
in bscan-probe and 115 in bscan-probe2, and it is a second, independent
confirmation that the ungroup — not the RTL — is the operative change.

**The genuine engineering finding**: the pad table gives EXTEST control cells to
the three TAP pads, and those cells are unimplementable by construction. The
padring override is right (you must not let EXTEST drop the TAP mid-test); the
pad table and BSDL are what disagree with silicon. IEEE 1149.1 Clause 10 excludes
TAP pins from the boundary register for exactly this reason. Nothing here is a
tapeout stopper — the chain length is unchanged and shift/SAMPLE still work —
but §7 lists the decision it forces.

Also seen, and *not* deletions: 15 cell-type swaps (7× `SDFCNQD1→DFCNQD1`,
8× `SDFCNQD1→SDFCNQD0`) — drive/variant churn from re-optimising after the
ungroup.

---

## 5. RE-DERIVE EVERY NUMBER (free, ~20 s, no EDA licence)

Ungroup-proof census — scopes on the module when it exists and on the flat
instance prefix when it does not:

```bash
cd /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/ASIC/eth-chiplet/build
python3 - <<'EOF'
import re, pathlib
def census(d):
    src = (pathlib.Path(d)/"outputs/nanosoc_eth_chiplet_pads_gate.v").read_text()
    mm = re.search(r"\nmodule\s+nanosoc_eth_chiplet_bscan\s*\(.*?\nendmodule", src, re.S)
    if mm: scope, pref = mm.group(0), ""
    else:  scope, pref = re.search(r"\nmodule\s+nanosoc_eth_chiplet_pads\s*\(.*?\nendmodule",
                                   src, re.S).group(0), "u_nanosoc_eth_chiplet_bscan_"
    out = {}
    for c, n in re.findall(r"^\s+([A-Z][A-Z0-9_]*)\s+(\\?\S+?)\s*\(", scope, re.M):
        if not re.match(r"(S?DF|EDF|QDF)", c): continue
        n = n.lstrip("\\")
        if "u_bsc_" not in n: continue
        out[n[len(pref):] if pref and n.startswith(pref) else n] = c
    return out
a, b = census("bscan-probe"), census("bscan-probe2")
print("probe %d   probe2 %d" % (len(a), len(b)))
for k in sorted(set(a) - set(b)): print("  DELETED:", k, a[k])
EOF
```
Expect `probe 119   probe2 115` and the four `DELETED:` lines from §4.

Input delta:
```bash
for d in bscan-probe bscan-probe2; do
  echo "== $d"; grep -E '"(set_multicycle_path|get_pins)"' $d/logs/syn.log
  grep -c "u_nanosoc_eth_chiplet_bscan/tck" $d/logs/syn.log
done
git log --oneline -S "set_multicycle_path -setup 2 -from [get_pins u_nanosoc_eth_chiplet_bscan" \
        -- ASIC/genus-innovus/inputs/bscan_constraints.sdc
```

---

## 6. IF A RUN IS STILL WANTED — the ladder, cheapest first

### 6a. FREE (minutes, one Genus licence, no synthesis)

Both runs wrote a reloadable session. Query bscan-probe2's database directly
instead of rebuilding it:

```bash
cd /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/ASIC/eth-chiplet/build/bscan-probe2
genus -no_gui -files /dev/stdin < /dev/null <<'TCL'
read_db outputs/nanosoc_eth_chiplet_pads_syn_session
puts "hinst  : [llength [get_db hinsts -if {.name == *u_nanosoc_eth_chiplet_bscan}]]"
puts "bsr    : [llength [get_cells -hier -filter {name =~ *u_bsc_*_q_reg}]]"
puts "excepts: [llength [get_db exceptions]]"
exit
TCL
```
*(`< /dev/null` is mandatory — `[[eda-cli-stdin-traps]]`: Genus holds a licence at
an interactive prompt forever.)*

### 6b. ONE GENUS RUN (~1.8 h) — and it is a candidate fix, not just a probe

Do **not** run "revert the IDCODE" or "restore the HIGHZ arm". Both hypotheses are
already refuted by §3's flop census and its positive control; those runs would
each cost 1.8 h to re-confirm 115, and neither can distinguish the ungroup.

The one run worth doing **pins the hierarchy back** — it tests the §2 mechanism
directly, and if it passes it *is* the change you land.

**The patch** (append to `ASIC/eth-chiplet/hooks/pre_synth.tcl`; the hook is
sourced after `elaborate` and before `syn_generic`, which is the only window in
which `ungroup_ok` binds — `1_synthesis.tcl:933`):

```tcl
# --- boundary-scan register ---------------------------------------------------
# Genus `ungroup_ok` defaults to true and auto_ungroup runs at the Genus default
# here, so this hierarchy is dissolved unless it is pinned. It was accidentally
# pinned until 2026-08-19 by a set_multicycle_path bound to its hierarchical
# pins; a2ca938 removed that (correctly — it was a broken exception), and the
# register was ungrouped from the next run onward. Pin it on purpose instead.
# Same instrument and same fail-loud rule as protect_link_clk_div.tcl.
set _bs_forms {
    {get_db hinsts -if {.module.name == nanosoc_eth_chiplet_bscan}}
    {get_db hinsts -if {.name == *u_nanosoc_eth_chiplet_bscan}}
    {get_cells -hierarchical -filter {ref_name =~ nanosoc_eth_chiplet_bscan*}}
    {get_cells -hierarchical -filter {name =~ *u_nanosoc_eth_chiplet_bscan*}}
}
set _bs_done 0
foreach _f $_bs_forms {
    if {![catch {eval $_f} _hits] && [llength $_hits] > 0} {
        foreach _h $_hits { catch {set_db $_h .ungroup_ok false} }
        say "bscan: ungroup_ok=false on [llength $_hits] instance(s) via: $_f"
        set _bs_done 1
        break
    }
}
if {!$_bs_done} {
    error "bscan: no query form matched the nanosoc_eth_chiplet_bscan hierarchy\
           before syn_generic. Do NOT waive by deleting this - find the form\
           that matches (see the QUERY SPELLING note in protect_link_clk_div.tcl)."
}
unset -nocomplain _bs_forms _f _hits _bs_done
```

**Launch (one command, from the repo root):**

```bash
make asic-syn RUN_TAG=bscan-ungroup
```

Leave every other knob at its default (`SYN_ISPATIAL=0`, `SYN_EXTRA_OPT=1`,
`SYN_STRICT=1`) — identical to both probes. Do **not** trim `SYN_EXTRA_OPT` to
save time: the deletion could occur in that pass, and a shortened run would
confound the result with the thing being measured.

**What to grep from the result:**

```bash
B=ASIC/eth-chiplet/build/bscan-ungroup
grep -c "^module nanosoc_eth_chiplet_bscan"  $B/outputs/nanosoc_eth_chiplet_pads_gate.v
grep -n "bscan: ungroup_ok=false"            $B/logs/syn.log
python3 scripts/bscan_syn_verdict.py --build $B --control ASIC/eth-chiplet/build/bscan-probe
# plus the §5 census, run over bscan-ungroup
```

**Decision table:**

| module def | boundary flops | meaning | action |
|---|---|---|---|
| 1 | **119** | §2 + §4 confirmed end to end: the ungroup was the whole story, both RTL deltas fully exonerated, and the 4 cells return | land the patch; fix `bscan_syn_verdict.py`; take the §7 BSDL decision |
| 1 | **115** | hierarchy pinned but the 4 still die → §4's cross-boundary argument is wrong and the deletion is intra-module | re-open on the RTL deltas; next probe = restore the `INSN_HIGHZ` arm alone |
| 1 | **< 115** | pinning the hierarchy made things worse (blocked an opt that was holding something alive) | do not land; capture `syn_qor.pre_opt.rep` vs final and diff |
| 0 | any | the attribute never bound — query spelling | the `error` above fires first and aborts the stage; fix the form, re-run |

**Restoring the tree afterwards:**
```bash
git checkout -- ASIC/eth-chiplet/hooks/pre_synth.tcl      # if not landing
rm -rf ASIC/eth-chiplet/build/bscan-ungroup                # scratch tag only
```
`bscan-probe` and `bscan-probe2` are untouched — the new tag is a separate build
directory, and `inputs/` and `scripts/` inside it are symlinks to the shared
originals. **Do not run this in an existing tag**: `bscan_syn_verdict.py` already
warns that a shared tag makes it judge a netlist that is not the one its timing
report describes. Nothing in this plan modifies RTL, SDC or any flow file.

---

## 7. FOLLOW-UPS THIS RAISES (not part of the experiment)

1. **`scripts/bscan_syn_verdict.py` cannot see an ungrouped register.** It calls a
   perfectly good netlist "optimised away entirely". Fix: fall back to the flat
   `u_nanosoc_eth_chiplet_bscan_*` prefix when the module scope is missing (the
   §5 census is the shape), and report *ungrouped* distinctly from *deleted*.
   Until then its verdict on any unpinned run is meaningless in both directions.
2. **Three TAP pads carry EXTEST control cells that cannot work** (§4). Either
   pin the hierarchy so they at least exist as declared, or — better — drop those
   four control cells from `pad_table.json` and the BSDL so the artefact stops
   promising drive that silicon cannot deliver. The BSDL/RTL disagreement class
   that `f76df69` was written to close is the same class as this one.
3. **A third input drifted between the probes** and is unrelated to bscan: the
   IMEM preload parameter went from `src/rtl/eth_imem_alive.hex` to `image.hex`
   (`reports/syn_hierarchy.rep:34`). Worth knowing before anyone compares these
   two tags for anything else.
