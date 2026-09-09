# `fpga/` — the eth chiplet on a KR260, under the nanoSoC FPGA Toolkit

This directory is the **project side** of the FPGA toolkit adoption. It
describes one thing: the **`kr260-eth-chiplet`** target — the whole nanoSoC
multicore SoC plus the ethernet MAC, the internal TideLink die-to-die link and
TideChart, built for one AMD Kria KR260.

It is a **manifest, not a flow**. There is no build logic here at all. The
engine lives in the toolkit (`nanoSoC-FPGA-Toolkit`), the facts about the
device live there too as a *part pack*, and what lives here is everything the
toolkit has no business knowing: which board, which pins, which clock, which
flist, which knobs are ours.

```
fpga/
  Makefile                     three lines, and they should stay three lines
  design.mk                    THE MANIFEST. Everything about this design
  board/kr260-eth-chiplet/
      board.tcl                THE BOARD PACK. PCB facts, nothing else
  targets/kr260-eth-chiplet/
      README.md                where the target collateral actually is, and why
  targets/README.md            (toolkit-scaffolded) the three-XDC split
  hooks/
      pre_synth.tcl            configured: DEVICE_CLASS + ASIC_TSMC65 assertions
      README.md                (toolkit-scaffolded) the seam rules
  overrides/                   empty, and correctly so
  SCAFFOLD_RECEIPT.md          what `fpga-flow-init` installed, unedited
```

Everything above was produced by
`fpga-flow-init --block nanosoc_eth_chiplet --board kr260-eth-chiplet --part
xck26-sfvc784-2LV-c` and then filled in.

## Try it

None of these launches a tool or takes a licence.

```
cd fpga
make help          the flow, in the order you run it
make check         is the contract complete?          -> exit 0
make env           engine / this run / project contract
make doctor        can this host run it?
make part-probe    the toolkit's xck26 pack
make board-probe   this project's KR260 pack
```

`make board-probe` is **red on this host and that is the correct answer** — see
"Known red" below.

---

## How this relates to `tidelink/fpga`

`tidelink/fpga` is the flow that **actually builds the KR260 bitstreams today**
and it is untouched. It is a 54 000-line Makefile plus a 38 000-line
`build_design.tcl`, it lives inside the `tidelink` submodule, and it reaches
**up** into this repository (`$(realpath $(TIDELINK_HOME)/..)`) for the SoC
sources. Nothing here changes any of that.

**This directory does not copy a single byte of that flow's collateral.** The
three XDCs, the block-design Tcl, the board-level top and the `/2` PHY clock
divider are all still at
`tidelink/fpga/targets/kr260-eth-chiplet/`, and `design.mk` points at every one
of them by variable:

| contract variable | resolves to |
|---|---|
| `TARGET_DIR` | `tidelink/fpga/targets/kr260-eth-chiplet` |
| `XDC_PINS` | `…/kr260_eth_chiplet_tidelink.xdc` |
| `XDC_TIMING` | `…/kr260_eth_chiplet_tidelink_timing.xdc` |
| `XDC_DRC` | `…/kr260_eth_chiplet_tidelink_drc.xdc` |
| `BD_TCL` | `…/tidelink_design.tcl` |
| `TOP_HDL` | `…/tidelink_design_wrapper.v` |
| `EXTRA_SRCS` | `…/tidelink_phy_clk_div2.v` |
| `FPGAHUB_TOML` | `tidelink/fpga/fpgahub.toml` |
| `IP_REPOS` | `tidelink/imp/fpga/{eth_chiplet_ip,phc_ip}` |

**A copy is a snapshot that drifts silently. A pointer cannot.** That is not an
abstract preference here: the timing XDC and the pins XDC were both rewritten
on 2026-08-21. A duplicate under `fpga/` made a fortnight earlier would have
gone on constraining the 2026-08-10 design with every gate green, and the only
symptom would have been on a bench.

