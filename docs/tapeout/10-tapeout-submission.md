# 10 — Tapeout submission

[← 09 Signoff checklist](09-signoff-checklist.md) · [index](00-index.md) · [11 Known issues →](11-known-issues.md)

How to build the hand-off bundle for `nanosoc_eth_chiplet_pads`, what is in it, and — the
part that decides whether the submission succeeds — **the questions that must be settled
with the foundry or MPW broker before it is sent**.

The governing fact on this page:

> **The GDSII this flow produces is not a complete chip.** It contains our routing, our
> power grid, our 8 memory macros' polygons, and **empty cell references** where every
> standard cell, IO driver and bond pad should be. It has no metal density fill, no seal
> ring, no scribe, and has never been LVS'd. All of that is normal for an academic PDK —
> and all of it has to be somebody's job, named in advance.

---

## 1. Build the bundle

```bash
scripts/ci/package_submission.sh                 # -> ASIC/genus-innovus/submission/<name>.zip
scripts/ci/package_submission.sh /path/to/dest   # or somewhere else
```

Source: [`scripts/ci/package_submission.sh`](../../scripts/ci/package_submission.sh)

The script exits non-zero if there is no GDS — there is nothing to submit without one. It
stages the files, writes `MANIFEST.txt`, zips, removes the staging directory and prints the
zip path on stdout.

**Bundle name** encodes provenance:

```
nanosoc_eth_chiplet_pads_<short-sha>[-dirty]_<YYYYMMDDTHHMMSSZ>.zip
```

A `-dirty` in that name means the working tree had uncommitted changes and **the submission
is not reproducible from a commit**. Do not send a `-dirty` bundle. Check first:

```bash
scripts/ci/signoff.py provenance      # prints a warning and records repo_dirty
```

In CI the bundle is built by `.github/workflows/asic-gds.yml` after `pnr_route` and
uploaded as artefact `gdsii-<run-number>` with 90-day retention.

---

## 2. What is in the bundle

| File | What it is | Baseline size |
|---|---|---|
| `nanosoc_eth_chiplet_pads.gds` | The stream. **Not self-contained** — see §3. | 441 MiB |
| `nanosoc_eth_chiplet_pads_pnr.v` | Post-P&R gate netlist. **This is what LVS needs.** | 57 MiB |
| `nanosoc_eth_chiplet_pads_pnr.sdf` | Post-P&R delays, three corners (min/typ/max views) | 567 MiB |
| `nanosoc_eth_chiplet_pads_syn.sdc` | Constraints as written out by synthesis | 51 KiB |
| `reports/` | Whole report directory, verbatim | ~750 KiB |
| `MANIFEST.txt` | Provenance, sha256 of every file, and the gap declaration | — |

Sizes are from the 2026-08-05 baseline
([`ASIC/genus-innovus/baseline_2026-08-05/`](../../ASIC/genus-innovus/baseline_2026-08-05/)).
The script prints `! MISSING <f>` for any file it cannot find rather than failing — **read
its output**, a bundle missing `_pnr.v` is a bundle LVS cannot be run against.

### What `MANIFEST.txt` records

Beyond the sha256 list: the UTC timestamp, build host, repo commit (with `-dirty` flag),
**recursive submodule status**, the paths of `genus` / `innovus` / `calibre` as resolved on
the build host, the Innovus version line lifted from the DRC report header, and the
floorplan geometry (`CORE_TO_IO`, `create_floorplan -site`).

The submodule list is not decoration. This design has 42 submodules and
[`docs/PIN_POLICY.md`](../PIN_POLICY.md) documents that **chiplet pins are routinely
unpushed** — a recorded gitlink that is not reachable from any remote means the bundle
cannot be rebuilt by anyone but the person who built it. Verify before sending:

```bash
# every gitlink must be reachable from at least one remote ref
git submodule status --recursive
```

### And then it declares its own gaps

The manifest ends with a `READ THIS BEFORE SUBMITTING` block listing six items:
non-self-contained GDS, no metal fill, no LVS, DRC-is-not-signoff-DRC, no seal ring or
scribe, and logical equivalence. **A bundle that does not declare its own gaps invites
somebody downstream to assume they were covered.**

