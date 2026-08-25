/*-----------------------------------------------------------------------------
 * hostio_fw -- CPU1 parking loop.
 *
 * WHAT IT IS.  A valid ARMv6-M vector table and two instructions.  CPU1 sits
 * in them forever, fetching from its own local IMEM and doing nothing else.
 *
 * WHAT IT DELIBERATELY DOES NOT DO.
 *   * No DMEM access.  No .data, no .bss, no stack use at all -- the initial
 *     SP is a valid value the core loads at reset and never a target of any
 *     push, because nothing here pushes.
 *   * No peripheral access of any kind.  Not the mailbox, not the remap
 *     register, not the MAC, not shared SRAM.  A parked CPU1 that still
 *     announced itself in shared SRAM would be contending for the very bus
 *     the memory tests are trying to measure, which is the whole reason for
 *     parking it.
 *   * NO WFI.  CPU1's PRMU sources the fabric's HCLK and HRESETn and nothing
 *     in this tree establishes what CPU1's SLEEPING output does to it.  A
 *     parking loop that gated the fabric clock would take the debug port down
 *     with it, so this spins awake instead.  That costs an instruction fetch
 *     per iteration out of CPU1's OWN IMEM -- no fabric traffic.
 *   * No self-modification, no revectoring, no VTOR write (the plain M0 has
 *     no VTOR; on an M0+ the boot path has already pointed vectoring here).
 *
 * LINKED FOR CPU1'S OWN VIEW.  CPU1 sees its 16 KB IMEM at 0x10000000
 * (build_soc/firmware/nanosoc_multicore_soc_cc_stage1_imem_memory.ld).
 * 0x90000000 is the DEBUG PORT's alias for the same RAM, not an address CPU1
 * ever fetches from.  Every vector below therefore points into 0x1000xxxx,
 * which is correct whether or not CPU1's REMAP bit is set -- the 0x00000000
 * aperture is CPU1's boot ROM until REMAP says otherwise.
 *
 * READ README.md BEFORE TRYING TO INSTALL THIS.  There is no route from the
 * ADP debug port into CPU1 IMEM today, by design and in code.
 *
 * Copyright 2026, SoC Labs (www.soclabs.org)
 *---------------------------------------------------------------------------*/
    .syntax unified
    .cpu    cortex-m0
    .thumb

/* -- vector table --------------------------------------------------------- */
    .section .fw_vectors, "a", %progbits
    .align  2
    .global fw_park_vectors
fw_park_vectors:
    .word   __StackTop          /*  0  initial SP (never used: nothing pushes) */
    .word   fw_park             /*  1  Reset                                   */
    .word   fw_park             /*  2  NMI                                     */
    .word   fw_park             /*  3  HardFault                               */
    .word   0                   /*  4  reserved                                */
    .word   0                   /*  5  reserved                                */
    .word   0                   /*  6  reserved                                */
    .word   0                   /*  7  reserved                                */
    .word   0                   /*  8  reserved                                */
    .word   0                   /*  9  reserved                                */
    .word   0                   /* 10  reserved                                */
    .word   fw_park             /* 11  SVCall                                  */
    .word   0                   /* 12  reserved                                */
    .word   0                   /* 13  reserved                                */
    .word   fw_park             /* 14  PendSV                                  */
    .word   fw_park             /* 15  SysTick                                 */

/* -- the parking loop ----------------------------------------------------- */
/* .thumb_func is what puts the Thumb bit into every `.word fw_park` above.
 * fw_check.py re-reads word 1 out of the built binary and refuses the image if
 * that bit is clear, so the property is measured, not assumed. */
    .section .text.fw_park, "ax", %progbits
    .align  2
    .thumb_func
    .global fw_park
    .type   fw_park, %function
fw_park:
    nop
    b       fw_park
    .size   fw_park, . - fw_park
