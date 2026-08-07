# 22 — Synthesis flow notes

Design-specific measurements and tool traps behind `ASIC/genus-innovus/scripts/1b_synthesis_eval.tcl`.

That script is written to be read by students learning the flow, so its comments
explain *what each stage does*. This file holds the *why* — the measurements,
the one-off findings, and the tool behaviours that cost someone a day. When the
script says "see 22-synthesis-flow-notes.md", this is the file.

Everything here was measured on `nanosoc_eth_chiplet_pads` (TSMC 65nm LP,
tcbn65lpwc, ~186k cells, ~58k sequential) unless stated otherwise.

---

## 1. Scan flops are not waste — do not "fix" them

The baseline netlist is **37,834 scan flops out of 57,971 (65%) with DFT off**.
That looks like an obvious bug. It is not.

`use_scan_seqs_for_non_dft` defaults to `true`. Every one of those `SDF*`
instances has a **live net on both `.SI` and `.SE`** — none tied off. Genus is
using the scan mux as the 2:1 load-enable mux for `if (en) q <= d`, which is the
standard and correct implementation.

Forcing it off makes the tool build that mux from discrete logic instead:

| implementation | area | cost |
|---|---|---|
| `SDFCNQD1` | 10.44 µm² | one cell, no extra logic level |
| `DFCNQD1` + `MUX2D0` | 7.92 + 3.24 = 11.16 µm² | plus a mux delay on D |

That is ~0.7 µm² worse on each of the 23,831 `SDFCNQD1` alone (**~17,000 µm²**),
plus a logic level in front of every enabled flop, on a design already at 80.67%
placement density. The third enum value, `degenerated_only`, is a middle ground;
check its exact semantics before reaching for it.

**Verdict:** leave `use_scan_seqs_for_non_dft` alone.

## 2. Recovery/removal arcs are off by default, and it hid a 126 ns violation

Genus does not analyse recovery/removal arcs unless told to. The consequence on
this design: synthesis reported **setup MET at +1 ps**, while Innovus at
pre-place found a **−126.815 ns recovery violation** from `TEST` into a wlink
`CDN` pin. Synthesis could not see the async-reset and test-mode distribution
network at all.

`set_db time_recovery_arcs true` (the `EVAL_RECOVERY` knob) fixes the blindness.
It does not fix the design.

## 3. `timing_report_unconstrained` does the opposite of what it sounds like

**Do not set it.** Despite the name, `true` means report *only* unconstrained
paths. Verified: with it set, `report_timing` on a design with a real critical
path emits `No paths`.

Setting it would silently empty every timing report the flow writes — including
the one `compare_syn.sh` parses, which would then compare two blank files and
report no difference. Ask for unconstrained paths explicitly with
`report_timing -unconstrained` instead; that overrides the attribute anyway.

## 4. `read_physical` requires MMMC (TUI-340)

iSpatial/PLE want the LEF, but `read_physical` cannot run from Genus's
`uninitialized` state. It aborts with:

```
TUI-340: Cannot perform initialization step 'physical_initialized' from
current state 'uninitialized'. The sequence is
  uninitialized - timing_initialized - physical_initialized -
  design_initialized - power_initialized - initialization_complete
```

Only the MMMC commands (`create_library_set` / `create_timing_condition` /
`create_delay_corner` / `create_constraint_mode` / `create_analysis_view` /
`set_analysis_view`) reach `timing_initialized`. The `create_library_domain`
setup the baseline flow uses does **not**.

**Consequence:** `EVAL_ISPATIAL=1` is useless without `EVAL_MMMC=1`, and
`EVAL_PLE` without MMMC silently falls back to process-node estimate tables
rather than real LEF + captable data. Still better than wireload, so the script
allows it — but warns.

## 5. Genus has no `-early` / `-late` (TUI-204)

Those are **Innovus** spellings (as used in `asic-flows/Cadence/procs.tcl`).
`report_timing -early` in Genus raises TUI-204. Use `report_timing -views <view>`.

This matters because getting it wrong produces **no hold report at all** — which
is the entire point of turning `EVAL_MMMC` on.

## 6. The library's own DRV limits, and a factor-of-2 trap

`tcbn65lpwc` constrains every pin already. Measured off the `.lib`:

- `default_max_transition : 0.7657` ns — and exactly **one** distinct
  `max_transition` value in the whole 77 MB file, so it is uniform.
- `max_capacitance` is **per-pin and scales with drive**: BUFFD1 58.7 fF,
  BUFFD2 118.2, BUFFD4 236.4, BUFFD8 472.8, BUFFD16 945.6, BUFFD24 1.418 pF.
  Range across the library: 7.0 fF – 1.418 pF over 348 distinct values.
- **No `max_fanout` at all** — zero occurrences of the attribute,
  `default_fanout_load : 1`. Every baseline reports the fanout check as `N/A / 0`.

The SDC adds almost nothing: `constraints.sdc:133-134` are the only DRV
constraints and both scope to top-level **ports** (`[all_outputs]` /
`[all_inputs]`). No SDC sets `max_transition` anywhere. So internal nets are
held to the **library** limits — not to nothing, which is what an earlier
version of the script's comments wrongly implied.

