# 48 — IMEC Cybershuttle signoff results: analysis and comparison to local checks

> Analysis of `ASIC/imec_results/Archive_nanosoc_eth_chiplet_pads_logo_full_L300_merged_dummyWithSealRing_17Aug26_15u14/`,
> received from IMEC 2026-08-17/18. Produced by four parallel investigations (DRC/custom_drc/bnd comparison,
> antenna real-vs-null determination, ERC/padring root cause, plan/submission-process impact) plus direct
> provenance verification. Written 2026-08-18.

## 0. The headline that reframes everything else

**The GDS IMEC checked is not current.** By exact md5sum match
(`7f6214965501c911bd65069378ae911d`), the file IMEC ran
(`nanosoc_eth_chiplet_pads_logo_full_L300.gds`, submission-recorded modification time
2026-08-10 15:30:43) is byte-identical to
`ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_outputs/nanosoc_eth_chiplet_pads_logo_full_L300.gds`
— a snapshot from the now-**legacy** `ASIC/genus-innovus` engine. It predates:

- the toolkit migration to the current shipping lineage (`ASIC/eth-chiplet/build/{fp1505,full-20260814}`),
- the LEFOBS phantom-metal corner fix (landed 2026-08-17),
- the PO.R.8 floating-gate characterization (2026-08-18),
- the STA re-run with real parasitics (2026-08-18),
- the discovery that `fp1505`'s route stage crashed mid-run, and that IR-drop on `fp1505` came back
  `FAIL_HARD` with 330 disconnected instances (2026-08-18).

Everything below should be read as **an independent, real-foundry cross-check of an eight-day-old snapshot**,
not a verdict on the chip the team is currently trying to finish.

**Not the binding submission.** IMEC/mini@sic runs a two-stage process — a **Dry Run GDS**
(check-only, no shuttle commitment) and a separate **Final GDS**. Our own broker correspondence
(`docs/tapeout/27-broker-questions-SEND-NOW.md`) records a Dry Run due **Aug 4 (missed)** and a Final GDS due
**Sep 1**. **UPDATE 2026-08-18 evening: David has confirmed the Final GDS date directly — it is 1 September.**
The "Aug 18 IP-merge" cutoff scenario below this line was raised as a live risk earlier today from an
unresolved broker question (**Q0**, "IP merge" classification) circulating in a deleted draft still visible
in git history; it is now moot. There is real time to do this properly — see
`docs/plans/CONVERGENCE_PLAN_2026-08-18.md` §9 for what that changes about sequencing.

## 1. Per-category findings

### 1.1 Antenna — a genuine pass, but not a transferable one

IMEC's antenna deck (`ant/`, 207 files, 11m15s runtime) is a **real, geometry-populated PASS**: 204 rule
`.rep` files plus 578 internal gate-level DFM checks (782 checks total) all read zero, cross-validated against
the same report's DevCheck census of **6,420,952 real transistor-level devices** in the checked GDS. This is
structurally different from our own historical antenna nulls, which are empty because our flow black-boxes
cell interiors (no gate/diffusion geometry to measure against at all) — this run had real geometry to check
and found nothing.

**But it doesn't close our open antenna-signoff item.** It ran against the retired 2026-08-10 build.
`docs/tapeout/45-measured-status-2026-08-18.md` §4.8 already documents that the current lineage's own Calibre
antenna run is a structural null (0/714, all `.rep` files bare 30-byte headers) and explicitly says
**"Status: OPEN."** That status is unchanged — antenna signoff on `fp1505`/`full-20260814` still has not been
performed with real geometry present. The fastest path to actually closing it would be resubmitting a current
GDS through the same IMEC check-only service, or getting real vendor macro layout swapped in locally before a
local Calibre antenna run.

### 1.2 ERC / padring hard errors

Two hard `[Error]`-level results, not warnings, with two different causes:

- **ERC: "No labels found in topcell. At least power/ground labels are required."**
  Root cause confirmed: the legacy stream-out map used to build this GDS declares `NAME <layer>/PIN` rows but
  no `NAME <layer>/SPNET` rows, so `write_stream` emitted the VDD/VSS/VDDIO/VSSIO special-net grid with zero
  text labels (`ASIC/genus-innovus/scripts/calibre/make_project_header.py` records exactly this on this same
  stream: "48 text labels, all top-level PIN names... no power text anywhere in the top cell"). **Likely
  already fixed in the current toolkit** — `ASIC/asic-toolkit/tech/tsmc65/derive.tcl`'s `gdsmap_derive` now
  auto-appends `SPNET` rows, and the actual maps used to build `fp1505`/`full-20260814`
  (`work/tech/gdsout.stream.map`) do contain `NAME M1/SPNET` … `NAME AP/SPNET` rows. **Unconfirmed**: no ERC
  has actually been re-run against a current-toolkit stream to prove the labels now land.

- **Padring: "Design does not contain any TSMC IO cells or bondpads."**
  Root cause: **deliberate, by-design black-boxing.** `place_bondpads.tcl` does instantiate real TSMC-named
  cells (`PAD70GU`/`PAD70NU`, `PVDD1DGZ_G`) matching exactly what IMEC's padring checker looks for, but per
  the flow's own documentation these ship as **name references only — no GDS geometry**, because the
  submission is explicitly a black-box one (std cells / IO / bond pads are LEF abstracts). A checker that
  needs actual pad geometry to recognize a cell can't see an empty reference. This explains the same report's
  earlier "No identical cell names found!" in the CompareCells step, and is why the later `bnd`/`custom_drc`
  by-cell breakdown *does* show violations against `PAD70GU`/`PAD70NU`/`CORNER_B` — that's IMEC's own library
  **replacement** step backfilling real vendor geometry after the fact, not something we submitted.
  **This is not vintage-specific — it's still true of the current toolkit too.** No fix or plan exists to
  ship real pad geometry; whether IMEC's real (non-check-only) flow requires it or accepts black-box + a
  padframe description file is a process question for the broker, not something fixable in this repo alone.

### 1.3 DRC / custom_drc / bnd — validated against our own local Calibre run on the identical file

We had already run our own local Calibre against this exact file
(`ASIC/genus-innovus/calibre_runs/drc_logo_L300/`), which makes this the one truly apples-to-apples comparison
in the whole exercise. Results:

| Finding | IMEC | Local (same file) | Read |
|---|---|---|---|
| `PO.R.8` (floating-gate, SRAM/ROM macro periphery) | 691 (4282) | **691 (4282) — exact match** | Independently validates `docs/tapeout/39-po-r8-resolved.md`; already waived, no action |
| `LOGO.S.1` | 1000 (capped) | 1000 (capped) | Real, we already knew — see below |
| `LOGO.R.4` | 1000 (capped) | true count ≥1134 (also capped) | Real, we already knew — see below |
| `CSR.R.1` (die-corner empty-area) | not listed by IMEC's deck | **28 (28), unchanged, still open** | Pre-existing corner blocker; IMEC's run doesn't make it go away, it just doesn't check that exact rule |
| `CSR.R.2:B` / `CSR.R.2:D` / `CSR.EN.8` | 104 / 91(364) / 28, mostly in `CORNER_B` | 0 locally (needs seal-ring metal we don't add) | Structurally can't fire without IMEC's added seal ring — but the 91-count `CSR.R.2:D` hits land in the exact same `CORNER_B` cell as the still-open `CSR.R.1` |
| Acute-angle `G.2:*`/`*.S.6` family, small `AP.*` deltas, density-window shifts | small counts (~24 each) | 0 or off-by-a-few | Explained by IMEC's added dummy fill + seal ring (topcell grew 1600×2000 → 1640×2040um) — not a real gap |

Two things here matter more than the raw counts:

1. **LOGO clearance (LOGO.S.1 / LOGO.R.4) is real, we caught it ourselves, and it is undocumented.** Local
   Calibre runs exist under three names — `drc_logo`, `drc_logo_L300`, `drc_logo_text` — with LOGO.R.4's true
   count falling 5497 → 1134/1186 across them, meaning **someone already worked on shrinking this and never
   finished or wrote it down.** Nothing in `docs/tapeout/*.md` tracks it. This needs a formal punch-list entry
   now, not rediscovery next time.
2. **The die-corner seal-ring problem is still open, and IMEC's new seal-ring findings are downstream of it,
   not independent of it.** `CSR.R.1` (all four corners occupied by 135µm `PCORNER_G`, blocking the seal ring)
   was never formally closed in `docs/tapeout/`, and this run confirms it's unchanged. IMEC's ring collided
   with those same corner cells and surfaced as fence-metal-width/space violations (`CSR.R.2:B/D`,
   `CSR.EN.8`) instead of the empty-area violation we already track — same root mechanism, different symptom.

## 2. Does this change our targeted outlook?

**No — the critical path is unchanged, and none of these findings are diagnostic of the build we're actually
trying to finish.** `docs/tapeout/45-measured-status-2026-08-18.md` already establishes, independently and
more recently, that the current lineage is `NOT SIGNED OFF`: `fp1505`'s route never completed, DRC is a real
FAIL (140 design-owned, 6159 density windows), IR-drop is `FAIL_HARD` (330 disconnected instances), and there
is no real RTL→netlist LEC proof. Those are the actual blockers, and none of them are things this IMEC report
speaks to one way or the other.

**What this report does add:**

- Real, external validation that our DRC methodology and PO.R.8 waiver story are sound (exact-count agreement
  with a foundry-licensed Calibre run).
- A real, non-null antenna pass — proof the methodology works when given real geometry, even though it doesn't
  transfer to the current build.
- Two concrete, previously-undocumented punch-list items (LOGO keep-out finish-line, CSR.R.1-family corner
  fix verification against the new rule IDs) that must be carried into whatever build goes back to IMEC next.
- A likely-fixed-but-unconfirmed ERC gap (PG labels) that's cheap to verify — re-run ERC (or just inspect the
  stream map) against a current-toolkit output.
- A structural, by-design padring gap (black-box IO/pads) that isn't a bug to fix in this repo but **is** a
  question to put to the broker before any real (non-check-only) submission.
- Confirmation this was very likely a Dry Run check, not our binding Final GDS — **Final GDS is confirmed
  1 September**, so there is real time to close the items below properly.

## 3. Punch list

**Resolved:**
1. ~~Resolve broker Q0 (IP-merge classification)~~ — moot; David confirmed the Final GDS date directly, 1 Sep.

**Must carry into the next build before it goes back to IMEC:**
2. Finish and document the LOGO keep-out fix (AP-layer-only logo, per the abandoned `drc_logo*` experiments).
3. Re-verify the die-corner seal-ring fix against `CSR.R.2:B/D` and `CSR.EN.8`, not just the originally-tracked
   `CSR.R.1` — the existing fix (if any) was never checked against these specific rule IDs.
4. Re-run ERC (or inspect `gdsout.stream.map`) against a current-toolkit (`fp1505`/`full-20260814`-lineage)
   stream to confirm the `SPNET` fix actually produces PG labels end-to-end.
5. Raise the black-box padring/IO question with the broker: does IMEC's real (non-dry-run) flow require real
   pad geometry, or is black-box + a padframe description file sufficient?
6. Get a fresh antenna check (IMEC dry-run service, or real vendor geometry swapped in locally) against the
   current build — the retired build's clean antenna result does not transfer.

**Unaffected — already tracked, no new action from this report:**
7. `fp1505` route completion, DRC design-owned count, IR-drop `FAIL_HARD`, LEC end-to-end proof — all
   pre-existing, all still the actual gating items, all outside what this IMEC report measures.
