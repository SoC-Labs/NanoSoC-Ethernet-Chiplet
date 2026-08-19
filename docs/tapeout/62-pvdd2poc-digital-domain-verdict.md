# 62 — `PVDD2POC` "multiple cells in digital domain": present/aware verdict

[← 52 Padring GDS check](52-padring-gds-check.md) · [53 Gate-promotion plan](53-gate-promotion-plan.md) · [index](00-index.md)

> **Status — measured 2026-08-19** against the working tree checked out at the time
> (`HEAD a2ca938`, branch `feat/padring-boundary-scan` — **not** `fix/tag-ram-gwen`; this
> repo has ~15 concurrent sessions and branch names in a task prompt are not reliable, see
> [`worktree-reads-are-not-commit-facts`] in the session's own memory discipline. What
> follows is what was actually read off disk, not assumed from the prompt).

---

## TL;DR

| Question | Verdict |
|---|---|
| **(a) Present on the current design?** | **YES.** 4 `PVDD2POC_G` instances, unchanged since the file's first commit, still on disk today. |
| **(b) Known before this message?** | **YES.** Landed in this repo's own docs the day before this session, with a purpose-built drift-detection script and a wired (report-gate) CI stage already tracking it. |
| **(c) Same defect as doc 51 (VDDIO/VSSIO no routed geometry)?** | **NO — a separate mechanism** that happens to touch the same net and the same pattern (IO supplies treated less rigorously than core VDD/VSS). See §4. |
| **(d) What would a second power domain need to contain?** | **Not confirmable from anything in this repo.** The team's own existing hypothesis is a *different* fix (reduce 4 POC cells to 1, not add a domain). See §5 and §6. |

---

## 1. Present on the current design — evidence

**The cells, exactly.** `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v` instantiates
`PVDD2POC_G` exactly four times, one per pad-ring side, all bound to the same pin and net:

```
215:PVDD2POC_G uPAD_VDDIO_T_0 (.VDDPST (VDDIO));   # top
228:PVDD2POC_G uPAD_VDDIO_B_0 (.VDDPST (VDDIO));   # bottom
241:PVDD2POC_G uPAD_VDDIO_L_0 (.VDDPST (VDDIO));   # left
249:PVDD2POC_G uPAD_VDDIO_R_0 (.VDDPST (VDDIO));   # right
```

Each side also carries two `PVDD2DGZ_G` siblings on the same `VDDIO` net (the "plain"
IO-supply pad — 8 more instances total, not gated by anything, shown for context only).

**Pad-ring positions**, cross-referenced against the IMEC report evaluated 2026-08-18
(`ASIC/imec_results/Archive_nanosoc_eth_chiplet_pads_logo_full_L300_dummy_merged_dummyWithSealRing_18Aug26_19u28/padring/Padring_check.rpt`
— gitignored, host-only, present in this working tree, same pattern as the ROM/LEC evidence
this project has already flagged as uncollected):

| Side | Instance | GDS position (µm) |
|---|---|---|
| Bottom | `uPAD_VDDIO_B_0` | (170.16, 20.16) |
| Top | `uPAD_VDDIO_T_0` | (195.16, 2020.16) |
| Left | `uPAD_VDDIO_L_0` | (20.16, 463.16) |
| Right | `uPAD_VDDIO_R_0` | (1620.16, 170.16) |

