# KR260 parity test — nanoSoC FPGA Toolkit vs `tidelink/fpga`

**Date:** 2026-09-08 · **Host:** srv03335 · **Tool:** Vivado 2024.1
(`/apps/Xilinx/Vivado/2024.1`) · **Part:** xck26-sfvc784-2LV-c ·
**Target:** `kr260-eth-chiplet` (die_a, `DEVICE_CLASS=1`)

## Verdict

**The new flow did not reach a bitstream. It cannot build this design today, and
the blocking defect is in the toolkit, not in this project's manifest.**

`make all` failed at stage 3 of 6 (`bd`). With a shim past that, it failed at
stage 4 (`synth`) on a defect no value of any contract variable in `design.mk`
can fix: the toolkit never calls `generate_target`, so a block design's
synthesisable HDL is never produced, and the board-level top cannot find the
module it instantiates.

Because no netlist, no routed checkpoint and no bitstream were produced, **the
utilisation / timing / netlist / bitstream / constraint comparisons this test
exists to make could not be run.** Only the left-hand column exists. Everything
below that reads as a comparison is a comparison of *inputs and mechanisms*,
which is all the evidence there is.

---

## 1. What was run

| | NEW | OLD |
|---|---|---|
| command | `make all RUN_TAG=parity-new` in `fpga/` | not rebuilt — existing artefact used |
| result | **FAILED at `bd`** | bitstream on disk, provenance verified below |
| run dir | `fpga/build/parity-new/` | `tidelink/imp/fpga/output/kr260-eth-chiplet/` |

A second run, `RUN_TAG=parity-wa`, was made with deliberate workarounds to find
out *how far* the toolkit could get. It reached the `bd` gate green and then
failed at `synth`. Section 5 lists every workaround; **that run is not parity
and is not offered as one.**

### The old flow's artefact, and why it is legitimate to reuse

`tidelink/imp/fpga/output/kr260-eth-chiplet/tidelink.bit`, 7 797 819 bytes,
2026-08-21 09:54.

```
$ head -c 200 tidelink.bit | strings
9tidelink_design_wrapper;UserID=0XFFFFFFFF;Version=2024.1
xck26-sfvc784-2LV-c
2026/08/21
        09:54:38
$ sha256sum tidelink.bit
6dbee2740dd9edd189a83d59bac998844922565f6716c932696e367b0918acba
```

That sha256 matches `tidelink_manifest.json`'s `"sha256"` field exactly, and the
manifest's `"source_commit": "5e8bdb5a2141ff5a82103813a326a2c9df2b43ed-dirty"`
is the **current** HEAD of the `tidelink` submodule — whose only working-tree
dirt today is two untracked paths (`dut_src.f`,
`imp/hw_gate/tl042_recovery_proto/`). The routed DCP, the timing report and the
Vivado run log from that build are all still on disk. Rebuilding would have cost
~45 minutes and produced nothing this does not already give.

**Provenance defect found in the old flow while checking this.** The manifest
records `"usr_access": "0xdf2b43ed"`, and the bitstream does not carry it. The
build log says so in as many words:

```
build_design.log:4424
USR_ACCESS: tree dirty/unknown (5e8bdb5a2141...-dirty) - NOT stamping a commit SHA
```

`build_design.tcl:639` stamps `TIDELINK_GIT_USR_ACCESS` only on a clean tree;
`scripts/build_provenance.tcl:276-279` computes the manifest field by *stripping*
`-dirty` and taking the low 32 bits unconditionally. So the manifest asserts a
register value the build explicitly declined to write. Anyone reading USR_ACCESS
back off a board and diffing it against this manifest will be sent hunting for
the wrong thing. This is unrelated to the toolkit and is the old flow's to fix.

---

## 2. What actually happened in the new flow

### Stage 1 `flist` — PASS

```
HARD FAILURES: none
```
596 source files resolved; `work/sources.tcl` written (89 903 bytes).

### Stage 2 `package-ip` — correctly skipped

`PACKAGE_TCL` is empty, so the stage records "not configured" and exits 0, as
CONTRACT §12.2 rule 7 requires.

### Stage 3 `bd` — **HARD FAIL**

```
fpga/build/parity-new/reports/bd_gate.txt

HARD FAILURES: 1
  - BD_TCL ran and NO block design exists afterwards. Vivado reports a failed
    create_bd_design as an ERROR and still exits 0, so the exit status said
    nothing. Check that BD_TCL calls create_bd_design, and that nothing in it
    caught the error.
```

No Vivado `ERROR` was emitted anywhere in `bd.log`. The gate is right and the
message is right.

**Cause.** `BD_TCL` points at
`tidelink/fpga/targets/kr260-eth-chiplet/tidelink_design.tcl`, which is **not a
script that builds a block design**. It is a library: its only top-level
construct is `proc create_root_design { parentCell }`. `grep` over the whole
file finds no `create_bd_design` and no call to `create_root_design`. The legacy
flow supplies both itself:

```
build_design.tcl:247   source $target_dir/tidelink_design.tcl
build_design.tcl:264-271  add_files tidelink_phy_clk_div2*.v ; update_compile_order
build_design.tcl:347-349  set design_name tidelink_design
                          create_bd_design $design_name
                          create_root_design ""
```

The toolkit's `flow/vivado/3_bd.tcl:408` does only `source $BD_TCL` and then
asserts a block design exists.

