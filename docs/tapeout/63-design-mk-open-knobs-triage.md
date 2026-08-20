# 63 — `design.mk` open-knob triage (everything outside 11d/11e)

**Read-only audit, 2026-08-19/20 overnight.** `ASIC/eth-chiplet/design.mk` has accumulated a
specific pattern over one long night of work: a budget/knob is discussed at length, a real
hazard or measurement is documented, and the knob is **deliberately left unset**, pending a
real derivation. Two instances are being actively resolved by parallel sessions tonight and
are **out of scope here, untouched, not duplicated**:

- **§11d** `PLACE_MIN_MACRO_PG_GAP` (design.mk:824-909)
- **§11e** `ROUTE_BUDGET_PG_VIAS` (design.mk:910-925)

This doc covers every *other* instance of the pattern found by reading the entire file
(990 lines), not just grepping it. Method: read every section, tag every `?=` and every
"deliberately"/"left unset"/"tracked debt"/"not yet"-shaped comment, then for each one check
(a) whether a value is actually set nearby, (b) whether the file's own stated reason is a
permanent policy or an unfinished derivation, and (c) whether `docs/tapeout/` already contains
the missing derivation.

No edits were made to `design.mk` or any other file as part of this audit.

---

## Result summary

| # | Location | Item | Verdict |
|---|---|---|---|
| 1 | design.mk:725-736, 741-743 | `CTS_TARGET_TRAN` / `CTS_ROUTE_TYPE` (closes `CHKCTS-1`, `CHKCTS-2`, `CHKCTS-9`) | **GENUINELY OPEN** |
| 2 | design.mk:273-284 | Analysis view names left unset | INTENTIONALLY INERT |
| 3 | design.mk:313-317 | DCAP4 endcaps / antenna diodes not gated | INTENTIONALLY INERT |
| 4 | design.mk:772-780 | Pad-name separator note (`PLACE_EXPECT_PADS` pattern) | INTENTIONALLY INERT |
| 5 | design.mk:218-222 | `DFT_SETUP_TCL` empty | INTENTIONALLY INERT |
| 6 | design.mk:293-298 | `INNOVUS_REMOTE_HOSTS` empty | INTENTIONALLY INERT |
| 7 | design.mk:738-740 | `IMPSP-2021` not allowlisted | Not this pattern — noted for completeness |
| — | §11b, §11c, §11f | PG ratchets, unrouted-net count, metal fill owner | Checked, all have real values set, **no stale comments found** |

Only **one** genuinely open item exists in this file outside the two excluded sections, and it
splits into two knobs sharing one comment block and one allowlist. No "ALREADY RESOLVED /
stale comment" case was found anywhere in the file. No item required guessing — everything
below is either a value actually present three lines away, or an explicit permanence claim in
the file's own prose.

---

## GENUINELY OPEN

### 1. `CTS_TARGET_TRAN` and `CTS_ROUTE_TYPE` — closes `CHKCTS-1`, `CHKCTS-2`, `CHKCTS-9`

**design.mk:724-736**, inside the `CTS_ERROR_ALLOWLIST` comment block:

```
#   CHKCTS-1/-2      no CTS max-transition target, 42 = trees x corners.
#   CHKCTS-9         no clock route_type, same 42.
#                    TRACKED DEBT, not permanent: the knobs that close them are
#                    CTS_TARGET_TRAN and CTS_ROUTE_TYPE. Remove these three from
#                    the list when the knobs are set, and expect the tree to
#                    change when they are.
```

immediately followed by the allowlist that still carries all three IDs (**design.mk:741-743**):

```make
export CTS_ERROR_ALLOWLIST   ?= IMPLF-223 IMPMSMV-3501 \
                                CHKCTS-18 CHKCTS-19 CHKCTS-20 \
                                CHKCTS-1 CHKCTS-2 CHKCTS-9
```

This is explicitly contrasted, one paragraph above, with `CHKCTS-18/19/20`, which the same
comment block marks **"PERMANENT AND INTENDED"**. `CHKCTS-1/2/9` get the opposite verdict in
the file's own words — **"TRACKED DEBT, not permanent"** — which is why this is GENUINELY
OPEN and not INTENTIONALLY INERT: the file itself draws that line, this audit is only
reporting it.

