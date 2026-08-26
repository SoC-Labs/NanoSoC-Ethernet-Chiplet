# ASIC first-silicon bring-up — HOSTIO4 / ADP debug port

**Status:** procedure, for use at a bench with **one die and no second chance**.
**Written** 2026-08-25/26, from RTL, the ASIC firmware build artefacts, the as-built pad table, and the shipped ROM mask geometry. **No hardware was touched and no EDA tool was run to write it.**
**Revision B, 2026-08-26** — six changes, listed in §0.6. Two of them change what you must run *in what order* (§5.0, §4.2); one closes a gate that would otherwise have deferred on silicon (§4.2); one removes a firmware route the FPGA sessions will have led you to expect (§6.3). Written the same way: no hardware touched, no EDA tool run.
**Supersedes, for ASIC use:** `docs/bringup/HOSTIO4_FUNCTIONAL_TEST_PLAN.md` §3 (bring-up ordering). That document remains the reference for *what each test does and why* — its §1 capability analysis, §1.5 hazard register, §2 test list and §4 coverage honesty are all still correct and are cited here rather than repeated. **Its §3 phase ordering is not correct for the ASIC and must not be followed literally.** §0 below says why.

> ## READ THIS BEFORE ANYTHING ELSE
>
> **The FPGA procedure assumes a quiescent bus in Phases B, C and D. On the ASIC there is no quiescent bus at power-on, and Phase F's "point of no return" has already been crossed before you send your first character.**
>
> `cpu1_bootgate` is tied `1'b1`, so CPU1 free-runs from power-on. Its boot ROM (`cc_rom`) writes the CPU0 boot gate on **every** terminating path — including the path where every boot candidate failed. That store is in the reticle: it is present in the shipped mask geometry at two sites and is absent from the eth ROM. §0.1 gives the whole chain.
>
> Six things follow, and they reshape the procedure rather than adding caveats to it:
>
> 1. **HIO-502 is a no-op on healthy silicon.** The gate it sets is already set. It survives only as a *conditional recovery action* (§7.3).
> 2. **HIO-106's expected value inverts.** Healthy fresh silicon reads `0x00000004` or `0x00000005`. **`0x00000000` is the reading that needs explaining** — and it is four different states, of which **only one is a silicon finding.** `HIO-106` now runs an eight-read ladder to say which. §3.2.
> 3. **HIO-107 is broken on the ASIC** and will report "CPU0 never ran" on a die where CPU0 ran perfectly. §3.7.4. A replacement is given.
> 4. **Every memory-integrity result in Phase D is inconclusive** until both cores are positively established as parked. §5.
> 5. **`[B]` Running Tier 2 destroys any firmware you have loaded, and nothing in Tiers 0–4 can restart the core.** This is an *ordering* constraint on the whole session, not a caveat on one test. §5.0.
> 6. **`[B]` The debug port cannot deliver firmware to CPU0 on this die.** It can on the FPGA, for a reason that does not transfer. The ASIC's route is the QSPI flash boot table. §6.3.
>
> **Rows marked `[B]` are new in revision B (2026-08-26). §0.6 lists all six changes and what each one is worth.**

---

## Contents

| § | |
|---|---|
| **0** | What changed from the FPGA plan, the evidence for it, and the measured ASIC/FPGA deltas — **§0.6 is the revision-B change list** |
| **1** | Pre-power checklist — including the open hardware decisions that gate everything |
| **2** | Phase A — the cold-boot capture. `HIO-001`, never once exercised, and Abort Gate 1 |
| **3** | Phase B — the boot-state ladder, then identity and census. Abort Gates 2–6 |
| **4** | Phase C — write behaviour, Abort Gates 7–8, and the PHC initialisation that must not be skipped |
| **5** | Phase D — **§5.0's ordering constraint first**, then memory integrity and the parking step that makes it mean anything |
| **6** | Phase E / F — cross-die, what "firmware" can and cannot mean on this die, and **§6.4, Ethernet's two-hop chain** |
| **7** | The SWD-is-silent differential diagnosis, ASIC edition |
| **8** | The first-silicon record sheet |
| **9** | When it goes wrong — including the case where HOSTIO is as blind as SWD |
| **10** | What is still unsafe to attempt on first silicon, and what this procedure cannot answer |

---

## 0. What changed, and what the evidence for it actually is

### 0.0 Evidence classes used in this document

Every asserted value carries a class. The classes are stronger than the FPGA plan's `M`/`R`/`B` in one specific way — **the ASIC has a class the FPGA never could: values verified against the shipped reticle.**

| Class | Meaning |
|---|---|
| **G** | **Verified at MASK GEOMETRY.** Extracted from the ROM's via programming in the tapeout stream and diffed word-for-word against the firmware image: `build/rom_verify/{cc,eth}_gds.{bits,json}`, `words_compared: 512`, `words_differing: 0`, gate last passed `2026-08-25T08:15:53Z`. **These values are in the reticle.** They are the only constants in this document that cannot be wrong for a build reason. |
| **R** | Read out of RTL or generated RTL, `file:line` given. Common to the FPGA and ASIC builds unless the row says otherwise. |
| **A** | Derived from an **ASIC-only** artefact — the as-built pad table, the ASIC SDC, the ASIC firmware ELF. Not dependent on any FPGA measurement, but still a build artefact: re-derive if the build moves. |
| **M-fpga** | Measured on the FPGA, 2026-08-25. **Does not transfer unless the row says why it does.** |
| **M-asic** | Measured on ASIC silicon. **This document contains none.** Every row of the record sheet in §8 exists to create the first ones. |
| **B** | From a specification artefact — yaml, RDL, C header. **Record and classify, never assert.** Four of these produced false reds on a good FPGA die (FPGA plan §0). |
| **OPEN** | Not established anywhere in this tree. Flagged, not guessed. |

### 0.1 The false assumption, and the chain that refutes it

The FPGA plan's Phases B–D assume nothing else is driving the bus while you read it. On the ASIC that is false from the instant power is applied. The chain, each link independently checkable:

| # | Link | Where | Class |
|---|---|---|---|
| 1 | `cpu1_bootgate` is tied `1'b1` — CPU1 **cannot** be held in reset. `cpu0_bootgate` is `chip_core_remap_ctrl_w[2]`. | `nanosoc_multicore_soc.sv:1387-1388` | **R** |
| 2 | `chip_core_remap_ctrl` resets to `4'b0000` on `PORESETn` only, and is **write-1-set** — `remap_q` is OR-ed with `HWDATA[3:0]`, so bits are only ever set, never cleared. It ignores `HADDR` entirely (`wire _unused = &{..., HADDR}`), so the whole `0x29xxxxxx` window is one 4-bit register. | `imp/fpga/nanosoc_multicore_ip/src/chip_core_remap_ctrl.v` | **R** |
| 3 | CPU1's ROM is `stage0_bootrom_chip_core`. Its `main()` releases CPU0 on the success path *and* on the all-candidates-failed path, by design and with the reason written out in the source: *"Still RELEASE eth/CPU0 so the network core runs its own SECONDARY stage-0 … otherwise a blank flash silently holds CPU0 in reset and the debug UART never transmits (the cpu0_bootgate silent-UART bug)."* | `nanosoc-multicore-system/firmware/bootloader/stage0_bootrom_chip_core/main.c` | **A** |
| 4 | GCC synthesised the address instead of using a literal pool entry: `movs r3,#164 ; movs r2,#4 ; lsls r3,r3,#22 ; str r2,[r3]`, i.e. `0xA4 << 22 = 0x29000000`. **This is why every grep for `0x29000000` in the ROM words came back empty — the constant is not in the image.** | `stage0_bootrom_chip_core.lst` @ `0x080004F4`, `0x08000528` | **A** |
| 5 | That eight-byte sequence — `A4 23 04 22 9B 05 1A 60` — is present in the shipped mask at ROM byte offsets **`0x4F4`** and **`0x528`**, and **absent from the eth ROM**. Verified in this session against `build/rom_verify/cc_gds.bits` and `eth_gds.bits`. Reported unanimous across all 23 build pins by the prior work; **this session confirmed it on the current shipping stream only.** | `build/rom_verify/` | **G** |
| 6 | The two sites are the two terminating paths. `+0x4F4` is followed by a second store of `0x1` (`subs r2,#3`), so the **success** path leaves the register at `0x5`. `+0x528` is followed by `dsb ; wfi ; b .`, so the **all-failed** path leaves it at `0x4`. | `stage0_bootrom_chip_core.lst` @ `0x080004F4`–`0x08000536` | **A** + **G** |

**You can check link 5 on the die itself, over HOSTIO, in four commands.** The cc boot ROM is readable at ADP `0x80000000`:

```
A x800004f4 ; R    ->  0x220423a4        # movs r3,#164 ; movs r2,#4
A x800004f8 ; R    ->  0x601a059b        # lsls r3,r3,#22 ; str r2,[r3]
A x80000528 ; R    ->  0x220423a4
A x8000052c ; R    ->  0x601a059b
```

**G.** Do this in Phase B. It converts the central premise of this procedure from something you were told into something you measured on the part in front of you.

### 0.2 What the ASIC boot actually does, in order — and every rung is HOSTIO-readable

This is the single most useful thing in this document. CPU1's stage-0 leaves a trail, and every mark on it is inside `debug_m`'s decode.

| Rung | ADP read | Healthy value | What it proves | Class |
|---|---|---|---|---|
| 0 | `0x800000E4` | `0x08000678` | The CPU1 ROM really is `stage0_bootrom_chip_core` — the ROM that writes the gate. The eth image reads `0x0800048C` here; that would mean the wrong image was baked into the CPU1 slot. | **G** |
| 1 | `0x98000200` | `0x0F1C0DE1` | CPU1 reached `main()`. It is the first statement in the function, before anything can fail. The address literal `0x18000200` and the marker `0x0F1C0DE1` are both in the reticle, at cc ROM `+0x538` and `+0x53C`. **Note the address: this is CPU1's OWN DMEM at ADP `0x98000200`. `0x18000200` from ADP is *eth* DMEM — a different physical RAM.** | **G** |
| 2 | `0x21000030` | `0x0000800B` | CPU1 wrote `AHB_SETUP` (Fast-Read 0x0B + 8 dummies). | **A** |
| 3 | `0x21000000` bit 8 | `1` | `CTRL.XIP_ACTIVE` latched. CPU1 got past `xip_enable()`'s readback check; if this is 0 the ROM took `halt()` there. | **A**/**R** |
| 4 | `0x23000010` | `0xD15C0001` | CPU1 published the XiP-warm handshake to IPC mailbox slot-1 data[0]. Literal in the reticle at cc ROM `+0x584`. **Caveat: a CPU1 *app* that booted will have overwritten this slot** — `chip_core_banner` uses it. Read it before Phase F, and read rung 5 to disambiguate. | **G** |
| 5 | `0x98000084` | `0xFFFFFFFF` (blank flash) or boot-table data | `g_tbl`, CPU1's 128-byte boot-table scratch, in `.bss`. Erased flash reads `0xFF`. Proves CPU1 executed a `copy_image` burst out of the XiP aperture. | **A** |
| 6 | `0x29000000` | `0x00000004` **or** `0x00000005` | A terminating path was reached. `0x4` = every candidate failed, CPU1 is now in `wfi ; b .` inside its ROM. `0x5` = a CRC-valid image was found, CPU1 set its own REMAP and branched into IMEM — **CPU1 is running an application.** | **R** + **G** |

**Read this ladder top-down in Phase B, before anything else, and record every rung.** It is the die's boot autopsy and it costs seven commands — nine with the two release-store sites §3.2 folds in — about 1.2 s of link time.

### 0.3 What `0x29000000 == 0x00000000` actually means

The brief for this document says `0x00000000` is the anomaly. That is right, but it is not one anomaly — it is four, and the ladder separates them. **In particular, on a bring-up board with no QSPI flash fitted, `0x00000000` is the *expected* reading, not a fault.**

**`[B]` `HIO-106` no longer just reads the gate.** On a zero it now runs the eight-read ladder itself and *classifies* the zero, so the test is the diagnostic rather than the trigger for one (`hostio_suite/tier1.py`, `_BOOT_LADDER` / `hio_106`). Read the table below as what that test will tell you. **Only the last row is a red.** The other three are diagnoses, and the third of them is the normal state of an unprovisioned board.

| Ladder state | Diagnosis | Class |
|---|---|---|
| Rung 1 fails (`0x98000200 != 0x0F1C0DE1`) | CPU1 never reached `main()`. Suspect the CPU1 core, its reset, or the ROM itself. Check rung 0 first — a wrong ROM image explains it without any silicon fault. | **A** |
| Rung 1 OK, rung 2/3 fail | CPU1 halted inside `xip_enable()` — `CTRL.XIP_ACTIVE` would not latch. `halt()` is `for(;;) wfi();`, a quiet park in ROM. Suspect the QSPI controller or its clock. | **A** |
| Rungs 1–3 OK, no rung 4, rung 6 still `0x00000000` | **BENIGN, and the most likely reading on a first bring-up board. Record it as a diagnosis, never as a fault.** `xip_enable()`'s warm-up read at `0x24000000` hit an AHB ERROR and CPU1 took `HardFault_Handler`, which is `b .` at `0x080001CE`. With no flash device the QSPI AHB wrapper holds `HREADYOUT` low for a 16-bit watchdog then ERRORs (FPGA plan HZ-6). **CPU1 is parked in a branch-to-self in ROM — the quietest bus state this die can be in.** CPU0 is still held in reset. | **A** + **R** |
| **Rung 4 published** (`0x23000010` = `0xD15C0001`) **and rung 6 still `0x00000000` on a RE-READ** | Contradiction. Rung 4 proves CPU1 survived `xip_enable()`, so it must have reached one of the two terminating stores — and both are in the reticle (§0.1). A zero then contradicts the mask. Re-read once (CPU1 may still be executing); if it holds, suspect the `0x29` decode arm or `chip_core_remap_ctrl`. **This is the only reading in this table that is a silicon finding, and the only one `HIO-106` fails on.** | — |

**`[B]` The benign park is worth something, not merely harmless.** A CPU1 sitting in `b .` at `0x080001CE` with CPU0 still in reset is the quietest bus state this die can reach without spending an irreversible bit — **quieter than anything §5.3's parking step can buy you, and free.** Every reading taken in that condition — the §3.5.1 uninitialised-SRAM swath above all, but also the census and any Phase-D spot check — is unusually trustworthy, because there is provably no other initiator. **If the ladder puts you here, take your one-shot measurements now.** Note the corollary: §5's quiescence argument is about the general case, and this particular case is better than it.

> **The watchdog interval is a function of the clock you supply, not a constant.** 65 536 `HCLK`. At the SDC's 100 MHz that is **0.655 ms**; at the FPGA's 25.010 MHz it is 2.62 ms. Note the FPGA plan's HZ-6 quotes "≈ 1.3 ms", which implies 50 MHz — a rate neither target runs at. Use `65536 / f_CLK`, with the `f_CLK` you measured in §3.6, not a quoted figure.

### 0.4 The measured ASIC/FPGA deltas this procedure carries