**Who owns it.** The project manifest. `BD_TCL`'s contract is "sourcing this
creates the block design", and this file does not meet it. `make check` reports
`ok BD_TCL <path>` because it checks only that the file exists — a gap worth
raising, but the manifest is the thing that is wrong.

### Stage 4 `synth` — **HARD FAIL (toolkit)**

Reached only in the workaround run. Three separate failures, in order:

**4a.** The project's own `pre_synth.tcl` refused:

```
SYNTH-FAIL: row names ip 'nanosoc_eth_chiplet_0', which is not in this project.
SYNTH-FAIL:   Check the instance name with: get_ips
```

The `RTL_ASSERT_TABLE` row names the **block-design cell** name. The Vivado IP
object is `tidelink_design_nanosoc_eth_chiplet_0_0`. But correcting it to the
fully-qualified name failed identically:

```
SYNTH-FAIL: row names ip 'tidelink_design_nanosoc_eth_chiplet_0_0', which is not in this project.
```

`get_ips` returns nothing at this seam at all, because the synth stage runs
in-memory and the BD's IP objects live in the *separate* project stage 3 built.
**The `ip` key of the shipped `pre_synth.tcl` template cannot be used by any
BD-based design.** That is a toolkit/template defect, not a manifest typo.
Dropping the `ip` key made the row pass against the fileset generic:

```
fpga/build/parity-wa/reports/rtl_assert_pre_synth.txt
verdict                  PASS
generic                  NUM_PHY_LANES=8 DEVICE_CLASS=1
verilog_define           ETH_WISHBONE_B3
```

**4b.** With the hook satisfied, synthesis died:

```
ERROR: [Synth 8-439] module 'tidelink_design' not found
       [.../targets/kr260-eth-chiplet/tidelink_design_wrapper.v:90]
ERROR: [Synth 8-6156] failed synthesizing module 'tidelink_design_wrapper'
```

**Cause — this is the finding.** `generate_target` appears **nowhere in the
toolkit**:

```
$ grep -rn "generate_target" flow/ mk/     # in nanoSoC-FPGA-Toolkit
$                                          # (no output)
```

The legacy flow calls it (`build_design.tcl:455`) and its project therefore has
the BD's synthesisable HDL on disk:

```
tidelink_project.gen/sources_1/bd/tidelink_design/synth/tidelink_design.v   19792 bytes
tidelink_project.gen/sources_1/bd/tidelink_design/hdl/tidelink_design_wrapper.v
```

The toolkit's run has neither — its `.gen` tree holds only `ip/`, `.bda` and
`.bxml`. A `.bd` file is not synthesisable on its own, so the board top's
`tidelink_design tidelink_design_i (...)` is an unresolved module.

**4c.** Supplying the missing `generate_target` at the `pre_synth` seam does
**not** fix it, and the failure explains why the handoff is structurally lossy:

```
PARITY-HOOK: generate_target FAILED: ERROR: [Common 17-39] 'generate_target' failed due to earlier errors.

ERROR: [BD 41-1712] The specified IP 'xilinx.com:ip:zynq_ultra_ps_e:3.5' does not
                    support the current part 'xc7vx485tffg1157-1'
ERROR: [BD 41-595]  Failed to add ip repository block <zynq_ultra_ps_e_0>
CRITICAL WARNING: [filemgmt 56-176] Module references are not supported in manual
                    compile order mode and will be ignored.
CRITICAL WARNING: [BD 41-1726] Unable to resolve module-source for block '/phy_clk_div2_0'.
INFO: [BD 41-434] Could not find an IP with XCI file by name: tidelink_design_nanosoc_eth_chiplet_0_0
```

Two independent structural problems are visible in that block:

1. **The in-memory design has no part when `read_bd` runs.**
   `xc7vx485tffg1157-1` is Vivado's default Virtex-7, not `xck26`. The toolkit
   passes the part only later, on the `synth_design -part` command line
   (`4_synth.tcl:556`); `Loading part xck26-sfvc784-2LV-c` does not appear in the
   log until line 3880, *after* the BD has been read and every IP in it has
   failed to resolve.
2. **The in-memory flow is in manual compile-order mode**, so the
   `tidelink_phy_clk_div2` module reference can never resolve. This is precisely
   what `build_design.tcl:250-253` warns about: *"Module references only resolve
   in automatic-compile-order mode against a file already in sources_1."*

CONTRACT §5 says handoff between stages is "by artefact name inside `work/`". For
a block design that is not sufficient: a `.bd` is not self-contained, and copying
it to "the contract path" separates it from the IP output products and the
project context it needs. The `bd` stage's own log records the copy:

```
BD:   copied to the contract path: .../build/parity-wa/work/tidelink_design.bd
```

### Stages 5-6 `impl`, `bitstream` — never reached.

---

## 3. The numbers

Everything measurable exists on one side only.

| metric | OLD (`tidelink/fpga`, routed) | NEW |
|---|---|---|
| bitstream | 7 797 819 B, 2026-08-21 09:54:38 | **not produced** |
| routed DCP | 48 697 181 B | **not produced** |
| CLB LUTs | 59 658 (50.94 %) | — |
| CLB Registers | 54 336 (23.20 %) | — |
| LUT as Logic / Memory | 58 893 / 765 | — |
| CLB | 12 860 (87.84 %) | — |
| CARRY8 / F7 / F8 | 986 / 3 324 / 501 | — |
| Block RAM Tile | 32.5 (22.57 %) | — |
| DSPs | 7 (0.56 %) | — |
| Bonded IOB | 34 (17.99 %) | — |
| MMCM / PLL / BUFGCTRL | 1 / 0 / 0 | — |
| WNS / TNS | **0.247 ns** / 0.000 ns | — |
| WHS / THS | **-22.273 ns** / -177.926 ns (8 failing endpoints of 116 678) | — |
| primitive cells | 131 005 | — |
| nets | 352 170 | — |
| ports / clocks | 34 / 11 | — |
| synth runtime | 12 min 58 s | n/a |
| total build | ~43 min (09:11 → 09:54) | died at 14:37 (bd), ~90 s in |

