# 09 — Signoff checklist

[← 08 Debugging](08-debugging.md) · [index](00-index.md) · [10 Tapeout submission →](10-tapeout-submission.md)

What must be true before `nanosoc_eth_chiplet_pads` is submitted, in the order worth doing
it. Cheap, high-catch checks first; the multi-hour licensed ones last; the ones that
**cannot be closed on this site at all** last of all, clearly marked.

Every item states **the command**, **what "pass" looks like as a testable condition**, and
**where it can run**. Where a check has never been run on this design, it says so — none of
the "not run" items below should be read as "probably fine".

> **Commands** prefixed `make <target>` run from `ASIC/genus-innovus/`.
> Commands prefixed `make asic-*`, `scripts/ci/*` and `./scripts/…` run from the repo root.
> Report paths are relative to `ASIC/genus-innovus/`.

---

## The one-screen summary

| # | Check | Closes where? | Status on this design |
|---|---|---|---|
| 0 | Provenance recorded | local, seconds | tooling exists, run it per submission |
| 1 | Artefacts present & non-empty | local, seconds | passes |
| 2 | Boundary / lint / elaboration / multi-driver | local | passes (gated in CI) |
| 3 | CDC | local | **runs, not clean** — report-only by design |
| 4 | Functional regression | local | passes (gated in CI) |
| 5 | **LEC — RTL vs synthesised netlist** | local | **run it. Highest catch per minute of any check here.** |
| 6 | **LEC — synth vs post-P&R netlist** | — | **DOES NOT EXIST anywhere in this repo** |
| 7 | Filler & gap closure | local, free (read reports) | passes — 0 gaps, 150,592 fillers |
| 8 | Antenna (router-level) | local, free | passes — "No Violations Found" |
| 9 | PG connectivity | local, free | **FAILS — 329 opens** ([11a](11-known-issues.md)) |
| 10 | Innovus `check_drc` | local, free | **539 violations** ([11b](11-known-issues.md)); *not* signoff DRC |
| 11 | Timing — setup/hold | local, free | setup WNS **+0.068 ns**, 0 FEP — but see 11a caveat below |
| 12 | Timing — DRV (transition/cap) | local, free | **FAILS — 1,243 + 618 violations** ([11g](11-known-issues.md)) |
| 13 | Calibre DRC | local, licensed, hours | run it, but it is **over an incomplete GDS** |
| 14 | Antenna signoff (foundry deck) | not wired here | **never run** |
| 15 | Metal density fill | **foundry / broker** | **never done — `add_metal_fill` is nowhere in this flow** |
| 16 | LVS | **foundry / broker** | **never run, and cannot be run here** |
| 17 | Cell-level GDS merge | **foundry** | **not done — the GDS is not self-contained** |
| 18 | Seal ring + scribe | **broker** | **not in the design data** |
| 19 | IR drop / power signoff | not wired here | **never run** |

Items 15–19 are the reason [10 — Tapeout submission](10-tapeout-submission.md) exists.
They are not oversights to be fixed on this site; they are hand-off boundaries to be
**agreed in writing with the recipient before the bundle is sent**.

---

## Tier 0 — seconds. Do these every time.

### 0. Record provenance

Signoff without provenance is an assertion about nothing in particular.

```bash
scripts/ci/signoff.py provenance
```

**Pass:** `build/signoff/provenance/provenance.md` exists, and
`"repo_dirty": false` in `provenance.json`.

**Fail loudly if dirty.** The script prints
`WARNING: working tree is dirty — this is not a reproducible signoff`.
A dirty tree means the GDS cannot be rebuilt from a commit, so the bundle's
`MANIFEST.txt` will carry a `-dirty` suffix and the submission is unreproducible.

Driver: [`scripts/ci/signoff.py`](../../scripts/ci/signoff.py) ·
manifest: [`ci/signoff.yaml`](../../ci/signoff.yaml)

### 1. Every stage actually produced its artefact

```bash
make status          # from ASIC/genus-innovus/
```

**Pass:** `yes` on every row — `flist romlibs syn place cts route gds pnr-netlist`.

This matters more than it looks. **Genus and Innovus both exit `0` after printing an
error and doing nothing** — three P&R stages once "passed" in under a minute because `-f`
is not a valid stylus argument. `make status` reads the artefacts on disk, not exit codes.
See [01](01-flow-overview.md) and [08](08-debugging.md).

Also confirm the four bundle files exist and are large:

```bash
ls -l ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads{.gds,_pnr.v,_pnr.sdf,_syn.sdc}
```

**Pass:** all four present, none zero-length. Reference sizes from the
2026-08-05 baseline: GDS 441 MiB, `_pnr.v` 57 MiB, `_pnr.sdf` 567 MiB.
A GDS of a few MB means the merge or the stream failed.

---

## Tier 1 — RTL gates. No PDK, runs on either host.

These are declared in [`ci/signoff.yaml`](../../ci/signoff.yaml) and driven by
`scripts/ci/signoff.py run rtl`. All are `gate: block` except CDC.

### 2. Boundary, lint, elaboration, multi-driver

```bash
scripts/ci/signoff.py run chip-boundary lint elab elab-strict
```

**Pass:** each stage reports `PASS`; `build/signoff/<stage>/status.json` has
`"passed": true`.

**`elab-strict` has a documented false-green** and the manifest guards against it: the
gate greps `verif/elab_strict/build/xrun_hal.log` for `MLTDRV`, so a HAL run that
**aborted before the multi-driver rules ran** finds nothing and reports OK. The `check:`
block asserts `Analysis complete` and rejects `BLDSTP` / `Analysis failed` first.
If you run `make elab-strict` by hand, apply the same test yourself:

```bash
grep -q 'Analysis complete' verif/elab_strict/build/xrun_hal.log \
  && ! grep -q 'BLDSTP\|Analysis failed' verif/elab_strict/build/xrun_hal.log \
  && echo OK
```

### 3. CDC

```bash
make cdc
```

**Pass criterion: there isn't one yet.** This stage is deliberately `gate: report`.
[`docs/CDC_FINDINGS.md`](../CDC_FINDINGS.md) says in its own words that it is
"a **starting point** for the physical team's CDC signoff, not a clean bill".

**What is actually owed for signoff:** a real CDC pass on the *taped-out configuration*,
run inside TideLink where the `pad_clk_rx → sys_hclk` crossing lives, with the shipped
parameters rather than the defaults. See
[`docs/PHYSICAL_HANDOFF.md` §6](../PHYSICAL_HANDOFF.md). Nobody has done this.

Related open constraint decision: `constraints.sdc` cuts `D2D_RX_CLK_0` with a blanket
`set_clock_groups -asynchronous`, and the file itself flags it —
`[OWNER] For SIGNOFF, narrow the D2D_RX_CLK_0 cut rather than leaving it a blanket group`.
A blanket async group means the tool reported *nothing* about that crossing.

### 4. Functional regression

```bash
make regress
```

**Pass:** exit 0; `verif/g2_soc_pair/results*.xml` and
`verif/g2_peer_aperture/results*.xml` show no failures.

**Scope honesty:** this proves the die-to-die datapath **in simulation between two
simulated dies**. No transaction has ever crossed a die boundary on silicon, and the sim
bring-up leans on bench straps rather than real auto-negotiation
(`NEGO_CFG_RESET = 7'h00` parks the FSM in `ST_BYPASS`). See
[`docs/PHYSICAL_HANDOFF.md` §6](../PHYSICAL_HANDOFF.md) and `docs/G2_SOC_PAIR_STATUS.md`.

---

## Tier 2 — LEC. Do this before anything licensed and expensive.

### 5. Logical equivalence: RTL vs **synthesised** netlist

**This is the single highest-value check on the page.** A previous build silently lost
TideLink's **entire TX datapath** to Genus `GLO-34` unused-logic removal, and the July
reference GDSII shipped hollow — no TX datapath, no PTP seconds counter, no timestamps.
Every other check on this list passed on that GDS. DRC does not care whether the logic is
there. LEC is the check that sees it.

```bash
make lec                                   # from ASIC/genus-innovus/
# or, with the post-condition enforced:
scripts/ci/signoff.py run lec              # from repo root
```

Runs Conformal: `lec -xl -Dofile ./lec.dofile` in `work/`, using `work/lec.dofile` and
`work/fv/` written by Genus during `make syn`.

**Pass — and you must test this yourself, because the tool will not:**

```bash
L=ASIC/genus-innovus/logs/lec.log
grep -qE 'Compare Results:[[:space:]]*PASS|Equivalent' "$L" \
  && ! grep -qE 'Different Key Points|Abort Points|Unknown Key Points' "$L" \
  && echo LEC-PASS
```

