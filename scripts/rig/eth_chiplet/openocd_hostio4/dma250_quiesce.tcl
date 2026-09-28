# dma250_quiesce.tcl -- hold the rc4 DMA-250 still while a debugger touches
# CPU-local memory (the cpu_ss_hsel / eth_ss_hsel silicon erratum).
#
# WHY. On the rc4 die the network core's port (0x0000_0000-0x1FFF_FFFF, and
# 0x5000_0000-0x5FFF_FFFF from SWD) and CPU1's port (0x8000_0000-0x9FFF_FFFF)
# take HTRANS without HSEL. While the DMA-250 runs a copy that crosses bus-matrix
# ports it puts a phantom transfer on those ports every beat, and an SWD or
# HOSTIO4 access that lands in the phantom's window is DROPPED: answered OKAY on
# the network core, ERROR on CPU1. Neither debug master can start the fault; they
# are victims only. Firmware built with the DMA-250 guard never runs such a copy,
# but an older image, a hand-poked DMA or a host script still can.
#
# WHAT. NSEC_CTRL.ALLCHPAUSE pauses every channel at a beat boundary and holds
# any command enabled afterwards off the bus until it is released, so no phantom
# can occur while it is set. Proven on the rc4 DMA-250 RTL (block bench,
# fwfix/sim/dma_vch): a running cross-region copy pauses within ~20 cycles, the
# bus then stays IDLE for the whole window, the pause and the resume are each
# preceded by >300 IDLE cycles (no <=1-IDLE switch), and the copy completes
# correctly after release; a command enabled while paused issues 0 transfers
# until release.
#
# REGISTER SEMANTICS (rendered rc4 RTL, not the TRM):
#   NSEC_CTRL   0x2000_020C  bit 9  ALLCHPAUSE      write-1-SET: writing 0 does NOT clear it
#   NSEC_STATUS 0x2000_0208  bit 19 STAT_ALLCHPAUSED set when every channel is paused
#                                   or idle; write-1-CLEAR, and that W1C is also what
#                                   clears ALLCHPAUSE (dmansecctrl_reg_bank:116-118,147)
#                            bit 17 STAT_ALLCHIDLE  STICKY: never poll it for "paused"
# Both registers sit behind the DMA's own APB slave at 0x2000_0000, which is not
# an affected port, so the pause itself is never a victim.
#
# USE (any OpenOCD target that reaches 0x2000_0000: SWD mem_ap/cortex_m or hostio4):
#   source dma250_quiesce.tcl
#   dma250_quiesced { load_image app.bin 0x90000000 bin }   ;# pause, run, release
#   dma250_pause ; ... ; dma250_release                     ;# explicit, nests
#   dma250_hold_for_gdb chip.ahb                            ;# paused while gdb is attached
#   dma250_status                                           ;# registers, for a human
#   dma250_release force                                    ;# recover a pause left set
#
# COST. While paused, firmware's DMA commands do not progress; a firmware poll
# with a short bound can time out. Hold the pause only around debug accesses.

# Jim Tcl (OpenOCD's interpreter) has no reliable namespace variables, so the
# state lives in prefixed globals.
if {![info exists ::dma250q_base]}  { set ::dma250q_base 0x20000000 }
if {![info exists ::dma250q_polls]} { set ::dma250q_polls 20 }
if {![info exists ::dma250q_log]}   { set ::dma250q_log 1 }
set ::dma250q_depth 0
set ::dma250q_owned 0

proc dma250q_a {off} { return [expr {$::dma250q_base + $off}] }
proc dma250q_rd {addr} { return [lindex [read_memory $addr 32 1] 0] }
proc dma250q_wr {addr val} { write_memory $addr 32 [list $val] }
proc dma250q_say {msg} { if {$::dma250q_log} { echo "dma250_quiesce: $msg" } }

# Pause every DMA-250 channel; error (and leave no access to the body) if the
# DMA does not acknowledge. Nests: only the outermost call talks to the DMA.
proc dma250_pause {} {
    set ST_PAUSED [expr {1 << 19}]
    set ALLCHPAUSE [expr {1 << 9}]
    if {$::dma250q_depth > 0} {
        incr ::dma250q_depth
        return
    }
    set ctrl_a [dma250q_a 0x20C]
    set stat_a [dma250q_a 0x208]
    set ctrl [dma250q_rd $ctrl_a]
    if {$ctrl & $ALLCHPAUSE} {
        set ::dma250q_owned 0
        dma250q_say "ALLCHPAUSE already set by someone else; using it, will not release it"
    } else {
        # a stale STAT_ALLCHPAUSED would satisfy the poll before OUR request is
        # acknowledged; with ALLCHPAUSE clear, its W1C touches nothing else
        if {[dma250q_rd $stat_a] & $ST_PAUSED} {
            dma250q_wr $stat_a $ST_PAUSED
        }
        dma250q_wr $ctrl_a [expr {$ctrl | $ALLCHPAUSE}]
        set ::dma250q_owned 1
    }
    for {set i 0} {$i < $::dma250q_polls} {incr i} {
        set st [dma250q_rd $stat_a]
        if {$st & $ST_PAUSED} {
            set ::dma250q_depth 1
            dma250q_say [format "DMA-250 paused (NSEC_STATUS=0x%08x, %d poll(s))" $st [expr {$i + 1}]]
            return
        }
    }
    error [format "dma250_pause: the DMA-250 did not acknowledge ALLCHPAUSE after %d polls (NSEC_STATUS=0x%08x). Refusing: a debug access now could be dropped. The request stays armed; 'dma250_release force' clears it once acknowledged." $::dma250q_polls $st]
}

# Release the pause this session set. 'force' releases whoever set it.
proc dma250_release {{force ""}} {
    set ST_PAUSED [expr {1 << 19}]
    set ALLCHPAUSE [expr {1 << 9}]
    if {$force ne "force"} {
        if {$::dma250q_depth > 1} {
            incr ::dma250q_depth -1
            return
        }
        if {$::dma250q_depth == 0} {
            return
        }
    }
    set ::dma250q_depth 0
    if {!$::dma250q_owned && $force ne "force"} {
        dma250q_say "not releasing: this session did not set ALLCHPAUSE"
        return
    }
    set ::dma250q_owned 0
    dma250q_wr [dma250q_a 0x208] $ST_PAUSED
    set ctrl [dma250q_rd [dma250q_a 0x20C]]
    if {$ctrl & $ALLCHPAUSE} {
        error [format "dma250_release: ALLCHPAUSE still set (NSEC_CTRL=0x%08x): it clears only by W1C of an acknowledged STAT_ALLCHPAUSED" $ctrl]
    }
    dma250q_say "DMA-250 released"
}

# Run body with the DMA-250 paused; always release, even if body fails.
proc dma250_quiesced {body} {
    dma250_pause
    set rc [catch {uplevel 1 $body} res]
    dma250_release
    if {$rc} {
        error $res
    }
    return $res
}

# Keep the DMA-250 paused for as long as gdb is attached to target t.
proc dma250_hold_for_gdb {t} {
    $t configure -event gdb-attach  { dma250_pause }
    $t configure -event gdb-detach  { dma250_release }
}

proc dma250_status {} {
    foreach {name off} {NSEC_STATUS 0x208 NSEC_CTRL 0x20C CH0_CMD 0x1000 CH0_STATUS 0x1004 CH1_CMD 0x1100 CH1_STATUS 0x1104} {
        echo [format "%-11s 0x%08x = 0x%08x" $name [dma250q_a $off] [dma250q_rd [dma250q_a $off]]]
    }
}
