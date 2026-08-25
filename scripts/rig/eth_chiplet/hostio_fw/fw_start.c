/*-----------------------------------------------------------------------------
 * hostio_fw -- startup shared by the two CPU0 images.
 *
 * Freestanding: no CMSIS, no libc, no crt0, no .data-copy step.  The whole
 * image (vectors, code, rodata and initialised data) is uploaded into IMEM,
 * which IS RAM, so load address == run address and the only runtime fix-up
 * needed is zeroing .bss.
 *
 * NO UART.  The ADP debug port's own STDIO path is dead on this SoC (the debug
 * USRT's APB slave is tied off and it has no pins) and uart2 needs an external
 * TXD->RXD loop before ADP can see anything, so a console here would be a
 * channel that reports nothing.  Every result these images produce travels
 * through shared SRAM instead -- the path HIO-504 proves.
 *
 * NO WFI ANYWHERE.  Nothing in this tree establishes what a core's SLEEPING
 * output does to the PRMU that sources the fabric's HCLK/HRESETn, so no image
 * here ever signals sleep.  Spin loops only.
 *
 * Copyright 2026, SoC Labs (www.soclabs.org)
 *---------------------------------------------------------------------------*/
#include "fw_rt.h"

extern uint32_t __StackTop;
extern uint32_t __bss_start__;
extern uint32_t __bss_end__;

void fw_reset(void);
void fw_startup(void);
void fw_fault_resume(void);
void fw_hardfault(void);

/* -- vector table ---------------------------------------------------------
 * A full ARMv6-M core table: 16 entries, so a stray NMI/SVC/PendSV/SysTick
 * lands somewhere defined instead of in whatever bytes happen to follow the
 * table.  Offset 0 is the initial SP, offset 4 the reset vector -- and
 * fw_check.py re-reads BOTH OUT OF THE BUILT BINARY and refuses an image whose
 * reset vector has not got the Thumb bit set, so that property is measured in
 * the artefact rather than assumed of the toolchain.
 *
 * VTOR is deliberately not written.  These images take no interrupts, the
 * plain Cortex-M0 has no VTOR at all, and on the boot paths that do reach here
 * the ROM has already pointed vectoring at IMEM (the ASIC stage-0 sets VTOR;
 * the FPGA smoke_remap ROM sets the REMAP alias).                            */
__attribute__((section(".fw_vectors"), used))
void *const fw_vectors[16] = {
    (void *)&__StackTop,    /*  0  initial SP                  */
    (void *)fw_reset,       /*  1  Reset                       */
    (void *)fw_hardfault,   /*  2  NMI                         */
    (void *)fw_hardfault,   /*  3  HardFault                   */
    0, 0, 0, 0, 0, 0, 0,    /*  4-10 reserved on ARMv6-M       */
    (void *)fw_hardfault,   /* 11  SVCall                      */
    0, 0,                   /* 12-13 reserved                  */
    (void *)fw_hardfault,   /* 14  PendSV                      */
    (void *)fw_hardfault,   /* 15  SysTick                     */
};

/* -- reset ---------------------------------------------------------------- */
__attribute__((naked, used))
void fw_reset(void)
{
    /* Every boot path that reaches here has already loaded SP from vector[0],
     * but one that did not would run with whatever SP it had, so set it again
     * from the same word rather than depend on the caller. */
    __asm volatile(
        "    .syntax unified\n"
        "    ldr   r0, =fw_vectors\n"
        "    ldr   r0, [r0, #0]\n"
        "    mov   sp, r0\n"
        "    bl    fw_startup\n"
        "1:  b     1b\n"
        "    .ltorg\n");
}

__attribute__((used))
void fw_startup(void)
{
    uint32_t *p = &__bss_start__;
    while (p < &__bss_end__)
        *p++ = 0u;
    fw_dsb();
    fw_main();
    for (;;) { }            /* fw_main does not return; belt and braces */
}

/* -- shared publishers ---------------------------------------------------- */
void fw_publish_identity(uint32_t image_id)
{
    FW_W32(FW_IMAGE_ID_ADDR, FW_IMAGE_ID_MAGIC | (image_id & 0xFFu));
    FW_W32(FW_CORE_HZ_ADDR, (uint32_t)FW_CORE_HZ);
    FW_W32(FW_BOOT_TOKEN_ADDR, FW_BOOT_TOKEN_VALUE);
    fw_dsb();
}

void fw_publish_sentinel(void)
{
    FW_W32(FW_SENTINEL_ADDR, FW_SENTINEL_VALUE);
    fw_dsb();
}

/* -- fault handling -------------------------------------------------------
 * HIO-507 wants ONE deliberate access to an unmapped address, and the image
 * that makes it has to survive doing so: a dead CPU0 also kills the heartbeat
 * HIO-504 needs, and then nothing can read the bus-fault record back through
 * firmware at all.
 *
 * So this handler returns PROPERLY.  It rewrites the stacked PC to
 * fw_fault_resume and performs a normal exception return, which clears the
 * HardFault's active state.  It does NOT branch out of handler mode with the
 * fault still active -- that leaves the core at priority -1, where the next
 * fault is a lockup rather than a fault, and the difference is invisible from
 * the debug port.
 *
 * The frame is always on MSP: these images never switch to PSP and never take
 * a nested exception, so EXC_RETURN's stack bit cannot be anything else.
 * ARMv6-M frame layout is r0 r1 r2 r3 r12 lr pc xpsr, so PC sits at +24.  Bit
 * 0 of the stacked PC is cleared explicitly; Thumb state comes back from the
 * stacked xPSR, which is untouched.                                          */
__attribute__((naked, used))
void fw_hardfault(void)
{
    __asm volatile(
        "    .syntax unified\n"
        "    mov   r0, sp\n"
        "    ldr   r1, [r0, #24]\n"          /* stacked PC                   */
        "    ldr   r2, =%c0\n"
        "    str   r1, [r2, #0]\n"           /* FW_FAULT_PC_ADDR  = that PC  */
        "    ldr   r2, =%c1\n"
        "    movs  r3, #%c2\n"
        "    str   r3, [r2, #0]\n"           /* FW_FAULT_INFO_ADDR = TAKEN   */
        "    ldr   r1, =fw_fault_resume\n"
        "    movs  r3, #1\n"
        "    bics  r1, r3\n"                 /* stacked PC bit 0 must be 0   */
        "    str   r1, [r0, #24]\n"
        "    bx    lr\n"                     /* real exception return        */
        "    .ltorg\n"
        :
        : "i"(FW_FAULT_PC_ADDR), "i"(FW_FAULT_INFO_ADDR),
          "i"(FW_FAULT_INFO_TAKEN));
}

/* Where a caught fault resumes: straight back into the image's steady-state
 * loop, on the stack the exception return has already unwound. */
__attribute__((used))
void fw_fault_resume(void)
{
    fw_main_loop();
    for (;;) { }
}