> **One correction to make by hand.** Manifest item 6 asks the reader to confirm
> `make lec` "has been run and passed for **THIS netlist**". `make lec` compares RTL to
> the **synthesised** netlist via Genus's `fv_map` — it never reads `outputs/*_pnr.v`.
> There is no post-P&R LEC in this repository (declared as the `post-pnr-lec` coverage gap
> in [`ci/signoff.yaml`](../../ci/signoff.yaml)). State that plainly in the covering note.
> See [09 item 6](09-signoff-checklist.md).

---

## 3. Why the GDS is not self-contained

`gds_merge_list` in
[`ASIC/genus-innovus/scripts/config.tcl`](../../ASIC/genus-innovus/scripts/config.tcl)
merges **8 files**, all memory macros under `/research/precompiled_mems/TSMC65/` and
`ASIC/romlibs/`:

| Macro | Source |
|---|---|
| `rf_32k`, `rf_16k`, `rf_08k`, `rf_01k` | `/research/precompiled_mems/TSMC65/rf_*/` |
| `flash_cache_data`, `flash_cache_tag` | `/research/precompiled_mems/TSMC65/flash_cache_*/` |
| `cc_rom` (`rom_via`), `eth_rom` (`eth_rom_via`) | `ASIC/romlibs/` |

Those are the only cells in this design that ship both `.gds2` **and** `.cdl` on this site.

`/tsmc65pdk/65` ships LEF, liberty, Milkyway and layer maps — and **no GDS, no CDL** — for:

- `tcbn65lp` standard cells (9-track)
- `tphn65lpgv2od3_sl` staggered IO drivers
- `tpbn65v` bond pads

So in our stream every instance of those libraries is an **empty cell reference**: correct
name, correct placement and orientation, no polygons. **The recipient must merge the
foundry cell libraries.** Everything downstream follows from this — it is why DRC here is
not signoff DRC, and why LVS cannot run here at all.

**Stream-out settings** (from
[`ASIC/asic-flows/Cadence/4_pnr_route.tcl`](../../ASIC/asic-flows/Cadence/4_pnr_route.tcl)):

```tcl
write_stream $OUT_DIR/${block_name}.gds \
    -map_file /tsmc65pdk/65/CMOS/util/lef/PRTF_EDI_65nm_001_Cad_V24a/PR_tech/Cadence/GdsOutMap/PRTF_EDI_N65_gdsout_6X1Z1U.24a.map \
    -lib_name DesignLib \
    -merge $gds_merge_list \
    -output_macros -unit 1000 -mode all
```

- **Layer map:** `PRTF_EDI_N65_gdsout_6X1Z1U.24a.map` — the 9-metal `6X1Z1U` stack.
  Sibling maps for other stacks sit in the same directory; picking the wrong one silently
  produces a stream on the wrong layer numbers.
- **Units:** `-unit 1000` → 1 nm database grid.
- **Top cell:** `nanosoc_eth_chiplet_pads`.

---

## 4. Questions to settle **before** submitting

These are not optional. Each has already been established as a real gap by direct
measurement, and each has a definite owner who is **not us** or, where it is us, needs
scheduling. Get answers in writing.

### 4.1 Who merges the cell-level GDS?

**Why it matters:** without it there is no chip — just routing over empty boxes.

**What to tell them:** we stream with `PRTF_EDI_N65_gdsout_6X1Z1U.24a.map`, 1 nm units,
top cell `nanosoc_eth_chiplet_pads`, libraries `tcbn65lp` (9-track, `tcbn65lp_220a`),
`tphn65lpgv2od3_sl` (`210a`, staggered, 2.5 V IO), `tpbn65v` (`200b`, `cup/9m/9M_6X1Z1U`).
Our 8 memory macros are **already merged in** — they must not double-merge them.

**What to ask:** which library revisions do they hold, and do they want our stream with the
memories merged (as shipped) or stripped out so they merge everything themselves?