Synthesis-stage utilisation for the old flow, for completeness: LUT 60 756,
FF 54 451, BRAM 32.5, DSP 7, IOB 34, MMCM 1.

The old build does **not** meet timing: `Timing constraints are not met.` — WHS
-22.273 ns on 8 endpoints. That is the shipping baseline, not a regression found
here.

**Bit-for-bit bitstream comparison, cell-count-by-`REF_NAME` comparison, per-port
`PACKAGE_PIN`/`IOSTANDARD` comparison and clock-definition comparison were all
prepared and all are unrunnable.** The probe that would have done it
(`build/_parity/dcp_probe.tcl`) ran successfully against the old checkpoint and
its outputs are in `build/_parity/probe/` as the baseline half; there is no
second half to diff it against.

---

## 4. Differences found, and which are explicable

Ordered by how much they would change the silicon.

### D1 — the two flows assemble the design differently. NOT explicable as a flow detail.

The old flow's Vivado project fileset holds **two** loose HDL files:

```
$ grep -oE '<File Path="[^"]*"' tidelink_project.xpr | grep -cE '\.(v|sv|svh)$'
2
    tidelink_design_wrapper.v
    tidelink_phy_clk_div2.v
```

`build_design.tcl` reads no RTL filelist at all. The entire SoC, TideLink,
TideChart and the ethernet MAC arrive through the **packaged IP**
`nanosoc_eth_chiplet`, built by a separate `make package_eth_chiplet_ip` step.

The new flow's fileset holds **596** source files (`SYNTH: source files declared
by the flist: 596`) *plus* the same packaged IP, because `RTL_FLIST` points at
the full SoC flist while `IP_REPOS` points at the legacy flow's IP outputs. Every
SoC module is therefore present twice: once loose, once inside the IP. This is a
direct consequence of `fpga/README.md`'s known hole 2 — "this manifest currently
consumes a packaged IP it cannot itself produce" — and it is larger than that
sentence suggests: it is not only that the IP cannot be produced, it is that the
sources which *would* produce it are also being fed to the top-level synthesis.

Whether that produces a different netlist is untested, because synthesis never
completed.

### D2 — `TIDELINK_PHY_V2` does not reach synthesis in the new flow. NOT explicable.

Old flow, Aug-21 log:

```
build_design.log:814   verilog_define injected into run synth_1 : -verilog_define TIDELINK_PHY_V2
build_design.log:852   Command: synth_design -top tidelink_design_wrapper
                       -part xck26-sfvc784-2LV-c -verilog_define TIDELINK_PHY_V2
```

New flow, from its own written artefact:

```
fpga/build/parity-wa/reports/rtl_assert_pre_synth.txt
verilog_define           ETH_WISHBONE_B3
declared_rtl_defines     (none)
```

`design.mk` puts `TIDELINK_PHY_V2` in `RTL_DEFINES_INBODY`. That variable is
delivered by exactly one stage — `2_package_ip.tcl`, "THE MATERIALISER" — and
`1_flist.tcl:434` states the rest plainly: *"RTL_DEFINES_INBODY NEVER REACHES
synth_setup's LIST AT ALL."* With `PACKAGE_TCL` empty, stage 2 does not run, so
the define is **declared and never delivered**.

Five files in the new flow's own top-level fileset read it:
`src/rtl/nanosoc_eth_chiplet.sv`, `tidelink/src/rtl/fifo/tidelink_apb_regs.sv`,
`tidelink/src/rtl/v2shims/{v2_Wlink.v, v2_axi_chiplet_controller.sv,
v2_tidelink_top.sv}`.

The other two in-body defines are safe by accident: `TD_AUTO_LANE_MASK_E4` and
`RAM_PRELOAD` are baked into the packaged IP by
`tidelink/fpga/vivado_ip/nanosoc_eth_chiplet_filelist.tcl`, and the new flow
consumes that same prebuilt IP. `TIDELINK_PHY_V2` is the one the legacy flow
delivers on the *synthesis command line*, deliberately scoped to `synth_1` only
(`build_design.tcl:495-499` explains why), and that mechanism has no equivalent
in the new flow.

### D3 — `FLOW_MODE=project` is declared and ignored. Explicable, but it is the root of D2.

`design.mk` sets `FLOW_MODE ?= project`. `flow/vivado/4_synth.tcl:64` says:
*"It does not implement FLOW_MODE=project's `launch_runs synth_1` path."* The
stage always runs in-memory and records the deviation in its NOT-COVERED list
rather than failing. The old flow's per-run `STEPS.SYNTH_DESIGN.ARGS.MORE
OPTIONS` define injection has nowhere to live in an in-memory flow, which is
*why* D2 exists.

### D4 — `BD_WRAPPER` name collision. Real, but **explicable** — the old flow has it too.

The toolkit's `BD_WRAPPER=1` calls `make_wrapper -top -force -import`, producing
a module named `<DESIGN_NAME>_wrapper` = `tidelink_design_wrapper` — the same
name as the project's hand-written board top in `TOP_HDL`. I set `BD_WRAPPER=0`
in the workaround run to avoid it.

**That precaution turns out to have been unnecessary, and I record it as an
error of caution rather than a finding.** The old flow generates the same
colliding file (`.gen/.../hdl/tidelink_design_wrapper.v`, 2 529 B) and Vivado
resolves in favour of the explicitly-added source:

```
build_design.log:971
INFO: [Synth 8-6157] synthesizing module 'tidelink_design_wrapper'
  [.../targets/kr260-eth-chiplet/tidelink_design_wrapper.v:25]
