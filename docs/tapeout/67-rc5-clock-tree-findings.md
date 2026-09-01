# 67 — rc5 flow findings, continued: the clock tree, and the two refuted preventions

**This file continues `66-rc5-flow-findings.md`.** It is a separate file for a
mechanical reason and not an editorial one: 66 reached 249,982 bytes and this
project's pre-commit guard refuses a tracked file over 262,144. Appending
F33-F35 to it would have needed a `VENDOR_CHECK_BYPASS`, which nothing in this
repository has ever needed (`vendor-check-bypass.log` is empty), and a size
guard tripping on a document that has outgrown one file is the guard being
right. Section numbering continues from 66; cross-references to F1-F32 mean
that file.

---

## F33 — THE LAST HOLD VIOLATION IS A SKEW-GROUP MEMBERSHIP DEFECT, AND `create_clock_tree_spec` CAUSES IT ON PURPOSE

`rc6full-20260831` finished RTL→GDS with exactly one hold violation. This is
what it is, why every run of this design has been one perturbation away from it,
and the one-attribute-shaped change that removes the exposure.

### The path, and the two numbers that settle it

`reports/hold_06_post_fill_av_ml_libset_hold.rep`, the whole of it that matters:

    Startpoint (R) ..._u_qspi_controller_mux_AHB_QSPI_BUSY_del_reg/CP   Clock QSPI_SCLK
    Endpoint   (R) ..._u_ahb_qspi_interface_ahb_qspi_busy_meta_reg/D    Clock clk

                           Capture       Launch
         Clock Edge:+       0.000        0.000
        Src Latency:+      -1.413       -1.413
        Net Latency:+       1.513 (P)    1.190 (P)
            Arrival:=       0.099       -0.223
               Hold:+       0.010
        Uncertainty:+       0.050
        Cppr Adjust:-       0.110
      Required Time:=       0.048
          Data Path:+       0.216   (already carrying two CKBD0 hold buffers)
              Slack:=      -0.056

**Source latency is IDENTICAL on both sides.** The entire difference is network
latency: 1.513 ns of `clk` tree to the capture flop against 1.190 ns of tree to
the launch flop — 323 ps, and the wrong way round. The launch flop is clocked by
a divide-by-2 of `clk` whose divider flop is itself a `clk` sink, so its clock
cannot physically be *earlier* than the divider's own CP plus one CP→Q. It is
earlier by 323 ps because **the divider's CP is early**.

### WHERE IT IS CREATED, WHICH IS NOT WHERE ANYONE LOOKED

    stage          rc6full-20260831 hold, View : ALL
    03_cts_opt     +0.005 /  0     (four active hold views)
    04_route       +0.005 /  0
    05_route_opt   -0.056 /  1
    06_post_fill   -0.056 /  1

Hold was **closed after CTS and still closed after detail route**. The violation
is created by `opt_design -post_route -setup -hold` — the simultaneous arm F29
adopted, which took setup from −0.268/133 to +0.083/0 in the same pass. So this
is not "CTS failed to close hold".

Stated exactly: at `04_route` the whole design's worst hold was +0.005 ns over
zero failing endpoints, and this path is not in `timing_04_route_early.rep`'s
worst-path list, so its pre-optimisation slack was better than +0.005 and this
run does not record what it was. What the run does record is that the
post-route pass moved it to −0.056. **The clock tree is not what failed the
path; it is what left the path with so little margin that a routine
optimisation move could.** A QSPI_SCLK→clk path balanced the way the spec's own
comment says it should be would be starting from a launch clock 1.2 ns later
than it is.

### THE MECHANISM, FROM FOUR ARTEFACTS AND THE VENDOR'S OWN WORDS

**1. The skew-group census.** `reports/cts_skew_groups.rep`, delay corner
`default_delay_corner_max:setup.late`, insertion delay min/max/avg:

| skew group | sinks | min | max | **avg** |
|---|---|---|---|---|
| `clk/default_constraint_mode` | 37,514 | 1.610 | 3.319 | **2.934** |
| `_clock_gen_clk_QSPI_SCLK_reg_reg/…` | 11 | 1.664 | 1.725 | **1.687** |
| `_clock_gen_clk_…_regs_reg13_reg[0]/…` | 1,941 | 1.702 | 3.311 | 1.983 |
| `_clock_gen_clk_…_regs_reg13_reg[1..4]/…` | 1,797 ea | 1.702 | 3.29x | 1.932 |
| `_clock_gen_clk_…_QSPI_SCLK_e_reg/…` | 11 | 2.693 | 2.831 | 2.804 |

The divider's group sits **1.25 ns below `clk`'s average and is 61 ps wide**. It
is not badly balanced. It is balanced beautifully, against the wrong thing.

**2. The spec says so in its own comments.** `reports/cts_clock_tree.spec`
:5876-5940. The group that *would* have balanced QSPI_SCLK's sinks against `clk`
exists, and is switched off with the reason written beside it:

    # This is a -constrains "none" skew group (reporting only) for generated
    # clock:QSPI_SCLK ... because it corresponds to a generated clock that is
    # synchronous to its master clock and will balanced as part of the skew
    # group corresponding to one of its master clocks.
    #  balancing master: clock:clk in timing_config default_constraint_mode
    create_skew_group -name QSPI_SCLK/default_constraint_mode -sources .../g457/ZN -auto_sinks
    set_db skew_group:QSPI_SCLK/default_constraint_mode .cts_skew_group_constrains none