| | FPGA (KR260, where every `M-fpga` value was taken) | ASIC | Class | Consequence |
|---|---|---|---|---|
| **Fabric clock** | **25.010 MHz** measured; routed report 25.011 | SDC target **100 MHz** (`create_clock -period 10.0 [get_ports CLK]`). **There is no PLL and no divider**: `assign SYS_HCLK = SYS_FCLK;` (`slcorem0p_prmu.v:91-93`) and `SYS_FCLK` comes straight off `uPAD_CLK_I`. **The ASIC fabric clock is whatever your oscillator supplies.** | **A** | Open hardware decision §1.2. Everything time-derived — `NS_INCR`, the QSPI watchdog, timer reloads — follows your board, not the SDC. |
| **eth boot ROM** | `smoke_remap` | `stage0_bootrom`. **320 words; 172 of them differ from `smoke_remap`; the first difference is at word 55.** Verified this session by word-diffing the two `.bin`s. | **A** | Every eth-ROM expected value in the FPGA plan is for the wrong image. Use the `eth_gds.bits` values in §8. |
| **`[B]` Debug-port firmware preload** | **works.** `smoke_remap` reads the image's SP and PC from the **always-mapped IMEM aperture** and `bx`es — it **never writes IMEM** — so an image preloaded over ADP survives the ROM and runs (`firmware/bootloader/smoke_remap/main.c`, the `remap_and_jump` naked block). | **does not work for CPU0.** `stage0_bootrom` `halt()`s if `CTRL.XIP_ACTIVE` is clear (`main.c:221`), and otherwise **copies a flash image over IMEM `0x10000000`** (`copy_image`, `:94-97,:145`) before CRC-checking it (`:149`) and halting if both candidates fail (`:238`). | **A** (+ **G** for the image identity) + **M-fpga** | **The delivery route for CPU0 firmware on this die is the QSPI flash boot table, not the debug port.** §6.3. Nothing about the FPGA's success here transfers — the two ROMs do opposite things to IMEM. |
| **eth DMEM word 0** (`0x18000000`) | `0x05F5E100` — `SystemCoreClock`, a **firmware build constant, not a clock register.** It is never a valid reference for this die's fabric rate; §3.6 is the only one. | **`0x00000000`.** `stage0_bootrom.elf` has **no `SystemCoreClock` symbol at all** and its `.data` is 104 bytes of zeros. `smoke_remap_bootrom.elf` does define it at `0x18000000`. | **A** | **This row will false-fail ABORT GATE 5** if the FPGA census class list is used unchanged. §3.5. |
| **PHC `NS_INCR`** | reset 4 → 0.1000× real time; writing 40 gave 1.0004×; restoring 4 gave 0.1000× | reset default is still 4 (`DEFAULT_NS_INCR = 8'd4`, `phc_apb_regs.sv:18`, commented *"4 ns for 250 MHz"*). At 100 MHz real time needs **10**, exactly, with no `NS_INCR_FRAC`. | **R** + **M-fpga** | **Not a blocker** — the register is RW and the remedy is proven on the FPGA. But an uninitialised PHC is *confidently wrong and reports no error*. §4.4 makes setting it a required step. |
| **TideLink ECC** | active | **bypassed** | **R** | TideLink readings are record-and-classify on first silicon. |
| **TideLink CRC** | `disable_crc = 1'h1` → OFF | `disable_crc = 1'h0` → **ON at reset** | **R** | Link bring-up timing will not match the FPGA. Do not fail a die for differing. |
| **FCSM recovery** | present | **stripped** | **R** | A link that enters a bad state will **not** self-heal. Budget a power cycle, not a retry. |
| **Ethernet MAC @ `0x40000000`** | unreachable (`R!` measured); **firmware read it exactly** — `MODER = 0x0000A000`, `PACKETLEN = 0x00400600` | unreachable, same structural reason | **M-fpga** + **R** | Firmware is the only route — and §6.3 shows HOSTIO **cannot load firmware onto CPU0 on this build.** **`[B]` On the ASIC that makes the MAC the far end of a two-hop chain — flash → firmware → MAC — that has never been exercised on any vehicle.** §6.4 |
| **`eth_ss_0` PS backdoor** | the workhorse of every FPGA session | **exists on no pin.** It is an internal SoC port. The complete external-host inventory on the die is **SWD (2 pins) and HOSTIO4 (7 pins)**. | **A** | Everything the FPGA work did through `eth_ss_0` has to be re-derived through HOSTIO or not done. |
| **`HOSTIO4_P1[0]`/`[1]`** | ordinary PMOD pins | **shared with JTAG TDI/TDO**, switched by the `SE` pin. Boundary scan and HOSTIO4 are **mutually exclusive**. | **A** | §1.3. This has no FPGA analogue at all. |
| **1PPS output** | present | **`phc_pps_out` is OPEN — no pad.** | **A** | PTP alignment can only ever be observed by reading PHC registers. |
| **Both UARTs** | present | **not bonded.** The eth stage-0's `halt()` prints `'X'` to a UART with no pin. | **A** | The FPGA plan's HIO-505 "firmware console" has no physical output on this die. |

### 0.5 One thing that does **not** change: the link is not four times faster

The ~130 ms per 32-bit read measured on the FPGA is set by the host's MicroPython pump loop and by HOSTIO4's six fully-interlocked beats per byte, **not** by `HCLK`. The SoC side of each beat is a two-flop synchroniser: 80 ns at 25 MHz, 20 ns at 100 MHz. **Budget the same ~130 ms per command on the ASIC.** Do not plan a session around a 4× speed-up; it is not there.

At 130 ms/command: Phase A ≈ 25 commands ≈ 3 s plus a power cycle. Phase B ≈ 160 commands ≈ 21 s. Phase C ≈ 130 commands ≈ 17 s. Phase D spot-checked is minutes; Phase D exhaustive is ~1.5 h (FPGA plan §4.1).

### 0.6 What revision B changed, 2026-08-26 — read this if you know the first issue

Six things were established after this document was first written. Each is marked `[B]` where it lands. **Two of them change the order of the session; none of them is a footnote.**

| # | What changed | Where | Class | If you skip it |
|---|---|---|---|---|
| 1 | **Running Tier 2 destroys any loaded firmware, and no tier below 5 can restart the core.** `HIO-203`/`HIO-204` carpet-write all 32 KB of eth IMEM and `HIO-208` carpets shared SRAM; **nothing in Tiers 0–4 pulses `CPU0_SWRST`.** | **§5.0** (new), §10.1 row 10 | **R** + **M-fpga** | You run your firmware-dependent tests against a wiped die and read the result as a silicon finding |
| 2 | **The debug-port firmware preload works on the FPGA and not on the ASIC**, for a reason that is in the two ROMs and does not transfer. **The ASIC's delivery route for CPU0 firmware is the QSPI flash boot table.** | §0.4, **§6.3** | **A** (+ **G** for image identity) + **M-fpga** | You spend bench time trying to boot CPU0 from the debug port, and read the ROM's own IMEM overwrite as a broken upload |
| 3 | **Abort Gate 8's write-path control moved to the QSPI `ADDR` scratch at `0x2100000C`**, off both RAMs. The old FPGA-plan location (`0x10001000`, eth IMEM) was justified on "IMEM is empty", which is false the moment anyone loads an image. **This also closed a real gap: the ASIC profile previously had NO control word, so Gate 8 would have deferred its positive control on silicon** — losing anti-vacuity on the gate that authorises the irreversible release. | **§4.2**, §3.5.1, §4.5, §8.6 | **R** | The one gate whose whole job is to be non-vacuous becomes vacuous, on the one die you have |
| 4 | **`HIO-106` now runs the eight-read ladder itself on a zero gate**, and classifies the zero into four states. **Only one of the four is a red.** The no-flash HardFault park at `0x080001CE` is benign, expected, and the quietest bus state the die can be in. | §0.3, **§3.2** | **A** + **R** | You abort a healthy unprovisioned die at B0, or you miss that the best measuring condition you will get is the one you are already in |
| 5 | **Ethernet is a two-hop chain on this die (flash → firmware → MAC) that has never been exercised anywhere.** The FPGA established what firmware CAN see, and isolated that board's MDIO fault to the physical line. | §0.4, **§6.4**, §10.2, §10.3 | **M-fpga** + **R** | You re-derive the FPGA's MDIO diagnosis on silicon, or read a two-hop failure as a MAC defect |
| 6 | **The PHC remedy is confirmed and the residual risk is now stated as a risk.** `NS_INCR` resets to 4, which is wrong on every target — real time needs `NS_INCR × f = 1e9`, so the ASIC wants **10**. MEASURED on FPGA: 40 gave 1.0004× real time, restoring 4 gave 0.1000×. It is RW, so this is a register write and not a silicon change. **The step itself was already in revision A; what is new is the explicit residual-risk statement and the `HIO-404` skip-record requirement.** | §0.4, **§4.4** | **R** + **M-fpga** | The die keeps time at 0.4× and reports no error — **a PTP clock that is confidently wrong is worse than one that is obviously dead**, because everything downstream will agree with it |

**Unchanged and worth restating, because a reader coming from FPGA notes will assume otherwise:** the FPGA fabric is **25.010 MHz**, measured against a host timer and matching the routed report to 0.004 % (§3.6). The ASIC's **100 MHz is an SDC target, not a property of the die** (§1.2). And `0x18000000` reading `0x05F5E100` on the FPGA is `SystemCoreClock`, **a firmware build constant compiled into `smoke_remap` — not a clock register, and never valid as a hardware rate reference.**

---

## 1. Pre-power checklist

Nothing below the line in §2 is meaningful until every row here is signed off. Two of these rows are **open hardware decisions that gate the entire bring-up** and cannot be closed from this repository.

### 1.1 OPEN HARDWARE DECISION #1 — where do the seven HOSTIO conductors land on the ASIC bring-up board?

**This is unanswered, and it gates everything.** On the KR260 the seven wires land on **PMOD3, bank 43** (and the note that *bank 43 works where bank 45 — SWD and LAN8720 MDIO — does not* is itself a live clue about the MDIO defect). On the HAPS-SX they land on PMOD3, bank 83, at `hostio4_p1[0..6]` → `BE18 BE19 BG19 BF19 BG16 BF17 BG17`. **Neither of those is the ASIC bring-up board.**

What the die gives you, from the as-built padring (`src/rtl/bscan/pad_table.json`, `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`) — **A**:

| Pad instance | Port bit | Cell | Ring index | Side | HOSTIO4 role (`FT1248MODE = 0`, EXTIO mode) |
|---|---|---|---|---|---|
| `uPAD_HOST_IO_0` | `HOSTIO4_P1[0]` | `PDDW16DGZ_G` | 23 | right | `IOREQ1` — SoC → host |
| `uPAD_HOST_IO_1` | `HOSTIO4_P1[1]` | `PDDW16DGZ_G` | 22 | right | `IOREQ2` — SoC → host |
| `uPAD_HOST_IO_2` | `HOSTIO4_P1[2]` | `PDDW16DGZ_G` | 21 | right | **`IOACK` — host → SoC, asynchronous** |
| `uPAD_HOST_IO_3` | `HOSTIO4_P1[3]` | `PDDW16DGZ_G` | 20 | right | `IODATA[0]` — bidirectional |
| `uPAD_HOST_IO_4` | `HOSTIO4_P1[4]` | `PDDW16DGZ_G` | 19 | right | `IODATA[1]` — bidirectional |
| `uPAD_HOST_IO_5` | `HOSTIO4_P1[5]` | `PDDW16DGZ_G` | 18 | right | `IODATA[2]` — bidirectional |
| `uPAD_HOST_IO_6` | `HOSTIO4_P1[6]` | `PDDW16DGZ_G` | 17 | right | `IODATA[3]` — bidirectional |

The role mapping is the HAPS-SX board top's, which is the only in-tree target that exposes the port; **it is a board-side convention that must be confirmed against the ASIC bring-up board's own wiring, not assumed.** If the roles are wrong the link will look simply dead, with no diagnostic.

**What the bench must decide and record before power:**

| # | Decision | Why it matters | Status |
|---|---|---|---|
| 1a | Which connector/pins on the bring-up board carry the seven, and in what order | Getting `IOACK` and an `IODATA` swapped gives a dead link that looks like dead silicon | **OPEN** |
| 1b | Are all seven on **one connector and one supply domain**? | `IOACK` is asynchronous and the four `IODATA` lines turn around; electrical proximity keeps handshake and nibble skew together. The FPGA targets did this deliberately. | **OPEN** |
| 1c | `VDDIO` level, and whether the host needs level shifting | The pad library is `tphn65lpgv2od3_sl` — the `od3` in that name is the 3.3 V I/O family, which is why the FPGA vehicles could wire an RP2350 straight onto a 3.3 V PMOD. **Confirm against the pad datasheet before connecting a host; do not take it from a library name.** | **OPEN** |
| 1d | Is a scope probe point available on `IOACK` and on at least one `IOREQ`? | §9.1's no-banner case has no software instrument. A scope on those two pins is the only thing that separates "the SoC never asserted a request" from "the host never acknowledged". | **OPEN** |

### 1.2 OPEN HARDWARE DECISION #2 — what drives `CLK`, and at what frequency?

`uPAD_CLK_I` → `soc_sys_fclk` → `SYS_FCLK`, and `assign SYS_HCLK = SYS_FCLK;`. **There is no PLL, no divider and no clock gate in that path** (`CLKGATE_PRESENT == 0` selects `SYS_FCLK` directly, `slcorem0p_prmu.v:87-93`). The 100 MHz in the SDC is a timing target, not a property of the die.

The same pad is **aliased onto `sys_fclk`, `rtc_clk` and `user_ref_clk`** — the v1 pad budget shares one pin between all three.

| # | Decision | Consequence | Status |
|---|---|---|---|
| 2a | Oscillator frequency on `CLK` | Sets `NS_INCR` (§4.4: `NS_INCR = 1e9 / f`), the QSPI no-flash watchdog (`65536 / f`), every timer reload, and the whole timing regime of the part | **OPEN** |
| 2b | Oscillator level and drive into a `PDDW04DGZ_G` input with **no internal pull** (`REN` tied high — see §1.4) | A floating or under-driven `CLK` gives no fabric clock, no banner, and the §9.1 double-blind | **OPEN** |
| 2c | Is `f` an exact integer divisor of 1e9? | 100 MHz → `NS_INCR = 10` exactly, `NS_INCR_FRAC = 0`. Anything else needs the fractional register and a stated residual error. | **OPEN** |

**Do not assume 100 MHz.** Measure it in §3.6 with the perf probe against a host-timed interval, and derive everything else from the measurement. The FPGA session got this wrong by exactly 4× once already, by estimating an interval instead of timing it.

### 1.3 Strap pins — `SE` and `TEST` must be LOW, and this is not a formality

**`SE` high turns `HOSTIO4_P1[0]` and `[1]` into JTAG TDI and TDO.** From `pad_table.json`'s `tap:` block: `tdi = uPAD_HOST_IO_0`, `tdo = uPAD_HOST_IO_1`, `en = uPAD_SE_I`. From `docs/bscan/BRINGUP.md`: *"`HOSTIO4_P1[0]` — the pad that becomes TDI — is a functional bidirectional pad whose output driver is enabled while `SE` is low. A JTAG master that drives TDI onto it before `SE` goes high is fighting a 16 mA output."*

**Boundary scan and HOSTIO4 cannot coexist. Sequencing between them is a bench hazard, not a formality.** If both are on the bring-up board, agree and write down which one owns the pins for this session, and physically disconnect the other master.

**`TEST` high bypasses every HOSTIO4 input synchroniser.** `hostio4_controller_sync` is `assign sig_s = (testmode) ? sig_a : sig_r[2];` — with `testmode` asserted, the asynchronous `IOACK` and the four `IODATA` status bits go straight into the FSM with no synchronisation at all. **R.** That is a metastability hazard on the one signal in the design that is explicitly documented as asynchronous.

| Strap | Required for this session | On-die default | Class |
|---|---|---|---|
| `SE` | **0** | `uPAD_SE_I` has `REN = tielo` → the weak **pull-down keeper is armed**. `SE` defaults low even if unbonded. | **A** |
| `TEST` | **0** | `uPAD_TEST_I`, `REN = tielo` → pull-down armed. Defaults low. | **A** |
| `NRST` | **driven, active low** | `uPAD_NRST_I` has `REN = tiehi` → **the keeper is DISARMED. `NRST` has no on-die pull of any kind and will float.** | **A** |
| `CLK` | **driven** | `uPAD_CLK_I`, `REN = tiehi` → **disarmed, floats.** | **A** |

`SE` and `TEST` are the good news: they fail safe. **`NRST` and `CLK` do not.** Both must be actively driven by the board.

### 1.4 Electrical requirements — and the one that is different on the ASIC

**On the ASIC all seven HOSTIO pads have `REN` tied HIGH, which *disarms* the keeper. There is no on-die pull-up or pull-down on any of the seven pins. They float.** (`REN : ACTIVE LOW pull enable — REN=0 arms the keeper`, `nanosoc_eth_chiplet_pads.v:36-40`; all seven `uPAD_HOST_IO_*` instances pass `.REN(tiehi)`.) **A.**

On the FPGA vehicles the IOBUF and board bias hid this. On the ASIC the board must provide the bias, and one of the seven has a required direction.

**`IOACK` must be biased HIGH.** The reasoning is in the RTL and it is worth stating in full, because getting it backwards produces a silent, permanent wedge:

- The `IOACK` synchroniser is instantiated with `RESET_VALUE(1'b1)` — it **presets to 1** (`hostio4_controller.v:55-64`). **R.**
- The FSM's reset state is `OFFZ`, and `OFFZ: nxt_fsm_state = (ioack_s) ? OFFZ : STAZ;  // hold idle if ACK high from reset` (`hostio4_controller_fsm.v:150`). **R.**
- `assign start_xfer = (cmd_req & !ioack_s);` (`:313`), and `cmd_req` is gated on `status_valid & iodata4_s[n] & pending_txn` (`:301-311`). **R.**

So: **`IOACK` biased high ⇒ the FSM parks in `OFFZ` and never starts a transfer into a host that is not there.** `IOACK` floating and reading low, with the four `IODATA` lines floating high, ⇒ the FSM leaves `OFFZ`, `cmd_req` asserts on the ADP's pending banner byte, `start_xfer` fires, and the FSM commits to a transfer, then blocks in `TXC1` waiting for an `IOACK` edge that will never come. **The banner is lost, the port is mid-transfer and out of phase, and a host attached later will find a link that looks dead.**

The `IODATA` synchronisers are the mirror of this and the RTL says so in a comment: they are `RESET_VALUE(1'b0)` because *"async status on iodata4 is active-hi so preset synchronizers to avoid spurious requests"*. That is the die protecting itself for the two clocks after reset only; after that the pins decide.

| Requirement | Value | Where it comes from | Class |
|---|---|---|---|
| `IOACK` pull-up | **required**, direction is not optional | FSM analysis above | **R** |
| Series resistors | **330 Ω** in each of the seven lines measured fine on the FPGA vehicle | FPGA bench | **M-fpga** |
| Worst-case low with 330 Ω series into a 5 kΩ pull-up | **204 mV** — comfortably inside a CMOS `V_IL` | `3.3 × 330/(5000+330) = 0.204 V`; arithmetic reproduced here and it is consistent with a 3.3 V rail | **M-fpga** |
| Bonding between host and die boards | **ground-only, with the two boards independently powered.** Do not back-feed the host's 3V3 into the target, or the reverse. | FPGA bench practice, and the HAPS-SX note *"don't back-feed the Pico's 3V3 into pin 6/12 while the HAPS board is powered"* | **M-fpga** |
| Bias on the other six | provide a defined idle level on all seven; only `IOACK`'s direction is dictated by the FSM | ASIC has no on-die keeper | **A** |

