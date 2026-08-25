/*-----------------------------------------------------------------------------
 * hostio_fw -- the tiny freestanding runtime the CPU0 images share.
 *
 * No libc, no CMSIS.  Everything here is a volatile access or a spin.
 *
 * Copyright 2026, SoC Labs (www.soclabs.org)
 *---------------------------------------------------------------------------*/
#ifndef FW_RT_H
#define FW_RT_H

#include <stdint.h>
#include "fw_abi.h"

/* FW_CORE_HZ is supplied by the build (fpga = 25010000, asic = 100000000).
 * There is no default: a wrong core frequency is exactly the kind of silent
 * 4x error that makes a timeout look like a hardware fault, so the build must
 * say which target this binary is for. */
#ifndef FW_CORE_HZ
#error "FW_CORE_HZ must be defined by the build (make TARGET=fpga|asic)"
#endif

#define FW_R32(a)     (*(volatile uint32_t *)(uintptr_t)(a))
#define FW_W32(a, v)  (*(volatile uint32_t *)(uintptr_t)(a) = (uint32_t)(v))

#define FW_ETH_R(off)      FW_R32(FW_ETHMAC_BASE + (off))
#define FW_ETH_W(off, v)   FW_W32(FW_ETHMAC_BASE + (off), (v))

static inline void fw_dsb(void) { __asm volatile("dsb" ::: "memory"); }

/* A spin the compiler cannot fold away.  Roughly 4 core cycles per iteration
 * on an M0/M0+ (subs + bne, plus fetch), but it is NOT a calibrated delay and
 * nothing here depends on its accuracy to better than a factor of a few. */
static inline void fw_spin(uint32_t iters)
{
    while (iters--)
        __asm volatile("" ::: "memory");
}

/* ~1 ms of spinning at the frequency this binary was built for.  Constant-
 * folded: no runtime division, so the image needs no libgcc. */
#define FW_SPIN_1MS  ((uint32_t)(FW_CORE_HZ / 4000u))

/* Publish "which image, built for which clock" and the boot-confirm token.
 * Call ONCE from main().  Deliberately does NOT write the sentinel -- see
 * fw_publish_sentinel(). */
void fw_publish_identity(uint32_t image_id);

/* Write the fixed liveness sentinel.  CALL EXACTLY ONCE PER BOOT, from main(),
 * and never from a loop: HIO-503 clears this word and polls for it to come
 * back, so a loop that rewrites it would report a relaunch that never
 * happened. */
void fw_publish_sentinel(void);

/* Each image provides these two. */
void fw_main(void);       /* entered from the startup code, never returns  */
void fw_main_loop(void);  /* the steady-state loop, also the fault resume  */

#endif /* FW_RT_H */