Sixteen lines later the promise is broken:

    create_skew_group -name _clock_gen_clk_QSPI_SCLK_reg_reg/default_constraint_mode \
        -sources CLK -sinks { ...apb_qspi_regs_reg13_reg[0..4]/CP
                              ...QSPI_CLK_DIV_COUNTER_reg[0..4]/CP
                              ...u_qspi_clock_div/QSPI_SCLK_reg_reg/CP } -rank 1

**`-rank 1`.** Per `<INNOVUS_DOC>/TCRcom/create_skew_group.html`, an exclusive
group is ranked above every existing group and its sinks "are only active sinks
in [it], which is the highest ranked parent skew group" — the rank-1 group
**removes those eleven pins from `clk`'s rank-0 group**. The reporting-only group
says QSPI_SCLK's sinks will be balanced by their master's group; the rank-1 group
is what stops that from being true.

**3. It is a feature, it is on by default, and the tool announces it.** Both
runs print, unprompted, at spec creation:

    cts_spec_config_create_generator_skew_groups=true: create_clock_tree_spec will
    generate skew groups with a name prefix of "_clock_gen" to balance clock
    generator connected flops with the clock generator they drive.

`<INNOVUS_DOC>/TCRcom/cts_Category_Attributes.html`, default **true**:
*"This attribute will cause the create_clock_tree_spec command to create skew
groups for sequential generators and their adjacent registers. Such skew groups
will be specified with the same highest rank so that they can be balanced from
the other normal skew groups that share some sinks of them."*

Nothing in this project ever set it. It is Innovus's default behaviour, it is
right for a generator whose consumers are its own neighbours, and it is wrong
for this divider, whose consumers are timed against `clk`.

**4. Confirmed on the database, not just in the report.** A read-only Innovus
session on a copy of rc6full's placed database
(`build/rc7probe-20260901`, `work/probe_skew.tcl`) sourced rc6full's own spec
and asked the database directly:

    40 skew groups; every _clock_gen_* group reads
        cts_skew_group_exclusive_sinks_rank = 1, cts_skew_group_constrains = default
    clk/default_constraint_mode reads rank 0, constrains default
    QSPI_SCLK/default_constraint_mode reads rank 0, constrains NONE

### AND IT IS THE SAME 1.2 ns IN EVERY RUN, WHICH IS WHAT MAKES IT THE LOTTERY

Same corner (`default_delay_corner_max:setup.late`), same column, every run of
this design that still has its CTS reports, against the post-fill hold that run
finished with:

| run | placement | route arm | divider island avg ID | `clk` avg ID | **gap** | post-fill hold |
|---|---|---|---|---|---|---|
| rc5 attempt 7 | rc5 | `hold_then_setup` | 1.766 | 2.960 | **1.194** | −0.100 / 66 |
| `rc6hold-20260831` | rc5 | `setup_then_hold` | 1.767 | 2.961 | **1.194** | +0.003 / 0 |
| `rc6route-20260831` | rc5 | `setup_hold` | 1.767 | 2.961 | **1.194** | +0.003 / 0 |
| `rc6full-20260831` | rc6full | `setup_hold` | 1.687 | 2.934 | **1.247** | **−0.056 / 1** |

The island MEMBERSHIP is byte-stable across all of them — 11 sinks in the
divider island, 1,941 + 4×1,797 in the `reg13` islands, 11 in the `SCLK_e`
island, and `clk` at 37,514 constrained with 32 unconstrained, in rc5vt,
rc6hold and rc6full alike. **The gap is not the variable; the gap is the
constant.** Which side of zero a run lands on is decided by the placement and by
the post-route pass on top of it.

And the two runs that differ ONLY in placement, both on the winning
`ROUTE_OPT_MODE=setup_hold` arm, are the two ends of it: rc6route at a 1.194 ns
gap closes hold, rc6full at a 1.247 ns gap does not, by 56 ps. **53 ps more gap,
56 ps of violation.** With n = 2 that is a correlation and not a proof, and it
is written here as one — but it is the correlation the rest of this section
acts on.

### THE FIX, AND WHY IT IS NOT THE ATTRIBUTE THE DOCUMENTATION NAMES

The obvious lever is `cts_spec_config_create_generator_skew_groups false`. It is
the wrong one **here**, and the reason is a timing trap of the same family this
project keeps finding: the attribute is consumed by `create_clock_tree_spec`,
which `flow/innovus/3_cts.tcl` runs in section 8 at :848/:876 — **118 lines
before `flow_hook pre_cts` at :994**. Setting it from this hook would read back
`false` and change nothing, which is exactly what
`opt_signoff_hold_target_slack` does two sections earlier in the same file.
Hooks own what runs after them.

What is available after the spec exists is `delete_skew_groups`, documented as
deleting the groups and *"mak[ing] no changes to the design"*. With the rank-1
island gone, its pins are active sinks of the highest-ranked group that still
contains them — `clk/default_constraint_mode`, created `-auto_sinks` at rank 0
and therefore already holding every CLK-reachable sink as a member.

