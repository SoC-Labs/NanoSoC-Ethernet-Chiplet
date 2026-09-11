# Verified fixes that belong in another repository

Each patch here was **measured**, not merely written, and each applies to a
repository this project consumes rather than owns — so it cannot be committed
where it was made. They live here so a proven fix is not lost between sessions,
which is a documented failure in this lab: a validated change left in a
worktree, in a detached-HEAD submodule, is a change nobody will find.

Apply with `git apply` in the target repository, on a branch, after checking
the diff still applies to that repo's current state.

---

## `tidelink-remove-dead-set_bus_skew.patch`

**Target:** `tidelink`, file
`fpga/targets/kr260-eth-chiplet/kr260_eth_chiplet_tidelink_timing.xdc`
**Made:** 2026-09-09. **One functional line removed**; the rest is the evidence,
written into the file where the constraint used to be.

### What it removes and why

```tcl
set_bus_skew -from [get_ports {pad_rx[*]}] -to [get_cells ...] 2.000
```

`set_bus_skew` takes **pins, cells or clocks**. It does not take ports. So this
constraint **has never applied, in either flow**, despite its own comment
calling it *"THE key build-to-build determinism constraint"*. Both flows emit
`Constraints 18-611` and `18-612` and carry on; the shipping bitstream was built
with it inert.

It is not fixable, and that was established by exhaustion against the shipping
routed checkpoint rather than by reading:

| `-from` tried | Vivado's answer |
|---|---|
| `get_ports` (as shipped) | `18-611` + `18-612`, type rejected |
| `get_pins` on the IBUF output | **ERROR `18-513`**, no valid startpoints |
| `get_cells` on the IBUF | **ERROR `18-513`** |
| `get_clocks` | `18-611` + `18-612`, type rejected |

Vivado's own messages contradict each other — handed ports it lists the legal
types as `(pin,cell,clock)`, handed a clock it lists `(port,pin,cell)`. The real
accepted set is the intersection, and `18-402` adds that it must be a *valid
startpoint*: a clock pin of a sequential cell. A bus launched from a primary
input pad has no on-die launch register, so nothing satisfies both.
`set_bus_skew` is a register-to-register CDC construct and cannot express a
pad-to-capture input bus. **A misconception, not a typo.**

### It would have failed anyway

Measured over all 128 `pad_rx[*]` capture paths on the shipping routed design:

    max datapath  3.797 ns      min datapath  1.405 ns
    bus skew      2.392 ns      asked for     2.000 ns   -> violates by 0.392

The achievable bound is ~2.4 ns, not 2.0.

### Proof the removal is safe

A/B `read_xdc` of the original and edited file against the shipping routed
checkpoint: `18-611`/`18-612` go **2 → 0**, total critical warnings from the
file go **2 → 0**, and `report_exceptions` on the RX group is byte-identical
(the `(3b)` `-datapath_only` exception is untouched).

### Scope beyond this file

A census of both chiplet checkouts found **13 dead `set_bus_skew` lines across
11 targets** — 9 in this port form, and 4 in an `IBUF[*]/O` pin form somebody
applied as a fix and never verified, which is *worse* (hard `ERROR 18-513`
rather than a critical warning). The compute chiplet reached the same conclusion
for its `kr260-pair-*` targets in July and deleted the constraint there with a
documented rationale; that cleanup never reached the `kr260-eth-chiplet*` or
`kr260-compute-chiplet*` targets in either checkout.

### One thing this does NOT fix

The RX data path is fine — that is what the numbers above say. The compute
chiplet's documented root cause for the bring-up lottery is the capture **clock**
tree (eight lane-identical mux chains merging into one high-fanout LUT-driven
net), fixed in RTL by a shared-BUFG hoist, not by any constraint.

---

Copyright (C) 2026, SoC Labs (www.soclabs.org)

---

## `tidelink-pad_tx-clock_fall.patch`

**The KR260 design does not miss hold. The constraint checks an edge nothing
captures on.** Applies cleanly to `tidelink @ 5e8bdb5`.

`set_output_delay` on `pad_tx[*]` omits `-clock_fall`, so it describes a
setup/hold window around the **rising** edge of the forwarded clock. The
receiving die captures on the **falling** edge. On the RX side Vivado infers the
capture edge from the capture flop — which is why `pad_rx[*]` shows no phantom
violation — but on the TX side the capture flop is off-chip and invisible, so
the edge has to be *declared*.

### Evidence that the far die captures on the falling edge

| | |
|---|---|
| routed netlist, `kr260-pair-nptp` | 82 endpoints clocked by **`pad_clk_rx'`** (primed = inverted) |
| routed netlist, `kr260-pair-flip-nptp` | 86 endpoints, same |
| RTL | `WavD2DGpio.v` reset default selects the inverted pad clock |
| the XDC itself, four lines above the constraint | *"MID-CELL (160 ns from either pad transition)"* |

The file already states the physics correctly and then constrains the wrong
edge.

### Measured, two builds differing ONLY in these two lines

Same design sha, same toolkit, same `SYNTH_GATED_CLOCK_CONVERSION=off`:

| | stock ±20 rising | `-clock_fall` ±8 |
|---|---|---|
| WNS | +0.332 | +0.276 |
| failing setup | 0 | 0 |
| WHS | **−22.145** | **+0.010** |
| THS | −176.923 | 0.000 |
| **failing hold** | **8**, all `pad_tx[*]` | **0** |
| `pad_tx` worst hold slack | −22.145 | **+151.592** |
| LUT / FF / BUFGCE | 59,851 / 54,337 / 23 | 59,851 / 54,337 / 23 |

**Identical utilisation.** The design does not change; only what is checked does.

### Where ±20 came from

Not a board measurement. Verbatim from commit `9aee1d39`:

> `set_output_delay pad_tx +/-5 -> +/-20 ns (period-scaled 4x, same
> 12.5%-of-period fraction; far die samples mid-cell so >=60 ns margin)`

It is ±5 multiplied by four because the link rate dropped by four. The comment
now above those lines claims they are absolute board-trace nanoseconds and that
the 12.5% framing was "a coincidence of its rate" — git says otherwise. That
comment is a retcon and this patch replaces it.

### ±8.000 is a BUDGET, not a measurement

No receiver setup/hold requirement is documented anywhere in these repositories;
the Wavious IP that owns the PHY constrains nothing on its pads, and no transmit
eye has ever been measured. ±8 is the same absolute on-die figure this ribbon's
receiving end already applies to its pad→capture path, and ~5% of the 159.93 ns
window the opposite-edge capture grants. **It should be replaced by a real
number when someone scopes the ribbon** — the highest-value measurement is the
duty cycle of `pad_clk_tx` at the connector, because the whole window exists
only by virtue of the opposite-edge capture.

### Why this is a patch and not a commit

`tidelink` is a shared submodule on a detached HEAD, also consumed by the
compute chiplet. Same reasoning as `tidelink-remove-dead-set_bus_skew.patch`.

**`EXPECT_WHS_MIN` in `fpga/design.mk` stays at `-1` until this lands upstream.**
The project builds against the stock XDC, which still reports −22.145. Arming
the gate before the fix lands would fail every build. Once it lands, hold
becomes gateable for the first time.
