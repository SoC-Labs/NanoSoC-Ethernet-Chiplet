# KR260 eth-chiplet — bench bring-up runbook

Operator steps to get the two-board eth-chiplet demo running. Target for the
first session: **M1 — the TideLink link up between two boards** (no ethernet,
no LAN8720 needed). Ethernet (M2) is a later session — see §7.

> **Confidence tags:** **[PROVEN]** = the exact command/flow works on the
> bare-link KR260 or PYNQ-Z2 today. **[FIRST-TIME]** = correct-by-construction
> but never run on this design — expect to iterate. This is first silicon for the
> eth-chiplet: treat every FIRST-TIME step as a debug step, not a formality.

---

## 0. Bill of materials

| Item | Notes |
|---|---|
| 2× KR260 | `kr260_01` / `kr260_02` in fpgahub (10.22.24.159 / .153), both free |
| Straight-through RPi-40 ribbon | J21↔J21. **Strip the +3V3 (1,17) and +5V (2,4) conductors** — a full ribbon back-feeds the regulators |
| 2× 3.3 V SWD probe | ST-Link/DAPLink, on **PMOD2** (pins 1-3) of each board |
| Dev host with the probes | `mapstone-dev` reaches both boards; probes plug into the host running OpenOCD |
| *(M2 only)* 2× Waveshare LAN8720 + 2 host NIC ports | not needed for M1 |

Two bitstreams (built, in `tidelink/imp/fpga/output/`):
`kr260-eth-chiplet/` (die_a, strap 0) and `kr260-eth-chiplet-flip/` (die_b, strap 1).

---

## 1. Cabling — do this first, powered off

1. Ribbon J21↔J21, **straight-through** (`BCM_n ↔ BCM_n`), power rails stripped.
2. **die_a image → one board, die_b (`-flip`) image → the other.** Same image on
   both drives two outputs onto every ribbon lane — never do it.
3. SWD probe on **PMOD2** of each board: `J11=SWCLK(1) J10=SWDIO(2) K13=nRST(3)`,
   GND on pin 5/11, VREF on pin 6/12 (reads 3.3 V). See
   [`KR260_BOARD_WIRING.md`](KR260_BOARD_WIRING.md).

---

## 2. Lease the boards **[PROVEN]**

```bash
fpgahub status                          # kr260_01, kr260_02 must show free
fpgahub lease acquire kr260_01
fpgahub lease acquire kr260_02
```

Everything below runs from the dev host under those leases. If a board is stuck,
`fpgahub board reset <name>` (or the `zynqmp_jtag_por` capability).

---

## 3. Deploy the bitstreams **[FIRST-TIME]**

The KR260s run **plain Ubuntu (no PYNQ)**; deploy is `fpgautil` with a
header-stripped `.bin`, then an AFI PS-master-port width re-poke (needed on every
PL load, not persisted).

Via fpgahub (preferred — one action per board, role-aware):
```bash
fpgahub actions run kr260_01 deploy_kr260_eth_chiplet_pair   # -> die_a image
fpgahub actions run kr260_02 deploy_kr260_eth_chiplet_pair   # -> die_b image
```

Or directly (equivalent; this is what the action calls):
```bash
make -C tidelink/fpga deploy_pair_role SOC=kr260_eth ROLE=die_a \
     KR260_HOST=ubuntu@10.22.24.159 KR260_PASSWORD=<pw>
make -C tidelink/fpga deploy_pair_role SOC=kr260_eth ROLE=die_b \
     KR260_HOST=ubuntu@10.22.24.153 KR260_PASSWORD=<pw>
```

**What to watch:** `fpgautil ... -f Full` returns success and `fpga_manager`
state reads `operating`. If the `.bin` is the wrong flavour the PL load silently
fails — this build uses `bit2bin_zynqmp.py` (header-strip only, **no** byte-swap),
already verified. The AFI re-poke runs after (`kr260_afi.sh`); if PS→PL reads
come back wrong-width later, that step didn't run.

---

## 4. Prove the board is alive — per board **[FIRST-TIME, adapt]**

```bash
sudo TIDELINK_SOC=kr260 python3 tidelink/pynq_host/scripts/kr260_smoke.py \
     --expect-role die_a          # die_b on the other board
```

Confirms the role strap reads back (die_a=0 / die_b=1) and a PL register is
writable through the PS aperture.

