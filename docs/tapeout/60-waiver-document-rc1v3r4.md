# Waiver document — nanoSoC Ethernet Chiplet, submission candidate rc1v3r4

    status      DRAFT for signature
    project     TMWB45_10042, imec mini@sic via Europractice
    node        TSMC 65 nm LOGIC-MS-RF G-LP-ULP, 9M_6X1Z1U, wire bond, 1P2V/2P5V
    die         1600 x 2000 um, 3.200 sqmm

    stream      ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260826_rc1v3r4.gds
    md5         acd2b93e1ac7ac2c672f236d50b3444c
    size        302,688,050 bytes
    topcell     nanosoc_eth_chiplet_pads

    basis       imec CheckAll+ 7.02, run 26 Aug 2026 17u29, on the merged
                dummy + seal-ring database built FROM THE STREAM ABOVE.
                imec's report records our md5 verbatim, so for the first time
                in this project a foundry-side result is bound to the bytes we
                intend to ship rather than to an ancestor of them.

    merged DB   1640 x 2040 um, 359,321,600 bytes, md5 15c38bd431a39db6019d0a777aba78bf
                (imec added the seal ring and a dummy filling pattern covering
                the entire chip area except dummy block/exclude.)

---

## 0. How to read this document

Every entry states the rule, the count as imec reports it, our position, and the
**measurement** behind that position. Where a count is quoted as `N (M)`, N is
the hierarchical count and M the placement-expanded count; imec's own
`How_to_read_the_final_report` defines the format, and the 1000-result cap
applies to N only.

Nothing in this document asks imec to change a number. Sections 1 and 2 are
findings we are asking to be accepted as-is. Section 3 lists what this run did
**not** measure, which is the part that still needs closing before signature.

---

## 1. Findings inside vendor IP we do not author

The main DRC deck reports **five rulechecks, 612 results**. Four of the five,
totalling **611 results**, are wholly contained in TSMC ESD/IO library cells
that arrive in the merged database through imec's own library replacement. We
do not author this geometry, we cannot edit it, and replacing it is precisely
what the merge step does.

| rule | count | resident cell | what the rule tests |
|---|---:|---|---|
| `ESD.23g` | 468 (5616) | `SBC331_POSTVDD2POC_G` | poly-to-contact space on the source side |
| `ESD.22g` | 28 (1344) | `SBC331_POSTP` | RPO width, drain side, PMOS |
| `ESD.21g` | 2 (144) | `SBC331_MOS_ESDN01_VDD2_RPO_095` | RPO width, drain side, NMOS |
| `RM.WARN.2` | 100 (600) | `SBC331_RES_04X22D11X47` | contact overlap on resistor head |
| `RM.WARN.2` | 14 (168) | `SBC331_POSTVDD2POC_G` | as above |

**Measured, not assumed.** The by-cell statistics in imec's own report attribute
every one of these results to a named `SBC331_*` cell. **Zero main-DRC results
are attributed to our top cell** other than the single `DRM.R.1` entry below.

**Ask:** accept as vendor-IP-resident, consistent with the library set imec
substitutes at merge.

### `DRM.R.1` — 1 result, and it is not a violation

The rule's own text: *"DRM.R.1 is a warning message to remind the users to check
the related DRMs."* It is a reminder to read the design rule manual, not a
geometry finding. Accepted as informational.

---

## 2. Findings that are ours, and why each is correct as it stands

### 2.1 `IM.FLOAT.AP` — 91 results. This is the chip logo.

Rule text: *"IMEC WARNING: No net connected between AP and top metal. Possibly
it's a logo."* It is a logo.

**Measured on this stream, with a control.** We parsed all 91 error polygons out
of imec's own RVE results file and tested each bounding box against the logo
cell bbox (x 320.0–1047.8, y 859.9–1180.1 um):

    rc1v3r4   91 polygons parsed, 91 inside the logo bbox, 0 outside
    pinfix    85 polygons parsed, 85 inside the logo bbox, 0 outside   [control]

Not one result falls outside the artwork, on either stream.

**On the increase from 85 to 91.** The two streams are independent routes. The
rule fires on AP with no connection to top metal, so the count depends on how
much M9 happens to sit beneath the artwork. A different route places different
top metal under the logo and six more AP shapes are left unconnected. The logo
artwork itself is unchanged between the two streams. This is an interaction
between fixed artwork and a re-route, not new floating metal.