**Proven on the database before it was put in a run.** The same read-only
session (`build/rc7probe-20260901`) deleted the seven islands and re-ran
`report_skew_groups`:

    skew groups                              40  ->  33
    clk/default_constraint_mode  Constrained Sinks   37,514  ->  39,469   (+1,955)
                                 Unconstrained Sinks     36  ->     36    (unchanged)
    _clock_gen_D2D_RX_CLK_0_count_reg[3]_1..8          4 sinks each, UNTOUCHED
    _clock_gen_clk_count_reg[3]  (D2D TX generator)    4 sinks,      UNTOUCHED

1,955 pins handed back to the master, nothing orphaned, and the nine D2D
generator islands — which have their own history and have not been measured —
left exactly as the tool built them.

### WHAT WENT INTO `hooks/pre_cts.tcl`

Three knobs, all recorded in `cts_manifest.txt` by `opt`:

    CTS_GEN_SKEW_REBALANCE   0/1     delete the matching generator islands
    CTS_GEN_SKEW_PATTERN     glob    default {_clock_gen_clk_*qspi*} (-nocase)
    CTS_GEN_SKEW_STRICT      0/1     flow_fail when the pattern matches nothing

and a block that refuses to be silently inert. It prints the pattern; it
**refuses to delete any rank-0 group**, because `clk/default_constraint_mode`
matches a careless one-character pattern and deleting it would unconstrain
37,514 sinks; it reads each island's sink and source lists through a
DISCOVERED attribute name rather than an assumed one, and says so when it
cannot; it deletes; and then it **asserts on the census** — every victim must
be gone, and every island source must still have a surviving rank-0
constraining group to fall back to. Both assertions are `flow_fail`, and both
fire before `ccopt_design`, so a run that trips one has spent seconds rather
than the hour and forty the clock tree costs.

`delete_skew_groups` takes a PATTERN, not a name, and five of the seven island
names contain `[0]`..`[4]`. Innovus 21.11 deletes them when handed the literal
name — measured twice, 40 → 33 both times — but a matcher that read `[0]` as a
character class would delete nothing and say nothing, so the survivors are
retried with the glob metacharacters escaped before the assertion is allowed to
fail.

### AND IT HAS A FIXTURE SUITE, WHICH FOUND A REAL DEFECT BEFORE THE TOOL DID

`hooks/tests/prove_pre_cts_gen_skew.sh` — 25 assertions, about a second, no
licence, same shape as `prove_post_cts_guard.sh`. Its model is rc6full's real
census: the seven QSPI islands with their real sink counts, the nine D2D
islands that must survive, `clk` at rank 0 with 37,514 sinks.

Writing it found the bracket-pattern hazard above (the harness's `string match`
left five of seven islands standing, and the hook's assertion caught it, which
is how the escaped retry came to exist) and two reporting gaps. The scenarios
that matter are the ones that prove the block can say NO:

    C   a pattern that hits a rank-0 group is REFUSED, and clk is still there after
    D   a pattern that matches nothing warns ... D2 and is fatal under STRICT
    E   a glob-only matcher misses five islands ... E2 and the escaped retry gets them
    F   a delete that silently does nothing is caught (7 of 7) ...
    F2  ... and so is one that half works (1 of 7)
    G   a master that stops constraining is a flow_fail, not a note
    H   an unreadable sink list is reported as unreadable, not as zero
    H3  an unreadable source list degrades the master check loudly

### 10. THE 20 ENDPOINTS THE FILL ADDS ARE ALL AT −0.000

Every one of the twenty is at slack **−0.000** — over the limit by less than
half a picosecond. Eighteen are a contiguous run of synthesis gates
(`g88320 … g88832`, mostly `/B1` and `/B2` pins) and two are in `u_dmac_0`.
They are nets that were sitting exactly on 0.300 and tipped microscopically
over; they are not a degradation the fill causes. A repair pass that leaves any
real margin removes all twenty as a side effect, so the +20 is not a reason to
distrust a pre-fill fix.

### 11. A DRV PASS AFTER THE FILL IS STRUCTURALLY IMPOSSIBLE

Phase C ran `opt_design -post_route -drv` on the post-fill database with the IO
override active. The engine is invoked internally as

    Internal optDRV -postRoute -max_tran -max_cap -maintainWNS
      -setupTNSCostFactor 0.3 -maxLocalDensity 0.96 -numThreads 14 -glitch

— **its own local-density ceiling is 0.96** — and its table then reports
`Density 100.01%` on every row:

    | nets | terms|  wViol  | ... |  #Buf  |  #Inv  | #Resize|Density|
    |   197|   695|    -0.25| ... |       0|       0|       0|100.01%|
    |   155|   566|    -0.25| ... |       0|       0|      60|100.01%|
    |    78|   224|    -0.24| ... |       0|       0|       0|100.01%|

and:

    *info: Total 155 net(s) have violations which can't be fixed by DRV optimization.
    *info:     3 net(s): Could not be fixed because the gain is not enough.
    *info:   124 net(s): Could not be fixed because of exceeding max local density.

