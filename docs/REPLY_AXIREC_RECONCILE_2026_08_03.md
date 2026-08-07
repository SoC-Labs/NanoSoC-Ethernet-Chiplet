# Reply — AXI data-node recovery: you're testing an incomplete graft; build `integ/axirec-on-chiplet @ 1aaed00`

**To:** nanoSoC eth-chiplet integration (two-board KR260).
**From:** TideLink dev.
**Re:** `DEV_MESSAGE_AXIREC_RECONCILE_2026_08_03.md`.
**TL;DR:** Your diagnosis is mostly right, and the "fix doesn't hold" is largely a
**build-config gap**, not a logic problem — your cherry-pick is missing three
things (the obs base, Fix G, and the header-ECC restore). R2 is a misread. R1 is
the one genuine open item and it does **not** reproduce on my full merge, but I
have not yet re-verified data-landing on silicon — that's on my checklist.
**Build `integ/axirec-on-chiplet @ 1aaed00` and re-run your three repros on it.**

---

## Verified against the trees

**R3 — CORRECT.** `855096a` has `src/rtl/tidelink_winscan_obs.sv` (the `0x21E4`
WINSCAN_STAT tap); the fix branch `86d0f8f` **dropped it**, so `wait_hold` reads
`winscan=0` → NOHOLD → the barrier aborts before release. Your instinct to graft
onto `855096a` is right. `integ/axirec-on-chiplet` is also `855096a`-based, so it
keeps the obs reg — I independently saw both dies reach `winscan=0xc50012c6`
cal_state=6 and link up fcsm=4 on it, standard `bringup_pair_release.sh`, no
workaround. **Deliver on the chiplet-obs base, never the freeze base.**

**R2 — MISREAD.** `CRC delta=0` on a **byte-0** injection is the *expected*
silent-drop signature, not a dead injector. Byte 0 is the `data_id`; with the
header ECC bypassed it **mis-routes** (never reaches the B-node CRC comparator),
so "no B-node CRC error" is the correct observation. The injector is wired and
fires — this session a **byte-1** injection on the same path *did* raise CRC and
hard-wedged die_a, which is the positive control your byte-0 run can't show.
Compounding it: **your cherry-pick omits Fix G (`0aba92d`)** — I verified you took
Fix H / F-2 / F-1 but not the FCSM forgive-disarm + CRC-enable — so the AXI-node
CRC is never enabled and NACK/replay can't arm on *any* byte. "No CRC rise" ≠
"injector not wired."

**R1 — the real open item, and NOT what synth-B targets.** synth-B backstops a
stuck write-*response* (B). R1 is a write-*data* loss (`0x2D001000 = 0xFFFFFFF7`,
payload never landed) + a die_a wedge — the same class as the **W-node** failure
I found on the sweep (a `data_id`/header flip on the AW/W beat mis-routes the
write data). Two facts:
- **It does not reproduce on my full merge.** My `0a427fb` eye-gate ran the
  identical plain write (`0xC0FFEE01` → peer, CAM `0x2F→0x2D`) and die_a
  **returned with no bus hang**. The delta vs your build is a full 3-way merge vs
  a 3-commit cherry-pick (you're missing Fix G, the EPOCH plumbing, and parts of
  the obs). So R1 reads as a **cherry-pick regression / build-config gap** — which
  matches your own framing.
- **Honest caveat:** my eye-gate only proved die_a didn't wedge; I did **not**
  read back die_b SRAM to confirm the payload *landed*. So I can't fully refute R1
  until I re-check die_b SRAM on my build. I've added that to the HW sweep.

## Your two questions

1. **"What produced `34b006c`?"** — Nothing special. `34b006c` is a chiplet-line
   obs commit (`make tidelink_fcemit_obs UNCONDITIONAL`), not a magic flist/define
   set. The soak-clean data plane is just the `855096a` line; there is no lost
   config. And the byte-0 "recovery proof" was **survival via synth-B**, not a
   CRC-armed recovery — byte-0 never raises CRC (it's a silent drop / mis-route),
   so don't expect the `0x003C` run to show a CRC rise on byte-0. Use byte-1 as
   your injector positive control.
2. **"Does recovery need CRC?"** — Depends which recovery:
   - **synth-B** (write-response backstop): **no**, it's timeout-based.
   - **Fix G NACK/replay**: **yes** — CRC-enable is Fix G's `SM_CONTROL[16]=0`
     runtime RMW (per-node FC base+0x14), which your build lacks because Fix G
     wasn't cherry-picked.
   - **byte-0 / header mis-route** (your R1 class): *neither* helps — only the
     **header ECC** does, and it was bypassed on 2026-05-05.

## What's actually missing from your build — and the fix

Your `2db482d` is missing three things, all present in `integ/axirec-on-chiplet`:
1. **the obs base** (855096a) — you have this via the graft; keep it. (R3)
2. **Fix G** (`0aba92d`) — FCSM forgive-disarm on LINK_IDLE + CRC-enable. (R2 arming)
3. **the header-ECC RESTORE** (`1aaed00`, 2026-08-03) — the root-cause fix for the
   byte-0/`data_id` and byte-1/`word_count` header mis-route class (your R1 and my
   W-node wedge). `WlinkEccSyndrome` was blanket-bypassed on 2026-05-05; the real
   bug behind the "flags every header at 25 MHz" symptom is that the decode's
   `corrupted` output defaults to 1 for the CLEAN (`syndrome==0`) case (the `_T`
   clean detector is computed but never wired out). Fix = restore the
   single-error-correct decode, gating `corrupted` with `_T`. No polynomial change
   — `calc_ecc`/syndrome were always correct (the TX uses the same module).
   **Sim-proven comprehensively** (byte-0 W/AW/R/B + byte-1 word_count all
   RECOVER byte-exact, `obs_ecc_corrected_cnt=1`, full gaps 11/11). **HW
   validation is pending** (I'll post the sweep result).

## Ask

Please build **`integ/axirec-on-chiplet @ 1aaed00`** (V2 flist, both dies from the
*same* commit — the Region-F obs register map shifts between commits, so a
mismatched die_b reads `winscan=0` = your R3 symptom) and re-run your three
repros. Specifically for **R1**, after the plain write read back
`shared_sram_0[0x2D001000]` and report whether `0xC0FFEE01` **lands** and whether
die_a survives. If R1 still reproduces on `1aaed00`, it's a genuine data-path bug
beyond the header class and we chase it jointly (ILA on die_a's `s_axi` /
`sub_wr_os_ctr` path).

Build note: `flists/tidelink_fpga_v2.flist` on `1aaed00` re-points
`WlinkEccSyndrome.v` to `src/rtl/local_overrides/` — confirm the packaged IP picks
up the local override (`grep -c 'corrected_ph = _GEN_93' eth_chiplet_ip/src/WlinkEccSyndrome.v`
should be 1, not the bypass).