`TARGET_DIR` is redirected as a **directory**, not just as three file paths,
and that is deliberate: `make check`'s orphan-XDC gate walks `TARGET_DIR` and
errors on any `.xdc` no variable names. Pointed at the real directory the gate
is real — the day somebody adds `…_extrefclk.xdc` and forgets to name it,
`check` goes red. Left at the toolkit default it would have walked an empty
project directory and reported *"0 file(s) in TARGET_DIR, all named by a
variable"*: a green verdict that measured nothing.

Migrating the collateral physically is a **later and separate decision**. When
it is taken it is a `git mv` plus deleting one override line in `design.mk`
section 4.

---

## What is NOT yet migrated

This directory describes the target. It does **not** yet build it. Everything
below is a real hole, listed so it is visible from the manifest rather than
discovered at the end of a long build.

1. **No stage has been run.** Phase 1 launches no EDA tool by design, so
   `flist`, `package-ip`, `bd`, `synth`, `impl` and `bitstream` have never
   executed against this manifest. `make check` proves the *inputs resolve*. It
   proves nothing about the outputs.

2. **The IP packaging scripts are not ported.** `PACKAGE_TCL` is empty.
   `tidelink/fpga/vivado_ip/package_eth_chiplet_ip.tcl` and its filelist are
   written against the legacy Makefile's environment
   (`FPGA_COMPONENT_FILELIST`, `FPGA_COMPONENT_LIB`, `NANOSOC_ETH_CHIPLET_DIR`),
   not against this contract's. `IP_REPOS` therefore points at the *outputs*
   the legacy flow leaves in `tidelink/imp/fpga/`, which means **this manifest
   currently consumes a packaged IP it cannot itself produce.**

3. **Firmware is not tracked as an input.** CPU0's IMEM image reaches the
   design through the `RAM_PRELOAD` in-body define plus the `ETH_IMEM_IMG`
   parameter default, resolved by `$readmemh` relative to the Vivado run
   directory — not through any variable. So `FW_HEX` / `FPGA_IMAGE_HEX` are
   empty and **a rebuilt hex against an unchanged bitstream is not detectable
   from here.**

4. **`kr260-eth-chiplet-flip` (die_b) is not described.** The second die —
   `DEVICE_CLASS 2`, role strap 1 — is a second `TARGET` over the same `BOARD`,
   which is exactly the distinction `TARGET` exists to carry. Adding it is a
   directory and a few lines, and it has not been done.

5. **No gate is ratcheted.** Every `EXPECT_*` is `-1`: *measure and report, do
   not gate*. That is the only defensible state before a first run. The legacy
   flow's `farm_gate_sv_baseline.txt` and WNS history came from a **different
   flow with a different constraint read window**; copying those numbers here
   would produce budgets that pass whatever this flow first emits and
   discriminate nothing. This repository already has a class of exactly that.

6. **No XDC baseline.** `make xdc-lint` needs a committed record of what each
   constraint file matched, and there is none for this flow.
   `tidelink/fpga/farm_gate_xdc_baseline.txt` is **not** it: different format,
   different reader.

7. **`RTL_FLIST_GEN` is empty on purpose.** The two generated lists the master
   flist `-f`-includes are produced by `make -C .. elab`, which also runs a full
   VCS elaboration. Wiring that here would make `make flist` — a stage that
   needs no licence — take a VCS licence and several minutes every time. The
   honest state is: the flist has a generator, the generator is not separable
   from a simulator run today, and until it is, `build/elab/{soc_vcs,
   tidelink_vcs}.f` are inputs whose freshness is the caller's problem. They
   are present as of 2026-08-26.

8. **`post_impl.tcl` was deleted, not configured.** The toolkit scaffolds a
   per-primitive utilisation assertion that refuses until `UTIL_ASSERT_TABLE`
   is declared. No per-primitive count for this design has been measured under
   this flow, and declaring a guessed one is the "budget set to the day's
   number" pattern above. The template's three honest ways out are *declare*,
   *move to a seam you use*, or *delete*; this is the third, recorded here so
   it reads as a decision rather than an omission. Restore it from the toolkit
   templates after the first green `impl`.