It managed 60 resizes and inserted **zero** buffers and **zero** inverters —
there is nowhere to put one. After `add_fillers` the core is full by
construction, so **no post-fill DRV repair is possible on this design**. This is
exactly the failure the toolkit's own knob comment predicts for
`ROUTE_OPT_DRV` at high utilisation; it just turns out to be a property of
running after the fill rather than of this design's utilisation.

That closes off one option that would otherwise look attractive — "measure the
gate's number, then repair it" — and it means the repair has to happen at
`4_route.tcl:1082`, where `ROUTE_OPT_DRV` already sits, before
`flow_step filler` at 1208.

### AND THE FLOW'S ONE CLOCK-ASYMMETRY GATE IS STRUCTURALLY BLIND TO THIS

`flow/innovus/3_cts.tcl:339`, `cts_hold_path_probe`, is the check that exists
for exactly this class of defect. It runs `report_timing -early` over
register-to-register paths and pulls three numbers out of the report:

    if {[regexp {Slack:=\s+([-0-9.]+)} $line -> s]} { set slack $s }
    if {[regexp {Src Latency:\+\s+([-0-9.]+)\s+([-0-9.]+)} $line -> c l]} { ... }

**Source latency only.** Its header says why — "launch and capture are the same
physical clock tree, so their source latencies must be equal" — and on this
defect they ARE equal: rc6full's `cts_manifest.txt` records

    hold_src_capture   -1.413
    hold_src_launch    -1.413

which is the probe reporting a perfectly symmetric clock on the run that
shipped a −0.056 hold violation caused entirely by a 323 ps NETWORK latency
asymmetry on the same path. The invariant the gate checks is real and it holds;
it is just not the invariant that broke. Adding the `Net Latency:` line to the
same regexp would cost one line and would have caught this at CTS —
`flow/innovus/3_cts.tcl` is the toolkit's file, not this project's, so it is
named here rather than changed.

### THE EXPERIMENT: `rc7gskew-20260901`, ONE FILE, ONE PLACEMENT, ONE VARIABLE

`build/rc7gskew-20260901` is cts → route from **rc6full-20260831's own placed
database** (`IN_RUN_TAG=rc6full-20260831`), staged by copying rc6full's pinned
tree and changing exactly one file — `pinned/eth-chiplet/hooks/pre_cts.tcl`.
`diff -rq` over the two pinned trees names that file and no other, and
`THE_ONLY_DIFF.patch` in the run directory is the diff. Every CTS-relevant
`design.mk` knob was checked against rc6full's launch header at staging time and
every one is identical; `ROUTE_OPT_MODE` reads `setup_hold`, which is what
rc6full's route actually ran (its `AMENDMENT-02`). The variable is passed in the
environment — `CTS_GEN_SKEW_REBALANCE=1` — because `design.mk` does not know the
knob, so the hook's own default of 0 reproduces rc6full without any edit.

**The rebalance did in the production stage exactly what the probe predicted:**

    CTS: rebalancing generator islands matching: _clock_gen_clk_*qspi*
    CTS: 40 skew group(s) exist before the rebalance
    CTS:   island _clock_gen_clk_QSPI_SCLK_reg_reg/...            : 11 sink(s)
    CTS:   island ..._apb_qspi_regs_reg13_reg[0]/...              : 1941 sink(s)
    CTS:   island ..._apb_qspi_regs_reg13_reg[1..4]/...           : 1797 sink(s) each
    CTS:   island ..._qspi_controller_QSPI_SCLK_e_reg/...         : 11 sink(s)
    CTS:   sink lists read through the 'sinks' attribute; 1962 distinct pin(s)
           over 7 island(s) (9151 with duplicates)
    CTS: rebalanced: deleted 7 generator island(s); 40 -> 33 skew groups
    CTS: surviving rank-0 constraining group(s): D2D_RX_CLK_0/... clk/... rmii_ref_clk/... swdclk/...

and its own `reports/cts_skew_groups.rep` closes the loop:

    Constrained Sinks           rc6full    rc7gskew
      clk/default_constraint_mode  37,514    39,469     (+1,955)
      unconstrained                    32        32     (unchanged)
      the seven QSPI islands       present     GONE
      the eight D2D islands        4 each    4 each     (untouched)
      _clock_gen_clk_count_reg[3]       4         4     (untouched, D2D TX)

### WHAT IT DID TO THE CLOCK TREE, AND TO THE HOLD WORK

`default_delay_corner_max:setup.late`, `clk/default_constraint_mode`:

                              min     max     avg
    rc6full                 1.610   3.319   2.934
    rc7gskew                1.244   2.988   2.529

and, the number this whole section is about, the hold the clock tree hands to
the post-CTS optimiser:

| CTS stage line | rc6full-20260831 | **rc7gskew-20260901** |
|---|---|---|
| `02_cts` / after `ccopt_design` | setup +0.083 / 0 · hold **−0.722 / 10,055** | setup +0.076 / 0 · hold **−0.733 / 1,951** |
| after `opt_design -post_cts` | setup +0.077 / 0 · hold −0.722 / 10,048 | setup +0.080 / 0 · hold −0.733 / 1,962 |
| after `opt_design -post_cts -hold` | setup +0.070 / 0 · hold **+0.005 / 0** | setup +0.080 / 0 · hold **+0.001 / 0** |
| guard: recovery pass spent | 0.690 ns / **9,120** endpoints | 0.701 ns / **1,746** endpoints |
| `03_cts_opt` (after guard repair) | setup +0.081 / 0 · hold +0.005 / 0 · tran −0.275 | setup +0.078 / 0 · hold +0.001 / 0 · tran −0.277 |

