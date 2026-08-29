# imec round-trip — SEND TODAY (Sat 29 August)

    status   DRAFT for review. NOT SENT.
    basis    Final Report on the rc2 merged + dummy + seal-ring stream,
             28 Aug 14u40, md5 6d64126c80b86497c015774cb71c3bb4 — imec's own
             report names that md5, that byte count and that write time, so it
             graded exactly what we published.
    replaces docs/tapeout/59-imec-round-trip-2026-08-27.md, which was written
             against the 25 Aug run on the PINFIX stream and was never sent.
             Two of its five asks are now answered by imec's own 28 Aug results
             and are dropped here. Do not send both.
    scope    THREE asks. No GDS re-spin is required for any of them.
    deadline Europractice submission 1 September. Observed imec turnaround on
             this project is 9–19 hours, so there is room for one exchange and
             possibly two — if this goes today.

---

## The 28 August run is clean, and thank you

`PO.R.8` does not appear in the report at all. Our local stream reports 691, and
we had said all along we believed that to be a LEF-abstract artefact rather than
real polysilicon; your library replacement cleared it completely. That was the
last outstanding blocker on our side and it is now closed.

More importantly, **the report contains no design-rule violations of any kind.**
No `G.*`, no `M*.S.*`, no `VIA*.R.*`. Padring: 0 errors, 0 warnings.

Every result in the report falls into one of four groups, and we believe none is
actionable by us:

| result | n | our reading |
|---|---:|---|
| `PM.W.1` | 893 | seal ring — 867 in `nanosoc_eth_chiplet_pads_dummy_WithSealRing`, 26 in `CORNER_B`, a cell we do not instantiate |
| `AP.S.4` | 46 | die/seal-ring interface, from pad masters you substitute at merge |
| `IM.FLOAT.AP` | 87 | the chip logo — intentionally unconnected AP artwork |
| `IM.POLYIMIDE.1` | 82 | one per bond pad; this part is wire-bond, not bumped |
| `IM.LOGO.R.1:WARN` | 1 | logo recognition layer deliberately omitted; your rule text says it is not mandatory |
| `RM.WARN.2`, `ESD.21g/22g/23g`, `DRM.R.1` | 114 / 2 / 28 / 468 / 1 | all inside TSMC's own `SBC331_*` bondpad cells |
| `CB.W.1/2:P80_ST` | 2 / 2 | **the wrong pitch switch — see ask 1** |

Against the 26 August run on rc1, every line is identical except `IM.FLOAT.AP`,
which improved 91 → 87.

---

## 1. Please re-run the wire-bond checks with `PITCH_60_STAGGER`

We raised this on 27 August and the mail was never sent, so the 28 August run
used `PITCH_80_STAGGER` again — and the four `CB.W.*` results are entirely a
consequence of that switch.

Measured from **your own ERC pad table**: outer row at x = 56, inner row at
x = 158, pads alternating every **67 µm** (same-row spacing 134 µm). On the
wire-bond deck's own switch definitions — "IO cell (≥ 70 µm pitch)" versus
"(≥ 60 µm pitch)" — a 67 µm ring selects `PITCH_60_STAGGER`, which is also the
deck's shipped default.

| switch | CB width needs | CB length needs | our 66 × 58 opening |
|---|---|---|---|
| `PITCH_80_STAGGER` (what ran, twice) | 65 | 75 | **both fail** |
| `PITCH_70_STAGGER` | 58 | 66 | passes, zero margin |
| `PITCH_60_STAGGER` (deck-correct) | 53 | 66 | passes, 5 µm margin |

**The four results are not the point.** The point is that the P60 rule family
has **never been run against this design** — every run so far has been P80 — so
we have no clean result for the switch that actually applies. We would rather
find that out now than on the final stream.

An earlier message of ours stated our parts are 70 µm staggered. That was our
error and this supersedes it.

## 2. ERC has never executed on this design, across seven submissions

Every run returns the same 13-line bail:

    [ Error ] - No labels found in topcell.  At least power/ground labels are required.

The topcell it names is `nanosoc_eth_chiplet_pads_dummy_WithSealRing` — **your**
merged wrapper, not ours. So we cannot tell from here whether the labels are
missing because our stream does not carry enough of them, or because ours do not
propagate into the wrapper your merge creates.

**Ask:** please tell us which it is, and what you need from us. Specifically:
should we add power/ground text labels on our topcell, and if so on which layer
and with what naming, so that they survive into the merged topcell your ERC
reads? We can re-stream with labels quickly if that is the answer — it is a
text-layer change and does not touch geometry.

This matters because ERC is the one check in the set that has produced no
information at all on any submission, and we would rather not tape out with it
having never run.

## 3. Please run PadShorts on the candidate

The only pad-short data we hold is dated 24 August and describes a stream that
is now three candidates old. Nothing we would ship has pad-short coverage.

**Ask:** please run the pad-short set on the final stream before acceptance, or
confirm it will run as part of the 1 September acceptance.

---

## Dropped from the 27 August draft, because the 28 August run answered them

- **"Which merge and library configuration will the FINAL run use?"** — the 26
  and 28 August runs used identical configuration and produced identical results
  on every rule bar the logo. We no longer need to ask.
- **"Please run ERC / LVS / PadShorts on the candidate itself"** — split. ERC and
  PadShorts are now asks 2 and 3 with specific questions attached. LVS is
  dropped entirely: your programme documentation is explicit that eptsmc runs
  DRC, ANT and BND only and that LVS is the customer's responsibility. We run it
  our side and it is clean on the discrepancy list we grade.

## Not asked, deliberately

The 27 August draft asked whether TSMC supplies OCV or AOCV derating guidance
for this node. We have since searched the kit exhaustively — 865 `.lib` files,
the ARM physical IP tree and the memory compilers — and found none, while the
28 nm kit on the same site ships it. We have recorded our flat derate as a
declared engineering assumption with a stated basis, and we are not going to
hold up a submission on it. If the answer is easy to hand, we would still
welcome it, but it is not a blocker and we are not asking you to chase it.

---

## Notes for us, not for the mail

- Counts are `hierarchical (flat)`; the 1000 cap applies to the FIRST column.
  `PM.W.1` at 893 of 1000 is the closest approach to truncation and is worth
  watching on the final run.
- imec's antenna has been zero on all seven runs, **including** the 18 August
  stream that carried 78,698 DRC results. Their antenna check has never
  discriminated anything on this design, so a zero there is weak evidence.
- Our own foundry-deck antenna run on the candidate bytes is also zero, over a
  demonstrably non-empty population — but only 9 cells in the design carry gate
  area and all are memory-macro internals, so it cannot see a net that routes a
  long antenna to a standard-cell input. Report it as "no violation found within
  a stated scope", never as "antenna is clean".
- If the candidate changes between now and submission the geometry does not,
  and this is now measured across all three: rc2, rc3fix and rc4 are
  DRC-IDENTICAL. The setup ECO that was "in flight" when this was drafted has
  landed as rc4 (md5 6b0833c4216bdb683ed2427cd0deba75, 29 Aug), and its Calibre
  summary matches rc3fix's line for line -- same 1,926 rulechecks executed, same
  737 results, same four tiers. The streams are NOT the same bytes: flat
  original-layer geometries read 178,282,662 against rc3fix's 178,282,660, so
  the three resized cells really are in there. Everything in this mail applies
  to any of the three.
  WHICH ONE WE SUBMIT is a separate decision: rc4 is the only candidate with no
  timing waiver (setup +0.015 / hold +0.003, FEP 0 at both), and it is the one
  to name if imec asks for a final md5.
