# Portability: what a second SoC would have to write

An audit of the Genus + Innovus flow against one question: **if another SoC Labs design
wanted to use this flow tomorrow, what would it have to supply, and what would it have to
fork?**

The conclusion is not "rewrite it". The flow works, it produces a GDSII, and its scripts
carry an unusually good record of *why* each decision was made. The problem is that the
reusable parts and the design-specific parts are interleaved line by line, and the contract
between the shared toolkit and the project is entirely implicit.

Findings marked **[verified]** were confirmed directly against the repository, the live
remote, or the LEF — not inferred from reading.

---

## 1. Where it stands

| Measure | Finding |
|---|---|
| `config.tcl` reusable flow logic | **~11 %** of 259 lines. The rest is ~16 PDK settings, ~11 site settings, ~42 design settings, interleaved |
| Adding one IP macro | **14 edits across 4 files** — the library table is written out six times (3 lists in `config.tcl`, 3 per-corner copies in the `.mmmc`) |
| Procs in the entire physical script set | **One** (`place_macro`, `floorplan.tcl:140-186`). Everything else is unrolled commands with literals in the argument list |
| Design data in `place_bondpads.tcl` | **69 %** · `floorplan.tcl` 58 % · `power_plan.tcl` 39 % literals |
| Toolkit↔project contract | **100 % implicit.** 10 required variables for synthesis, 8/3/5 for the P&R stages, plus undeclared MMMC view names that fail hours in |
| Environment preflight | **None.** Every required env var is unguarded |

The port has, in effect, already happened once by copy-paste: the ancestor of
`power_plan.tcl` is in this repo at
`nanosoc_arch_tech/asic/ASIC/TSMC65nm/28pin/Cadence/scripts/` — same author header, same
command sequence, different literals. Four sibling copies exist. That is the current
mechanism for reuse, and it is why the ancestor runs `add_metal_fill` and this flow does
not.

---

## 2. The failure mode that makes all of this dangerous

Both tools **exit 0 after printing an error and doing nothing**. The repository documents
this three times and defends against it with `test -s` artefact assertions on every stage.

That defence is sound but late — it fires after ten minutes of RTL reading or five hours of
P&R. And it means every portability defect in this flow is a *silent* defect: a missing
environment variable, a dropped `+define+`, a library list that lost an entry all present
as a completed run with a wrong result rather than as an error.

**[verified] Both tools accept `-abort_on_error` and `-batch`, and the flow uses neither.**
The Genus manual names this exact failure mode:

> Use the `genus -abort_on_error -f <your script>` command to specify that Genus
> automatically quit if a script error is detected when reading in HDL files instead of
> holding at the `genus:root:>` prompt.

This is the highest-leverage single change available, because it converts a whole class of
silent portability failures into loud ones.

!!! warning "But do not enable it blind"
    `-abort_on_error` exits on *any* `Error (XXX)` message, and this design deliberately
    tolerates several — the `check_cpf` wrapper at `config.tcl:51-67` exists specifically
    to swallow 91 pre-existing low-power rule errors so synthesis can proceed. Enabling
    abort-on-error could undo exactly the tolerance the flow depends on. Introduce it one
    stage at a time and keep the artefact assertions.

---

## 3. Three seams, in priority order

### 3.1 The shared submodule is diverged, and both directions are bad

**[verified]** `ASIC/asic-flows` carries four uncommitted stage-script edits — 6 insertions
— replacing `set_multi_cpu_usage -local_cpu 8` with a call to `soclabs_setup_multi_cpu`.
That proc is defined **project-side**, at `config.tcl:241-259`.

This inverts the dependency: the shared toolkit now requires a symbol only this project
provides.

- **Push it as-is** → every other design dies at stage 1 with `invalid command name`, and
  because both tools exit 0, they see silent no-op stages rather than an error.