> **`lec.dofile` ends with `exit -f`, which returns 0 even when key points differ, and
> the Makefile adds no check.** Without the grep above a non-equivalent design passes
> silently. This is the worst false-green in the physical flow, and it is exactly the
> failure mode that let the hollow July GDSII through. `signoff.py` enforces it via the
> `check:` block on the `lec` stage in [`ci/signoff.yaml`](../../ci/signoff.yaml).

**Prerequisite:** `make clean` deletes `work/`, which destroys `lec.dofile` and `fv/`.
LEC must run in the same work area as the `syn` that produced them, or not at all.

### 6. Logical equivalence: synthesised vs **post-P&R** netlist — DOES NOT EXIST

There is **no post-P&R LEC anywhere in this repository.** Item 5 compares RTL to the
netlist Genus wrote; nothing compares anything to `outputs/nanosoc_eth_chiplet_pads_pnr.v`.

`scripts/ci/package_submission.sh`'s MANIFEST item 6 asks the reader to
"confirm `make lec` has been run and passed for **THIS netlist**" — but `make lec` cannot
do that. Declared as a coverage gap (`post-pnr-lec`) in
[`ci/signoff.yaml`](../../ci/signoff.yaml).

**What this leaves uncovered:** anything CTS, `opt_design -post_route -hold` or the
bond-pad/filler stage could change. Post-route hold repair inserted **65,250 instances**
between `opt_design_postcts_hold` (194,869) and `opt_design_postroute_hold` (260,119) —
that is a large amount of unverified structural change.

**To close it:** run Conformal with the synthesised netlist as golden and
`outputs/*_pnr.v` as revised, reading the same LEF/liberty set. Not scripted here.
Until then, say so in the hand-off rather than implying LEC covered the shipped netlist.

---

## Tier 3 — physical checks the flow already ran. Free: just read the reports.

`4_pnr_route.tcl` runs all four of these after routing and bond-pad placement. Reading
them costs nothing; the 2026-08-05 baseline numbers are quoted so you can spot a
regression at a glance. Baseline:
[`ASIC/genus-innovus/baseline_2026-08-05/reports/`](../../ASIC/genus-innovus/baseline_2026-08-05/reports/)

A stage-by-stage diff against the baseline is emitted automatically by
[`scripts/ci/asic_stage_report.sh`](../../scripts/ci/asic_stage_report.sh):

```bash
scripts/ci/asic_stage_report.sh route
```

That script is **report-only and never gates** — it prints `n/a` rather than failing.
The pass criteria below are yours to apply.

### 7. Filler and gap closure

```bash
grep -c . reports/nanosoc_eth_chiplet_pads_imp_filler.rep
cat work/check_filler.log
```

**Pass:**
- `check_filler.log` reads `Total number of gaps found: 0` **and**
  `Total number of padded cell violations: 0`
- the route log reports a **non-zero** `Total N filler insts added`

**Baseline: passes.** 0 gaps, 0 padded-cell violations, **150,592 filler instances**
inserted — of which **50,274 are `ANTENNA` diodes**, plus FILL1 51,788 / FILL2 27,799 /
FILL4 18,391 / FILL8 1,194 / FILL16 379 / FILL32 93 / FILL64 674.

**This check exists because it once failed silently.** `write_power_intent -cpf` cannot
translate the design's UPF supply commands, so Genus emits a CPF containing only
`create_power_domain -name PD_TOP -default`. Innovus then fails every filler pass with
`IMPSP-5110: No supply-net names for Power Domain 'PD_TOP'`, `add_fillers` reports
"For 0 new insts", and **the flow completes and streams a GDSII with zero filler cells and
95,568 free-site gaps (~5.9% of the core)** — no base-layer density fill, no antenna
diodes. `make syn` now repairs the CPF (`cpf-patch` target), and `power_plan.tcl` errors
out if the domain has no supply nets. If `add_fillers` ever reports 0 again, that is the
cause. See [04](04-power-plan.md) and [06](06-fill-antenna-bondpads.md).

### 8. Antenna — router level

```bash
cat reports/nanosoc_eth_chiplet_pads_imp_antenna.rep
```

**Pass:** the file contains `No Violations Found`.

**Baseline: passes.**

**Do not call this antenna signoff.** It is Innovus `check_process_antenna` against
LEF-derived antenna rules, over an incomplete GDS. The foundry decks are present but not
wired into anything here: `/tsmc65pdk/65/CMOS/util/ANTENNA_DRC/CN65S_9M_ANT.26_2a`.
Declared as the `antenna-signoff` coverage gap in `ci/signoff.yaml`. See item 14.

