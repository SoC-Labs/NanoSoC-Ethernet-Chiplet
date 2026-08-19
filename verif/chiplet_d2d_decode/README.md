# `verif/chiplet_d2d_decode` — the D2D sub-decoder

Two standalone VCS benches for `src/rtl/chiplet_d2d_decode.sv`. No cocotb, no
submodules: the decoder is self-contained, so each bench compiles just it plus
a testbench.

```sh
source ../../set_env.sh
make                 # both benches
make tx-gate
make hready-loop
```

| bench | what it proves |
|---|---|
| `tb_tx_gate.sv` | With the link down, a TX-aperture access takes a proper two-cycle AHB ERROR instead of wedging the bus — and no OTHER region is closed, so the APB banks used to bring the link up stay reachable. |
| `tb_hready_loop.sv` | Four back-to-back peer writes complete and land. This guards the combinational HREADY cycle between the decoder's response mux and TideLink's `ahb_sub_hreadyout` (`docs/D2D_HREADY_LOOP.md`). |

## The one thing that will surprise you

`tb_hready_loop.sv` can be rebuilt with `+define+NO_HREADY_FIX` to get the
broken wiring, but that variant is **deliberately not run by `make`**. A
zero-delay combinational loop means no simulation time passes, so VCS neither
errors nor finishes and no timeout can fire. The guard is therefore that the
fixed variant completes with the right answers, and that removing the fix hangs.