**Watch for:** one **local override** exists in the LEF set —
`ASIC/tech_wrappers/tsmc65/local_overrides/tphn65lpgv2od3_sl_9lm.lef`, a copy of the TSMC
IO driver LEF with `USE POWER ;` / `USE GROUND ;` added to exactly three pins
(`VDDPST` on `PVDD2DGZ_G` and `PVDD2POC_G`, `VSSPST` on `PVSS2DGZ_G`). It is a
**LEF-only, abstract-only** change made so `connect_global_net -type pg_pin` could match
them; it does not alter any polygon and the shared PDK was not modified. Mention it anyway
— it is a deviation from the shipped library and they should know.

### 4.2 Who adds metal density fill?

**Why it matters:** **this is the single most likely thing to bite at submission.**

**State plainly:** `add_metal_fill` appears **nowhere** in this flow —

```bash
grep -rn 'add_metal_fill' ASIC/     # no hits
```

Standard-cell filler **and** antenna diodes *are* inserted (150,592 instances, of which
50,274 `ANTENNA` diodes) — that is base-layer fill, a different thing. **Per-layer metal
density is entirely unaddressed and will fail foundry density rules as-is.**

**What to ask:** do they insert metal fill as part of acceptance, or must we deliver a
density-clean stream? If it is ours: we need the density rules, the fill cell set and — the
real cost — a re-run, since fill changes coupling capacitance and therefore timing.

### 4.3 Who runs LVS?

**Why it matters:** LVS has **never been run on this design**, in any form.

**Why we cannot:** it needs a CDL netlist for every leaf cell; only the 8 memories have
one. `ASIC/genus-innovus/scripts/calibre_lvs` is a zero-byte placeholder. The PDK ships
`ICV_iLVS/` and `LVS.rsf` but no Calibre LVS deck usable against libraries we have no CDL
for.

**What we supply:** `nanosoc_eth_chiplet_pads_pnr.v`. Ask what netlist format they want —
Verilog is what we have; if they need CDL from us, that is a conversion we have not done
and it still would not include leaf-cell subcircuits.

**Ask specifically:** do they need a `.spi`/CDL top-level, a layout-vs-schematic device
list, or is the post-P&R Verilog sufficient against their own cell CDL?

### 4.4 Who adds the seal ring and scribe?

**Why it matters:** there is **no seal ring and no scribe** in the design data, and no
space reserved for one inside the die box.

**Geometry to give them:** die `1600 × 2000 µm`, **pad ring starting at coordinate (0,0)**
— the die box is `(0,0)–(1600,2000)`. `CORE_TO_IO = 70 µm`, IO cells 135 µm tall, so the
core box is `(205,205)–(1395,1795)`. The bond ring is **staggered**: `PAD70GU` outer
(86.685 µm tall), `PAD70NU` inner (171 µm tall).

**What to ask:** do they add seal ring and scribe outside our 1600 × 2000, or must it come
out of it? **If it must come out of it, the floorplan changes and everything re-runs** —
`CORE_TO_IO` and 21 absolute macro coordinates are coupled to the die box, see
[03 Floorplan](03-floorplan.md). This question has a schedule attached to it; ask it early.

### 4.5 What layer map do they expect?

We stream with `PRTF_EDI_N65_gdsout_6X1Z1U.24a.map`. Confirm they expect `6X1Z1U`
(9-metal: 6 thin + 1Z + 1U + AP) and the TSMC PRTF layer numbering rather than a
broker-specific map. Ask whether they want the `.map` file itself included in the bundle —
it is PDK material, so check the licence before shipping it, but they need to know which
one was used either way.

### 4.6 What format, and how is it delivered?

Ask for all of:

- **Stream format** — GDSII (what we produce) or OASIS? Conversion is trivial, but it must
  be their call.
- **Compression** — the bundle contents total ~1.1 GB uncompressed (the SDF alone is
  567 MiB) before the script zips them. Do they want the GDS gzipped separately, and do
  they even want the SDF?
