# Upstreaming the two block-description YAMLs

Two `nanosoc_gen` block descriptions were authored in this integration repo but
describe modules that live in their own home repos. They should move there so the
boundary model tracks the RTL it describes, instead of drifting in a third repo.

| File (here) | Module | RTL ports | Home repo | Destination |
|---|---|---|---|---|
| `sys_desc/tidelink_top.yaml` | `tidelink_top` | **165** | `tidelink` | `tidelink/sys_desc/tidelink_top.yaml` |
| `sys_desc/tidechart.yaml` | `tidechart_controller` | **28** | `tidechart` | `tidechart/sys_desc/tidechart.yaml` |

Port counts are not taken on faith — both were re-derived mechanically from the RTL
for this plan (count of `input|output|inout` port lines between the module header
`)(` and its closing `);`):

- `tidelink/src/rtl/tidelink_top.sv` → **165** (matches the YAML's own accounting,
  `sys_desc/tidelink_top.yaml:35` "TOTAL RTL PORTS: 165").
- `tidechart/src/rtl/tidechart_controller.sv` (module at `:20`, header closes `:93`)
  → **28** (matches `sys_desc/tidechart.yaml:17` "RTL PORT COUNT = 28").

---

## 1. `tidelink_top.yaml` → `tidelink/sys_desc/tidelink_top.yaml`

### Where it goes
`tidelink` **already has a `sys_desc/` directory** with one block description:
`tidelink/sys_desc/tidelink.yaml` (module `tidelink` — the older, minimal
2-AHB-interface + SRAM block). The new file describes a **different** module,
`tidelink_top` (the full chiplet stack: RX FIFO, FC adapter, XHB500 bridges,
address translator, chiplet controller). There is **no name clash** —
`tidelink.yaml` and `tidelink_top.yaml` coexist as two distinct block models in the
same directory. Drop the file in as-is.

### What the maintainer must verify
1. **Port count vs RTL: 165.** Re-run the count against whatever commit `tidelink`
   ships as canonical. The YAML header (`:11-13`) records it was derived from
   `src/rtl/tidelink_top.sv` at `origin/integ/tidelink-soc`; confirm that branch is
   the one the block model should track, and that the port list has not changed
   since (the header's per-group expansion at `:38-55` documents exactly how 165
   decomposes — 1 AHB target `ahb_sub` expands to 12 = canonical 13 minus
   `hmastlock`, etc.). If a port was added/removed, the total and the offending
   group both need updating or `make chip-boundary`/elaboration will mismatch.
2. **`gen: False` is correct** — the RTL is authoritative; the generator only learns
   the boundary. Nothing should regenerate `tidelink_top.sv` from this YAML.
3. **SRAMs are modelled as internal** (FIFO buffers, TSMC65 `rf_16k`/FPGA BRAM
   selected by flist, not by the YAML). Confirm that matches `tidelink`'s own view.

### Path / variable adjustments
- **No edit inside the YAML.** Its only path reference is the header comment
  "Derived from RTL: `src/rtl/tidelink_top.sv`", already relative to the tidelink
  repo root — correct once the file lives there.
- **This repo's search path already reaches it.** `set_env.sh:48` puts
  `${TIDELINK_HOME}/sys_desc` on `CHIPLET_SYS_DESC_LIB_DIRS`. So after the move the
  chiplet resolves `tidelink_top` from tidelink with no env change **— provided the
  local copy is removed.** `set_env.sh:43` lists this repo's own
  `${NANOSOC_ETH_CHIPLET_HOME}/sys_desc` **earlier** in the search order, so a
  lingering `sys_desc/tidelink_top.yaml` here would shadow the upstreamed one.
  **Action: `git rm sys_desc/tidelink_top.yaml` in this repo once tidelink carries it.**

---

## 2. `tidechart.yaml` → `tidechart/sys_desc/tidechart.yaml`

### Where it goes
`tidechart` has **no `sys_desc/` directory yet** — it must be created:
`tidechart/sys_desc/tidechart.yaml`. Keep the filename `tidechart.yaml` (module
inside is `tidechart_controller`, `sys_desc/tidechart.yaml:79`).

### What the maintainer must verify
1. **Port count vs RTL: 28.** Re-derive against the canonical `tidechart` commit.
   The YAML header (`:11-12`) records it was derived from
   `src/rtl/tidechart_controller.sv` on worktree branch
   `add-subtree-and-irqc-axis`; confirm that is the boundary to model, and that the
   28-port header hasn't changed. The YAML declares exactly one interface entry per
   RTL port with matching direction/width.
2. **Adapter-set dependency.** The YAML deliberately models the APB slave and the
   `tc_axis_rx_*` / `tc_axis_tx_*` AXI-Stream pair as **raw `wire` ports**, because
   the `nanosoc_gen` adapter set it was written against (`ahb, dbg_ahb, axis,
   axis_byte, gpio, swd`) has no `apb` adapter and none whose shape matches
   TideChart's stream ports (`sys_desc/tidechart.yaml:28-46`). A maintainer must
   check this modelling choice still holds against the `nanosoc_gen` version
   `tidechart` will be consumed with — if an `apb`/matching-`axis` adapter is later
   added, these should be reconsidered so the boundary uses the protocol form.
3. **Peer, not parent.** The header notes TideChart is a *peer* to TideLink —
   neither instantiates the other; the integrator wires them via `tc_axis_*`. The
   block model is of `tidechart_controller`'s boundary only. Confirm no accidental
   assumption of a containing hierarchy.

### Path / variable adjustments
- **No edit inside the YAML** (its RTL path reference is already repo-relative).
- **This repo's search path does NOT yet reach `${TIDECHART_HOME}/sys_desc`.**
  `set_env.sh:42-48` lists five `sys_desc` dirs including `${TIDELINK_HOME}/sys_desc`
  but **not** `${TIDECHART_HOME}/sys_desc`. So upstreaming TideChart's block model
  needs a **two-part change here**, done together to avoid a window where the model
  resolves nowhere:
  1. Add `${TIDECHART_HOME}/sys_desc` to `CHIPLET_SYS_DESC_LIB_DIRS` in `set_env.sh`.
  2. `git rm sys_desc/tidechart.yaml` from this repo.
  (`TIDECHART_HOME` is already exported at `set_env.sh:32`, so no new variable.)

---

## Suggested order of operations
1. In each home repo: add the file, verify the port count against that repo's RTL,
   run whatever `sys_desc`/lint check the home repo has (or a trial
   `make chip-boundary`/elaboration in this repo pointing at the upstreamed copy).
2. Bump the submodule pins here to the commits that carry the files.
3. In this repo, in one commit: add `${TIDECHART_HOME}/sys_desc` to `set_env.sh`
   and `git rm` **both** local copies. Re-run `make elab` / `make chip-boundary` to
   prove the chiplet still resolves both block models from their new homes.
