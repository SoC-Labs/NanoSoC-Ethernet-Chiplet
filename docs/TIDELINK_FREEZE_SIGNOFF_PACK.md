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

### 4b. ⚠ THE SIM GATE THAT SHIPPED WITH THIS FREEZE DID NOT RUN ON THE FROZEN LINE

Recorded 2026-08-23. All 59 files in `tidelink/imp/sim_gate/` (56 PASS / 3 XFAIL)
are stamped **`3620af3328ca-dirty`**. Two problems, both measured:

- **`3620af33` is NOT an ancestor of the frozen pin `5e8bdb5a`.** `git merge-base
  --is-ancestor` returns false. It is a 2026-08-18 merge commit on a different line.
- The **`-dirty`** suffix means the worktree carried uncommitted changes when the
  gate ran, so the results do not correspond to any commit at all.

**So "sim gate green" must not be read as "green on the freeze".** The gate is green
on a dirty tree at a commit off the frozen line. That is precisely the trap this
project documented for itself, and it was live at the freeze.

**What this does NOT invalidate.** The frozen pointer has its own independent
evidence recorded in this pack: `elab` PASS at 213 modules, `verif/g2_soc_pair`
15/15, and the hardware matrix in section 5 — all run against `5e8bdb5a` directly.
The sim gate is an additional claim, not the load-bearing one.

**To close it:** re-run `make sim_gate` on a clean checkout of `5e8bdb5a` and
replace the 59 status files, or strike the sim-gate row from the signoff block.
Do not sign the pack with this row reading green and unqualified.

**⚠ A CLEAN TIDELINK CHECKOUT IS NOT SUFFICIENT, AND THE OBVIOUS ATTEMPT PRODUCES A
FALSE GREEN.** Measured 2026-08-24. The gate reaches outside the tidelink tree:

```
cocotb/tidechart_tidelink_pair/Makefile:23   TIDECHART_HOME ?= $(realpath $(TIDELINK_HOME)/../tidechart)
cocotb/tidechart_tidelink_pair/Makefile:24   CHIPLET_HOME   ?= $(realpath $(TIDELINK_HOME)/../nanosoc-ethernet-chiplet)

td-bisect/nanosoc-ethernet-chiplet -> /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet   SYMLINK
td-bisect/tidechart               -> /home/dam1n19/SoCLabs/tidechart                   SYMLINK
```

In `td-bisect/baseline-5e8bdb5a` — the natural clean worktree — those siblings **exist
as symlinks into the live working tree** (`1ef68f1`, `feat/padring-boundary-scan`, 26
modified/untracked files, mutating continuously). `realpath` succeeds, no error is
raised, and the gate compiles **frozen tidelink RTL against dirty chiplet RTL** — a
combination that exists on no branch anywhere. That is exactly the defect §4b exists
to rule out, so a naive re-run would not fail to close §4b; **it would close it with a
false green.**

**The failure is silent in one direction only, and it is the dangerous one.** With the
siblings *absent*, `realpath` returns empty, the dep-check sees a leading-slash path
(`/src/rtl/tidechart_shim.sv`) and ~5 suites abort at 0s with `MISSING DEPENDENCY` —
loud, visible, and structurally incapable of reflecting an RTL change. With the
siblings *present but wrong*, there is no error at all. **Absent path → visible red.
Present-but-wrong path → invisible pass.**

**Requirements for a run that actually closes §4b:**
1. Set `CHIPLET_HOME` and `TIDECHART_HOME` **explicitly**, to checkouts at committed
   SHAs (chiplet pinning `5e8bdb5a`). Never let them default.
2. **Record which chiplet SHA was used** in the result. A gate result without it is
   not evidence.
3. Confirm each FAIL **elaborated** before believing it — an abort at 0s is a null
   result, not a failure.
4. Beware label≠target: `sim_gate_tc_pair_smoke` does not exist; the target is
   `sim_gate_tc_smoke` (likewise `_eth_m0`/`_eth_m1`/`_eth_shape_a`/`_tc_election`).
   A wrong label gives exit 2 = `No rule to make target` = **tested nothing**, which
   reads exactly like a real failure.

**MEASURABLE — the fix is smaller than it looks (2026-08-24).** `CHIPLET_HOME` has
exactly **one** consumer:

```
cocotb/tidechart_tidelink_pair/Makefile:40   VERILOG_SOURCES += $(CHIPLET_HOME)/src/rtl/tidechart_shim.sv
```

One file. **No chiplet checkout, worktree or build is required** — extract it from the
commit (`git show 1ef68f1:src/rtl/tidechart_shim.sv`, md5 `ddd655f7ab6dbe3a62b3e5d25fbb4377`,
verified byte-identical to the live worktree copy, which is clean at HEAD).

**And the chiplet was never the uncontrolled input.** `tidechart_shim.sv` is clean at
HEAD, so the two observed FAILs did not elaborate against a mutating file. The
uncontrolled input was the *other* variable:

```
chiplet HEAD pins tidechart:   4b4b89820ab1
TIDECHART_HOME resolved to:    /home/dam1n19/SoCLabs/tidechart  =  b5102b277c40, 84 DIRTY FILES
```

Wrong commit **and** dirty. `tidechart_shim.sv:194` connects `.device_strap(device_strap)`
into a tidechart module that lacks the port at `b5102b27` — hence `Error-[UPIMI-E]` after
~5 s of real elaboration. **That is a pin mismatch, not an external failure and not a
dependency abort.** Five clean tidechart checkouts sit at exactly `4b4b8982`; the one
safe to use (a real directory, not a worktree of this repo) is
`td-bisect/ethchip-pinbump-2026-08-19/tidechart`.

    make sim_gate \
      CHIPLET_HOME=<dir containing src/rtl/tidechart_shim.sv extracted from 1ef68f1> \
      TIDECHART_HOME=/home/dam1n19/SoCLabs/td-bisect/ethchip-pinbump-2026-08-19/tidechart

**Record the triple with the result — chiplet `1ef68f1` / tidechart `4b4b8982` / tidelink
`5e8bdb5a`.** A gate result that does not name all three is not evidence for this row.

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

> ## ⚠⚠ RETRACTED 2026-08-24 — THE READ-FAILURE CORPUS BELOW IS LARGELY AN SSH TRANSPORT ARTEFACT
>
> **The three `mismatch @100` failures are not DUT failures.** Found by tidelink-92,
> verified here independently from the archive and the harness source.
>
> **The archived signature cannot be a data mismatch.** From `RESCUE_2026-08-22/evidence/`,
> read with `repr()` rather than printed:
>
> ```
> sysval_a4.json   detail = 'read mismatch @100: '
> sysval_a5.json   detail = 'read mismatch @100: '
> sysval_a6.json   detail = 'read mismatch @100: '
> ```
>
> The text after the colon is `out[:80]` and it is **empty**. A real mismatch cannot produce
> that: `read_chunk` prints `READCHUNK .. firstbad idx.. got0x.. exp0x..` and exits 1, so
> `out` would be non-empty *and* contain `READCHUNK`. Empty output with a non-zero rc is a
> command that **never ran**.
>
> **The harness conflates transport failure with data mismatch, and discards the evidence
> twice** (`tidelink/pynq_host/scripts/kr260_sysval.py`):
>
> ```python
> :58   cmd = "cd td && echo %r | sudo -S python3 %s %s 2>/dev/null" % (PW, BOARD, args)
> :60   return rc, out.strip()                    # err DISCARDED
> :238  if rc != 0 or "READCHUNK" not in out:
>           record("T10_read_soak", "FAIL", "read mismatch @%d: %s" % (start, out[:80]))
> ```
>
> `2>/dev/null` throws away the remote stderr; `return rc, out.strip()` throws away ssh's
> own stderr — where `Connection reset by peer` would appear. `rc == 124` is handled as a
> timeout, but **`rc == 255` falls into the generic branch and is labelled "read mismatch"**.
> There is no `ControlMaster`: **every board call opens a fresh ssh connection.** The board
> runs `maxstartups 10:30:100` with `logingracetime 120`, so past 10 pending connections
> ~30% are randomly reset, each slot held up to 120 s.
>
> **The corroborating detail is already in the table below:** run 3 is recorded VOID with
> `deploy rc=255`. The harness *did* surface the transport failure at the deploy step — it
> simply could not do so in the read path, because that branch relabels it.
>
> **Discriminating experiment (tidelink-92, same bus traffic, differing only in connection
> churn):** fresh-ssh-per-call → **3 PASS / 3 FAIL**; one reused connection → **6 PASS / 0
> FAIL**, 128 words byte-exact. Plus 108 chunked cross-die readbacks across 9 bring-ups with
> **zero** read failures, and a chunk sweep at 24/24 for CHUNK ∈ {30, 50, 100, 128} —
> including CHUNK=128, which has **zero** mid-read CAM seams.
>
> **INVALIDATED:** the "2 PASS / 4 FAIL" corpus as evidence of a DUT defect, and any
> conclusion resting on it. The original "CHUNK=30 passed, CHUNK=50 failed 1-in-4" was n=1
> per setting against a random ~30% connection-drop process.
>
> **NOT INVALIDATED — hold this line precisely:**
> - **The TL-027 `w_inc` CDC defect** (§5e). Proven in *simulation*, independent of any
>   hardware run. **Mechanism real; causation to the field withdrawn.**
> - **The single obs-word capture** in which the register *changed* —
>   `0xB5000001 → 0xB5000600`, bit[9] 0→1, bit[0] 1→0. **An ssh reset cannot fabricate a
>   changed register value**; that read succeeded and returned different bits. One genuine
>   park may have occurred. This is now the strongest read-side datapoint we have and it
>   should be **re-taken with a fixed harness, not discarded.**
>
> **Consequence:** cross-die read remains **NOT VALIDATED** — but for a different and weaker
> reason than this section originally claimed. It is unvalidated because *the instrument was
> unsound*, not because failures were observed. Those are very different findings, and only
> the second would have been a defect.
>
> **Fix the harness before anything leans on it again:** keep stderr, distinguish `rc=255`
> from a data mismatch, add `ControlMaster`. Then re-run the corpus. **T6 endurance needs the
> same check** — 2 of 8 archived runs "failed at beat 1024", a fixed connection ordinal with
> the same empty-output signature.