9. **The toolkit is a sibling checkout, not a submodule.** `FPGA_FLOW_DIR`
   defaults to `$(FPGA_DIR)/../../nanoSoC-FPGA-Toolkit`, which is true of every
   SoC Labs bench here and of nothing else. Vendoring it is the end state.

## Known red

`make board-probe` exits non-zero on this host, and the message is correct:

> `KRIA_BOARD_FILES` is unset, and **no Vivado install on this machine carries
> `data/boards/board_files` at all** — 2021.1, 2024.1, 2025.2 and 2026.1 were
> all checked on 2026-09-08, and the user `xhub` board_store holds
> `TUL/pynq-z2` and nothing else.

`board_part` is `xilinx.com:kr260_som:part0:1.1`, and the pack schema makes
`board_repo_paths` mandatory the moment `board_part` is set — because without
it Vivado resolves the VLNV against whatever board files happen to be installed
on the machine running the build. So the pack **defers** the key through
`board_env KRIA_BOARD_FILES` rather than guessing a path: the resolution
attempt is recorded whether or not it succeeds, and an unresolved key stays
*unset with a reason* instead of becoming `""` and flowing onward.

Set `KRIA_BOARD_FILES` to a directory containing `kr260_som` and the pack goes
green — verified:

```
$ KRIA_BOARD_FILES=<a dir containing kr260_som/> make board-probe
board pack 'kr260-eth-chiplet': every value it declares resolves on srv03335.
… exit 0
```

The wider point is that **the KR260 bitstreams in `tidelink/imp/` were built
somewhere the Kria board files were present, and nothing in the tree records
where.** This pack is the first thing that writes the dependency down.

---

## Findings from the first real adoption

Raised against the toolkit, not worked around here except where noted.

1. **`make check` fails when `PART` is empty, so the board pack cannot be the
   single source of the device.** `design.mk.in` tells the reader to *"delete
   this line and let `board.tcl` be the single place the device is named"*, and
   `mk/flow.mk` says in as many words that *"PART normally arrives from the
   board pack … at this layer PART is frequently EMPTY, and that is not an
   error"* — but `fpga-flow-check` treats an empty `PART` as a hard failure and
   never loads the pack to ask. Measured: `make check PART=` → `MISS PART`,
   exit 2. So `PART` is stated **twice** here, in `design.mk` and in
   `board.tcl`, with nothing comparing them.

2. **`make check` cannot see an unreadable `-f` include, and reports a green
   count anyway.** With both generated sub-lists pointed at non-existent paths,
   `check` still says `ok RTL_FLIST … 5 source line(s)` and
   `ok absence cross-checked / flist and -f includes only`. Those 5 lines are
   the master flist's own; the ~2 000 SoC and TideLink sources behind the two
   `-f` includes contributed zero and **nothing said so**. It is the shape the
   contract's own rule 2 forbids — a verdict invented from data it could not
   read. An unreadable `-f` target should be `UNVERIFIED`, and the `-f` count
   should be reported next to the entry count.

3. **`fpga-flow-part-probe` decides "is a site variable unset?" by grepping its
   own report text for the literal `<unset:NAME>` marker**, rather than asking
   `pack_env_report`, which records every resolution attempt and knows the
   answer. A pack that writes a good prose error and drops the marker is told
   *"NO SITE VARIABLE IS UNSET, so this is not a mount problem"* — the opposite
   of the truth, and it sends the reader away from the one thing that would fix
   it. **Worked around here**: `board.tcl` interpolates `$root` into its error
   string so the marker survives, with a comment saying why.

