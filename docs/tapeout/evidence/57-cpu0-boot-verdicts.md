# Evidence for [57](../57-cpu0-boot-on-the-routed-netlist.md) — the CPU0 boot verdicts, verbatim

*Captured 2026-08-19. **This file exists because the build directories these came
from are gitignored and are overwritten by the next run.** The `fp1505` evidence
directory was rewritten twice in three hours on 2026-08-19 (11:20, then 12:25),
and a page that cites a path rather than the bytes becomes uncheckable the
moment somebody re-runs. Nothing below is edited: it is `verdict.txt` and the
`GLSN-` lines of `sim.log` as the simulator wrote them.*

---

## A. The probe run — `full_handshake` evidence, 2026-08-19 12:19

Netlist `ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads_pnr.v`,
sha256 `ac04899a03353a3c592a29fef9bdbfdeca800db893044788cf1d414271505197`;
PG-completed copy sha256 `1019108ef0fb1d23f3eca3d869596b5ba13d124424c0e1b9f0ba75c6d1abc15d`;
flash image sha256 `2a96f2a4b78a5917440f63956924dd214a8d1b8aaf16b86bfa0dbc0461d713af`
(TABLE0/TABLE1 + an 880-byte `SLOT_A` and an 880-byte `SLOT_B`);
VCS T-2022.06-SP2, zero-delay; run 20 ms, 277.7 s CPU.

This is the run that settles S2 vs S4 and that measures every re-sourced probe
beside the 4-bit-bus probe it replaces. The two `*_BUS` rows are the bus form,
kept deliberately in the same run as the control.

### `verdict.txt`

```
FORCES 0 no testbench override was applied; no design signal was held by the bench during this run.
cc_rom.nonx PASS words=512 X=0 mismatch=0
cc_rom.content PASS words=512 X=0 mismatch=0
eth_rom.nonx PASS words=512 X=0 mismatch=0
eth_rom.content PASS words=512 X=0 mismatch=0
cc_rom_port.accessed PASS accesses=15313 xdata=0
cc_rom_port.data_nonx PASS accesses=15313 xdata=0
eth_rom_port.accessed PASS accesses=12504 xdata=0
eth_rom_port.data_nonx PASS accesses=12504 xdata=0
cpu1_dmem_write.accessed PASS accesses=510 xdata=0
cpu1_dmem_write.data_nonx PASS accesses=510 xdata=0
cpu1_imem_write.accessed PASS accesses=220 xdata=0
cpu1_imem_write.data_nonx PASS accesses=220 xdata=0
eth_imem_prestaged.accessed FAIL accesses=0 xdata=0
eth_imem_prestaged.data_nonx FAIL accesses=0 xdata=0
eth_imem_write_after_release.accessed PASS accesses=220 xdata=0
eth_imem_write_after_release.data_nonx PASS accesses=220 xdata=0
eth_imem_fetch.accessed PASS accesses=436010 xdata=0
eth_imem_fetch.data_nonx PASS accesses=436010 xdata=0
cc_rom_msp_on_Q PASS at=1490000
cc_rom_rstvec_on_Q PASS at=1510000
eth_rom_msp_on_Q PASS at=3179430000
eth_rom_rstvec_on_Q PASS at=3179450000
cpu0_bootgate_released_by_cpu1_BUS FAIL never
cpu1_remap_after_verified_image_BUS FAIL never
remap_ctrl_bit2_set PASS at=3179230000
remap_bit2_at_flop_q PASS at=3179230000
remap_write_strobe PASS at=3179210000
qspi_xip_active_latched PASS at=64970000
ipc_slot1_warm_word PASS at=72710000
cpu1_remap_bit0_set PASS at=3179410000
cpu1_remap_after_verified_image_v2 PASS at=3179410000
eth_sysctrl_remap_set PASS at=5484510000
RESULT FAIL pass=28 fail=4
```

### `sim.log` — every `GLSN-` line except the per-access and per-address logs