Six sysval runs on the frozen pointer (one clean, one bad-eye, one void, three POR-recovered):

| run | bring-up | T2b canary | T3 write soak | T10 read soak | T6 endurance |
|---|---|---|---|---|---|
| 1 | try 1/8 | PASS 8/8 | **PASS 128/128** | **PASS 128/128** | FAIL — 5th of eight 256-beat chunks; see the retraction below — this is a BUCKET [1024,1280), not a beat |
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

**The full primary-source corpus is worse for the claim than the retraction above assumed. There
is n=1, not n=2.** The corpus is **9 sysval JSON artefacts plus 1 log-only run** (2026-08-09,
recorded in `run_categoryA_goodeye.log`, which predates JSON output) = **10 recorded runs**. The
table below counts the 9 JSON runs; the count-based statement further down counts all 10. Stated
explicitly because these two numbers previously appeared in this document without reconciliation.

| verdict | count | beats |
|---|---|---|
| **write-path wedge** | **1** | 1024 |
| obs-plane fault `(no-obs)` | 3 | **1024, 0, 0** |
| SKIPPED (link already down after T10) | 5 | — |
| **PASS** | **0** | — |

Two things this settles:

1. **Only ONE record in the entire corpus is a write-path failure.** The *other* "beat 1024" run
   took the obs branch at `:215-217`, which means `rc == 0` — **the 1024-1279 write chunk
   completed successfully** and only the follow-up `obs()` call returned nothing. The pack
   conflated a write wedge with an observability-plane timeout because both print the same beat
   number. They are different events.
2. **The obs-plane faults occur at beats 1024, 0 and 0** — the same code path, including **beat
   zero twice**. That is not a threshold. (An older 08-09 run failed the same way at 768.)

All obs faults are `(no-obs)`: the diagnostic plane did not answer, so **no Region-F witness
value has ever been captured for any T6 failure.** Note this interacts with the finding that the
observability plane shares a matrix port with the wedged path — "no-obs" may be a symptom rather
than a measurement, and must not be read as data either way.

**Defensible statement, and the only one that should reach submission text:** *a chunked
peer-write endurance soak has never passed (0 of 10 recorded runs). Of the failures, exactly one
was a write-path wedge, in the 5th of eight 256-beat chunks; the others were diagnostic-plane
timeouts at chunk indices 0, 0 and 4. No fixed beat threshold is established.*