- **Leave it unpushed** → a fresh recursive clone gets `b19e784`'s `-local_cpu 8` plus a
  committed `config.tcl` defining a proc nobody calls. Correct results at 8 cores instead
  of 14 — roughly 40 % throughput lost on a multi-hour P&R, with no warning.

**The working GDSII currently depends on state that exists in no commit.**

**[verified]** against the live remote: the pinned commit `b19e784` is `refs/heads/lpddr4-pll`
and also `origin/HEAD`; `main` is a different commit. `.gitmodules` records no `branch =`
key, so nothing states that the required commit lives only on a feature branch named for an
unrelated design. Clones resolve today, but nothing protects that.

**Fix:** upstream the proc body into `Cadence/procs.tcl` **and** the four call sites in one
atomic commit; keep the numeric defaults (14 cores — a fact about `srv03335`) local. Record
`branch =` in `.gitmodules`. Add a preflight that fails if
`git -C ASIC/asic-flows diff --quiet` does not hold — that check alone would have caught
this.

### 3.2 The contract is implicit

No stage script declares what it needs. A design that forgets one variable discovers it
hours in, or not at all. The concrete gaps:

- Every required env var is unguarded: `TSMC_65_HOME`, `NANOSOC_ETH_CHIPLET_HOME`,
  `ASIC_FLIST`, `SOCLABS_ASIC_FLOW_DIR`, and `CLK_PERIOD` buried in `constraints.sdc:19`.
- MMMC view names are referenced by literal string in `4_pnr_route.tcl:48`.
- `4_pnr_route.tcl:61` hardcodes a TSMC GDS layer-map path, which blocks any other PDK.
- **[verified]** `1_synthesis.tcl:51` sources `../scripts/dft_setup.tcl` under
  `if {$DFT == 1}`, and that file exists nowhere in the tree. `DFT 1` cannot work.
- Ten hook points are bare `source` calls; exactly one is guarded. One
  (`source ../scripts/filler.tcl`) was dropped upstream, and `conformal_signoff.tcl` is
  **0 bytes** — which is why `scripts/lec/` had to be written project-side.

**Fix:** a `require_env` preflight that lists every missing name at once and calls `exit 1`
— not `error`, which reproduces the exit-0 trap — plus a written manifest of required
symbols per stage.

### 3.3 Parameters are interleaved with algorithm

The scripts are readable, well-commented and almost entirely unrolled. `power_plan.tcl`
contains one 19-line `set_db` block written **twice, byte-identical**. `floorplan.tcl`
places 21 macros by absolute coordinate with no recorded rationale beyond 17 `## MOVED`
deltas.

**Fix:** the split the repo already uses in `constraints.sdc:14-31`, where clock and
uncertainty values are hoisted into named variables with the rationale attached to the
*variable* rather than the call site. Apply it to the physical scripts as
`pdk_params.tcl` (technology data), `design_params.tcl` (design data) and `fp_procs.tcl`
(reusable procs, no literals).

---

## 4. Ranked actions

Effort: **S** hours · **M** a day · **L** multi-day. Risk is to the *currently working
tapeout flow*.