**Confirmed live, not stale prose.** Neither `CTS_TARGET_TRAN` nor `CTS_ROUTE_TYPE` appears
anywhere else in `design.mk` — there is no `export … ?=` for either. The most recent full
build (`build/full-20260814/reports/cts_manifest.txt`) confirms both are still riding the
toolkit default of `0`, and `build/full-20260814/reports/pnr_messages_cts.rep` confirms all
three IDs are firing at the stated count and being allowlisted:

```
CHKCTS-1               42  allowlisted
CHKCTS-2               42  allowlisted
CHKCTS-9               42  allowlisted
```

**Checked against `docs/tapeout/`, including 42/45/54/56 as directed.** No numbered doc
mentions `CTS_TARGET_TRAN`, `CTS_ROUTE_TYPE`, or `CHKCTS-1/-2/-9` at all (`grep -rl` across
`docs/tapeout/*.md` is empty). The one place this gap *is* discussed at length is
`docs/tapeout/scripts/06-cts-and-route.md` §1.4 and §3.2, which documents the gap thoroughly
— quotes the same Innovus UG passage, confirms "no skew target and no transition target are
set anywhere," and separately confirms no non-default routing rule is applied to clock nets —
but **does not conclude with a number or a recommendation to act now**. It calls the missing
transition target "a deliberate gap, not a bug, but it is a gap," and calls the missing
route-type rule "a known, deliberate simplification, and at 65 nm it is survivable; it would
not be at a small node," explicitly suggesting the routing-rule half is worth revisiting
"once hold is fixed... not before, because the congestion it adds lands on the same resource
hold repair is already exhausting" (design finishes routing at 83.6% density, climbing to
92% during hold repair, per that doc §3.3). So this is **not** a five-minute transcription —
the derivation genuinely doesn't exist yet anywhere in the repo, and one half of it (route
type) may not be prudent to touch until the hold-repair work elsewhere finishes.

Splitting the two knobs by effort, since one is materially cheaper than the other:

#### 1a. `CTS_TARGET_TRAN` (closes `CHKCTS-1`, `CHKCTS-2`) — cheaper half

- **What's needed:** a numeric `cts_target_max_transition_time` value, with a derivation and
  a date, in the same style as every other budget in this file (compare §11b's via/fragment
  ratchets).
