# 46 — Why gate1 aborted, and why relaunching it will not help

**Date:** 2026-08-18
**Status:** synthesis is BLOCKED at this HEAD. This is not specific to `gate1`.

If you are here because someone said "just re-run gate1" — read §1 first. It will
abort again, in the same place, for the same reason.

## 1. What happened

`make -C ASIC/eth-chiplet all RUN_TAG=gate1` ran ~2h and died **in synthesis**. No
place, cts or route stage ever started.

    SYN-FAIL: unexpected errors: SDC-202 x2, TIM-303 x2
    SYN-FAIL: strict mode is set - stopping here.
    Abnormal exit.
    make[1]: *** [.../asic-toolkit/mk/flow.mk:457: syn] Error 1
    make:    *** [.../asic-toolkit/mk/flow.mk:595: all] Error 2

The gate is `1_synthesis.tcl:1373` — it collects error codes seen during the stage
and calls `flow_fail` on any that are not allowlisted. **It behaved correctly.** It
refused to hand a netlist to P&R after constraints failed to apply.

## 2. It is NOT a property of gate1

An independent, concurrent run on the same HEAD, with an unmodified `constraints.sdc`,
aborted at the same gate:

    build/resyn-20260818   SYN-FAIL: unexpected errors: SDC-202 x1, TUI-66 x2
    build/gate1            SYN-FAIL: unexpected errors: SDC-202 x2, TIM-303 x2

Different codes, same outcome. **Any `make syn` at this HEAD aborts.** Reproduce:

    grep -h "SYN-FAIL: unexpected errors" ASIC/eth-chiplet/build/*/logs/syn.log

## 3. Root cause — the C2 Option A block in `constraints.sdc`

Its two `set_max_delay` commands fail, and they fail in two stages:

1. **As originally written** (`-datapath_only`): `TUI-66 — A floating point number
   was expected, but '-datapath_only' was seen instead`. Genus does not support that
   option. This is what `resyn` hit.
2. **With `-datapath_only` removed**: `TIM-303 — Invalid path specification. A 'from'
   object is invalid. The object is 'hpin:<WL>/.../a2l_fc_replay/fifo/mem/rdata[100]'`.
   The anchors are hierarchical INSTANCES. `get_cells` resolves them (25 successful,
   0 failed), but `set_max_delay -from` expands an instance to its pins, and an output
   pin is not a valid timing startpoint. This is what `gate1` hit.

Measured both ways: `"set_max_delay" - successful 0 , failed 2`. **The C2 datapath
bound has never been applied to any netlist this project has produced.**

### Why nobody noticed until a run reached the gate

The block is wrapped in `if {[catch { ... }]}` with a documented fallback to plain
`set_max_delay`. **That fallback can never fire.** `read_sdc` processes one SDC command
at a time and reports failures through its own path (`SDC-202`, appended to
`$::dc::sdc_failed_commands`); it does not raise a Tcl error, so the enclosing `catch`
never sees one and the else-arm never runs.

Consequence for anyone auditing: `grep -c 'C2 OPTION A' syn.log` returns 0 because the
WARN `puts` live in that dead else-arm. **A zero there means the fallback did not fire,
NOT that the block was skipped.** Read the `read_sdc` statistics block instead — it
counts every command as successful or failed.

The same inert-`catch` pattern is live at `tidelink_constraints.sdc:617` around
`set_driving_cell`. It is harmless only while its inner commands succeed (currently
`successful 2, failed 0`).

## 4. The syn outputs are NOT safely reusable

`outputs/nanosoc_eth_chiplet_pads_gate.v` (15:55), `_gate.sdf` and `_syn.sdc` (16:01)
all landed **before** the end-of-stage check, so the files exist and look complete.
They are the product of a stage that **failed its own gate**. Running
`make place SYN_RUN_TAG=gate1` would build on a netlist the flow explicitly refused to
bless, timed against constraints that are known not to have applied. Do not do it
without deciding, on the record, that a missing C2 bound is acceptable.

## 5. Three ways out

1. **Fix the `-from` objects.** Name the launching sequential elements rather than the
   hierarchical instances. Correct, and the bound finally does its job. This is a
   timing-intent question and needs the D2D timing owner. See
   `docs/C2_TRANSMIT_GROUP_OPTIONS.md`, whose §"Not validated" flagged exactly the two
   uncertainties this run has now answered.
2. **Delete the two failing commands, deliberately and visibly.** Since the bound has
   never applied, removing them changes no timing result and unblocks synthesis today.
   It converts a hard stop into a documented gap.
3. **Allowlist `SDC-202`/`TIM-303` in strict mode. — DO NOT.** That is the
   gate-that-cannot-fail pattern this project keeps rediscovering: it would hide every
   future constraint that silently fails to apply, which is the exact defect above.

Options 1 and 2 are both defensible. 3 is how this stays invisible for another month.
