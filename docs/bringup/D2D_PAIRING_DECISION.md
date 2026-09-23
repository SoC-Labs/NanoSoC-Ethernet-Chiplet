# D2D pairing record — which die is which

**Status: RECORD OPEN. Created 2026-09-23 by dam1n19 (david@mapstone.me).
ONE FIELD IS UNFILLED — §2. It must be filled before the 2026-09-24 submission.**

This file exists because the eth↔compute pairing has, until now, been held only in
conversation. It is the ETH side of a two-sided record: the compute side's copy is
`~/SoCLabs/NanoSoC-Compute-Chiplet/nanosoc-compute-system/compute-subsystem/firmware/Makefile:61–80`,
which cites this repo back. Neither file is complete without the other.

**If you are bringing up the pair, read §2, §3 and §5a and nothing else.** §5a says
which eth FPGA image faces compute's. The role does not decide it.

---

## 1. The pair

| | **Ethernet die** | **Compute die** |
|---|---|---|
| Repo | `~/SoCLabs/nanosoc-ethernet-chiplet` (this one) | `~/SoCLabs/NanoSoC-Compute-Chiplet` |
| IDCODE part number | `0x0001` | `0x0002` (reserved) — `docs/bscan/IDCODE_DECISION.md` |
| Role is set by | a host, at runtime — **settable** (mask-fixed only if the parked resident writer lands, §3) | the manager stage-1 image, **loaded from QSPI flash — reflashable, even on silicon** |
| Where | `tidelink/pynq_host/scripts/kr260_eth_bringup.py:271` (`--role`, no default) | `.../compute-subsystem/firmware/Makefile:80` (`COMPUTE_D2D_ROLE_MASTER ?= 1`) |

These are the only two dice in the pair. There is no third.

---

## 2. THE DECISION — **UNFILLED**

> ### This die (ethernet) is: `________________`  ← **die_a (master) or die_b (slave). FILL THIS IN.**
>
> Decided by: `________________`  on: `________________`

**Do not fill this in without reading §5.** The compute side has already committed
to `die_a` / **master**, and the two sides must be complementary. If this die is
also made `die_a`, the pair has two masters and will not train.

Once filled, the value is consumed in exactly one place on this side: the `--role`
argument, §3. Nothing in this repo's RTL or firmware needs to change.

---

## 3. How to apply it (eth side)

```bash
# both boards, at the same time, from the dev host:
KR260_HOST=<eth board>     KR260_ETH_ROLE=<the value from §2> \
    bash tidelink/pynq_host/scripts/kr260_eth_run.sh bringup
```

`--role` has **no default** and `--bringup` refuses to run without it
(`kr260_eth_bringup.py:447–448`). That is deliberate: this die cannot drift into a
clash by accident, and nobody arrives at a role without choosing one.

**The role does not choose the eth FPGA image.** Against compute's
`kr260-compute-chiplet`, load **`kr260-eth-chiplet` (non-flip)**, whatever role
this die runs. The runbook's "die_b → `-flip`" rule (`KR260_BENCH_RUNBOOK.md:36`)
applies only to the eth↔eth pair. Used here, it puts both forwarded clocks on AC14
and neither die trains. See §5a.

**There is no resident writer on this die.** Nothing in this repo's firmware or RTL
writes `ROLE_CFG[1]`; the only writer is the external KR260 PS host above
(`kr260_eth_bringup.py:271`). With no host attached, `role_lock` never latches,
`wlink_por_reset` stays asserted, `pad_clk_tx` stays gated — and because the compute
die's RX link clock *is* this die's forwarded `pad_clk_tx`, **neither die trains**.
Verified 2026-09-22. A host is therefore mandatory for eth-side bring-up, not a
convenience.

