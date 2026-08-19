# wedge_bench — the D2D AW-wedge regression gate

`imp/hw_gate/wedge_bench/` turns the existing minimal proof-of-mechanism
(`tidelink/cocotb/tidelink_axi_datanode_recovery/test_h1_a2l_full_no_crc.py`)
into a bench a candidate fix can be **gated** on: it reproduces the wedge
deterministically, proves it persists, and — the part that makes it a gate
rather than a demo — **fails when the fix is absent and passes when it is
present, both directions demonstrated below**.

Nothing under `tidelink/` is modified. The harness (`tb_top.sv`, `pad_skid.sv`,
`err_inject.sv`, `pair_v2_common.py`, `AHBSubMaster`'s conventions) is reused
in place; only the stall models, recovery hooks, wedge monitor and data
scoreboard are new. Simulation only — no hardware is touched.

---

## 1. The mechanism, as measured

Peer-ACK silence on die A's AW node closes **two independent locks**, not one.
The second was found by this bench and matters directly to the fix design:

| # | lock | signal | why it closes | what it blocks |
|---|------|--------|---------------|----------------|
| 1 | replay window | `a2l_full` → `app_ready=0` | `a2l_full` clears only when `a2l_link_addr` advances, and that needs a genuine peer ACK through `ack_nack_fifo` (`WlinkGenericFCReplayV2_1.v:75,80-83,121,168`) | `s_axi_awready=0` — the bridge stops accepting AWs |
| 2 | transmit credit | `fe_rx_is_full` | `fe_rx_ptr` is updated **only** on `isAckPacket \| isNackPacket` (`WlinkGenericFCSM.v:978`), so it freezes with the ACK stream; `_T_59 = link_valid & ~fe_rx_is_full` gates `a2l_fc_replay_link_advance` (`:385, :708`) | the FCSM stops transmitting — `rbin` stalls even when the app side is free |

Downstream, XHB500 holds `m_ahb_sub_hreadyout` at 0 for ever. There is **no
timeout and no self-clear on either lock**: measured `socl_l7_wdog_cnt` stays
flat at 0 and the AW FCSM sits in state 4 for the whole observation window.

**Consequence for the three fix workstreams: a fix that only drains the a2l
replay window does not recover the link.** The bench measured exactly that —
see the `drain_only` leg below: `a2l_full` goes to 0 and `s_axi_awready` goes
back to 1, while `ahb_sub_hreadyout` stays 0 and every subsequent write still
times out.

---

## 2. Running it

```sh
cd /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/imp/hw_gate/wedge_bench
. ./env.sh            # MANDATORY — see below
./run_gate.sh         # the whole ladder + the discrimination matrix
```

`env.sh` is the environment block from the task, in one file. Getting it wrong
makes ~40 unrelated suites fail in seconds on an unexpanded
`${CMSDK_FPGA_SRAM_V}`; that reads like a mass regression but is purely an env
fault.

Individual legs:

```sh
make wedge_healthy        # NEGATIVE CONTROL   -> must PASS
make wedge_repro          # wedge + persistence -> must PASS
make wedge_gate_absent    # THE GATE, no fix    -> must FAIL
make wedge_drain_only     # THE GATE, incomplete fix -> must FAIL
make wedge_gate_present   # THE GATE, two-lock fix   -> must PASS
make wedge_ackresume      # causal control      -> must PASS
make wedge_loss           # silent-drop check, good case -> must PASS
make wedge_loss_detect    # silent-drop detector self-test -> must PASS
```

### Stale-build discipline

flist RTL is **not** a make dependency in this project's cocotb envs, so a
stale `simv` reproduces old results perfectly and yields a confident wrong
answer. Every target here `rm -rf`s its own `sim_build_<leg>/` **and** `build/`
before invoking the sub-make (`KEEP_BUILD=1` opts out, for throwaway iteration
only). `run_gate.sh` additionally refuses to score any leg whose log does not
contain a fresh `recompiling module tb_top` line, and reports it as `STALE`
rather than as a pass or a fail.

---

## 3. What each test asserts

All five live in `test_wedge_gate.py`; the first four share **one** stimulus body
(`run_scenario`): bring up the pair with CRC off, sanity-write the peer,
install the stall, fill the replay window with peer-aperture writes, probe,
observe, then re-probe and audit peer memory.

### `test_wedge_occurs_and_persists` — the wedge is real and permanent
* non-vacuity (below) holds;
* the post-fill probe write returned `timeout` or `error`;
* `a2l_full=1 & app_ready=0` held for **≥ `WEDGE_PERSIST_CYCLES` (default
  26,001) contiguous cycles**, matching the margin of the original repro;
* it never cleared (`cleared_at is None`).

Corroboration recorded, not asserted: `s_axi_awready` low fraction,
`ahb_sub_hreadyout` low fraction, AW-FCSM state histogram, max
`socl_l7_wdog_cnt`.

### `test_wedge_recovers` — **the gate**
Same stimulus, opposite expectation. A candidate passes only if *all* of:
* **(a) non-vacuity** — a stall was actually installed, the wedge really
  formed, it was sustained (≥ `WEDGE_HOLD_MIN`, default 200 cycles), and
  `s_axi_awready` was low for ≥ 90% of the wedged cycles, i.e. the AW channel
  really was refusing writes. Deliberately **not** required: "some AHB transfer
  timed out" — that conflates *the wedge happened* with *the fix was slow*, and
  a fix fast enough that no master transfer ever hits the closed window is a
  better fix, not a vacuous run. Refused transfers are logged as corroboration;
* **(b)** the wedge then **cleared**;
* **(c)** the path is **usable again** — three fresh peer writes complete and
  land byte-exact;
* **(d)** no **silent** data loss, no corruption, no phantom writes.

It also refuses to run under `WEDGE_STALL=hard`, which Forces `a2l_link_addr`
itself and so makes any in-RTL fix impossible by construction.

### `test_healthy_no_wedge` — the negative control
Identical stimulus with the ACK stream left alone. Every write must complete
and land byte-exact, and `a2l_full` must never hold for `WEDGE_HOLD_MIN`
cycles — the same threshold the wedge legs must exceed, so the two directions
cannot drift apart. If this fails, every wedge verdict the bench makes is worthless.

### `test_loss_detector_can_fire` — self-test of the check above
Runs the healthy scenario, confirms the audit is clean, then mutates peer
memory three ways (zero a landed word, corrupt a landed word, write a word
nobody addressed) and re-runs the **same production audit**, which must report
one silent drop, one corruption and one phantom. A check that cannot fail is
not a check. Scope is stated in limit 3.

### `test_no_silent_data_loss` — no false recovery
The contract is **not** "never lose a beat" — a fix is allowed to give up on an
un-ACKed window. The contract is that every lost beat must have been
**reported** (HRESP=ERROR, or the transfer never completed). A beat the master
was told had succeeded and that is not in peer memory is a `SILENT DROP` and
fails.

For that to be a real check the bench drives **bufferable** fills
(`HPROT[2]=1`, `WEDGE_BUFFERABLE=1`): XHB500's early write response releases
the master before the data reaches the peer, which is the only path on this DUT
by which a lost peer write can be silent rather than reported. No such loss
occurred in the runs below — see limit 3 — which is why
`test_loss_detector_can_fire` exists.

---

## 4. Knobs

| var | default | meaning |
|-----|---------|---------|
| `WEDGE_STALL` | `ackpkt` | how the peer ACK stream is silenced — see below |
| `WEDGE_RECOVERY` | `none` | `none`, `poke_drain`, `poke_drain_credit`, `poke_ackresume`, `rtl` |
| `WEDGE_ARM_CYCLES` | 4096 | contiguous `a2l_full` cycles before a modelled fix fires |
| `WEDGE_PERSIST_CYCLES` | 26001 | persistence margin |
| `WEDGE_HOLD_MIN` | 200 | the single wedge/no-wedge threshold, used in both directions |
| `WEDGE_BUFFERABLE` | 0 | fills use HPROT[2]=1 (early write response) |
| `WEDGE_FIX_RTL` | — | space-separated candidate `.v` files to swap into the flist |

**Stall models** (`AckStall`):
* `ackpkt` *(default)* — Force `pkt_is_ack_pkt=0` in die A's AW FCSM: inbound
  ACK packets are never recognised. Closest to "the peer went silent", and the
  only mode that leaves `a2l_link_addr` **and** `fe_rx_ptr` free for a
  candidate fix to drive.
* `ackupd` — Force `a2l_fc_replay.link_ack_update=0`, one level further in.
* `hard` — `ackupd` **plus** Force `a2l_link_addr`. This is the original
  minimal repro; unrecoverable by construction, so it is a control for the
  bench, never a mode to gate a fix in. `test_wedge_recovers` refuses it.
* `txblock` — `ackpkt` plus Force `link_advance=0`, intended to make the window
  genuinely **undelivered**. **Measured unsound — do not gate on it**; see
  limit 2. Retained as a diagnostic only.
* `none` — the negative control.

**Recovery models** (`RecoveryAgent`):
* `none` — shipping RTL. Nothing happens.
* `poke_drain` — models a timeout that discards the un-ACKed replay window
  (`a2l_link_addr <- a2l_app_addr`). **Measured insufficient** (lock 2).
* `poke_drain_credit` — the above **plus** a credit resync
  (`fe_rx_ptr <- ne_rx_ptr`), re-poked whenever `fe_rx_is_full` reasserts.
  Clears both locks.
* `poke_ackresume` — releases the stall: the causal control.
* `rtl` — no bench action at all; recovery must come from RTL compiled in via
  `WEDGE_FIX_RTL`.

---

## 5. Gating a real RTL candidate

`gen_flist.sh` builds the bench's private flist from
`tidelink/flists/tidelink_fpga_v2.flist` and swaps any line whose basename
matches a candidate file. It matches on exact basename suffix (so
`WlinkGenericFCReplayV2_1.v` does not swallow `..._10.v`) and **hard-errors if
a candidate matches no line** — a silently ignored candidate is exactly the
false green this bench exists to prevent.

```sh
# both directions, same test, same stimulus
make wedge_rtl_absent                                   # must FAIL
make wedge_rtl WEDGE_FIX_RTL="/abs/WlinkGenericFCSM.v /abs/WlinkGenericFCReplayV2_1.v" \
               EXTRA_DEFINES=+define+YOUR_FIX_ENABLE    # must PASS
./run_gate.sh /abs/path/to/candidate.v                  # adds both legs to the ladder
```

`WEDGE_RECOVERY=rtl` means the bench takes **no action at all** — every
observed recovery has to come from the candidate's own logic. `EXTRA_DEFINES`
is forwarded to VCS, for candidates that sit behind a Verilog `ifdef.

`fix_ref/WlinkGenericFCReplayV2_1.v` is a worked example of the hook — a
bench-local drop-in with an `ifdef WEDGE_FIX_DRAIN` stall timer. **It is not a
proposed fix**: it only addresses lock 1, so the gate rejects it, which is the
point of shipping it (it demonstrates the hook compiles a candidate in *and*
that the gate does not rubber-stamp an incomplete one).

---

## 6. Demonstrated discrimination

All figures below are from **one ladder run of the shipped code**, every leg
built from scratch (`rm -rf sim_build_<leg>/ build/`) and every log carrying 87
fresh `recompiling module …` lines including `recompiling module tb_top`.
`run_gate.sh` re-checks that and would print `STALE` instead of a verdict if it
were missing. Raw logs: `logs/<leg>.log`, matrix: `logs/GATE_LADDER.txt`.

```
LEG            EXPECT ACTUAL MATCH    WHAT IT PROVES
----------------------------------------------------------------------------------------
healthy        PASS   PASS   yes      NEGATIVE CONTROL - healthy link must not wedge
repro          PASS   PASS   yes      wedge forms and persists >= WEDGE_PERSIST_CYCLES
gate_absent    FAIL   FAIL   yes      THE GATE with no fix - must FAIL
drain_only     FAIL   FAIL   yes      INCOMPLETE fix (replay window only) - rejected
gate_present   PASS   PASS   yes      THE GATE with a two-lock fix - must PASS
ackresume      PASS   PASS   yes      causal control - peer ACKs resume, wedge clears
loss           PASS   PASS   yes      recovery that restores delivery drops nothing silently
loss_detect    PASS   PASS   yes      silent-drop detector self-test - it CAN fire
----------------------------------------------------------------------------------------
GATE: GREEN -- every leg matched its expected polarity, including the two
      legs that are REQUIRED to fail. The bench discriminates.
```

### The discrimination, leg by leg

**`healthy` — the negative control (PASS).** Same 14 fills + probe + 3 post
writes, ACK stream untouched.
`19/19 peer writes landed byte-exact, longest contiguous a2l_full run = 0
cycles, 0 silent drops / 0 reported losses / 0 corruptions / 0 phantoms.`
The bench does not wedge on its own, so every wedge verdict below is about the
stall and not about the harness.

**`repro` — the wedge, and its permanence (PASS).**
`wedge asserted at cycle 7540; a2l_full=1 & app_ready=0 held for 109,785
contiguous cycles` (required ≥ 26,001) `and never cleared (cleared_at=None)`.
Corroboration over those same cycles: `s_axi_awready LOW 109,785/109,785
(100.0%)`, `ahb_sub_hreadyout LOW 109,783/109,785 (100.0%)`, AW-FCSM parked in
state 4, `max socl_l7_wdog_cnt = 0` — no timer anywhere is even counting.

**`gate_absent` — the gate with no fix (FAIL, as required).** Same stimulus,
`test_wedge_recovers`:
```
AssertionError: NO RECOVERY: the wedge held for 89784 contiguous cycles and
never cleared (observed 97323 cycles, recovery model 'none' arm=4096).
final:  a2l_full=1 app_ready=0 awready=0 hreadyout=0 wbin=9 laddr=1 rbin=9 ...
```
This is the direction that matters: **the gate cannot pass without a fix.**

**`drain_only` — an incomplete fix (FAIL, as required).** A *recurring* timeout
that drains only the a2l replay window. It does clear the first lock —
`cleared_at=11660`, `a2l_full=0`, `app_ready=1`, `s_axi_awready=1` — and the
gate still rejects it:
```
AssertionError: recovery cleared a2l_full but the path is still not usable:
post-recovery write outcomes = ['timeout', 'timeout', 'timeout']
```
The end-of-observation state says exactly why:
```
a2l_full=0 app_ready=1 awready=1 hreadyout=0
wbin=11 laddr=9 rbin=9   fe_rx_full=1 fe_ptr=2 ne_ptr=9
```
Lock 1 is open (`a2l_full=0`, `awready=1`) but `rbin` is frozen at 9 while
`wbin` has reached 11 — two AW words sat in the FIFO that the FCSM never
transmitted, because `fe_rx_is_full=1` (`fe_ptr=2` vs `ne_ptr=9`) was still
holding `link_advance` low. **This is the load-bearing result for the fix
workstreams: clearing `a2l_full` is necessary and not sufficient.**

**`gate_present` — a two-lock fix (PASS).** The same recurring timeout plus a
credit resync (`fe_rx_ptr <- ne_rx_ptr`), re-poked whenever `fe_rx_is_full`
reasserts:
```
VERDICT wedge_recovers: PASS -- wedge formed at cycle 7540, cleared at 11660
(4120 contiguous cycles), path usable (['ok','ok','ok']), 0 reported loss(es),
0 silent
[SB] issued=19 landed=19 silent_drops=0 reported_losses=0 corruptions=0 phantoms=0
```
Same test, same stimulus, opposite verdict from `gate_absent`. That pair is the
discrimination proof.

**`ackresume` — the causal control (PASS).** Releasing the ACK-silence force
alone recovers everything: `wedge formed at 7540, cleared at 17420 (9880
contiguous cycles), path usable, 8/9 landed, 1 reported loss, 0 silent`. The
wedge is exactly peer-ACK starvation — nothing else was needed to clear it.

**`loss` — no false recovery (PASS).** Bufferable fills (`HPROT[2]=1`, so the
master is released early and a lost beat *would* be silent), ACK-silence stall,
two-lock recovery: `19 landed, 0 lost, 0 silent drops, 0 corruptions`.

**`loss_detect` — the detector's own self-test (PASS).** Clean baseline, then
peer memory is mutated three ways and the *same production audit* is re-run:
```
[SELFTEST] issued=7 landed=5 silent_drops=1 reported_losses=0 corruptions=1 phantoms=1
  SILENT DROP  fill0 off=0x200 want=0xa5a50000 got=0x00000000 master_saw=OK
  CORRUPTION   fill1 off=0x204 want=0xa5a50001 got=0xbadc0de5 master_saw=ok
  PHANTOM      off=0x800 got=0xfeedface
```
See limit 3 for exactly what this does and does not establish.

### The RTL hook, demonstrated

`fix_ref/WlinkGenericFCReplayV2_1.v` (a stall timer that drains the replay
window, behind `+define+WEDGE_FIX_DRAIN`) was run through both legs with
`WEDGE_RECOVERY=rtl`, i.e. **with the bench poking nothing**:

| leg | candidate in the flist | `cleared_at` | verdict |
|-----|------------------------|--------------|---------|
| `rtl_absent` | no | `None` — 89,784 contiguous wedged cycles, never cleared | FAIL: `NO RECOVERY` |
| `rtl` | yes (`flist:269` → `fix_ref/…`, `+define+WEDGE_FIX_DRAIN` in the VCS args, 87 fresh `recompiling module` lines) | **31,244** after 23,704 contiguous wedged cycles | FAIL: `path is still not usable` |

Two things are established. The hook really compiles a candidate in and the
candidate really acts — nothing but the RTL moved `a2l_full`, and the two legs
differ observably (`cleared_at=None` vs `cleared_at=31244`). And the gate is
not a rubber stamp: it rejected the candidate anyway, with the right diagnosis
(the replay window cleared, the path did not), because `fix_ref` only addresses
lock 1.

### Threshold margins

`WEDGE_HOLD_MIN=200` is the single wedge/no-wedge threshold, used in both
directions so they cannot drift. Measured margin is ~20x each way: the healthy
control's longest contiguous `a2l_full` run was **0** cycles; the shortest
wedge any stalled leg produced was **4,120**.


---

## 7. Honest limits

Read these before quoting a green from this bench.

1. **The stall is injected, not emergent.** Peer-ACK silence is modelled by a
   cocotb `Force` of `pkt_is_ack_pkt=0` inside die A's AW FCSM. It is faithful
   to the RTL — `a2l_link_addr` and `fe_rx_ptr` both freeze exactly as a real
   silent peer would freeze them, because both are fed from
   `ack_nack_fifo` — but it is still an injected fault. The bench does not
   prove the peer *does* go silent on silicon; it proves what happens when it
   does.

2. **`txblock` is not a valid gating stall — measured.** Forcing
   `link_advance=0` freezes the FIFO read pointer mid-packet, the far die then
   sees an unexpected packet number and NACKs, and the NACK's `link_revert`
   rewinds `a2l_link_addr` *and* `fifo_io_rbin_ptr` together (the TL-032
   revert-aware rewind), releasing the very freeze the mode was meant to
   install. Observed directly: `laddr` and `rbin` both jumped to 6 at the same
   instant. `txblock` is retained as a diagnostic only; do not gate on it.

3. **No DUT-produced silent drop could be constructed.** On this harness an AHB
   write completes only when its B response returns, so a peer write lost in
   the link surfaces as a timeout or `HRESP=ERROR` — *reported*, not silent.
   The one early-completion path, XHB500's bufferable write
   (`HPROT[2]=1`, `WEDGE_BUFFERABLE=1`), only grants its early response while
   `s_axi_awready` is still high, i.e. before the window closes, and those
   writes were measured to land. So the silent-drop arm of the audit is proven
   by a **memory-mutation self-test** (`test_loss_detector_can_fire`), not by a
   DUT-produced loss. That is weaker evidence and is labelled as such. The
   check is wired to the real production audit and to real peer memory, so it
   will fire if a candidate fix introduces an early-completion path — which is
   exactly the risk the check exists for.

4. **The "fix present" leg is a bench model, not RTL.** `poke_drain_credit`
   is cocotb Forces standing in for a recurring stall timeout that clears both
   locks. It shows the gate *can* be satisfied and what a satisfying fix must
   do; it is not itself a fix, and it does not prove any particular RTL is
   synthesisable or safe. The RTL hook (`WEDGE_FIX_RTL`) is the path for real
   candidates and is verified to swap files into the flist and hard-error on a
   candidate that matches nothing.

5. **`fix_ref/` only addresses lock 1**, so the gate rejects it. That is
   deliberate — it demonstrates the hook without pretending to be a fix — but
   it means the bench has not yet been run against any real candidate.

6. **Coverage is narrow.** Single die pair, `REF_PERIOD_NS=40`, CRC off,
   single-beat writes on the AW path only. No bursts, no read path, no
   concurrent PTP/TideChart traffic, one test per simulation (the suite's
   convention: a second `run_bringup_full` does not re-POR cleanly).

7. **`socl_l7_wdog_cnt` stays flat at 0** through every wedge run. The AW
   FCSM's existing watchdog is *not* a viable trigger for this wedge, matching
   the original H1 probe's finding. Any fix that expects to hang recovery off
   that counter will not fire.