**The clock tree hands the optimiser 1,951 failing hold endpoints instead of
10,055 — an 81% reduction — for 7 ps of setup.** Worst-case hold WNS out of
ccopt is unchanged (−0.733 against −0.722), which is the honest reading: the
rebalance does not make the worst path better, it removes four fifths of the
population that had to be repaired at all. The same 81% shows up again in what
the F16 guard catches the recovery pass spending: 1,746 endpoints against
rc6full's 9,120, on the same knob settings.

Both databases leave CTS with hold closed over four active hold views. rc7gskew
leaves it at +0.001 against rc6full's +0.005 and with 3 ps less setup, and it
gets there with an 81% smaller repair.

### AND AT ROUTE: THE HOLD VIOLATION IS GONE, IN EVERY VIEW, WITH NO ECO

rc7gskew's route ran `ROUTE_OPT_MODE=setup_hold` — the same arm rc6full's route
ran — on the same placement, from the rebalanced cts database.

| stage | rc6full-20260831 | **rc7gskew-20260901** |
|---|---|---|
| post-cts (as read) | setup +0.078 / 0 · hold +0.005 / 0 | setup +0.078 / 0 · hold +0.001 / 0 |
| `04_route` | setup **−0.268 / 133** · hold +0.005 / 0 | setup **−0.144 / 77** · hold +0.001 / 0 |
| `05_route_opt` | setup +0.083 / 0 · hold **−0.056 / 1** · tran −0.132 / **156** | setup **−0.023 / 1** · hold **+0.001 / 0** · tran −0.103 / **110** |
| `06_post_fill` | setup +0.082 / 0 · hold **−0.056 / 1** · tran −0.132 / **155** | setup **−0.024 / 1** · hold **+0.002 / 0** · tran −0.103 / **114** |

**The per-view artefact, which is the claim and not the aggregate.**
`report_timing -early -view <v> -max_paths 20000 -max_slack 0`, one file per
active hold view, on the post-fill database:

    hold_06_post_fill_default_analysis_view_hold.rep   rc6full 1 path   rc7gskew 0
    hold_06_post_fill_av_ml_libset_hold.rep            rc6full 1 path   rc7gskew 0
    hold_06_post_fill_av_ltfix_libset_hold.rep         rc6full 1 path   rc7gskew 0

`av_ml_libset_hold` is FF / 1.32 V / 125 C — the corner that carried the
−0.056. **Three separate files, each independently empty. Hold is closed at
every corner, from a change made before `ccopt_design`, with no ECO anywhere.**

### THE COST, STATED AS PLAINLY AS THE WIN

**Setup opens one endpoint at −0.024 ns.** It is not a QSPI path and it is not
new physics — it is this design's own critical path:

    Path 1: VIOLATED (-0.023 ns) Setup Check
      Startpoint ..._u_cpu_0_..._cortexm0plus_..._core_op_q_reg   clk
      Endpoint   ..._u_tidelink_fifo_u_apb_regs_doorbell_response_acc_reg[15]/D   clk
      Data Path: 9.664 ns   (period 10.000, setup uncertainty 0.350)
      Net Latency: capture 2.283  launch 2.464     <- 181 ps of useful skew, the wrong way

CPU → fabric → TideLink APB register, 9.664 ns of logic in a 10 ns period,
inside `clk` in both directions. It misses by 23 ps because the rebalanced
tree is 0.4 ns shallower (`clk` avg insertion delay 2.934 → 2.529) and CCOpt
scheduled 181 ps of useful skew across it in the unhelpful direction. This is
this design's own logic-depth study — "82 of ~100 levels are outside
TideLink" — arriving as a timing number.

**Two of three dimensions improved and one 23 ps endpoint appeared.** DRV is
better by 41 endpoints and 29 ps (155 → 114, −0.132 → −0.103); hold went from
one failing endpoint to none; setup went from zero to one. By this project's own
measurement — "post-route setup repair is CHEAP AND SHARP … post-route hold
repair is EXPENSIVE AND BLUNT" — that is the right direction to have traded, but
it is a trade and not a clean sweep, and the next section is the experiment that
asks whether it had to be paid at all.

### THE ROUTE GATE, ROW BY ROW

`reports/route_gate.txt`, both runs, `HARD FAILURES: none` in both:

    rc6full-20260831                        rc7gskew-20260901
    380 missing power vias  > budget 0      380 missing power vias  > budget 0
    PG opens 51             > budget 0      PG opens 51             > budget 0
    dangling PG wires 727   > budget 0      dangling PG wires 727   > budget 0
    hold FEP 1  (WNS -0.056) > budget 0     -- ABSENT --
    -- ABSENT --                            setup FEP 1 (WNS -0.024) > budget 0
    max_transition FEP 155  > budget 0      max_transition FEP 114  > budget 0

The three PG rows are byte-identical: they are F23's standing known-bad and this
workstream did not touch them. **The hold row is gone**, a setup row at −24 ps
takes its place, and the transition row falls by 41 endpoints.