> **Do not carry the 330 Ω / 5 kΩ numbers over as though they were verified on this die.** They are the FPGA vehicle's numbers into an FPGA IOBUF. The ASIC pad is a `PDDW16DGZ_G` — a 16 mA driver — on a `VDDIO` you have not yet confirmed (§1.1c). The *method* transfers; the *numbers* need one re-check against the ASIC pad's `V_OL`/`V_IH` before you trust them.

### 1.5 Host-side readiness — four measured traps, none of them optional

All four are from `scripts/rig/eth_chiplet/hostio_adp.py` and `hostio_suite/CONTRACT.md`, all measured on the FPGA link, and **all four are properties of the host driver, so all four transfer to the ASIC unchanged.**

1. **The status-nibble polarity fix.** The reference PIO driver in `nanosoc_arch_tech/rtl/hostio4/rpi-pico-pio` idles the status nibble active-**low**; the shipping RTL (`hostio4_controller_fsm.v:301`) is active-**high**. **Used unmodified, the link looks simply dead.** Confirm your driver has the fix before you power the die — this failure mode is indistinguishable from a dead port and it will consume your one cold-boot capture.
2. **The resync watchdog must be live.** A starved watchdog gives 0/16 reads that look exactly like dead silicon. The host PIO has no timeout and cannot resynchronise itself: if SM0 samples RQ1 high while the target is unconfigured it parks at instruction 8/22 **holding ACK high**, which pins the SoC FSM in `OFFZ` forever. `pump()` calls `resync()` automatically when SM0 sits outside the idle loop. **Verify the watchdog on the host before the die is powered** — it is Abort Gate 1's precondition and there is no way to check it afterwards without spending the cold boot.
3. **`sm0.put()` blocks when its TX FIFO is full.** Every `put()` must be guarded on `tx_fifo() < 4`. This is the documented hang and it is how the port was wedged repeatedly.
4. **The first command after ESC is always rejected with `?`.** Send a throwaway (`C`) before anything that matters. `adp.enter()` absorbs it.

And the two formatting rules that govern every command in this document (FPGA plan §1.2, both measured):

- **Always write parameters as `x` + exactly 8 hex digits.** The parameter's *digit count* sets `HSIZE`. `W FF` is a **byte** write of `0xFF`; `Wx000000FF` is a word write. This applies to `A`, `R`, `W`, `P`, `V` and `M` alike.
- **`R` and `W` both auto-increment. Re-issue `A x<addr>` before EVERY access.** The only exceptions are the increment tests themselves and the block engines `R<n>`/`F<n>`/`U<n>`, which increment by design. Twelve of the FPGA plan's Revision-1 sequences got this wrong, including the irreversible one.

### 1.6 Pre-power sign-off

Do not apply power until every row is initialled.

| # | Item | § |
|---|---|---|
| 1 | The seven conductors are landed, identified, and the role mapping is confirmed against the board — not assumed from the HAPS-SX table | 1.1 |
| 2 | `VDDIO` level confirmed; host level-shifted if required | 1.1c |
| 3 | `IOACK` is pulled **high** | 1.4 |
| 4 | All seven lines have a defined idle level and series resistors sized against the **ASIC** pad, not the FPGA's | 1.4 |
| 5 | Grounds bonded; boards independently powered; no rail back-feed in either direction | 1.4 |
| 6 | `SE` = 0 and `TEST` = 0, confirmed by measurement not by "it has a pull-down" | 1.3 |
| 7 | Any JTAG/boundary-scan master on `HOSTIO4_P1[0]`/`[1]` is physically disconnected | 1.3 |
| 8 | `NRST` and `CLK` are actively driven — **neither has an on-die pull** | 1.3 |
| 9 | `CLK` frequency recorded, and the derived `NS_INCR` and QSPI watchdog written down | 1.2 |
| 10 | Host driver has the **active-high status nibble** fix | 1.5 |
| 11 | Host resync watchdog verified live, on the bench, before power | 1.5 |
| 12 | Scope on `IOACK` and one `IOREQ`, armed | 1.1d |
| 13 | Capture is **running and logging to a file** — §2 | 2 |
| 14 | Is a QSPI flash device fitted, and is it provisioned? **Write the answer down.** It decides which of §0.3's readings is expected. | 0.3 |

---

## 2. Phase A — the cold-boot capture

### 2.1 `HIO-001` — the one test that has never been run

`HIO-001` is the only test in the whole plan that proves the ADP **TX** path with **zero** dependence on the RX path. It is Abort Gate 1. **It has never been exercised on any vehicle**, because it skips on a running die and every FPGA run was warm: the FPGA plan's §6.1 records it as the first entry in the skip list — *"the runner refuses `HZ.RESET` without an explicit flag; needs a power-cycle capture the warm runs did not have."*

**You get one clean shot at it per die per power cycle, and it comes before you have any other instrument.**

### 2.2 The procedure

1. Complete §1.6 in full.
2. Bring up the host driver with the die **unpowered**. Confirm the resync watchdog is running (§1.5.2).
3. **Start capturing raw RX words to a file, and leave it running.** Not a terminal, a file. `adp.raw_rx()` in the suite harness is the primitive; capture RX **words**, 12 bits each, not decoded text — you will want the flow/control words later if this goes wrong (§9.1).
4. **Send nothing.** Any host stimulus destroys the one property this test establishes. No ESC, no `C`, no resync-triggered status re-advertisement beyond what the idle pump does.
5. **Apply power.**
6. Capture for at least 10 s. Save the file with the die serial in its name.

### 2.3 What to look for

| Observation | Verdict |
|---|---|
| Exactly one word matching `0x50c1ab..` , and it is **`0x50c1ab04`** | **PASS.** §2.4 says what that proves. |
| One word matching `0x50c1ab01` | **RED, and it is a build finding, not a silicon one.** `0x50c1ab01` is the `ADPBASIC` build (`socdebug_adp_control.v:64-68`). An `ADPBASIC` ADP has **no `F`, `M`, `P`, `U` or `V` commands** — the block fill, the poll engine and the binary upload are all absent, and about half of this procedure becomes unexecutable. Stop and establish which netlist was taped out. **R** |
| More than one banner | **RED.** The die is resetting repeatedly. Suspect `NRST`, the supplies, or a watchdog. Count them and record the interval — the interval is the diagnosis. |
| A prompt (`]`) follows the banner | **RED.** The banner is supposed to take the `STD_IOCHK` bypass at `ADP_LINEACK2:733` and leave the port *outside* the monitor. A prompt means it did not, and §3.1's "the cold die starts outside the monitor" premise — which Abort Gate 2 depends on — is false for this die. |
| No banner-shaped word at all | **ABORT GATE 1. Stop. Go to §9.1.** |

### 2.4 What the banner proves — four things from one word

This is the reason `HIO-001` is Gate 1 rather than a formality. The fabric clock and reset come from CPU1's PRMU, and the ADP hangs off that same clock and reset (FPGA plan §1.6, **R**). So a single `0x50c1ab04` on the wire proves, simultaneously:

1. **The core supplies are up.**
2. **CPU1's PRMU is released and running** — because `SYS_HCLK` is its output and the ADP is clocked from it.
3. **The fabric clock is toggling and `HRESETn` is deasserted** — a stopped clock or a held reset produces no banner.
4. **The ADP itself is out of reset** — `banner <= 1'b1` is set in the reset arm at `socdebug_adp_control.v:436` and is only cleared by having been transmitted.

And, negatively but just as usefully: it proves **the entire host→SoC direction is irrelevant to this result.** The banner is emitted with no host stimulus whatsoever. If the banner arrives and nothing else does, the fault is in exactly one direction and you know which.

### 2.5 A late banner is still the banner — but you have lost the timing

The banner is a **latched intent**, not a timed emission. `banner` is set at reset and cleared only after the word has been written out through the ordinary COM-TX handshake (`:723`, `:733`). If the host attaches late, or resyncs, the queued banner can still come out.

**Record the arrival time relative to power-on.** A banner at t+0.2 s and a banner at t+40 s after a resync mean different things: the first is a healthy cold boot, the second means something about the link's initial phase was wrong and you fixed it by accident. Neither is a fail, but only the first is a clean Gate 1.

### 2.6 Abort Gate 1, restated

> **ABORT GATE 1 — no banner-shaped word in the cold-boot capture. STOP.**
>
> **What a failure means:** nothing about the SoC has been established, in either direction. This is the only gate in the procedure whose failure is uninformative about the thing being gated.
>
> **What it does NOT mean:** it does **not** mean the die is dead. It does not distinguish a dead die from a dead link, a wrong pin map, a floating `CLK`, a floating `NRST`, an `SE` strap you did not check, or a host driver with the wrong status-nibble polarity. **Six of the fourteen rows in §1.6 produce exactly this symptom.**
>
> **What to do:** §9.1. Work the §1.6 list backwards with a scope before you conclude anything about silicon.

### 2.7 Phase A, the rest

| Step | Test | Gate |
|---|---|---|
| A0 | Host watchdog verified live (§1.5.2) — **before** power | Without it Gate 1 is not trustworthy |
| A1 | `HIO-001` cold-boot capture | **ABORT GATE 1** (§2.6) |
| A2 | `HIO-002`, `HIO-003`, `HIO-004`, `HIO-010` — monitor entry, bad-command rejection, exit/re-entry | **ABORT GATE 2** — see §3.1 for the ASIC-specific restatement, which is *different from the FPGA's* |
| A3 | `HIO-005`, `HIO-006`, `HIO-008`, `HIO-009`, `HIO-011`, `HIO-120` — address register, size encoder, auto-increment, block dump, GPO/GPI loopback, mask/value | If `HIO-006` fails, **every parameter in every later test is the wrong access size.** Stop. |
| A4 | `HIO-007` — the `R!` / `R ` control pair | **ABORT GATE 3: if `!` never appears, or never clears, stop.** Every OK/ERROR classification below is vacuous without a demonstrated two-sided flag. |

---

## 3. Phase B — the boot-state ladder first, then identity and census

This is the phase that changes most. On the FPGA, B1 was a single read of `0x29000000`. On the ASIC that one read cannot tell you what happened, and the value it returns is the opposite of what the FPGA plan expects.

### 3.1 ABORT GATE 2, and why the ASIC is the *only* place it is valid

The FPGA plan's Gate 2 says: send ESC, see no prompt ⇒ the host→SoC path is dead. That gate **fired on a healthy FPGA die and took nine tests with it**, because ESC is an *entry event only* (`FNvalid_adp_entry` is evaluated only in `STD_RXD1`): inside the monitor it is swallowed as a command letter and returns nothing.

The precondition — "the port was provably outside the monitor when the ESC went out" — **holds exactly once in the life of a power cycle, and this is that once.** The banner leaves the ADP in `STD_IOCHK`, the STDIO bypass (`:733`). A genuinely cold ASIC die at A2 satisfies the precondition for real.

> **ABORT GATE 2 — no prompt after the ESC, on a cold die that has just emitted its banner and received nothing since.**
>
> **What a failure means:** the host→SoC direction is not working. The banner already proved TX, so the fault is isolated to one PIO state machine, the four `IODATA` lines, and `IOREQ1`/`IOREQ2`. Scope those.
>
> **What it does NOT mean:** it does not mean the die is faulty. The most likely causes remain host-side: the status-nibble polarity (§1.5.1), a parked PIO holding ACK high, or the wrong pin mapping on three of seven wires.
>
> **When this gate is INVALID:** the moment anything has been sent to the port, or the banner was not the last event. **On any re-run — and there will be re-runs — force the bypass with `X` first and confirm it landed** (`_to_bypass()` in `hostio_suite/tier0.py` implements the two-probe discipline). A silent ESC alone is not evidence of a dead RX path on a warm port.

### 3.2 B0 — the boot-state ladder. Run this FIRST, before Gate 4

Nine reads, in this order. Record every one verbatim in §8 before running anything else. The full table with expected values and meanings is §0.2; this is the running order and the branch.

**`[B]` `HIO-106` now does this for you, and it is a diagnostic step rather than a check.** The suite's `HIO-106` reads `0x29000000` first and, **on a zero, runs the eight-read ladder below and classifies the zero into one of §0.3's four states** (`hostio_suite/tier1.py`, `_BOOT_LADDER`). Three of the four are diagnoses; **only "rung 4 published and the gate still zero on a re-read" is a red.** Run it by hand as written here if you are not running the suite — the value is in the classification, and a bare read of `0x29000000` cannot produce one.

```
A x800000e4 ; R      # 0 : which ROM is in the CPU1 slot         G  expect 0x08000678
A x800004f4 ; R      # 0': the release store, site 1             G  expect 0x220423a4
A x800004f8 ; R      # 0': the release store, site 1 (cont.)     G  expect 0x601a059b
A x98000200 ; R      # 1 : CPU1 main() entered                   G  expect 0x0f1c0de1
A x21000030 ; R      # 2 : AHB_SETUP written                     A  expect 0x0000800b
A x21000000 ; R      # 3 : CTRL, bit 8 = XIP_ACTIVE              A  expect bit 8 set
A x23000010 ; R      # 4 : XiP-warm handshake published          G  expect 0xd15c0001
A x98000084 ; R      # 5 : CPU1 g_tbl, boot-table scratch        A  expect 0xffffffff on blank flash
A x29000000 ; R      # 6 : terminating path reached              R  expect 0x00000004 or 0x00000005
```

**Branch on rung 6:**

| Rung 6 | Meaning | Where to go |
|---|---|---|
| `0x00000004` | Every boot candidate failed — the normal reading on an unprovisioned board. CPU1 is in `wfi ; b .` in ROM. **CPU0 has been released and is running its own stage-0.** | §3.3 |
| `0x00000005` | A CRC-valid image was found. CPU1 released CPU0, set its own REMAP, and **branched into IMEM. CPU1 is running an application** and you do not know what it is doing to memory. | §3.3, then treat every Phase D result as inconclusive until §5 |
| `0x00000000` | CPU1 did not reach a terminating path. **Read the ladder upward** and use §0.3's table. On a board with no QSPI flash this is *expected*, and it is the quietest bus state this die can be in. | §0.3 |
| anything else (bit 1 set) | `CHIP_CORE_BOOTGATE` is set. Nothing in either ROM writes it, and the SoC ties `cpu1_bootgate` to `1'b1` so it does nothing. **Record it as an unexplained reading** — it means something wrote this register that is not the ROM. | §8, and stop before Phase C |

### 3.3 B0b — CPU0's own trail

CPU0 is released on both of CPU1's terminating paths. It then runs `stage0_bootrom` (the eth ROM) and leaves its own marks. **A**:

| ADP read | Healthy | Meaning |
|---|---|---|
| `0x080000E4` | `0x0800048C` | The eth ROM slot holds `stage0_bootrom`, not the cc image. **G** |
| `0x18000084` | `0xFFFFFFFF` (blank flash), or boot-table data | eth `g_tbl` — CPU0 executed a `copy_image` burst out of XiP |
| `0x10000000` | `0x00000000` if nothing was copied; otherwise image data | eth IMEM. CPU0's ROM **overwrites this** on every boot attempt — see §6.3 |

**The eth ROM's `halt()` prints `'X'` to a UART that has no pad on this die.** Do not look for it.

### 3.4 B1 — Abort Gate 4, unchanged

`HIO-103` / `HIO-104` — `reset_ctrl` CID and PID at `0x2A000FF0`/`0x2A000FD0`. The CID bytes are `0x0D`, `0xF0`, `0x05`, `0xB1` at `0xFF0`/`0xFF4`/`0xFF8`/`0xFFC` (`nanosoc_reset_ctrl.v:97-100`, **R**), i.e. `0xB105F00D` assembled.

> **ABORT GATE 4 — wrong CID ⇒ the fabric is not decoding.** Nothing below is meaningful. Suspect the matrix, the `0x2A` decode arm, or `HADDR` routing from the ADP.
>
> **What it does NOT mean:** it does not implicate the ADP, which Gates 1–3 already exercised.

### 3.5 B2 — the census, with the ASIC class corrections. Abort Gate 5

Run the FPGA plan's §2.1 census — 35 probes, `A x<addr>` + `R` each, with `0x08000000` and `0x30000000` as the two controls — **with these four rows reclassified. Using the FPGA class list unchanged will false-fail Gate 5 on a good ASIC die.**

| Addr | FPGA class | **ASIC class** | Why it changes | Class |
|---|---|---|---|---|
| `0x18000000` | **D** (`0x05f5e100`) | **Z** (`0x00000000`) | The ASIC eth ROM is `stage0_bootrom`, which **has no `SystemCoreClock` symbol** and whose `.data` is 104 bytes of zeros. `smoke_remap_bootrom.elf` defines `SystemCoreClock` at `0x18000000`; `stage0_bootrom.elf` does not. | **A** |
| `0x10000000` | D/Z | **D/Z, and expect it to MOVE** | eth IMEM is CPU0's `copy_image` destination. It can hold flash data, partial data, or nothing, and it can change between two reads. Do not use it as a stable identity row. | **A** |
| `0x90000000` | D/Z (`0x00000000` on FPGA) | **D/Z, and expect it to MOVE** | CPU1 IMEM, same reasoning. Non-zero here on rung-6 `0x5` is *expected*, not an anomaly. | **A** |
| `0x2D000000` | Z (`0x00000000` on FPGA) | **record, do not classify** | Shared SRAM. Neither ROM writes it. On the FPGA this is zero because block RAM initialises to zero; **on the ASIC it holds whatever the TSMC macro powers up as.** See §3.5.1 — this row is a *measurement*, not a check. | **A** |

