# 47 — The island feed works, and it is the most fragile thing in the run

**Status:** the fix is landed (`bfbccf6`) and screened — 8 at-risk islands → 0, functional
stranded 55 → 0, shorts 0, with a control failing in the right direction. This page is not
about whether it works. It is about the two ways it can stop working without anything going
red, and it exists because the next person to move a macro will meet both.

---

## 1. The second feed has 0.4 µm of freedom

```
feed set x= 877.000   VDD 877.000-880.600  VSS 881.800-885.400   feeds 3 islands, window [877.000, 889.600]
feed set x=1049.000   VDD 1049.000-1052.600 VSS 1053.800-1057.400 feeds 5 islands, window [1049.000, 1049.400]
```

The first feed has 12.6 µm of slack. **The second has 0.4 µm.** `u_shared_sram_0` starts at
x = 1052.400 and the VDD stripe's far edge lands at 1052.600 — 0.200 µm clear.

The placement is derived, so it recomputes when macros move. **That is not the same as being
safe.** If a macro move narrows that window to nothing there is no legal placement at all, and
the failure will not present as "no valid x" — see §2.

## 2. The gate that guards it cannot see the way it fails

The first derived form centred each feed in its window rather than placing it at the left end.
At the centre (883.3 / 1049.2) the VDD edge lands **0.400 µm inside** `u_shared_sram_0`, and
because an M5 rung runs out to the far edge of the nearest same-net vertical stripe and
terminates there with a via stack, that produced:

```
7 new M1/M3 shorts   Net VDD & Blockage of Cell ...u_shared_sram_0...
check_drc            65 -> 80
FP-ISLAND verdict    still PASS
```

**`check_fp_pg.tcl` compares VDD against VSS. It does not compare VDD against a macro
blockage.** So the island gate reported the feed working while the feed was shorting into an
SRAM. The only thing that caught it was `check_drc`, which this project has independently
measured as disagreeing *in sign* with Calibre — so it is not a check anyone should be relying
on to catch this either.

**Rule, and it is in `power_plan.tcl` beside the code:** place each feed at the LEFT end of its
window — the end furthest from the macro halo that created the island — never the middle.

## 3. What would have to change for this to be robust

Not asserted as done; this is the list for whoever picks it up.

1. **Teach the gate the failure mode.** FP-ISLAND should compare the emitted feed against macro
   blockages, not only VDD against VSS. Until it does, a passing FP-ISLAND is a statement about
   rail-to-rail shorts, not about whether the feed is legal.
2. **Gate the window width itself.** A feed whose window is under some margin — 0.4 µm is
   plainly under it — should warn loudly at power-plan time, with the coordinates.
3. **Price it in Calibre, not `check_drc`.** The screen recorded 65 → 69 on the landed form and
   deliberately did not rank on it.

## 4. The lesson that is not about power grids

The claim "the divider is not in the shipping netlist" was first supported with
`grep -c '^module tidelink_link_clk_div' <gate.v>` → 0. **That probe is dead.** Genus
uniquifies and renames, so `grep -c '^module tidelink'` also returns 0 while `grep -c '^module'`
returns 3052 — no tidelink module matches that pattern whether or not it is in the design. The
zero measured the naming convention.

The conclusion survived on evidence that carries its own control: the netlist is dated
2026-08-14 and the divider RTL first appeared 2026-08-17, so it cannot contain it; and
`ratio_hold_r` and `rate_regs`, both introduced by the divider, return 0 against 143 unrelated
`clk_div` hits (QSPI, `stclkctrl`) that prove the search space is populated.

**A grep returning zero over a corpus you have not shown to be searchable is not a measurement.**
Related: `docs/tapeout/45`, and the `a-zero-that-measured-nothing` class this repo keeps
producing.
