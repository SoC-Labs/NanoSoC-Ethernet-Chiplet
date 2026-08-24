# Detecting unrouted nets in a front-end-only stream

**2026-08-24 · independent review · READ-ONLY, nothing committed**

What to BUILD so that "a pin shipped with no metal" cannot reach the foundry
again. A sibling owns *why LVS missed part of it*; this owns the gate set.

Site paths are `$RUN`, `$SCRATCH`, `$IMEC`. No vendor values reproduced.

---

## 0. Headline

**The check that would have caught this is already written, already correct, and
has never run.**

`ASIC/asic-toolkit/flow/innovus/4_route.tcl:1570` calls
`check_connectivity -type regular` after the rip-up repair, parses it, and
`lappend hard` on any unrouted signal net — with an explicit UNKNOWN path if the
check itself cannot run. It is exactly right. But:

    find ASIC/eth-chiplet/build -name '*imp_connectivity_postrepair.rep'
    -> nothing.  Never produced, in any run on disk.

It sits inside `if {$ROUTE_REGWIRE_REPAIR && [info exists DRC_REP]}` and then
inside the arm where `0 < RegularWire <= MAX`. It fires only when that one
specific repair fires. **There is no unconditional connectivity check before
`write_stream` (line 1749).**

That is the single highest-value change in this document, and it is a few lines.

The evidence that it works is already on disk. Run against a routed database
that carries the defect, `check_connectivity -type regular` names **both**
defective nets:

    Net .../FE_PHN9997_..._cache_subsystem_RAMCLD0WDATA_123: no routing
    Net .../..._cache_subsystem_RAMCLD0RDATA[123]: no routing
        2 Problem(s) (IMPVFC-98)

LVS named one of the two. This names both, in seconds, before the stream exists.

*Provenance, stated precisely:* these reports come from the `pinfix-20260824`
arms, which `read_db` pre-staged local copies (`db_orig`, `db_ctl`, ...). The
`FE_PHN9997_` hold-buffer prefix matches **valid4's** NRDR-27 line exactly and
does **not** appear in rzG's, so the graded lineage is valid4, not the submitted
rzG database. Both runs carried the same three bare pins — the toolkit comment at
`4_route.tcl` records the defect as "MEASURED, gdsrun-20260824-valid4 and
-20260823-rzG (the SUBMITTED stream)" — so the demonstration holds, but it has
not been run against rzG itself. **Running it on rzG's routed DB is a one-command
confirmation worth doing before relying on this.**

---

## 1. Two corrections to the brief's premise

### LVS caught one of the three bare pins, not all three

    foundry found (post-merge, 14 PO.R.8):
        way0 word_3  D[27]   -> RAMCLD0WDATA[123]
        way1 word_3  D[27]   -> RAMCLD0WDATA[123]
        way0 word_3  Q[27]   -> RAMCLD0RDATA[123]

    LVS on rzG ($SCRATCH/lvs/run/nanosoc_eth_chiplet_pads.lvs.rep):
        RAMCLD0RDATA[123]  line 3612  ** missing connection **  Xg87561:B2
        RAMCLD0WDATA[123]  ABSENT

Measured:

    grep -c 'RAMCLD0WDATA\[123\]'  ..._lvs_src.cdl        -> 5
    grep -c 'WDATA\[123\]\|WDATA_123'  ...lvs.rep         -> 0
    grep -c 'RAMCLD0RDATA\[123\]' ..._lvs_src.cdl         -> 2

The write-side net is in the source netlist five times and in the report zero
times. LVS flagged the stranded **load** (`Xg87561:B2`, an AOI22D1 at
837.800,428.035, per INCORRECT INSTANCES) and not the two stranded macro
**inputs**. `gds_macro_pin_connected.py` found all three.

**So LVS is necessary and not sufficient.** That is measured, not hedged.

### Do NOT gate on the router's warning stream

The brief proposes asserting on `NRDR-27` and `There were N open nets`. I tested
it and it produces a false positive on a healthy run.

`gdsrun-20260824-valid4` — the run whose repair *worked* — emits all of it:

    13:49:14  #INFO: There were 4 open nets and ecoRoute -fix_drc will not route these nets.
    13:49:16  #WARNING (NRDR-27) Net ...FE_PHN9997_..._RAMCLD0WDATA_123 is not globally routed.
    13:49:19  ROUTE: regwire-repair: route_eco failed:
    13:49:31  ROUTE: regwire-repair: Regular Wire 5 -> 0