**The discriminator that would settle it was designed on 2026-08-09 and has never been run:**
parameterise the hardcoded `step` at `kr260_sysval.py:208` and sweep chunk geometry across
independent bring-ups. Rig-only, no rebuild needed.

T6 having never passed is unaffected and is now primary-source verified: 0 PASS across every
artefact.

### 5d. ⚠ CORRECTION — cross-die reads ARE reachable by a shipping-path master

**Recorded 2026-08-24. An earlier assessment in this project concluded "nothing on a
shipping path reads cross-die" and used it to justify shipping the read defect. That
conclusion was WRONG and is retracted here.**

What the earlier analysis actually established: *no shipping firmware currently issues
a cross-die read.* That is true — `NANOSOC_D2D_PEER_BASE` has zero consumers, ethernet
BDs point at local scratch, PTP arrives as pushed wires, TideChart's bus master is
write-only and not instantiated.

**What the tapeout default requires is different: that no shipping-path master CAN.**
It can. Verified in the generated interconnect and the decode:

    multicore_ahb_interconnect.v:39-44   _DMAC_0_M -> ..., _D2D, ...   (5 initiators reach D2D)
                                         _D2D_M -> _SHARED_SRAM_0, _IPC_MAILBOX_0  (inbound only)
    multicore_matrix_decode_DMAC_0_M.v   0x2e000000-0x2fffffff -> MI12
    chiplet_d2d_decode.sv:200            hsel_peer = xfer & a_peer      <- NO hwrite term
    chiplet_d2d_decode.sv:228            hsel_peer ? DPH_PEER           <- read data returned

**The matrix decodes by ADDRESS BITS, never by symbol.** The DMA-250 and the ETHMAC DMA
both carry runtime-programmable source addresses; the peer decode is not write-qualified;
and the DMA's 32-bit source-address field is in the taped-out netlist with no address
filter. A DMA descriptor, an ethernet TX buffer descriptor, a CPU1 load, or a debugger
over SWD all reach it.

A documentation bug likely seeded the error: `nanosoc_multicore_addrmap.h:482` asserts
*"Only CPU0 (network_core) can reach it"* — the generated RTL contradicts its own header.

**Consequence for the shipping decision.** The schedule argument is untouched and remains
the operative reason to ship as frozen: every GDS run since 21 Aug is seeded from one
synthesis keyed on the flist hash, and re-synthesis must start by 27 Aug to finish. But
the risk side is no longer "the defect is on an unreachable path" — it is **a live,
programmable path that no configuration prevents**. Anyone weighing this must weigh it
that way.

**The reusable lesson:** reachability is a property of the address decode, not of the
symbol table. "No caller exists" and "no caller can exist" are different claims, and
only the second licenses shipping a defect as unreachable.

### 5e. The `w_inc` self-heal is now PROVEN as a mechanism — on all five nodes