> ⚠️ **Address-map caveat.** `kr260_smoke.py`'s map mirrors the **bare-link**
> `kr260-pair-*` BD (the PS reaching TideLink's apertures directly). The
> eth-chiplet BD is different: the PS reaches the SoC through the **`eth_ss_0`
> AHB backdoor at HPM0 `0x8000_0000`**, and the *on-chip M0s* drive TideLink. So
> the smoke script's TideLink-aperture pokes will not match the eth-chiplet
> as-is. Use it to confirm the role strap + a live PL reg; expect the
> deeper pokes to need the eth-chiplet map. The eth-chiplet-native scripts are
> `pynq_host/scripts/kr260_onchip_{smoke,autonomy,soak}.py` — these assume the
> on-chip drive model and are the right starting point.

---

## 5. SWD — halt an M0, read CPUID **[PROVEN flow, FIRST-TIME pins]**

Reuses the PYNQ-Z2 OpenOCD flow unchanged (only the pins moved to PMOD2):
```bash
openocd -f nanosoc-multicore-system/pynq/scripts/openocd/nanosoc_multicore.cfg
#   default SWD_INTERFACE=interface/stlink.cfg; DAPLink -> add
#   -c "set SWD_INTERFACE interface/cmsis-dap.cfg"
```
Success = OpenOCD attaches over SWD, halts each Cortex-M0+, reads CPUID, and can
read/write DMEM through each AP. If it can't attach: check VREF reads 3.3 V on
PMOD2 pin 6, and drop `adapter speed 1000` (long flying-lead SWCLK is the usual
culprit). The board's own micro-USB JTAG cannot do this — it reaches the PL
config TAP only.

---

## 6. Bring the link up — the actual M1 demo **[FIRST-TIME]**

The eth-chiplet's on-chip cores drive TideLink, so use the **on-chip** bring-up
path, not the PS-driven `bringup_pair_converge.sh` (that one is bare-link, where
the PS pokes the TideLink apertures directly):

```bash
# starting point — the on-chip smoke, run per board / as a pair
sudo TIDELINK_SOC=kr260 python3 tidelink/pynq_host/scripts/kr260_onchip_smoke.py ...
```

**Success criterion (same as bare-link):** both dies reach **FCSM = 4
(LINK_IDLE, bilateral)**. Judge link health by FCSM, *not* lane-lock (lane-lock
reads 0x00 after training — expected). Pin die_a as grandmaster by strap; do not
rely on TideChart auto-election (finding G1 — unresolved).

If it doesn't converge, the bare-link `kr260-pair-nptp` image is the fallback
control: it is the smaller, route-clean design that isolates "is the ribbon /
PHY / bench flow good?" from "is the eth-chiplet SoC good?". **Bench the bare
link first if anything is uncertain.**

---

## 7. Ethernet (M2) — separate session, do not attempt in M1

Blocked on three things, none needed for the link demo above:
1. **Hub topology** — a PL-ethernet segment per KR260 with a unique `pl_mac` per
   die. See [`KR260_LAN8720_FPGAHUB_PLAN.md`](KR260_LAN8720_FPGAHUB_PLAN.md).
2. **Firmware** — the eth-chiplet has no ethernet firmware (MDIO bring-up, MAC
   out of internal loopback, PicoTCP).
3. **The module** — Waveshare LAN8720 into PMOD1, TX1 lead to PMOD2 pin 4.
   Cheap early check: fit it and cable it — the PHY **link LED** alone proves the
   RMII pinout and the 3.3 V bank, before any firmware.

---

## 8. Known state / caveats going in

- **First silicon.** Neither the eth-chiplet nor the bare-link KR260 image has
  ever been on a bench. Expect PHY-eye / deskew surprises at the ~3 MHz link rate.
- **Timing.** Both dies build. The TideLink RX has residual setup (−2.9/−3.3 ns,
  4 endpoints) — but it is a **runtime-calibrated** forwarded-clock interface
  (TideLink's autonomous winscan finds the capture window), and the bare-link
  ships with the same-shape numbers and works. The ethernet clock domain is now
  properly constrained. Not a blocker for M1; watch it if the link is flaky.
- **G1 (grandmaster).** DEVICE_CLASS is not strapped per die yet — pin die_a by
  `role_strap_i`, don't rely on auto-election.
- **UART.** Currently on spare J21 pins; the tidier EMIO→`/dev/ttyPS1` path is
  not built yet. SWD works without it.

---

## 9. Fast-path checklist

```
[ ] ribbon straight-through, power rails stripped, die_a<->die_b images not swapped
[ ] SWD probe VREF reads 3.3 V on PMOD2 pin 6
[ ] fpgahub lease acquire kr260_01 && kr260_02
[ ] deploy die_a -> kr260_01, die_b -> kr260_02 ; fpga_manager = operating
[ ] kr260_smoke --expect-role : role strap + live PL reg OK
[ ] openocd attaches, halts an M0, reads CPUID
[ ] on-chip bring-up -> FCSM=4 bilateral on both dies   <-- M1 done
```
