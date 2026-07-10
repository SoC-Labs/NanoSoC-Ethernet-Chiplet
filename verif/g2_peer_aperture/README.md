# g2_peer_aperture — a transaction across the die boundary

```sh
source ../../set_env.sh
make                       # all four tests
make MODULE=test_peer_aperture WAVES=1
```

## Why

Everything else in this repo proves the **port**. `soc_d2d_loopback` (in the SoC)
drives `d2d_ahb_m` against a memory model. `verif/chiplet_d2d_decode` proves the
sub-decode and its wedge gate. `docs/PEER_APERTURE_PROGRAMMING.md` §8.1 proves,
by reading the Chisel and the generated Verilog, that Wlink carries `addr[31:24]`
end to end.

None of that is a transaction crossing a link with another die at the far end.
This is.

Die A writes `0x2F00_1000`. TideLink's 8-rule CAM rewrites `addr[31:24]` from
`0x2F` to `0x2D`. The packetiser must carry the rewritten byte, and die B's
`ahb_mng` must re-present `0x2D00_1000` to its local fabric, where
`ahb_probe_mem` latches what it was actually shown.

## The tests

| Test | What it establishes |
|---|---|
| `test_link_comes_up` | Guard. `cal_done` on both dies, `cr`/`crack` seen on the slave. If this fails nothing else in the file means anything. |
| `test_cross_die_write_carries_upper_byte` | Die B is presented `0x2D00_1000`, carrying the payload. The CAM fired, the link carried the byte, and the far die reconstructed it. |
| `test_cam_disabled_is_identity` | **The control.** Same transfer with `global_enable=0`; die B must see the *untranslated* `0x2F00_1000`. |
| `test_cross_die_read_returns_written_data` | The return path: die A reads back what it wrote, so the response crossed B→A and landed on the right beat. |

The control is not optional. Asserting "die B saw `0x2D`" proves nothing by
itself — a testbench with `0x2D` hard-wired anywhere would pass it. Only the pair
of results shows that the CAM is what moved the byte and that the byte crossed
the link rather than being invented on the far side.

## Relationship to the upstream harness

Structure is lifted from `tidelink/cocotb/tidelink_top_pair/tb_top.sv`: same two
dies, same `pad_skid` cross-wiring, same straps, same shared `hclk`, same
software bring-up. That testbench **ties off `ahb_sub` and `ahb_mng`** — the two
ports the peer aperture rides on — so it is copied rather than reused. `pad_skid`
itself is compiled unmodified from the submodule. Nothing in `tidelink/` is
touched; its pin is frozen.

Unlike upstream, this env compiles the **resolved** TideLink filelist
(`flist/resolve_tidelink_flist.py`), so exactly one definition of every module
reaches the compiler and the netlist is a property of the filelist rather than of
whichever tool reads it. See `docs/PIN_POLICY.md`.

## Traps encoded here (all cost real time to find)

* **`ROLE_CFG` is `0x2080`**, not the `0x2084` in `INTEGRATION_GUIDE.md:263`.
  Writing `0x2084` lands on the next register and the role never locks.
* **The calibrator needs a sim bypass.** `u_calibrator.tb_early_exit_force_q = 1`
  on both dies, applied *before* `role_locked` rises, or both sit in `S_VALIDATE`
  for 2M link cycles and `cal_done` never asserts.
* **`lanes_locked == 0xFF` is not the gate.** It reads `0xFF` only while training
  patterns drive, and falls to `0x00` after `S_DONE`. Gate on `cal_done`, bit 16
  of `SWI_LANE_STATUS` (`0x2108`).
* **`link_active` is not evidence of a working link** — it is literally
  `assign link_active = role_locked_o`. Gate on the FCSM's `cr_pkt_seen_rx` and
  `crack_pkt_seen_rx` instead.
* **`PAIR_CREDIT_COUNTER` reads 0 on a healthy link.** It only moves on a real
  RX-FIFO read completion. Never gate "link up" on it.
* **Hold `hwdata` for the whole AHB data phase**, and sample `hreadyout` on a
  clock edge rather than combinationally in the same timestep. Get this wrong and
  the payload ships as zero while the address check still passes.
* **Direction is master→slave on purpose.** TideLink's own tests record a
  sim-harness S→M asymmetry (`test_04`, `test_30`, `test_36`) where the master's
  `crack_pkt_seen_rx` stays 0 regardless of bring-up. M→S is the proven-good
  direction.

## What this is not

Not the full G2. The plan's assertion 1 says "**CPU0** on die A writes
`shared_sram_0` on die B"; here an AHB master model stands in for CPU0, and
`ahb_probe_mem` stands in for die B's `shared_sram_0`. Swapping in two real
`nanosoc_multicore_soc` instances is the remaining step — the addressing and the
bring-up do not change, so this env is the scaffold for it.

`chiplet_d2d_decode` is deliberately absent: it only generates selects, so putting
it in the path would drag in an AHB-to-APB bridge for the two APB banks and prove
nothing new. Its wedge gate is proven at unit level in `verif/chiplet_d2d_decode`.

The doorbell (plan assertion 2) is already proven upstream in
`tidelink/cocotb/tidelink_top_pair/test_05`; it is not re-proven here.