**Ask:** accept as intentional unconnected AP artwork.

### 2.2 `IM.LOGO.R.1:WARN` — 1 result. Deliberate, and the rule says it is optional.

Rule text: *"Missing Logo layer. Make sure chip has visible logo top metal or AP.
Logo recognition layer is not a must have."*

A visible AP logo is present — it is what generates the 91 results above. The
logo **recognition** layer is deliberately omitted. We are not re-adding it: on
a placed-and-routed die it has no legal placement, and restoring the marker
takes two capped rulechecks back over 25,000 results with no legal position
available.

**Ask:** accept. The rule declares itself non-mandatory.

### 2.3 `IM.POLYIMIDE.1` — 82 results, one per bond pad. Conditional on bumping.

Rule text: *"Polyimide not found on chip core passivation openings. **If bumping
is required** ... polyimide may be a must have."*

This part is **wire bond, no bumping**, as declared in the BEOL option and
confirmed by imec's own run configuration (`bnd BEOL_option Wirebond`). The
rule's precondition does not hold.

**Ask:** accept as not applicable to a wire-bond part.

---

## 3. Seal-ring-side findings — imec's geometry, not ours

`PM.W.1` = 893 (971) and `AP.S.4` = 46 (46). Both arise from the seal ring and
polyimide that imec adds after we ship, and neither is actionable by us.

Our reasoning, so it can be checked rather than taken:

- **All 893 `PM.W.1` results lie wholly inside the 20 um perimeter band added
  during merge.** Measured on THIS stream by parsing every error polygon out of
  imec's own RVE file and computing its distance to the merged-die edge:
  893 of 893 within the band, 100% within 30 um of the edge, and **884 of the
  893 have one bbox dimension of exactly 20.000 um** — the band width itself.
  **26 are in `CORNER_B`, a cell that does not exist in our GDS and that we
  never instantiate** (imec's own by-cell table attributes them there).
- The rule's own seal-ring exclusion is derived from holes in the CB layer. Our
  CB openings are simple octagons with no holes, so that exclusion evaluates
  empty and the rule fires across the ring itself.
- **`PM.W.1` has now read 889 / 919 / 903 / 893 / 893 / 893 across six runs on
  six materially different streams** — including one that carried no CB at all.
  A count that barely moves across six different designs is not measuring our
  design.
- **All 46 `AP.S.4` results sit at exactly 20.000 um from the merged-die edge** —
  measured, min and max both 20.000 — which is precisely the die/seal-ring
  interface, i.e. our original die boundary inside imec's enlarged frame. Not
  one is anywhere else. The AP side comes from the pad masters imec substitutes
  at merge; the PM side is imec's seal ring. Neither side is geometry we
  authored.

**We cannot check any of this locally**: our stream contains no PM, CB, CB2 or
UBM geometry at all, so every local result on these rules is a zero produced by
absent layers rather than by compliance.

**Ask:** written confirmation that these are expected for the seal-ring flow.
Without it, roughly 939 results stand unexplained against our design.

---

## 4. `CB.W.1` / `CB.W.2` — 2 each. Run at the wrong pad pitch.

Both fired under `#DEFINE PITCH_80_STAGGER`. **Our ring is 67 um.**

Measured from imec's own ERC pad table: outer row at x = 56, inner row at
x = 158, pads alternating every **67 um** (same-row spacing 134 um). On the
wire-bond deck's own switch definitions — "IO cell (>= 70 um pitch)" versus
"(>= 60 um pitch)" — a 67 um ring selects **`PITCH_60_STAGGER`**, which is also
the deck's shipped default.

| switch | CB width needs | CB length needs | our 66 x 58 opening |
|---|---|---|---|
| `PITCH_80_STAGGER` (what ran, all six runs) | 65 | 75 | **both fail** |
| `PITCH_70_STAGGER` | 58 | 66 | passes, zero margin |
| `PITCH_60_STAGGER` (deck-correct) | 53 | 66 | passes, 5 um margin |

The four results are not the point. **The P60 rule family has never been run
against this design** — every run so far has been P80 — so we hold no clean
result for the switch that actually applies.

**Ask:** re-run the wire-bond checks with `PITCH_60_STAGGER`. This is the one
item in this document that could still change a number we sign off on.

---

## 5. Scope of this deliverable, and the one check still outstanding

**LVS is not an imec check.** It is not in scope for the CheckAll+ archive and
its absence here is correct, not a gap. LVS is ours and we hold it: the
`lvs-missing-connection` gate PASSES on this candidate, with one accepted
known-bad (`lvs-verdict-incorrect`) recorded against the verdict parser rather
than against the layout.

**ERC and pad shorts arrive as a SEPARATE deliverable**, not in this archive.
The 13-line `erc/` bail in the archive — *"No labels found in topcell"* — is an
artefact of that deck running against imec's wrapper cell
`nanosoc_eth_chiplet_pads_dummy_WithSealRing`, which carries no labels, while
ours sit one level down. It is expected and it is **not a finding**. The real
results come in the `PadShorts` package.

### The one thing genuinely outstanding

**The ERC / pad-short package we hold is bound to a superseded stream.**

    held      PadShorts/, dated 24 Aug 2026
    layout    temporary_erc_nanosoc_eth_chiplet_pads_dummy_WithSealRing_24Aug26.gds.gz
    lineage   DRYRUN_20260823_rzG  -- TWO streams behind this candidate

Its findings, for reference only and **not carried into this waiver** because
they do not describe these bytes:

| result | count | standing position |
|---|---:|---|
| floating pads | **0** | *"NO FLOATING PAD DETECTED"* |
| shorted pads | listed | domain-pure — every pair sits on one of the four supply buses, which is by construction for a multi-pad supply |
| `mnpg` | 10 | MOS connected to both power and ground — ESD clamp structures |
| `mppg` | 28 | as above |

**Ask:** run the ERC / pad-short package on this candidate
(md5 `acd2b93e1ac7ac2c672f236d50b3444c`), or confirm it will run on the final
1 September stream before acceptance.

### `PO.R.8` post-merge

Not evaluable by us: reads 0 here because imec substitutes real standard-cell
geometry at merge, while our stream carries LEF abstracts. Only a foundry run
can close it, and **this run does** — it reports 0.

---

## 6. What this run DID clear, and it is worth stating

Recorded because a waiver document that lists only problems misrepresents the
state of the design.

| check | result |
|---|---|
| **Antenna** | **0 results.** 17-minute run, by-cell statistics block empty. |
| **Padring** | **0 errors, 0 warnings.** Cell orientations correct; bondpads correctly placed on all four sides; 1 power domain, digital, 0 power-check errors; no PRCUT cells. |
| **Metal density** | **Passes.** 161 per-layer density datasets (OD, PO, M1–M9, AP, IND, CUPVIAT) and **no `DN.*` rulecheck reported** — on the filled die, with imec's dummy fill applied. |
| **`VIA3.R.4:M4`** | **Cleared, foundry-confirmed.** Present as 1 result on the previous stream, absent here. |
| **Main DRC in our own geometry** | **0 results**, `DRM.R.1` reminder excepted. |

### The A/B that makes the above meaningful

The 25 Aug and 26 Aug runs used **byte-identical configuration** — same deck
versions, same switches, same three replacement libraries. We diffed the full
switch table and it is identical. So the only differences between the two result
sets are attributable to the streams:

    pinfix (3215cbe1...)  ->  rc1v3r4 (acd2b93e...)

    VIA3.R.4:M4    1  ->  0        our post-route ECO, confirmed foundry-side
    IM.FLOAT.AP   85  -> 91        logo, verified inside bbox on both

**Two changes across the entire report.** Every other rulecheck is identical,
count for count.

---

## 7. Signature

This document is a statement of position on findings in a specific stream. It is
valid only for md5 `acd2b93e1ac7ac2c672f236d50b3444c`; any re-stream invalidates
it and it must be re-issued.

| | |
|---|---|
| Prepared by | _______________________ |
| Date | _______________________ |
| Design authority | _______________________ |
| Date | _______________________ |

**Sections 1–4 and 6 are complete, measured on this stream, and signable now.**

One item is outstanding and it is not a finding against the design: the ERC /
pad-short package has not yet been run on this candidate, only on a stream two
revisions behind. A waiver cannot waive a check that has not executed on the
bytes being shipped, so this document is issued with that stated rather than
withheld — sign sections 1–4 and 6 on their own terms, and close section 5 when
the package arrives.

If the ERC / pad-short run on this candidate returns what the rzG run returned —
zero floating pads and domain-pure supply shorts — no change to sections 1–4 is
expected and this document stands as issued.
