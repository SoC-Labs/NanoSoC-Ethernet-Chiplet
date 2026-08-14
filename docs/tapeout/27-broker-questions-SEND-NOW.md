# Broker questions — SEND NOW (run 10042-LP / TMWB45, Fab 14)

**Status: DRAFT READY TO SEND.** Two questions now outrank everything else, and one of them may have moved our deadline forward by two weeks.

> **REVISED 2026-08-11.** Three questions added (12 `PO.R.8` vendor waiver, 13 bond-pad deck generation) and question 4 rewritten now that the mini@sic manual has been read in full — it delegates dummy fill to eptsmc, which changes what we must do ourselves.
>
> **Our own DRC position improved substantially on 08-11 and the older numbers in this repo are stale.** We found that our stream-out map was emitting LEF *obstruction* geometry onto the real metal layers, putting 7.37 mm² of phantom conductor into the GDS — 68.8 % of all metal, 2.30× the die area. With a corrected map: total DRC results **7,527 → 3,606**, antenna **→ 0**, and the `M*.W.3` pad blankets **773 → 0**. Those were ours, not the broker's, and they are fixed. What remains is 691 `PO.R.8` (question 12), ~2,400 inside vendor macros, and ~500 genuinely ours. Do not send any attribution document written before 08-11 — see `28-drc-status-and-attribution.md`, which still carries a DO-NOT-SEND banner for this reason.

Recipient: `eptsmc@imec.be` (named in the schedule for LVS and merge services), or a portal support case — *Support Tape-out* for submission, *Support Foundry* for LVS. Source: `TSMC_EPmini@sicschedule2026V1_3c.pdf`, 26 Jan 2026.

## Confirmed dates for our run

| milestone | date | status |
|---|---|---|
| Reserve before | May 25 | done |
| Signed quote/PO before | Jul 17 | done |
| **Dry run GDS** | **Aug 4** | **MISSED — 5 days ago** |
| **Final GDS** | **Sep 1** | **…or Aug 18, see Q0** |
| Tape-out | Sep 15 | |
| Estimated shipment | Nov 27 | |

## Q0 — ARE WE AN "IP MERGE" CASE? (ask first, answer changes everything)

The schedule footnote on the Final GDS column reads, verbatim:

> \*\* **Provide final GDS two weeks earlier in case of IP merge.** In case of LVS or other services are required, please reach out to eptsmc@imec.be at the purchase order stage.

and the guidelines add:

> To ensure timely inclusion in the TSMC MPW when an IP merge is required, **deliver the final GDS 2 weeks in advance** to allow sufficient time for integration and validation.
> **Complete LVS Setup Required** — A fully validated LVS setup must be in place before initiating the merge process.
> TSMC requests to re-submit the merge even for minor typos or missing files

**We are shipping black-box TSMC standard cells, IO and bond pads for eptsmc to import.** If that counts as an IP merge, then:

- our final GDS is due **Aug 18, not Sep 1** — nine days from now, not twenty-three; and
- a **fully validated LVS setup** is a precondition, which we cannot produce today: we hold Front-End packages only, so there is no CDL for `tcbn65lp`, `tphn65lpgv2od3_sl` or `tpbn65v`.

Note also that the PO-stage window for arranging LVS services (Jul 17) has passed.

**Ask this before anything else.** If the answer is yes, the schedule and the LVS gap both need resolving this week.

---

## Draft