```
GLSN-FORCES: 0 no testbench override was applied in this run
GLSN-EVENT: 0 simulation start
GLSN-FLASH: BENCH-SUPPLIED DEVICE sst26vf064b on QSPI_SCLK,QSPI_nCS,QSPI_IO
GLSN-FLASH:   the boot image below came from the bench, not the design.
GLSN-FLASH: loaded 'qspi_flash_image.hex' into sst26vf064b.I0.memory (0x100000 bytes pre-erased to FF)
GLSN-FLASH: offset 0x0 = 54 4f 4f 42 (magic, LE; expect 54 4f 4f 42)
GLSN-TRACE: 10000 bootgate_remap_ctrl = 0xZ
GLSN-TRACE: 10000 bootgate_bit2 = 0x0
GLSN-TRACE: 10000 remap_wr_en_q = 0x0
GLSN-TRACE: 10000 xip_active = 0x0
GLSN-TRACE: 10000 eth_sysctrl_remap0 = 0x0
GLSN-EVENT: 1270000 reset NRST released
GLSN-EVENT: 1490000 expect cc_rom_msp_on_Q satisfied
GLSN-EVENT: 1510000 expect cc_rom_rstvec_on_Q satisfied
GLSN-TRACE: 64970000 xip_active = 0x1
GLSN-EVENT: 64970000 expect qspi_xip_active_latched satisfied
GLSN-EVENT: 72710000 expect ipc_slot1_warm_word satisfied
GLSN-TRACE: 3179210000 remap_wr_en_q = 0x1
GLSN-EVENT: 3179210000 expect remap_write_strobe satisfied
GLSN-TRACE: 3179230000 bootgate_remap_ctrl = 0xZ
GLSN-TRACE: 3179230000 bootgate_bit2 = 0x1
GLSN-TRACE: 3179230000 remap_wr_en_q = 0x0
GLSN-EVENT: 3179230000 expect remap_ctrl_bit2_set satisfied
GLSN-EVENT: 3179230000 expect remap_bit2_at_flop_q satisfied
GLSN-TRACE: 3179390000 remap_wr_en_q = 0x1
GLSN-TRACE: 3179410000 remap_wr_en_q = 0x0
GLSN-EVENT: 3179410000 expect cpu1_remap_bit0_set satisfied
GLSN-EVENT: 3179410000 expect cpu1_remap_after_verified_image_v2 satisfied
GLSN-EVENT: 3179430000 expect eth_rom_msp_on_Q satisfied
GLSN-EVENT: 3179450000 expect eth_rom_rstvec_on_Q satisfied
GLSN-TRACE: 5484510000 eth_sysctrl_remap0 = 0x1
GLSN-EVENT: 5484510000 expect eth_sysctrl_remap_set satisfied
GLSN-EVENT: 19999990000 run complete
GLSN-VERDICT: cc_rom.nonx PASS words=512 X=0 mismatch=0
GLSN-VERDICT: cc_rom.content PASS words=512 X=0 mismatch=0
GLSN-VERDICT: eth_rom.nonx PASS words=512 X=0 mismatch=0
GLSN-VERDICT: eth_rom.content PASS words=512 X=0 mismatch=0
GLSN-INFO: cc_rom_port first access A=0x0 D=0x18003c00
GLSN-VERDICT: cc_rom_port.accessed PASS accesses=15313 xdata=0
GLSN-VERDICT: cc_rom_port.data_nonx PASS accesses=15313 xdata=0
GLSN-INFO: eth_rom_port first access A=0x0 D=0x18003c00
GLSN-VERDICT: eth_rom_port.accessed PASS accesses=12504 xdata=0
GLSN-VERDICT: eth_rom_port.data_nonx PASS accesses=12504 xdata=0
GLSN-INFO: cpu1_dmem_write first access A=0x19 D=0x80000c1
GLSN-VERDICT: cpu1_dmem_write.accessed PASS accesses=510 xdata=0
GLSN-VERDICT: cpu1_dmem_write.data_nonx PASS accesses=510 xdata=0
GLSN-INFO: cpu1_imem_write first access A=0x0 D=0x18000c00
GLSN-VERDICT: cpu1_imem_write.accessed PASS accesses=220 xdata=0
GLSN-VERDICT: cpu1_imem_write.data_nonx PASS accesses=220 xdata=0
GLSN-VERDICT: eth_imem_prestaged.accessed FAIL accesses=0 xdata=0
GLSN-VERDICT: eth_imem_prestaged.data_nonx FAIL accesses=0 xdata=0
GLSN-INFO: eth_imem_write_after_release first access A=0x0 D=0x18003c00
GLSN-VERDICT: eth_imem_write_after_release.accessed PASS accesses=220 xdata=0
GLSN-VERDICT: eth_imem_write_after_release.data_nonx PASS accesses=220 xdata=0
GLSN-INFO: eth_imem_fetch first access A=0x0 D=0x18003c00
GLSN-VERDICT: eth_imem_fetch.accessed PASS accesses=436010 xdata=0
GLSN-VERDICT: eth_imem_fetch.data_nonx PASS accesses=436010 xdata=0
GLSN-VERDICT: cc_rom_msp_on_Q PASS at=1490000
GLSN-VERDICT: cc_rom_rstvec_on_Q PASS at=1510000
GLSN-VERDICT: eth_rom_msp_on_Q PASS at=3179430000
GLSN-VERDICT: eth_rom_rstvec_on_Q PASS at=3179450000
GLSN-VERDICT: cpu0_bootgate_released_by_cpu1_BUS FAIL never
GLSN-VERDICT: cpu1_remap_after_verified_image_BUS FAIL never
GLSN-VERDICT: remap_ctrl_bit2_set PASS at=3179230000
GLSN-VERDICT: remap_bit2_at_flop_q PASS at=3179230000
GLSN-VERDICT: remap_write_strobe PASS at=3179210000
GLSN-VERDICT: qspi_xip_active_latched PASS at=64970000
GLSN-VERDICT: ipc_slot1_warm_word PASS at=72710000
GLSN-VERDICT: cpu1_remap_bit0_set PASS at=3179410000
GLSN-VERDICT: cpu1_remap_after_verified_image_v2 PASS at=3179410000
GLSN-VERDICT: eth_sysctrl_remap_set PASS at=5484510000
GLSN-RESULT: FAIL  pass=28 fail=4
```