**The factor-of-2 trap.** The library sets `slew_lower/upper_threshold_pct` to
30/70 with `slew_derate_from_library : 0.50`. So 765.7 ps is on the library's
*table* scale, and the actual 30–70% slew it corresponds to is ~383 ps. Whether
the tool compares `set_max_transition` against the derated or un-derated value
decides whether a 0.40 ns limit tightens anything at all. **Measure it** —
`report_constraint -all_violators` prints actual against required — before
trusting any tightened number.

Better still: use the slew criterion from TSMC's signoff documentation. The
`.lib` number is a characterisation boundary, not a recommendation.

## 7. Area recovery is not always what eats your margin

`opt_area_recovery_setup_target_slack` defaults to `0.0`, so `syn_opt` reclaims
area and leakage until slack reaches exactly zero. It is tempting to blame every
zero-slack handoff on it. Be careful:

| block | interconnect | final slack |
|---|---|---|
| ha1588 | wireload | 1023 ps |
| dma_250_ahb | wireload | 1468 ps |
| both | PLE | 1–21 ps |

Area recovery plainly did **not** drive the wireload runs to zero. On those
blocks the margin went to realistic RC, not reclaim, and ~0 ps is honest
closure rather than a pathology.

The full-chip baseline **is** the case that looks like reclaim: +1 ps on
wireload estimates, where the subblocks had a nanosecond to spare. Worth
reserving margin there. Measure before assuming it applies elsewhere.

## 8. PLE is not a free win

Measured with the same SDC on both sides:

| block | PLE + clock gating |
|---|---|
| ha1588 (15.6k insts) | **−10.6%** area, −3.3% instances |
| dma_250_ahb | **+5.7%** area |

`dma_250_ahb` has far fewer enable-mux flops for clock gating to convert, so the
gating overhead is not repaid. Do not assume the direction; run the A/B.

For contrast, the baseline runs on `wireload`, which is why its netlist has only
**299 buffers in 186k cells** — the tool never saw a wire.

## 9. Clock uncertainty

Uncertainty is **not a clock attribute** in Genus — it lives on the clock *pair*,
so there is nothing to query with `get_db`. The script therefore audits the
*written* SDC, which is also the file the `.mmmc` feeds to Innovus.

Two states this design has actually been in, both caught by that audit:

- a clock with `-setup` but no `-hold`
- a clock with neither — **six of the nine** were bare on the 2026-08-06 run

Generated clocks do **not** inherit their master's uncertainty. A clock with no
uncertainty is timed with zero margin in P&R.

The original bug this was written for — 0.35 ns of setup jitter charged to the
*hold* check on `rmii_ref_clk` — is fixed at source in `inputs/*.sdc`. The audit
stays because the failure mode recurs whenever a clock is added.

## 10. Smaller traps

- **`get_db clocks`, not `get_clocks`.** The latter returns an opaque collection
  handle that `foreach` cannot walk.
- **`syn_opt -spatial`, not `-physical`.** The `-physical` spelling belongs to
  `syn_generic` / `syn_map`.
- **`read_physical -lefs`, not `-lef`.**
- **`report_summary` is unusable here** — it fails with "Failed on summary_table"
  in this flow. Omitted deliberately; a call that warns on every run just
  teaches people to ignore warnings.
- **`report_constraint` needs `-check_type` or `-drv_violation_type`** and
  refuses to run without one, so it is called once per type and concatenated.
- **`lp_insert_clock_gating` must be set before `elaborate`.** Genus infers the
  enables during generic synthesis; setting it later does nothing at all. The
  baseline never sets it and has **0 ICG cells across 58,121 sequential
  elements**. The min/max flops bounds are *design* attributes, so they can only
  be set after elaborate.
- **`CKLHQD20/24` and `CKLNQD20/24` are `dont_use`** in tcbn65lpwc. The PDK marks
  them for a reason; the flow does not second-guess it. That still leaves the
  D1–D16 range, 16 usable ICG cells.
- **Genus exits 0 when its `-f` script fails.** It prints "Encountered problems
  processing file", drops to its prompt, reads EOF and leaves. This is why the
  script ends with an explicit error gate and why the Makefile tests for the
  netlist artefact. See [17-silent-noops.md](17-silent-noops.md).
- **`report_messages` is the only reliable in-tool count of issued errors.**
  `get_db messages` returns the static message catalogue, not what was raised.
- **`CDFG-464`** — a 32-bit signal driving the 1-bit `sel` port of
  `u_sys_hclk_mux` / `u_sys_hresetn_mux` / `u_sys_poresetn_mux`. Surfaced by
  `check_design`, reported to nobody in the baseline log. See
  [18-message-census.md](18-message-census.md).
- **`RCLP-203`** — low-power rule check, allowlisted: 34× UPF naming, 55× PG
  pins, 2× undriven QSPI tag RAM GWEN. See
  [18-message-census.md](18-message-census.md).

## 11. Why the DRV knob defaults to off

`EVAL_DRV_FIX` tightens DRV below the library ceiling. It is **off** because the
constraints it sets are *design-scoped*, so `write_sdc` carries them into
`<block>_syn.sdc` — the file the `.mmmc` feeds to Innovus.

Promote such a run with `EVAL_OUT_DIR=../outputs` and P&R starts signing off
against 0.40 ns instead of the library's 0.7657, multiplying the post-route DRV
count for reasons that have nothing to do with the design.

Treat tightened DRV as a **synthesis target**: strip the design-scoped lines from
the written SDC, or re-assert the signoff value before `write_sdc`.