> **Subject: nanosoc_eth_chiplet_pads — TSMC 65LP mini@sic, corner keep-out and deck configuration queries (September shuttle)**
>
> Hello,
>
> We are preparing a TSMC 65nm LP (CLN65LP, 9M_6X1Z1U) design for the early-September mini@sic shuttle. Die is 1600 × 2000 µm (3.2 mm², aspect 1:1.25). We hold Front-End PDK packages only. A few questions before we freeze the floorplan.
>
> **1. Corner keep-out — now CLEAN on our side; we are asking only to confirm.**
> *(Updated 2026-08-11: we have since found and fixed the cause ourselves — see the note below this draft. Our four corners now measure **0 `CSR.R.1`** across all 162 corner rulechecks, down from 56. No pad-ring or floorplan change was needed. We are keeping the question only to confirm the requirement and the remedy you expect, not because we are blocked.)*
>
> Our pad ring places a `PCORNER_G` corner cell (135 × 135 µm) at each of the four die corners. We read in the mini@sic manual that each corner must leave an empty triangle so TSMC can fit the seal ring, and that `CSR.x.x` violations must be cleaned even when we do not supply a seal ring. The deck's `EMPTY_AREA` derivation (`INT CHIP_NOSR < 74 ABUT == 90`) suggests a 74 µm leg.
> - What exactly must be empty, and to what dimension?
> - Which remedy do you accept: (a) removing the corner cells and filling with `PFILLER*_G`, (b) a chamfer you apply at import, or (c) moving the pad ring inward at the corners?
> - If (a): the corner cells currently carry the pad-ring VDDIO/VSSIO/VDD/VSS bus continuity between adjacent sides. How should we maintain ring continuity and the ESD arrangement the manual describes without them?
>
> **2. Black-box import.** We intend to submit a GDS in which TSMC standard cells, IO drivers and bond pads are empty cell references, with only our routing, vias and eight compiled memory macros as real geometry. Please confirm you import the TSMC layouts on your side, and confirm this for our exact library set: `tcbn65lp` (220a), `tphn65lpgv2od3_sl` (210a), `tpbn65v` (200b).
>
> **3. Calibre deck switches.** Please send your exact `#DEFINE` set for `CLN65S_9M_6X1Z1U.26_2a`. Specifically:
> - Is `LP` defined? (It is commented out in the shipped deck and we are CLN65LP.)
> - Is `WLCSP_SEALRING` disabled for a wire-bond design? It is active in the shipped deck, and it changes the `SR_EDGE`/`CSR` derivation.
> - `FULL_CHIP`, `MIXED_SCHEME`, `CHECK_LOW_DENSITY`, `ChipWindowUsed`?
>
> **4. Dummy fill.** The mini@sic manual states that "the eptsmc team can do it for you", conditional on the design being "clean except for those violations that are solved by dummy filling". We would like to take that option. Please confirm, and clarify three points:
> - The manual says TSMC will waive `OD.DN.2` / `Mx.DN.1` / `Mx.DN.1.1` if **TSMC's auto-fill utility** is used. Does that waiver apply when eptsmc runs the fill on our behalf? Our worst-window M8 density is ~7.6 % against a 20 % floor at 75 × 75 µm, so this materially changes what we must fix.
> - We hold `T-N65-CL-DR-001-C3` (Dummy Metal) but our Calibre is **v2023.1_18.8**, below the **v2024.1_36.20** minimum the C3 package states. If we are to run fill ourselves, is an Innovus-generated `add_metal_fill` result acceptable in place of C3?
> - **FEOL fill we cannot do at all.** With standard cells as black boxes there is no OD or PO geometry in our GDS to fill around, so `DOD.R.1` / `DPO.R.1` are unreachable for us and only become meaningful after you import the cell layouts. Please confirm FEOL fill is on your side.
>
> One caution from our own experiment: when we ran metal fill locally it placed **755 `CSR.R.1` violations into the four corner keep-outs** (172 of them on AP alone), against **zero** in the same design unfilled. Whoever runs fill will need to exclude the corner triangles, so this interacts directly with question 1.
>
> **5. Tap cells / LUP.6.** We use `tcbn65lp` with endcap insertion (`DCAP4`) and no explicit well-tap insertion. Will `LUP.6` fire after you import the cell layouts, and what tap spacing do you require? We would rather fix this now than discover it in your acceptance report.
>
> **6. Antenna and bond-pad decks.** Do you run ANT (`CN65S_9M_ANT.26_2a`) and BND (`CN65_WIRE_BOND_9M_6X1Z1U.20a`) as part of acceptance, or are they ours to clean before submission?
>
> **7. LVS.** We have no CDL for standard cells, IO or bond pads (Front-End packages only). Please confirm black-box LVS is acceptable and send the application note. Related: some of our DRC waivers concern spacing between our power grid and a hard macro's `OBS` geometry, where the same-net argument would normally be evidenced by LVS. How would you like that documented?
>
> **8. Preliminary GDS.** We would like to send a preliminary stream early. What is the deadline, and what must it contain?
>
> **9. Seal ring.** Please confirm the seal ring is added by TSMC at no area cost, and give the expected seal-ring width and scribe so we can state the packaged die size.
>
> **10. Schedule.** Please confirm the September submission deadline and the cut-off for a revised stream after a preliminary submission.
>
> **11. RC extraction.** We have `/tsmc65pdk/65/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile` locally. Please confirm this is the correct dataset for the 9M 6X1Z1U stack, or send yours.
>
> **12. `PO.R.8` inside compiled memories — 691 results, and we believe they are vendor-owned.**
> Our DRC reports 691 `PO.R.8` (floating-gate) results. Every one is inside a sub-cell of a compiled memory macro, where the merged geometry is the vendor's own GDS — none are in our routing. We have verified they are **identical under both the 2012 (DRD 2.1b) and 2024 (DRD 2.6_2) deck generations**, so this is not a rule-revision artefact, and the design rule manual states `PO.R.8` "is only checked in whole chip, not in IP level" — i.e. it is deferred to full chip precisely because IP-level connectivity is incomplete, which is our situation exactly.
> The mini@sic manual allows waiving "known DRC violations mentioned in the release notes of the TSMC library of the cell in which the error occurs." **We do not have such a release note for these memory compilers.** Could you either supply the known-waivable-DRC list for our memory instances, or confirm that these 691 are expected and waived at merge? This is currently our largest single DRC category and we would rather not spend effort on violations we cannot fix.
>
> **13. Bond-pad deck — we think we are running the wrong generation.**
> Our BND deck is `CN65_WIRE_BOND_9M_6X1Z1U.20a`, which self-identifies as `T-N65-CL-DR-001-C1 VER 2.0a` against design-rule document VER 2.0 — six revisions behind the DRC deck we run (`.26_2a`, DRD 2.6_2). The **rule document** `T-000-CL-DR-017` v1.4 is present in our PDK, but its **Calibre command file (`-C1`)** is not — that string appears nowhere in our installation.
> Please either supply the `T-000-CL-DR-017-C1` command file, or confirm that `CN65_WIRE_BOND_9M_6X1Z1U.20a` is the deck you accept for a 70 µm staggered wire-bond ring. (For reference, we run it with `PITCH_70_STAGGER`; we instantiate `PAD70GU`/`PAD70NU` in two staggered rows.)
>
> Thank you,
> [name]

