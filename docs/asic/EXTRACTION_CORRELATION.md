# Extraction correlation between the P&R tool and the signoff tool

Measured 2026-08-27 on `gdsrun-20260826-rc1`. Nothing in this document changed a
tracked file, a database, or a pin.

---

## Verdict, before the evidence

The engine gap is **real, it is extraction, and it is worth an 8.5x multiplier on
the hold failing-endpoint count the P&R tool optimises against**. One attribute
closes a third of it, in 151 seconds, on collateral this project already has.

But the mechanism written up in
`ASIC/eth-chiplet/build/holdeco-20260827/ENGINE_GAP_FINDING.txt` is **wrong in a
way that matters**, and the change it implies would have fixed nothing:

| claim | status |
|---|---|
| the two engines disagree by ~4.5% of data path on the shared endpoints | **VERIFIED** — reproduced to the fourth decimal, §2.4 |
| the hold requirements are identical | **VERIFIED** — identical on all four, and cell delay agrees across 1,363,586 arcs, §2.2 |
| the tool logs IMPEXT-6202 and nobody has actioned it | **VERIFIED** — genuine tool emission, not an echoed comment, §1.1 |
| "the P&R tool runs its cap table at effort medium" | **REFUTED** — post-route it already runs a Quantus engine off the same deck the signoff tool uses, §1.2 |
| "dropping the cap table so QRC is used throughout" is the fix | **REFUTED as the fix for THIS gap** — it changes pre-route extraction only. Worth doing, for a different reason, §1.3 |
| the shift is uniform, and macro inputs fail first only because their requirement is ~8x a flop's | **REFUTED** — the disagreement is *concentrated on* macro-input nets, not merely amplified there, §2.3 |
| worth ~15 ps of hold slack across the design | **PART TRUE** — worth 12–19 ps on the shared endpoints, but worth **1 ps of WNS** and **120 endpoints**, §3 |

Recommendation: **land the change, disabled, now; enable it after submission.** §8.

---

## 1. The configuration difference, verified

### 1.1 IMPEXT-6202 is genuinely emitted

The project MMMC (`ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.mmmc`,
`create_rc_corner` blocks) passes **both** `-cap_table` and `-qrc_tech` on all
three RC corners. The tool objects, once per session:

```
**WARN: (IMPEXT-6202):  In addition to the technology file, the capacitance table
file is specified for all the RC corners. ... the capacitance table files can be
removed from the create_rc_corner command to enable the technology file to be
used for pre_route and post_route (effort level medium/high/signoff) extraction
engines.
```

This is not the logs echoing their own Tcl. Across the six P&R logs of the
shipping candidate there are 27 occurrences of the string; **zero** carry an
`@file NNNN:` prefix or a leading `#`, and the message appears in the tool's own
end-of-run WARNING census with a count:

```
$ cd ASIC/eth-chiplet/build/gdsrun-20260826-rc1/work
$ for f in innovus.log innovus.log1 innovus.log2 innovus.logv innovus.logv1 innovus.logv2; do
    tot=$(grep -c IMPEXT-6202 $f)
    ech=$(grep IMPEXT-6202 $f | grep -cE '(@file [0-9]+:|^[[:space:]]*#)')
    echo "$f total=$tot echoed=$ech"
  done
```

### 1.2 But the post-route extractor is NOT the cap table

Read back live from the routed database today:

```
extract_rc_engine            post_route
extract_rc_effort_level      medium
extract_rc_lef_tech_file_map <empty>
extract_rc_hard_block_obs    false
extract_rc_qrc_cmd_type      auto
extract_rc_qrc_run_mode      concurrent
extract_rc_coupled           true
```

Per the installed tool reference (`TCRcom/extract_rc_Category_Attributes.html`),
`extract_rc_effort_level` selects the **post-route engine variant**, and `medium`
is TQuantus — "the default extraction engine in the post-Route flow for 65 nm and
below design", requiring a Quantus technology file and no Quantus licence. The
route log shows it doing exactly that, off the same deck the signoff flow uses:

```
#Start tQuantus RC extraction...
#found CAPMODEL  <the project's QRC deck>
#found RESMODEL  <the project's QRC deck> 25.000000
#Complete tQuantus RC extraction.
# Parasitics Mode: SPEF/RCDB
```

It even derives, unaided, the same design-to-deck layer correspondence that
`ASIC/sta/qrc_layer_map.ccl` derives by hand from the interconnect topology —
independent corroboration of that file:

```
#metal1 -> M1 (1) ... #metal9 -> M9 (9)   #metal10 -> AP (10)
```

So the P&R tool is **not** extracting off a table. It is extracting off the same
deck, with a lower-tier engine. The tiers, from the same reference page:

| effort | engine | notes |
|---|---|---|
| `low` | native detailed | the fallback when no deck is supplied |
| `medium` | TQuantus | **in use today**; no Quantus licence |
| `high` | IQuantus | "superior accuracy compared to TQuantus"; needs a Quantus-XL licence, unverified on this site |
| `signoff` | standalone Quantus | highest accuracy; **this is what the signoff flow already runs** |

### 1.3 What the cap table still governs, and why it is still worth removing

Pre-route. Place, CTS and every pre-route optimisation decision are made against
the cap tables, which the tech pack itself flags as being for a **different metal
stack** from the one this design is built on. Removing them from
`create_rc_corner` moves those stages onto the stack-correct deck.

That is a genuine defect and it should be fixed — but it is a *placement and
clock-tree* fix, not this one. It cannot move a post-route hold number, because
post-route the cap table is not being read.

---

## 2. How large the disagreement is — measured over the whole design, no licence

### 2.1 The artefact pair

Both tools wrote a delay file for the **same** routed netlist:

| file | writer | extractor |
|---|---|---|
| `ASIC/eth-chiplet/build/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_pnr.sdf` | P&R | TQuantus |
| `ASIC/sta/work/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_signoff.sdf` | signoff | standalone Quantus |

581,962 interconnect entries each, and **all 581,962 keys match** — same netlist,
same names. 1,363,586 cell arcs each.

Both are written **with derate applied**: the reference for `write_sdf` in both
tools says "By default, the `set_timing_derate` command writes scaled delays to
the SDF file", and neither flow passes `-no_derate`. So the derate cancels in a
ratio taken between the two files, and no correction is needed.

### 2.2 The control row, and the measurement

Compare the late slot of each file — the same corner in both.

```
CONTROL   cell arcs        n = 1,363,586   median ratio  1.0000
MEASURED  interconnect     n =    21,682   median ratio  0.9667   (aggregate 0.9674)
                           (nets whose P&R delay is at least 10 ps)
```

The control is the load-bearing half. The two tools agree on cell delay **to the
picosecond, at the median, across 1.36 million arcs**. That rules out a library
difference, a derate difference and a corner difference in one measurement — and
it leaves the 3.3% on the wires standing alone.

Binned by magnitude, cell arcs stay at 1.0000 in every bin up to 0.4 ns and only
reach 0.9855 in the largest bin (618 arcs above 0.8 ns) — i.e. the tools diverge
where the load is heaviest, and nowhere else.

### 2.3 Where the disagreement actually lives

Not uniformly. The interconnect ratio is a spread, not a shift:

```
p1 0.8947   p10 0.9091   p25 0.9333   p50 0.9667   p75 1.0000   p99 1.0714
56.7% of nets below 1.0
```

The four endpoints both tools rank in their worst-50, decomposed arc by arc, say
the same thing much more sharply. On the three memory-macro endpoints **every
upstream arc agrees to within 2 ps**, and the whole difference sits on the last
one — the driver into the macro's data input:

| endpoint | last arc, P&R | last arc, signoff | arriving transition |
|---|---|---|---|
| `...way1_cache_ram_data_ram_0_word_0_i/D[8]` | 0.113 | 0.103 | 0.189 -> 0.179 |
| `...way1_cache_ram_data_ram_0_word_1_i/D[0]` | 0.107 | 0.096 | 0.167 -> 0.158 |
| `...way1_cache_ram_data_ram_0_word_0_i/D[29]` | 0.100 | 0.095 | 0.133 -> 0.125 |

(the fourth is a flop endpoint; its largest single arc difference is 14 ps, on a
gate whose output transition is 0.13 ns — again the heavily loaded one.)

**So the correct statement of the mechanism is: the two extractors disagree about
the capacitance of heavily loaded nets, and a memory data input is the archetype
of a heavily loaded net.** Macro inputs dominate the signoff failing list for two
reasons compounding, not one: they are where the tools disagree, *and* their hold
requirement is an order of magnitude a flop's, so a given error costs more there.
The prior write-up has only the second reason and explicitly denies the first.