One per side, matching the die's four edges exactly (die is 1600×2000 µm — `x=0/1,600,000`,
`y=0/2,000,000` in 1 nm units, per `floorplan.tcl`'s `create_floorplan -die_size 1600 2000`,
independently confirmed in [doc 52 §5](52-padring-gds-check.md#5-validation-run-against-the-exact-gds-imec-saw)).

**Still present today, not just in the archived GDS.** Ran the repo's own drift-detector
against the live working tree:

```
$ python3 scripts/check_pvdd2poc_cardinality.py
PVDD2POC_G      : 4 instance(s) found
  side T          uPAD_VDDIO_T_0       -> .VDDPST(VDDIO)
  side B          uPAD_VDDIO_B_0       -> .VDDPST(VDDIO)
  side L          uPAD_VDDIO_L_0       -> .VDDPST(VDDIO)
  side R          uPAD_VDDIO_R_0       -> .VDDPST(VDDIO)
PVDD2DGZ_G      : 8 instance(s) found (context only, not gated)
...
PASS: 4 PVDD2POC_G instance(s), matches the recorded baseline (4), all wired to VDDIO,
names cross-check clean against the .io/tcl sources.
```

**It has never been anything else.** `git log -p --all -S "PVDD2POC_G uPAD_VDDIO" -- ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`
shows exactly one commit touching that pattern: `97f7fe6` (2026-07-16, "copy initial
genus-innovus flow from nanosoc-multicore-system") — the file's very first commit, which
inherited these four instances (unwired, `()`) from the sibling `nanosoc-multicore-system`
project. `defcb66` ("wire the 34 supply pads to the rails they are supposed to be on") later
bound `.VDDPST(VDDIO)`, but never changed the count or the cell type. `git status` on the
file today is clean (no uncommitted edits). **This is a defect the design was born with, on
2026-07-16, not something introduced by recent work.**

The project's CPF has likewise never changed in a way that bears on this: `git log --all -p
-S 'create_power_domain' -- '*.cpf'` returns one hit, the same 2026-07-16 initial copy, and
every generated build CPF since (`ASIC/eth-chiplet/build/*/outputs/nanosoc_eth_chiplet_pads_gate1.cpf`,
gitignored build output, checked directly) still reads:

```
create_power_domain -name PD_TOP -default
create_ground_nets -nets VSS
create_power_nets -nets VDD
update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS
```

— one domain, and (see §6) it does not even declare `VDDIO`/`VSSIO` as nets at all in the
shipping CPF, for reasons unrelated to this defect (see [doc 61](61-power-intent-never-adapted.md);
Genus's `write_power_intent -cpf` drops those constructs regardless of UPF content).

**Verdict: present, unambiguously, on the current design — and has been since the design's
first commit.**

---

## 2. What "digital domain" means here — both hypotheses checked

The task framing raised two live possibilities: a CPF/UPF power-domain classification, or a
padring-side/domain grouping convention. Both were checked against what is actually in this
repo, not assumed.

**Hypothesis A — CPF/UPF `-domain` binding.** Ruled out as the source of this specific
error. The CPF the P&R flow reads declares exactly one domain (`PD_TOP`), and Innovus/Genus
CPF domains bind **standard cells and macros**, never pad-ring I/O cells — nothing in
`power_plan.tcl`, the CPF, or the UPF assigns `PVDD2POC_G`/`PVDD2DGZ_G`/any pad cell to a
CPF power domain at all. The `.io` floorplan format
(`ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io`) has no `domain=` attribute in its
grammar — confirmed by inspection: the only per-instance attributes it supports are `name=`,
`place_status=`, `offset=`, `space=`, and `orientation=` (used only by the 4 corner cells).
So there is no mechanism in this design's source tree by which a pad cell could be assigned
to "the digital domain" via CPF/UPF/`.io` — **the CPF is not what is being complained
about.**

**Hypothesis B — a padring-checker-internal domain concept.** This is what the evidence
actually supports. The full IMEC `Padring_check.rpt` (§1 above) reports, in its own SUMMARY
section, immediately before and around the PVDD2POC error:

```
Power-checks results on digital domain: 0
Error-padringcheck, multiple PVDD2POC cells in digital domain
...
Number of power domains:   1
	Domain 0 is DIGITAL
```

That is Calibre's `Padringcheck` program computing its **own** notion of "power domain" by
walking the padring geometry itself — almost certainly using `PVDD2POC_G` instances as
domain-boundary/anchor markers (consistent with TSMC padring convention, where POC-suffixed
pad cells commonly serve as domain-transition anchors in multi-supply rings; this reading is
**general TSMC/Cadence convention knowledge, not confirmed against a POC-cell datasheet — no
such datasheet is on this site**, per [doc 55 Q8](55-imec-preliminary-gds-submission-checklist.md)
and the script's own docstring). The tool found exactly **one** domain across the whole ring
(consistent with this design's genuinely single-supply padframe — every pad is on `VDD`,
`VSS`, `VDDIO`, or `VSSIO`, no split rail), and then flagged that **within** that one domain
it saw 4 anchor-type cells where — on the best available reading — it expects exactly 1.

**So "digital domain" here is Padringcheck's own physical/geometric bookkeeping, not this
repo's CPF domain.** The CPF's `PD_TOP` and Padringcheck's "Domain 0 is DIGITAL" are two
unrelated concepts that happen to share the word "domain" — the CPF is single-domain
by construction (see §1), and Padringcheck's single-domain finding is a **consequence of
reading the padring**, not of reading the CPF (Padringcheck has no CPF/UPF input at all in
this flow — its only input named in the report is the pad-ring GDS library).

---

## 3. Was the team aware before this message? Yes, extensively.

| When (2026-08-18/19) | What | Where |
|---|---|---|
| Report generated | IMEC's archive-2 `Padring_check.rpt` contains the verbatim line `Error-padringcheck, multiple PVDD2POC cells in digital domain` | `ASIC/imec_results/Archive_..._18Aug26_19u28/padring/Padring_check.rpt` (gitignored, host-only) |
| `23:37` 18-Aug | Logged as broker question **Q8**: *"`PVDD2POC_G` — 'multiple cells in digital domain'. We instantiate it once per side (4 total), all on the same VDDIO net. Is this cell expected once per ring? No POC datasheet is available to us"* | `16d7811`, [doc 55](55-imec-preliminary-gds-submission-checklist.md) |
| same day | Root-cause reasoning written up: *"Best-evidenced read: Calibre expects this domain-boundary/anchor cell once per ring, not once per side. Likely fix: keep one instance, convert the other three to `PVDD2DGZ_G`. Not confirmable from what's on disk — no TSMC POC-cell datasheet is in-repo; needs a broker question or vendor doc before applying."* | `docs/plans/CONVERGENCE_PLAN_2026-08-18.md` §"New: PVDD2POC" |
| `10:14` 19-Aug (this morning, before this task) | A **drift-detection** script and CI stage landed: `scripts/check_pvdd2poc_cardinality.py`, wired as `ci/signoff.yaml` id `padring-power-domain` (`phase: physical`, `gate: report` — explicitly **not a fix**, tracks the count so a future silent change is visible) | `32d4edf`, alongside `90b1d88` |
| ongoing | Tracked in the gate-promotion retrospective as *"needs external input: PVDD2POC confirmation (broker/vendor datasheet)"* | [doc 53 §2–§4](53-gate-promotion-plan.md) |

**Verdict: not only known, but already named as an explicit open broker question, already
root-cause-hypothesised (with the hypothesis correctly labelled unconfirmed), and already
under automated drift tracking — all landed 8–20 hours before this task's message, by this
same project.** Nothing here is a new discovery; this task's own investigation independently
reproduces conclusions the team had already reached and documented.

---

## 4. Same defect as doc 51's VDDIO/VSSIO gap, or separate? Separate.

Both defects involve `VDDIO` and both stem from the same underlying pattern — IO supply
nets receiving less engineering rigor than core `VDD`/`VSS` — but they are mechanistically
independent, caught by different tools, and fixed by disjoint changes:

| | [Doc 51](51-erc-pg-labels.md): VDDIO/VSSIO never routed | This doc: PVDD2POC cardinality |
|---|---|---|
| **What's wrong** | `add_rings`/`add_stripes`/`route_special` in `power_plan.tcl` name only `{VDD VSS}` — zero ring/stripe metal ever generated for `VDDIO`/`VSSIO` | 4 `PVDD2POC_G` cells placed (once per side) where Padringcheck's own domain-anchor convention evidently expects a different count |
| **Level** | Physical routing — is there copper for this net at all | Cell-type/census — which *kind* of pad cell occupies these 4 slots |
| **Caught by** | Calibre ERC: "No labels found in topcell" | Calibre Padringcheck: "multiple PVDD2POC cells" |
| **Fix location** | `power_plan.tcl`'s `add_rings`/`add_stripes`/`route_special` calls | `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v` cell-type selection |

**Why converting POC cells would not fix doc 51, and vice versa:** `PVDD2POC_G` and its
sibling `PVDD2DGZ_G` bind to the identical pin (`VDDPST`) and identical net (`VDDIO`) —
doc 51 itself establishes that `connect_global_net`/pin binding is "PIN MEMBERSHIP, not
geometry." Converting 3 of the 4 POC instances to `PVDD2DGZ_G` changes zero routed wires;
the ring/stripe gap doc 51 measured persists identically either way. Conversely, routing
real `VDDIO`/`VSSIO` ring/stripe geometry would not change which pad-cell *type* occupies
the 4 anchor slots, so it would not silence Padringcheck's cardinality complaint. Both
findings appear in the **same** 18-Aug IMEC archive-2 run (so both are live simultaneously
on that stream), reported by different report sections, with different repair surfaces.

**Verdict: related in theme (VDDIO treated as an afterthought), not the same defect.**

---

## 5. What a second power domain would need to contain — inferred, NOT confirmed

**The team's own existing hypothesis is not "add a power domain" at all.** As quoted in §3,
the best-evidenced (still unconfirmed) local read is the opposite kind of fix — *reduce* the
POC-cell count from 4 to 1 (keep one anchor per ring, convert the other three to the plain
`PVDD2DGZ_G` supply pad) — explicitly **not** touching the CPF. `scripts/check_pvdd2poc_cardinality.py`'s
own docstring is emphatic that it "does NOT decide 1 vs 4 and does NOT convert any instance."

If the manual's page 31 item 4 instead calls for a genuine **second CPF/UPF power domain**
(a different remedy than the one this team has been considering), the only domain split
available anywhere in this design's own history to build from is the one already named in
the **original, tracked** CPF this project was copied from
(`ASIC/genus-innovus/inputs/nanosoc_chip_pads.cpf`, commit `97f7fe6`, still on disk,
unedited since) — which already lists power/ground nets as `{VDD VDDIO}` / `{VSS VSSIO}`
even though it only ever declares one domain:

```
create_ground_nets -nets {VSS VSSIO}
create_power_nets -nets {VDD VDDIO}
create_global_connection -net VSSIO -pins VSSPST
create_global_connection -net VDDIO -pins VDDPST
```

By extension — **inferred, not confirmed** — a second domain, if genuinely required, would
plausibly need to:

- be named something like `PD_IO` (naming not confirmed by anything on disk);
- have `-primary_power_net VDDIO -primary_ground_net VSSIO`;
- contain the pad cells whose supply pin is `VDDPST`/`VSSPST` — i.e. all 4 `PVDD2POC_G`
  (`uPAD_VDDIO_{T,B,L,R}_0`), the 8 `PVDD2DGZ_G` siblings, and the 12 `PVSS2DGZ_G` ground
  pads, all currently on `VDDIO`/`VSSIO`;
- leave `PD_TOP` (`VDD`/`VSS`) holding the core logic, the 6 `PVDD1DGZ_G` and 4
  `PVSS1DGZ_G` core-supply pads, and every standard cell/macro.

**This is inference from this design's own pre-existing (unused) net declarations, not a
derivation of what the manual or Calibre's Padringcheck actually requires.** It is offered
only so the chip owner has a concrete starting shape to check the manual's guidance against —
not as a proposed fix, and nothing here was implemented, per the task's own constraint.

---

## 6. What could NOT be determined without the manual

The following are genuine gaps this investigation could not close from anything in this
repo, general TSMC/Cadence CPF/padring convention, or the IMEC report text. Re-sharing the
manual (specifically page 31, item 4) would close these:

1. **Whether "instantiating another power domain" in the manual's own vocabulary means a
   CPF/UPF `create_power_domain`, or something Padringcheck-specific** (a deck switch, a
   GDS-level domain label/text, a different POC-cell placement rule). §2 establishes that
   Padringcheck's "digital domain" concept is not driven by this project's CPF today — but
   whether the manual's fix operates by *adding* a CPF/UPF domain that Padringcheck would
   then read, or by some other mechanism entirely, is not determinable from what's on disk.
2. **What `PVDD2POC_G` (the "POC" suffix specifically) is actually specified to do.** No
   TSMC POC-cell datasheet exists anywhere on this site (confirmed absent by the same search
   that found everything else in this doc). The "one anchor per ring" reading in §2 and §5
   is convention-based inference from the CONVERGENCE_PLAN/doc 53 authors, not a vendor
   citation.
3. **Whether the fix is "reduce 4→1" (the team's current hypothesis) or "add a domain
   construct while keeping 4" (what the task description says the manual may indicate) —
   these are different remedies and this repo has evidence pointing only at the former.**
4. **Whether a second domain, if required, is expected to have real supply-net separation on
   the die** (i.e. does the manual expect `VDDIO` to actually be a physically distinct rail
   from `VDD` with its own regulation, which this design's single-supply padframe does not
   currently provide) **or is purely a checker-satisfying declaration** with no physical
   change. This bears directly on whether doc 51's routing gap and this defect would become
   the same fix under the manual's guidance, or would remain separate even then.
5. **Whether any accepted remedy changes the pad-ring's physical layout** (cell count,
   position, or ring segmentation), which would interact with the still-open corner
   orientation fix ([doc 52 §7](52-padring-gds-check.md#7-corner-orientation)) and the
   not-yet-re-streamed GDS state described there.

---

## Related pages

[00-index.md](00-index.md) ·
[51 — Calibre ERC: PG labels](51-erc-pg-labels.md) — the VDDIO/VSSIO routing-geometry gap,
established separate from this finding in §4 ·
[52 — Padring GDS check](52-padring-gds-check.md) — the sibling Padringcheck finding
(corner orientation) from the same IMEC run, already fixed in the `.io` source ·
[53 — Gate-promotion plan](53-gate-promotion-plan.md) §2, §4 — where this check was designed
and its IMEC-tool-parity status tracked ·
[55 — IMEC preliminary GDS submission checklist](55-imec-preliminary-gds-submission-checklist.md)
Q8 — the broker question already queued on this exact finding ·
[61 — Power intent never adapted](61-power-intent-never-adapted.md) — why the shipping CPF
carries no `VDDIO`/`VSSIO` net declarations at all, unrelated to this defect but relevant
background for §5 ·
[`scripts/check_pvdd2poc_cardinality.py`](../../scripts/check_pvdd2poc_cardinality.py) — the
drift-detection check this doc's §1 ran ·
`docs/plans/CONVERGENCE_PLAN_2026-08-18.md` §"New: PVDD2POC" — where the root-cause
hypothesis in §5 above originates

---

[← 52 Padring GDS check](52-padring-gds-check.md) · [index](00-index.md)