---

## B. The forced run it replaced — `build/gls-netlist/fp1505_cc`, 2026-08-18 23:22

The comparator for the 916x timing discriminator: `eth_rom_msp_on_Q at=3470000`
against A's `at=3179430000`.

**This one demonstrates the hazard this file exists for.** It was read out of
`build/gls-netlist/fp1505_cc/verdict.txt` at 11:55 on 2026-08-19 and that path
had been overwritten by a concurrent re-run by 12:23 — while this page was being
written. What follows is the capture, and the path no longer holds it. Note that
it carries **no `FORCES` line at all**: it predates the census, which is exactly
the "absence means UNKNOWN, not clean" case the gate is built around. The force
was recorded only in the transcript beside it, as two `GLSN-FORCE` lines.

```
cc_rom.nonx PASS words=512 X=0 mismatch=0
cc_rom.content PASS words=512 X=0 mismatch=0
eth_rom.nonx PASS words=512 X=0 mismatch=0
eth_rom.content PASS words=512 X=0 mismatch=0
cc_rom_port.accessed PASS accesses=2857 xdata=0
cc_rom_port.data_nonx PASS accesses=2857 xdata=0
eth_rom_port.accessed PASS accesses=2602 xdata=0
eth_rom_port.data_nonx PASS accesses=2602 xdata=0
cpu1_dmem_write.accessed PASS accesses=245 xdata=0
cpu1_dmem_write.data_nonx PASS accesses=245 xdata=0
cc_rom_msp_on_Q PASS at=1490000
cc_rom_rstvec_on_Q PASS at=1510000
eth_rom_msp_on_Q PASS at=3470000
eth_rom_rstvec_on_Q PASS at=3490000
RESULT PASS pass=14 fail=0
```

and from its `sim.log`:

```
GLSN-FORCE: declared cpu0_bootgate -> 1'b1 : CPU0_BOOTGATE. chip_core_remap_ctrl[2] holds CPU0/eth in reset until CPU1 writes 0x4 to it, which its stage-0 bootrom only does after a QSPI XiP bring-up. This bench models no flash device, so CPU1 never reaches that write and CPU0 never fetches at all (eth_rom_port.accessed=0). Forcing the bootgate proves CPU0'S ROM FETCH PATH ONLY.
GLSN-FORCE: 3270000 applied cpu0_bootgate = 1'b1
```

