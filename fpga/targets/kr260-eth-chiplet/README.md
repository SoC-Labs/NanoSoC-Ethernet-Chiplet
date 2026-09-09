# `targets/kr260-eth-chiplet/` — where the collateral is, and why it is not here

**This directory is deliberately almost empty. The collateral it is named after
is real, current, in daily use, and lives one submodule away:**

```
tidelink/fpga/targets/kr260-eth-chiplet/
    kr260_eth_chiplet_tidelink.xdc            7 198 B   -> XDC_PINS
    kr260_eth_chiplet_tidelink_timing.xdc    28 770 B   -> XDC_TIMING
    kr260_eth_chiplet_tidelink_drc.xdc        1 805 B   -> XDC_DRC
    tidelink_design.tcl                      14 752 B   -> BD_TCL
    tidelink_design_wrapper.v                 5 055 B   -> TOP_HDL
    tidelink_phy_clk_div2.v                   3 092 B   -> EXTRA_SRCS
    BUILD_NOTES.md
```

`fpga/design.mk` sets

```make
TARGET_DIR := $(PROJECT_ROOT)/tidelink/fpga/targets/kr260-eth-chiplet
```

and names each file above in its role-specific variable. So **`TARGET_DIR` is
not this directory** — it is that one.

## Why point instead of copy

A copy is a snapshot that drifts silently. A pointer cannot.

That is concrete here rather than tidy-minded: the pins XDC and the 28 KB
timing XDC were both rewritten on **2026-08-21**. A duplicate made under
`fpga/` a fortnight earlier would have gone on constraining the 2026-08-10
design, `make check` would have stayed green on it, and the only place the
difference would have shown up is a bench.

## Why redirect the whole DIRECTORY and not just the six paths

`make check` carries an **orphan-XDC gate**: it walks `TARGET_DIR` and errors
on any `.xdc` that no variable names. That gate exists because the flow this
replaces discovers its constraints by the glob `*_tidelink*.xdc`, so a file
named anything else is invisible — present in the directory, read by nothing,
warned about by nobody — and Vivado drops a constraint that matched nothing
without an error, so the two failure modes are indistinguishable from the log.

Pointed at the real directory, that gate is **real**: the day somebody adds
`kr260_eth_chiplet_tidelink_extrefclk.xdc` and forgets to name it in
`XDC_OPTIONAL`, `make check` goes red. Left at the toolkit's default it would
have walked *this* directory, found nothing, and reported

```
ok   XDC coverage   0 file(s) in TARGET_DIR, all named by a variable
```

— a green verdict that measured nothing. Today it reports **3 file(s), all
named by a variable**, which is the whole set.

## What lives here instead

Nothing but this file. The three scaffolded XDC stubs that `fpga-flow-init`
wrote here were **deleted**: leaving them would have created exactly the second,
drifting copy this arrangement exists to prevent, and their placeholder markers
would have failed `make check` forever.

## When this changes

Moving the collateral physically is a **separate, later decision** — it is
phase 2, together with reversing the direction the two repositories point in
(`tidelink/fpga` currently reaches *up* into this repo for the SoC sources).
When it is taken, it is:

1. `git mv tidelink/fpga/targets/kr260-eth-chiplet/* fpga/targets/kr260-eth-chiplet/`
2. delete the `TARGET_DIR := …` override in `fpga/design.mk` section 4
3. rewrite the six file paths in terms of `$(TARGET_DIR)`
4. `make check` — the orphan gate now covers this directory, and the count must
   still read 3

Until step 1 happens, doing steps 2–4 alone would silently build a different
design.

*Copyright (C) 2026, SoC Labs (www.soclabs.org)*
