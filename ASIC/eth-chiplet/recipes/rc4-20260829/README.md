# rc4-20260829 — the recipe

The four steps that turn a routed database into the submitted stream. These lived
only under `ASIC/eth-chiplet/build/`, which is gitignored (`git ls-files` there
returns 0), so before this commit rc4 could not be rebuilt from a clean clone:
they existed as single deletable copies on one disk.

    stream   nanosoc_eth_chiplet_pads_rc4_logo.gds
    md5      6b0833c4216bdb683ed2427cd0deba75
    sha256   73fad49a087d390741bbb62f303fcca504adbc2c4b564e451364fd4d9f9cfd19
    size     303,996,534 bytes
    store    ethchip-nanosoc_eth_chiplet_pads/rc4-20260829

## Order

1. `setupfix1_innovus.eco` — applied to rc3fix's routed database. **This file is
   what makes rc4 rc4:** three cell resizes that close setup. Verified against
   both netlists — 207,445 instances each, 0 added, 0 removed, exactly 3 differ.
2. `restream.sh` — writes the signoff stream from the ECO'd database.
3. `logo_merge.sh` — merges the chip logo, producing the submitted stream.

`restream.sh` and `logo_merge.sh` are the originals with site and build paths
replaced by `${REPO_ROOT}`, `${RUN_DIR}`, `${MEM_BASE}` and `${INNOVUS}`; nothing
else was changed. `setupfix1_innovus.eco` is byte-identical in its directives —
only Tempus' provenance comments were redacted, and that was checked with a diff
over the non-comment lines.

## Two inputs are NOT here, deliberately

**The GDS layer map.** `gdsout.stream.map` is derived from the PDK at build time
by `ASIC/genus-innovus/scripts/gdsmap_derive.py` into a gitignored directory. It
is vendor-derived collateral and this repository is public — the vendor guard
rejects it, correctly. Regenerate it; do not copy it in.

**The crossbar RTL.** `tidelink/deps/xhb500/generated` is ~195 MB of Arm-generated
interconnect, gitignored at `tidelink/.gitignore:72` and untracked deliberately.
It cannot be published here. The generator *inputs* ARE tracked —
`tidelink/deps/xhb500/configs/*.cfg`, 8 KB — so anyone with the Arm licence can
regenerate it. Without it, synthesis fails to elaborate `u_xhb_sub`, which is
exactly how this gap was found (see `docs/tapeout/66-rc5-flow-findings.md`, F5).

## What this recipe does not give you

Reproducing the *bytes* additionally needs the routed database rc4 was ECO'd
from, which is not in git either. This recipe reproduces the **procedure**, and
lets a reader see precisely what was done to produce the submission. The stream
itself lives in the artifact store, where the raw md5 above is a retrievable
property.
