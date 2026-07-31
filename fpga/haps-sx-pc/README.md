# nanoSoC ethernet chiplet on HAPS-SX — ProtoCompiler flow

A second, independent path to a HAPS-SX bitstream for the same
`nanosoc_eth_chiplet`, through **ProtoCompiler's Unified-Compile front end**
(`protocompiler100`) instead of synthesising from RTL in Vivado.

Sibling of [`../haps-sx`](../haps-sx) (the direct-Vivado flow). Both produce a
working VU19P bitstream; this one routes the chiplet through the licensed
ProtoCompiler UC front end first.

> **Status: builds to a bitstream (2026-07-24). Not yet run on hardware.**
>
> | | ProtoCompiler flow | Direct-Vivado (`../haps-sx`) |
> |---|---|---|
> | Bitstream | `build/vivado_out/nanosoc_eth_chiplet_haps_sx_pc.bit` | `.../nanosoc_eth_chiplet_haps_sx.bit` |
> | Setup WNS | **+4.018 ns** | +2.650 ns |
> | Hold WHS | **+0.012 ns** (met) | −0.078 ns |
> | LUTs | 64,162 (1.57 %) | 56,100 (1.37 %) |
> | Registers | 47,155 | 48,610 |
> | BRAM tiles | 20.5 | 32.5 |
> | Bonded IOB | 40 | 40 |
> | DRC | clean + 1 waived `LUTLP-1` | same |
>
> The two are NOT bit-identical and are not meant to be — ProtoCompiler's front
> end elaborates and transforms the design differently before Vivado maps it.
> Notably the PC flow closes hold cleanly (the direct flow has a −78 ps miss)
> and maps fewer BRAM tiles but more LUTs, because ProtoCompiler splits the
> preloaded memories into byte-lane arrays that Vivado infers differently.

---

## 1. Why this flow, and what it is

This site owns `ProtoCompiler` / `ProtoCompiler100` but **not** `ProtoCompilerS`
(ProtoSynthesis) — so the kit's intended single-FPGA flow can't run, and the
HAPS-100 *partition* flow bakes in UMRBus-programmed CFGLUT5 force elements that
are dead on the SX (see the `haps-sx-protocompiler` project note). The route
that works, proven first on `hello_sx`:

```
database load -technology HAPS-100          # checks out protocompiler100
launch uc -utf ... ; run compile -ucdb      # VCS front end + HAPS transforms
database set_state c0 ; export netlist      # CLEAN generic Verilog @ state c0
        -> exported/synvcs/*_compile*.vm
Vivado: read the .vm + board top + XDC -> synth -> P&R -> bitstream
```

The netlist is exported at **state c0 — before `pre_map`/`map`**, which is
where the MH123 "single-FPGA synthesis-only not supported" gate and the CFGLUT5
poison both live. `-technology HAPS-100` is used purely as a vehicle for the
licensed UC front end; **Vivado does the actual mapping and P&R.**

**What goes through ProtoCompiler:** the pure `nanosoc_eth_chiplet` — exactly
the RTL `make elab` compiles under VCS, no Xilinx primitives. The board top
(IBUFDS / MMCM / IOBUF / PHY /8 divider) is read as ordinary RTL in the Vivado
leg, wrapping the exported netlist. Everything downstream — pins, timing, the
`LUTLP-1` waiver, the firmware preload — is **reused from `../haps-sx`** so the
two flows cannot drift.

---

## 2. Build

```sh
module load protocompiler        # protocompiler100 + bundled VCS W-2024.09
module load haps-sx-tools         # vivado + confpro_sx + COBRA_PATH

make -C fpga/haps-sx-pc filelist    # assemble + dedup the UC source list
make -C fpga/haps-sx-pc pcnetlist   # UC compile -> export netlist @ c0
make -C fpga/haps-sx-pc bitstream   # Vivado: wrap the .vm -> .bit
make -C fpga/haps-sx-pc all         # pcnetlist then bitstream
```

`pcnetlist` needs `build/image.hex` staged (the firmware preload — ProtoCompiler
resolves `$readmemh` at *compile* time). `make firmware` (delegated to
`../haps-sx`) produces it.

Long ProtoCompiler and Vivado runs should be launched under `setsid` (see the
`run_*.sh` wrappers) so a killed parent can't reap them.

---

## 3. The six things that had to be fixed to scale from hello_sx