### 2.4 The prior figure, reproduced

The four shared endpoints, data path signoff-over-P&R:

```
0.9331   0.9684   0.9628   0.9604      mean 0.9562
hold requirement identical on all four (0.024 / 0.177 / 0.189 / 0.176)
```

Against the prior write-up's 0.9331 / 0.9684 / 0.9595 / 0.9604, mean 0.9554.
Reproduced.

---

## 3. The prototype: one attribute, measured today

Read-only copy of the shipping candidate's routed database, signoff derate
re-issued, hold reported on `default_analysis_view_hold` with a zero threshold,
then **only the extraction engine changed** and the report repeated.

| arm | extractor | hold WNS | hold FEP | TNS | macro-input endpoints | agreement with the signoff tool's worst-50 |
|---|---|---|---|---|---|---|
| A (as shipped) | TQuantus, effort `medium` | -0.012 | **16** | -0.035 | 2 | **0 of 50** |
| B | standalone Quantus, effort `signoff` | -0.013 | **136** | -0.404 | 86 | **21 of 50** |
| signoff tool, for reference | standalone Quantus | -0.053 | 394 (all hold views) | -2.309 | 34 of its own 50 | — |

Arm A reproduces the shipping candidate's own committed number exactly (16 /
-0.012 in `reports/hold_06_post_fill.rep`), so the control holds and the delta is
attributable.

The run's own artefacts are at `ASIC/eth-chiplet/build/extract-corr-20260827/` —
the script, the console log and both path reports. That directory is **ignored by
git and therefore host-only**, which is the standing trap in this project: the
durable form of this result is the reproduction in section 9, not those files.

Read that table carefully, because it does not say what the brief says:

* **The population moves, hugely.** 16 -> 136 endpoints, 8.5x; TNS 11.5x. 122 of
  the 136 are new, 14 of the original 16 survive, 2 improve.
* **The character of the population flips to match signoff's.** 2 macro inputs
  become 86 of 136, matching signoff's macro-dominated profile. Overlap with the
  signoff tool's worst-50 goes from **zero endpoints to 21**: as shipped, not one
  of the endpoints the P&R tool calls failing appears anywhere in the signoff
  tool's fifty worst. (Comparing *worst-50 against worst-50* instead of
  failing-against-worst-50 finds the four of §2.4 — a lower bar, and still four.)
* **The WNS barely moves.** -0.012 -> -0.013, against signoff's -0.053. Extraction
  is worth roughly a third of the endpoint count and **essentially none of the
  WNS gap**. Whatever explains the remaining -0.040 is not extraction, and this
  document does not identify it.

That is the honest scope: this change makes the P&R tool optimise the *right set
of paths*. It does not make its worst number agree with signoff's.

---

## 4. Ruled out, so nobody re-proposes them

* **Signal integrity.** Both tools ran with SI on — the report headers say
  `Signoff Settings: SI On` on both sides. Not a configuration difference.
* **Metal fill.** The shipping candidate carries no fill (`metal_fill off` in
  `reports/route_manifest.txt`, owner declared as the foundry), and the signoff
  extraction reports `MetalFill : OFF` for that reason. Both sides see the same
  absence.
* **Corner or temperature.** Both extract at the same temperature, and all three
  RC corners in this project point at the one deck — so the parasitics are
  corner-independent here and cannot be the difference. (That is itself a known
  limitation, recorded in the header of `ASIC/sta/qrc_layer_map.ccl`; it applies
  equally to both tools and so cancels.)
* **Reading the signoff parasitics back into the P&R tool.** Already measured
  by the previous session and confirmed here as a dead end: `read_spef` of the
  318 MB signoff file returns ok and leaves timing unchanged. Note for anyone
  re-testing it: the session's memory grew by about the size of the file, so
  "silent no-op" understates it — something was loaded and had no effect. Do not
  build on that path.
* **The macro timing arcs.** Cell delay agrees at the median across 1.36 million
  arcs, and the hold requirements are identical to the picosecond.

One further difference exists and pushes the *other* way, so it is not the cause
but should be recorded: the signoff extraction treats hard-macro obstruction
metal as visible (its grey-box mode is on), while the P&R tool's
`extract_rc_hard_block_obs` is `false`, its default, and is set nowhere in this
flow. The reference says setting it true "removes the optimism for such routes
and provides better correlation with sign-off extraction without significantly
impacting runtime". Enabling it would add capacitance in the P&R tool — the P&R
tool already has more — so it widens this particular gap while closing a
different one. Change it only with its own measurement.