### 9. PG connectivity

```bash
grep -c 'has special routes with opens' reports/nanosoc_eth_chiplet_pads_imp_connectivity.rep
grep -A5 'Begin Summary' reports/nanosoc_eth_chiplet_pads_imp_connectivity.rep
```

**Pass:** `0` opens (`IMPVFC-200`) on `VDD` and `VSS`.

**Baseline: FAILS — 329 opens**, plus 671 dangling wires (`IMPVFC-94`).

> **The report caps at 1,000 messages** (`1000 total info(s) created`), so **329 is a
> lower bound** once the list saturates. Do not treat a number that stops moving as
> evidence that nothing changed — see [11a](11-known-issues.md), where two hypotheses have
> already been falsified by experiment.

This is an **open, unresolved defect**. It must be understood before submission: PG opens
either mean real missing vias (a functional power-delivery defect that silicon will show
as brownout under load) or reporting artefacts from `sroute`. Nobody has established
which.

### 10. Innovus `check_drc`

```bash
grep -cE '^[A-Z]+:' reports/nanosoc_eth_chiplet_pads_imp_drc.rep
grep -oE '^[A-Z][A-Za-z ]+:' reports/nanosoc_eth_chiplet_pads_imp_drc.rep | sort | uniq -c | sort -rn
```

**Pass:** `0`.

**Baseline: 539 violations** — SHORT 379, SPACING 108, EndOfLine 41, MINSTEP 28,
MINHOLE 14, NSMETAL 7, MINCUT 2, MINWIDTH 1. Of those, **398 involve a bond-pad blockage**
and **318 are `VDD`/`VSS` special wires shorting into one** — root-caused and fixed by
raising `CORE_TO_IO` 50 → 70 µm; a verification run is in flight. See
[11b](11-known-issues.md) and [03](03-floorplan.md).

> ### This is NOT signoff DRC
>
> It is `check_drc` over a GDS whose `gds_merge_list` holds **only the 8 memory macros**.
> Standard cells, IO drivers and bond pads are **empty cell references**. It therefore
> checks routing, PG and blockage geometry — and nothing at all inside a standard cell,
> an IO driver or a bond pad. A clean result here would still say nothing about density,
> base layers, or cell-internal rules.

---

## Tier 4 — timing. Free, but read all of it, not just WNS.

### 11. Setup and hold

```bash
cat reports/timing_summary_05_route_opt.rep
cat reports/qor_05_route_opt.rep
```

**Pass:** setup `WNS ≥ 0`, `TNS = 0`, `FEP = 0` across all views, in the
**`05_route_opt`** summary (the final one — earlier stages are not signoff).

**Baseline: passes on setup.** `View : ALL` WNS **+0.068 ns**, TNS 0.000, FEP 0.
Per group: reg2reg +0.068, in2reg +0.807, reg2out +8.062, ClockGate +6.800, Async +2.398.
`min_pulse_width` +5.823, `min_period` +7.045, both 0 FEP.

Two caveats that make this number softer than it looks:

- **`report_timing_summary` in `4_pnr_route.tcl` cannot report early and late together.**
  The file opens with `**ERROR: (TCLCMD-1130)` — Innovus discarded `-early` and used
  `-late` alone. **The summary you are reading is setup only.** For hold, read
  `reports/nanosoc_eth_chiplet_pads_imp_timing_early.rep` and
  `..._imp_timing_typical_early.rep`.
- **Hold margin is a live open item.** `CLK_HOLD_ERROR = 0.05` in
  `inputs/constraints.sdc` is deliberately *not* the 0.35 ns oscillator jitter used for
  setup, and the file itself calls it "a signoff margin — revisit it with the clocking
  spec". It has not been revisited. See [11e](11-known-issues.md).

Also worth a look before you sign anything: **core utilisation reached 89.45 %** at
`opt_design_postroute_hold` (from 75.52 % post-CTS), because hold repair inserted 65,250
instances. That is the practical ceiling of this floorplan.

### 12. Design-rule violations in timing (DRV) — **currently failing**

```bash
sed -n '/^# DRV/,/^#---*$/p' reports/timing_summary_05_route_opt.rep
```

**Pass:** `max_transition` and `max_capacitance` FEP both `0`.

**Baseline: FAILS.**

| Check | WNS | TNS | FEP |
|---|---|---|---|
| `max_transition` | −3.035 | −1032.060 | **1,243** |
| `max_capacitance` | −0.173 | −2.361 | **618** |

