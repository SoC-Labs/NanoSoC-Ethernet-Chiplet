# Parity with rc4, from the flow

    run      vt9par-20260916 — `make eco` on vt9b-20260916 (fresh place → cts → route at high extraction)
    measured 2026-09-16/17, every number from a manifest, a gate file or a Calibre/Tempus report
    verdict  DRC identical to the shipped stream; setup, hold and max_transition better; LVS unchanged

## 1. Against rc4

| | rc4 (shipped, imec-graded) | vt9par (this flow) |
|---|---|---|
| Calibre results / non-zero rulechecks | 737 / **32** | 737 / **32** |
| design-caused DRC results | 0 | 0 |
| in-flow `check_drc` | 0 | 0 |
| foundry antenna | imec: 0 | **0**, 721 rulechecks (714 foundry + 7 controls) |
| LEC | pass | 0 non-equivalent, 0 aborted, 0 not-compared |
| setup WNS / endpoints (Tempus, parasitics) | +0.015 / 0 | **+0.070 / 0** |
| hold WNS / endpoints | +0.003 / 0 | **+0.007 / 0** |
| max_transition nets | 190 | **71** |
| placement legality | not measured | 82 → 82, 0 overlaps |
| LVS | INCORRECT, pad-ring class | same class |
| signoff STA gate | (no gate existed) | **PASS** |

Only two rulechecks differ from rc4 at all: M3.DN.1 2 → 1 and M5.DN.1 5 → 6,
both density windows the foundry owns, and they cancel in the count.

The STA is the first on this flow's own output with extraction evidence the
gate requires: standalone Quantus, effort read back as `signoff`, three SPEFs
of 368 MB, 249,507 nets, fallback counts IMPEXT-3518 / EXTSNZ-127 /
IMPEXT-5016 all zero. Two report-only lines stand, by policy: the async
clock-group cut leaves 5,113 untested checks per side, printed on every run
rather than hidden under a ratchet (constraints.sdc:706, docs/tapeout/75).

LVS is INCORRECT in the same pad-ring class as every stream of this design
including the shipped one: 52 ports matched, the same "Layout Extra Pins"
shape, net counts tracking the netlist. Three of its per-pin lines differ
from vt7eco's because this is a different netlist, not a different class.

## 2. What made the difference

Four flow changes, each measured on its own before being combined:

| change | measured alone |
|---|---|
| marker-driven PG repair in the ECO stage (toolkit) | 36 → 35 rulechecks; only VIA3.R.4:M4 moved (doc 73) |
| via-fill pass gated on a `check_drc` delta (place) | 36 → 33; in-flow check_drc 3 → 0 (doc 74) |
| `ROUTE_EXTRACT_EFFORT=high` + `ECO_OPT_ARGS="-setup -drv -hold"` | setup closed in-flow, signoff agrees to 6 ps (doc 72) |
| the two together, on a fresh lineage | **33 − 1 = 32**, parity |

## 3. A conclusion of mine that this run refutes

Doc 72 §8 and the memory said the two residual fast-hot hold endpoints were
floorplan, not flow — that there was no room at those sites, since rc4's own
holdfix settings applied as a second pass placed one buffer and reported
"15 net(s): no legal location".

vt9par closes hold at +0.007 / 0 endpoints on the same floorplan at the same
utilisation. The endpoints belonged to the vt3pg-derived lineage, not to the
die: route-stage hold reads vt3pg CTS +0.005 / 0 → vt7high route −0.036 / 3,
against vt9b CTS +0.010 / 0 → vt9b route +0.009 / 0, both routed at `high`
with the same knobs. More than one variable separates those two runs — a
fresh place and clock tree, and the via gate — so the cause is not isolated.
What is settled is that "there is no room" was wrong, disproved by a run that
found it.

The vt8hold finding stands unchanged: withholding the weakest hold buffers
trades max_transition for unfixable hold (261 → 69 nets, hold 1 → 84
endpoints), and utilisation remains the lever to plan a NEW die around. What
does not stand is calling a residue a floorplan limit before trying a fresh
lineage.

## 4. What is still open

- **LVS pad-ring class.** Unchanged since rc4 and never closed. A decision:
  write the position down as the shipped state, or fix the labelling.
- **The async clock-group exposure**, 5,113 untested checks per side. Printed
  on every run, ceiling 0, nobody's task yet.
- **A fresh synthesis.** This lineage reuses vt1-20260902. The next full
  chain should re-synthesise, which also clears the SDC staleness gate that
  the comment amendment in 6f1370d now trips.