| # | Action | Effort | Payoff | Risk |
|---|---|---|---|---|
| 1 | Record `branch =` for `ASIC/asic-flows` in `.gitmodules`; document the pin | S | High | **None** — metadata only |
| 2 | Fix `PIN_MAP.md` and the false "auto-generated" header on the `.io` file | S | High | **None** — docs only |
| 3 | Preflight that fails if the shared submodule is dirty | S | High | None — additive check |
| 4 | `require_env` preflight with `exit 1` | S | High | None — additive, fails earlier than today |
| 5 | Upstream `soclabs_setup_multi_cpu` (proc **and** call sites, one commit) | S | High | Low — but coordinate with the toolkit owner |
| 6 | Fix the `+define+` gap in `read_flist.tcl` | S | **High** | **Medium — see §5** |
| 7 | Fix `config.tcl:209` to derive the DRC deck from `$TSMC_65_HOME` | S | Medium | None — same path today |
| 8 | Factor `have_cmd`/`if_genus`/`if_innovus` into `procs.tcl` | S | Medium | None |
| 9 | Single-source `BLOCK` (currently written in 6 places) | S | Medium | Low |
| 10 | Delete or implement the dead `DFT` switch | S | Medium | None — it cannot work today |
| 11 | Derive the 82 bond-pad names from the `.io` file + assert the count | M | High | Low — **[verified]** exact parity mapping |
| 12 | Declare macro/IP libraries once as a table; generate the six lists | M | **High** | **Medium — gate on a byte-equality diff against today's lists; LEF read order matters** |
| 13 | Trial `-abort_on_error -batch`, one stage at a time | M | **High** | **Medium — see §2** |
| 14 | Split `pdk_params` / `design_params` / `fp_procs` | L | High | Medium — do after 11 and 12 |
| 15 | Full `designs/<block>/` relocation | L | Low *until a second design exists* | High — touches relative paths inside the shared submodule |

**Do 1-5 first.** They are hours of work, cannot affect the flow, and two of them
(1 and 3) close a live hazard.

---

## 5. What would destabilise the working flow

Recorded so nobody "cleans these up" without knowing what they cost:

- **`CORE_TO_IO = 70`.** Raised from 50 to clear the inner staggered bond pads. Shrank the
  core from 1230×1630 to 1190×1590 and required re-placing 17 of 21 macros.
- **The position of `source ../scripts/filler.tcl`** in `place_bondpads.tcl:29`. It must run
  *before* the pad loops so `check_drc` markers scope to the core only. Move it below and
  the filler repair is handed a marker set dominated by pad-ring geometry it cannot touch —
  376 of 379 shorts in the 2026-08-05 baseline were that class.
- **The OCV line's position.** Moving it once cost 96,545 fictional hold paths.
- **M9's `-spacing 3.05` must not be unified with M8's `1.2`.** It encodes M9's flat `SPACING`
  rule *and* its `MINENCLOSEDAREA` rule, which M8's width-banded table does not impose.
- **IO filler cell order must stay largest-first.** `PFILLER1_G` exists solely because the
  left side's 42 µm gap decomposes as 20+20+1+1.
- **The local IO-driver LEF override** (`USE POWER ;` / `USE GROUND ;` on three pins).
  Without it `connect_global_net -type pg_pin` cannot match, and NanoRoute threads
  VDDIO/VSSIO as ordinary signal nets — 76 DRC violations.
- **`-abort_on_error` vs the `check_cpf` wrapper**, as in §2.
- **The macro/IP library list order.** LEF read order is significant; any table-driven
  regeneration must be proved byte-identical before it is trusted.

---

## 6. What a new design would supply, under the proposed scheme

The target is that a second SoC writes only this:

```
ASIC/designs/<block>/
  design.tcl          # block name, power/ground nets, top-level HDL, DFT flag
  macros.tcl          # the macro table: {pattern x y orient comment}
  inputs/             # constraints.sdc, .upf
  <block>.io          # pad ring order  (bond-pad lists derived from it, not duplicated)
  floorplan.tcl       # die/core geometry + the macro table; procs come from the flow layer
```

…and everything under `ASIC/site/`, `ASIC/pdk/` and `ASIC/flow/` is shared. Today, by
contrast, a second design forks `config.tcl` and all seven physical scripts and edits
literals in place — which is exactly how the four sibling copies of `power_plan.tcl` in
this repository came to exist, and why the improvements made to one never reached the
others.

---

## 7. Source audits

This page synthesises three independent audits — the configuration and orchestration layer,
the physical scripts, and the shared-toolkit seam. Their detailed findings, including the
per-file verdicts and the full evidence tables, are summarised here; the per-script detail
lives in the [script reference](00-index.md).