`qor_05_route_opt.rep` reports the same as `DRV(T) Tran -1032` / `DRV(C) Load -2`.

Slow transitions are not a cosmetic complaint: they invalidate the delay model the +0.068 ns
setup number was computed with, and they are a hot-electron/reliability concern the
foundry may ask about. **This has not been triaged.** See [11g](11-known-issues.md).

---

## Tier 5 — licensed and slow. Run last, locally.

### 13. Calibre DRC

```bash
make drc_batch                    # headless; from ASIC/genus-innovus/
make drc                          # same, in the Calibre GUI
make asic-drc                     # equivalent, from the repo root
scripts/ci/signoff.py run drc     # same, with the violation count enforced
```

Deck: `/tsmc65pdk/65/CMOS/util/MAIN_DRC_TopMu/CLN65S_9M_6X1Z1U.26_2a`
(also `drc_ruledeck` in [`config.tcl`](../../ASIC/genus-innovus/scripts/config.tcl)).
Results land in `work/drc_run/`.

**Pass — Calibre will not tell you, so count it yourself:**

```bash
python3 - ASIC/genus-innovus/work/drc_run/DRC.rep <<'EOF'
import re, sys
txt = open(sys.argv[1], errors="replace").read()
bad = [(n, int(c)) for n, c in re.findall(
        r'RULECHECK\s+(\S+).*?TOTAL Result Count\s*=\s*(\d+)', txt, re.S) if int(c) > 0]
print(bad or "DRC clean")
sys.exit(1 if bad else 0)
EOF
```

> **Calibre exits 0 whether or not it found violations.** The `drc` stage in
> `ci/signoff.yaml` wraps exactly the script above for that reason.

**Two things that have bitten this design already:**

1. **The TSMC deck ships with placeholders** — `LAYOUT PATH "GDSFILENAME"` and
   `LAYOUT PRIMARY "TOPCELLNAME"`. They *must* be overridden by a Calibre Interactive
   runset. The Makefile generates `work/calibre_drc.runset` with layout and top cell
   derived together from `$(GDS)` and `$(BLOCK)`, so they cannot drift apart. In the July
   reference run they did drift: the deck named the *pre-pads* stream against top cell
   `nanosoc_eth_chiplet_pads`, which is not a cell in that file — hence its **0-byte
   `DRC_RES.db`**.
2. **The `exec calibre` at the end of `4_pnr_route.tcl` is a no-op.** It passes the
   ruledeck with no runset, so the placeholders are never resolved. The baseline's
   `work/DRC_RES.db` is 0 bytes for that reason. **Use `make drc_batch`, not the
   in-Innovus call.**

**And the caveat that outranks all of the above:** Calibre here runs over the **same
incomplete GDS**. It cannot check anything inside a standard cell, an IO driver or a bond
pad, because there is no polygon data for them on this site. A clean Calibre run here is
necessary, and nowhere near sufficient.

---

## Tier 6 — cannot be closed on this site. Agree these with the recipient.

Each of these is a real signoff requirement that **this repository cannot satisfy at all**.
They are all declared as coverage gaps in [`ci/signoff.yaml`](../../ci/signoff.yaml) and
restated in the bundle's `MANIFEST.txt`. Take them to
[10 — Tapeout submission](10-tapeout-submission.md) as questions, not tasks.

### 14. Antenna signoff against the foundry deck — **never run**

The 9-metal antenna deck exists at
`/tsmc65pdk/65/CMOS/util/ANTENNA_DRC/CN65S_9M_ANT.26_2a`, but nothing in this flow invokes
it, and it would run over the incomplete GDS anyway. Item 8 is a router-level check only.

**Ask the broker:** do they run antenna as part of their acceptance flow, or is it ours?

### 15. Metal density fill — **never done, and most likely to bite**

```bash
grep -rn 'add_metal_fill' ASIC/    # returns nothing
```

**`add_metal_fill` appears nowhere in any script in this flow.** Standard-cell filler and
antenna diodes are inserted (item 7) — that is *base-layer* fill and it is a different
thing. **Per-layer metal density is entirely unaddressed and will fail foundry density
rules as-is.**

This is the item most likely to stop a submission. **Settle it before you send anything.**

### 16. LVS — **never run, and cannot run here**

LVS needs a CDL netlist for **every leaf cell**. On this site only the 8 memory macros
ship `.cdl`, under `/research/precompiled_mems/TSMC65/`. There is no CDL for `tcbn65lp`,
`tphn65lpgv2od3_sl` or `tpbn65v`. `ASIC/genus-innovus/scripts/calibre_lvs` is a
**zero-byte file**.