`make route` returned non-zero, the launcher recorded it, then asserted on the
artefact and found the routed database present — the same distinction rc6hold
made between "a gate refused to certify" and "a stage failed to produce".

### AND THE NEXT SINGLE VARIABLE IS RUNNING: WAS THE WHOLE FAMILY NECESSARY?

`build/rc7gskew1-20260901` is the same run with one word changed —
`CTS_GEN_SKEW_PATTERN=_clock_gen_clk_QSPI_SCLK_reg_reg*`, the **divider island
alone, 11 pins instead of 1,955**. Its CTS says most of the effect belongs to
the five `reg13` "adjacent register" islands and not to the divider:

    after ccopt_design, hold WNS / failing endpoints
      rc6full     no rebalance          -0.722 / 10,055    setup +0.083
      rc7gskew    7 islands, 1,955 pins -0.733 /  1,951    setup +0.076
      rc7gskew1   1 island,     11 pins -0.709 /  9,624    setup +0.084

So the 81% collapse in the hold population comes from handing the ~1,955
CPU/interconnect/tidechart flops back to `clk`, not from the divider — and the
narrow arm keeps rc6full's setup (+0.084) exactly where the wide arm lost 7 ps
of it. **If the narrow arm also closes the QSPI hold path at route, it is
strictly the better configuration and the pattern default should be narrowed to
it.** Its route result is the addendum below.

---

## ADDENDUM TO F33 — THE DIVIDER'S ISLAND ALONE IS THE ANSWER, AND IT IS BETTER THAN THE CONTROL IN EVERY DIRECTION

`rc7gskew1-20260901` finished. **Eleven pins.** Three arms, one placed database
(rc6full-20260831's), one pinned tree changed in one file each time,
`ROUTE_OPT_MODE=setup_hold` in all three, `06_post_fill`:

| `CTS_GEN_SKEW_PATTERN` | islands | pins moved | setup | hold | max_transition |
|---|---|---|---|---|---|
| *(rebalance off — `rc6full-20260831`)* | 0 | 0 | +0.082 / 0 | **−0.056 / 1** | −0.132 / 155 |
| `_clock_gen_clk_*qspi*` (`rc7gskew`) | 7 | 1,955 | **−0.024 / 1** | +0.002 / 0 | −0.103 / 114 |
| **`_clock_gen_clk_QSPI_SCLK_reg_reg*`** (`rc7gskew1`) | **1** | **11** | **+0.103 / 0** | **+0.000 / 0** | −0.110 / 155 |

**Both directions close, and setup closes with 21 ps MORE margin than the run
that had no rebalance at all** (+0.103 against +0.082). The per-view artefact
again, on the post-fill database:

    hold_06_post_fill_default_analysis_view_hold.rep    0 violating paths
    hold_06_post_fill_av_ml_libset_hold.rep             0 violating paths
    hold_06_post_fill_av_ltfix_libset_hold.rep          0 violating paths

### AND THE ROUTE GATE HAS NO TIMING ROW ON IT AT ALL

    rc6full-20260831              rc7gskew-20260901            rc7gskew1-20260901
    380 missing power vias        380 missing power vias       380 missing power vias
    PG opens 51                   PG opens 51                  PG opens 51
    dangling PG wires 727         dangling PG wires 727        dangling PG wires 727
    hold FEP 1  (-0.056)          setup FEP 1 (-0.024)         -- NOTHING --
    max_transition FEP 155        max_transition FEP 114       max_transition FEP 155

`HARD FAILURES: none` in all three. **For the first time in this design's
history a routed database reaches the route stage's own signoff gate with
nothing to say about setup OR hold.** What is left on it is the three PG rows
that are F23's standing known-bad and byte-identical across all three runs, and
`max_transition`, which F32 has taken apart separately.

### WHY THE NARROW PATTERN BEATS THE WIDE ONE, AND WHERE THE 81% WENT

The wide pattern is not wrong about the mechanism — it is right about a bigger
piece of it than the design can currently afford:

    after ccopt_design, hold WNS / failing endpoints, and setup
      rc6full     0 islands,     0 pins   -0.722 / 10,055   setup +0.083
      rc7gskew    7 islands, 1,955 pins   -0.733 /  1,951   setup +0.076
      rc7gskew1   1 island,     11 pins   -0.709 /  9,624   setup +0.084

**81% of the hold population ccopt hands the optimiser comes from the five
`reg13` islands, not from the divider.** Those islands hold 1,941 + 4×1,797
sinks of CPU, interconnect and tidechart flops that are "adjacent" to the QSPI
divide-ratio config register only in the sense that a datapath reaches them, and
taking them out of `clk`'s balancing pool is a real defect affecting ~2,000
flops. Returning them fixes that population — and, on THIS placement, makes the
`clk` tree 0.4 ns shallower (avg insertion delay 2.934 → 2.529), which
reschedules the useful skew that the CPU → TideLink APB path at 9.664 ns was
living on, and that path then misses by 23 ps.

**The divider's island is the one that has to go and the only one that has to
go.** Eleven pins — the generator flop, its five-bit counter and the five
`reg13` config bits — put back into `clk`'s pool, and every QSPI_SCLK → clk hold
path is fixed without touching the balance of the other 39,458 sinks.

That the 81% is real and currently unaffordable is the honest state of it: the
`reg13` islands are a known defect, left in place, with the knob to remove them
and the number that says what removing them costs on this placement.

### RUNTIME, AND THE STAGE EXIT

    == STAGE cts   starting 2026-09-01T14:46:15  done 16:24:58   1 h 39 min
    == STAGE route starting 2026-09-01T16:24:58  done 17:58:41   1 h 34 min

and the cts stage exited **clean** — no `FAILED (rc)` line, `0` real
`IMPDBTCL-248`. That is the committed revision of the hook running end to end
in a production stage, and it is the proof that the attribute-probe defect
`AMENDMENT-01` describes is actually fixed rather than merely fixed in fixtures.

---

## F34 — `opt_delete_insts`: THE NAMED NEXT VARIABLE, MEASURED

F26 left one instruction: *"`opt_delete_insts` (default `true`, exposed as
`CTS_RECOVERY_DELETE_INSTS`, deliberately not set in this run so that the area
attribute could be tested alone) is the obvious next single variable."* This is
that measurement.

