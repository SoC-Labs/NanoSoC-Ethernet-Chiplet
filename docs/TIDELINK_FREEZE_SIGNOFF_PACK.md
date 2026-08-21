# TideLink RTL freeze — signoff pack

**STATUS: TEMPLATE. Every `<TBD>` must be a measured value before this is a signoff.**
An unfilled field is not a pass; it is an unmeasured field. Do not quote a green from this
document until the SHA line below names a real frozen pair.

## 1. The frozen pair (fill FIRST — everything else is meaningless without it)

    superproject   cebb5bb7   branch feat/padring-boundary-scan
    tidelink pin   5e8bdb5a2141ff5a82103813a326a2c9df2b43ed   pushed & fetchable: YES (origin/main)
    frozen at      2026-08-21 (tidelink push); pin bumped 2026-08-21

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
| `terminal_timeout` (TL-037) | 0 | 1 | **>=1** | **1** PASS |
| `wr_hold_drain_release` (TL-043) | 0 | 2 | **>=2** | **2** PASS |
| `read_would_overmint` (N3) | 0 | 7 | **>=7** | **7** PASS |
| `AUTO_ANCHOR` | 26 | 26 | **26** | **26** PASS |
| `socl_l7_wdog` (TL-033, decision 1) | 111 | 81 | **111** | **111** PASS |
| `dbg_a2l_wedged` (debug block, decision 1) | 6 | 0 | **6** | **6** PASS |
| `link_clk_div_ratio_i` (divider absorbed) | 12 | 0 | **12** | **12** PASS |

**Census result 2026-08-21: 7 of 7 PASS on the frozen pin.**

Structural check (a name count is not enough):

    git grep -n 'ahb_sub_w_beat_consumed_o *= *s_axi_wvalid *& *s_axi_wready' <pin> -- src/rtl/tidelink_top.sv

Flist checks (RTL present but unlisted is RTL that does not exist):

    git show <pin>:flists/tidelink_top_full_asic_v2.flist | grep -c 'local_overrides/WlinkGenericFCSM'   # MUST be 1 (_6 only) per decision 2
    git show <pin>:flists/tidelink_top_full_asic_v2.flist | grep -nE 'link_clk_div|link_rate_regs'       # MUST be present (divider ships)

Measured 2026-08-21 on `5e8bdb5a`:

| check | result |
|---|---|
| FCSM from `local_overrides/` | **1** (`_6` only; 0-5 from `deps/`) — PASS |
| Divider ships | `tidelink_link_clk_div.sv` :410, `tidelink_link_rate_regs.sv` :414 — PASS |
| Per-beat W consumption (structural) | `tidelink_top.sv:638` exact form — PASS |
| `deps/xhb500/generated` tracked | **untracked** — the SHA no longer pins a pointer — PASS |

## 3b. Build-input provenance — what the SHA CANNOT pin

The frozen SHA does **not** pin the XHB-500 bridge RTL, by construction: `deps/xhb500/generated`
is generate-on-demand output, produced by `set_env.sh` from `$XHB500_IP_DIR` on first run. It is
correctly untracked as of the freeze (see the defect note below). So for this dependency,
"reproducible" means **same SHA _plus_ same release string** — record both:

    XHB500 source: CoreLink XHB-500, generated via
                   $XHB500_IP_DIR/logical/generate at build time.
                   Release identified by CONTENT FINGERPRINT, not by name:
                   md5(xhb500_ahb_to_axi_bridge_chiplet_slv_hazard_list.sv)
                     = c5b8757ba1b248cfe13b76fc7a22ef40

**Correction, 2026-08-21 — the first scan of this measured the wrong space.** An initial
`find -maxdepth 4 -iname '*xhb*'` reported 2 installs, exactly 1 with a generator, and concluded the
source was unambiguous *because it was unique*. That was wrong: the install the build actually uses is
nested three levels deeper under a different product's release tree, and the scan never saw it. A
complete scan finds **7** installs, **2** of which bear a generator. The conclusion survives and is now
stronger for the right reason: both generator-bearing installs are the same release and carry
**byte-identical** hazard templates, so the generated output is identical whichever one
`XHB500_IP_DIR` names, and the other 5 cannot be sources at all. Had the two differed, the original
claim would have asserted provenance from an install no build ever reads.

The release is pinned by fingerprint rather than by its vendor revision string: this repository is
public and the pre-commit vendor gate rejects revision-coded vendor release names in tracked content
(same reason the GLS fixtures redact their model lists). The fingerprint is the stronger check in any
case — it is computed from the generated RTL actually consumed, so it verifies the bytes rather than
trusting a label. The revision string is recorded off-repo in the licensee's IP records.

Verified 2026-08-20 (read-only probe of the vendor tree):

| check | result |
|---|---|
| XHB-500 installs on the build host | **7** (a `maxdepth 4` scan finds only 2 — see note) |
| Of those, shipping `logical/generate` | **2** |
| Hazard template across both generator-bearing installs | **byte-identical** (`c5eaad36...`) |
| Release stamped in our generated RTL | matches the generator-bearing installs |
| Wrong-release failure mode | `set_env.sh` fails on a missing generator — **loud, not silent** |

**Defect fixed at the freeze (found 2026-08-20, pre-push).** Before the fix, `deps/xhb500/generated`
was tracked as a mode-120000 symlink to an absolute path in a *separate* checkout, where it is
git-ignored build output on branch `rescue/primary-worktree-2026-08-10` — governed by no commit
anywhere. The shipping flist `flists/tidelink_top_full_asic_v2.flist` sources 32 XHB-500 files
through that path, including `..._hazard_list.sv`. Introduced by `1f139c94`, a rescue snapshot that
captured a local convenience shortcut; `main` at `969a0c9d` predates it and was clean, which is why
it survived without anyone being careless. Content was identical both ways at the time of the fix
(`hazard_list.sv` = `c5b8757ba1b248cfe13b76fc7a22ef40`), so no build ever consumed divergent RTL.

**Not closed:** a from-scratch generate on a clean tree has not been exercised end-to-end, and there
is no generate log on disk — provenance above is inferred from the release stamp inside the file
(strong, but not a run record). This is a reproducibility check on the frozen artefact, not a
precondition for the freeze. Post-freeze.

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
   Context for the underlying wedge (now foreclosed by the tie-down): the saturating resource is
   `HAZARD_LIST_SIZE = 4` in the **Arm vendor template** — a CoreLink XHB-500 default
   inherited from the licensed bridge, not a value chosen in our integration and not ours to set.
5. **FPGA != ASIC configuration** — the tapeout ships ECC/CRC/FCSM settings the FPGA does not.

## 7. Signoff

    RTL frozen and fetchable          <TBD>
    Content census passes             <TBD>
    Sim gate green on frozen pair     <TBD>
    Hardware re-validated on frozen   <TBD>
    Limitations documented            yes (section 6)
    Signed off by                     <TBD>