`hello_sx` (84 LUTs, one file) hides everything hard about a real design. Each
of these is a genuine difference for a 579-source SoC with ARM IP; **none
touches a submodule**, and none needs a licence we lack.

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | `Error-[MPD] Module previously declared` (vlogan) | UC's two-step `vlogan` treats a duplicate module as an ERROR; `make elab`'s single-step `vcs` tolerates it as last-wins (`OPD`). Shared CMSDK cells + XHB500 generic cells appear twice, byte-identical. | Run the repo's `flist/dedup_merged_flist.py` over the assembled list — 5 pure-duplicate files dropped. |
| 2 | `Error-[MULTI-MEM-INIT-SAME-HIERSIG]` | `sl_fpga_rom_word.v` zero-fills its BRAM *and* `$readmemh`s it in one initial block. UC's protocompiler-flow elaboration forbids two inits of one signal. | Local override (`vsrc_override/sl_fpga_rom_word.v`) with a single init, prepended so dedup keeps it (first-wins). Zero-fill was sim X-avoidance only; FPGA BRAM inits to 0. |
| 3 | `Error-[ZEBUUC-XMRTRAN-NYIIA]` cross-module ref | `tidelink_sram.sv` zero-inits sub-instance BRAMs via cross-module writes in a `synthesis translate_off` block. UC's VCS elaboration doesn't honour `translate_off` (a synth pragma), compiles it, rejects the XMR. | The RTL author's own `` `ifndef TIDELINK_SRAM_NO_ZERO_INIT`` — add the define. Synth-only code, so no effect on the netlist. |
| 4 | `@E: DE106 Cannot find image.hex` | ProtoCompiler resolves `$readmemh` at *compile* — the preload is real, not deferred. | Stage `build/image.hex` before `pcnetlist`. (Good news: it means the preload carries through — see §4.) |
| 5 | `Synth 8-7136 parameter NUM_PHY_LANES does not exist` | The exported `.vm` module is post-elaboration — its parameters are baked away — so the board top's `#(.NUM_PHY_LANES(...))` override has no target. | `` `ifdef CHIPLET_IS_NETLIST`` in the shared board top selects a no-override instantiation; the Vivado leg defines it. Direct flow (define absent) is unchanged. |
| 6 | `Synth 8-273 non-binary digit to $readmemb` | **A Vivado 2024.1 synthesis bug** (§5). ProtoCompiler writes the preload as `$readmemb` with hex `@`-addresses (`@0..@ef`); Vivado synth mis-parses an `@`-address containing a hex *letter*. | `scripts/fix_ini_readmemb.py` rewrites the `.ini` files to dense, address-less form. |

The pattern behind all six: **UC's ZeBu-derived elaboration, and Vivado's synth
of the result, are both stricter than plain VCS sim** — they trip on
legal-but-loose idioms (duplicate modules, double inits, `translate_off` XMRs,
hex readmem addresses) that the normal sim/Vivado-from-RTL path tolerates.

---

## 4. The preload survives the flow

The open question going in was whether the IMEM firmware would carry through.
It does: ProtoCompiler resolves the original `$readmemh(image.hex)` at compile
and re-emits it, per inferred byte-lane BRAM, as
`$readmemb("ini_dir/<lane>.ini", ...)` with the data written into `ini_dir/`.
Verified the firmware bytes (initial SP, reset vector) land in the right lanes.
So **this flow produces a bootable bitstream, not just a structural one.** The
Vivado leg symlinks the (format-fixed) `ini_dir` into its CWD so the netlist's
relative `$readmemb` paths resolve.

---

## 5. Bug found: Vivado `$readmemb` mis-parses hex-letter `@`-addresses

Isolated with a standalone reproducer (`synth_design` on a 3-line module):

- `.ini` with numeric `@`-addresses (`@0`, `@1`, `@2`) → **reads fine**
- `.ini` with hex-letter `@`-addresses (`@a`, `@ee`) → **`Synth 8-273 error in
  $readmem data: non-binary digit to $readmemb`**, regardless of delimiter
  (tab / space / newline)

The `@`-address in `$readmem` is hex per the LRM (letters a–f legal), and
simulation accepts it, so this is a **Vivado 2024.1 synthesis defect** — it
misreads the letter in the address as a data digit. ProtoCompiler's export uses
hex addresses and so triggers it. `fix_ini_readmemb.py` sidesteps it by emitting
dense, sequential, address-less files (line N = address N), which have no
`@`-addresses to mis-parse; gaps are zero-filled so positional addressing stays
exact.

---

## 6. Layout

```
fpga/haps-sx-pc/
├── Makefile                      filelist / pcnetlist / firmware / xdc / bitstream
├── README.md                     this file
├── scripts/
│   ├── assemble_uc_filelist.py   chiplet flist -> one flat VCS -f for UC
│   ├── pc_common.tcl             UTF / vcs_cmd / compile / export @ c0
│   ├── build_pc.tcl              ProtoCompiler batch driver
│   ├── options.tcl               device / speed grade
│   ├── build_vivado_pc.tcl       Vivado leg: read .vm + board top -> bitstream
│   └── fix_ini_readmemb.py       work around the Vivado $readmemb bug (§5)
└── vsrc_override/
    └── sl_fpga_rom_word.v        single-init override for UC (blocker #2)
```

Reused from `../haps-sx` (not duplicated): the board top, the `.cob` and its
generated XDC, the `LUTLP-1` DRC waiver, and the firmware image.

Reused from the repo root: `flist/nanosoc_eth_chiplet.flist`,
`flist/flatten_soc_flist.py`, `flist/resolve_tidelink_flist.py`,
`flist/dedup_merged_flist.py`.

---

## 7. When to prefer this over the direct flow

The direct-Vivado flow (`../haps-sx`) is simpler — one tool, no ProtoCompiler
licence, faster. Prefer it by default.

This flow earns its keep when you specifically want ProtoCompiler in the loop:
its HAPS front-end transforms (gated-clock conversion, etc.), parity with a
ProtoCompiler-based ASIC/emulation flow, or as a second opinion on elaboration.
It also happened to close hold timing where the direct flow did not — not a
reason to choose it, but a data point.

Identify instrumentation does **not** survive this path (the IICE weaves in at
`pre_map`/`map`, which this flow never reaches). For Identify, use Synplify.