**A resident writer exists, and is PARKED, not landed** (2026-09-23): the
`nanosoc-multicore-system` branch `park/resident-role-writer-2026-09-23`, commit
`7f17cbc`. It writes `ROLE_CFG` at `0x2E032080` as the sixth instruction of CPU1
stage-0 `main()`. **In sim it trains the pair with no host**: shipping V2 PHY,
calibrator sim bypass off, one ROM image per die. Both dice reach `FCSM==4` with
`cal_done=1` at 9,496 µs, and the negative control stays dead for 60 ms. That is a
functional result, not a margin one: ideal pads, one seed. Landing it is a full
RTL→GDS re-run, because the ROM is mask-programmed and rebuilt inside every run
(`ASIC/rom_build.mk:20-24`). It would make this die's role **permanent**.
`ETH_D2D_ROLE` has no default, and building it unset is a compile error.

---

## 4. The `die_a`/`die_b` ↔ master/slave mapping

This mapping **is** recorded, in RTL, and this section only restates it. The
authority is the chiplet controller, not any script or document:

| name | `ROLE_CFG[0]` | `ROLE_CFG` write | role | evidence |
|---|---|---|---|---|
| `die_a` | `0` | `0x02` | **master** / grandmaster | `tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv:637`, `:679` |
| `die_b` | `1` | `0x03` | **slave** | same |

- `axi_chiplet_controller.sv:637` — `ROLE_CFG [0]=role (0=master,1=slave), [1]=role_lock (W1S)`
- `axi_chiplet_controller.sv:679` — `wire role_is_master = ~role_effective;` (so role bit `0` ⇒ master)
- `axi_chiplet_controller.sv:175` — `role_strap_i, // 0=master, 1=slave (strap default)`
- Host side agrees: `kr260_eth_bringup.py:88–89` (`ROLE_CFG_MASTER_LOCK = 0x02`,
  `ROLE_CFG_SLAVE_LOCK = 0x03`) and `:131–132` (`_ROLE_NAMES`).
- Compute side agrees: `.../firmware/manager_stage1/main.c:162`
  (`die_a master (0x02), die_b slave (0x03)`).

**`die_a` and `die_b` are ROLE names, not die names.** Nothing in the hardware ties
either name to a particular piece of silicon — which is the whole reason this file
exists. Two separate uses of the vocabulary are live in this repo and must not be
confused:

1. **The eth↔eth FPGA control pair** (`docs/bringup/KR260_BENCH_RUNBOOK.md:186–189`):
   two KR260 boards running two **different** ethernet images: board 1
   `kr260-eth-chiplet` (die_a ball map, strap 0) and board 2 `kr260-eth-chiplet-flip`
   (die_b ball map, strap 1). *(Corrected 2026-09-23: this line said "arbitrarily
   labelled". The label follows the image, and the image fixes the J21 ball map
   (§5a). The role is still `ROLE_CFG`.)* This says nothing about the ASIC pair.
2. **The eth↔compute ASIC pair** — this file. §2 is the only statement of it.

---

## 5. The contradiction that must be resolved before §2 is filled

Two committed statements, one in each repo, cannot both be true:

| where | what it says | dated |
|---|---|---|
| compute `.../firmware/Makefile:61` | "**ROLE: this die is MASTER (die_a).**" | 2026-09-22 (`541ace0`, `b2c1af0`) |
| eth `docs/design/CHIPLET_ALIGNMENT.md:175` | "**pin die_a grandmaster via `ROLE_CFG` master-lock**" — in context, this die | 2026-08-19 (`ab929f2`) |
| eth `docs/design/CHIPLET_ALIGNMENT.md:154` | compute's J21 ball map should "**match eth die_b now**" — puts compute in the `die_b` position. **RESOLVED §5a:** this is a ball map, not a role, and it holds with compute as `die_a` | 2026-08-19 (`ab929f2`) |

`CHIPLET_ALIGNMENT.md` is a month older and predates the compute side's decision;
it is also stale in detail (it cites `nanosoc_eth_chiplet.sv:47` for `DEVICE_CLASS`,
which is now `:81`). It should not be treated as the authority. But note that its
line 154 is a **wiring** claim, not a role claim — if compute's J21 ball map was in
fact built to the eth `die_b` position, whoever fills §2 needs to confirm that the
physical orientation still works with compute as `die_a`. Those are separable
questions. **The wiring question is now settled (§5a).** Compute's map was built to
the eth `die_b` position, and the wiring works with compute as `die_a`, provided the
eth board runs its **non-flip** image.

