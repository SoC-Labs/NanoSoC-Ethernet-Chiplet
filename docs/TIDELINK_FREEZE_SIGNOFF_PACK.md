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

    verif/g2_soc_pair on the frozen pair   result: TESTS=15 PASS=15 FAIL=0 SKIP=0  (SIM_RC=0, 2026-08-21)
    elab on the frozen pointer             result: PASS -- 213 modules, simv_chiplet linked, ELAB_RC=0
                                           all 32 xhb500 paths in the flattened flist resolve

NOTE ON `make sim_gate`: that target lives in tidelink/Makefile and is the TIDELINK session's gate.
Run from this superproject it false-reds (~5 fails) because CHIPLET_HOME/TIDECHART_HOME assume
tidelink is a sibling, not a child. The tidelink session ran it in its own worktree, where the layout
is correct. The integration-level gate on THIS side is verif/g2_soc_pair, recorded above.
    known-unrelated failures allowed       tc_pair_smoke / tc_pair_election_datamode (UPIMI-E tidechart-shim skew)

⚠ Two traps that make this gate LIE: the `a2l_replay_cdc` `dut_src_*.f` churn silently dirties the tree
mid-run, and **the aggregate can exit 0 while its own summary says FAILURES DETECTED**. Read the
per-suite table, never the exit code. No summary line means unmeasured, not green.

## 5. Hardware re-validation ON THE FROZEN POINTER

Vehicle `kr260-eth-chiplet` (die_a kr260-01, die_b kr260-02 flip). **Rebuilt from the frozen pin —
citing the 2026-08-20 pre-fold A/B is NOT acceptable here** (decision 3).

