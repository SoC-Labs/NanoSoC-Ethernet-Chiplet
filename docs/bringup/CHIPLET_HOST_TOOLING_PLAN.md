# Chiplet interconnect host tooling — bundling / packaging plan

**Question:** should our chiplet interconnect host tools (`kr260_eth_bringup.py`,
`kr260_eth_xfer.py`, `eth_ss_probe.py`, `kr260_eth_run.sh`, `tl_socmap.py`, the
deploy/AFI scripts…) move into a shared subrepo so all chiplet designs can use them?

**Answer: no new repo.** The tools already live in the right *repo* — `tidelink`, the
de-facto shared D2D home (vendored as a submodule by ≥4 chiplet designs) — but in the
wrong *form*: **inside** the tidelink submodule yet **outside** its pip package, as
loose scripts that hard-code **three separate address maps**. Fix the form, not the
home: **package `pynq_host/` as part of tidelink's existing python package, and
collapse the three maps behind a per-target address-descriptor registry.**

---

## Why not a separate repo

- Every D2D consumer **already vendors tidelink**; the tools poke TideLink registers
  in lockstep with tidelink's `regs.py`/RTL. A separate repo adds a *second* thing to
  version-pin against the same RTL and a deeper (4th-level) submodule — exactly the
  "two-checkouts trap" already in our memory, doubled. There is no non-tidelink D2D
  consumer to justify the split.
- Reuse is *already* achieved by tidelink being shared. The real defects are: (a) the
  tools aren't packaged, so they're **copied into every consumer and have already
  diverged** (this submodule has `eth_ss_probe.py`/`kr260_eth_*` the standalone
  `~/SoCLabs/tidelink` checkout lacks); and (b) **three hard-coded address maps**.
  Both are fixed *inside* tidelink.

## The real problem: three address maps, three code styles

| Map | Where | Shape |
|---|---|---|
| **Bare-link** (`0x44xx`↔`0x84xx`/`0xA4xx`) | one good table in `tl_socmap.py:76-142`, then **re-hard-coded inline 3×** (`overlay.py:42-57`, `bare_overlay.py:32-48`, `tl_poke.py:31-35`) + ~30 literals in `tl39.py` | aperture-pair relocation |
| **eth-chiplet backdoor** (`host = 0x4_0000_0000 + SoC_haddr`) | hard-coded independently in `kr260_eth_bringup.py:69-83`, `kr260_eth_xfer.py:40-57`, `eth_ss_probe.py:13-15`; uses **none** of tl_socmap | affine window+offset |
| **SoC-internal register offsets** (bank `0x2000`, role `+0x080`, …) | genuinely SoC-independent, **already codified** in `python/tidelink/regs.py:14-46` — but every bring-up script **bypasses it** and re-hard-codes offsets | shared |

**Net: base is per-target; offset is shared.** The eth-chiplet vs bare-link
difference is entirely in the *base/access* layer, which is exactly what a clean
abstraction should exploit.

## Recommendation (Option: hybrid, homed in tidelink)

1. **Promote `pynq_host/` into `python/tidelink/host/`** — a pip-installable
   subpackage with `console_scripts` (`tl39`, `kr260-eth-bringup`, `eth-ss-probe`,
   `kr260-eth-xfer`). `setup.py`'s `find_packages()` currently ships `python/` only,
   so `pynq_host/` is copied wholesale and drifts — packaging kills the drift.
2. **Refactor `tl_socmap.py` into a Target registry** (below) and add a
   `KR260EthChipletTarget`. Leave `tl_socmap.py` as a thin re-export shim so the
   lone-file deploy path keeps working.
3. **De-duplicate:** point the 3 inline bare-link copies + the 3 eth scripts at the
   registry; import offsets from `regs.py` (kills 3 map copies + the re-hard-coded
   offsets).
4. **Keep the generic ZynqMP `.sh` deploy/AFI scripts as scripts**, but drive their
   two eth-vs-bare special-cases (`kr260_deploy.sh:64-67` `TARGET`-string match;
   `kr260_afi.sh` bare-link canaries) from the target descriptor instead of string
   matching.
5. **Versioning:** cut a tidelink **tag** at the migration; consumers pin the tag
   (today this design pins `…-288-g84bbd69`, 288 commits past the last tag); sync the
   static `0.1.0` to the tag. Move eth-chiplet-only code off shared `main` behind the
   registry so a compute-chiplet consumer doesn't inherit eth scripts it can't use.

## The address-map abstraction

Every address is `to_host(base + offset)` where **offset is shared** (`regs.py`) and
**base + host-access is per-target**. Both existing shapes are affine maps with a
bounds guard:

```python
class Target:                          # one per SoC/bitstream target
    name: str
    def to_host(self, canonical_addr) -> int: ...      # FAIL-LOUD on out-of-range

Z2Target.to_host(a)              = a                    # identity (today's default)
KR260BareTarget.to_host(a)       = APERTURES relocation # = current tl_socmap
KR260EthChipletTarget.to_host(a) = WINDOW_BASE + a      # + guard to eth_ss_0 window;
                                                        #   peer-0x2F gated on FCSM==4
TARGETS = {"z2":…, "kr260":…, "kr260-eth-chiplet":…}    # the registry
```

- Selection via `TIDELINK_SOC`/`--target` (keep existing aliases). Tools compute
  `target.to_host(regs.TLAPB_BASE + regs.SWI_LANE_STATUS)` — base per-target, offset
  from `regs.py`.
- **N maps injected by:** a built-in registry (the three first-party targets, kept
  auditable in one fail-loud table) + an optional per-design `chiplet_host.toml`
  override for a new SoC (mirrors the `fpga/fpgahub.toml` per-project-manifest
  precedent). Entry-points are the over-engineered future option — not needed now.
- **Non-negotiable:** the abstraction carries each target's **safety guard**, not just
  its base — `KR260BareTarget` keeps tl_socmap's "outside every aperture →
  `SocMapError`"; `KR260EthChipletTarget` keeps "refuse out-of-window" +
  "refuse peer `0x2F` unless FCSM==4". A wrong base on ZynqMP is an unrecoverable AXI
  hang — this is an incremental extraction behind the existing tests, never a
  big-bang rewrite.

## What this buys

Reuse (one importable package, no copy-drift) · map-per-SoC (registry) · versioning
(one tidelink tag) · CI (registry tests run off-board — `tl_socmap` already has zero
pynq/board deps) · ownership (the tidelink team, who already own it de-facto). The new
cross-die test modes ([CROSS_DIE_TEST_BACKLOG.md](CROSS_DIE_TEST_BACKLOG.md) items
1-3) should land behind this descriptor, not as more hard-coded scripts.

### Key paths
- Registry seed: `tidelink/pynq_host/tl_socmap.py:76-142`
- Offset source (already packaged): `tidelink/python/tidelink/regs.py:14-46`, `python/setup.py`
- Inline map copies to collapse: `overlay.py:42-57`, `bare_overlay.py:32-48`, `tl_poke.py:31-35`
- eth-chiplet hard-coded maps: `kr260_eth_bringup.py:69-83`, `kr260_eth_xfer.py:40-57`, `eth_ss_probe.py:13-15`
- Deploy plumbing to parameterize: `kr260_deploy.sh:64-67`, `kr260_afi.sh:44-52`
