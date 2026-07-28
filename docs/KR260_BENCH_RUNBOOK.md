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
`fpgahub board reset <name>` (JTAG POR via the `kr260_jtag_por` plugin).

> **Recovery gotcha (verified 2026-07-27).** `fpgahub board reset` and the other
> per-board endpoints **404 from some client hosts** (a CLI/daemon route skew) but
> work when run **on `mapstone-dev`** (where the daemon lives). If a reset 404s,
> ssh to `mapstone-dev` and run it there:
> `ssh mapstone-dev 'fpgahub board reset kr260_01 --yes'` → issues the JTAG POR
> (`method=default plugin=kr260_jtag_por`, "POR issued … via local (cable …)").
> The board pings again ~10 s later. The collection endpoints (`status`, `board
> list`, `lease …`) work from any host; only the `board/<name>/…` routes need this.

---

## 3. Deploy the bitstreams **[PROVEN on silicon 2026-07-27]**

Both dies now deploy clean, end-to-end, on the real boards: **die_a → kr260_01
and die_b → kr260_02 both reach `fpga_manager=operating`**, AFI widths read
32-bit on both PS master ports, and the full post-load SSH round-trip completes
(proving the PS AXI bus is healthy, not wedged). The `.bin` flavour, the mirrored
staging layout, and the AFI re-poke are all validated. What is *not* yet proven
is anything **past** the load — see the wedge hazard below and §4–§6.

The KR260s run **plain Ubuntu (no PYNQ)**; deploy is `fpgautil` with a
header-stripped `.bin`, then an AFI PS-master-port width re-poke (needed on every
PL load, not persisted).

> **🔴 WEDGE HAZARD — the defining eth-chiplet difference (learned the hard way).**
> On the eth-chiplet the PS can reach **only** the SoC's AHB via the `eth_ss_0`
> backdoor at HPM0 `0x8000_0000`. **Any PS read of a PL address the SoC does not
> decode hangs the ZynqMP PS AXI bus with no timeout** — the board goes to 100 %
> packet loss and only a **JTAG POR** recovers it (see §2 recovery gotcha). This
> is not hypothetical: the bare-link AFI *canaries* (`0x8403_xxxx`) wedged
> kr260_01 on first load. The deploy now **auto-skips those canaries** for
> `kr260-eth-chiplet*` targets (`KR260_AFI_NO_CANARY=1`, threaded by
> `kr260_deploy.sh`); the width fix still runs. **Do not** point any bare-link
> host script (`kr260_smoke.py`, `bringup_pair_converge.sh`, raw `devmem` at
> `0x8403_xxxx`/`0x8404_xxxx`) at the eth-chiplet — they read undecoded addresses
> and will re-wedge. Only touch addresses inside the `eth_ss_0` window that the
> SoC AHB actually decodes.

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

## 4. Prove the board is alive — per board **[eth-chiplet-native, PROVEN-safe]**

The eth-chiplet PS reaches the SoC ONLY through the `eth_ss_0` AHB backdoor,
which on the built bitstream is the **HPM0_FPD high aperture at PS phys
`0x4_0000_0000`** (`tidelink.hwh:4112`), **NOT `0x8000_0000`**. A SoC-internal
address `A` is reached from the PS at `0x4_0000_0000 + A`. Two SAFE, read-only
checks — they touch only combinational boot ROM / RO APB registers on the
free-running system clock, so they cannot wedge the bus the way a bare-link poke
does (the SoC AHB matrix's default slave terminates any in-window miss with
SLVERR, never a hang):

```bash
# a) boot-ROM aliveness: proves the PS->SoC backdoor delivers into the live SoC.
sudo python3 ~/td/scripts/eth_ss_probe.py          # expect PASS: 0x18003c00 / 0x08000189 / ...

# b) TideLink config-plane status (read-only): effective role + calibration/FCSM.
sudo python3 ~/td/scripts/kr260_eth_bringup.py --status
```

> ⚠️ **NEVER run the bare-link `kr260_smoke.py` / `kr260_onchip_*.py` / `tl39.py`
> on the eth-chiplet.** Their map pokes `0x8403_xxxx` / `0x8000_0000`, which are
> UNDECODED here — the read hangs the PS AXI bus with no timeout (JTAG-POR-only
> recovery; this wedged kr260_01 on first bring-up, 2026-07-27). The
> eth-chiplet-native tools above address the SoC through the `0x4_2E03_xxxx`
> backdoor instead, and refuse any out-of-window address.

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

## 6. Bring the link up — the actual M1 demo **[eth-chiplet-native]**

The link is brought up **directly from each board's PS over the `eth_ss_0`
backdoor** — no firmware, no SWD probe. `D2D_PORT.md §3` is explicit: the
PS-facing masters can drive "role strap, calibration poll, training drop … with
no CPU firmware running." `kr260_eth_bringup.py` replays the exact register
recipe proven in `verif/g2_soc_pair/test_g2_soc_pair.py`, addressed through the
`0x4_2E03_xxxx` backdoor. Run on **BOTH boards together** (die_a=master,
die_b=slave); each die's `cal_done` only asserts once the peer is also up over
the ribbon, so the two independent runs self-synchronise:

```bash
# board 1 (die_a image) and board 2 (die_b image) — start both, ideally together:
sudo python3 ~/td/scripts/kr260_eth_bringup.py --bringup --role die_a   # board 1
sudo python3 ~/td/scripts/kr260_eth_bringup.py --bringup --role die_b   # board 2
```

**Success criterion:** both dies reach **FCSM = 4 (LINK_IDLE, bilateral)** with
`calibration_done = 1`. Judge link health by FCSM, *not* lane-lock (lane-lock
reads 0x00 after training — expected). die_a is pinned grandmaster by
`--role die_a` (ROLE_CFG master-lock); do not rely on auto-election (G1).

> The on-chip-firmware path (an M0 app loaded over SWD that runs the same
> recipe) is the autonomous alternative, but is **not needed** for the bench
> demo — the PS-side path above is simpler and reuses no SWD. Both cores reach
> the D2D window (`D2D_PORT.md §3`), so a firmware port is a later option.
>
> **This tool is correct-by-construction from the sim but has NOT run on
> silicon.** cal_done/FCSM depend on the physical ribbon + the runtime winscan
> (first silicon — see §8); treat the first run as a debug step.

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
[x] deploy die_a -> kr260_01, die_b -> kr260_02 ; fpga_manager = operating   <-- PROVEN 2026-07-27
[ ] eth_ss_probe.py -> PASS (boot ROM 0x18003c00...) : PS->SoC backdoor alive
[ ] kr260_eth_bringup.py --status : TideLink config plane reads back
[ ] ribbon seated; run kr260_eth_bringup.py --bringup on BOTH boards together
[ ] both dies -> FCSM=4 (LINK_IDLE) + cal_done=1   <-- M1 done
```

> **Do NOT run `kr260_smoke.py` / `kr260_onchip_*.py` / `tl39.py` on the
> eth-chiplet** — their map is bare-link and pokes undecoded `0x8403_xxxx` /
> `0x8000_0000` that wedge the PS (see §3/§4). Use the eth-chiplet-native
> `eth_ss_probe.py` (§4) and `kr260_eth_bringup.py` (§4/§6), which address the
> SoC through the `0x4_2E03_xxxx` backdoor and refuse any out-of-window address.
> SWD (§5) is now optional — the PS-side bring-up needs no probe.
