# eth-chiplet-native rig tools

Written 2026-08-24. These address the SoC **only** through the `eth_ss_0` backdoor
(PS phys `0x4_0000_0000` + SoC address) and refuse to touch the bare-link
`0x8403_xxxx` / `0x8000_0000` family, which is undecoded on this design and wedges
the ZynqMP PS AXI bus with no timeout (JTAG-POR-only recovery).

| Tool | What it does | Safe? |
|---|---|---|
| `ethmac_probe.py` | Reads the ETHMAC register plane and checks 4 independent reset values (MODER/IPGT/TX_BD_NUM/MIIMODER). Exits non-zero on all-zeroes or all-ones rather than reporting a cheerful "alive". | read-only |
| `mdio_scan2.py` | Is a PHY fitted? MDIO sweep with **stability, uniqueness and plausibility** tests. | writes only ETHMAC MDIO regs |
| `rd21f8_eth.py` | Reads the read-path sticky witness at SoC `0x2E0321F8` (marker `0xB5`). | read-only |

## Why `rd21f8_eth.py` exists

`~/td/rd21f8.py`, staged on the boards, reads **`0x840321F8`** — the bare-link
address. Running it on an eth-chiplet board wedges it. This is the same register
via the correct window.

Note `health_snapshot.py` reads `0x21E0` (marker `0xAD`) and reports `HEALTHY`
through a completely dead read path. The read-path stickies are at `0x21F8`
(marker `0xB5`): bit[9] `sub_err_sticky`, bit[10] `xhb_stall_stuck_sticky`,
bit[0] `hreadyout_raw`. **Check the top byte is `0xB5` before trusting any bit.**
Never read `0x21AC`/`0x21B0`/`0x21B4` — they hard-stall the CPU.

## Discrimination note

`mdio_scan2.py` replaced a v1 that rejected only `0x0000`/`0xFFFF` and therefore
reported "PHY FOUND" at 7 consecutive addresses on a **floating** MDIO line. A
presence test that cannot distinguish a device from an undriven wire is not a
test. The v2 checks are: same value across 4 reads; a real PHY occupies one
address not most of the bus; and the OUI must be recognisable.

## Measured 2026-08-24, kr260_02 (die_b, 08-21 V2)

- ETHMAC register plane **ALIVE** — MODER `0xA000`, IPGT `0x12`, TX_BD_NUM `0x40`,
  MIIMODER `0x64` all exact. `PACKETLEN 0x00400600` = MINFL 64 / MAXFL 1536, correct.
  First ETHMAC access on this vehicle; no wedge.
- **MDIO does not work, and the cause is NOT a missing PHY.** A LAN8720 IS fitted
  to PMOD1 on both boards (LEDs lit, operator-confirmed). Measured:
  - MDC runs at **~230 kHz** (BUSY high ~279 us for a 64-MDC-period frame),
    well within the LAN8720 2.5 MHz maximum. CLKDIV=100.
  - MDIO transactions **are driven**: `MIISTATUS.BUSY` asserts and clears.
  - The MAC reports every read **valid** — `NVALID` never sets.
  - `MIIRX_DATA` is **stable when quiescent** (`0xF81F`), so this is not a
    free-running-register artifact.
  - Yet all 32 addresses return incoherent, unstable, rotating bit patterns.
  So: management interface electrically active and correctly timed, no PHY
  answering coherently. **Unresolved — needs bench access.**
  Leading candidate: MDIO pull-up strength. The XDC uses the FPGA's *internal*
  `PULLUP` (weak, ~10k+) while `docs/design/PIN_MAP.md` records that MDIO needs an
  **external** pull-up (typically 1.5-4.7k). Marginal edges on PMOD wiring would
  give exactly coherent-but-wrong data. Other candidates: MDC/MDIO not reaching
  the module (this design already had to overflow TX1 to PMOD2.4, so the pin map
  is non-obvious), or the PHY strapped/held differently than assumed.