- **Delivery** — SFTP drop, physical media, a portal? Is there a size cap?
- **Checksums** — `MANIFEST.txt` carries sha256 for every file; confirm that is the digest
  they check against.
- **Naming** — do they impose a filename or top-cell convention? Ours is
  `nanosoc_eth_chiplet_pads` throughout, including the top cell inside the stream.
- **Deadline and MPW shuttle date** — and the cut-off for a *revised* stream, since
  §4.2 and §4.4 could both force a re-run.

### 4.7 What acceptance checks do they run, and what do they consider blocking?

Give them our numbers up front rather than letting their tools find them:

- Innovus `check_drc`: **539** violations, of which **398** involve a bond-pad blockage
  and **318** are `VDD`/`VSS` special wires shorting into one. Root-caused, fix in flight
  ([11b](11-known-issues.md)).
- `check_connectivity`: **329** PG opens on `VDD`/`VSS`, unresolved
  ([11a](11-known-issues.md)). **Report caps at 1,000 messages — this is a lower bound.**
- Post-route DRV: **1,243** `max_transition` and **618** `max_capacitance` violations
  ([11g](11-known-issues.md)).
- Setup: WNS **+0.068 ns**, TNS 0, FEP 0 at `05_route_opt`.

**Ask:** which of those do they treat as blocking, and do they re-run DRC themselves after
merging the cell libraries — because that run is the first one whose result actually means
something.

---

## 5. Covering note — say these six things

Do not rely on the recipient reading `MANIFEST.txt`. Put this in the email:

1. **The stream is not self-contained.** Standard cells, IO drivers and bond pads are empty
   cell references. The 8 memory macros are already merged.
2. **No metal density fill.** Base-layer filler and antenna diodes are in; per-layer metal
   density is not addressed.
3. **LVS has never been run.** `*_pnr.v` is enclosed for whoever holds the cell CDL.
4. **The DRC numbers in `reports/` are Innovus `check_drc` over the incomplete stream**,
   not signoff DRC. Calibre was run against the same incomplete stream.
5. **No seal ring, no scribe.** Die is 1600 × 2000 µm, pad ring from (0,0).
6. **Logical equivalence covers RTL → synthesised netlist only.** Nothing in this repo
   compares anything to the enclosed `*_pnr.v`. State it; do not let silence imply
   coverage.

---

## 6. Pre-send checklist

- [ ] Working tree clean — bundle name has **no** `-dirty`
- [ ] `git submodule status --recursive` — every gitlink reachable from a remote
      ([`PIN_POLICY.md`](../PIN_POLICY.md))
- [ ] `package_submission.sh` printed no `! MISSING` lines
- [ ] `MANIFEST.txt` read end to end, and its LEC claim corrected by hand (§2)
- [ ] All of [09 — Signoff checklist](09-signoff-checklist.md) tiers 0–5 done, numbers
      recorded
- [ ] [11 — Known issues](11-known-issues.md) reviewed; anything still open is *in the
      covering note*
- [ ] §4.1–4.7 answered **in writing** by the foundry or broker
- [ ] Covering note (§5) written and attached
- [ ] Bundle sha256 sent separately from the bundle

---

## Related

- [09 — Signoff checklist](09-signoff-checklist.md) — what must be true first
- [11 — Known issues](11-known-issues.md) — the live open items
- [03 — Floorplan](03-floorplan.md) — die/core geometry, why `CORE_TO_IO` is coupled to
  macro placement
- [06 — Fill, antenna, bond pads](06-fill-antenna-bondpads.md) — what fill *is* inserted
- [`docs/PHYSICAL_HANDOFF.md`](../PHYSICAL_HANDOFF.md) — what has and has not been verified
  at RTL level
- [`docs/PIN_MAP.md`](../PIN_MAP.md) · [`docs/PIN_POLICY.md`](../PIN_POLICY.md) ·
  [`docs/POWER_DOMAINS.md`](../POWER_DOMAINS.md)

---

[← 09 Signoff checklist](09-signoff-checklist.md) · [index](00-index.md) · [11 Known issues →](11-known-issues.md)