Everything else in the §2.1 list transfers, including its two `[R2]` corrections (`0x00000000` and `0x1FFFFFF0` are class **Z**, not **D** — Revision 1's classing of those two would have false-failed Gate 5 on a healthy FPGA chip too).

> **ABORT GATE 5 — any address in the wrong outcome class ⇒ stop and locate the decode fault.** Running later tests against a shifted map produces confident readings of the wrong register.
>
> **What it does NOT mean:** a single row disagreeing is far more likely to be a wrong *expectation* than a wrong *decode*. Four of the FPGA plan's expectations were wrong and every one of them cost a good die a red. **Before you abort on one row, check whether that row is class `B` or class `A` — if it is, it is a documentation finding until proven otherwise on the RTL.** Abort on a *pattern*: a whole region in the wrong class, or a control behaving wrongly.

#### 3.5.1 A measurement to take here and nowhere else — what does uninitialised SRAM read as on this die?

**Read a swath of shared SRAM at `0x2D000000` before anything writes it.** Sixteen words is enough: `A x2d000000 ; Rx00000010`.

Nothing in either boot ROM touches the shared SRAM, so on a fresh die this is the power-up state of a TSMC `rf_08k` macro, uncontaminated. **The answer decides whether several other tests in this procedure work at all:**

- **Mixed / pseudo-random:** then "reads exactly zero" is *evidence of an initialising write*, and §3.7.4's replacement for `HIO-107` works.
- **All zeros:** then zero carries no information anywhere on this die, `HIO-107` cannot be repaired, and every "reads zero" observation in Phase B is ambiguous between "initialised to zero" and "never written".

**`[B]` This measurement now survives all of Phase C.** Revision A's Gate-8 positive control wrote shared SRAM and destroyed it; the control moved to the QSPI `ADDR` scratch (§4.2) and no Phase-C step writes this RAM any more. It is still **destroyed by Phase D** (`HIO-208` carpets all 8 KB) and by any power cycle, and it cannot be retaken without one. **Take it in Phase B or lose it** — and if §0.3's ladder put you in the benign no-flash park, this is the cleanest condition you will ever read it in.

### 3.6 B3 — Abort Gate 6, and the clock measurement that must not be assumed

`HIO-402`. The restated form from the FPGA plan's Revision 2 is correct and transfers unchanged — **use it, not Revision 1's**:

> **ABORT GATE 6 — the gate trips ONLY on a counter that demonstrably counted and then stopped:** a **zero delta from a mid-range value, with a `CTRL[0]` SNAP written before each of the two samples.** A static `0x00000000` (never snapped) and a static `0xFFFFFFFF` (**saturated — positive evidence the clock ran**) are **SKIPs, not aborts.**
>
> **And the standing independent evidence:** the ADP is clocked from the same net as this counter. **A monitor that is answering you cannot be on a stopped `HCLK`.** Every register read in Phase B would still have "worked" if the fabric were really latched — but so would nothing else. **Do not power-cycle a die on this row.**
>
> The block's traps, all measured on the FPGA and all structural: `P0_CYC` at `0x2C200040` is a **shadow**, frozen until `CTRL[0]` SNAP; `CTRL` at `0x2C200008` is **write-only and self-clearing**, so reading it back as `0x00000000` is the correct answer; and the counters **saturate**, they do not wrap.

**And then use it to measure the clock you actually applied.** This is an ASIC-specific requirement, because §1.2 leaves `f_CLK` open:

```
A x2c200008 ; Wx00000002      # CLR the live counters
A x2c200008 ; Wx00000001      # SNAP
A x2c200040 ; R               # sample 1  -- start the HOST timer NOW
   ... wait a host-TIMED interval T, at least 15 s ...
A x2c200008 ; Wx00000001      # SNAP
A x2c200040 ; R               # sample 2  -- stop the HOST timer
f_HCLK = (sample2 - sample1) / T
```

**Time `T` on the host, with a clock. Do not estimate it.** The FPGA session estimated the interval once and got the fabric rate wrong by exactly 4×, because the client burns four commands × 2200 ms of pump per snap cycle. Re-measured against a host timer it gave 492,193,491 cycles over 19.680 s = 25.010 MHz, matching the routed report to 0.004 %.

Record `f_HCLK`. **Everything in §4.4 and §0.3 is derived from it.**

### 3.7 B4 — identity, and the four FPGA expectations that must not be carried over

Run `HIO-101`, `HIO-102`, `HIO-108`–`HIO-113`, `HIO-115`–`HIO-117`, `HIO-121`–`HIO-127`. **Record every value verbatim. This block is the die's fingerprint and it is what you diff between dies.** Four specific corrections:

**3.7.1 `HIO-101` / `HIO-102` are now class G, not class B.** The FPGA plan lists the boot-ROM anchor words and the `+0xE4` discriminators as build-artefact-derived and unverified. On the ASIC they are **verified against the shipped mask** (`build/rom_verify/`, 512/512 words identical for both ROMs). Use the §8 table's values and **assert** them. This is the only place in the whole procedure where a `B`-class row is promoted rather than demoted.

**3.7.2 `HIO-102`'s discriminator is load-bearing here in a way it never was on the FPGA.** It is rung 0 of the boot ladder. If `0x800000E4` does not read `0x08000678`, the CPU1 ROM is not the ROM that writes the boot gate, and **the entire premise of this procedure is void for this die.**

**3.7.3 Every TideLink and TideChart row is record-and-classify, not compare.** ECC is bypassed, CRC is on at reset, FCSM recovery is stripped. The marker bytes are structural and transfer — `0xB5` at `0x2E0321F8`, `0xAD` at `0x2E0321E0` — but **the status bits below them may legitimately differ and a die must not be failed for differing from an FPGA figure.** Note also that the FPGA run recorded `fcsm_state = 8`, outside the documented 0–7 range, with no peer attached; that encoding gap is still open and `HIO-407`'s signatures should not be used to diagnose anything until it is closed.

**3.7.4 `HIO-107` is BROKEN on the ASIC. Do not run it as written.**

`HIO-107` asserts consistency between the boot gate and CPU0 having run, using eth DMEM word 0: "bit 2 = 0 **and** `0x18000000` = 0 ⇒ consistent, CPU0 never scatter-loaded `.data`." On the ASIC, **`0x18000000` is `0x00000000` whether or not CPU0 ran**, because the ASIC eth ROM's `.data[0]` is zero (§0.4). The test will report "CPU0 never ran" on a die where CPU0 ran perfectly. It is a false red waiting to happen and it sits right next to the most important decision in the procedure.

**Replacement, valid only if §3.5.1 showed uninitialised SRAM is not all-zero:**

```
A x18000000 ; Rx00000010     # the initialised region: .data [0x00,0x68) + .bss [0x68,0x104)
A x18000200 ; Rx00000010     # an UNINITIALISED region of the same RAM
A x18000084 ; R              # eth g_tbl -- 0xFFFFFFFF on blank flash
```

CPU0's `Reset_Handler` copies `.data` to `0x18000000..0x18000068` and zeroes `.bss` to `0x18000104`. So: **the initialised region reading exactly zero while `0x18000200` reads mixed is positive evidence the scatter-load ran.** Both regions reading mixed means it did not. `0x18000084` reading `0xFFFFFFFF` is independent, stronger evidence — it means CPU0 got as far as a `copy_image` burst out of the XiP aperture.

**This replacement is inferred, not measured.** It rests on TSMC `rf_*` macros powering up non-deterministically, which §3.5.1 tests directly and which the FPGA could never have tested because block RAM initialises to zero. **If §3.5.1 comes back all zeros, record `HIO-107` as NOT EXECUTABLE on this die rather than passing or failing it.**

### 3.8 B5 — the bus-fault monitor, read before anything can disturb it

`bus_fault_monitor` at `0x2C300000` is a **first-fault recorder**. `HIO-108` reads its `BFM1` magic at `0x2C300010` = `0x42464D31` (`src/rtl/wrappers/bus_fault_monitor.v:282`, **R** — this one *is* RTL-confirmed).

**On a die with no responsive QSPI flash, §0.3 predicts a recorded first fault at `0x24000000`.** That is a falsifiable prediction you can check in three reads, and it would independently confirm the whole no-flash diagnosis.

**But the register offsets around the magic and the initiator-index map (0 `eth_ss_m`, 1 `cpu_ss_1_m`, 2 `dmac_0_m`, 3 `dap_ss_0_m`) are class `B`** — they come from `firmware/include/bus_dbg.h:11-13` and have never been reconciled against the instantiated RTL. **Record what you read and which offsets you read it from. Do not assert, and do not W1C anything here in Phase B** — the record is the evidence and it is one-shot.

### 3.9 Which Phase-B gates could fire wrongly on good ASIC silicon

Stated explicitly, because at a bench with one part a wrong abort is as expensive as a wrong pass.

| Gate | Could fire wrongly because | Guard |
|---|---|---|
| **Gate 2** | It is valid exactly once — on a genuinely cold die whose last event was the banner. Any re-run, any stray character, any late banner invalidates it. It **already fired on a healthy FPGA die** for exactly this reason. | Force the bypass with `X` and confirm it landed; never declare a dead RX path from a silent ESC alone |
| **Gate 5** | `0x18000000` reads `0x00000000` on the ASIC and `0x05f5e100` on the FPGA. Carrying the FPGA class list unchanged fails a good die on that row. `0x10000000`/`0x90000000` can legitimately move between two reads because a core is writing them. | §3.5's reclassification; abort on a pattern, not a row |
| **Gate 6** | Revision 1's "strictly increasing" form compared a frozen shadow with itself and **failed on a healthy cold FPGA die**. A saturated `0xFFFFFFFF` is positive evidence the clock ran, not a fault. | Use the Revision 2 form quoted in §3.6, with SNAP before every sample |
| **`HIO-106`** | Its FPGA expectation is inverted on the ASIC. `0x00000004` is healthy. **`[B]` It no longer aborts on a zero** — it runs the eight-read ladder and classifies, and three of the four classifications are diagnoses rather than reds. | §0.2, §0.3, §3.2 |
| **`HIO-107`** | Structurally broken on the ASIC (§3.7.4) | Replace or mark NOT EXECUTABLE |
| **Every `B`-class identity row** | Four of them produced false reds on the first FPGA hardware run: `RESET_INFO` polarity, `LINK_CAPABILITIES`, `evt_route` PID0, the perf-probe ID. The RDL, the yaml and the C header are all *specifications*; the RTL is what was built. | Record and classify. A `B`-class row that goes red is a documentation finding until proven otherwise on the RTL |
| **Every TideLink row** | The ASIC configuration genuinely differs (ECC, CRC, FCSM) | Record-and-classify only; no ASIC baseline exists yet |

---

## 4. Phase C — write behaviour, and the PHC initialisation

**`[B]` Nothing in this phase destroys anything at all now.** Revision A carried one deliberate exception — Gate 8's positive control overwrote a shared-SRAM word — and moving that control to the QSPI `ADDR` scratch (§4.2), where it is written and then restored, removed it. **Consequence worth taking: the §3.5.1 uninitialised-SRAM reading now survives the whole of Phase C** (§4.5).

### 4.1 C1 — Abort Gate 7, the poll engine

`HIO-401`, the built-in discrimination pair. It needs no fault injection and no DUT state:

```
A x08000000 ; Mx00000000 ; Vx00000000 ; Px00000010   ->  P 0x00000001    must MATCH on iteration 1
A x08000000 ; Mx00000000 ; Vx00000001 ; Px00000010   ->  P!0x00000010    must NEVER match, full budget, ! flag
```

> **ABORT GATE 7 — if either polarity fails, every `P`-based test below is vacuous.** Do not skip this because it "always passes"; it is the only thing that distinguishes a poll engine that is really looping and really comparing from one that is returning a plausible number.
>
> **What it does NOT mean:** a failure here does not implicate the bus. `P` never shows you the polled value — `ADP_ECHOCMD` overwrites `adp_bus_data` with `adp_param` — so a `P` result says something about the *engine*, and only about the engine.

### 4.2 C2 — Abort Gate 8, and why it is a *different* gate on the ASIC

`HIO-313` is the gate that authorises anything irreversible. Its Revision-1 form asserted only "the value did not change", **which a completely dead ADP write path satisfies perfectly** — the gate authorising the irreversible action could not detect the one failure that matters.

**On the ASIC this is worse, not better.** `chip_core_remap_ctrl` is write-1-set, and on a healthy die bit 2 (and possibly bit 0) are *already set* before you arrive. Writing `0x00000000` to it changes nothing **whether or not the write path works, whether or not the bus decodes, and whether or not the register exists.** The no-change arm of `HIO-313` is not weak evidence on the ASIC; it is **zero** evidence.

**Therefore, on the ASIC the positive control is not an addition to the gate. It IS the gate.**

**`[B]` The control word is the QSPI `ADDR` scratch at `0x2100000C`, and it is not a RAM word.** Revision A of this document used shared SRAM at `0x2D000FF0`; the FPGA plan used `0x10001000` inside eth IMEM. Both were RAM and both were wrong, for the same reason: **the eth-IMEM choice was justified on the premise that IMEM is empty, which is false the moment anyone loads an image — and false by construction on this die, because CPU0's ROM `copy_image`s into it on every boot attempt.** Shared SRAM is better but still contended: it carries the firmware ABI block (`0x2D000000`–`0x2D00004C`), the boot-confirm token, the parking image's signature word, and **`HIO-208` carpets all 8 KB of it in Tier 2.**

`0x2100000C` is none of those things, and the RTL is unambiguous — **R**:

- It is `reg [31:0] reg3` (`apb_qspi_regs.v:112`), **written unmasked** (`:188`, `reg3 <= PWDATA`) and **read back whole and combinationally** (`:220`, `PRDATA = reg3`). Any 32-bit pattern round-trips exactly. **The `reg3[21:0]` narrowing at `:136` is on the derived OUTPUT PORT to the flash controller and is not observable over APB** — check that line before you doubt the top ten bits.
- **It cannot start a flash transaction.** The command byte and `QSPI_ENABLE` live in `reg2` at `0x21000008` (`:128-129`), a different register you must not write.
- Neither boot ROM touches it. Both write only `AHB_SETUP` (`0x21000030`) and `CTRL` (`0x21000000`).
- **With `XIP_ACTIVE` set, the scratch is electrically unreachable from the flash.** `qspi_controller_mux.v:55-63` muxes *every* APB control input — `CMD`, `ENABLE`, `READ`, `WRITE`, `ADDR_EN`, `DUMMY_CYCLES`, `N_RW_BYTES`, `ADDR`, `WDATA` — away from the flash controller whenever `XIP_ACTIVE == 1'b1`. While XiP is armed the APB path is not merely idle, it is disconnected.

```
# 1. prove the control word is STABLE before you use it as a control
A x2100000c ; R          # read once   -- record as <orig>. 0x00000000 on a fresh die
A x2100000c ; R          # read again  -- must be IDENTICAL. If it moved, something
                         #                else owns this register; say so and stop.
# 2. the contemporaneous positive control -- reversible, on the same write path
A x2100000c ; Wx5a5a5a5a
A x2100000c ; R          -> must read 0x5a5a5a5a       # all 32 bits, not 22
A x2100000c ; Wxa5a5a5a5
A x2100000c ; R          -> must read 0xa5a5a5a5       # two patterns, not one
A x2100000c ; W<orig>
A x2100000c ; R          -> must read <orig>           # restored
# 3. only now, the no-op on the real register
A x29000000 ; R          # record v
A x29000000 ; Wx00000000 # OR with zero -- must not report '!'
A x29000000 ; R          # must still read v
```

**Two complementary patterns, not the suite's single `0x0BADC0DE` tag:** a cell stuck at one polarity passes a single-pattern control. Restore `<orig>` even though it is almost certainly zero — restoring is what makes this reversible, and reversibility is why it can sit in front of an irreversible write.

> **Do not write `0x21000000` or `0x21000008` here.** `0x21000000` is `CTRL`, boot-ladder rung 3 — writing it can pull `XIP_ACTIVE` down under a core that is mid-`copy_image` (§4.3). `0x21000008` is `reg2`, which carries `QSPI_ENABLE`. The scratch at `0x2100000C` is safe precisely because it is neither.

> **`reg3` resets on `PRESETn`** (`:175`), so any `CPU1_SWRST` clears it and the control must be re-run afterwards. That is not a defect — Gate 8 requires a *contemporaneous* control anyway, and §5.3 pulses that reset.

> **`[B]` This closed a gap, not just moved a word.** The ASIC target profile previously declared **no** control word at all, so on silicon **Abort Gate 8 would have deferred its positive control** and fallen back to the bare no-change assertion — which the opening of this section has just shown is *zero* evidence on this die. The gate that authorises the irreversible release would have been the one gate in the procedure that could not fail. It now has a control on both vehicles (`hostio_suite/targets.py`, `write_path_control_addr`).

> **ABORT GATE 8 — if the positive control did not run, or either pattern did not stick, or the no-op reports `!` or changes the value, do not perform any irreversible write.** That means: no `0x29000000` bit 0 (the parking step, §5.3), no `HIO-502`, nothing.
>
> **A no-change assertion is not a test.** *Contemporaneous* is load-bearing: a write test that passed ten minutes ago does not prove the write path is alive now.
>
> **What a failure does NOT mean:** it does not mean the boot gate is faulty. It means you have no evidence either way, which is a different and more recoverable situation.

### 4.3 C3 — the register-behaviour block

Run `HIO-301`, `HIO-302`, `HIO-303`, `HIO-304`, `HIO-305`, `HIO-306`, `HIO-307`, `HIO-309`, `HIO-311`, `HIO-312`, `HIO-314`, with `HIO-314` (RO-immutability) **last** — it retro-validates every identity constant Phase B recorded.

Three ASIC notes:

- **`HIO-304` (spinlock) — respect HZ-7.** A **read** of an acquire page *acquires the lock*. Pages are `HADDR[9:8]`: 0 = CPU0, 1 = CPU1, 2 = DBG, 3 = DIAG. **On the ASIC, unlike the FPGA sessions, CPU0 and CPU1 are both live** and page 0/1 acquisitions can interfere with running ROM code. Use the **DBG page (`0x2C100200`)** for the debugger's own acquisitions, and note that the DIAG page (`0x2C100300` OWNER, `0x2C100304` FORCE_RELEASE) is *not* an acquire page and is safe to read.
- **`HIO-312` (QSPI registers) — do not disturb XiP while a core may still be using it.** `0x21000000` and `0x21000030` are rungs 2 and 3 of the boot ladder. Read them in Phase B; if you must write them in Phase C, record their prior values first, because writing `CTRL` can pull `XIP_ACTIVE` down under a core that is mid-`copy_image`.
- **`0x24000000`–`0x24FFFFFF` stays blocklisted (HZ-6).** With no flash the AHB wrapper holds `HREADYOUT` low for `65536 / f_CLK` before erroring; **any host-side transaction timeout shorter than that will fire first and look like a dead port.** At 100 MHz that is 0.655 ms, comfortably inside the ~130 ms link, but state the number rather than assuming it.

### 4.4 C4 — PHC initialisation. THIS IS A REQUIRED STEP, NOT A TEST

**An uninitialised PHC on this die is confidently wrong and reports no error.** The reset default `NS_INCR = 4` is commented *"4 ns for 250 MHz"* — a frequency this design has never run at on any target. At 100 MHz that is **0.4× real time**, silently.

This is **not a tapeout blocker and must not be used to argue for a GDS spin.** `NS_INCR` is RW; only the reset default is wrong. Measured on the FPGA die, both directions, with the PHC enabled: `NS_INCR = 4` → 0.1000× real time; write 40 (`0x28` at `0x22000008`, reads back `0x28`) → 1.0004× real time; restore 4 → clean. **M-fpga.** The fix belongs in PHC init firmware; until that firmware exists, it belongs in this procedure.

```
A x22000000 ; Wx00000001      # enable the PHC -- it is FROZEN out of reset
A x22000008 ; R               # record the reset default. Expect 0x00000004.
A x22000008 ; Wx0000000A      # NS_INCR = 10, for exactly 100 MHz
A x22000008 ; R               # must read back 0x0000000A
```

**`NS_INCR = round(1e9 / f_HCLK)`, using the `f_HCLK` you measured in §3.6 — not 100 MHz because the SDC says so.**

| `f_CLK` you applied | `NS_INCR` | `NS_INCR_FRAC` @ `0x2200000C` | Residual |
|---|---|---|---|
| exactly 100 MHz | **10** | 0 | exact |
| 50 MHz | 20 | 0 | exact |
| 25.000 MHz | 40 | 0 | exact |
| anything not dividing 1e9 | `floor(1e9/f)` | `round((1e9/f - floor) × 2^32)` | state it in the record |

Then run `HIO-404` — two PHC captures bracketed by a **host-timed** interval — and record `phc_ns_per_wall_second`. It should be within a fraction of a percent of 1e9. `HIO-404` is the guard: it reds on *"does not keep real time"* rather than on an assumed frequency, so it catches an uninitialised die.

**Caveat, stated because it has bitten this plan repeatedly:** the RW behaviour of `NS_INCR` is proven on **FPGA only**. The ASIC instantiates the same IP with the same parameter, so it should carry, but that is untested on silicon. **Read the value back after writing it. Do not assume the write landed.**

> **`[B]` State the residual risk in the record, not just the remedy.** An uninitialised PHC on this die runs at **0.4× real time and reports no error** — no flag, no status bit, no ERROR on any read. **A PTP clock that is confidently wrong is worse than one that is obviously dead**, because everything downstream of it will agree with itself. `HIO-404` is the only thing that catches it, and only because it reds on *"does not keep real time"* rather than on an assumed frequency. If you skip `HIO-404`, record that you skipped it.

**And record that `phc_pps_out` is OPEN on this die** (`nanosoc_eth_chiplet_pads.v` header). There is no physical 1PPS pin, so PTP alignment can only ever be observed by reading PHC registers — which, on a standalone board, means HOSTIO4 or SWD, and SWD has never returned a DPIDR.

### 4.5 C5 — capture before Phase D destroys it

`HIO-414` — the firmware boot-confirm token at `0x2D001FF0`. **B**-class (the token `0xB007C0FE` comes from `firmware/include/nanosoc_boot_confirm.h` and is written by firmware, so it is doubly build-dependent). Read it now; Phase D overwrites the shared SRAM.

Also capture, now, anything from §3.5.1 you have not yet written down. **`[B]` The shared SRAM's power-up state is no longer destroyed by §4.2 — the control word moved off this RAM — but `HIO-208` carpets all 8 KB in Phase D, so Phase C is still the last chance.**

---

## 5. Phase D — memory integrity, and the parking step that makes it mean anything

### 5.0 `[B]` Phase D DESTROYS any firmware you have loaded, and nothing below Tier 5 can restart the core

**This is a sequencing constraint on the whole session. Read it before you plan the running order, not when you reach Phase D.**

Three facts. None of them has a workaround you can reach from the bench once you are past it:

1. **`HIO-203` and `HIO-204` each fill ALL 32 KB of eth IMEM** — `0x10000000`–`0x10007FFF`, with `0x5A5A5A5A` and then its complement (`hostio_suite/tier2_3.py`, `hio_203`/`hio_204`, both `destroys="ALL 32 KB of eth IMEM"`). That is CPU0's entire instruction memory. **R.**
2. **`HIO-208` carpets ALL 8 KB of shared SRAM** — `0x2D000000`–`0x2D001FFF`. That is every firmware witness word there is: the heartbeat, the sentinel, the image ID, the MDIO result block, the MAC register captures, the boot-confirm token `HIO-414` reads. **R.**
3. **Nothing in Tiers 0–4 pulses `CPU0_SWRST`.** The only write to `0x2A000020` bit 0 anywhere in the suite is inside `HIO-503`, which is **Tier 5** (`tier4_5.py`, `@test("HIO-503", tier=5, ...)`). **So the core cannot be restarted by anything you run in Phase D.** **R.**

**MEASURED on the FPGA:** a 1128-byte image (`fw_mdio_probe.bin`) loaded over the ADP `U` command ran for **exactly one Tier-1 pass** before Tier 2 erased it. **M-fpga** — and it transfers, because all three facts above are properties of the suite and the memory map, not of the vehicle.

> **THE RULE: in any one power cycle, every firmware-dependent test runs BEFORE Tier 2 — or the image is reloaded after it.** Tier 5, and anything at all that reads a firmware witness word out of `0x2D0000xx`, is firmware-dependent. **A Tier-5 run after a Tier-2 run is measuring a wiped die**, and it will red on a healthy one.

**The ASIC makes this sharper in two ways, in opposite directions.**

- **Worse:** on this die eth IMEM is not merely *possibly* loaded, it is **live instruction memory by construction** — `cc_rom` releases CPU0 and CPU0's ROM `copy_image`s into `0x10000000` on every boot attempt (§3.3, §6.3). On a die with provisioned flash, `HIO-203`/`HIO-204` are writing over a **running** core's code, not over an idle scratch RAM. That is a Phase-D quiescence question (§5.2), not only an ordering one.
- **Better:** the ASIC's recovery is a *reset*, not a reload. **You cannot reload CPU0 over the debug port on this build (§6.3)** — but with a provisioned flash, `HIO-503`'s `CPU0_SWRST` makes CPU0's ROM re-copy the image out of XiP, which restores what Tier 2 destroyed. On the FPGA the only recovery is `fw_load.py` over the `U` command. **Which recovery you have depends entirely on §1.6 row 14 — is a flash fitted, and is it provisioned.** Write that answer down before you order the session.

**On a die with no flash there is no recovery at all in that power cycle.** CPU0's ROM will find nothing, halt, and eth IMEM will hold whatever Tier 2 left in it until you cycle power.

### 5.1 The honest position

On the ASIC, **both cores are running by the time you can issue a command.** A memory-integrity result taken against a live core is not a fail and not a pass; it is **inconclusive**, and reporting it as either is the specific failure this procedure exists to prevent.

The picture is more nuanced than "there is never a quiescent bus", and the nuance is useful:

- In the common bring-up case — unprovisioned or absent flash — **both cores self-park in ROM within tens of milliseconds.** CPU1 ends in `wfi ; b .` (all-candidates-failed path) or `HardFault_Handler: b .` (no flash). CPU0 ends in `halt()`'s `for(;;) wfi();` or its own `HardFault`. Neither touches RAM after that point.
- So the bus usually *is* quiet by the time you get there — **but it is quiet by accident, nothing tells you when it settled, and it is not quiet at all if rung 6 read `0x00000005`** (a CPU1 application is running) or if flash is provisioned (CPU0 runs an application).

**The rule: establish quiescence positively, or mark the whole phase inconclusive. Do not infer it.**

### 5.2 D0 — establishing quiescence, with two independent instruments

**Instrument 1 — the perf probe, for top-matrix traffic.** SNAP/CLR, wait a host-timed interval, SNAP, read the per-initiator counters at `0x2C200000`. Zero transfers on the `eth_ss_m` and `cpu_ss_1_m` initiators over 10 s means neither core is crossing the top matrix.

*Its limit, stated plainly:* it sees only traffic that **leaves** a subsystem. A core spinning in its own ROM, or thrashing its own IMEM/DMEM, does not cross the top matrix and does not appear. So this instrument is **necessary and not sufficient** for the core-local RAMs — which are most of the RAMs Phase D tests. It **is** sufficient for the shared SRAM at `0x2D000000` and for the DMA-250. The initiator index map is class `B`; record which index you read.

**Instrument 2 — `HIO-211`, promoted from a soak to a gate.** The FPGA plan runs `HIO-211` last, as a retention test. **On the ASIC run it FIRST, as the quiescence gate**, in each RAM you are about to test:

```
A x<ram_base+0x100> ; Wx5a5a5a5a
   ... wait 30 s ...
A x<ram_base+0x100> ; R      -> must still read 0x5a5a5a5a
```

If it moved, something else is writing that RAM and every pattern test in that RAM is inconclusive. This is the only instrument that sees core-local traffic, and it is the one that actually answers the question Phase D needs answered.

### 5.3 D0b — parking CPU1

**Preconditions: Abort Gate 8 has passed with its positive control (§4.2), and you have decided to spend an irreversible bit.**

A parking image is being built under `scripts/rig/eth_chiplet/hostio_fw/`. It is a minimal vector table plus a spin loop, loaded into CPU1 IMEM at the **remap-independent alias `0x90000000`** and entered by pointing CPU1's reset vector at IMEM.

**Requirements on that image, stated here because a parked core and a crashed core look identical over this port:**

| # | Requirement | Why |
|---|---|---|
| P1 | `[0x00]` = a valid initial SP; `[0x04]` = entry address **with the Thumb bit set**. An ARMv6-M reset with bit 0 clear in the PC faults immediately. | A HardFaulted CPU1 is *also* quiet, so quiescence alone cannot tell you the image ran |
| P2 | **Use `0x10000009`-style absolute IMEM addresses, not `0x00000009`.** `0x10000000` is CPU1's remap-independent IMEM alias; `0x00000000` depends on the remap bit you are about to set | Removes one dependency from the riskiest step |
| P3 | **The image MUST write a distinctive signature word before it spins.** The ABI already defines one: `FW_IMAGE_ID_ADDR = 0x2D000008`, value `FW_IMAGE_ID_MAGIC` OR `FW_IMAGE_ID_PARK` = `0x48465701` (`scripts/rig/eth_chiplet/hostio_fw/fw_abi.h`). Shared SRAM is the right home for it — ADP reaches it regardless of remap state | **This is the positive control for the whole parking step.** Without it, "CPU1 is quiet" is exactly the shape of assertion §4.2 forbids. A HardFaulted CPU1 is *also* quiet |
| P4 | Keep the SP below `0x18001C00`. **CPU1's DMEM is 8 KB** (`CC_DMEM_RAM_ADDR_W = 13`), so the ROM's `__StackTop = 0x18003c00` **aliases** down to `0x18001C00`. A parking image that assumes 16 KB will put its stack on top of itself | **R**; and see §5.5 |
| P5 | Total length ≤ a few tens of bytes, and **record the exact byte count** — `U`'s count must equal the payload length exactly; it has no timeout and no abort | A short count leaves the monitor mid-upload |

**The sequence:**

```
# 0. arm the two "did it really re-boot?" witnesses, so their later state is FRESH
A x98000200 ; Wx00000000                  # clear CPU1's ROM liveness marker
A x2d000008 ; Wx00000000                  # clear the parking image's ID word

# 1. zero CPU1 IMEM (16 KB = 4096 words). V's digit count sets the fill size.
A x90000000 ; Vx00000000 ; Fx00001000

# 2. upload the parking image, N bytes, then N raw binary bytes on the wire
A x90000000 ; Ux<N as 8 hex digits>      # followed by the raw payload

# 3. VERIFY, including the LAST byte explicitly.
#    F and U have an off-by-one hole: in both ADP_FWRITE (:658) and ADP_UWRITE (:637)
#    the HRESP capture sits in the ELSE branch, so a fill or upload whose only
#    erroring beat is the LAST reports clean.
A x90000000 ; Rx<N/4 as 8 hex digits>     # dump the whole payload back
A x<0x90000000 + N - 4> ; R               # the FINAL word, read on its own

# 4. IRREVERSIBLE (HZ-4): point CPU1's reset vector at IMEM
A x29000000 ; Wx00000001                  # set REMAP bit 0
A x29000000 ; R                           # confirm bit 0 is now set

# 5. HZ-5: pulse CPU1_SWRST. THIS RESETS THE WHOLE FABRIC, INCLUDING HOSTIO.
A x2a000020 ; Wx00000002
#    -> the link drops, the ADP re-emits its banner. This is a free re-run of HIO-001.
#    -> re-enter the monitor. Every ADP register (address, M, V) has reset.

# 6. VERIFY THE PARK, positively
A x2d000008 ; R                           # the P3 signature -- MUST read 0x48465701
A x98000200 ; R                           # 0x0F1C0DE1 must now be ABSENT: CPU1 booted from
                                          #   IMEM, not its ROM, so it never rewrote the
                                          #   marker step 0 cleared. Its ABSENCE is now a
                                          #   fresh observation rather than a stale one.
   ... then Instrument 2 (§5.2) on CPU1 DMEM ...
```

**Four consequences of step 5 you must expect, none of them faults:**

1. **The banner reappears.** Capture it. It is a second, free `HIO-001`.
2. **`chip_core_remap_ctrl` survives** — it resets on `PORESETn` only, not `HRESETn`. Your remap bit and the boot gate persist.
3. **CPU0 restarts too**, because `cpu0_resetn = cpu0_bootgate & ~cpu0_reset_pulse` and the gate is still set. CPU0 re-runs its stage-0. Let it settle before measuring.
4. **CPU0 parks *earlier and more cleanly* than before.** The QSPI registers reset on `PRESETn` (`apb_qspi_regs.v:170`), so `CTRL.XIP_ACTIVE` is now 0; with CPU1 parked, nobody re-enables XiP; so CPU0's stage-0 fails its `XIP_ACTIVE` readback and takes `halt()` **without ever touching the XiP aperture.** This is the quietest reachable state of this die and it is a *better* Phase-D condition than the cold boot was.

**Cost, recorded deliberately:** one irreversible bit (`0x29000000[0]`, clearable only by a power cycle) and one fabric reset. **Record which you did.** After a power cycle the die returns to the §0.2 boot ladder and the parking must be redone.

### 5.4 D0c — you cannot park CPU0 the same way

**There is no equivalent for CPU0, and this is a structural limit of the ASIC, not an oversight.**

CPU0 boots from the eth boot ROM at `0x00000000` on every reset. The register that would redirect it — the eth-subsystem `sys_remap_ctrl` at `0x50002000` — is **outside `debug_m`'s decode**: `0x50000000`–`0x5FFFFFFF` is an ERROR from ADP and is visible only to the SWD DAP (FPGA plan §1.4, and the gap analysis's initiator-reach table). **ADP cannot change the eth REMAP bit.** So `CPU0_SWRST` always restarts CPU0 *in its ROM*, which always attempts a `copy_image` into eth IMEM.

