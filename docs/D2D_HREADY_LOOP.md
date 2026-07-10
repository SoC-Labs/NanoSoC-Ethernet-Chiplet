# A combinational cycle on the peer aperture's HREADY

**Status: OPEN. Found 2026-07-10 while bringing up `verif/g2_peer_aperture`.**
Not exercised by anything that runs today. Must be broken before tapeout.

## The cycle

TideLink's `ahb_sub_hreadyout` depends **combinationally on its own
`ahb_sub_hready` input** (`tidelink/src/rtl/tidelink_top.sv`):

```systemverilog
wire ext_addr_phase = ahb_sub_hsel & ahb_sub_htrans[1] & ahb_sub_hready;   // :1119
wire ext_is_nonseq  = ext_addr_phase & (ahb_sub_htrans == 2'b10);          // :1120
assign ahb_sub_hreadyout = (ext_is_nonseq && !pipe_valid_r) ? 1'b0
                                                            : xhb_sub_hreadyout_raw;  // :1169
```

`nanosoc_eth_chiplet.sv:563` drives that input from the decoder's response mux:

```systemverilog
.ahb_sub_hready (d2d_ahb_m_hready),      // = chiplet_d2d_decode.hready
```

and `chiplet_d2d_decode.sv:211,218` selects the peer's own `hreadyout` into it
whenever the outstanding data phase belongs to the peer:

```systemverilog
DPH_PEER: begin ... hready_r = hreadyout_peer; ... end
assign hready = hready_r;
```

So when `dph_code == DPH_PEER`:

```
hready -> ext_addr_phase -> ext_is_nonseq -> ahb_sub_hreadyout -> hready_r -> hready
```

A cycle with no register in it. Evaluate it with `pipe_valid_r == 0` and a fresh
peer `NONSEQ` presented: `hready=1 ⇒ hreadyout=0 ⇒ hready=0 ⇒ hreadyout=raw=1 ⇒
hready=1 ⇒ …`. It does not settle.

## How it presents

VCS does **not** report an error. It spins at 100 % CPU with **simulation time
frozen**, which is indistinguishable from a slow test until you look. The tell is
that a periodic heartbeat coroutine stops logging while the process keeps
burning a core. `verif/g2_peer_aperture/test_peer_aperture.py` carries such a
heartbeat for exactly this reason — a sim-time timeout cannot fire when sim time
does not advance.

Synthesis should report it as a combinational loop. Nothing has synthesised it:
see below.

## Why nothing has caught it

* **The SoC's FPGA and ASIC builds never instantiate TideLink.** The `0x2E/0x2F`
  D2D window is terminated by `nanosoc_d2d_idle_slave`, which answers with a
  two-cycle ERROR. There is no `hready` feedback because there is no TideLink.
* **`make elab` only elaborates.** It links a netlist; it does not evaluate it,
  and it does not look for combinational cycles.
* **`verif/chiplet_d2d_decode` drives the decoder standalone**, with stub slaves
  whose `hreadyout` is a constant or a register. No feedback, no cycle.
* **TideLink's own `tidelink_top_pair` testbench ties `ahb_sub_hready` to
  `1'b1`** and leaves `ahb_mng` dangling — it never closes the loop either.
* **`soc_d2d_loopback` drives the SoC's `d2d_ahb_m` against a memory model**, not
  against TideLink.

The cycle therefore exists only in `nanosoc_eth_chiplet.sv`, the one module that
wires the real decoder to the real TideLink — and until `verif/g2_peer_aperture`
there was nothing that put a transaction through it.

## When it activates

The guard is `ext_is_nonseq && !pipe_valid_r`, true on the first cycle of a new
peer `NONSEQ` address phase. The feedback is live only while
`dph_code == DPH_PEER`, i.e. while the outstanding data phase is *also* the peer.

So a single isolated peer access, preceded by an idle bus, does not activate it:
`dph_code == DPH_NONE` falls through to the mux's `default:` arm, which drives
`hready_r = 1'b1` unconditionally (`chiplet_d2d_decode.sv:213`), and the feedback
is cut. **Back-to-back peer transfers do activate it** — which is precisely what a
`memcpy` across the aperture, or any loop of stores into remote `shared_sram_0`,
generates. This is not an exotic corner.

The same shape exists on the other five decoded slaves, since the mux feeds each
of their `hreadyout`s back as `hready`. It bites on the peer path because
TideLink's `ahb_sub_hreadyout` reads `ahb_sub_hready`. Whether `ahb_tx`,
`ahb_fifo` and `ahb_ptp` do the same has not been checked — TideLink's own
testbench loops `ahb_tx_hready` back from `ahb_tx_hreadyout`
(`tb_top.sv`, `m_ahb_tx_hready_loop`) and does not spin, which is weak evidence
that the TX aperture is clean. **Audit the other five before tapeout.**

## Candidate fixes

Neither is implemented. Both need simulating.

1. **Chiplet-side (preferred; TideLink's pin is frozen).** Do not feed the peer
   subordinate its own readiness. A subordinate's `HREADYOUT` must not be a
   function of `HREADY` — AMBA says so — so supplying `1'b1` while the peer owns
   the data phase is not a lie, it is removing an input the slave should never
   have used:

   ```systemverilog
   // hready_to_peer: the global HREADY, except that the peer never sees its own
   // contribution. Breaks the cycle without changing what any other slave sees.
   wire hready_to_peer = (dph_code == DPH_PEER) ? 1'b1 : d2d_ahb_m_hready;
   ```

   This requires `chiplet_d2d_decode` to export `dph_code == DPH_PEER` (one new
   output). It is exactly what TideLink's own pair testbench does implicitly by
   tying `ahb_sub_hready` high with a single subordinate on the port.

2. **TideLink-side (the real fix).** Make `ahb_sub_hreadyout` a function of
   registered state only. The `& ahb_sub_hready` term in `ext_addr_phase` exists
   to avoid latching an address phase that the bus has not committed; the
   `!pipe_valid_r` guard already prevents double-latching. Removing the `hready`
   term alone is **not** safe — the decoder asserts `hsel_peer` combinationally
   during a previous slave's wait state, so TideLink would latch an uncommitted
   address. The correct change is to qualify the latch with a registered
   "previous transfer completed" flag instead of the live `hready`.

## Reproducing

Restore the loop in the pair testbench:

```systemverilog
// verif/g2_peer_aperture/tb_pair.sv
wire m_sub_hready = m_sub_hreadyout;   // instead of 1'b1
```

Run `make`. The heartbeat stops at the first peer write; `simv` sits at 100 % CPU
with sim time frozen. That is the same cycle the chiplet top closes on
back-to-back peer transfers, just closed unconditionally.

## What this does not affect

The peer-aperture *data plane* is correct: `verif/g2_peer_aperture` proves a
write crosses the link with `addr[31:24]` translated `0x2F → 0x2D`, that the data
crosses, that a read returns it, and that with the CAM disabled the address
arrives untranslated. Address translation, the packetiser and the far-die
reconstruction are all sound. This is a handshake wiring defect at the chiplet
boundary, not a link defect.