**CORRECTED 2026-09-23 — the premise this section originally argued from is
false.** It said compute's role is baked into a ROM and frozen at tapeout, so compute
should hold the fixed role and this die should adapt. **Compute's role is not in mask
ROM.** It is in the M0+ manager *stage-1* image (`manager_stage1/main.c:171`), which
compute's immutable stage-0 ROM loads from QSPI flash into IMEM
(`compute-subsystem/firmware/bootrom/main.c:5-8`). Baking it into ROM instead is
"Option Z" (`firmware/Makefile:183-195`, `COMPUTE_D2D_BOOTROM`), which is opt-in: no
Makefile sets it, and `gen_compute_soc.sh:105` states the ROM is byte-identical to
the default when it is unset. So:

- **As shipped, both sides are changeable** — compute by reflash, this die by `--role`.
- **If the parked resident writer lands** (§3), **this die becomes the mask-fixed
  side** and compute the adaptable one. The original argument inverts.
- **Both role orders train.** In sim on the shipping V2 PHY with the calibrator's
  sim bypass off, eth `die_b` + compute `die_a` and the reverse both reach
  `FCSM==4` (LINK_IDLE) at 10,452 µs.

What remains is a genuine choice, not a forced one: **`die_b`** is the zero-change
option (compute already defaults to `die_a`); **`die_a`** makes this die the
master/grandmaster, and compute reflashes its default.

**Cost of changing it later:** compute side, a reflash — possible on silicon. This
side, free while it stays a host argument; **permanent** the moment the resident
writer lands in mask ROM.

### 5a. J21 wiring on the FPGA bench — RESOLVED 2026-09-23

**Verdict: the J21 ball map does not depend on the role, but it does depend on the
image, and each chiplet has two images.** `CHIPLET_ALIGNMENT.md:154` asked compute to
copy "eth die_b's ball map". Compute did, and that holds with compute as `die_a`.
What it leaves is a rule for which **eth image** faces compute's.

- **The eth↔eth pair runs two images, not one.** `kr260-eth-chiplet` (strap 0,
  `DEVICE_CLASS` 1) and `kr260-eth-chiplet-flip` (strap 1, `DEVICE_CLASS` 2) differ in
  their J21 balls. The flip XDC swaps the TX and RX ball sets, including the two
  forwarded clocks. The ribbon is straight (`BCM_n ↔ BCM_n`), so the crossover is
  done by the flip XDC, not by the cable.
  Evidence: `tidelink/fpga/targets/kr260-eth-chiplet{,-flip}/kr260_eth_chiplet_tidelink.xdc:20-39`,
  `…/tidelink_design.tcl:140` (strap) and `:155` (class), and
  `KR260_BENCH_RUNBOOK.md:28-29`, `:35-37`. The ball lines have not changed since
  tidelink `a671f5b6` (2026-07-22), so they are the ones M1 trained on
  (2026-07-27, `KR260_BENCH_RUNBOOK.md:335`).
- **Compute's two images carry the same two ball maps, with flip/non-flip swapped.**
  Non-flip `kr260-compute-chiplet` matches eth `-flip` ball for ball: `pad_clk_tx_0`
  on AC14, `pad_clk_rx_0` on AD15
  (compute `tidelink/fpga/targets/kr260-compute-chiplet/kr260_compute_chiplet_tidelink.xdc:58-78`,
  compute tidelink `4e8dc3c`, unchanged since `d64554e` 2026-07-31).
  Compute `-flip` matches eth non-flip (`…-flip/kr260_compute_chiplet_tidelink.xdc:54-74`).
  Compute's toolkit builds only the non-flip image (compute `fpga/design.mk:177`).