What you get instead is the observation in §5.3 consequence 4: with CPU1 parked and XiP down, CPU0's own ROM parks it for you, earlier than it would otherwise. **That is the mechanism to rely on, and it is worth verifying with Instrument 2 on eth IMEM before trusting any eth-IMEM pattern test.**

### 5.5 D1–D6 — the memory tests, with the ASIC's real geometry

| RAM | ADP base | Physical size | `F` count for a full fill | Note |
|---|---|---|---|---|
| eth bootrom | `0x08000000` | 2 KB | — | RO. `HIO-209` write-protection test — **and re-read its `[R2]` note: Revision 1's version wrote word 1 and checked word 0, so it passed unconditionally.** |
| eth IMEM | `0x10000000` | 32 KB (`ETH_IMEM_RAM_ADDR_W = 15`) | `Fx00002000` | **CPU0's `copy_image` destination.** Gate on Instrument 2 |
| eth DMEM | `0x18000000` | 16 KB (`ETH_DMEM_RAM_ADDR_W = 14`) | `Fx00001000` | Holds CPU0's `.data`/`.bss`/`g_tbl` and its stack at `__StackTop = 0x18003c00`, which **is** valid here |
| CPU1 bootrom | `0x80000000` | 2 KB | — | RO |
| CPU1 IMEM | `0x90000000` | 16 KB (`CC_IMEM_RAM_ADDR_W = 14`) | `Fx00001000` | Holds the parking image after §5.3 |
| CPU1 DMEM | `0x98000000` | **8 KB** (`CC_DMEM_RAM_ADDR_W = 13`) | `Fx00000800` | **See the aliasing note below** |
| shared SRAM | `0x2D000000` | 8 KB | `Fx00000800` | Written by neither ROM |