**What we can supply:** `outputs/nanosoc_eth_chiplet_pads_pnr.v`, to whoever holds the
foundry data. **They run LVS; we cannot.**

### 17. Cell-level GDS merge — **the recipient must do this**

`gds_merge_list` in [`config.tcl`](../../ASIC/genus-innovus/scripts/config.tcl) merges
**only the 8 memory macros** (`rf_32k`, `rf_16k`, `rf_08k`, `rf_01k`, `cc_rom`, `eth_rom`,
`flash_cache_data`, `flash_cache_tag`) — those ship `.gds2` *and* `.cdl` locally.

`/tsmc65pdk/65` ships LEF, liberty, Milkyway and layer maps but **no GDS and no CDL** for
`tcbn65lp` or the IO libraries. That is the normal academic-PDK arrangement: polygon data
stays at the foundry. **Standard cells, IO drivers and bond pads are therefore empty cell
references in our stream.**

Layer map used by `write_stream`
([`4_pnr_route.tcl`](../../ASIC/asic-flows/Cadence/4_pnr_route.tcl)):

```
/tsmc65pdk/65/CMOS/util/lef/PRTF_EDI_65nm_001_Cad_V24a/PR_tech/Cadence/GdsOutMap/PRTF_EDI_N65_gdsout_6X1Z1U.24a.map
```

### 18. Seal ring and scribe — **not in the design data**

Die is **1600 × 2000 µm with the pad ring starting at coordinate (0,0)**. There is no seal
ring and no scribe structure in the stream, and no space reserved for one inside the die
box. **Confirm with the broker who adds them, and whether that changes the die outline we
must draw to.**

### 19. IR drop / power signoff — **never run**

No Voltus, no RedHawk. `reports/nanosoc_eth_chiplet_pads_imp_power.rep` is
`report_power` — an estimate, not an IR-drop analysis. Given item 9's 329 PG opens and
89.45 % utilisation, this is not a gap to wave through quietly.

---

## Running the whole pipeline

```bash
scripts/ci/signoff.py list                # stages, gates, host requirement, coverage gaps
scripts/ci/signoff.py provenance
scripts/ci/signoff.py run rtl             # tiers 1
scripts/ci/signoff.py run physical        # LEC + Calibre DRC — srv03335 only
scripts/ci/signoff.py report              # one collated report + declared gaps
```

`build/signoff/signoff_report.md` prints three sections that matter more than the pass
table: **stages not run in this session**, **declared coverage gaps**, and a verdict that
distinguishes `NOT SIGNED OFF` from `PARTIAL` from "all executed gates passed".

The physical stages need `/tsmc65pdk`, so only `srv03335` can run them
(`label: soclabs-pdk`, enforced by [`scripts/ci/preflight.sh`](../../scripts/ci/preflight.sh)).
Implementation itself is **not** in this pipeline — it is
`.github/workflows/asic-gds.yml`. Run order:
`asic-signoff (rtl)` → `asic-gds` → `asic-signoff (physical)`.

---

## Before you send the bundle

Read [10 — Tapeout submission](10-tapeout-submission.md) and [11 — Known
issues](11-known-issues.md) end to end, then confirm all of:

- [ ] Provenance recorded, working tree **clean**
- [ ] `make status` all `yes`; the four bundle files present and plausibly sized
- [ ] `scripts/ci/signoff.py run rtl` → all blocking stages PASS
- [ ] **LEC run, and the log grepped by hand** (`exit -f` returns 0 regardless)
- [ ] It is written down that **post-P&R LEC does not exist**
- [ ] `check_filler` → 0 gaps; `add_fillers` → non-zero
- [ ] `check_process_antenna` → `No Violations Found`
- [ ] `check_connectivity` opens count recorded — **currently 329, not zero**
- [ ] `check_drc` count recorded — **currently 539, and it is not signoff DRC**
- [ ] Setup WNS/TNS/FEP recorded from `05_route_opt`; hold read separately from the
      `_early` reports
- [ ] DRV counts recorded — **currently 1,243 + 618, not zero**
- [ ] Calibre DRC run via `make drc_batch`, result **counted**, not assumed
- [ ] Items 15–19 answered **in writing** by the foundry or broker

---

[← 08 Debugging](08-debugging.md) · [index](00-index.md) · [10 Tapeout submission →](10-tapeout-submission.md)
