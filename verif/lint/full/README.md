# Full-design lint — the whole chiplet, two tools, one scope

`make lint` (`verif/lint/run.sh`) lints **three** modules against blackboxes of
everything else. `docs/verification/LINT_FINDINGS.md` §5 lists what a full-integration pass
would require and explicitly does not attempt it. **This is that pass.**

```sh
verif/lint/full/run.sh                    # both tools
verif/lint/full/run.sh --verilator-only   # ~90 s, no EDA licence
verif/lint/full/run.sh --hal-only         # ~35 min, needs Xcelium/HAL
```

Reports land in `build/lint/full/`.

| | scope | tool | time | licence |
|---|---|---|---|---|
| `make lint` | 3 modules | Verilator | 5 s | none |
| **`verif/lint/full/run.sh`** | **590 files, `nanosoc_eth_chiplet_chip`** | **Verilator + HAL** | 90 s / 35 min | HAL only |

Both tools consume the **same** resolved filelist and the **same** black boxes,
so a finding from one can be looked for in the other. That is the point: two
independent front ends agreeing on a width bug is evidence; one tool shouting is
a hypothesis.

## What gets linted, and what does not

Scope comes from `flist/nanosoc_eth_chiplet_asic.flist` — the **ship**
configuration (TideLink V2 PHY, tech memories), not the FPGA/generic flist the
CDC and elab-strict gates use.

Three ownership tiers (`zones.py`), because *who can fix this* is the only
question that decides whether a finding is actionable:

- **`arm-ip`** — black-boxed. The read-only `/research/AAA/ip_library` trees plus
  the Arm IP that lives inside the submodules (XHB500 under `tidelink/deps/`,
  the rendered DMA-250 under `build_soc/`), plus the eight compiled hard macros
  (`rf_*`, `rom_via`, `eth_rom_via`, `flash_cache_*`). 191 modules stubbed.
- **`third-party`** — compiled and analysed, **reported but never gated**: the
  OpenCores MAC and HA1588, their patched copies, the Wlink/Bluespec bridges,
  `local_overrides/`. A finding here is an upstream escalation.
- **`authored`** — SoC Labs RTL. The gate applies here.

### Tiering must survive symlinks

Tiering is a path-prefix test, and Verilator canonicalises symlinks before it
names a file — as does the resolved filelist. So a vendor tree reached through a
link arrives spelled in a way that carries none of the prefixes above, tiers
`authored`, is never black-boxed, and reddens the gate as if it were our RTL.

This is not hypothetical. `tidelink/deps/xhb500/generated` was made a symlink to
a **second tidelink checkout** (`${TIDELINK_STANDALONE}`, a different
commit) on 2026-08-10. Arm IP modules stubbed silently fell 191 → 165, and 28
XHB500 sources were linted verbatim, contributing 24 findings — every one of the
four regressed `(zone, code)` pairs and the run's only hard `%Error`
(`BLKANDNBLK`). The `191` quoted above is the number from before that link
existed, and the number the fixed `zones.py` restores.

Note that `os.path.realpath` on *both sides* does **not** fix this: the link sits
*below* the prefix directory, so `realpath` of the prefix is unchanged while a
file under it canonicalises into a different tree. `zones.py` instead expands
each prefix to the canonical target of every symlink inside it that escapes it.
In-repo prefixes are scanned at import (local disk, ~10 ms); the `/research` lab
tree is NFS (~6 s warm, ~2 min cold) and is scanned only if some path matches no
prefix at all. `LINT_ZONES_NO_SYMLINK_SCAN=1` disables the scan for a dead mount.

The fix is in the zoning, not the symlink — the link may be load-bearing for
another flow, and the gate must be correct either way.

**Re-validated 2026-08-17 18:44**, after another session replaced the link with a
real directory: 2626 files, byte-identical to what the link pointed at, minus the
self-referential `generated/generated`. The pass reproduces the recorded baseline
exactly — 2 authored findings, both `soc-generated|CMPCONST`, 191 Arm modules
stubbed, zero `%Error`, zero zoning-gap lines, and no path in the resolved
filelist naming the second checkout. Baseline unchanged.