---

## 5. Where the change belongs

**Not in the toolkit.** `ASIC/asic-toolkit` is a pinned submodule; a change there
costs a pin roll and reaches every project. Nothing here is general: the effort
level that is right for this design depends on this design's Quantus licence
availability and this design's runtime budget.

**Two changes, two homes.**

**(a) The post-route engine — `ASIC/eth-chiplet/hooks/pre_route.tcl`.**
The toolkit sources exactly ten hook names
(`pre_synth`, `post_synth`, `pre_floorplan`, `post_powerplan`, `pre_place`,
`post_place`, `pre_cts`, `post_cts`, `pre_route`, `post_route`) and a file with
any other name is never read — so a new `pre_extract.tcl` would be silently
inert. `pre_route` is called at `flow/innovus/4_route.tcl:881`, on the line
before `step "route"` and therefore before `route_design` and before every
`opt_design -post_route` arm. That is the only seam in the flow that is both
project-owned and early enough.

`pre_route.tcl` is **owned by another session today** and must not be edited from
here. The extraction knob should land as a second, independently gated section in
that file, coordinated with its owner. It should follow that file's own pattern,
which is the house pattern for exactly this kind of change:

* a master switch defaulting to the current behaviour, so the file can land
  before the change is wanted (`opt ROUTE_EXTRACT_EFFORT ""` — empty means "leave
  the tool's default alone");
* the tech pack consulted first and the literal only as a fallback;
* a `warn` block on the off path saying what is being inherited instead;
* every knob echoed into `route_manifest.txt`, where `extract_rc_effort` is
  **already** a recorded field (`4_route.tcl:2163`), so the manifest starts
  telling the truth about this run with no further work.

Sketch, not a patch:

```tcl
opt ROUTE_EXTRACT_EFFORT   ""     ;# "", low, medium, high, signoff
opt ROUTE_EXTRACT_MAP      ""     ;# CCL layer map; REQUIRED at signoff
if {$ROUTE_EXTRACT_EFFORT ne ""} {
    if {$ROUTE_EXTRACT_EFFORT eq "signoff" && ![file exists $ROUTE_EXTRACT_MAP]} {
        flow_fail "effort signoff needs extract_rc_lef_tech_file_map ..."
    }
    if {$ROUTE_EXTRACT_MAP ne ""} { set_db extract_rc_lef_tech_file_map $ROUTE_EXTRACT_MAP }
    set_db extract_rc_effort_level $ROUTE_EXTRACT_EFFORT
}
```

**(b) The cap tables — the project MMMC, `ASIC/genus-innovus/scripts/<block>.mmmc`.**
Delete the three `-cap_table` arguments and keep `-qrc_tech`. That file is
project-owned and tracked in this repository (it is a contract directory, not a
submodule and not lab-shared), so this costs no pin. It is read only by the
place stage's `init_design`, not by synthesis, so the netlist is unaffected;
placement, CTS and pre-route optimisation are.

Do these **separately**, one run each. They act on different stages and merging
them makes a regression unattributable.

### Two operational requirements that will bite

1. **The layer map is required at effort `signoff`.** With
   `extract_rc_qrc_cmd_type auto` (the default) the reference states
   "the `extract_rc_lef_tech_file_map` attribute is required to be specified",
   and that the map must be in CCL format — which is precisely the format of
   `ASIC/sta/qrc_layer_map.ccl`. **That file is directly reusable as-is**; the
   prototype used it unmodified and the extraction ran clean, raising only the
   single expected unmapped-contact-layer warning that the file's own header
   predicts and explains. At effort `high` the map is generated automatically and
   is not needed.
2. **The standalone engine is resolved from `PATH`, and the default `PATH` on
   this host resolves it to an installation three major releases older than the
   P&R tool.** `ASIC/sta/run_sta.sh` already carries this scar and fixes it for
   the signoff flow by prepending a version-matched location from
   `ASIC/sta/site.env`. The P&R stage does no such thing. A `pre_route` change
   that sets effort `signoff` **must** be accompanied by the same `PATH`
   discipline in the stage's environment, or the run will silently extract with
   the wrong-version engine.

---

## 6. Cost

**Extraction runtime, measured today** on this design, 8 CPU:

| engine | wall |
|---|---|
| TQuantus, per pass, in the shipping route run | 35–85 s (five passes, ~241 s total) |
| standalone Quantus, `extract_rc` end to end | **151 s** (of which the solver itself reports 2 min 3 s clock / 1 min 44 s CPU) |

**Why it is only one extraction and not three.** All three RC corners in this
project name the one deck at the one temperature, so the standalone engine runs
**once** and serves all three. The prototype confirms this: a single solver
invocation, one technology corner. A project with genuinely per-corner decks
would pay three times this.

**Extrapolated cost to the route stage.** The shipping route stage ran 4,200 s
wall (`route_manifest.txt: runtime_s 4200`) and spent ~241 s of it extracting.
Replacing five TQuantus passes with five standalone passes is roughly
`5 x (151 - 48) = ~515 s`, i.e. **about +9 minutes on a 70-minute stage, +12%**.
Against a full synthesis-to-route flow of ~4.6 hours (16,551 s of recorded stage
runtime) that is about +3%.
This is not a runtime problem.

**Licence cost.** The standalone engine checked out 4 + 1 seats at 8 CPU in the
prototype (3 + 1 at 6 CPU in the signoff flow). Seats were available on demand on
three separate days. The `high`/IQuantus tier needs a *different* feature which
this investigation could **not** confirm is licensed here — do not plan on it
without checking.

**Collateral cost: none.** The deck is already wired into the MMMC and already in
use. The layer map already exists. Nothing needs to be fetched, unpacked or
requested.

---

## 7. Risk

### What cannot turn red, and why

* **The hold and setup gates are already red.** `ROUTE_BUDGET_HOLD_FEP` and
  `ROUTE_BUDGET_SETUP_FEP` are 0 and the project overrides neither; the route
  gate already reports `hold FEP 16 > budget 0`. The signoff gate's
  `setup_fep_budget`/`hold_fep_budget` in `ASIC/sta/sta_policy.json` are also 0
  against 4 and 394. There is no green hold or setup verdict anywhere for this
  change to spoil — it makes an already-failing count larger and more honest.
* **Transition and capacitance DRV move the safe way.** The signoff extractor
  produces lower capacitance and sharper transitions, so `max_transition`
  (currently 6, already over budget) and `max_capacitance` (currently 0, green)
  can only improve or hold.
* **Synthesis is untouched by either change.** The MMMC is read by the place
  stage's `init_design` only. The gate netlist, and therefore every equivalence,
  ROM and netlist-simulation result bound to it, is unaffected *by the setting*.

### What genuinely moves

* **The routing does.** Optimisation decisions change, so the routed database,
  the streamed layout and every geometric result computed from them change:
  design-rule counts, connectivity, antenna, per-layer density, power-grid via
  and open counts, and the placement-dependent verification results. This is the
  real cost and it is not small.
* **The manual layout repair does not survive.** A known geometry fix in this
  project is derived from a specific verification result set and does not
  re-derive itself on a new route — the previous session recorded exactly this
  when it declined to re-run it after an ECO. A new route means re-deriving it.
* **Every A/B comparison against the shipping baseline is void, by the toolkit's
  own rule.** `ASIC/asic-toolkit/ci/equivalence.py` already lists
  `extract_rc_effort` among the knobs that make a run pair *void rather than
  failed* — "a different extraction is a different measurement" — and lists
  `hooks_run` alongside it. So the toolkit has already decided that a run with
  this change cannot be compared with the shipping candidate. That is correct and
  it is the point, but it means the new run must be judged on its own absolute
  numbers, with no regression check available against the thing it replaces.
* **The signoff pack is pinned by path to the current candidate.** `ci/signoff.yaml`
  spells `gdsrun-20260826-rc1` into `run:`, `check:` and `artifacts:` across the
  timing stages. A new build tag means re-pinning those rows, and until that is
  done the pack grades the old build.

### The risk that decides the question

Not the extraction. The **re-run**. Turning this on requires a fresh route, and
the shipping candidate's physical signoff — the layout-rule results, the manual
repair, the verification evidence bundle — is bound to the route it already has.
Re-rolling that eight days from submission buys a *better-targeted hold
optimisation* at the price of re-qualifying every geometric result, with no
regression check available to tell you whether you have gone backwards.

---

## 8. Recommendation

**Land it now, off. Enable it after submission.**

1. **Now, before 1 September.** Add the extraction section to `pre_route.tcl`,
   defaulting to the current behaviour so that a run without the environment
   variable is byte-for-byte the run we have today, and coordinate the edit with
   that file's current owner. Add the version-matched `PATH` handling for the
   standalone engine. Nothing about the shipping candidate changes; the knob
   simply becomes available and the manifest starts recording it.
2. **Now, and separately.** Record in the tapeout notes that the P&R hold count
   for this candidate is an underestimate by roughly 8.5x in population, and that
   the hold fix that shipped was computed in the signoff tool for exactly this
   reason. That is a statement about the candidate, not a change to it.
3. **After submission, first thing next revision.** Enable `signoff` effort with
   the existing layer map, and remove the cap tables from the MMMC — as two
   separate runs, in that order, each judged on its own absolute numbers.
4. **Do not** chase the residual WNS gap with this change. It does not move it.
   -0.013 against -0.053 is a separate investigation.

The argument for waiting is not that the change is risky in itself — it is
cheap, reversible and uses collateral already in the tree. It is that it can only
be *used* by re-routing, and re-routing eight days out re-opens a physical
signoff that is closed.

---

## 9. Reproducing the numbers

**The 3.3% wire-delay figure and its control** (no tool, no licence, ~2 min):

```bash
cd /path/to/nanosoc-ethernet-chiplet
I=ASIC/eth-chiplet/build/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_pnr.sdf
T=ASIC/sta/work/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_signoff.sdf

# interconnect: key on (driver, load), keep the late slot
ex() { awk 'match($0,/\(INTERCONNECT +([^ ]+) +([^ ]+) +\([-0-9.]+::([-0-9.]+)\)/,m){
             print m[1]"\t"m[2]"\t"m[3] }' "$1" | sort -k1,1 -k2,2 ; }
join -t$'\t' -j 1 \
  <(ex $I | awk -F'\t' '{print $1"|"$2"\t"$3}') \
  <(ex $T | awk -F'\t' '{print $1"|"$2"\t"$3}') \
| awk -F'\t' '$2>=0.010{r[n++]=$3/$2} END{asort(r); print "n="n, "median="r[int(n/2)]}'
```

Expect `median = 0.9667` over 21,682 nets. Then run the same join over `IOPATH`
arcs instead — that is the control, and it must come out at `1.0000`. **If the
control is not 1.0000, stop**: the two files are not at the same corner or one of
them was written with `-no_derate`, and the interconnect number means nothing.

**The 16 -> 136 prototype** (one P&R seat plus Quantus seats, ~6 min wall):

```bash
cp -a ASIC/eth-chiplet/build/gdsrun-20260826-rc1/work/nanosoc_eth_chiplet_pads_routed  $SCRATCH/db_src
export QUANTUS_HOME=<the release matched to the P&R tool; see ASIC/sta/site.env>
export PATH="$QUANTUS_HOME/bin:$QUANTUS_HOME/tools/bin:$PATH"    # NOT optional; see 5.2
innovus -stylus -no_gui -files $SCRATCH/xcorr.tcl < /dev/null
```

with `xcorr.tcl`:

```tcl
set_multi_cpu_usage -local_cpu 8
read_db $SCRATCH/db_src
set_timing_derate -early -data  0.95
set_timing_derate -late  -data  1.05
set_timing_derate -early -clock 0.97
set_timing_derate -late  -clock 1.03
# CONTROL ARM - must reproduce the candidate's own 16 / -0.012
report_timing -early -view default_analysis_view_hold -max_paths 20000 -max_slack 0 > A.rep
# TREATMENT - the only change
set_db extract_rc_lef_tech_file_map [pwd]/ASIC/sta/qrc_layer_map.ccl
set_db extract_rc_effort_level signoff
extract_rc
report_timing -early -view default_analysis_view_hold -max_paths 20000 -max_slack 0 > B.rep
exit 0
```

then count `^Path [0-9]+: VIOLATED` in each. **Assert on the reports, not on the
exit code** — the tool exits 0 after errors, and this run legitimately prints
106 of them. The two classes it prints with an `**ERROR:` prefix - 20
library-format and 1 power-intent - are both pre-existing; the library one alone
appears 213 times in the shipping candidate's own route log.

Arm A must give 16 / -0.012. If it does not, the database or the derate is not
what you think it is and arm B is uninterpretable.