---

## RESOLVED 2026-08-11 — Q1 is no longer urgent, and the remedy was none of (a)/(b)/(c)

**The 56 corner violations were phantom geometry we were creating ourselves in stream-out, not the `PCORNER_G` cells' real layout.** Our GdsOutMap emitted LEF `LEFOBS` (routing *obstruction*) onto the real metal layers, so every corner cell's full-footprint blockage streamed as manufactured metal — four solid 135 × 135 µm plates on M1–M7, which is exactly what filled the 74 µm triangles.

Measured, same design, same deck, only the stream-out map differing:

| stream | `CSR.R.1` (162 rulechecks) |
|---|---|
| stock PDK map | **56** |
| stock map + project mini@sic header | **56** |
| **corrected map (`LEFOBS` dropped)** | **0** |
| stock map + metal fill | **755** ⚠ |

So the cost is a one-line map change, **not** the ~1.5 weeks a floorplan move would have taken, and not the pad-ring surgery of remedy (a). The paragraph below is retained for the record but its cost analysis no longer applies.

The 755 figure is the live risk now: metal fill drops geometry straight into the keep-outs. Fill must exclude the corner triangles — that is question 4.

## Why Q1 *was* urgent (superseded — retained for the record)

`PCORNER_G` is 135 µm; the keep-out appears to be 74 µm; 135 > 74, so the violation is arithmetic. The three remedies differ by an order of magnitude in cost: deleting the corner cells is a P&R-only change (~4 h, because the corner cells are **not in the gate netlist** — they are physical-only instances from `scripts/nanosoc_eth_chiplet_pads.io:23,47,78,101`), whereas moving the pad ring inward moves the core box and forces a full re-run including synthesis (~1.5 weeks). We cannot choose without their answer, and any full run we do before the answer is provisional.

**MEASURED 2026-08-09 — we CAN self-check it, and it fires.** First Calibre DRC run in this project's history (deck `CLN65S_9M_6X1Z1U.26_2a` with `#DEFINE LP` added, 1,955 rulechecks, 470 s):

```
CSR.R.1:M1i / M1_real ... M7i / M7_real     4 results each  (one per corner)
CSR.R.1 on M8, M9, AP                       0
CSR.R.1 on OD/PO/NW/PP/NP/DNW/CO (17 rules) 0     <- silent: black-box cells
```

The four violating polygons are exactly the corner triangles, confirming the **74 µm** leg:

```
(0,0)-(74,0)-(0,74)                (1526,0)-(1600,0)-(1600,74)
(0,1926)-(74,2000)-(0,2000)        (1526,2000)-(1600,1926)-(1600,2000)
```

The rule text is `EMPTY_AREA AND M5_real`, and the violation covers the **whole** triangle — i.e. it is the `PCORNER_G` cells' own M1–M7 abstract geometry, which our stream does carry (IO cells stream on GDS layers 31–37). M8/M9/AP are clean because the corner cells have no shapes on those layers, and our own M8/M9 rings start at x=191, well inside.

**Two consequences.** First, the metal half of this is self-checkable today, so we can iterate locally rather than waiting for an acceptance report. Second, it cannot be fixed by routing differently — the offending geometry *is* the corner cell, so the remedy is necessarily (a) remove them or (c) move the ring. That is why Q1 needs an answer, and why we would rather not guess.