```
$ grep -ci force build/gls-netlist/fp1505_cc/verdict.txt
0
$ grep -c GLSN-FORCE build/gls-netlist/fp1505_cc/sim.log
2
```

That pair — `RESULT PASS pass=14 fail=0` in the file the gate reads, and the
whole caveat in a file it did not open — is the regression this stage was
rewritten against.

---

## C. The run the in-tree signoff check passes — `full-20260814`, 2026-08-18 17:34

Four keys are asserted by `ci/signoff.yaml`'s `gls-netlist` check:
`cc_rom.content`, `cc_rom_port.accessed`, `cc_rom_msp_on_Q`,
`cc_rom_rstvec_on_Q`. All four are `PASS` here. The file's own `RESULT` is
`FAIL`.

```
cc_rom.nonx PASS words=512 X=0 mismatch=0
cc_rom.content PASS words=512 X=0 mismatch=0
eth_rom.nonx PASS words=512 X=0 mismatch=0
eth_rom.content PASS words=512 X=0 mismatch=0
cc_rom_port.accessed PASS accesses=2857 xdata=0
cc_rom_port.data_nonx PASS accesses=2857 xdata=0
eth_rom_port.accessed FAIL accesses=0 xdata=0
eth_rom_port.data_nonx FAIL accesses=0 xdata=0
cpu1_dmem_write.accessed PASS accesses=245 xdata=0
cpu1_dmem_write.data_nonx PASS accesses=245 xdata=0
cc_rom_msp_on_Q PASS at=1490000
cc_rom_rstvec_on_Q PASS at=1510000
eth_rom_msp_on_Q FAIL never
eth_rom_rstvec_on_Q FAIL never
RESULT FAIL pass=10 fail=4
```

---

## D. The shipped bench, as republished 2026-08-19 12:25

Another session landed a corrected `ASIC/gls-netlist/bench/eth_chiplet_fp1505_cc.json`
while doc 57 was being written. It drops the two 4-bit-bus expects, probes the
bootgate as a single bit (as a **trace**, not an expect), and adds
`qspi_flash_addressed`, `cpu0_rom_idle_at_1ms` and the `cpu1_imem_fetch` pair.
Its `run_cycles` is 250,000 — the simulation ends at 5.000 ms, and CPU0's
post-CRC store was measured at 5.4845 ms.

```
FORCES 0 no testbench override was applied; no design signal was held by the bench during this run.
cc_rom.nonx PASS words=512 X=0 mismatch=0
cc_rom.content PASS words=512 X=0 mismatch=0
eth_rom.nonx PASS words=512 X=0 mismatch=0
eth_rom.content PASS words=512 X=0 mismatch=0
cc_rom_port.accessed PASS accesses=16783 xdata=0
cc_rom_port.data_nonx PASS accesses=16783 xdata=0
eth_rom_port.accessed PASS accesses=23919 xdata=0
eth_rom_port.data_nonx PASS accesses=23919 xdata=0
cpu1_dmem_write.accessed PASS accesses=512 xdata=0
cpu1_dmem_write.data_nonx PASS accesses=512 xdata=0
cpu1_imem_write.accessed PASS accesses=250 xdata=0
cpu1_imem_write.data_nonx PASS accesses=250 xdata=0
cpu1_imem_fetch.accessed PASS accesses=13141 xdata=0
cpu1_imem_fetch.data_nonx PASS accesses=13141 xdata=0
cc_rom_msp_on_Q PASS at=1490000
cc_rom_rstvec_on_Q PASS at=1510000
cpu1_main_entered PASS at=46830000
eth_rom_msp_on_Q PASS at=3457830000
eth_rom_rstvec_on_Q PASS at=3457850000
cpu0_rom_idle_at_1ms PASS at=1000010000
qspi_flash_addressed PASS at=47590000
eth_rom_branch_word62 PASS at=3457870000
RESULT PASS pass=22 fail=0
```