- Not yet established: whether `rmii_ref_clk` (pin B11, PMOD1.10 = the PHY's
  nINT/REFCLKO) is actually toggling. The LAN8720 only drives it in REF_CLK_OUT
  mode; if the module is strapped REF_CLK_IN, the MAC datapath has no clock.
  Check with a scope before attributing any loopback failure to the MAC.

## Before any backdoor access

Compare board boot time against bitstream load time. A `fpgautil` PL load does
**not** survive a reboot, and `fpga_manager` reads `operating` regardless of whose
design is loaded.

## MAC internal loopback — measured 2026-08-24, kr260_02

`mac_loopback.py` uses `MODER.LOOPBK`, so it needs **no PHY access** and is
independent of the MDIO defect. It also works as a remote clock detector: the MAC
TX/RX engines run on `mii_tx_clk`/`mii_rx_clk`, derived /2 from `rmii_ref_clk`.

Result: **transmit engine never started.**

- `MODER` written and read back exactly `0x0000A4A3`; `TX_BD_NUM` took; TX descriptor
  armed at `0x0040B800` — register plane completely healthy.
- After 2 s: `INT_SOURCE = 0x00000000` (no TXB/TXE/RXB/RXE).
- **TX descriptor READY bit still set** — the MAC never consumed it.
- RX buffer poisoned to zeros first, still zeros: a stale-data false pass was impossible.

A descriptor that is never consumed means no clock, not bad data.

### Unified root cause (leading)

The LAN8720 modules are the same known-good ones used on the PYNQ-Z2, so they are
strapped REF_CLK_OUT and the parts are fine. Two symptoms remain — MDIO driven at a
correct 230 kHz with no answer, and a TX engine with no clock. **Both follow from
PMOD1 signals not reaching the module**: MDC/MDIO never arrive at the PHY, and the
PHY's REF_CLK never arrives at the die. One wiring-level fault beats two independent ones.

Prime suspect: the KR260 **PMOD-pin-to-package-ball** mapping in the XDC. The PMOD
*pin* map is identical to the working Z2 build (pin4 MDC, pin9 MDIO, pin10 REF_CLK),
but the package balls necessarily differ between devices and could not be verified —
no AMD board file or KR260 schematic is on this host, and the repo's XDC and
`docs/bringup/KR260_BOARD_WIRING.md` merely agree with each other. Second suspect:
PMOD1 bank power/enable.

**Check with a scope:** PMOD1.10 should carry 50 MHz; PMOD1.4 should show MDC bursts
while `mdio_diag.py` runs. Both dead at the connector => the ball mapping is wrong.

### Note for the ASIC

Nothing here indicts the MAC. Register plane exact, descriptors accepted, MDIO engine
correctly timed at 230 kHz. This is an FPGA board/XDC integration fault.

### Separate real defect found in the same diff

The KR260 XDC **dropped `IOB TRUE`** from the RMII TX pins. The Z2 XDC documents it as
load-bearing — it packs the `rmii_to_mii` TX launch flop into the pad (OLOGIC), and the
comment records validation over 744k frames with the eye scoped on `rmii_ref_clk`.
Restore it before trusting any TX result.

## bit[10] is NOT a wedge indicator — corrected 2026-08-24

`xhb_stall_stuck_sticky` was being read as a deadlock witness. A peer session's
run on the **pair-onchip** vehicle set bit[10] on BOTH dies in BOTH arms
(`0xB5000001 -> 0xB5000421`) while every cross-die read returned **byte-exact**
and a 5000-packet soak was clean. So bit[10] fires during traffic that completes
perfectly.

**Read bit[10] as "hazard-list pressure occurred", never as "deadlock".**

The discriminating signature for the read-park wedge is:
  - **bit[9] `sub_err_sticky` 0 -> 1** (read backstop fired: read abandoned locally), AND
  - **bit[0] `hreadyout_raw` 1 -> 0 AND STAYING 0** (port did not recover)
Neither of those appeared in the healthy pair-onchip run. bit[10] appeared in both.