### The substrate, and its one honest caveat

Two Innovus sessions, each reading its **own copy of the same bytes** —
`rc6full-20260831`'s written `cts` database, `md5`-identical between the arms
because both were copied from it. Each session reproduces the attribute
environment the recovery pass ran under in the flow, proves every attribute
took by read-back, runs `opt_design -post_cts`, and measures on both sides.

    design_flow_effort      extreme     (was standard)
    opt_skew_ccopt          extreme     (was standard)
    opt_hold_target_slack   0.080       (reads back 0.08)
    opt_setup_target_slack  0.075       (reads back 0.0749)
    opt_area_recovery       false       (was true)   <- F26's refuted prevention, kept ON in both arms
    opt_delete_insts        ARM A: tool default (reads 'true')   ARM B: false

**The caveat, stated first.** The written `cts` database is the state *after*
the guard's repair pass (setup +0.081 / hold +0.005 / 0), not the state the
recovery pass saw inside the run (setup +0.070 / hold +0.005 / 0). It is the
same KIND of state — hold closed, repair present, recovery not yet run — and it
is bit-identical between the two arms, which is what makes the comparison
one-variable. It is not a replay of the run, and the absolute numbers below
should not be quoted against the run's.

### Two traps this experiment walked into first, both now written down

* **A bare `report_timing_summary` EMITS NO HOLD SECTION AT ALL.** Measured
  here at 12:01 on 2026-09-01: the report has `# SETUP` and `# DRV` and no
  `# HOLD`. The toolkit's own `pnr_qor_line`
  (`flow/common/pnr_utils.tcl:1209`) passes `-checks {setup hold drv}` inside
  `pnr_simultaneous`, and both halves are load-bearing — without the mode the
  summary is setup-only (TCLCMD-1130). A hold guard reading a bare summary
  measures nothing and says "within budget". Cost: one arm.
* **`grep`ping an Innovus log for a word that appears in the script's own
  source.** The waiter watching for `FATAL` fired on the `@file NNN:` echo of a
  `P "FATAL: ..."` line that had not run. That is F25's family and the log
  filter has to exclude `@file` lines.

### THE RESULT: `opt_delete_insts` IS NOT THE MECHANISM EITHER

Both arms started from the same numbers, to the digit, which is what makes the
comparison one-variable:

    BOTH ARMS, BEFORE:  insts 248,847 | buf+inv 61,661 | setup +0.081/0 | hold +0.005/0

| | **arm A** `opt_delete_insts` default (**reads `true`**) | **arm B** `opt_delete_insts` **`false`** (was `true`) |
|---|---|---|
| insts after | 217,480 (**−31,367**) | 217,484 (**−31,363**) |
| buffers+inverters after | 30,294 (**−31,367**) | 30,298 (**−31,363**) |
| setup WNS / FEP | +0.081 → **+0.077** / 0 | +0.081 → **+0.076** / 0 |
| hold WNS / FEP | +0.005 → **−0.668 / 8,865** | +0.005 → **−0.668 / 8,871** |

**The attribute took** — the arm's own read-back line is
`opt_delete_insts = false (was true)` — **and it changed four cells out of
thirty-one thousand three hundred and sixty-seven.** Hold lands on the same
−0.668 in both arms. `opt_delete_insts=false` does not prevent the deletion.

**So both documented preventions are now refuted.** F26 killed
`opt_area_recovery`; this kills `opt_delete_insts`. The attribute that Innovus
documents as controlling whether optimisation may delete instances is set false,
proven false, and 31,363 instances are deleted anyway. Neither is the mechanism.
`CTS_RECOVERY_DELETE_INSTS` should stay blank: setting it buys nothing and
costs a knob that reads as protection.

### AND TWO THINGS THIS MEASUREMENT SETTLES THAT WERE NOT THE QUESTION

**1. Every deleted cell is a buffer or an inverter.** The instance delta and
the buffer+inverter delta are the SAME NUMBER in both arms — −31,367 and
−31,363. Not "mostly buffers": the whole reduction is the clock/repair
buffering, and nothing else in the design was touched. That is the hold repair
being removed, named at cell-class level for the first time.