```

That is the 5 055-byte hand-written top, the one carrying the SWDIO and MDIO
`IOBUF`s. It matters: the old design's ports include `MDIO` and `SWDIO` as
`INOUT`, which only exist because of those IOBUFs. The auto wrapper would expose
six unidirectional ports instead and the pin XDC would not match. The toolkit's
own `bd_gate.txt` is candid that it does not check this:

> *whether the wrapper is what TOP instantiates. The wrapper's module name is
> recorded here; nothing checks that the board-level top names it*

So: same hazard in both flows, resolved the same way, **unproven under the
toolkit** because synthesis never ran.

### D5 — `EXTRA_SRCS` is not in the fileset when the BD needs it. Explicable; a knob exists.

The BD instantiates the `/2` divider by module reference. That resolves only
against a file already in `sources_1`. The toolkit reads `TOP_HDL`/`EXTRA_SRCS`
in **stage 4** (`4_synth.tcl:391`), and `FLIST_TOP_IN_SOURCES` defaults to `0`,
so at stage 3 the divider is absent. Setting `FLIST_TOP_IN_SOURCES=1` would fix
it; I used the shim's own `add_files` instead, mirroring the legacy flow.

### D6 — a stray `nanosoc_eth_chiplet_bd.gen/` was written into the repository root.

Caused by my `generate_target` probe, not by an unmodified toolkit run
(`CRITICAL WARNING: [IP_Flow 19-4739] Writing uncustomized BOM file
'/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/nanosoc_eth_chiplet_bd.gen/...'`).
8 files. **Moved to `fpga/build/_parity/stray_repo_root_bd_gen/` and the repo
root restored to its starting `git status`.** Recorded because it shows the
in-memory BD path writes outside the run tree, which CONTRACT §5 forbids.

### Explicable and matching — checked, no difference found

- **XDC read window.** Old: pins XDC both, timing + DRC `USED_IN_SYNTHESIS
  false` / `USED_IN_IMPLEMENTATION true` (`build_design.tcl:365-386`). New:
  identical, `4_synth.tcl:458-459` and `5_impl.tcl:335-336`. The new flow's log
  states it explicitly, and it is right.
- **The XDC files themselves.** `design.mk` points at the *same three files* in
  `tidelink/fpga/targets/kr260-eth-chiplet/`; nothing was copied, so they cannot
  drift.
- **BD global synthesis.** `BD_GLOBAL_SYNTH=1` → `synth_checkpoint_mode None`,
  matching `build_design.tcl`'s setting.
- **Optional XDCs.** `FPGA_USE_IDELAY=0` and `FPGA_TIDELINK_EXTREFCLK=0` match
  the old flow's defaults; neither file exists in this target dir anyway.
- **`bd_8888`.** The new flow's `bd` log reports two block designs
  (`bd_8888 tidelink_design`). Benign — `bd_8888` is the AXI SmartConnect's own
  nested BD, and it exists identically in the old flow's project.
- **`RTL_PARAMS`.** `NUM_PHY_LANES=8 DEVICE_CLASS=1` reached the fileset and the
  assertion passed.

---

## 5. Workarounds used — and why this is not a parity result

Four, all outside the project tree, all in `fpga/build/_parity/`:

1. **`BD_TCL` replaced with a shim** (`build/_parity/bd_tcl_shim.tcl`) that does
   the `add_files` + `create_bd_design` + `create_root_design ""` the legacy
   flow does. Without it, stage 3 fails.
2. **`BD_WRAPPER=0`.** Precautionary; D4 shows it was not needed.
3. **`RTL_ASSERT_TABLE` rewritten** to drop the `ip` key. Without it, stage 4's
   own hook refuses.
4. **`HOOKS_DIR` redirected** to a build-local `pre_synth.tcl` calling
   `generate_target`. It failed, and its failure is the evidence in §2/4c.

Nothing under `nanoSoC-FPGA-Toolkit/`, `tidelink/`, or any tracked project file
was modified. Nothing was committed or staged. No board was touched.

**A build that needs four undocumented workarounds and still does not synthesise
is not parity, and the workaround run's artefacts must not be read as one.**

---

## 6. What this test could not prove

- Whether the two flows produce the **same netlist**. No new netlist exists.
- Whether the **same constraints** are applied to the **same ports**. The read
  window and the files match by inspection; nothing was measured on a design.
- Whether D1 (the same RTL entering twice) causes module-resolution conflicts.
- Whether D2 changes behaviour. `TIDELINK_PHY_V2` demonstrably does not reach
  the new flow's synthesis; what that *does* to the design is untested, and the
  legacy comment warning that enabling it more widely would "switch on three
  previously-dead code blocks in a silicon-proven configuration" suggests the
  reverse direction deserves the same care.
- Whether the toolkit can build a design **without** a block design. Everything
  that failed here is BD-specific. `flist` passed cleanly and its verdict was
  honest.

## 7. What would have to change

**Toolkit (blocking, in order):**

1. Generate the BD's output products. `generate_target` exists nowhere in the
   flow. Doing it in stage 3, inside the project that owns the BD, is the only
   place it can work.
2. Fix the stage-3 → stage-4 handoff. A bare `.bd` copied by name is not a
   sufficient artefact. Either carry the generated `synth/<bd>.v` and the IP
   output products, or hand over the project.
3. Set the part on the in-memory design **before** `read_bd`, not on the
   `synth_design` command line. Reading a Zynq UltraScale+ BD against a default
   Virtex-7 part cannot work.
4. Either implement `FLOW_MODE=project` or make declaring it an error. Silently
   ignoring it and noting the deviation in a NOT-COVERED list is how D2 got in.
5. `pre_synth.tcl`'s `ip` key is unusable for BD designs — `get_ips` is empty at
   that seam. Either resolve BD IP or say the key does not apply.
6. Consider whether `BD_TCL`'s contract should be checked, not assumed.
   `make check` said `ok BD_TCL` for a file that defines a proc and builds
   nothing.

**Project manifest:**

7. `BD_TCL` must name something that actually creates the block design.
8. `TIDELINK_PHY_V2` must be delivered by a mechanism that runs. `RTL_DEFINES`
   (command line) is the honest home for it while stage 2 is unconfigured.
9. `RTL_ASSERT_TABLE`'s `ip` field names a BD cell, not a Vivado IP instance.
10. Decide what `RTL_FLIST` is *for* when the SoC arrives via a packaged IP.
    Feeding both is D1.

---

## Artefacts

```
fpga/build/parity-new/          the unmodified `make all` run (fails at bd)
fpga/build/parity-wa/           the workaround run (fails at synth)
fpga/build/_parity/new_flow.log wa_flow.log     full console output
fpga/build/_parity/bd_tcl_shim.tcl              workaround 1
fpga/build/_parity/hooks/pre_synth.tcl          workaround 4
fpga/build/_parity/dcp_probe.tcl                the comparison probe
fpga/build/_parity/probe/old_*                  the OLD baseline it measured
fpga/build/_parity/stray_repo_root_bd_gen/      D6
```

*Copyright (C) 2026, SoC Labs (www.soclabs.org)*

---

# FOLLOW-UP, 2026-09-08 evening — the toolkit now builds this design

**Run tag `bd-fix`.** Same host, same Vivado 2024.1, same part, same target.
Everything in this section was measured on that run; where a number is quoted
from the shipping build it is the same `build/_parity/probe/old_*` baseline
section 3 used.

## Verdict

**The new flow now produces a routed design that is IDENTICAL to the shipping
one by every measure this test can take, and a bitstream.** `make all` still
stops at `impl`, and it stops on a defect in the design's own timing XDC that
the shipping build also has and does not gate on.

## What the three blocking defects turned out to need

| # | Defect | Fix | File |
|---|---|---|---|
| 1 | `generate_target` exists nowhere | call it in stage 3, inside the project that owns the BD, and assert on the generated `synth/<bd>.v` | `flow/vivado/3_bd.tcl` |
| 2 | handoff is a bare `.bd` | stage 3 writes `work/bd_handoff.tcl` naming the `.bd` **in situ**; stage 4 sources it and refuses if it is absent | `3_bd.tcl` + `4_synth.tcl` |
| 3 | no part before `read_bd` | `create_project -in_memory -part` before the IP catalogue, the sources and the BD | `flow/vivado/4_synth.tcl` |

A fourth, found on the way: `create_bd_cell -type module -reference` needs
**automatic** compile-order mode, which `read_verilog` into a project does not
leave behind. Stage 3 now sets `source_mgmt_mode All` and updates the compile
order before `BD_TCL` runs.

## The comparison section 3 could not make

Both routed checkpoints, same probe (`build/_parity/dcp_probe.tcl`):

| metric | OLD (shipping) | NEW (`bd-fix`) |
|---|---|---|
| primitive cells | 131 005 | **131 005** |
| nets | 352 170 | **352 170** |
| ports / clocks | 34 / 11 | **34 / 11** |
| WNS / TNS | 0.247 / 0.000 | **0.247 / 0.000** |
| WHS / THS | -22.273 / -177.926 | **-22.273 / -177.926** |
| THS failing endpoints | 8 of 116 678 | **8 of 116 678** |
| CLB LUTs / Registers | 59 658 / 54 336 | **59 658 / 54 336** |
| cells by `REF_NAME` | 42 types | **identical, every count** |
| `PACKAGE_PIN` + `IOSTANDARD` per port | 34 ports | **identical, every port** |
| clock definitions (period, waveform, source pin) | 11 | **identical, every clock** |
| memory INIT content | 1 106 cells | **identical, every cell** |

Post-synthesis matched exactly too: LUT 60 756, FF 54 451, DSP 7, IOB 34,
black boxes 0 in both.

**Getting there took three project-manifest corrections, and each one was a
thing the shipping recipe did that this manifest had never written down.** The
first run of the new flow differed by +196 primitives and +0.17 ns WNS; the
causes, in the order they were isolated:

1. **Implementation directives.** The shipping build runs `opt_design`
   (Default), `phys_opt_design -directive AggressiveExplore`, `route_design`
   with no `-tns_cleanup`, and a SECOND `phys_opt_design -directive
   AggressiveExplore` after routing. The toolkit's defaults are Explore /
   Default / `-tns_cleanup` / no post-route pass. Six `IMPL_*` knobs, now
   stated in `design.mk` §12.
2. **`MARK_DEBUG`.** The RTL carries `(* mark_debug *)`; the shipping flow
   clears it on **48 nets** immediately before `opt_design`
   (`strip_mark_debug.tcl`, an `impl_1` TCL.PRE hook), and this manifest had no
   equivalent, so 48 nets stayed un-optimisable. `fpga/hooks/pre_impl.tcl`
   now does it at the seam the toolkit provides, and clears **48**.
3. Directives alone did NOT converge it — measured. `MARK_DEBUG` was the rest.

## The bitstream

`nanosoc_eth_chiplet.bit` + `.bin` + `.xsa` + two `.hwh`. With the two bitstream
properties set to the tool defaults the shipping build used
(`BITSTREAM_COMPRESS=0`, `BITSTREAM_UNUSEDPIN=Pullup`) it is **7 797 819 bytes —
the same size as `tidelink.bit`, to the byte** — and differs in **606 of them**:

* **8 bytes, explicable**: the build date and time in the `.bit` header.
* **598 bytes, NOT explained.** 574 of them are a single set bit (`0x00`→`0x10`
  ×448, `0x00`→`0x20` ×126) at a regular 12-byte pitch, clustered in four
  regions of the payload with two megabyte-sized regions untouched. Ruled out by
  measurement: memory INIT (identical, 1 106 cells), `CFGBVS`/`CONFIG_VOLTAGE`
  (changing them moves 5 bytes, not 598), compression, unused-pin policy, and
  the netlist itself. It is recorded as unexplained rather than attributed.

The **delivered** bitstream keeps the toolkit's declared settings
(compressed, `Pullnone`) and is 6 703 433 bytes. `Pullnone` versus the shipping
build's inherited `Pullup` on unused pins is a **board-visible difference** and
this project has not yet made that choice deliberately.

## Where `make all` stops, and why that is the right answer

```
fpga/build/bd-fix/reports/impl_gate.txt
BUDGETS EXCEEDED
  - critical_warnings 1 > budget 0 (ALLOW_CRITICAL_WARNINGS=0;
    ids not allowlisted: Constraints 18-611, Constraints 18-612)