The scan is now inert but **not** redundant. `deps/xhb500/generated/` is in
tidelink's `.gitignore`, yet the symlink is still the *tracked* entry (mode
120000) at both the submodule's HEAD and the commit the parent pins — the real
directory is ignored content sitting over a tracked-deleted link. One
`git checkout` or `git submodule update --force` restores it. Proven still
functional against a sandbox repo carrying the link: `arm-ip` with the scan,
`authored` without. Cost is 0.10 s at import (up from 0.042 s: the walk now
crosses 3041 real entries instead of stopping at one link), against a ~90 s lint.

Its limit is worth stating plainly: it *discovers* links, it does not alias a
path. With no link present, `${TIDELINK_STANDALONE}/deps/xhb500/...`
tiers `authored` again — harmless while nothing names that spelling, wrong the
day a filelist hard-codes the second checkout without a link in between.

### Why black boxes and not `lint_off -file`

Verilator 4.028 applies a config file's `-file` filter at **parse time only**.
The V3-stage checks — `UNOPTFLAT`, `COMBDLY`, `BLKANDNBLK` — are emitted after
that filter and go straight through it. Measured: 10 findings from the Arm IP
trees survived a `lint_off -file` over those exact paths, including a
`BLKANDNBLK` **error** inside XHB500 that set the exit status. The only way to
keep vendor IP out of a lint report is to keep it out of the front end.

`gen_bbox_any.py` builds the stubs read-only from the real sources: full header
(`#(...)`, `import pkg::*;`, port list) plus, for a Verilog-1995 header, the
direction and parameter declarations. Body dropped. SystemVerilog **packages**
have no module and stay compiled — they carry the types the stubs reference.

## The three buckets

A finding is one of:

- **FLOW** — an artifact of running this tool over this filelist, not a
  statement about the design. Suppressed at the tool, counted in the report so
  the suppression stays visible. Verilator: `UNPACKED` (4.028 cannot model
  unpacked structs), `ASSIGNDLY`/`STMTDLY`/`INITIALDLY` (a `#delay` that
  synthesis also ignores), `REALCVT`. HAL: the `-check ALL_RTL` naming/comment
  ruleset.
- **WAIVED** — a real finding the owning repo has already triaged. Every entry
  in `verilator_lint.py:WAIVED_CODES` cites the unit-level waiver it inherits
  (`nanosoc-multicore-system/lint/hal.tcl`,
  `tidelink/lint/verilator/Makefile`).
- **DESIGN** — everything else. This is the report.

HAL adds a fourth, **CDC** — reset/clock-domain structure (`RSTDMN` alone is
8250 findings). Real, but `make cdc` owns it, and HAL infers the clock model
with no SDC input, so those counts are not a lint verdict.

## Unit-level waivers

`hal_rules.tcl` is the union of every `lint/hal.tcl` in the integration (82
rules): the shared SoC ruleset (68) plus TideLink (+6) and the sub-IP flows
(+8). Each rule keeps the justification its owning repo recorded.

> **Do not merge a unit-level ruleset blindly.** The SoC's shared `hal.tcl`
> waives `MLTDRV` and `CLKDMN` under its "generated-top" and "third-party IP"
> headings. Those are precisely the rules `make elab-strict` and `make cdc`
> exist to catch. Merging the set as-is silences both gates: measured, `MLTDRV`
> and `CLKDMN` both drop to **0** findings across the whole chiplet. A waiver
> that is correct for one block is not automatically correct for the
> integration. `hal_report.py:NEVER_WAIVE` is the list that must survive any
> merge.

## Files

| file | what |
|---|---|
| `run.sh` | entry point; runs one or both tools |
| `verilator_lint.py` | resolve → dedup → black-box → verilator → classify |
| `hal_lint.sh` | HAL over the filelist `verilator_lint.py` emitted |
| `hal_report.py` | HAL log → the same FLOW/CDC/DESIGN report |
| `flist_resolve.py` | recursive `-f`, `${VAR}` expansion, duplicate-module detection |
| `zones.py` | the three ownership tiers |
| `gen_bbox_any.py` | header-only blackbox for any module (ANSI or Verilog-1995) |
| `gen_macro_bbox.py` | blackbox for a compiled hard macro, with port-coverage assertion |
| `hal_rules.tcl` | merged unit-level HAL waivers |