- **The role cannot move a ball.** The board wrapper fixes each pad's direction
  (`tidelink_design_wrapper.v:27-30`, whole-bus connections at
  `tidelink_design.tcl:210-213`). `ROLE_CFG`, once locked, overrides the strap
  (`tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv:676-678`, identical in
  compute's tidelink).

**Trace: eth `kr260-eth-chiplet` ↔ compute `kr260-compute-chiplet`, straight ribbon**

| eth port (eth XDC line) | ball | J21 phys (BCM) | compute port (compute XDC line) |
|---|---|---|---|
| `pad_clk_tx` (`:20`) → | AD15 | 27 (0) | → `pad_clk_rx_0` (`:70`), **compute's RX link clock** |
| `pad_tx[0..7]` (`:21-28`) → | AD14 AC13 AA13 AB13 AG14 AH14 AG13 AH13 | 28 21 32 33 7 29 31 26 | → `pad_rx_0[0..7]` (`:71-78`) |
| `pad_clk_rx` (`:31`) ← | AC14 | 24 (8) | ← `pad_clk_tx_0` (`:58`) |
| `pad_rx[0..7]` (`:32-39`) ← | AB15 AB14 AE13 AF13 W14 W13 Y14 Y13 | 36 11 19 23 8 10 12 35 | ← `pad_tx_0[0..7]` (`:59-66`) |

Each of the 18 conductors has one driver and one receiver, and the lane index is
preserved. Phys pin numbers are from the compute XDC header (`:30-49`).

**Checked on the built bitstreams as well as the XDCs.** `PACKAGE_PIN` and `DIRECTION` were read
from the routed checkpoints with Vivado 2024.1, 2026-09-23. The eth
`fpga/build/landed` build (2026-09-14, non-flip, the image compute's plan names) and
the compute `fpga/build/cwallow` build (2026-09-17, non-flip) complement each other
on **18 of 18** pads. Eth `pad_clk_tx` is AD15 OUT and compute `pad_clk_rx_0` is
AD15 IN. Compute `pad_clk_tx_0` is AC14 OUT and eth `pad_clk_rx` is AC14 IN. The
eth legacy `kr260-eth-chiplet` / `-flip` pair (2026-08-21) also complements on
18 of 18. Eth `-flip` against compute `cwallow` is wrong on **18 of 18**.
Compute's single-core tree (`~/SoCLabs/fpga-single-core-20260923`, not yet
built) carries the same pad lines and strap 0.

**The four pairings:**

| eth image | compute image | result |
|---|---|---|
| `kr260-eth-chiplet` | `kr260-compute-chiplet` | **correct.** This is the pair both toolkits build today. |
| `kr260-eth-chiplet-flip` | `kr260-compute-chiplet-flip` | correct |
| `kr260-eth-chiplet-flip` | `kr260-compute-chiplet` | **dead, with contention.** Both dies drive AC14 and one set of 8 lanes. Nobody drives AD15. |
| `kr260-eth-chiplet` | `kr260-compute-chiplet-flip` | **dead, with contention.** Both dies drive AD15 and one set of 8 lanes. Nobody drives AC14. |

**The trap is the name.** With compute as `die_a`, this die runs `--role die_b`. The
eth runbook maps "die_b" to the `-flip` image (`KR260_BENCH_RUNBOOK.md:36`). For this
pair that is row 3: no forwarded clock reaches either die, and the bench shows a dead
link. Load eth's **non-flip** image and pass `--role die_b`.

**Two side effects of that choice (not wiring):**
- Eth's non-flip image carries strap 0 and `DEVICE_CLASS` 1 (`tidelink_design.tcl:140`,
  `:155`). `--role die_b` overrides the strap. It does not change `DEVICE_CLASS`, so the
  TideChart tie in §7 stands.
- Compute's own labels contradict each other. The non-flip BD Tcl says "die_a /
  straight" with strap 0, while its pin XDC says "die_b / STRAIGHT" (compute
  `fpga/design.mk:211-218` records this). The het repo's patch `0002-H6-compute-strap`
  (strap → 1 on the non-flip image) was written for compute-as-`die_b`. With compute
  as `die_a`, strap 0 already agrees with the role.

**Also on the same ribbon:** both chiplets put `uart_txd` on W12 (J21 phys 38; eth XDC
`:42`, compute XDC `:94`). A full ribbon ties the two outputs together. Strip phys 38
and 40 as well as 1/2/4/17 (compute `docs/FPGA_VALIDATION_PLAN.md` B10). This does not
stop the link training. M1 trained with the runbook's strip list (1/2/4/17,
`KR260_BENCH_RUNBOOK.md:23`), which leaves 38 connected.

