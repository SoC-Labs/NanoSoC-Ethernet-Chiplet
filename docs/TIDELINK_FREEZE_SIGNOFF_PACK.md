# TideLink RTL freeze — signoff pack

**STATUS: TEMPLATE. Every `<TBD>` must be a measured value before this is a signoff.**
An unfilled field is not a pass; it is an unmeasured field. Do not quote a green from this
document until the SHA line below names a real frozen pair.

## 1. The frozen pair (fill FIRST — everything else is meaningless without it)

    superproject   <TBD sha>   branch <TBD>
    tidelink pin   <TBD sha>   pushed & fetchable: <TBD yes/no>
    frozen at      <TBD date/time>

**Gate:** `git ls-tree <superproject-sha> tidelink` MUST equal the tidelink pin, and that pin MUST be
reachable from a remote (`git branch -r --contains <pin>` non-empty). A pin a clone cannot fetch is
not a freeze. This project has shipped a stream from RTL that existed on no remote — do not repeat it.

## 2. Decisions ratified into this freeze (David, 2026-08-20, interactive)

| # | Decision | Answer |
|---|---|---|
| 1 | WIP `3493d3d7` | **KEEP WHOLE** — regains TL-033 on the canonical line; keeps the instrumentation that caught two live defects; FCSM half cannot reach the tapeout netlist |
| 2 | FCSM flist | **HOLD on `deps/`, ratified** — status quo becomes the decision, so both dies agree; the never-run silicon ILA gated only the *re-point* |
| 3 | Fold validation | **FULL HARDWARE RE-VALIDATION** — the divider is in the PHY reference clock path and is invisible to both sim and STA |
| 4 | Execution | Proceed on the frozen pin; **stop before GDS launch** |

## 3. Content census — must-survive tokens on the frozen pin

Run `git grep -c <tok> <pin> -- src/rtl`. Baselines measured 2026-08-20.

| token | pin `e6aaa82f` | main `d0a977aa` | REQUIRED on frozen | measured |
|---|---|---|---|---|
| `terminal_timeout` (TL-037) | 0 | 1 | **>=1** | `<TBD>` |
| `wr_hold_drain_release` (TL-043) | 0 | 2 | **>=2** | `<TBD>` |
| `read_would_overmint` (N3) | 0 | 7 | **>=7** | `<TBD>` |
| `AUTO_ANCHOR` | 26 | 26 | **26** | `<TBD>` |
| `socl_l7_wdog` (TL-033, decision 1) | 111 | 81 | **111** | `<TBD>` |
| `dbg_a2l_wedged` (debug block, decision 1) | 6 | 0 | **6** | `<TBD>` |
| `link_clk_div_ratio_i` (divider absorbed) | 12 | 0 | **12** | `<TBD>` |

Structural check (a name count is not enough):

    git grep -n 'ahb_sub_w_beat_consumed_o *= *s_axi_wvalid *& *s_axi_wready' <pin> -- src/rtl/tidelink_top.sv

Flist checks (RTL present but unlisted is RTL that does not exist):

    git show <pin>:flists/tidelink_top_full_asic_v2.flist | grep -c 'local_overrides/WlinkGenericFCSM'   # MUST be 1 (_6 only) per decision 2
    git show <pin>:flists/tidelink_top_full_asic_v2.flist | grep -nE 'link_clk_div|link_rate_regs'       # MUST be present (divider ships)

## 4. Simulation gate

    make sim_gate on the frozen pair       result: <TBD>   uniform stamp: <TBD>
    known-unrelated failures allowed       tc_pair_smoke / tc_pair_election_datamode (UPIMI-E tidechart-shim skew)

⚠ Two traps that make this gate LIE: the `a2l_replay_cdc` `dut_src_*.f` churn silently dirties the tree
mid-run, and **the aggregate can exit 0 while its own summary says FAILURES DETECTED**. Read the
per-suite table, never the exit code. No summary line means unmeasured, not green.

## 5. Hardware re-validation ON THE FROZEN POINTER

Vehicle `kr260-eth-chiplet` (die_a kr260-01, die_b kr260-02 flip). **Rebuilt from the frozen pin —
citing the 2026-08-20 pre-fold A/B is NOT acceptable here** (decision 3).

| # | Check | Expected | Measured |
|---|---|---|---|
| 1 | Bitstream builds from frozen pin | rc=0, setup met (hold red is the known baseline) | `<TBD>` |
| 2 | Link bring-up both dies | `fcsm=4 cal=1` | `<TBD>` |
| 3 | Instrument answering | `0x4_2E03_21F8` marker `0xB5` | `<TBD>` |
| 4 | Tie-down in effect | `[4] pipe_hprot_r[2] = 0` | `<TBD>` |
| 5 | Hazard list cannot saturate | `[7:5] hwm = 1` (pre-fix was 4) | `<TBD>` |
| 6 | Posted-burst induce completes | DONE, not ERROR/hang | `<TBD>` |
| 7 | Peer-write soak byte-exact | 0 bad | `<TBD>` |
| 8 | Post-soak link healthy | `fcsm=4`, RegionF `data_healthy=1` | `<TBD>` |

**Bring-up is a marginal-eye lottery** — it failed several times on 2026-08-20. Only compare or accept
results at `fcsm=4` on BOTH dies. A run at any other link state is VOID, not a negative result.

## 6. Known limitations shipping with this freeze

1. **Peer-write throughput ~0.89 MB/s** (75x/100x vs a posted burst). Structural: the per-word cost IS
   the B round trip; `s_axi_bvalid` returns across the link with no local early-B. Not optimisable in
   the wrapper, and pipelining outstanding singles cannot help (non-bufferable is non-posted by
   definition). The lever is link latency. See `TAPEOUT_LIMITATION_D2D_PEER_WRITE.md`.
2. **Multi-beat AXI burst path corrupts then wedges** — foreclosed by the tie-down, which forces
   `AWLEN=0`. A disclosed residual of the burst fix (`BURST_FIX_HARDENING.md` bounded depth-1 to the
   non-bufferable path), now measured and confirmed. Post-tapeout work.
3. **Hold timing red on every FPGA build** (~-22 ns, 8 endpoints, D2D GPIO PHY RX capture). Pre-existing
   baseline, runtime-calibrated; unrelated to the peer-write path.
4. **Both `ahb_sub` backstops are starvable** aggregate-progress timers; the W node has no timeout;
   the re-ACK is a one-shot that cannot re-arm. Layer-2 recovery is post-tapeout.
5. **FPGA != ASIC configuration** — the tapeout ships ECC/CRC/FCSM settings the FPGA does not.

## 7. Signoff

    RTL frozen and fetchable          <TBD>
    Content census passes             <TBD>
    Sim gate green on frozen pair     <TBD>
    Hardware re-validated on frozen   <TBD>
    Limitations documented            yes (section 6)
    Signed off by                     <TBD>