```

Both ids are one constraint, `kr260_eth_chiplet_tidelink_timing.xdc:241`:

```
set_bus_skew -from [get_ports {pad_rx[*]}] -to [get_cells -hier ...] 2.000
CRITICAL WARNING: [Constraints 18-612] set_bus_skew: list of objects specified
  for option 'from' does not contain any object of type(s) '(pin,cell,clock)'
  supported by the constraint. The constraint will not be applied.
```

Its own comment calls it "THE key build-to-build determinism constraint". It
names **ports**, `set_bus_skew` takes pins/cells/clocks, and **it has never been
applied** — in either flow. The shipping build emits the identical pair
(`build_design.log`, 3 ids / 6 occurrences) and ships anyway. The new flow is
right to stop; the fix is in the XDC and is not this report's to make.

Two toolkit defects were found here and are NOT fixed, because both are outside
the files this work was allowed to touch:

* `MSG_GATE_ALLOWLIST` **cannot grant an exemption at `impl`**. The exemption
  requires the ids read from the log to account for the tool's own count, and at
  that stage they do not: `get_msg_config -count` says 1 while the log carries 3.
  The only knob that clears it is `ALLOW_CRITICAL_WARNINGS=1`, which is a blunt
  demotion and was NOT used.
* `util_row`'s `string is integer -strict` cannot read `Block RAM Tile | 32.5`,
  so **BRAM is `unmeasured` in both the synth and the impl manifests** and
  `ci/assert-stage.sh synth` fails on it. Duplicated in `4_synth.tcl` and
  `5_impl.tcl`; a one-line fix in each, and it needs a run that re-measures it.

`ci/assert-stage.sh` is green on `flist`, `bd` and `bitstream`.

## Workarounds used, named

1. **`BITSTREAM_CFGBVS=GND` / `BITSTREAM_CONFIG_VOLTAGE=1.8`.** The bitstream
   stage refuses without them. Measured on this design's own checkpoint:
   family `zynquplus`, both properties unset, `report_drc -checks CFGBVS-1` →
   **0 violations**; the shipping log never mentions CFGBVS. The values are
   inert here and are set only to satisfy a step with no family guard. That
   guard is the real fix and it is a toolkit change.
2. **`make bitstream` run by hand.** `make all` stops at `impl` for the reason
   above, so the last stage was invoked against the routed checkpoint the same
   run produced. No gate was demoted to do it.

*Copyright (C) 2026, SoC Labs (www.soclabs.org)*

---

# ADDENDUM, 2026-09-09 — the 598 bytes, explained

**Run dir:** `fpga/build/_bitdiff/` (diagnostic only, gitignored). Same host
(srv03335), same Vivado 2024.1 build 5076996 as the shipping build.

## Verdict

**`BITSTREAM.CONFIG.UNUSEDPIN`. The shipping build set no bitstream properties at
all and got Vivado's default, `Pulldown`; the parity comparison forced `Pullup`.
The 598 bytes are the unused-I/O pull configuration and the CRC word that
follows from it. Nothing else differs: the new flow's routed checkpoint, written
at tool defaults, reproduces `tidelink.bit` byte for byte apart from the header
date/time.**

```
$ open_checkpoint fpga/build/bd-fix/outputs/nanosoc_eth_chiplet_routed.dcp
$ write_bitstream -force NEW_DEFAULT.bit          # nothing set, as the shipping build did
$ cmp -l NEW_DEFAULT.bit tidelink.bit | wc -l
8                                                 # 0x69 0x6b 0x6c 0x71 0x72 0x75 0x77 0x78
$ tail -c +128 NEW_DEFAULT.bit | sha256sum        # configuration payload
cc9092fc791fa4d552554e14adf0feaee2cfe9830c96c476a5d364c639103624
$ tail -c +128 tidelink.bit     | sha256sum
cc9092fc791fa4d552554e14adf0feaee2cfe9830c96c476a5d364c639103624
```

Those 8 bytes are the build date and time. **Parity is total — netlist,
placement, routing and configuration bitstream.**

## The proof

From the **shipping** routed checkpoint, one Vivado session, four writes:

| `BITSTREAM.CONFIG.UNUSEDPIN` | bytes differing from shipping payload |
|---|---|
| *(nothing set — as the shipping build)* | **0** |
| `Pulldown` (explicit) | **0** |
| `Pullup` | **598** |
| `Pullnone` | 307 |

Setting `Pulldown` explicitly is byte-identical to setting nothing, which is what
"the tool default on this part is Pulldown" means operationally. `Pullup` — the
value the parity comparison used — reproduces the 598-byte residue exactly.

The residue is a property of the *setting*, not of the design. An independent
legacy build of a **different** design (`kr260-eth-chiplet.tl033`, 2026-08-11)
regenerated from its own checkpoint gives a byte-for-byte identical difference
profile: same 24 frames, same per-frame byte counts, same 598 total.

## Byte accounting — all 606

| bytes | what | where |
|---:|---|---|
| 8 | `.bit` header build date/time | `0x69`–`0x78` |
| 594 | unused-I/O pull configuration | 24 configuration frames (below) |
| 4 | the bitstream CRC register value | `.bit` `0x76f54b`, `0xb960b033` → `0xca19ec8d` |

The CRC is a **consequence**: a `T1 w CRC` packet at `0x76f547` checksums the
FDRI stream, so it must move if any frame byte moves. Outside those three
groups the two command streams are **identical packet for packet** — same
`IDCODE`, `COR0`, `COR1`, `CTL0`, `CTL1`, `MASK`, `TIMER`, `WBSTAR`, same
`CMD` sequence, same single FDRI write.

## Where the frames sit

`.bit` layout: 127-byte header; sync `0xAA995566` at `0xCF`; **one** type-2 FDRI
write of 1 948 908 words = **20 956 frames × 93 words**, data starting at `.bit`
byte 407 (`.bin` byte 280). Frame *f* occupies `.bit` bytes `407 + 372f`.

Configuration rows are **4469 frames**. Frames 0–17 875 are four block-type-0
rows; frames 17 876–20 955 are 3 080 frames of block type 1 (BRAM **content**),
of which only 209 are non-zero and **none differ** — an independent
corroboration of the memory-INIT result above.

FAR fields, verified against a `write_bitstream -logic_location_file` `.ll`
(2 050 anchor frames; each of the 243 distinct (column, minor) anchors
resolves to the same row-relative frame offset in every row it appears in):
block type
`[26:24]`, row `[23:18]`, column `[17:8]`, minor `[7:0]`.

| cluster | block type | rows | frames (row-relative) | FAR | frames | bytes |
|---|---|---|---|---|---|---|
| **A** | 0 | 0,1,2,3 | 1666–1669 | **col 49, minors 0–3** — `0x00003100`–`03`, `0x00043100`–`03`, `0x00083100`–`03`, `0x000C3100`–`03` | 16 | 448 |
| **B** | 0 | 0,1,2,3 | 828–829 | col unresolved (lies in the column block 22–26); minors 0–1 of that column | 8 | 146 |

Absolute frame indices: A = 1666, 6135, 10604, 15073 (+0…3); B = 828, 5297,
9766, 14235 (+0…1). Column 49 is the first column after the CLB column holding
`SLICE_X22` (FAR col 48). Column B's number is not resolvable from the `.ll`
because the design instantiates no logic in FAR columns 22–26, so no anchor
lands there; the row-relative frame offset is the exact address.

**Why the "12-byte pitch, single set bit" shape.** A 93-word frame is
45 words | 3 clock-row words | 45 words = 60 tile rows at 1.5 words each. The
extra bits are one bit per *two* tile rows — hence every third word — running
the full height of the column, 27 of the 31 possible positions plus the clock
row, with a symmetric 4-position exception pattern (words 1, 22, 49, 70). That
is a per-I/O-site field replicated up an I/O column, in all four rows, which is
exactly what an unused-pin pull setting is.

The three settings separate cleanly, and show the field is two bits per site:

* `Pulldown` — the default — encodes as **all-zero**. All 16 cluster-A frames
  are entirely zero in the shipping bitstream.
* `Pullnone` sets **one** bit per site: it moves only the odd minors
  (829; 1667, 1669) — 303 frame bytes.
* `Pullup` sets **both** bits per site: it moves both minors of each pair
  (828 *and* 829; 1666–1669) — 594 frame bytes.
* `Pullnone` additionally touches one frame that `Pullup` leaves alone:
  row-relative offset 3632, **row 3 only** (absolute frame 17039, 6 bytes).

Under `Pullup` each cluster-A frame carries 28 words of `0x00100000`, identical
in all four rows. Cluster B is non-zero under every setting and differs per row
(24/6/17/26 bytes in rows 0–3) — consistent with it being the column that also
carries this design's 34 placed ports, whose own configuration bits share those
frames and are untouched by the pull setting.

## USR_ACCESS — explains none of it, and the provenance defect is confirmed

**There is no `AXSS` (register 13) write anywhere in either bitstream.** Decoded
from the command packet stream directly, not inferred from the log:
`BITSTREAM.CONFIG.USR_ACCESS` is unset in both routed checkpoints, and neither
`.bit` contains a USR_ACCESS register write. USR_ACCESS accounts for **0 of the
598 bytes**.

The defect recorded in §1 stands and is now confirmed at the bitstream level
rather than from `build_design.log`: `tidelink_manifest.json` asserts
`"usr_access": "0xdf2b43ed"` for a bitstream that carries no such register.

## Refuted along the way

Each of these was tested and is **not** the cause:

1. **Post-route `phys_opt_design`.** The legacy flow copies
   `tidelink_design_wrapper_routed.dcp` to `output/`, which is the checkpoint
   from *before* the post-route pass; the bitstream is written after it. That
   asymmetry is real, but not the cause: writing from
   `_postroute_physopt.dcp` gives the identical payload to writing from
   `_routed.dcp`.
2. **In-session state lost by a checkpoint round trip.** Opening `_routed.dcp`,
   running `phys_opt_design -directive AggressiveExplore`, then writing in the
   same session gives the same payload again.
3. **`-bin_file`.** `write_bitstream -force` and `write_bitstream -force
   -bin_file` produce identical `.bit` payloads.
4. **Tool or host drift.** Both builds: srv03335, Vivado 2024.1 SW Build 5076996.
5. **Any other `BITSTREAM.*` property.** All are unset in both checkpoints, and
   the pre-FDRI register stream is identical packet for packet.

Five independent paths — shipping `_routed.dcp`, shipping
`_postroute_physopt.dcp`, in-session re-`phys_opt`, a full in-session
`route_design` + `phys_opt_design` re-run from the pre-route
`_physopt.dcp`, and the new flow's own checkpoint — all produce the same
payload under the same settings. The re-route is the strongest of these: routing
this design again from scratch reproduces the shipped routing bit for bit. There
was never any non-determinism to find.

## Corrections to the section above

1. **"the shipping build's inherited `Pullup`" is wrong.** The shipping build
   inherited **`Pulldown`**. It set no bitstream properties at all — its `.bit`
   header carries no `;COMPRESS=` tag, which Vivado adds whenever the property
   is explicitly set. The parity build's `BITSTREAM_UNUSEDPIN=Pullup` was
   therefore not "the shipping build's settings"; it was the one deviation.
2. **"598 bytes, NOT explained"** — now fully explained, and "unused-pin policy"
   should be removed from the ruled-out list: it was ruled out against the wrong
   baseline (`Pullup` vs `Pullnone`, neither of which is the default).
3. **The delivered bitstream's board-visible difference is real but mis-stated.**
   `Pullnone` differs from the shipping silicon by *Pullnone vs Pulldown* — 303
   frame bytes plus the CRC, 307 in all — not by Pullnone vs Pullup.
   **The shipping KR260 bitstream pulls every unused PL pin DOWN.** To match it,
   `design.mk` should say `BITSTREAM_UNUSEDPIN ?= Pulldown`, or the project
   should make the choice deliberately and write down why.
4. **`BITSTREAM_CFGBVS=GND` / `BITSTREAM_CONFIG_VOLTAGE=1.8` were never applied.**
   `bd-fix-bit6.console:3031,3033` records both `set_property` calls *failing*:
   `WARNING: [Vivado 12-5460] The attribute CFGBVS is not supported in the
   xck26-sfvc784-2LV-c device`. They are inert because they do not exist on this
   part, which is a stronger statement than the one made above, and it makes the
   toolkit's family guard the whole of the fix.
5. **Latent provenance gap (legacy flow, not the toolkit).** `output/` ships the
   pre-post-route-phys_opt checkpoint next to a bitstream written from the
   post-pass design. They agreed on this build; nothing guarantees they will.

## Are the two bitstreams "functionally equivalent"?

The **fabric** configuration is identical — every LUT, flop, BRAM content,
route and I/O standard, bit for bit. The bitstreams are **not** interchangeable:
they terminate unused PL pins differently, which is an electrical property of
the loaded device, visible on the carrier's headers. "Functionally equivalent"
would be doing the work of hiding a deliberate board-level choice that this
project has still not made.

## Evidence

All under `fpga/build/_bitdiff/`, reproducible from the `.tcl` files there:
`rewrite.tcl` (both checkpoints, one session), `prpo.tcl` (post-route physopt
checkpoint), `live.tcl` (in-session phys_opt), `ll.tcl` (`.ll` + `-bin_file`
control), `ctl.tcl` (the tl033 control), `pins.tcl` (the four UNUSEDPIN writes),
`final.tcl` (the headline check).

*Copyright (C) 2026, SoC Labs (www.soclabs.org)*