| # | Check | Expected | Measured |
|---|---|---|---|
| 1 | Bitstream builds from frozen pin | rc=0, setup met (hold red is the known baseline) | **PASS** — BUILD_RC=0, ~45 min, tidelink.bit 7,797,819 B @ 09:54:38. Setup WNS **+0.247ns**, 0/116678 failing. Hold WHS **-22.273ns**, **8** failing = the documented baseline. WPWS +2.000, 0 failing. |
| 2 | Link bring-up both dies | `fcsm=4 cal=1` | **PASS** — 4 of 4 valid attempts reached FCSM=4 on both dies, each ACCEPTED on try 1/8 |
| 3 | Instrument answering | `0x4_2E03_21F8` marker `0xB5` | **PASS** — `witness_raw=0xb5000001` (marker present, baseline control value), `regf_raw=0xad800000`, `data_healthy=1`, `fcsm=4`, `cal=1`, read directly on die_a |
| 4 | Tie-down in effect | `[4] pipe_hprot_r[2] = 0` | **PASS (by consequence)** — obs read 2026-08-21: `wr_hwm=0`, `wr_err=0`, `stall_stuck=0`, `synth_b=0`. The hazard list never allocates, which is precisely what the HPROT tie-down produces. The hprot bit itself is not a field in the obs JSON. |
| 5 | Hazard list cannot saturate | `[7:5] hwm = 1` (pre-fix was 4) | **PASS — `wr_hwm = 0`** on a live healthy link (2 independent bring-ups). Better than the expected 1; pre-fix was 4. Direct evidence the tie-down forecloses hazard allocation entirely. |
| 6 | Posted-burst induce completes | DONE, not ERROR/hang | **NOT MEASURABLE with current tooling** (attempted 2026-08-22, three independent blockers — see 5c). Partially covered by `wr_hwm=0`, but the DMA-posted case specifically is UNTESTED. |
| 7 | Peer-write soak byte-exact | 0 bad | **PASS** — T3_delivery_soak 128/128 byte-exact in **4 of 4** valid attempts |
| 8 | Post-soak link healthy | `fcsm=4`, RegionF `data_healthy=1` | **PARTIAL** — healthy after the write soak in 4/4; NOT healthy after the read soak in 3/4 (link down, die_a POR'd) |

**Bring-up is a marginal-eye lottery** — it failed several times on 2026-08-20. Only compare or accept
results at `fcsm=4` on BOTH dies. A run at any other link state is VOID, not a negative result.

### 5b. Cross-die READ is NOT validated — the significant finding of 2026-08-21

Five sysval runs on the frozen pointer (one clean, one bad-eye, one void, three POR-recovered):

| run | bring-up | T2b canary | T3 write soak | T10 read soak | T6 endurance |
|---|---|---|---|---|---|
| 1 | try 1/8 | PASS 8/8 | **PASS 128/128** | **PASS 128/128** | FAIL — wedged at beat **1024** |
| 2 | try 1/8, FCSM=4 | **FAIL — canary wedged** | not reached | not reached | not reached |
| 3 | EXHAUSTED 8/8 | — | — | — | **VOID** (die_a wedged, deploy rc=255) |
| 4 | try 1/8 | PASS 8/8 | PASS 128/128 | **FAIL — mismatch @100** | SKIPPED (link down) |
| 5 | try 1/8 | PASS 8/8 | PASS 128/128 | **FAIL — mismatch @100** | SKIPPED (link down) |
| 6 | try 1/8 | PASS 8/8 | PASS 128/128 | **FAIL — mismatch @100** | SKIPPED (link down) |

**Writes are solid: 4 of 4 valid runs delivered 128/128 byte-exact.**

**Reads are not — but NOT deterministically, and the earlier "deterministic" reading in this
pack was WRONG.** A chunk-size discriminator run on 2026-08-21 refuted both hypotheses:

| CHUNK | seam predicts | pattern predicts | OBSERVED |
|---|---|---|---|
| 50 | fail @100 | fail @100 | ambiguous by construction — 1 PASS, 3 FAIL @100 |
| **30** | fail @60 | fail @100 | **PASS 128/128** — both refuted |
| **64** | PASS | fail @100 | **FAIL, Region-F fault AFTER all 128 reads** — both refuted |

The decisive control is the *same* setting twice: at fixed `CHUNK=50` the result is **1 PASS /
3 FAIL**. So the three identical `@100` failures were a run of correlated draws, not a
deterministic index. Read reliability across all six frozen-RTL runs is **2 PASS / 4 FAIL**,
with three different failure signatures (mismatch mid-soak, Region-F fault after completion,
link down). That is the profile of an unreliable, eye-sensitive path — consistent with the
documented read/write asymmetry — not a fixed logic fault.

**Cross-die READ is therefore NOT hardware-validated, for a different reason than first
recorded:** it is intermittent (~33% pass), not broken at a specific offset.

**DOES IT TRANSFER TO SILICON? Yes, probably — and the earlier "different PHY" reasoning in
this pack was FALSE.** It was twice stated here that the rig uses a GPIO PHY while the ASIC uses
"the real D2D PHY", so rig read behaviour might not transfer. **There is no separate D2D PHY in
the v1 ship config.** Verified on the frozen SHA — the ASIC ship flist and the FPGA build compile
the *same* PHY sources:

| file | ASIC v2 flist | FPGA elab flist |
|---|---|---|
| `WlinkGPIOPHY_v2.v` | yes | yes |
| `WavD2DGpioTx.v` | yes | yes |
| `tidelink_phy_align_calibrator_v2.sv` | yes | yes |

The only `serdes`/`pcs`/`pma` strings in the ship flist are **comment lines** — no such RTL is
compiled. And the line rate moves the wrong way: **~4.7–25 MHz on the rig, ~100 MHz on the ASIC
target** (UI = 10 ns). Same PHY architecture, same calibrator, same sync/mask datapath, at
roughly 4–20x the rate, so the eye is **tighter** on silicon, not more forgiving.

What genuinely does differ: pad cells, delay-cell quantum, flat ASIC clocking versus FPGA fabric
routing. Those are real and unquantified, and the rig's reliability percentages are explicitly
NOT the ASIC's numbers. So this is not "read WILL fail on silicon".

**The defensible position for signoff: cross-die read is unvalidated on a PHY architecture that
silicon shares, at a line rate where the eye is tighter. Treat it as a LIVE SHIPPING RISK, not
an unknown-transfer rig curiosity.** Credit: the tidelink session caught this premise error.

**Consequence for the freeze: cross-die READ must not be described as hardware-validated.**
Cross-die WRITE is. This corrects run 1 read as evidence in isolation — a single pass against
three deterministic failures is not a validation.

**T6 endurance: RETRACTED — the "beat 1024, n=2, reproducible" claim in this pack was WRONG,
and the submission wording it authorised must NOT be used.**

I wrote that beat 1024 was reproducible across "independent bring-ups with different chunk
settings". Verified against the harness, that justification is false:

- `kr260_sysval.py:208` — T6 steps in **`step = 256`, hardcoded**. `SYSVAL_READ_CHUNK` is used
  ONLY in the read soak (`:233`). **The two runs were the same experiment, not two
  parameterisations.** My stated reason for treating them as independent does not exist.
- `:214` records `done` **before** adding the failing chunk. So "beat 1024" means *the 5th of
  eight 256-beat chunks failed* — the true failure point is bounded only to **[1024, 1280)**,
  and there are just 8 possible reported values. It is a bucket, not a beat.
- The two runs failed on **different code paths**: run 1 at `:213-214` (the write chunk itself
  returned non-zero); run d1 at `:215-217` where the write **succeeded** and only the diagnostic
  obs read came back `no-obs` — the "instrument not answering" case, which the recovery doc
  says must not be read as data. **One of the two may not be a wedge at all.**
- The 2026-08-09 run failed in the **4th** bucket (768) — adjacent, and at the time that
  variability was read as ruling out a fixed boundary.
- It is not cumulative-since-link-up (T2b+T3+T10 put ~1160 writes on the link first) and not an
  address boundary (`eth_sysval_board.py:90-96` always writes `0x2F001000+`; the hex argument is
  a data seed, not an address). And no structure of depth 1024 exists in the D2D write path —
  FC packet number is 8 bits, `HAZARD_LIST_SIZE=4`, `sub_wr_os_ctr` is 3 bits. 1024 = 4 x 256
  fully explains the number as an artefact of the harness.

**Defensible statement, and the only one that should reach submission text:** *a chunked
peer-write soak failed in the 5th of eight 256-beat chunks in 2 of 2 attempts on the frozen
build, with two different failure signatures; the failure point is bounded to [1024, 1280) and
the underlying threshold, if any, is unmeasured.*

T6 still has never passed, and that part stands.

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
