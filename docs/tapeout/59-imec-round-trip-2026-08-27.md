# imec round-trip — send by Wed 27 August

    status   DRAFT for review. Not sent.
    basis    Final Report on the PINFIX merged + dummy + seal-ring stream,
             25 Aug 14u10, on our submission candidate md5 3215cbe1...
             (re-anchored 25 Aug: the rzG stream this was first written against
             is superseded and carries a functional defect -- do not ask imec to
             act on it.)
    scope    four asks. NO GDS re-spin is required for any of them.

The wire-bond and custom-DRC results report six rule families we had not
classified. All six have now been triaged. **None requires a geometry change on
our side.** Four are imec-side, two need a sentence in the submission letter.

The 25 August run also closed the outstanding blocker: `PO.R.8` went 14 -> 0 on
the merged database, and eight other rules with it. Thank you -- that settles it.
The asks below are what remains.

Send to the tape-out submission mailbox. This supersedes Q7 of the 19 August set,
which contained an error of ours — see §1.

---

## 1. We gave you the wrong pad pitch. The switch should be P60, not P80.

Our 19 August Q7 stated our parts are **70 µm staggered**. That was wrong, and it
is our error, not yours.

Measured from **your own ERC pad table** in the 24 August archive: outer row at
x = 56, inner row at x = 158, pads alternating every **67 µm** (same-row spacing
134 µm). On the wire-bond deck's own switch definitions — "IO cell (≥ 70 µm
pitch)" versus "(≥ 60 µm pitch)" — a 67 µm ring selects **`PITCH_60_STAGGER`**,
which is also the deck's shipped default.

The 24 August run used `PITCH_80_STAGGER`. That produces the two `CB.W.*`
results, and it is the only reason they appear:

| switch | CB width needs | CB length needs | our 66 × 58 opening |
|---|---|---|---|
| `PITCH_80_STAGGER` (what ran) | 65 | 75 | **both fail** |
| `PITCH_70_STAGGER` | 58 | 66 | passes, zero margin |
| `PITCH_60_STAGGER` (deck-correct) | 53 | 66 | passes, 5 µm margin |

**Ask:** please re-run the wire-bond checks with `PITCH_60_STAGGER`.

The four results are not the point. The point is that **the P60 rule family has
never been run against this design** — every run so far has been P80, so we have
no clean result for the switch that actually applies. We would rather find that
out now than on the final stream.

## 2. Please confirm in writing that `PM.W.1` and `AP.S.4` are seal-ring-side.

`PM.W.1` reports **893** results and `AP.S.4` reports **46**. We believe both are
inherent to the seal ring and polyimide *you* add after we ship, and that neither
is actionable by us. Our reasoning, so you can check it rather than take it:

- **884 of the 893 `PM.W.1` results lie wholly inside the 20 µm perimeter band
  added during your merge**, and all 893 are within 30 µm of the die edge. Every
  result bbox has one dimension of exactly 20.000 µm — the band width. 26 of them
  are in `CORNER_B`, a cell that does not exist in our GDS and that we never
  instantiate.
- The rule's own seal-ring exclusion is derived from holes in the CB layer. Our CB
  openings are simple octagons with no holes, so that exclusion evaluates empty
  and the rule fires across the ring itself.
- `PM.W.1` reads 889 / 919 / 903 / 893 / 893 across your five runs (17, 18, 21,
  24, 25 August) on five materially different streams — including the 17 August
  one, where our stream carried no CB at all. A count that barely moves across
  five different designs is not measuring our design. The 24th and 25th are
  **bit-identical** on every wire-bond rule, on a pair of streams where nine
  other rulechecks went from non-zero to zero.
- All 46 `AP.S.4` results sit exactly at the die/seal-ring interface, each 3.5 µm
  deep and 0.315 µm from a bond-pad opening. The AP side comes from the pad
  masters *you* substitute at merge; the PM side is your seal ring. Neither side
  is geometry we authored.

**Ask:** a line in the acceptance report, or in reply to this mail, confirming
these are expected for your seal-ring flow. Without it, roughly 939 results stand
unexplained against our design.

We cannot check any of this locally: our stream contains no PM, CB, CB2 or UBM
geometry at all, so every local result on these rules is a zero produced by
absent layers rather than by compliance. Your merged database is the only place
these rules can be evaluated.

## 3. Which merge and library configuration will the FINAL run use?

The pad-master replacement source and the seal-ring script between them determine
most of the numbers above. The 24 and 25 August runs used identical configuration
— same three replacement libraries, identical IP set — so this is a forward-looking
question, not a complaint.

**Ask:** please confirm the 1 September run will use that same configuration, and
tell us if anything changes.

## 4. Please run ERC / LVS / PadShorts on the candidate itself.

The 25 August archive contains no LVS section, and its `erc/` report is the
13-line bail ("No labels found in topcell"). The only pad-short and floating-pad
data we hold is from the **24 August rzG** run -- a stream that is now superseded.

So the stream we intend to ship has, at present, **no ERC and no LVS result of its
own**. The DRC, antenna and padring checks all ran on it and all pass; those three
are not in question.

**Ask:** please run the pad-short / ERC / LVS set on the pinfix candidate, or
confirm it will run on the final 1 September stream before acceptance.

---

## Answered on our side, no action needed from imec

Stated here so the acceptance report is complete. These will be repeated in the
submission letter.

| result | n | our position |
|---|---:|---|
| `IM.FLOAT.AP` | 85 | **This is the chip logo**, at x 320.0–1047.8, y 859.9–1180.1, which matches the logo cell bbox exactly. Intentionally unconnected AP artwork. Your own ERC agrees the pads are fine — it reports no floating pad. Your rule text anticipates this: "Possibly it's a logo." |
| `IM.POLYIMIDE.1` | 82 | One per bond pad. This part is **wire bond, no bumping**, as declared in the BEOL option. The rule is conditional on bumping. |
| `IM.LOGO.R.1:WARN` | 1 | The logo *recognition* layer is deliberately omitted; your rule text says it is not mandatory. A visible AP logo is present — it is what generates the 85 results above. We are **not** re-adding the recognition layer: on a placed-and-routed die it has no legal placement and it resurrects two capped rulechecks. |

---

## Notes for us, not for the mail

- Counts are **`hierarchical (flat)`** — imec's own `How_to_read_the_final_report`
  PDF says so. **The 1000 cap applies to the FIRST column**, not the second;
  column 2 is the absolute placement-expanded count and is uncapped (`ESD.23g`
  = 468 (5616) proves it). Cross-checked: the DevCheck parenthesised column sums
  to exactly the report's own device total. So the truncation-risk number is
  `PM.W.1` at **893 of 1000 (89%)** — nothing is capped, but that is the closest
  approach and it is worth watching on the final run.
- All six findings **transfer unchanged** to the pinfix candidate — confirmed by
  layer census against both streams, not assumed. The only deltas between the two
  streams are routing layers and cell names.
- Our local wire-bond deck resolves to a 2009 rule set, a different document from
  the one imec runs. A local run today is not evaluating imec's rule at all — its
  `PM.W.1` has a different threshold and a companion rule that theirs does not.
  Re-point it at the version in the PDK's own utility archive before quoting any
  local wire-bond result. Hygiene, not a blocker.
- Corrections this triage forced on our own docs: `AP.S.4` was recorded as
  possibly ours to fix — it is not; the 16 earlier `AP.W.1`/`AP.S.1` results were
  the **logo seam**, already fixed, not the tidelink SRAM as speculated; and the
  P70-vs-P80 comparison in the wire-bond doc is stale because it ran on a stream
  with no CB.