**No eth↔compute FPGA pair has ever been brought up.** The het repo's last word is
"SOFTWARE-READY, bench run pending"
(`NanoSoC-Hetrogeneous-Chiplet-Testing/docs/ETH_COMPUTE_BRINGUP.md:3`, 2026-07-31).
Its last commit is 2026-08-06 (`815e64f`), and its audit says not to run the pair
(`CHIPLET_ALIGNMENT_AUDIT.md` R1). Compute's plan, written 2026-09-23 and uncommitted
(`docs/FPGA_VALIDATION_PLAN.md` G15), uses exactly the row-1 pair, with "Compute
master, eth `--role die_b`". The sim results in §5 cannot speak to J21: an RTL sim
has no package pins.

---

## 6. Where each side's role is set — exact citations

**Ethernet die (this repo) — settable at runtime:**
- `tidelink/pynq_host/scripts/kr260_eth_bringup.py:407–409` — `--role`, `choices=("die_a","die_b")`, **no default**
- `tidelink/pynq_host/scripts/kr260_eth_bringup.py:447–448` — `--bringup` errors out without it
- `tidelink/pynq_host/scripts/kr260_eth_bringup.py:88–89`, `:131–132` — name → `ROLE_CFG` value
- `tidelink/pynq_host/scripts/kr260_eth_bringup.py:271` — the actual `ROLE_CFG` write
- `tidelink/pynq_host/scripts/kr260_eth_run.sh:32`, `:68–73` — `KR260_ETH_ROLE`, no default, refuses without
- `tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv:637`, `:676–681` — the register and the role mux

**Compute die — reflashable (manager stage-1, loaded from QSPI flash):**
- repo `~/SoCLabs/NanoSoC-Compute-Chiplet`, submodule `nanosoc-compute-system`, branch `feat/m4-external-dap-bench`
- `compute-subsystem/firmware/Makefile:80` — `COMPUTE_D2D_ROLE_MASTER ?= 1` (**1 = die_a = master**)
- `compute-subsystem/firmware/Makefile:61–79` — the decision, its evidence, and the citation back to this repo
- `compute-subsystem/firmware/manager_stage1/main.c:162–168` — the `ROLE_CFG` write
- `compute-subsystem/firmware/manager_stage1/main.c:207+` — `die_a` originator programs the CAM
- `compute-subsystem/firmware/Makefile:60` — `COMPUTE_D2D_LINK_TEST ?= 1`, so the shipping
  manager image attempts bring-up and records the outcome to shared SRAM `0x50`/`0x58`

---

## 7. What is still unrecorded after this file

- **§2 itself**, until someone fills it.
- **Which physical package/board position each die occupies.** §4 fixes name→role;
  it does not fix die→name. The FPGA J21 half of §5's wiring question is **resolved
  in §5a**: the ball map follows the image, not the role, so pair
  `kr260-eth-chiplet` with `kr260-compute-chiplet`. §5a does not answer the silicon
  D2D crossover (package or PCB). No FPGA XDC covers it.
- **`DEVICE_CLASS`.** This die defaults `16'h0001` (`src/rtl/nanosoc_eth_chiplet.sv:81`)
  and compute is reported to default the same. That is a TideChart *election* tie, a
  separate mechanism from `ROLE_CFG` and not resolved by this file. `ROLE_CFG`
  master-lock does not depend on TideChart, so it is the belt-and-braces either way.

---

## 8. Related

- `docs/bringup/KR260_BENCH_RUNBOOK.md` — the eth↔eth FPGA control pair
- `docs/design/CHIPLET_ALIGNMENT.md` — eth↔compute alignment overlay (stale; see §5)
- `docs/bscan/IDCODE_DECISION.md` — the other place the two dice are named together
- `~/SoCLabs/NanoSoC-Hetrogeneous-Chiplet-Testing/docs/BRINGUP_GAPS.md` — the master gap list
