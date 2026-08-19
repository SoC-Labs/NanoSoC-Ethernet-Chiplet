# Request: TSMC 65 nm Back-End (BE) packages


> **STATUS — the request stands, but its 2026-08-06 framing is wrong on one point.**
> "The single blocker … on running LVS at all" is false: Calibre nmLVS and `v2lvs`
> are installed here (`/eda/mentor/calibre/bin/`) and **black-box LVS runs today** —
> see `../asic/LVS_FINDINGS.md`, which records measured runs, and
> `../asic/DRC_WAIVER_INVENTORY.md` §7, which supersedes the status section below.
> What the `_BE` packages genuinely unblock is **full-chip** LVS and manufacturing-layer
> DRC, because no standard-cell / IO / bond-pad GDS or CDL exists on this system.
> Everything from §1 onward (what to ask for, and why) is unchanged.

**Status 2026-08-06: this is the single blocker on delivering a manufacturable
GDS and on running LVS at all. No amount of local engineering substitutes for
it. Everything else needed is already on this system.**

Route this to whoever holds the university / Europractice TSMC 65 nm licence.
It is a **licence-scope question, not a technical one** — the packages exist,
we are simply not licensed for the views that contain layout and netlists.

---

## 1. What to ask for

We currently have the **Front End (`_FE`)** packages of every library. We need
the **Back End (`_BE`)** counterpart of each — same vendor, same process, same
revision, so this is an extension of an existing licence rather than a new one.

### Mandatory for `nanosoc_eth_chiplet_pads`

| Package | Supplies | Cells it unblocks |
|---|---|---|
| **`tcbn65lp_<rev>_BE`** | standard-cell GDS + CDL | the 9-track SVT core (`config.tcl` `BASE_LIB = tcbn65lpwc.lib`) |
| **`tphn65lpgv2od3_sl_<rev>_BE`** | 2.5 V staggered IO driver GDS + CDL | `PDDW16DGZ_G` ×36, `PVSS2DGZ_G` ×12, `PDDW04DGZ_G` ×9, `PVDD2DGZ_G` ×8, `PVDD1DGZ_G` ×6, `PVSS1DGZ_G` ×4, `PVDD2POC_G` ×4, `PDUW16DGZ_G` ×2, `PDUW08DGZ_G` ×1, `PCORNER_G`, `PFILLER{1,5,10,20}_G` |
| **`tpbn65v_<rev>_BE`** | bond-pad GDS + CDL | `PAD70GU` ×42, `PAD70NU` ×40 |

### Worth adding to the same request (no marginal effort, avoids a second round)

`tcbn65lphvt_<rev>_BE`, `tcbn65lplvt_<rev>_BE`, `tcbn65lpcg_<rev>_BE`,
`tcbn65lpcghvt_<rev>_BE`, `tcbn65lpcglvt_<rev>_BE`.

### Phrasing that gets the right thing

The FE packs we hold shipped the view tarballs
`_apf _sef _vcn _ctc _ibs _mdt _nldm _rln _vit _vlg _ecsm _ccs _pdb _doc`.

> **We need the `_gds` / `_gds2` (layout) and `_cdl` (LVS source netlist) views.
> TSMC distributes these only in the `*_BE` packages.**

---

## 2. Why — the evidence

`write_stream` completes and produces a 435 MB GDS that *looks* finished. It is
not. The route log records:

```
IMPOGDS-217: Master cell: FILL1 not found in merged file(s) and will therefore
             not be included in the resulting write_stream file
IMPOGDS-218: Number of master cells not found after merging: 424
```

`4_pnr_route.tcl` merges only `$gds_merge_list`, which `config.tcl` defines as
the **eight memory macros**. Everything else is streamed from its LEF abstract.

**The failure mode is worse than "incomplete".** Because `write_stream` ran with
`-output_macros`, each of the 424 missing masters got its LEF pin and
obstruction shapes — so every cell name resolves and nothing errors:

| cell | what is in the GDS | what should be there |
|---|---|---|
| `SDFCNQD1` | 94 polygons, layer `(31,0)` M1 only | full FEOL: NW, OD, PO, CO, M1… |
| `INVD1` | 8 polygons, M1 only | ditto |
| `FILL1` | 2 polygons, M1 only | ditto |
| `PAD70GU` | 13 polygons, AP/RDL only | full pad stack |
| `rf_32k…` (merged correctly) | 545 polygons across OD/PO/CO/M1…(108,0) | — |

**There is not one transistor in the standard cells, IO drivers or bond pads.**
Consequently any DRC result obtained from this stream must be **withdrawn, not
caveated** — Calibre is checking routing geometry over M1-only shells.

Confirmed absent, exhaustively: `find $TSMC_65_HOME -iname '*.cdl' -o -iname
'*.gds*'` returns exactly **one** file, `util/unit.cdl` (92 bytes, a units
header). Every TSMC 65 package on this system carries the `_FE` suffix; no
`*_BE` directory exists anywhere on `$TSMC_65_HOME`, `/research`, `/opt/cad`,
`/srv`, `$CDS_INSTALL` or `/apps`.