Recorded 2026-08-24. The a2l CDC self-heal half of the AR/R fix, previously unproven on
every node including the three that ship, has been demonstrated in the existing two-clock
bench:

    NODE=7 override (w_inc = 1'b1)   PASS
    NODE=7 deps     (w_inc = edge)   FAIL -- 8/8 ACKs lost PERMANENTLY
    link-clk a2l_link_addr = [2,2,...]   app-clk synced ack STUCK at [1,1,...]

All five data-plane nodes, both arms, with a must-be-present control delivering 12/12 in
the same runs. The earlier header claim that "idle single-clock sim never tears -> silicon
verifies w_inc" was wrong about its own bench, which already had independent `app_clk` and
`link_clk`.

**Scope, stated deliberately:** this proves the MECHANISM exists and the fix addresses it.
**Causation to any observed silicon read failure remains OPEN** — the fix predicts a wedge
and the dominant observed signature is a data mismatch.

### 5f. Standing caveat on EVERY rig-sourced read result

The rig and the ASIC ship opposite CRC configurations on the R node:

    rig  (tidelink_fpga_v2.flist)          disable_crc <= 1'h1   CRC OFF
    ASIC (tidelink_top_full_asic_v2.flist) disable_crc <= 1'h0   CRC ON

With CRC off a corrupted read packet is **committed silently** — no NACK, no counter, no
flag. Every read measurement in this pack was taken in the OFF configuration. Silicon will
detect and NACK the same event, so rig read results do not transfer, in either direction.

**SECOND STANDING CAVEAT — the transport (added 2026-08-24, see §5b).** Every result sourced
from `kr260_sysval.py` was taken through a harness that opens a **fresh ssh connection per
board call** against a board configured `maxstartups 10:30:100`, and that **relabels
`rc=255` as a data mismatch** while discarding both stderr streams. Until that is fixed:

- **A sysval FAIL is not evidence of a DUT defect** unless the recorded detail contains
  actual data (`READCHUNK ... got0x... exp0x...`). **An empty detail string means the
  command never ran.**
- **A sysval PASS is still trustworthy** — the transport failure mode destroys results, it
  does not fabricate byte-exact ones.

**The asymmetry matters: this caveat invalidates reds, not greens.** Do not let it be used
to discount a passing result, and do not let a red be quoted from this corpus without
checking its detail string first.

### 5g. ⚠ BUILD PROVENANCE IS FAIL-OPEN — "built from the freeze" stamps are UNVERIFIED

**Every `git_dirty: false` FPGA manifest predating tidelink `df0f1f24` is UNVERIFIED, not
verified.** Found 2026-08-24 by tidelink-92, mechanism reproduced here.

`tidelink/fpga/scripts/build_provenance.tcl:76`:

```tcl
if { ![catch { exec git -C $root status --porcelain } st] && [string trim $st] ne "" } {
    set dirty "-dirty"
}
```

In a worktree whose `deps/*` are symlinks, `git status` exits **128**
(`error: expected submodule path 'deps/axi-chiplet-controller' not to be a symbolic link`).
The `catch` swallows the failure, the `&&` short-circuits, and **failure-to-evaluate is
written out as CLEAN — silently, with no warning.** Measured, same commit, opposite verdicts:

| tree | `git status` | stamped |
|---|---|---|
| `hostio-wt/tidelink` | rc=128 | `git_dirty: false` ❌ |
| `nanosoc-ethernet-chiplet/tidelink` | rc=0, 2 untracked | `git_dirty: true` ✅ |

The strongest instance: `imp/fpga/output/kr260-pair-onchip` (2026-07-24) stamps
`source_commit: "unknown"` **and** `git_dirty: false` — a build whose commit git could not
determine, recorded clean. Both fields derive from one proc (`:296`), so this is **one root
cause, not two bugs**.

**Consequence for this pack: there is no genuinely-clean `5e8bdb5a` eth-chiplet FPGA build on
this host. The honest ones are dirty at the same commit.** This does not change the tapeout
answer — it devalues the evidentiary standing of every "built from the freeze" claim,
including ones made here. Fixed upstream in `df0f1f24` (`rev2/hygiene`, unpushed).

**This is the third independent fail-open in the provenance chain**, alongside the gitignored
XHB500 tree (§3b) and the GDS runs' symlinked `scripts`/`inputs`. The pattern is the finding:
**three separate mechanisms each score "could not determine" as "clean".**

### 5h. The rule these corrections produced

Two reachability errors were made this week — one on each die, by different sessions, with the
same shape. §5d: "no caller exists" was used to support "no caller can exist", stopping at the
symbol table instead of the address decode. On the compute die: `ahb_sub_hprot` was traced as a
straight passthrough and called a live freeze-blocker, stopping at the passthrough instead of
the guard one file upstream (`nanosoc_compute_chiplet.sv:366`, whose rejection logic sits
**outside** the `` `ifndef SYNTHESIS`` at `:400-417` and therefore synthesizes).

Both traced a path until it confirmed the expected answer, then stopped. The rule, in
tidelink-92's words:

> **A reachability claim is not finished at the hop that confirms it — it is finished at the
> hop that could refute it.**

**Corollary for the twins, undocumented in either repo until now: the two dies are protected
against different halves of the same defect.** This die ties `ahb_sub_hprot[3:2]=00`
(`nanosoc_eth_chiplet.sv:995`), forcing `singles_burst=1` on reads **and** writes at the cost
of all burst performance. The compute die guards **writes only**, leaving cacheable-burst
reads on an XHB500 arm that has never executed in any test at any commit on either die.

## 6. Known limitations shipping with this freeze

1. **Peer-write throughput ~0.89 MB/s ON THE BENCH LINK CONFIG (50 MHz hclk) — NOT a silicon
   figure.** The source measurement carries an explicit caveat that was stripped when the number
   was carried here: *"absolute numbers are this bench's link config only; the RATIO is more robust
   than the absolute."* This pack itself records the rig at ~4.7-25 MHz and the ASIC target at
   ~100 MHz, so 50 MHz is neither. Scaled arithmetically to the ASIC target the figure is
   **~1.78 MB/s**, and that is a derivation, not a measurement — **no throughput figure in this
   tree has ever been measured on silicon.** Quote the ratio (75x/100x vs a posted burst), not the
   absolute. Structural: the per-word cost IS
   the B round trip; `s_axi_bvalid` returns across the link with no local early-B. Not optimisable in
   the wrapper, and pipelining outstanding singles cannot help (non-bufferable is non-posted by
   definition). The lever is link latency. See `TAPEOUT_LIMITATION_D2D_PEER_WRITE.md`.
2. **Multi-beat AXI bursts are UNAVAILABLE — switched off as collateral of the wedge fix, not
   because the burst bug is unfixed.** The distinction matters and the earlier wording obscured it.

   The corruption fix (`cap_done_r` / `hwdata_hold_r`) LANDED and gates 14/14, and
   `BURST_FIX_HARDENING.md` closes two of its three residuals. The one open bound — bufferable/EWR
   at depth>1, "neither exercised nor claimed" (§3) — sits on a path the tie-down makes
   unreachable. So nothing about bursts can corrupt in the shipping configuration.

   What ships instead is a capability gap. The tie-down zeroes `HPROT[3:2]`, but the two bits do
   different jobs in the bridge: **`hprot[2]` gates the wedge** (`core_addr.sv:235`, `hazard_add`)
   and **`hprot[3]` forces single-beat** (`core_addr.sv:147`, `singles_burst`). Only the first
   needed to die. Zeroing both is why peer-write throughput is one B round trip per word.

   **A recovery route is identified and its premise is LIVE — capability established, occurrence
   unmeasured.** The route: pass `hprot[3]`, keep `hprot[2]` low, restoring multi-beat while
   leaving `hazard_add` permanently false.

   *This entry previously read "measured as valueless". That was wrong and is retracted.* The
   measurement behind it — 291 files, 96 `hburst` assignments, all SINGLE, no fixed-length drivers
   — counted **constants in wrappers and testbenches**. The DMA-250 does not assign a constant, so
   the scan established "nothing hardcodes a burst", which was then reported as "nothing can emit
   one". Different claims; the stronger one was not what was measured.

   **The DMA-250 as rendered CAN emit fixed-length INCR.** Verified:
   `dma250_biu_CFG_MIN.sv:557` `assign hburst = xfer_ax_payload_dst.xfer_burst;` with explicit
   beat-counting for SINGLE/INCR4/INCR8/INCR16 at `:304-307`;
   `dma250_pch_rw_ctrl_CFG_MIN.sv:825-829` renders all four arms of the burst-type case, selected
   by `blen_tran_xfer = burst_len_t'(blen >> bsize)` (`:485`) where `blen` is an internal register
   loaded from the channel command path, not a render constant; and
   `dma250_pch_ctrl_fsm_CFG_MIN.sv:294/305/316` emits INCR4/INCR8 unconditionally in specific FSM
   states.

   **What is still open: does our traffic actually do it?** Nobody has shown that the deployed
   configuration programs a channel such that `blen >> bsize` lands on 4/8/16, nor that such a
   burst survives the path to TideLink's `ahb_sub` port. **The item is neither closed nor
   justified** — it sits behind one measurement: an AHB monitor on `hburst` at the D2D bridge
   during a real DMA run, counting non-`000`/`001` encodings. That is a measurement, not a patch,
   and it decides the item.

   If it fires, the bit split is the candidate — and `awcache = 0x2` (Modifiable-but-not-Bufferable,
   an encoding neither silicon arm exercised: today `0x0` COMPLETES, pre-fix `0x3` WEDGES) is the
   first thing to test.

   **Keep this distinct from the burst CORRUPTION fix**, which is closed and on the freeze
   (`d0a977aa`, per-beat W-consumption strobe, 14/14 on `g2_soc_pair`). The two are conflated
   easily: corruption is FIXED; multi-beat *performance* is switched off and its recovery is
   unquantified.

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