> **CPU1's stack does not live where the linker thinks it does.** Both stage-0 ROMs share `nanosoc_multicore_soc_stage0_bootrom_memory.ld` and both link `__StackTop = 0x18003c00`. That is inside eth's 16 KB DMEM, but **CPU1's DMEM is 8 KB**, and `nanosoc_region_sram` drives the macro with `HADDR[RAM_ADDR_W-1:0]`, so `0x18003c00` **aliases to `0x18001C00`** — ADP `0x98001C00`. **A**.
>
> Consequences: (a) a Phase-D pattern test of the top of CPU1 DMEM is writing on a live stack unless CPU1 is parked; (b) `HIO-118`'s alias-wrap probe should find the wrap at 8 KB, and finding it at 16 KB would be the real finding; (c) the parking image's SP must respect P4 in §5.3.

**`[B]` Before you start: §5.0.** D2 and D3 below destroy every firmware image and every firmware witness word on the die, and nothing you can run in this phase restarts a core. If anything in this session depends on firmware, it runs before D2 or it does not run in this power cycle.

Order: **D1** `HIO-118` size/alias probes first — the real depth governs every pattern below. **D2** `HIO-201`, `HIO-202`, `HIO-210` on eth IMEM, then `HIO-203`/`HIO-204`. **D3** eth DMEM (`HIO-205`), shared SRAM (`HIO-208`). **D4** CPU1 IMEM/DMEM (`HIO-206`/`HIO-207`) — **only after §5.3, and re-uploading the parking image afterwards if you overwrite IMEM.** **D5** `HIO-209`, `HIO-211`. **D6** re-run `HIO-007` after each of D2–D5 — cheap, and it catches a destructive test leaving the port in a state where the error flag no longer discriminates.

**`HIO-202` (address uniqueness) cannot be replaced by an `F`-based test.** `F` writes one value everywhere; only a per-address unique value can detect an address-bus fault.

---

## 6. Phase E and Phase F

### 6.1 Phase E — cross-die

Unchanged in structure from the FPGA plan, with three ASIC caveats stacked on top. Only with a peer die present and both dies through Phases A–C.

| Step | Test | Gate |
|---|---|---|
| E1 | `HIO-408` — wait for `calibration_done`, both dies | **ABORT: no link-up ⇒ do not touch `0x2F`** |
| E2 | `HIO-407` + `HIO-409` — `fcsm` ∈ 4–7, `cal` = 1, both markers present, `0x1F8[10] == 0` | **ABORT: any of those wrong ⇒ do not touch `0x2F`** |
| E3 | `HIO-410` on **both** dies — exactly one may report `is_root` | Dual root is a hard red; record and stop |
| E4 | `HIO-413` — one single peer read, then `HIO-409` as the **very next command** | **HZ-2. Budget a power cycle. Never unattended.** |

**ASIC caveats:**

- **CRC is ON at reset** (the FPGA had it off), so `HIO-408`'s time-to-`calibration_done` and `HIO-407`'s FCSM trajectory will not match FPGA numbers. **Record the ASIC values as the new baseline. Do not fail a die for differing from an FPGA figure.**
- **FCSM recovery is stripped**, so a link that enters a bad state **will not self-heal**. `fcsm = 1` / `fcsm = 2` signatures that were transient on the FPGA are **terminal** here. Budget a power cycle rather than a retry.
- **`fcsm_state = 8` is an open encoding question**, recorded on the FPGA with no peer attached and never resolved. Until it is closed, `HIO-407`'s state signatures are not a diagnostic — they are a reading.
- **HZ-1 quarantine stands**: `0x2E0321A0`–`0x2E0321B8`, the *whole band*. *"Uninterruptible AXI hang. Power cycle to recover."* Simulation can never reproduce it, so the blocklist is load-bearing and nothing downstream will catch a mistake.
- **HZ-8 read-clearing registers stand**: `0x2E032020`, `024`, `038`, `15C`, `160`, `168`. **A read *is* a write.** Never poll them and never include them in a sweep.

### 6.2 Phase F is not a point of no return any more

**Phase F's defining property in the FPGA plan — that `HIO-502` crosses an irreversible line — does not exist on the ASIC.** The line is crossed at power-on by `cc_rom`, before Phase A. Concretely:

| FPGA-plan claim | ASIC status |
|---|---|
| `HIO-502` (set `0x29000000` bit 2) is the point of no return | **A no-op on healthy silicon.** Bit 2 is already set. It survives only as a conditional recovery action — see §7.3 |
| "From here CPU0 contends for the bus and mutates memory; nothing in Phases B–D is repeatable in the same conditions" | **True from power-on.** This is why §5 exists |
| Phase F is where irreversibility begins | **The only irreversible action left in this procedure is the parking step's `0x29000000` bit 0 (§5.3), and it is in Phase D** |

**What is still irreversible on this die, in full:** every bit of `chip_core_remap_ctrl`. It is write-1-set and resets on `PORESETn` only. Bit 0 (CPU1 REMAP), bit 1 (`CHIP_CORE_BOOTGATE` — inert, because `cpu1_bootgate` is tied `1'b1`, but still permanently settable), bit 2 (CPU0 bootgate, already set). **Nothing else in this procedure cannot be undone by a power cycle.**

### 6.3 What "firmware" can and cannot mean on this die — a first-order asymmetry

This is not in the FPGA plan and it changes what Phase F is for.

**HOSTIO CAN run your code on CPU1.** Preload IMEM at `0x90000000`, set `0x29000000` bit 0 so CPU1's reset vector comes from IMEM, pulse `CPU1_SWRST`. That is exactly the parking mechanism of §5.3, and it works for any image, not just a spin loop. `chip_core_remap_ctrl[0]` drives `u_cpu_ss_1.sys_remap_ctrl`, and the CPU-SS decode's `remapping_dec` arm maps `0x00000000`–`0x07FFFFFF` to IMEM when it is set. **R.**

**HOSTIO CANNOT run your code on CPU0 on this build.** Three facts compose:

1. CPU0 boots from the eth boot ROM at `0x00000000` on every reset, because the eth REMAP resets to 0.
2. The eth REMAP register is at `0x50002000`, and `0x50000000`–`0x5FFFFFFF` is **not in `debug_m`'s decode** — it is an ERROR from ADP and visible only to the SWD DAP.
3. The eth ROM *itself* overwrites eth IMEM with a `copy_image` from XiP on every boot attempt, and only sets REMAP + VTOR and jumps if a CRC-valid image was found in flash.

**Therefore `HIO-501` (preload CPU0 IMEM) + `HIO-503` (relaunch via `CPU0_SWRST`) cannot make CPU0 execute your image.** The ROM will overwrite what you loaded and, failing CRC, halt.

#### `[B]` And the FPGA will have told you the opposite, convincingly

**The debug-port firmware preload genuinely works on the FPGA. It is not a myth and nobody was careless.** The two vehicles carry different eth ROMs and those ROMs do **opposite** things to IMEM:

| | FPGA eth ROM — `smoke_remap` | ASIC eth ROM — `stage0_bootrom` |
|---|---|---|
| What it does to IMEM | **Never writes it.** Reads the loaded image's SP and PC from the **always-mapped IMEM aperture**, then a single naked `str REMAP,#1` immediately followed by `bx`, both 16-bit Thumb in one prefetch line | **Overwrites it.** `copy_image()` word-copies the flash image to `0x10000000` on every boot attempt (`main.c:94-97`, `:145`) |
| If XiP is not up | proceeds — it arms `AHB_SETUP` and `XIP_ACTIVE` and does not gate on them | **`halt()`s.** `if ((ctrl_rb & (1u << 8)) == 0u) halt();` (`main.c:221`) |
| Then | `bx` into whatever you loaded | CRC-checks the copy (`:149`) and `halt()`s if both boot-table candidates fail (`:238`) |
| **Effect on an ADP preload** | **survives and runs** | **erased, then CRC-failed, then halted** |

