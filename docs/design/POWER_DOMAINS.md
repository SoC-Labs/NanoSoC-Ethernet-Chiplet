# D2D power domains — analysis and recommendation

`PHYSICAL_HANDOFF.md §5` lists "add the D2D power domain" as an open item. This is
the analysis behind that decision. It is **analysis + a recommendation, not a UPF
file** — the domain cut is ultimately a `[TEAM]` / PDK decision, but the RTL
constrains it in ways recorded here.

Read `RESET_ORDERING.md` first — the reset regimes and the source-synchronous
clock story drive everything below.

## Recommendation up front

**For the first tapeout: put the D2D link in the SAME power domain as the SoC
core (one domain), and defer an independently-powerable link domain.** Two RTL
facts drive this:

1. **The link is source-synchronous and its RX domain is clocked by the FAR die**
   (`d2d_clk_rx` → `pad_clk_rx`, `tidelink_top.sv:235`). A die cannot power its
   own link down in isolation without a *coordinated* link-down with the peer, or
   the peer keeps driving a clock and data into unpowered receivers.
2. **`role_locked` gates the whole Wlink datapath and both sides of the a2l
   ACK-ptr CDC** (`wlink_por_reset = ~poresetn | ~role_locked`,
   `app_clk_reset = ~hresetn | ~role_locked`,
   `axi_chiplet_controller.sv:2681,2686`). A separate link domain that can drop
   while the core is up multiplies the reset-ordering hazards `RESET_ORDERING.md`
   already flags into a live power-sequencing problem.

A single domain means the whole chiplet powers together — no core-sleep-with-link-up
— which is the right scope for a first chiplet. The split path is documented below
for when a use case (a remote die keeping this die's link alive while its core
sleeps) actually needs it.

## Candidate domains

| Domain | Contents | Clock(s) | Justification |
|---|---|---|---|
| **CORE** | the SoC, `chiplet_d2d_decode`, both APB bridges, `tidechart_shim`, the PHC | `sys_hclk` (from `sys_fclk`) | one AHB fabric, one clock; `nanosoc_eth_chiplet.sv` clocks all of these on `sys_hclk` |
| **LINK** | `tidelink_top` (Wlink LL/FC, packetiser, calibrator, autoneg), the recovered-RX-clock logic | `user_ref_clk` (PLL ref, async to core), `pad_clk_rx` (far die), gated by `role_locked` | the async clocks and the far-die-driven RX are all here |
| **PHY/pad** | the D2D pad ring (`d2d_clk_tx/rx`, `d2d_tx/rx[7:0]`), the I2C sideband pads | pad-level | pads often sit in their own domain regardless; the D2D pads are the physical interface to the peer |

`user_ref_clk` and the two APB bridges are the ambiguous cases: the bridges are in
CORE (they're `cmsdk_ahb_to_apb`, `sys_hclk`), but they *feed* LINK's APB config.

## The key question: same domain or separate?

**Argument for SEPARATE (independently-powerable LINK):**
- A remote die could keep the link trained while this die's core sleeps — useful
  for a low-power "link stays up, CPU idle" mode.
- The link's async clocks (`user_ref_clk`, `pad_clk_rx`) already make it a natural
  CDC island.

**Argument for SAME (one domain) — stronger for v1:**
- **The link cannot power down unilaterally.** `pad_clk_rx` is the *peer's* clock.
  If this die's LINK domain powers off while the peer is up and driving, the peer
  sees no `role_locked` / no credit return and eventually wedges (the a2l
  false-FULL failure mode `RESET_ORDERING.md §4` describes is one such wedge).
  Powering the link down safely needs a *bilateral* link-down handshake first —
  protocol work, not just a power switch.
- **`role_locked` couples link reset to core reset.** With the link in its own
  domain, `role_locked` (a LINK signal) still resets logic whose power you're
  independently controlling — every combination of {core up/down} × {link up/down}
  becomes a reset-ordering case to verify. In one domain there is one sequence.
- **No proven low-power use case yet.** Nothing in the current firmware or the G2
  bring-up needs core-sleep-with-link-up. Do not pay the isolation/retention cost
  for a mode nobody exercises.

## If the team DOES split it — the crossing

Should a later revision want a separate LINK domain, isolation + (if voltages
differ) level-shifting is needed on every signal group that crosses LINK↔CORE in
`nanosoc_eth_chiplet.sv`. These are:

- **The peer AHB path** — `d2d_ahb_m_*` (CORE→LINK, into `tidelink.ahb_sub` via the
  decode) and `d2d_ahb_s_*` (LINK→CORE, from `tidelink.ahb_mng`). Wide buses;
  isolate to a benign IDLE/`hresp=OKAY` when LINK is down or the CORE stalls.
- **The APB config path** — the decode's `tlapb`/`tcapb` bridge outputs into
  `tidelink`'s APB port. Isolate to "no transaction".
- **The interrupts** — `d2d_irq[15:0]` (LINK→CORE, into the two NVICs), plus
  `doorbell_irq`, `ptp_irq`, etc. Isolate to **deasserted** so a powered-down LINK
  cannot inject a spurious IRQ.
- **The PHC/servo signals** — the D2D servo source into the PHC (`d2d_phc_*`).
- **Status** — `link_active_o`, `role_locked_o`, `role_is_master_o`, `d2d_reset_o`.
  Note `link_active_o` also **gates the TX aperture internally** — isolate it to 0
  (link-down) so the aperture faults rather than wedges.

These are exactly the CORE↔LINK crossings already documented as CDC in
`PHYSICAL_HANDOFF.md §1`; a domain cut turns each CDC into a CDC **and** a power
crossing.

## Retention

`ROLE_CFG` survives `hresetn` but not `poresetn` (`RESET_ORDERING.md §1`;
POR-only reset). The address-translation **CAM does not survive `hresetn`**
(`PEER_APERTURE_PROGRAMMING.md §2`; re-program after any warm reset).

- In a **single domain**, this is just the normal reset story — nothing extra.
- In a **split** where LINK stays powered across a CORE `poresetn`: `ROLE_CFG` and
  the CAM must physically reside in the domain that stays up, or the link silently
  loses its role/translation on a core power-cycle and the first peer write after
  wake DECERRs. This is a retention requirement, not just an isolation one.

## Decision checklist for the team

- [ ] **Confirm single-domain for v1** (the recommendation), or justify a split
      against the two arguments above.
- [ ] If single: still honour `RESET_ORDERING.md` — the PHY/pad power and the
      `role_locked`-gated RX reset are sequenced correctly even within one domain.
- [ ] If split: draw the isolation clamps on every group in "the crossing", set
      `link_active_o` isolation to 0, `d2d_irq` isolation to deasserted.
- [ ] If split with LINK-stays-up: place `ROLE_CFG` + the CAM in the retained
      domain (retention regs or always-on).
- [ ] Decide the PHY/pad domain voltage and whether `user_ref_clk` /
      `pad_clk_rx` receivers share it.
- [ ] Feed the chosen domain per pad back into `PIN_MAP.md`'s "domain" column.

## What the RTL dictates vs what is a free choice

- **Dictated:** `role_locked` couples link and datapath reset; `pad_clk_rx` is the
  far die's clock; `ROLE_CFG`/CAM reset survival. These are not negotiable — they
  are how the frozen TideLink RTL behaves.
- **Free choice (PDK/team):** the number of domains, the voltages, isolation-cell
  and retention-cell selection, and whether to build the low-power
  core-sleep-with-link-up mode at all.
