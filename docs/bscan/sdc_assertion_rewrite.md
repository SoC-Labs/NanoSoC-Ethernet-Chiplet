# The SDC-time assertion: keep it, and make it say what it proves

**Proposed replacement for §4 of `ASIC/genus-innovus/inputs/bscan_constraints.sdc`.
Not applied — the live file is untouched.**

## Why it must change

The current comment says:

> Constraints are read AFTER elaborate, so by this point
> `u_nanosoc_eth_chiplet_bscan` either resolves or the boundary-scan register is
> NOT IN THE DESIGN. There is no third reading. That is precisely the failure
> removing `set_case_analysis 0 [get_ports SE]` exists to prevent: with SE held
> constant the register is unreachable and unobservable, Genus deletes all 76
> cells as correct constant propagation, and synthesis reports success.

The last sentence claims this check covers the deletion. **It demonstrably does
not**, for two independent reasons:

1. **Timing.** Constraints are read at §8, *before* `syn_generic`, `syn_map` and
   `syn_opt`. Every optimisation-time deletion happens after this line has
   already passed. It cannot fail on a deletion that has not happened yet.
2. **Object.** It resolves a *module instance*. On the 2026-08-20 run Genus
   auto-ungrouped `nanosoc_eth_chiplet_bscan` (`GLO-51` ×47) while all 76 shift
   stages remained. Moved later in the flow, this check would report the
   register absent on a netlist that has it.

There **is** a third reading, and the comment denies it: *ungrouped, and
entirely present.*

The check still earns its place. It proves the RTL was compiled and the
filelist was right — cheaply, and before a licence-hour. It is a **filelist and
elaboration check**, not a survival check, and the comment should say so.

## Proposed replacement

```tcl
# ── 4. THE REGISTER WAS ELABORATED. This is an assertion, and a narrow one. ──
#
# WHAT THIS PROVES: at the moment constraints are read, an instance named
# u_nanosoc_eth_chiplet_bscan exists in the elaborated design. That is a real
# thing to know and it is cheap here: it fails a run in seconds if
# src/rtl/bscan/*.sv fell out of the rendered ASIC filelist, if the padring
# wrapper stopped instantiating the register, or if a rename went half-applied.
#
# WHAT THIS DOES NOT PROVE, AND CANNOT:
#
#   (a) THAT THE REGISTER SURVIVES OPTIMISATION. Constraints are read at
#       section 8 of flow/genus/1_synthesis.tcl. syn_generic (:949), syn_map
#       (:972) and syn_opt (:1007) all run AFTERWARDS. The deletion this file's
#       header describes -- SE held constant, the register unreachable and
#       unobservable, Genus correctly propagating it away -- happens in
#       syn_generic, LONG AFTER this line has already passed. No assertion here
#       can see it. Anyone reading this block as cover for that failure is
#       reading it wrong, and an earlier version of this comment invited them
#       to.
#
#   (b) THAT ANYTHING IS PRESENT LATER UNDER THIS NAME. Genus ungroups by
#       default and SELECTIVELY. Measured on this design, two runs one day
#       apart: 2026-08-19 kept `module nanosoc_eth_chiplet_bscan`; 2026-08-20
#       dissolved it into the parent (GLO-51 x45 vs x47) while every one of the
#       76 shift stages remained. A get_cells on this instance name after
#       mapping would report the register absent on a netlist that has it -- and
#       a check that did exactly that is what produced the "117 of 119 cells
#       deleted" alarm. The truth was four.
#
#       What survives ungrouping is the INSTANCE NAMES of the leaf cells, which
#       carry the dissolved hierarchy as a prefix:
#           kept       u_bsc_00_NRST_I_obs_dr_q_reg
#           ungrouped  u_nanosoc_eth_chiplet_bscan_u_bsc_00_NRST_I_obs_dr_q_reg
#       Anything asking "is it still there" must match on those, with a leading
#       wildcard, and must be statement-aware rather than line-oriented --
#       write_hdl wraps at a column, so a longer name puts the cell type and the
#       instance name on different lines and a per-line regex counts only the
#       short ones.
#
# WHERE THE SURVIVAL QUESTION IS ACTUALLY ANSWERED: flow/genus/1_synthesis.tcl
# section 13b, after syn_opt and before write_hdl, from the claims in
# ASIC/eth-chiplet/survival.tcl. That gate counts leaf instances by name against
# a floor derived from src/rtl/bscan/pad_table.json, and it fails the synthesis
# run. See docs/bscan/DELETION_GUARD_DESIGN.md. THIS check and THAT one are not
# redundant: this one catches a filelist that never compiled the register, which
# no post-optimisation headcount can distinguish from a deletion.
#
# STILL AN ERROR, NOT A WARNING. A warning in a 3000-line Genus log that already
# carries 163 of them is not a response to a missing boundary-scan register.
if {![llength [get_cells -quiet u_nanosoc_eth_chiplet_bscan]]} {
    error "bscan: u_nanosoc_eth_chiplet_bscan does not exist in the elaborated\
           design. Check that src/rtl/bscan/*.sv are in the rendered ASIC\
           filelist and that the padring wrapper still instantiates the\
           register. NOTE this fires at ELABORATION only -- if you are here\
           because cells went missing from a NETLIST, this is not the check\
           that would have caught it; see section 13b and\
           docs/bscan/DELETION_GUARD_DESIGN.md."
}
```

## What changed

| | before | after |
|---|---|---|
| claimed scope | implies it covers optimisation-time deletion | states it covers elaboration only, and why it cannot cover more |
| "no third reading" | asserted | **withdrawn** — ungrouped-and-present is the third reading, and it occurred |
| where the real check lives | not mentioned | §13b, named, with the file to read |
| error text | tells you to check SE case-analysis — misleading, since SE cannot have caused *this* failure | tells you to check the filelist, and redirects a netlist-shaped problem to the right gate |

The `set_case_analysis` guidance is not lost: it moves to the `-advice` string on
the boundary-scan claim in `survival_manifest.eth-chiplet.tcl`, where it fires at
the point the deletion is actually detectable.
