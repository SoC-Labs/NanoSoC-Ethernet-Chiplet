# D2D pairing record — which die is which

**Status: RECORD OPEN. Created 2026-09-23 by dam1n19 (david@mapstone.me).
ONE FIELD IS UNFILLED — §2. It must be filled before the 2026-09-24 submission.**

This file exists because the eth↔compute pairing has, until now, been held only in
conversation. It is the ETH side of a two-sided record: the compute side's copy is
`~/SoCLabs/NanoSoC-Compute-Chiplet/nanosoc-compute-system/compute-subsystem/firmware/Makefile:61–80`,
which cites this repo back. Neither file is complete without the other.

**If you are bringing up the pair, read §2 and §3 and nothing else.**

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
   two KR260 boards, both running an *ethernet* image, arbitrarily labelled board 1
   = `die_a` and board 2 = `die_b`. This says nothing about the ASIC pair.
2. **The eth↔compute ASIC pair** — this file. §2 is the only statement of it.

---

## 5. The contradiction that must be resolved before §2 is filled

Two committed statements, one in each repo, cannot both be true:

| where | what it says | dated |
|---|---|---|
| compute `.../firmware/Makefile:61` | "**ROLE: this die is MASTER (die_a).**" | 2026-09-22 (`541ace0`, `b2c1af0`) |
| eth `docs/design/CHIPLET_ALIGNMENT.md:159` | "**pin die_a grandmaster via `ROLE_CFG` master-lock**" — in context, this die | 2026-08-19 (`ab929f2`) |
| eth `docs/design/CHIPLET_ALIGNMENT.md:151` | compute's J21 ball map should "**match eth die_b now**" — puts compute in the `die_b` position | 2026-08-19 (`ab929f2`) |

`CHIPLET_ALIGNMENT.md` is a month older and predates the compute side's decision;
it is also stale in detail (it cites `nanosoc_eth_chiplet.sv:47` for `DEVICE_CLASS`,
which is now `:81`). It should not be treated as the authority. But note that its
line 151 is a **wiring** claim, not a role claim — if compute's J21 ball map was in
fact built to the eth `die_b` position, whoever fills §2 needs to confirm that the
physical orientation still works with compute as `die_a`. Those are separable
questions and only one of them is settled.

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
  it does not fix die→name, and §5's wiring question is open.
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