and then calls `route_eco -target` (5 occurrences in that log), which repairs it.
`-fix_drc` *declining* open nets is now expected behaviour, and its warnings are
normal intermediate state. A gate on any of those three strings fails valid4,
whose stream is good.

(I also expected the toolkit's own comment — which quotes the NRDR-27 text
verbatim — to echo into logs as `@file` and self-trigger, per the standing
"Innovus logs echo their own Tcl source" trap. **It does not**: measured 0
`@file`-prefixed NRDR-27 lines across rzG and valid4. The trap is real in
general; it does not apply here. The false positive above is a different and
worse one, because it is on the tool's real output.)

**Assert on the post-repair state, not on the messages that preceded it.**

---

## 2. How it escaped — the run's own timestamps

`$RUN = ASIC/eth-chiplet/build/gdsrun-20260823-rzG`, `work/innovus.logv2`:

| time | line | event |
|---|---|---|
| 18:54:44 | 27426 | `check_connectivity` (untyped) -> 764 markers |
| 18:59:46 | 30680 | `regwire-repair: 5 Regular Wire marker(s) - ripping up and rerouting` |
| 18:59:46 | — | `delete_routes -regular_wire_with_drc` |
| 19:00:33 | 30820 | `#INFO: There were 4 open nets ... will not route these nets.` |
| 19:00:35 | 30825 | `#WARNING (NRDR-27) Net ...RAMCLD0WDATA[123] is not globally routed.` |
| 19:00:38 | 30862 | `ROUTE: regwire-repair: route_eco failed:` |
| 19:00:51 | 31304 | `regwire-repair: Regular Wire 5 -> 0`  ← scored a success |
| 19:01:09 | — | `write_stream` |

Three defects in nine minutes:

1. **The connectivity check ran five minutes before the last mutation.** Its 764
   markers are all power/ground — I censused the report body: `372 VDD, 368 VSS,
   12 VSSIO, 12 VDDIO`, **zero signal nets**. Clean because the damage had not
   happened yet.
2. **The repair's success metric counts the symptom it removed, not the wire it
   destroyed.** A deleted net carries no DRC marker, so `5 -> 0` is a perfect
   score for having deleted the routing. General class: *a repair judged only by
   the defect it was asked to remove.*
3. **`route_eco failed` was swallowed.** `catch { ... } _e` -> `say` -> continue.
   Still true of the new `route_eco -target` call: it only *says* it failed.

Toolkit `cadbd3b` (`-target`) and `3a8c30a` (post-repair re-check) address 1 and
2 — see §0 for why 2 is not yet armed. Defect 3 remains open.

---

## 3. Ranked proposals

Each states its **assertion** and its **population control** — the number that
tells a real zero from an unexecuted check.

### #1 — Unconditional `check_connectivity -type regular` before `write_stream`  `[HIGHEST VALUE]`

**Assertion.** Immediately before `write_stream`, on the final database:

    FAIL if any line matches ^Net (\S+):        (i.e. any unrouted signal net)
    UNKNOWN (not pass) if the check throws or the report is absent

**Why this is #1.** It catches the defect *at its source*, in the router's own
database, before the stream exists — so the run can abort instead of shipping.
It covers **all** signal nets, not just macro pins. It costs seconds inside a
session that is already open. It needs no licence beyond the one already held.
And the parsing logic, the hard-fail, and the UNKNOWN path are **already written**
at `4_route.tcl:1570` — the work is to hoist the call out of the
`ROUTE_REGWIRE_REPAIR` arm and run it unconditionally.

**Two-direction proof — already on disk, real tool output, no mutation needed.**
Full census of `ASIC/eth-chiplet/build/pinfix-20260824/reports/`:

    conn_preopt.rep       0 nets   Found no problems or warnings     <- pre-repair checkpoint
    conn_before_ctl.rep   2 nets   2 Problem(s) (IMPVFC-98)          <- FAIL fixture
    conn_final_ctl.rep    2 nets   2 Problem(s) (IMPVFC-98)          <- control: no change, still broken
    conn_before_orig.rep  2 nets   2 Problem(s) (IMPVFC-98)
    conn_final_orig.rep   0 nets   Found no problems or warnings     <- PASS fixture
    conn_before_eco.rep   2 nets   2 Problem(s) (IMPVFC-98)
    conn_final_eco.rep    0 nets   Found no problems or warnings
    conn_before_blkg.rep  2 nets   2 Problem(s) (IMPVFC-98)
    conn_final_blkg.rep   0 nets   Found no problems or warnings

The two nets, verbatim:

    Net .../FE_PHN9997_..._cache_subsystem_RAMCLD0WDATA_123: no routing
    Net .../..._cache_subsystem_RAMCLD0RDATA[123]: no routing
        2 Problem(s) (IMPVFC-98): Net has no global routing and no special routing.

**It names both defective nets, including `RAMCLD0WDATA[123]` — the one LVS did
not report.** Three independent fixes converge to 0; the no-change control stays
at 2. That is a proper two-direction proof with a control, on real tool output,
with zero mutation.

`conn_preopt.rep` is clean, which independently confirms §2: the routing was
intact at the pre-repair checkpoint and the damage was done by the rip-up.

> **Naming trap — read `ARMS.txt` before using these.** `_orig` is *not* the
> original broken stream; it is FIX Option 1, the one submitted. The control is
> `_ctl`. `ARMS.txt` exists because "a peer session read `_orig` as 'the original
> broken stream' and nearly stopped a good submission" — I made the same
> misreading while drafting this and caught it only by opening the file. In
> `conn_<phase>_<arm>`, `before`/`final` is the phase and the arm is the *fix
> under test*, so `conn_before_orig` means "the defective input state that arm
> orig was handed", not "the state of the original stream".

(Those reports come from the hand-written `pinfix-20260824/pinfix_common.tcl:67`,
not the flow; the flow's own artefact `*_imp_connectivity_postrepair.rep` has
never been written.)

**Population control.** The report must exist, its header must contain
`-type regular`, and its generation timestamp must be after the last route
operation. `Found no problems or warnings.` must be matched *positively* — an
empty or truncated report is UNKNOWN, never PASS.

**Misses.** It grades Innovus's database, not the stream. A defect introduced by
`write_stream` itself — a layer missing from the map file, a merge that did not
happen — is invisible to it. That is what #2 and #3 cover.

---

### #2 — Commit `accept_stream.py` and wire the macro-pin gate into signoff  `[HIGHEST VALUE, jointly]`

**`scripts/ci/accept_stream.py` is UNTRACKED.** `git ls-files` does not know it.
It is the best-designed harness in the tree and it is one `rm` from gone — the
standing "validated fixes can be orphaned in scratch" failure, live.

It already grades four criteria to PASS / FAIL / **UNMEASURED**, runs
`gds_macro_pin_connected.py` with a real population control (648 flash_cache_data
signal pins + 100 flash_cache_tag, so a narrowed scope fails instead of passing
quietly), refuses a DRC verdict without a matched same-session control run, and
exits `2` for "at least one UNMEASURED — you do not have a verdict".

**Assertion.** `bare == 0` over all placed macros, quoted as `0 bare of 748`,
never as a bare zero. VIA-ONLY reported separately.

**Why it stays high despite #1.** It is the only check that found all three pins,
and it measures the **streamed GDS** rather than the router's database. #1 and #2
fail independently.

**Work.** Commit it; add a `signoff.yaml` stage; build the fixture pair. Two
framework traps: `prove` requires **both** `must_pass` and `must_fail`, and its
sandbox symlinks the repo, so a fixture expressing *absence* needs
`.__exclusive__` or it reads the live file.

**Correction to my own earlier draft:** `signoff.py` *does* have the third state —
`PASS, FAIL, UNVERIFIED` at line 76, with "UNVERIFIED is not a softer FAIL... FAIL
indicts the design, UNVERIFIED indicts the run" and "Never add a code path that
turns UNVERIFIED into PASS". The discipline is present in both harnesses. The gap
is only that one of them is untracked.

**Stale note to fix while committing:** `accept_stream.py`'s criterion-2 comment
says no run has ever produced a `-type regular` artefact. The `pinfix-20260824`
reports above now falsify that.

---

### #3 — Gate the LVS run that already works, on a scoped assertion

**Assertion.** Not the verdict — the verdict stays INCORRECT for known reasons
(`.GLOBAL VSS` floods unmatched source nets; the pad ring has no LEF PINs), and
gating on noise is why it was ignored for a day. Instead, in `INCORRECT NETS`,
count net-discrepancy blocks whose *layout* column reads
`** missing connection **`, then:

    FAIL if any such block's SOURCE net name is hierarchical
          (contains '/' after the leading 'X')

**Measured on rzG:**

    missing-connection net blocks       69
      flat / top-level names            68   <- noise floor (bsp_*_in/out, VDDIO,
                                                VSS, VSSIO, FE_OFN*_LTIE_*)
      hierarchical names                 1   <- the defect

68:1 separation on real data. Note `grep -c "missing connection"` returns
**1095**, because the string recurs per-pin in `INCORRECT INSTANCES`; a gate
written against the raw grep is unusable. Count *net blocks*.

**Population control.** `flat_top_blocks >= 1` and the `INCORRECT NETS` section
present. Also assert the run used `LVS_PG=1 LVS_PG_PIN_TEXT=1` — without them
boxed leaves extract with zero pins and the compare degrades to a cell census.
Those flags are part of the assertion, not part of the setup.

**Catches.** Any net below top whose extracted connectivity is smaller than
source — over all ~222k nets, all standard cells included.
**Misses (measured).** `RAMCLD0WDATA[123]`. Do not claim macro-pin coverage.

**Cost.** Calibre LVS, licence held, already run: **111 s CPU / 115 s elapsed**;
~5 min wall including extraction.

**Two-direction proof.** rzG -> 1 (FAIL); pinfix -> 0 with the 68-block floor
intact (PASS). *Caveat: only the rzG run is in reach here; the pinfix LVS numbers
are the sibling's and I did not reproduce them.* Add a third direction that
proves the filter rather than the data: rename the hierarchical net in a copy of
the report to a flat name and confirm the gate flips.

---

### #4 — Ask the broker to return the MERGED stream  `[best value per unit effort]`

**Measured today: what they return is not merged.**
`$IMEC/Archive_..._18Aug26_19u28/nanosoc_eth_chiplet_pads_logo_full_L300.gds`
(305,721,896 B):

    cells 2460   cells with OD/PO 224   (the same 224 as ours: the memory macros)
    DFCNQD1  54 shapes, OD=0     INVD1  8 shapes, OD=0     PDDW16DGZ_G  64, OD=0

They merge internally, check, and hand back reports plus our own stream with
their fill. The merged database never crosses back.

**What it unlocks.** `docs/plans/BROKER_QUESTIONS_2026-08-19.md` Q8 records their
own three runs: `PO.R.8` = 691 unmerged, **0** with `tcbn65lp` +
`tphn65lpgv2od3_sl`, **0** with `tpbn65v` added. On a merged stream the assertion
is `PO.R.8 == 0` — zero threshold, no waiver, no cell list, fully discriminating.
Every blindness this document works around simply ends.

Q8 already asks for the merge *list*. **Add a distinct ask: return the merged
GDS, or run our two scripts on their side of the merge.** Both
`gds_macro_pin_connected.py` and `gds_cell_populated.py` were built stdlib-only,
no KLayout and no licence, explicitly so they can be handed over — that intent is
already in their headers. Cost to us: one paragraph.

---

### #5 — Licence-free connectivity extraction (avenue 1): the only SHORT detector

Feasible, and far cheaper than the brief assumed. **Measured on rzG:**

| step | time | RSS |
|---|---|---|
| KLayout reads the 300 MB stream (hierarchical, 2,328 cells) | **4.2 s** | 0.65 GB |
| `LayoutToNetlist`, M1 + VIA1, extract | **71 s** | 2.68 GB |
| `LayoutToNetlist`, 10 metals + 9 via layers, extract | **234 s** | 3.5 GB |

Full-stack gives **209,734 conductor clusters** against **222,517** nets — within
6%, i.e. it genuinely reconstructs connectivity from geometry alone. KLayout
0.30.10 is installed, open source, no token contention.

**What it adds over everything above: shorts.** #1 and #3 are *opens* tests. Two
nets merged into one cluster is the complementary failure and nothing we run
detects it in the stream — a live risk given how much manual geometry surgery
this stream sees (logo seam repair, fill trimming, M5 offset work, spliced ECO
patches). It also runs with no Calibre token, so it can gate every build rather
than every submission.

**Assertion.** Per netlist net, all its instance-pin locations fall in exactly one
cluster (open); and no cluster contains pins of two different nets (short).
**Population control.** `clusters_found` and `pins_located` both non-zero and
within a declared band of the net count; zero located pins is NOT-MEASURED.

**Honest status.** The cluster-to-netlist join is **not built**. I tried the
elegant shortcut — KLayout's hierarchical netlist, asking for subcircuit pins with
no parent net — and **it returns 0 and is wrong**: KLayout gives every isolated
pin its own singleton top-level net, so the query must be cluster-cardinality,
not null-pin. A design detail, not a blocker, but unbuilt.

---

### #6 — Extend the pin gate to standard cells (avenue 2) — **defer**

Mechanically feasible and cheaper than the brief assumed: **no LEF and no DEF are
needed for the geometry half.** Standard cells are placed as SREFs in the top cell
and their masters already carry their LEF pin metal.

    top-level placements  2,327,195 over 1,642 distinct masters
    cells  2,328 total | 10 empty shells | 2,094 metal-only | 224 with OD/PO
    DFCNQD1  19 polygons, all on 31/0 (M1), no text
    stream map:  M1 -> 31/0 for LEFPIN,PIN,NET,SPNET,VIA   (all one layer/datatype)

Two consequences of that map line. Pin metal and router metal are distinguishable
**only by hierarchy**, never by layer — precisely the trick
`gds_macro_pin_connected.py` already uses. And standard-cell masters carry **no
pin text**, so separating a signal pin from a VDD/VSS rail *does* need the LEF
(macros are self-describing: `flash_cache_data` carries 81 M1 / 81 M2 / 81 M3 /
481 M4 pin texts).

**Why it still ranks low: #3 already covers standard-cell nets, better.** LVS
compares all ~222k nets against the source netlist and therefore *knows which pins
should be connected*. A purely geometric pin check does not, so its
false-positive story — legitimately unconnected outputs, single-pin nets, unused
pins — is the whole problem, and resolving it means rebuilding LVS.

**Now measured, and the answer is the opposite of what I expected: it is fast
enough and useless anyway.** Flat two-region intersection on M1 over the whole
die, rzG:

    router M1 (top-level wires + via-master landing pads)     849,567 polys    7.8 s
    pin M1 (every non-via master, unmerged)                15,707,390 polys    9.1 s
    not_interacting(pins, router)          -> 7,945,841 "bare"   275.4 s, 10.85 GB

**Runtime is fine — under five minutes.** The problem is the result:
**7,945,841 of 15,707,390 pin polygons come back "bare", a 50.6% hit rate.**
That is the false-positive story the brief asked for, quantified. The population
is dominated by things that are *supposed* to have no router metal on them —
`FILL1`/`FILL4` filler cells, the 42,219 `ANTENNA` diodes, and power-rail
segments between straps — none of which the geometry can distinguish from a
defect.

Two filters would be needed to make it mean anything: the LEF, to reduce the
population to declared **signal** pins; and the netlist, to know which of those
are *supposed* to be connected. Once you have both you have rebuilt LVS, which
is #3, which already works and already covers standard-cell nets.

So the honest verdict on avenue 2 is not "too slow" — it is **"tractable and
redundant"**. Deferred on value, not on cost.

---

### #7 — Make the `PO.R.8` waiver a set (avenue 3) — **bad idea, drop it**

It would not have caught this defect, for a structural reason.

In our pre-merge stream *every* gate behind a macro input pin is already floating,
because its driver is a LEF abstract with no diffusion — true whether or not our
router reached the pin. Removing the metal from D[27] creates **no new** `PO.R.8`
result: the result was already there, already waived, at the same coordinate, in
the same cell. The count does not move because **nothing moves**. Set-ifying a set
that does not change cannot detect a change to it. The count only moves
post-merge, at the foundry, which is where the 14 came from.

What the waiver already does well and should keep: cell-scoped with per-cell
counts, fails on drift in *either* direction, fails if a listed cell matches
nothing, and `drc_census.py` refuses in code to waive the layout primary cell.
The residual gain from coordinates is catching a swap *within* one already-waived
macro periphery cell — narrow, and not this class.

**Leave it alone.** Spend the effort on #4, which deletes the waiver by making
`PO.R.8 == 0` assertable.

---

## 4. The minimal set

1. **#1** unconditional `-type regular` before `write_stream` — the router's DB,
   before the stream exists, seconds, both defect nets.
2. **#2** macro-pin gate on the streamed GDS — catches what `write_stream` breaks;
   found all three pins.
3. **#3** scoped LVS assertion — all ~222k nets; misses stranded macro inputs.

Their misses are complementary and measured. #4 removes the need for all three if
the broker agrees.

**Also close the swallowed failure:** make `catch { route_eco -target }` set a
stage-failure flag, not only `say`.

---

## 5. NOT-MEASURED must be structural

The brief's example — HTTP 200 with a JSON `errors` body read as "0 files" — has a
direct analogue in every gate here: *a zero that measured nothing.*

**A live example, produced by this review, an hour ago.** My own standard-cell
probe (#6) printed:

    ROUTER M1 polys=849567 in 7.7s
    PIN M1 polys=0 in 7.6s
    not_interacting 7.7s -> 0 bare pin polygons

`0 bare pin polygons` — a clean pass, and completely worthless: the pin region was
empty. KLayout's `RecursiveShapeIterator.unselect_cells()` is **inherited by child
cells**, so unselecting the top cell silently deselected the entire tree. The
check ran over nothing and reported zero.

It was caught only because the probe printed its own population alongside its
result. Had it printed just the verdict, it would have read as a pass over
366,446 instances. This is the same shape as the HTTP-200-with-an-error-body case,
and the same shape as the defect that started all of this. **Print the
denominator, always, in the same line as the result.**

The discipline is already present in both `signoff.py` (`PASS/FAIL/UNVERIFIED`,
"never add a code path that turns UNVERIFIED into PASS") and `accept_stream.py`
(`PASS/FAIL/UNMEASURED`, exit 2 = no verdict). The gaps are narrower than
"build it": **`accept_stream.py` is untracked**, and every assertion in §3 needs
its population control written down with it. `0 bare of 748` is a result; `0 bare`
is not. `0 hierarchical blocks of 69` is a result; `0` is not.

---

## 6. Measurement appendix

Measured 2026-08-24 on this host, load average 1.11 throughout.

| what | value |
|---|---|
| streams on disk | rzG (defective, 302,019,464 B), pinfix (fixed, 302,611,140 B) |
| KLayout | 0.30.10 batch (`klayout -b -r`), open source |
| KLayout read 300 MB | 4.2 s, 0.65 GB, 2,328 cells |
| KLayout L2N M1+VIA1 | 71 s, 2.68 GB, 784,112 clusters |
| KLayout L2N full stack | 234 s, 3.5 GB, 209,734 clusters |
| design scale (rzG manifest) | 366,446 insts / 222,517 nets |
| Calibre LVS | 111 s CPU / 115 s elapsed; 5,983,875 devices |
| LVS missing-connection net blocks (rzG) | 69 total / 68 flat / 1 hierarchical |
| LVS raw grep (misleading) | 1,095 |
| rzG connectivity markers | 764, all PG: 372 VDD / 368 VSS / 12 VSSIO / 12 VDDIO |
| route stage runtime | 4,042 s |
| `*_imp_connectivity_postrepair.rep` | **never produced, any run** |
| IMEC returned archive | NOT merged: 224 cells with OD/PO, `DFCNQD1` OD=0 |
| NRDR-27 `@file` echoes | 0 across rzG and valid4 (the echo trap does not apply) |
| KLayout flat M1 join (std-cell scale) | 849,567 router + 15,707,390 pin polys; join 275.4 s / 10.85 GB -> 7,945,841 "bare" (50.6% false-positive rate) |
| pinfix connectivity arms | before: 2 nets IMPVFC-98 (all arms + ctl); final: 0 (orig/eco/blkg), 2 (ctl) |
| `conn_preopt.rep` | clean — routing intact before the rip-up |
| python libs | numpy only; no gdstk/gdspy/shapely/klayout module |

Throwaway probes live in `$SCRATCH` (`probe2.py`, `probe5.py`, `probe6.py`,
`p7.py`). Nothing was written into the repo but this document.

### Corrections to figures in the brief

- "7 completely empty shells" — I count **10** on rzG: three ARM row-edge/filler
  cells, `PAD70GU_SL`, `PAD70NU_SL`, `PCORNER_G`, `PFILLER1/5/10/20_G`. The bond
  pads having *zero* geometry is worth noting separately: **no pad-pin check of
  any kind is possible on our stream.**
- "223,407 nets" — the rzG manifest records **222,517**.
- "366,995 instances" — the manifest records **366,446**.

Small, and they change no conclusion.
