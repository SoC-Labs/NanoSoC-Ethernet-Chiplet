# `verif/g2_soc_pair` — a transaction between two REAL chiplet dies

Two whole `nanosoc_multicore_soc` instances, each behind its own
`chiplet_d2d_decode` and `tidelink_top`, cross-wired through the PHY pads.

```sh
source ../../set_env.sh
make                       # == make elab: structural elaboration under VCS
make sim                   # the cocotb tests
make sim MODULE=test_peer_burst_corruption TESTCASE=test_peer_write_burst_delivers_each_beat
```

`make` (the default goal) only ELABORATES — it does not go through cocotb — so
it is the fast check that the merged flist still builds.

## What it proves

```
die A eth_ss_0 (external master)
  -> die A SoC matrix -> d2d_ahb_m -> chiplet_d2d_decode (hsel_peer)
  -> die A tidelink ahb_sub  (0x2F aperture)
  == CAM rewrites addr[31:24] 0x2F -> 0x2D ==
  -> PHY pads -> die B tidelink ahb_mng
  -> die B d2d_ahb_s -> die B SoC matrix -> die B shared_sram_0
```

Everything is firmware-free. Both dies' CPU0 are boot-gated secondaries that are
never released and both CPU1 halt on the unprogrammed flash, so every stimulus is
an external master on each die's `eth_ss_0`. The links are brought up the same
way: AHB writes to `0x2E03_xxxx` reach TideLink's APB through the chiplet
decode's `tlapb` bridge.

`verif/g2_peer_aperture` runs the same experiment against ONE TideLink pair with
an AHB master model standing in for CPU0. It is structurally blind to anything
inside the `nanosoc_eth_chiplet` wrapper — including the peer-write data
steering — which is why this environment exists.

## Test modules

| module | what it covers |
|---|---|
| `test_g2_soc_pair.py` | harness smoke test, the full cross-die write, and the W-channel-backpressure regression |
| `test_peer_burst_corruption.py` | a continuous INCR4 peer write must deliver each beat's OWN payload |
| `test_peer_burst_adversarial.py` | the same logic from the shapes a narrow test misses: INCR16, back-to-back bursts, single-after-burst, read-after-write, W-backpressure, and a `wr_hold_r` characterisation |

Every module must be named in the Makefile's `MODULE` list or it does not run —
and `regress` still reports PASS. A suite is green over what it RUNS.

Clean between debug runs: `rm -rf build` (the build directory is `build/`, not
`sim_build*`).

`zdma_induce.c` is a separate host-side tool; see `README_zdma_induce.md`.