**A** (firmware source, both images) + **G** (the ASIC image's identity is verified at mask geometry — §8.4 rung 0) + **M-fpga** (the FPGA behaviour was observed, not inferred).

**So: on the ASIC the delivery route for CPU0 firmware is the QSPI flash boot table, not the debug port.** Not a limitation of the transport — `U` works, §6.3.1 settles that for CPU1 IMEM — but of what the ROM does next. There is no sequence of ADP commands that changes it, because the register that would (the eth REMAP at `0x50002000`) is off `debug_m`'s decode.

**Consequences that must be written into the coverage record:**

- The FPGA plan's §3.1 conclusion — *"on a die where SWD returns nothing, HOSTIO alone is sufficient to take the chip from cold to running firmware"* — is **true for CPU1's memory in principle, and false for CPU0 on silicon.** `[B]` "In principle" is doing work: §6.3.1's four commands have not been run on any die, so even the CPU1 half is unconfirmed.
- `HIO-506` ("Ethernet MAC and MDIO, via CPU0 firmware") is the **only** route to the MAC, and it depends on CPU0 firmware. **So on first silicon, with unprovisioned flash, the Ethernet MAC is unreachable, full stop.** `[B]` §6.4 gives what the FPGA already established about the far end, and why none of it transfers.
- The only route to CPU0 code is **provisioning the QSPI flash**. ADP *can* reach the QSPI controller's APB command aperture at `0x21000000`, so flash programming from HOSTIO is conceivable — see §10.1 row 6, where it is listed as **not for first silicon**.

**`HIO-503` (`A x2a000020 ; Wx00000001`, `CPU0_SWRST`) remains valuable** as a *cheap, repeatable, non-destructive re-run of CPU0's boot* that does not touch HOSTIO. It is the right instrument for re-taking the §3.3 trail, not for launching firmware.

**`HIO-509` (`A x2a000020 ; Wx00000002`, `CPU1_SWRST`)** returns everything except `chip_core_remap_ctrl` to cold and re-emits the banner. It is the whole-SoC reset and a free `HIO-001`. **HZ-5:** it resets HOSTIO itself; the link drops and must be re-entered.

#### 6.3.1 A disagreement about CPU1 IMEM, and the four commands that settle it

`scripts/rig/eth_chiplet/hostio_fw/fw_abi.h` carries the note *"`FW_CPU1_IMEM_DEBUG_ALIAS 0x90000000` … there is no route from the debug port into this memory today."* **This document says the opposite, so do not take either on trust — take the measurement.**

What the generated RTL says (`build_soc/rtl/nanosoc_cpu_ss_ahb_interconnect/`, **R**):

- The CPU-SS matrix has **two** initiators. `CPU_0` is CPU1's own core and reaches `BOOTROM_0, IMEM_0, DMEM_0, SYSTEM`. **`CPU_SS` is the external slave port** — the one `debug_m` enters through — and reaches `BOOTROM_0, IMEM_0, DMEM_0` (`nanosoc_cpu_ss_ahb_interconnect.v:39-40`).
- `nanosoc_cpu_ss_matrix_decode_CPU_SS.v:245-257` maps **`0x90000000`–`0x97FFFFFF` → MI1 = IMEM** and **`0x98000000`–`0x9FFFFFFF` → MI2 = DMEM**, in both remap arms.
- `nanosoc_cpu_ss_arbiter_IMEM_0.v` exists precisely to arbitrate the two initiators for that RAM.

There is no read-only qualifier anywhere on that path. **On the RTL, ADP writes to `0x90000000` reach CPU1 IMEM.**

The likelier explanation of the contrary note is the *transport*, not the die: the FPGA plan's §6.5 records `HIO-501`/`HIO-508` as blocked because *"the client had no raw-payload transmit call for `U`"* — **not** by the die. `harness.py` now has `raw_tx` (`:887`), so that blocker is gone.

**Settle it on the die, in Phase C, before you depend on it in Phase D:**

```
A x90003ff0 ; R            # record v   (top of CPU1 IMEM, away from any loaded image)
A x90003ff0 ; Wx5a5a5a5a
A x90003ff0 ; R            -> 0x5a5a5a5a ?
A x90003ff0 ; W<v>         # restore
```

**If that write does not stick, §5.3 and §6.3 are both void for this die** — there is then no way to run any code on either core from this port, and the whole of Phase F reduces to observation. Record the result either way; it is one of the most consequential four commands in this procedure.

### 6.4 `[B]` Ethernet on this die — a two-hop chain that has never been exercised

**The MAC at `0x40000000` is structurally unreachable from `debug_m`.** MEASURED `R!0x00000000` (FPGA plan §5.1); the ASIC has the same decode and the same result. No alias, no window, no translation. **Firmware is the only route.** **M-fpga** + **R**.

**What the FPGA already established, so that nobody re-derives it here.** Firmware read the MAC **exactly** — `MODER = 0x0000A000` and `PACKETLEN = 0x00400600`, both untouched reset values, published as witnesses rather than written — while reporting **all 32 PHY addresses unstable, zero MIIM timeouts, and `MIISTATUS.BUSY` clearing on every transaction, across 108 completed scan passes.** **M-fpga.**

**That combination is an isolation, not a failure.** In one run it rules out the firmware (it read the MAC correctly), the MAC (its registers are exact), the MIIM controller (BUSY asserts and clears every time), and the clock divider (zero timeouts, MDC in spec at the reset `CLKDIV = 0x64`). What is left is **the physical MDIO line on that board** — leading candidate an inadequate pull-up (`scripts/rig/eth_chiplet/README.md`, 2026-08-24). **It is a KR260 board finding and it is closed as far as the chiplet is concerned. Do not spend silicon time on it.**

**None of that transfers to the ASIC, because the transport does not exist yet.** A MAC register read on this die is a **two-hop chain — QSPI flash → CPU0 firmware → MAC — and it has never been exercised end-to-end on any vehicle.** The FPGA delivered its firmware over the debug port, which §6.3 shows the ASIC cannot do. Three consequences for the record:

- **`HIO-506` is NOT EXECUTABLE on first silicon with unprovisioned flash.** Record it as that, never as a fail.
- On a provisioned die, a failure of the chain **is not attributable to the MAC** until the first two hops are independently witnessed. The witnesses are the image ID at `0x2D000008` and the heartbeat at `0x2D000000` — and **Tier 2 destroys both (§5.0), so read them first.**
- **Nothing in this procedure tests Ethernet.** It belongs in the coverage record as *not covered by this port*, beside §10.2 item 1.

> **Provenance, stated because it is thinner than the rest of this document.** The FPGA MDIO figures above come from the firmware run in progress on 2026-08-26 and are read back from `hostio_fw/fw_abi.h`'s witness words — `FW_MDIO_MASK_UNSTABLE_ADDR 0x2D000028`, `FW_MDIO_TIMEOUTS_ADDR 0x2D000034`, `FW_MDIO_SCANS_ADDR 0x2D000040`. **They are not yet in a tracked artefact.** The MAC reset values and the `R!` reachability result are independently corroborated (`scripts/rig/eth_chiplet/README.md`; FPGA plan §5.1); the 108-pass scan census is not. Treat the isolation as **M-fpga** and the pass count as a figure to re-confirm from the run log before it is quoted anywhere load-bearing.

---

## 7. The SWD-is-silent differential diagnosis — ASIC edition

**SWD has never returned a DPIDR on any of these boards.** On the ASIC that symptom is far more serious than it was on the FPGA, because **the complete external-host inventory on the die is SWD (2 pins) and HOSTIO4 (7 pins)**. There is no `eth_ss_0` backdoor; it is an internal SoC port that exists on no pin off the KR260 carrier. If both are silent you have no host access to the part at all.

**Separating those causes is HOSTIO's principal strategic value on this chiplet**, and the table below is the reason it is worth spending a bring-up board on the seven wires.

### 7.1 The differential table

| What you observe | What it rules IN | What it rules OUT | Action |
|---|---|---|---|
| **HOSTIO banner appears** (§2) | Core supplies up; CPU1's PRMU released; the fabric clock and `HRESETn` live; the ADP out of reset — **all four from one word**, because the fabric clock and reset *are* CPU1's PRMU outputs | *"The die is dead." "The clock is not running." "Reset is stuck."* **None of these can be the reason SWD is silent.** | Stop debugging the SoC. Debug the SWD wiring: the DAP, the two pins, their pull-ups and level shifting, the debug power domain |
| **Banner appears and the §3.5 census matches** | The AHB matrix decodes correctly for a non-CPU initiator | A broken bus fabric as the cause of SWD silence | Same, with more confidence |
| **§3.6 shows `P0_CYC` advancing under SNAP discipline** | The fabric clock is genuinely toggling, not merely settled | A latched-up or gated fabric | Same |
| **Boot ladder rung 0 reads `0x08000678`** | The ROM in the CPU1 slot is the one that was signed off, verified at mask geometry | *"The wrong image was baked."* | Proceed. This is also the premise-check for the whole procedure |
| **Rung 6 reads `0x00000004`** | CPU1 ran to completion, found no valid boot image, and released CPU0. **The normal state of an unprovisioned die.** | *"CPU1 crashed." "The boot gate is broken."* | Nothing is wrong. Provision the flash when you want firmware |
| **Rung 6 reads `0x00000005`** | CPU1 found a CRC-valid image and **is running it** | *"Nothing is executing on this part."* | The die is further along than you think. Treat Phase D as inconclusive until §5.3 |
| **Rung 6 reads `0x00000000`, rungs 1–3 OK** | CPU1 HardFaulted, almost certainly on the XiP warm-up read with no flash responding. It is parked in `b .` in ROM | *"CPU1 never started." "The die is dead."* | **Check whether a QSPI flash is fitted before suspecting silicon.** §0.3 |
| **Rung 6 reads `0x00000000`, rung 1 fails** | CPU1 never reached `main()` | nothing else | Check rung 0 first — a wrong ROM image explains this with no silicon fault |
| **`0x29000000` bit 2 = 0 and you have exhausted §0.3** | **CPU0 has never been released from reset.** It never started; it did not crash. **This is invisible to SWD**, and it is a completely different fault from a dead chip | *"CPU0 has crashed."* | **Release CPU0 yourself** — this is what `HIO-502` is for now (§7.3) — and the chip may simply work |
| **CPU0 released and CPU0's trail (§3.3) shows it ran, but nothing else happens** | CPU0 was released and executed its ROM, then halted | *"CPU0 was never released."* | A **firmware/flash** problem, not a silicon or debug problem |
| **`SE` was found high** | The two pads you were trying to talk to were TDI and TDO | — | **This is an ASIC-only failure mode with no FPGA analogue.** Re-strap and re-power. §1.3 |
| **No banner at all** | **Nothing.** | **Nothing.** | §7.2 — and it is informative anyway |

### 7.2 The one case where HOSTIO is as blind as SWD — and why that is still a result

**No banner means HOSTIO cannot tell you why HOSTIO is silent.** If the port does not answer, the port cannot self-diagnose. That case needs a scope on seven pins.

**But two independent debug paths failing together is itself evidence, and it points somewhere specific.** SWD and HOSTIO4 share almost nothing: different pads, different sides of the ring, different protocols, different masters on the matrix, different clock sources (SWD has its own `SWDCK` pad and a 40 ns SDC clock; HOSTIO4 has no source-synchronous clock at all and runs off `SYS_HCLK`). The one thing they do share is **the die being powered, clocked and out of reset.**

So a double blind points at the **common cause**, not at either path:

1. **Power** — core `VDD`, `VDDIO`, and their sequencing.
2. **`CLK`** — which has **no on-die pull** (§1.3) and must be actively driven. A floating `CLK` gives no `SYS_FCLK`, hence no `SYS_HCLK`, hence no ADP, hence no banner, and no DAP either.
3. **`NRST`** — which also has **no on-die pull** and will float. A held-low or floating-and-drifting `NRST` produces exactly this.
4. **CPU1's PRMU** — the single point of failure for the whole fabric, since `SYS_HCLK = SYS_FCLK` passes through it.

**It does not point at the SWD wiring, and it does not point at the seven HOSTIO conductors** — those would have to fail simultaneously and independently.

**Scope, in this order:** the supplies; `CLK` at the pin; `NRST` at the pin; then `IOACK` and one `IOREQ` (§1.1d) to see whether the SoC ever asserted a request at all. **An `IOREQ` that asserts and never releases means the die is alive and the host never acknowledged — which moves the whole problem to the host and is very good news.**

### 7.3 `HIO-502` reclassified

`HIO-502` — `A x29000000 ; Wx00000004` — was the FPGA plan's single irreversible action, gated by Abort Gate 8 and placed at the end of everything.

**On the ASIC it is a conditional recovery action**, used in exactly one circumstance: **the §0.3 ladder shows CPU1 never reached a terminating path, and you have decided to release CPU0 anyway** so that it can run its own stage-0 and produce the §3.3 trail. It is still gated by Abort Gate 8 (§4.2) and it is still irreversible without a power cycle — but on a die where bit 2 already reads 1 it changes nothing at all, and running it "to be safe" tells you nothing.

**Note the auto-increment defect in its FPGA-plan form has never been exercised anywhere.** Write it as `A x29000000` immediately followed by `Wx00000004`, with no access between them, and read the register back afterwards.

---

## 8. The first-silicon record sheet

**This is the die's fingerprint. Capture every value verbatim, in hex, exactly as the port printed it — including the `!` flag and the digit count.** These are the values that let one die be diffed against another, and against `scripts/rig/eth_chiplet/hostio_suite/golden_fpga_reference.json`.

**Record `R 0x00000000` and `R!0x00000000` as different things. They are.** An OK-with-zeros and a bus ERROR both show `0x00000000`; only the flag distinguishes them, and `r.error` is the only correct way to test for one.

### 8.1 Die and bench header — fill in before power

| Field | Value |
|---|---|
| Die serial / wafer / position | |
| Bring-up board revision, and the HOSTIO pin landing used (§1.1) | |
| `VDDIO` measured | |
| `CLK` source and nominal frequency (§1.2) | |
| `SE` measured at the pin | must be **0** |
| `TEST` measured at the pin | must be **0** |
| `NRST` drive arrangement | |
| QSPI flash **fitted?** **provisioned?** (§1.6 row 14) | |
| Host driver commit, and **status-nibble polarity fix present?** | |
| Cold-boot capture filename | |
| Operator, date, session | |

### 8.2 Phase A — the port

| # | Command / observation | Expected | Class | Recorded |
|---|---|---|---|---|
| A1 | cold-boot banner word | `0x50c1ab04` | **R** | |
| A1 | banner arrival, seconds after power-on | < 1 s | — | |
| A1 | number of banner words in 10 s | exactly 1 | **R** | |
| A1 | prompt after the banner? | **no** | **R** | |
| A4 | `A x30000000 ; R` | `R!` flag **set** | **M-fpga**+**R** | |
| A4 | `A x08000000 ; R` | `R ` flag **clear**, `0x18003c00` | **G** | |

### 8.3 Phase B — the boot ladder (§0.2). Record ALL of these, in this order

| # | ADP read | Expected (ASIC) | Class | Recorded |
|---|---|---|---|---|
| B0.0 | `0x800000E4` | `0x08000678` — cc ROM is `stage0_bootrom_chip_core` | **G** | |
| B0.0' | `0x800004F4` | `0x220423a4` | **G** | |
| B0.0' | `0x800004F8` | `0x601a059b` | **G** | |
| B0.0' | `0x80000528` | `0x220423a4` | **G** | |
| B0.0' | `0x8000052C` | `0x601a059b` | **G** | |
| B0.1 | `0x98000200` | `0x0f1c0de1` — CPU1 `main()` entered | **G** | |
| B0.2 | `0x21000030` | `0x0000800b` — `AHB_SETUP` | **A** | |
| B0.3 | `0x21000000` | bit 8 set — `CTRL.XIP_ACTIVE` | **A** | |
| B0.4 | `0x23000010` | `0xd15c0001` — XiP-warm handshake | **G** | |
| B0.5 | `0x98000084` | `0xffffffff` on blank flash — CPU1 `g_tbl` | **A** | |
| B0.6 | **`0x29000000`** | **`0x00000004` or `0x00000005`** | **R** | |
| B0b | `0x080000E4` | `0x0800048c` — eth ROM is `stage0_bootrom` | **G** | |
| B0b | `0x18000084` | `0xffffffff` on blank flash — eth `g_tbl` | **A** | |
| B0b | `0x10000000` | may be anything; **may move between reads** | **A** | |

### 8.4 Phase B — the mask-verified ROM fingerprint

**These are class G: extracted from the ROM via-programming in the shipped stream and diffed 512/512 words clean against the firmware image.** They are the only constants in this procedure that cannot be wrong for a build reason. Assert them.

| eth ROM (ADP `0x08000000` + off) | Expected | | cc ROM (ADP `0x80000000` + off) | Expected |
|---|---|---|---|---|
| `+0x000` | `0x18003c00` | | `+0x000` | `0x18003c00` |
| `+0x004` | `0x08000189` | | `+0x004` | `0x08000189` |
| `+0x0E4` | **`0x0800048c`** | | `+0x0E4` | **`0x08000678`** |
| `+0x100` | `0x1800006c` | | `+0x100` | `0x1800006c` |
| `+0x1F8` | `0xe7fee7fe` | | `+0x1F8` | `0xe7fee7fe` |
| `+0x398` | `0xd15c0001` | | `+0x4F4` | `0x220423a4` |
| `+0x4F8` | `0x080000e9` | | `+0x4F8` | `0x601a059b` |
| `+0x4FC` | `0x080000c1` | | `+0x528` | `0x220423a4` |
| `+0x500` | `0x00000000` (past the image) | | `+0x52C` | `0x601a059b` |
| `+0x7FC` | `0x00000000` (past the image) | | `+0x538` | `0x18000200` |
| | | | `+0x53C` | `0x0f1c0de1` |
| | | | `+0x584` | `0xd15c0001` |
| | | | `+0x6E8` | `0x080000c1` |
| | | | `+0x6EC` | `0x00000000` (past the image) |
| | | | `+0x7FC` | `0x00000000` (past the image) |

The eth image is 320 words and the cc image 443 words, in a 512-word (2 KB) ROM that **aliases every 2 KB**. The `+0x500` / `+0x6EC` / `+0x7FC` rows are the "must read zero" controls: they stop the fingerprint passing on a bus that returns plausible data.

### 8.5 Phase B — identity, state and the census

| ADP read | What it is | FPGA read (`M-fpga`) | ASIC expectation | Recorded |
|---|---|---|---|---|
| `0x2A000FF0`/`FF4`/`FF8`/`FFC` | `reset_ctrl` CID `0x0D F0 05 B1` | — | **assert** (**R**) | |
| `0x2A000FD0`.. | `reset_ctrl` PID | — | **R** | |
| `0x2A000010`/`0x2A000014` | `RESET_INFO_CPU0`/`CPU1` | `0x00000000` | `0x00000000` — a power-on **clears** it, and `ext_sysresetreq` is tied `1'b0`. **Polarity is backwards in Revision 1.** | |
| `0x2C300010` | `bus_fault_monitor` `BFM1` | — | `0x42464d31` (**R**) | |
| `0x2C300000`/`004`/`008` | first-fault record | — | **record only** — offsets are class **B**. §3.8 predicts a fault at `0x24000000` on a no-flash board | |
| `0x2C000000` | `etc_capture` `ETC1` | — | `0x45544331` (**R**) | |
| `0x2C200000` | perf-probe ID | `0x50524631` | `0x50524631` (**R**, and **M-fpga**). **Not** the `0x50524601` in `perf_probe.h` | |
| `0x23000034` | IPC `PERIPH_ID` | — | `0xc0de0001` (**R**) | |
| `0x21000FFC` | QSPI `CIDR3` | `0x00000053` (ASCII `S`) | same | |
| `0x28000FE0` | `cc_periph` | — | record | |
| `0x28006FF0` | `uart2` CID | — | **record, do not assert** — freeze from silicon | |
| `0x20000FC8` | DMA-250 `IIDR` | `0x2500043b` — present, **not** power-gated | record. `IIDR == 0` would mean power-gated | |
| `0x2B000FE0` | `evt_route` "PID0" | `0x00000000` | **this is an ALIAS, not a PID.** The block has no CoreSight ID space | |
| `0x2E030200` | `LINK_CAPABILITIES` | `0x00000088` | record. The RDL's `0x00080008` is a spec the Chisel RTL never read | |
| `0x2E032108` | TideLink `fcsm`/`cal`/`lane` | `0x00100000` → `fcsm_state = 0`, `cal = 0`, `lane_locked = 0`, bit 20 = `a2l_replay_app_valid` | **record only.** `fcsm_state` is bits **[19:17]**, not [20:17] | |
| `0x2E0321F8` | XHB witness, marker `0xB5` | `0xb5000001` | marker **structural**; status bits may differ | |
| `0x2E0321E0` | marker `0xAD` | `0xad800000` | marker **structural**; status bits may differ | |
| `0x2E040010` | `TC_DEVICE_CLASS` | `0x00000002` (per-die strap, **not** the RDL's `0x00000001`) | **record.** Confirm a peer die reads something different before concluding the tiebreak works | |
| `0x2E04002C` | `TC_ERROR` | `0x00000000` — `[2] dual_root` clear | record | |
| `0x2D000000`.. (16 words) | **uninitialised SRAM power-up state** | `0x00000000` (FPGA BRAM initialises to zero — **tells you nothing about the ASIC**) | **§3.5.1 — take this in Phase B or lose it** | |
| `0x2D001FF0` | boot-confirm token | — | class **B**; record before Phase D | |

### 8.6 Phase B/C — the derived numbers

| Quantity | How | Recorded |
|---|---|---|
| `f_HCLK` from the perf probe, over a **host-timed** interval ≥ 15 s | §3.6 | |
| Host-timed interval `T` actually used | §3.6 | |
| `NS_INCR` written = `round(1e9 / f_HCLK)` | §4.4 | |
| `NS_INCR` read back | §4.4 | |
| `phc_ns_per_wall_second` after the write | §4.4 — target 1.000e9 | |
| QSPI no-flash watchdog = `65536 / f_HCLK` | §0.3 | |
| Measured link round-trip, ms per 32-bit read | expect ~130 ms; §0.5 | |
| **Does an ADP write to CPU1 IMEM `0x90003FF0` stick?** | §6.3.1 — four commands. **If not, §5.3 and §6.3 are void for this die** | |
| **`[B]`** Gate 8 positive control at **`0x2100000C`** (QSPI `ADDR` scratch): the two pre-reads, both patterns read back, and the restored value | §4.2 — **not a RAM word any more**; if you used a different address, say which and why | |

### 8.7 How to diff a die against `golden_fpga_reference.json`

That file is explicit that it is **not** an ASIC reference. Use it as a *transport* control — proof that the harness is really talking to a die — not as an expectation.

**Rows that should agree, and what agreement proves:**

| Row | Agreement proves |
|---|---|
| `0x30000000`, `0x40000000`, `0x40001000`, `0x50000000` → `R!` | The error class transfers. Structural, same decode |
| `0x08000000`, `0x80000000`, `0x84000000` → `0x18003c00` | Both builds share the stage-0 linker script's `__StackTop`. Weak evidence — it would agree even with the wrong image |
| `0x840321F8` → `0xe7fee7fe` | cc ROM `+0x1F8` is `0xe7fee7fe` in the shipped mask too. **Note `0x84xxxxxx` is an ordinary CPU1 ROM alias from ADP** — it is not a bare-link access and it does not wedge from this port |
| `0x28000000`, `0x20000000` → `0x00000000` with **no** `!` | The OK-with-zeros class is being distinguished from the error class |

**Rows that must NOT be diffed, and will differ on a healthy ASIC die:**

| Row | Why |
|---|---|
| **`0x18000000` = `0x05f5e100`** | **The single most likely false red in the whole exercise.** That word is `SystemCoreClock` from `smoke_remap`. The ASIC's `stage0_bootrom` has no such symbol; **`0x00000000` is correct on the ASIC** |
| `0x080000E4`, `0x800000E4` and every other ROM word past `+0x00C` | Different images. 172 of 320 words differ, first at word 55 |
| `0x21000000 = 0x00000100` | State, not a constant — whether XiP happens to be active |
| `0x29000000 = 0x00000004` | State. It *will* often agree — for the same reason, now understood — but it is a reading, not a check |
| `0x2D000000 = 0x00000000` | FPGA block RAM initialises to zero. ASIC SRAM does not necessarily. §3.5.1 |
| Everything under `state_dependent` and every TideLink row | Explicitly labelled "record these, never assert them", and the ASIC configuration differs |

**When this die's Phase-B fingerprint is complete, freeze it as the ASIC golden reference** — `golden_asic_reference.json`, alongside the FPGA one, with its own provenance header saying which die, which board, which `f_CLK`, and which QSPI state produced it. **Do not merge it into the FPGA file.**

---

## 9. When it goes wrong

### 9.1 No banner at all — the double blind

**Work this list before concluding anything about silicon. Six of the fourteen pre-power rows produce exactly this symptom.**

| Order | Check | Instrument | Why here |
|---|---|---|---|
| 1 | Supplies present and in sequence | meter | Common cause of the double blind (§7.2) |
| 2 | `CLK` toggling **at the pin**, at the frequency you think | scope | **No on-die pull.** A floating `CLK` gives no `SYS_HCLK`, no ADP, no DAP |
| 3 | `NRST` high and stable **at the pin** | scope | **No on-die pull.** A drifting `NRST` gives repeated resets or a permanent hold |
| 4 | `SE` = 0 **at the pin** | meter | If high, you were talking to TDI/TDO. **ASIC-only failure mode** |
| 5 | `TEST` = 0 **at the pin** | meter | If high, every HOSTIO synchroniser is bypassed |
| 6 | Does `IOREQ1` or `IOREQ2` ever assert? | scope | **This is the key measurement.** If yes: the die is alive, the ADP is running, and the host never acknowledged — the problem is entirely host-side and the news is good. If no: go back to rows 1–3 |
| 7 | Is `IOACK` biased **high** at the pin? | meter | If it is floating low, the SoC FSM left `OFFZ`, committed to a transfer and blocked in `TXC1`. §1.4 |
| 8 | Host status-nibble polarity: active-**high**? | code review | Used unmodified, the reference PIO driver makes a healthy link look dead |
| 9 | Host PIO parked holding ACK high? | `resync()` | Pins the SoC in `OFFZ` forever with no symptom other than silence |
| 10 | The seven wires, in the order you assumed | continuity | §1.1 is an OPEN decision; a swapped `IOACK`/`IODATA` pair is silent |

**Only after all ten: power-cycle once with the capture running, and if it is still silent, record the double blind as the result.** Per §7.2 that points at power, `CLK`, `NRST` or the PRMU — **not** at either debug path — and it is a genuine, reportable finding rather than an absence of one.

### 9.2 The port answers, then stops answering

| Symptom | Most likely cause | Action |
|---|---|---|
| Silence immediately after touching `0x24000000`–`0x24FFFFFF` | **HZ-6.** With no flash the QSPI AHB wrapper holds `HREADYOUT` low for `65536 / f_CLK` before erroring. **With flash present, a CPU executing from XiP livelocks on a backward branch and the wrapper watchdog never fires** | Wait `65536 / f_CLK` × 10 and retry. If it never returns, power-cycle. **Do not re-enter that aperture** |
| Silence immediately after touching `0x2E0321A0`–`0x2E0321B8` | **HZ-1.** *"Uninterruptible AXI hang. Power cycle to recover."* | Power-cycle. You have lost the die's cold state; §3.5.1 and the boot ladder must be retaken |
| Silence immediately after a `0x2F` access | **HZ-2.** A failed cross-die read parks the peer port and the **next** access wedges the host. `0x2F` has no default responder, so ADP has no error escape | Power-cycle. Never touch `0x2F` unattended |
| Silence after a write into `0x2E000000`–`0x2E003FFF` while the link is up | **HZ-3** | Power-cycle. Read link state before writing there |
| Silence, and the last command was fine | Host PIO parked (§1.5.2). `resync()` should recover it | `resync()`, then re-advertise the status nibble immediately — `resync()` reloads X=0 and the SoC otherwise sees "host has nothing to do" |
| Answers, but every read is `0x00000000` with no `!` | Could be genuine, could be a dead read path | Re-run `HIO-007`. **This is what Abort Gate 3 exists for**, and it is cheap enough to re-run after every destructive test |

**There is no `HREADY` timeout anywhere in the ADP FSM.** A slave that never returns `HREADY` hangs the ADP forever, with the bus held. ADP is **immune** to *undecoded* addresses — they reach a default slave that ERRORs and the monitor stays usable — and **fully exposed** to *stalling* ones. The hazard list is not caution; it is the complete set of places that can take the die away from you.

### 9.3 A result you do not believe

The FPGA plan's §4.3 list of false-green shapes is fully applicable here, and two of its six have already fired on real hardware. The two that matter most on the ASIC:

- **A no-change assertion that passes because the access went nowhere.** On the ASIC this is *worse* than on the FPGA, because `chip_core_remap_ctrl` bits are already set (§4.2). **Every no-change assertion needs a contemporaneous positive control on the same path.** A register that reads `0x00000000` both times is **UNEXERCISED**, not a pass.
- **An expected value from a specification the RTL never implemented.** This produces the mirror failure — a false **red** on a good die — and it fired four times on the first FPGA run. **A `B`-class row that goes red is a documentation finding until proven otherwise on the RTL.**

And one that is specific to this document: **a `G`-class row that goes red is a hard finding.** Those values are in the reticle. If `0x800000E4` does not read `0x08000678`, either the ROM read path is faulty or the wrong image was baked — and the second of those is checkable against `build/rom_verify/rom_content_hashes.txt` without touching hardware.

---

## 10. What is still unsafe on first silicon, and what this procedure cannot answer

### 10.1 Do not do these on the first die

| # | Action | Why not |
|---|---|---|
| 1 | **Any access to `0x24000000`–`0x24FFFFFF` (QSPI XiP).** | HZ-6, both directions: with no flash you stall for `65536 / f_CLK`; **with** flash a CPU executing from XiP can livelock with the watchdog never firing. XiP-heavy tests have wedged a host in the lab already |
| 2 | **Any access inside `0x2E0321A0`–`0x2E0321B8`.** | HZ-1. Uninterruptible hang; **simulation can never reproduce it**, so the blocklist is the only guard. The marker bytes visible in that band are bait — the stall is beside the APB slave and the marker is unreachable |
| 3 | **Any access to `0x2F000000`+ without a peer die, Phase E complete, and a human watching.** | HZ-2. No default responder; a failed read parks the port and the *next* access wedges the host |
| 4 | **Reading `0x2C100000`/`0x2C100100`/`0x2C100200` in a blind sweep.** | HZ-7: a **read** of an acquire page *acquires the lock*, and on the ASIC both cores are live and may be contending for it |
| 5 | **Reading `0x2E032020`/`024`/`038`/`15C`/`160`/`168`.** | HZ-8: read-clearing and auto-incrementing. A read *is* a write, and it corrupts live credit bookkeeping |
| 6 | **Programming the QSPI flash from HOSTIO** via the APB command aperture at `0x21000000`. | It is the only route to CPU0 firmware (§6.3) and it is *conceivable* — but it means erasing and programming the device the part boots from, from a debug port, on a die you have measured for one afternoon. **If the flash ends up in a state the ROM cannot parse, CPU1 halts and every §0.2 rung above 5 disappears.** Do it on a second die, or with a socketed part, or through a flash programmer |
| 7 | **Setting `0x29000000` bit 1 (`CHIP_CORE_BOOTGATE`).** | Inert — `cpu1_bootgate` is tied `1'b1` — but write-1-set and permanent. There is no reason to and no way back |
| 8 | **Boundary scan in the same session as HOSTIO.** | They are mutually exclusive by construction (`SE` switches the pins) and a JTAG master driving TDI while `SE` is low fights a 16 mA output. §1.3 |
| 9 | **Concluding anything from Phase D before §5.2 has established quiescence.** | Not a hardware hazard; a reasoning one. It is the specific failure this document exists to prevent |
| 10 | **`[B]` Running Tier 2 before any firmware-dependent test in the same power cycle.** | Not a hardware hazard either, and no gate catches it. `HIO-203`/`HIO-204` wipe all 32 KB of eth IMEM, `HIO-208` wipes all 8 KB of shared SRAM, and **nothing below Tier 5 can restart the core**. A Tier-5 run afterwards is measuring a wiped die and will red on a healthy one. §5.0 |

### 10.2 What HOSTIO fundamentally cannot test on this die

Structural limits, not gaps to be closed by a better test. Each belongs in the coverage record as *not covered by this port*.

1. **Everything off `debug_m`'s decode.** The Ethernet MAC and MDIO (`0x40000000`), the eth APB block including **the eth REMAP control** (`0x50000000`), eth scratch RX/TX (`0x30000000`/`0x38000000`), the CRC checker (`0x48000000`), the eth perf probe (`0x60000000`). **And because §6.3 shows HOSTIO cannot load CPU0 firmware on this build, "only through firmware" means "only with a provisioned flash". `[B]` For the MAC that makes it a two-hop chain — flash → firmware → MAC — never exercised end-to-end on any vehicle. §6.4.**
2. **CPU internal state.** No register read, no halt, no single-step, no breakpoints, no PC sampling. The `0xA0000000`/`0xB0000000` debug windows are visible to `dap_ss_0_m` only — and SWD has never attached.
3. **Anything analogue.** Supplies, IR drop, PLL lock and jitter, the D2D eye, LAN8720 electricals, pad drive, ESD.
4. **Timing and margin.** ADP issues single non-pipelined `NONSEQ` beats and cannot vary clock or voltage. **A die can pass every test in this procedure and still fail at speed.**
5. **AHB behaviour ADP cannot generate.** `HTRANS` is `NONSEQ` only; `HBURST` is `INCR` regardless; `HADDR[1:0]` is forced to `00` for word accesses, so **misaligned-access fault behaviour cannot be tested at all**; `HMASTLOCK` is tied 0. Multi-initiator arbitration can be *observed* through the perf probes but not *provoked*.
6. **Real-time response.** Interrupt latency, PPS edge alignment, PTP servo behaviour, packet-rate behaviour, races. **One qualification earned on the FPGA die: the PHC's *rate* IS measurable from this port, and measuring it found a real defect.** A rate is not a servo, and it was still enough.
7. **Simultaneity.** Two initiators at once, cross-die concurrency. HZ-2 additionally means the peer aperture **cannot be soaked** — one guarded shot at a time is the honest ceiling.
8. **Its own link.** If HOSTIO does not answer, HOSTIO cannot say why. §9.1.
9. **Scan, BIST and boundary scan.** Separate infrastructure, separate plan, and mutually exclusive with this one.
10. **Power-domain control.** The DMA-250's power state is observable (`IIDR == 0` means gated, not absent), not controllable.

### 10.3 Open items carried into first silicon

| Item | Status |
|---|---|
| **Where the seven conductors land on the ASIC bring-up board** | **OPEN. Gates everything.** §1.1 |
| **What drives `CLK`, and at what frequency** | **OPEN. Gates `NS_INCR`, the QSPI watchdog and every timing figure.** §1.2 |
| **`VDDIO` level and whether the host needs level shifting** | **OPEN.** The `od3` in the pad library name is not a datasheet. §1.1c |
| **The 330 Ω / 5 kΩ / 204 mV numbers against the ASIC pad** | **OPEN.** The method transfers; the numbers were taken against an FPGA IOBUF, not a `PDDW16DGZ_G`. §1.4 |
| **Does uninitialised SRAM read as zero on this die?** | **OPEN, and one-shot.** Decides whether §3.7.4's `HIO-107` replacement works at all. §3.5.1 |
| **The parking image** | Being built under `scripts/rig/eth_chiplet/hostio_fw/`. **Requirements P1–P5 in §5.3 are on it, and P3 — the signature word — is not optional**: without it, "CPU1 is quiet" is exactly the kind of assertion §4.2 forbids |
| **`HIO-119` discovery-table base address** | Unresolved in the built RTL. **SKIP it; never guess a base** |
| **`HIO-412` DMA-250 channel offsets, start bit, done bit** | Unresolved (`dma250_regdef.h`). The gate is otherwise open — the DMA is present and not power-gated |
| **`HIO-308`/`HIO-507` `bus_fault_monitor` offsets and the initiator-index map** | Still class **B** (`firmware/include/bus_dbg.h`). The `BFM1` magic is **R**; the offsets are not |
| **TideLink `fcsm_state = 8`** | Undocumented encoding, recorded on the FPGA with no peer. **Close it before `HIO-407` is trusted as a diagnostic** |
| **`HIO-505` firmware console** | **Structurally impossible on the ASIC.** It polls `uart2` RX-buffer-full to recover console output, but firmware writes **TX** — and neither UART is bonded on this die. There is no console over this port |
| **`HIO-501`/`HIO-503` on CPU0** | **Cannot launch firmware on CPU0** on this build. §6.3. This is new, and it belongs in the coverage record. **It also bears on the parallel firmware work:** `hostio_fw/fw_abi.h` describes `HIO-503` as *"zeroes `FW_SENTINEL_ADDR`, pulses `CPU0_SWRST` and polls for it to reappear"* — on the ASIC, `CPU0_SWRST` restarts CPU0 **in its boot ROM**, which overwrites eth IMEM from XiP and halts on a blank flash, so the sentinel never reappears and the test reds on a healthy die. That sequence works only with a provisioned flash carrying the image. **`[B]` §6.3's ROM-vs-ROM table says why the FPGA sessions succeeded at this and silicon cannot** |
| **Can ADP write CPU1 IMEM at `0x90000000`?** | **Disputed.** The generated RTL says yes and `hostio_fw/fw_abi.h` says no. §6.3.1 gives the four commands that settle it. **Settle it in Phase C** |
| **The FPGA `0x29000000 = 0x00000004` "unresolved" item** | **Explained by this document's mechanism.** The FPGA's CPU1 ROM reads `0x1800006c` at `+0x100`, matching a stage-0 image and **not** `smoke_remap` (`0x18000070`); the eth image cannot have written the gate because the release store is absent from `eth_gds.bits`; and the value is `0x4`, not `0x5`, which is precisely the all-candidates-failed signature. **Inference, not proof** — an earlier session's write cannot be formally excluded — but it is the only self-consistent reading, and `0x29000000` and `0x29000004` returning the same word is now *structurally* explained: `chip_core_remap_ctrl` ignores `HADDR` entirely |
| **`[B]` Ethernet, end to end** | **OPEN, and untested everywhere.** The MAC is unreachable from ADP by construction; firmware is the only route; on the ASIC that route is a two-hop chain (flash → firmware → MAC) that has never run. The FPGA's MDIO fault is **isolated to that board's physical line** and is not a chiplet question. §6.4 |
| **`[B]` Which firmware-recovery path this bench has** | **OPEN until §1.6 row 14 is answered.** With provisioned flash, `CPU0_SWRST` restores what Tier 2 destroyed. With no flash there is **no recovery in that power cycle**. It decides the whole running order. §5.0 |
| **`M-asic` values** | **There are none.** Every row of §8 exists to create the first ones |

---

## Appendix A — provenance of the mask-geometry evidence

| Artefact | Value |
|---|---|
| ROM bit extraction | `build/rom_verify/{cc,eth}_gds.bits` — 512 lines of 32 binary digits, one per ROM word |
| Extractor | `ASIC/asic-toolkit/scripts/asic-flow-rom-gds-bits`, version 2, sha256 `09444b31…c1f24ca` |
| Geometry sources | `ASIC/romlibs/cc_rom/rom_via.memlib` sha256 `3079b1ba…01024e94`; `ASIC/tech_wrappers/tsmc65/nanosoc_rom.spec` sha256 `759e9dad…71b27ce6` |
| Gate result | `words_compared: 512`, `words_differing: 0`, for **both** ROMs |
| Code files verified against | eth `eth_ss_bootrom.bintxt` sha256 `582200fe…52a1e29c`; cc `nanosoc_bootrom_chip_core.bintxt` sha256 `20095b28…27f2510f` |
| ROM gate last passed | `2026-08-25T08:15:53Z` on `srv03335` (`build/rom_verify/last_pass.txt`) |
| Release-store sites confirmed this session | `A4 23 04 22 9B 05 1A 60` at cc byte offsets `0x4F4` and `0x528`; **absent from `eth_gds.bits`**; no literal `0x29000000` anywhere in either ROM |
| Reported but not re-verified here | Unanimity of those two sites across all 23 build pins. This session confirmed the **current shipping stream** only |

> **`build/rom_verify/` is gitignored and host-only.** If this die's fingerprint is to be defensible later, copy the `.bits`, `.json` and `last_pass.txt` alongside the record sheet **before** the build directory is cleaned.

## Appendix B — command crib

```
Ax<8 hex>   set address        -- RE-ISSUE BEFORE EVERY ACCESS
A           report address
R           read, addr += size            R<n> = n-line block dump
Wx<8 hex>   write, addr += size
Mx<8 hex>   compare mask       M   report
Vx<8 hex>   compare value / fill datum    V   report
Px<8 hex>   poll, budget n     -> "P 0x<iters>" on match, "P!0x<budget>" on timeout
Fx<8 hex>   fill n units with V, addr += size
Ux<8 hex>   upload n raw binary bytes to addr, addr += 1
Cx<8 hex>   GPO8: 0x1xx clear, 0x2xx set, 0x3xx overwrite; low byte is the operand
X           exit to the STDIO bypass          ESC  re-enter the monitor (entry event ONLY)
```

**The two rules that govern every line above:** parameters are always `x` + exactly 8 hex digits (the digit count sets `HSIZE`), and `A` is re-issued before every access (`R` **and** `W` auto-increment).

**`S` is not a self-test** — it pushes a byte at a USRT whose APB slave is tied off and which has no pins. **`C` is inert at the system level** — `GPO8` is wired to `GPI8` at the SoC top and appears nowhere else. Do not plan a reset around `C`.
