# The marker-driven PG repair, inside the flow

    measured 2026-09-16, build/vt9a3-20260916 (ECO on vt7high-20260914)
    toolkit  810d3e4   project pin bumped the same day
    result   Calibre 36 -> 35 non-zero rulechecks; VIA3.R.4:M4 1 -> 0; nothing else moved

## 1. What was wrong

rc4 cleared `VIA3.R.4:M4` with a marker-driven post-route ECO,
`ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl`, fed the run's own
Calibre results. That script is byte-identical in the shipped tree and this
one, it is proven twice at 738 -> 737 with no other rulecheck moving, and it
was never wired into the flow. The power-plan hook says so in capitals at
`hooks/post_powerplan.tcl:321`: not optional, not in this flow, every run that
streams without it ships the violation. The vt7high routed database contained
none of its via masters.

## 2. What the stage does now

`flow/innovus/5_eco.tcl` gained an optional step between the ECO route and the
in-flow checks, so `check_place` and `check_drc` judge the repaired database:

    ECO_MARKER_REPAIR_TCL    the project's repair script ("" = no step)
    ECO_MARKER_DRC_RESULTS   the PARENT's Calibre .drc.results
                             ("" = <parent work>/drc_run/<block>.drc.results)

A requested repair whose marker file is absent is HARD — "no marker" is the
control arm, the stream that ships the violation. A script that raises is HARD
with the tool's own ERROR lines quoted. The stage counts via masters before
and after and refuses a summary the database does not corroborate.

## 3. Measured

| | vt7higheco2 (no repair) | vt9a3 (repair) |
|---|---|---|
| Calibre non-zero rulechecks | 36 | **35** |
| Calibre results | 742 | 741 |
| VIA3.R.4:M4 | 1 | **0** |
| every other rulecheck | — | unchanged |
| setup / hold (signoff view) | +0.066 / 0 · −0.021 / 2 | identical |
| max_transition | 93 nets | identical |
| placement (check_place) | 82 → 82, 0 overlaps | identical |
| legalization scan | 0 / 0 / 0 | identical |
| GDS | 341,205,708 B | 341,208,024 B |
| wall | 3,455 s | 4,042 s |

The repair reported 1 site, 2 masters cloned; the database gained 2 via
definitions (1369 → 1371) and no instances, and its census names the two
masters it displaced. The stage's own numbers and the script's agree.

## 4. A defect the stage found in itself

The first two attempts refused. `vt9a` refused on `DMMMC-12` — the distributed
timing client's CPU-utilisation monitor firing under four concurrent EDA jobs,
on a view that finished successfully; tolerated now with that diagnosis in
`design.mk`, because it says nothing about the design.

`vt9a2` refused with "the marker-driven repair returned normally and printed no
summary line the stage can read". The line was in the log afterwards. The stage
noted where the session log ended, sourced the script, then read the tail —
and Innovus buffers that log, so the slower run looked before the write landed.
A race, not a missing line, and the gate refused rather than reporting a zero
it could not measure, which is the behaviour we want.

Fixed in toolkit 810d3e4: the script is sourced inside
`redirect -variable ... -tee`, which takes its output directly and still leaves
it in the log; the log tail is read as well and the two are unioned, so a UI
that refuses the redirect degrades to the old behaviour rather than going
blind. Both arms are proved in the stub harness — under the stub the capture is
the only source, so the existing marker assertions exercise it, and
`eco_redirect_no_variable.tcl` makes the stub refuse the capture and requires
the summary to come from the log. Harness 139 / 0.

## 5. Where this leaves the DRC gap

    rc4 (shipped)           32 non-zero rulechecks
    vt7high / vt7higheco2   36
    vt9a3 (this run)        35   <- VIA3.R.4:M4 closed

The remaining three are the via-fill pass's, gated separately in the place
stage (docs/tapeout/74); a route stream carrying that gate is measured in the
same record.