Reconstruction from installed views was checked and is impossible: Milkyway
`frame_only` holds 855 FRAM abstracts against 2 CEL entries (both filler
tiles); `celtic/` is `.cdb` noise models; `volcano/` is rule files; and the
staggered-IO `Back_End/` directory contains **only** `lef`.

Two flow files already point at data we do not have, which suggests this was
hit before and parked:
- `ASIC/common.mk:106` — `TCBN65LP_BE ?= /home/dwn1c21/SoC-Labs/phys_ip/.../tcbn65lp_<rev>_BE` (does not exist)
- `ahb_qspi/syn/asic/pdk_paths.tcl:47,62` — expect `*.gds` under `Back_End/celtic/` (none there)

---

## 3. What this unblocks, and how fast

**The cost after receipt is minutes, not another implementation run.** The
routed Innovus database is on disk (`ASIC/genus-innovus/work/nanosoc_eth_chiplet_pads`,
93 MB), so the sequence is:

1. append the three GDS paths to `gds_merge_list` in `ASIC/genus-innovus/scripts/config.tcl`
2. `restore_design` + `write_stream` — **minutes**
3. LVS: port `tidelink/syn/asic/calibre/scripts/run_calibre_lvs.sh` (a working
   `v2lvs` + `calibre -lvs -hier -64` harness that already exists in this repo)
   into `ASIC/genus-innovus/scripts/calibre_lvs` — about an hour
4. real signoff DRC over a real GDS

**Nothing is blocked on tooling.** All three signoff-grade LVS engines are
licensed and completely idle:

| engine | feature | issued | in use |
|---|---|---|---|
| Calibre nmLVS-H 2023.1_18.8 | `calibrelvs` / `calibrehlvs` | 150 / 150 | **0** |
| Synopsys IC Validator U-2022.12 | `ICValidator2-CompareEngine` | 192 | **0** |
| Cadence Pegasus 23.11.000 | `Pegasus_LVS` / `Pegasus_advlvs` | 41 / 41 | **0** |

Rule decks are on disk: `$TSMC_65_HOME/CMOS/LP/pdk/Calibre/lvs/calibre.lvs`
(854 KB) with `source.added` and `xcell`, plus
`util/MAIN_DECK/CALIBRE_FLOW/UTM/DFM_LVS_RC_CAL_N65_ALRDL_UTM_<rev>` matching
our `9M_6X1Z1U` stack. (Assura and PVS are installed but have **no** licence
features on the server — do not plan around them.)

---

## 4. Routes considered and rejected

**Retarget to the Arm sc12 library.** `$PHYS_IP/arm/tsmc/cln65lp/`
does ship complete standard cells — `sc12_base_rvt` has real layout
(`gds2` 11.6 MB, 967 `*_A12TR` structures with genuine NW/OD/PO/CO/M1 polygons)
and a real Calibre-format transistor netlist (`cdl` 1.1 MB). **But it is only
half a kit: ARM's cln65lp node ships no IO library and no bond-pad library.**
164 pad-ring instances across 11 TSMC cell types would still have no GDS and no
CDL, so full-chip LVS remains impossible. It also forces 9-track → 12-track rows
(new floorplan and power plan) and a metal-stack change — `arm_tech/<rev>` offers
`1p9m_6x2z` but **not** our `6X1Z1U`, which would invalidate the DRC deck
selection and the GDS-out layer map. 1–2 weeks of work that still does not
produce a bondable die.

**Reconstruct from Milkyway / celtic / volcano.** Ruled out — see §2.

---

## 5. Do not wait for this — these are unblocked today

- **The seal ring is already on-site.** `../design/PHYSICAL_HANDOFF.md` and the
  signoff checklist record it as not started and the broker's responsibility.
  In fact `$TSMC_65_HOME/CMOS/doc/sealring/sealring.zip` (1.26 MB) contains
  `N65_Mu_SR_<date>.gds` (1.45 MB), whose "Mu" matches the `MAIN_DRC_TopMu`
  deck this design uses. **Decide now whether the 1600 × 2000 µm die outline has
  to grow to accommodate it** — the pad ring currently starts at (0,0) with no
  space reserved, and that answer changes the floorplan. Far cheaper to learn
  today than after the BE packs land.
- **Metal density fill** — `add_metal_fill` appears nowhere in the flow. Innovus
  can do it, and Calibre YieldEnhancer (`calyield*`) is licensed and idle. It
  must be sequenced *after* the cell merge, since fill over hollow cells is
  wrong by construction. Assign an owner now.
- **Port the LVS harness now** and let it fail loudly on missing CDL, so the day
  the packages arrive it is one command rather than a day of scripting.
- **The quality gaps that are ours, not the foundry's**: 329 PG connectivity
  opens, 539 `check_drc` violations, 1,243 + 618 DRV, and no synth↔P&R LEC
  anywhere in the repo. None is blocked on this request, and all of them get
  more expensive to fix after the packages arrive.

---

## 6. One thing to correct immediately

Any claim that DRC has been run on this design must be withdrawn. It has not
been run meaningfully, and `scripts/ci/package_submission.sh`'s MANIFEST item 4
("reports DRC is not signoff DRC") understates it: the stream those reports
describe has no transistors in 424 of its cell masters.
