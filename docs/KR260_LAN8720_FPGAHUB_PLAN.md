# LAN8720 on KR260 — fpgahub topology work

**Audience:** the agent/operator modifying the fpgahub topology.
**Goal:** make the nanoSoC's ethernet (LAN8720 RMII PHY) usable on the two
KR260 boards, the way it already works on the PYNQ-Z2 pair.

> **Scope split.** The FPGA side is **done** (§1). This document is about the
> **hub-side topology + host network** work (§3), which is the blocker. §5 lists
> what is still missing beyond the hub so nobody assumes the hub is the last step.

---

## 1. What is already done (FPGA side — no action needed)

| Item | State |
|---|---|
| RMII + MDIO wired out of the SoC (tie-offs removed, IP wrapper → BD → board wrapper → XDC) | **done** |
| MDIO IOBUF (`T = ~md_padoe_o`, active-high OE per OpenCores `eth_top`) | **done** |
| Pin constraints: module on **PMOD1**, TX1 overflow on **PMOD2 pin 4 (K12)** | **done** |
| 50 MHz `REF_CLK`: `create_clock` + `CLOCK_DEDICATED_ROUTE FALSE` (non-CCIO pin) | **done** |
| Both bitstreams build (die_a + die_b), all RMII pins place at LVCMOS33 | **done** |
| Bonded IOB 25 → 34 (+9 = the RMII/MDIO signals) — proves it reaches the netlist | **verified** |

Pinout is the **fixed Waveshare module order**, ported verbatim from the working
Z2 build (`nanosoc-multicore-system/pynq/targets/pynq-z2/nanosoc_multicore.xdc`):

```
Pmod pin: 1=RX1  2=TX0  3=CRS_DV  4=MDC  7=TX_EN  8=RX0  9=MDIO  10=REF_CLK
overflow: TX1  ->  PMOD2 pin 4 (K12)
```

See [`KR260_BOARD_WIRING.md`](KR260_BOARD_WIRING.md) for the full ball map and
the 1.8 V/3.3 V PMOD split (PMOD4 is 1.8 V — keep the PHY off it).

**Not yet validated on hardware.** The pins place and route; no LAN8720 has been
physically fitted or driven.

---

## 2. How the hub models PL ethernet (the mental model)

This was the key thing to establish, and it is **already fully modelled** in
fpgahub — nothing new needs inventing.

**Each ethernet segment is its own board entry.** On the Z2 pair, one physical
board appears twice:

| Entry | Net IF | Board IP | Capability | What it is |
|---|---|---|---|---|
| `pynq_z2_01_ps` | `pynq_z2_01_ps` | 192.168.2.101 | `ethernet_ps_gem` | Zynq PS GEM (Linux) |
| `pynq_z2_01_pl` | `pynq_z2_01_pl` | 192.168.1.101 | **`ethernet_phy_lan8720`** | **the nanoSoC via LAN8720** |

Each `_pl` link gets its **own /24** (…1.x, …3.x, …5.x across the four boards),
i.e. a dedicated host-side NIC per PL link.

**The board schema already has a PL-MAC field** (`fpgahub/config.py`,
`class BoardNetwork`):

```python
host_ip:   IPv4Interface   # host-side NIC address/prefix
board_ip:  IPv4Address     # the endpoint's IP
board_mac: str             # Zynq PS-GEM MAC — dnsmasq static leases + identity
pl_mac:    str | None      # PL-side PicoTCP MAC — the soft-MAC the CM0+ firmware
                           # programs into the OpenCores ethernet controller.
                           # Rendered into the firmware binary at build time via
                           # the BOARD_MAC make-var. None = compiled-in default.
hostname:  str
dns_search: str = "fpga"
```

So the identity chain is:

```
fpgahub  boards.<X>.network.pl_mac
   -> BOARD_MAC= make-var
   -> -DBOARD_MAC_1..6
   -> firmware (e.g. ethernet-subsystem-ahb/firmware/eth_app/udp_echo/udp_echo.c)
   -> programmed into the OpenCores MAC
```

**Capabilities are free-form, operator-curated tags.** The daemon gates dispatch
of actions declaring `requires_capabilities`; an **empty list is permissive**.
`ethernet_phy_lan8720` is already used as a real gate by
`nanosoc-multicore-system/ethernet-subsystem-ahb/fpga/fpgahub.toml`
(`flash_firmware_tftp`, `test_quick`, `ci_full`).

---

## 3. The work — hub topology

### 3.1 Current KR260 state

```
kr260_01   mapstone-dev  hub 1-1.2.3  net kr260_01_eth  10.22.24.159  kr260-01
kr260_02   mapstone-dev  hub 1-1.2.2  net kr260_02_eth  10.22.24.153  kr260-02
capabilities (both): zynqmp_jtag_por, jtag_ftdi, swd_stlink, uart_console
```

One entry each = **management/PS ethernet only** (lab 10.22.24.x). There is **no
PL-side ethernet segment**, no `pl_mac`, and no `ethernet_phy_lan8720`.

### 3.2 What to add

**(a) A PL-ethernet board entry per KR260**, mirroring the Z2 `_pl` pattern.
Suggested `kr260_01_pl` / `kr260_02_pl`:

```toml
[boards.kr260_01_pl]
server      = "mapstone-dev"
hub_path    = "1-1.2.3"          # same physical board as kr260_01
description = "KR260-01 nanoSoC PL ethernet via LAN8720 on PMOD1"
capabilities = ["ethernet_phy_lan8720"]

[boards.kr260_01_pl.naming]
net_name = "kr260_01_pl"          # <= IFNAMSIZ, no illegal chars

[boards.kr260_01_pl.network]
host_ip   = "192.168.20.1/24"     # host NIC — pick a FREE /24
board_ip  = "192.168.20.101"      # the nanoSoC's IP
board_mac = "<PS-GEM MAC of KR260-01>"
pl_mac    = "02:00:5e:00:20:01"   # MUST be unique per die — see warning below
hostname  = "kr260-01-pl"
```

…and the same for `kr260_02_pl` on a **different** /24 (e.g. `192.168.21.0/24`,
`pl_mac` `02:00:5e:00:21:01`).

**(b) Add the capability to the existing entries too** if you want ethernet
actions dispatchable against `kr260_01`/`kr260_02` themselves rather than only
the `_pl` entries. Decide which entry the actions target and tag that one.

**(c) Apply:**
```bash
fpgahub network apply     # systemd-networkd + dnsmasq + resolved drop-ins
fpgahub nftables apply    # per-board forward-chain rules
```

### 3.3 ⚠️ Two-board hazards specific to this demo

1. **`pl_mac` must differ between die_a and die_b.** Both boards run the *same
   SoC image*; if `pl_mac` is unset the firmware falls back to its **compiled-in
   default**, so both nanoSoCs would appear on the network with an **identical
   MAC**. On a single-board bench that is invisible; with the pair it is a
   silent, confusing failure. Set it explicitly on both.
2. **`board_ip` must differ**, on separate subnets, matching the Z2 convention.
3. Use locally-administered MACs (`02:` prefix) as the Z2 does.

### 3.4 Physical prerequisite to confirm

Each `_pl` segment needs a **dedicated host-side NIC/port on mapstone-dev**, as
the Z2s have. Two KR260 PL links = two more ports. **Confirm these exist before
allocating subnets** — this is the most likely hard blocker, and it is a
lab-hardware question, not a config one.

---

## 4. Validation ladder (cheapest first)

1. `fpgahub board list` — the `_pl` entries appear with `ethernet_phy_lan8720`.
2. `fpgahub network apply` clean; host NIC has `host_ip`; `ip link` shows `net_name`.
3. LAN8720 module fitted to PMOD1 (+ TX1 lead to PMOD2 pin 4); PHY link LED on
   when cabled to the host port — **this alone proves the RMII pinout and the
   3.3 V bank**, before any firmware.
4. Load the eth-chiplet bitstream, run firmware, `ping <board_ip>` from the host.
5. MDIO: PHY ID read back over MDIO (catches a mis-wired MDIO/MDC or a PHYAD
   strap problem — see the strap-pin note in the wiring doc).

---

## 5. Not the hub's job — still outstanding

Do not assume ethernet works once the topology lands:

- **Firmware.** `udp_echo` belongs to the standalone `ethernet-subsystem-ahb`
  project. The **eth-chiplet has no ethernet firmware yet** — it needs MDIO PHY
  bring-up, the MAC taken **out of internal loopback** (M1 posture), and a
  PicoTCP stack instance.
- **No ethernet actions in the tidelink manifest.** `tidelink/fpga/fpgahub.toml`
  now has eth-chiplet build/deploy actions, but nothing ethernet-specific. The
  `ethernet-subsystem-ahb` manifest (§2) is the template to copy.
- **`IOB TRUE` on the RMII TX pins** is deliberately *not* replicated from the
  Z2 — TideLink's `pad_rx` needed `IOB FALSE` on this device. Verify IOB packing
  on the KR260 HD bank before adding it.
- **REF_CLK sourcing.** Currently PHY-sourced (`REF_CLK_OUT`) into a non-CCIO
  pin, waived with `CLOCK_DEDICATED_ROUTE FALSE`, matching the Z2 at V12. If the
  eye is poor on the bench, the alternative is FPGA-sourced 50 MHz (needs a
  module strapped for REF_CLK-in).
- **Timing.** The eth-chiplet builds with residual setup (−2.9/−3.3 ns) and a
  forwarded-clock TX hold (−22 ns) that is **shared with the bare-link target**
  and pre-existing. Not ethernet-related, but it gates trusting any bench result.

---

## 6. One-line summary for the topology agent

> Add a **PL-ethernet board entry per KR260** (`kr260_0{1,2}_pl`) mirroring the
> Z2 `_pl` pattern — own `/24`, own `net_name`, `capabilities =
> ["ethernet_phy_lan8720"]`, and a **unique `pl_mac` per die** (this is the MAC
> the nanoSoC firmware programs into the OpenCores controller via `BOARD_MAC`).
> Then `fpgahub network apply` + `fpgahub nftables apply`. First confirm two
> spare host NIC ports exist on mapstone-dev.

### References
- Board/network schema: `fpgahub/config.py` — `BoardNetwork`, `capabilities`.
- Working LAN8720 precedent: `nanosoc-multicore-system/ethernet-subsystem-ahb/fpga/fpgahub.toml`.
- `BOARD_MAC` consumer: `.../firmware/eth_app/udp_echo/udp_echo.c`.
- Z2 RMII pinout: `nanosoc-multicore-system/pynq/targets/pynq-z2/nanosoc_multicore.xdc`.
- KR260 pin/voltage map: [`KR260_BOARD_WIRING.md`](KR260_BOARD_WIRING.md).