4. **`cfgbvs` and `config_voltage` are still PART keys in the code.**
   `CONTRACT.md` §8 says they are **board** keys — *"corrected 2026-09-08"* —
   and lists them among the board pack's optional keys. `part/pack_api.tcl`
   still declares them at part scope (lines 388, 392) and the board schema has
   no such keys. So the correction landed in the prose and not in the schema:
   setting either in a board pack is a fatal unknown-key error, and setting
   them in a part pack is exactly what the contract forbids. Since an unknown
   key is fatal, **nothing can state them at all**, which is the situation §8
   claims to have fixed.

5. **`FPGAHUB_TOML`'s scaffolded default asserts where the contract says it
   must discover.** §3.3's corollary requires `?= $(wildcard …)`;
   `templates/design.mk.in` writes the bare path. The consequence is exactly
   the one §3.3 describes: a fresh scaffold with no deploy configured reports
   `MISS FPGAHUB_TOML` and cannot pass `make check` until it creates an empty
   file it never asked for. Reproduced on the scaffold before it was filled in.

6. **`make board-probe` prints 8 of the 15 board schema keys.**
   `board.tcl.in` and `CONTRACT.md` §11.6 both describe it as printing *"every
   key it resolved"*. `pack_summary` prints a fixed headline list, so
   `deploy_style`, `connectors`, `oscillator_hz`, `jtag_serial`,
   `io_voltage_by_bank`, `board_rev` and a **successfully** resolved deferred
   key are all invisible — including two this pack sets. They are readable via
   `fpga-flow-part-get`, so this is a reporting gap, not a data loss.

7. **`fpga-flow-part-get`'s `<key> <value>` output cannot survive a multi-line
   value.** A `list`-typed key legitimately wants to be long, and one embedded
   newline desynchronises every line after it for a caller parsing with `read`.
   **Worked around here**: `connectors` is one line, with a comment saying why.

8. **There is no contract variable for a place/route directive.**
   `TIDELINK_PLACE_DIRECTIVE` is declared here as a project knob, and it is the
   one in that block that arguably should not be: `STEPS.PLACE_DESIGN.ARGS.
   DIRECTIVE` is a generic Vivado implementation strategy that every project on
   this tool wants. §3.3 has `FLOW_MODE` and `NUM_JOBS` and nothing for
   implementation strategy, so today the only contract-sanctioned way to set
   one is a **wholesale step override** — a large hammer for one property, and
   one that `make check` then warns about forever. Suggest
   `SYNTH_DIRECTIVE` / `PLACE_DIRECTIVE` / `ROUTE_DIRECTIVE`, defaulting empty.

9. **Two of the four acceptance `RTL_PARAMS` are not top-level parameters.**
   `NUM_PHY_LANES` and `DEVICE_CLASS` are parameters of
   `nanosoc_eth_chiplet_vivado_wrapper` and survive packaging as `CONFIG.*`.
   `CLKGATE_PRESENT` is a parameter of `slcorem0` deep inside the SoC (default
   `0`) and `TXGEN_PRESENT` is a parameter of `tidelink_top` (default `1'b1`).
   Listing those two would emit a generic override for a parameter the top
   module does not declare — which Vivado accepts silently and applies to
   nothing. They are recorded as observed defaults in `design.mk` §5 and
   deliberately kept out of `RTL_PARAMS`.

10. **Acceptance item 5 pins a host state, not a behaviour.** `CONTRACT.md`
    §11.5 requires `make doctor` to report *"that Vivado 2025.2 and 2026.1 are
    advertised by modulefiles and absent from the filesystem"*. On this host
    both are now **present**, under `/research/CAD/Xilinx/Vivado/`, and
    `doctor` correctly says so. The behaviour is right and the acceptance
    sentence has expired.

11. **`make check`'s exit code moves between 1 and 2 for the same kind of
    failure.** The unfilled scaffold exits **1**; the same run with `PART`
    empty exits **2**. §10 assigns 1 to *"we looked and found something"* and 2
    to *"we could not look"*, and a missing required input is arguably either —
    but a caller is entitled to a rule, and today the rule is not stated.

---

*Copyright (C) 2026, SoC Labs (www.soclabs.org)*