- **Derivable from disk, no licence needed for the lookup itself:**
  `build/full-20260814/reports/nanosoc_eth_chiplet_pads_cts.tran.gz` (post-CTS max-transition
  check — the only violations recorded are on 4 external/pad-boundary nets, remarked
  non-fixable, zero on any internal clock net) and the per-tree skew/latency reports already
  present in the same directory (`cts_clock_skew.rep`, `cts_clock_latency_setup.rep`,
  `cts_clock_latency_hold.rep`) give the actual measured transition behaviour of this
  design's 4 clock trees under the automatic target Innovus currently picks. `docs/tapeout/
  scripts/06-cts-and-route.md` §1.4 already has the tree/skew-group inventory (4 trees, 14
  skew groups, periods 10/20/40/10 ns) transcribed, saving a re-read of `design_clk.spec`.
- **Effort:** roughly 30-60 minutes of report reading to pick a defensible target (e.g. a
  fraction of the tightest clock period, or the worst observed tree transition plus margin)
  and write the `export CTS_TARGET_TRAN ?= <value>` line with its derivation. **No EDA tool
  run required to produce a candidate value** — the data needed to derive one is already on
  disk from the 2026-08-17 `full-20260814` CTS stage.
- **What still needs a run:** confirming the chosen value actually makes `CHKCTS-1`/`CHKCTS-2`
  stop firing (so they can be removed from the allowlist per the comment's own instruction)
  requires a real `make cts` — Innovus, licensed, and on this project's history that stage
  alone took ~58 minutes (`cts_manifest.txt: runtime_s 3489`). That confirmation step is the
  expensive part, not the derivation.

#### 1b. `CTS_ROUTE_TYPE` (closes `CHKCTS-9`) — pricier half

- **What's needed:** more than a boolean flip. `CTS_ROUTE_TYPE=1` requires `CTS_ROUTE_LAYERS`
  (or a tech-pack `route_layer_range`) to be supplied explicitly — `ASIC/asic-toolkit/tech/
  tsmc65/tech.tcl:477` confirms the tech pack deliberately leaves this unset too and "the
  engine refuses that experiment outright rather than guessing a span, which is the right
  behaviour." So closing this one is a real physical-design decision (which metal
  layers/spacing rule for clock trunks and leaves), not a report lookup.
- **Not derivable from existing reports alone** — no report on disk records a candidate layer
  range, and `docs/tapeout/scripts/06-cts-and-route.md` §3.2 stops at naming the UG's
  Routing Rule Recommendations (double-width double-spacing shielded trunks, double-width
  leaves) without picking layers for this design.
- **Priority tension worth flagging, not resolving here:** `design.mk`'s own comment calls
  this "TRACKED DEBT, not permanent" alongside `CTS_TARGET_TRAN`, with no distinction in
  urgency. The reference doc that actually analysed it recommends **waiting** — routing rule
  changes consume routing resource on a design already at 83.6-92% density, and it explicitly
  says to evaluate this "once hold is fixed... not before." Both documents are internally
  consistent (open ≠ urgent), but a future reader skimming only the `design.mk` comment could
  reasonably schedule this before hold repair when the more detailed doc says not to. Worth a
  one-line cross-reference from `design.mk` to `docs/tapeout/scripts/06-cts-and-route.md`
  §3.2 when someone next touches this comment (not done here — audit only).
- **Effort:** picking the layer range is a real engineering judgement call, not a timed
  lookup — call it an hour-plus of tech-LEF/stack review, and it should probably happen after
  the hold-repair work rather than tonight. Validating it costs a full CTS + route re-run
  (multi-hour, Innovus licence), same tool as 1a but with route added.

**Recommended order for whoever picks this up:** land `CTS_TARGET_TRAN` first (cheap,
independent, closes 2 of the 3 IDs), leave `CTS_ROUTE_TYPE` for after the hold-repair work
the reference doc says it should wait for.

---

## INTENTIONALLY INERT (correctly left alone — reported for completeness, not as TODO)

### 2. Analysis view names — design.mk:273-284

`CTS_SETUP_VIEW` / `CTS_HOLD_VIEW` / `ROUTE_VIEWS_SETUP` / `ROUTE_VIEWS_HOLD` /
`ROUTE_VIEWS_TYPICAL` are all left unset. The comment's own reasoning is a permanent
structural fact, not a pending derivation: the engine's defaults
(`default_analysis_view_setup` / `_hold`) are **exactly** the names this design's own mmmc
file uses, so "the correct action is to set nothing," and overriding them to any other name
would abort CTS after placement has already been paid for. `ROUTE_VIEWS_TYPICAL` is named
explicitly as an optional reporting-only addition with no timing effect. Nothing to do here.

### 3. DCAP4 endcaps and antenna diodes not gated — design.mk:313-317

Explicitly headed "DELIBERATELY NOT GATED," with the reason given as permanent: both counts
"track row geometry and move on legitimate floorplan edits" (endcaps 4492→4446, diodes
41,176→38,290 "between runs of the same design"), and an exact expectation on a legitimately
moving number "trains people to ignore the gate." `docs/tapeout/42-stranded-cells-pg-islands.
md` independently records the same DCAP4/ANTENNA movement (4,446 / 106 stranded, 2.38%),
consistent with this being a known-moving quantity, not an unmeasured one. Both counts still
appear in the census output for a human to watch. Not a TODO.

### 4. Pad-name separator note — design.mk:772-780

Reads at first glance like an open item ("MIND THE SEPARATOR... measured, not theorised") but
concludes with the opposite of a gap: the toolkit's *default* pattern
(`uPAD_%RAIL%_*`) is the one that is measured **correct** (VDD→6, VSS→4, matching
`PLACE_EXPECT_PADS` two lines above), while the alternative spelling
(`uPAD_%RAIL%*`) is the trap, and the engine already refuses ambiguous patterns rather than
guessing. The comment's last line says so directly: **"Left at the toolkit default
deliberately: this note names the trap, it does not change the value."** Nothing to set.

### 5. `DFT_SETUP_TCL` empty — design.mk:218-222

Not a placeholder: "No scan chain is bonded on this tapeout," sourced to
`../genus-innovus/scripts/config.tcl`'s `set DFT 0`. TEST/SE are handled by
`set_case_analysis` in the live constraints instead. An empty DFT setup script is the correct
state for a design with no DFT to set up, not an unfinished derivation.

### 6. `INNOVUS_REMOTE_HOSTS` empty — design.mk:293-298

Justified by a measurement already taken and stated inline: "the measured inter-host link is
~25 MB/s, ~37x slower than local disk, so slaves spend longer fetching the design than they
save." This is a completed measurement with a conclusion, not an open one — the knob is
empty *because* distribution was measured to be a net loss, not because nobody has checked.

---

## Adjacent but not this pattern

### `IMPSP-2021` — design.mk:738-740

```
# NOT allowlisted, deliberately: IMPSP-2021 "could not legalize 1 instance". That
# is a real placement failure - a CKBD16 clock buffer 2.4 um below the core's top
# edge with no legal site within 230 um - and adding it here would bury it.
```

This is the mirror image of the pattern in the prompt: it's a real defect that is
**deliberately left failing** rather than a knob deliberately left unset. There is no knob
associated with it in `design.mk` — the fix belongs in the floorplan/legalization itself, not
in an allowlist entry. Flagging it here only so the next reader doesn't mistake its absence
from the tables above for an oversight; it is out of this audit's pattern (no budget/value is
pending), and it is already correctly not suppressed.

---

## Sections checked and cleared (no stale comments found)

Specifically checked, since these are the sections most likely to have a "comment reads open,
value is actually set" mismatch, given they sit textually close to §11d/§11e:

- **§11b, design.mk:781-809** — `PLACE_MIN_PG_VIAS` and `PLACE_MAX_PG_FRAGS`. The comment
  opens by describing the pre-existing gap ("BOTH DEFAULT TO -1... and both sat at -1 for the
  whole life of this project") but the same block closes with the actual measured floor/ceiling
  and the two `export … ?=` lines land immediately below with values (`6`, `3570`). Coherent,
  not stale — this section already IS what §11d/§11e are trying to become.
- **§11c, design.mk:811-822** — `ROUTE_EXPECT_UNROUTED ?= 2`, set immediately after its
  measurement paragraph. Not stale.
- **§11f, design.mk:927-950** — `METAL_FILL_OWNER ?= foundry`, set immediately after its
  reasoning, with an explicit statement that this is "the CORRECT setting rather than a gap."
  Not stale.

No AMBIGUOUS items were found — every comment in the file was resolvable to one of the other
three verdicts from the text alone.

---

## Out of scope, noted only for awareness

`ASIC/asic-toolkit/tech/tsmc65/tech.tcl` (a different file, not `design.mk`, not audited here)
carries the identical rhetorical pattern for several tech-pack-level knobs — OCV derate
(`derate_data_early/late`, `derate_clock_early/late`), `max_transition`/`max_capacitance`, and
the ICG flop bounds — each explicitly headed "deliberately NOT set" with the same reasoning
style ("a plausible number in a pack reads as a measured one"). These are a different file
outside this task's scope and are not included in the verdict tables above; naming them only
so a future full-repo sweep doesn't have to rediscover that the pattern isn't unique to
`design.mk`.

---

## What was excluded, per instructions, and not touched

- **§11d** (design.mk:824-909), `PLACE_MIN_MACRO_PG_GAP` — live edit in progress tonight.
- **§11e** (design.mk:910-925), `ROUTE_BUDGET_PG_VIAS` — live edit in progress tonight.

Neither was read for the purpose of adding to this triage beyond confirming their line ranges
so the tables above don't overlap them.