**2. The "setup recovery" pass recovers no setup on this database.** Setup goes
**+0.081 → +0.077** (arm A) and **+0.081 → +0.076** (arm B) — it LOSES 4 and
5 ps. rc7gskew's own in-flow run of the same pass agrees, with the guard's
ledger line reading `setup gained -0.0020 ns | hold spent 0.7010 ns and 1746
endpoint(s)`.

On a database that already has setup closed with margin, `opt_design -post_cts`
after the hold pass is **not a setup recovery at all** — it is area reclaim
that spends the hold repair and returns nothing in the direction it is named
for. The DRV repair measured in F26 (117 internal `max_transition` endpoints,
worst internal −0.698 → −0.324, `max_capacitance` to zero) is the *entire*
remaining justification for running it, and the F16 guard plus its repair pass
is what makes running it affordable. Every word of that is now measurement
rather than expectation.

---

## F35 — WHAT TO SET, AND WHAT IS STILL OPEN

### The three knobs, and where they belong

`hooks/pre_cts.tcl` declares them with `opt`, so they land in
`cts_manifest.txt` whether or not `design.mk` names them, and the hook's own
defaults are the measured configuration. `design.mk` should still carry them —
`print-timing-knobs` is what a launcher echoes into its log, and a knob that is
only in a hook cannot be read there:

    export CTS_GEN_SKEW_REBALANCE ?= 1
    export CTS_GEN_SKEW_PATTERN   ?= _clock_gen_clk_QSPI_SCLK_reg_reg*
    export CTS_GEN_SKEW_STRICT    ?= 0

**The pattern is the DIVIDER'S ISLAND ALONE — eleven pins — and that is a
measurement, not a preference.** The wider `_clock_gen_clk_*qspi*` also closes
hold and then costs a −0.024 ns setup endpoint; the narrow one closes hold AND
leaves setup better than the run with no rebalance at all. The three-arm table
is in the addendum at the end of F33.

and three lines in the `print-timing-knobs` recipe beside the other `CTS_*`
rows. Setting `CTS_GEN_SKEW_REBALANCE=0` reproduces `rc6full-20260831` exactly;
that is the control and it is one variable away.

**`CTS_RECOVERY_DELETE_INSTS` stays blank.** F34 measured it: the attribute
takes, and it changes four cells out of 31,363. Setting it would put a knob in
the manifest that reads as protection and provides none.

### Verifying it took, in the log of any run

    CTS: rebalancing generator islands matching: _clock_gen_clk_QSPI_SCLK_reg_reg*
    CTS: 40 skew group(s) exist before the rebalance
    CTS:   island _clock_gen_clk_QSPI_SCLK_reg_reg/default_constraint_mode : 11 sink(s)
    CTS:   sink lists read through 'sinks': 11 distinct pin(s) over 1 island(s)
    CTS: rebalanced: deleted 1 generator island(s); 40 -> 39 skew groups
    CTS: every deleted island falls back to a rank-0 constraining group: clk/default_constraint_mode

and in `reports/cts_skew_groups.rep`, `clk/default_constraint_mode` at **37,525**
constrained sinks rather than 37,514 — eleven more. If the count is 37,514 the
knob did not take, whatever the manifest says. (On the wide pattern the same
line reads 39,469.)

### The fixtures

    hooks/tests/prove_post_cts_guard.sh      16 assertions   ~1 s   no licence
    hooks/tests/prove_pre_cts_gen_skew.sh    26 assertions   ~1 s   no licence

Both green. The post-CTS guard suite is unchanged and `post_cts.tcl` was not
touched by this work; the guard did its job in both new runs, catching 9,120
endpoints in rc6full and 1,746 in rc7gskew and repairing both.

### WHAT IS STILL OPEN, IN ORDER

1. **The five `reg13` "adjacent register" islands are still in place, and they
   are 81% of the problem by population.** Deleting them takes ccopt's hold
   output from 10,055 failing endpoints to 1,951; keeping them costs nothing at
   route on this placement and deleting them costs a −0.024 setup endpoint. That
   trade is placement-specific and worth re-testing on any new placement:
   `CTS_GEN_SKEW_PATTERN=_clock_gen_clk_*qspi*` is the one-word change.
2. **The nine D2D generator islands are untouched and unmeasured.** The same
   mechanism builds `_clock_gen_D2D_RX_CLK_0_count_reg[3]_1..8` (4 sinks each)
   and `_clock_gen_clk_count_reg[3]` (the D2D TX word-clock generator). Nobody
   has looked at whether they cost the D2D word clocks anything. Widening
   `CTS_GEN_SKEW_PATTERN` is a one-word change and a 3 h run.
3. **`cts_hold_path_probe` still measures source latency only.** One line in
   `flow/innovus/3_cts.tcl` — the toolkit's file — would have caught this defect
   at CTS instead of at post-fill.
4. **Nothing here is signoff.** Every number is Innovus's own; `ASIC/sta/run_sta.sh`
   has not been run on rc7gskew.
5. **`typical_analysis_view_setup` (F24) is still activated by no stage**, and
   the three PG rows (F23) are still the route gate's standing known-bad.
