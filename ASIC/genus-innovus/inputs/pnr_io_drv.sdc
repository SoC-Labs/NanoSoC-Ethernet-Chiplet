#-----------------------------------------------------------------------------
# pnr_io_drv.sdc -- the IO ring's slew limit, stated where the IO ring is.
#
# READ BY P&R ONLY. scripts/nanosoc_eth_chiplet_pads.mmmc names this file in
# create_constraint_mode, second, after the Genus-written
# outputs/<block>_syn.sdc. Genus never reads it, and that is the whole reason
# this file can exist: `-override` is an Innovus parameter that Genus does not
# document, so the mechanism is only available on this side of the flow.
#-----------------------------------------------------------------------------
#
# WHAT PROBLEM. inputs/constraints.sdc ends with
#
#     set_max_transition 0.300 [current_design]
#
# and that line is correct and must stay: it is 2.55x tighter than the library
# default, it catches 26,050 internal nets, and it is what removed the last
# post-route setup ECO. Its own comment block prices it, defends it against
# three specific "improvements", and then states the one thing it cannot fix:
#
#     "The smallest limit from ANY source wins -- library, port-specific SDC and
#      design-scoped SDC alike -- and a per-port value can never buy an
#      exemption back. ... Of the 236 [pad-ring rows], only 97 can NEVER be
#      fixed: 48 uPAD_*/PAD pins driving off-chip, 49 top-level ports, slew
#      ASSERTED by set_input_transition, not computed. No repeater moves either.
#      ... Innovus -override can exempt them on the P&R side where Genus is not
#      the reader."
#
# THIS FILE IS THAT EXEMPTION. It is not a new decision; it is the decision that
# block already reached, finally applied on the side of the flow that can apply
# it.
#
# THE POPULATION, MEASURED -- rc5vt-20260829/reports/drv_05_route_opt.rep, the
# post-route DRV report of the first unaided RTL->GDS run. 195 max_transition
# failing endpoints, all in default_analysis_view_setup, split exactly:
#
#     96  top-level ports and uPAD_*/PAD pins      <- this file
#     99  internal pins, worst -0.223, median ~-0.00  <- NOT this file; those are
#                                                        real and opt fixes them
#
# The 96, by actual slew and count:
#
#     6.324  2   I2C_SDA        (100 pF off-chip bus, 100 kHz interface)
#     6.321  2   I2C_SCL
#     5.000  8   NRST SWDCK SWDIO RMII_MDIO + their PADs
#     3.000 16   QSPI_IO[3:0] RMII_REF_CLK RMII_RXD[1:0] RMII_CRS_DV + PADs
#     2.000 18   HOSTIO4_P1[6:0] SE TEST + PADs
#     1.866  8   RMII_MDC RMII_TXD[1:0] RMII_TX_EN + PADs
#     1.200  2   CLK
#     1.087  4   QSPI_SCLK QSPI_nCS
#     0.676 18   TL_CLK_TX TL_TX[7:0] + PADs
#     0.593 18   TL_CLK_RX TL_RX[7:0] + PADs
#
# EVERY ONE OF THOSE NUMBERS IS AN ASSERTION OR AN OFF-CHIP LOAD, not a property
# the router can change. 3.000 is inputs/qspi_constraints.sdc:143 and
# inputs/ethernet_constraints.sdc:161 (`set_input_transition -max 3.0`); 5.000 is
# ethernet_constraints.sdc:225 and the library's last characterised point;
# 6.32 is i2c_constraints.sdc's 100 pF `set_load` through the pad driver, on a
# bus whose own SDC line 226 already asked for 300 ns and was overruled by the
# design-scope min(); 0.593/0.676 are the D2D pads' own driving cell and channel
# capacitance from tidelink_constraints.sdc.
#
# ------------------------------------------------------------------------------
# WHAT THIS COSTS, STATED BEFORE THE CODE
# ------------------------------------------------------------------------------
# The IO ring is no longer checked against 0.300 ns. It is checked against
# PNR_IO_MAX_TRAN instead, default 7.000 ns -- above the worst value this design
# has ever produced (6.324) and therefore quiet today, but NOT infinite: a pin
# that went past 7 ns would fire, and 7.0 is close enough to 6.324 that a
# material change in the I2C load would fire it.
#
# WHAT THAT MEANS THE RUN NO LONGER PROVES: nothing about IO slew that it
# previously proved. A limit of 0.300 on a pin whose slew is asserted at 3.0 is
# not a check that was passing before and is being switched off; it is a check
# that reported the same 96 rows on every run regardless of the design, which is
# a constant, not a measurement. The standing census of what those slews ARE
# lives in rc5vt-20260829/reports/drv_05_route_opt.rep and in the table above,
# and it should be re-read, not assumed, whenever a pad, a load or an interface
# rate changes.
#
# WHAT IS DELIBERATELY NOT EXEMPTED. The pad cells' CORE-side pins (I, OEN, REN
# -- 139 of them in the rc4 census) are driven by internal logic and are ordinary
# fixable violations. They do not match either selector below and stay at 0.300.
#
# ------------------------------------------------------------------------------

# THE WHOLE FILE BEHIND ONE SWITCH, so "what does this change" is answered by a
# run rather than by reading. PNR_IO_DRV_OVERRIDE=0 leaves the design-scope
# 0.300 applying to the pad ring, which is exactly what every run up to and
# including rc5 did.
#
# IT IS A proc AND NOT AN EARLY `return`, deliberately. A bare `return` at the
# top level of a constraint file behaves one way under `source` and is not
# guaranteed to behave the same way under whatever read_sdc does with the file
# internally. A proc called on the next line has one meaning everywhere, and it
# also keeps every temporary in this file out of the global namespace, which
# matters when the file is sourced into a live session by hand.
proc pnr_io_drv_apply {} {
    # -override does nothing at all unless this is true, and it is false by default.
    # Setting it and NOT proving it is how a run comes out looking configured and
    # is not, so the read-back is checked and a failure is announced loudly rather
    # than left for the DRV report to imply.
    if {[catch {set_db timing_constraint_enable_drv_limit_override true} __e]} {
        puts "**ERROR: pnr_io_drv.sdc: timing_constraint_enable_drv_limit_override"
        puts "**ERROR:   could not be set ($__e). Every -override below is INERT and"
        puts "**ERROR:   the IO ring is still being checked against 0.300 ns."
    } else {
        set __rb "<unreadable>"
        catch { set __rb [get_db timing_constraint_enable_drv_limit_override] }
        if {$__rb ne "true"} {
            puts "**ERROR: pnr_io_drv.sdc: timing_constraint_enable_drv_limit_override"
            puts "**ERROR:   was set to true and reads back '$__rb'. The -override"
            puts "**ERROR:   parameters below will be accepted and ignored."
        } else {
            puts "pnr_io_drv.sdc: drv_limit_override enabled (reads back $__rb)"
        }
        unset -nocomplain __rb
    }
    unset -nocomplain __e

    # The ceiling. Overridable from design.mk (PNR_IO_MAX_TRAN) so a sweep does not
    # need this file edited, and defaulted here so the file is still correct when it
    # is sourced by hand on a database.
    set __io_tran 7.000
    if {[info exists ::env(PNR_IO_MAX_TRAN)]
        && [string is double -strict [string trim $::env(PNR_IO_MAX_TRAN)]]} {
        set __io_tran [string trim $::env(PNR_IO_MAX_TRAN)]
    }

    # Two selectors, and they are narrow on purpose.
    #   all_ports        the chip boundary. A top-level port's slew is either an
    #                    assertion or the far side of a pad; neither is routable.
    #   uPAD_*/PAD       the off-chip face of every pad cell in this ring. The
    #                    naming convention is the padring wrapper's and is asserted
    #                    below rather than assumed, because a wrapper rename would
    #                    otherwise silently reduce this file to the ports half.
    # TWO SPELLINGS OF THE SAME SELECTION, AND BOTH ARE NEEDED. MEASURED on
    # rc5's placed database, 2026-08-31:
    #
    #     get_pins uPAD_*/PAD          -> 1     (prints as "0x1")
    #     get_pins -hierarchical ...   -> 1
    #     get_db pins uPAD_*/PAD       -> 48    pin:.../uPAD_HOST_IO_0/PAD ...
    #     get_ports *                  -> 1
    #     get_db ports *               -> 52
    #
    # get_ports/get_pins return an Innovus COLLECTION HANDLE, and `llength` of
    # a collection is 1 no matter how many objects it holds. get_db returns a
    # plain Tcl list. The first draft counted the collection, got 1, and its own
    # sanity check correctly announced "only 1 uPAD_*/PAD pins matched" -- the
    # check worked; the count did not.
    #
    # SO: the COLLECTION goes to set_max_transition, because that is the object
    # type the SDC commands take and because get_ports expands bused ports the
    # way SDC expects. The get_db LIST is used only for the counts below, which
    # exist to notice a pad-wrapper rename.
    #
    # `all_ports` is NOT used. MEASURED on rc5's routed database: it is an
    # SDC-context command and raises `invalid command name "all_ports"` when
    # this file is sourced into a live Innovus session by hand, which is how
    # anyone debugging a DRV report will source it. get_ports is valid in both.
    set __io_pads [get_pins uPAD_*/PAD]
    set __io_prts [get_ports *]
    set __n_pads  [llength [get_db pins uPAD_*/PAD]]
    set __n_prts  [llength [get_db ports *]]

    if {$__n_pads < 40} {
        puts "**WARN: pnr_io_drv.sdc: only $__n_pads uPAD_*/PAD pins matched."
        puts "**WARN:   The rc5 census found 48 of them violating alone. If the pad"
        puts "**WARN:   wrapper's instance naming has changed, this file is now"
        puts "**WARN:   exempting the ports and not the pads, and the max_transition"
        puts "**WARN:   count will carry ~48 rows nothing in the design can fix."
    }

    # CAUGHT, NOT LET FLY, and the asymmetry with the rest of this project's
    # gates is deliberate. This file is read by read_mmmc/init_design at the
    # very start of the PLACE stage of a five-hour run. An uncaught error here
    # aborts that run before it has read a library, to fix a reporting problem.
    # A caught one degrades to "the IO ring keeps the 0.300 limit", which is
    # the pre-2026-08-31 behaviour AND which the route stage's max_transition
    # budget of 0 then reports loudly on its own. Failing quietly is not an
    # option either way round; failing EXPENSIVELY is.
    #
    # MEASURED 2026-08-31, and this is why the catch is here at all: issued
    # interactively on a loaded database rather than through a constraint mode,
    # these two lines raise
    #     **ERROR: (TCLCMD-1048): constraints are specified but no constraint
    #     mode is enabled interactively.
    # That is correct behaviour and not a defect in this file -- through
    # create_constraint_mode a mode IS active -- but anyone sourcing this file
    # by hand to debug a DRV report needs
    #     set_interactive_constraint_modes [all_constraint_modes -active]
    # first, and will otherwise conclude the mechanism does not work.
    set __ok 1
    foreach {__what __objs __n} [list port(s) $__io_prts $__n_prts \
                                      pad(s)  $__io_pads $__n_pads] {
        if {$__n == 0} { continue }
        if {[catch {set_max_transition $__io_tran -override $__objs} __oe]} {
            set __ok 0
            puts "**ERROR: pnr_io_drv.sdc: set_max_transition -override on the"
            puts "**ERROR:   $__n $__what raised: $__oe"
            puts "**ERROR:   The IO ring keeps the design-scope 0.300 ns limit."
            puts "**ERROR:   Expect the pad-ring rows back in the max_transition"
            puts "**ERROR:   report and the route budget of 0 to fail on them."
        }
    }
    if {$__ok} {
        puts "pnr_io_drv.sdc: max_transition $__io_tran ns -override on\
              $__n_prts port(s) and $__n_pads pad PAD pin(s)"
    }
    unset -nocomplain __ok __what __objs __n __oe __n_pads __n_prts

    unset -nocomplain __io_tran __io_pads __io_prts

}

if {[info exists ::env(PNR_IO_DRV_OVERRIDE)]
    && [string trim $::env(PNR_IO_DRV_OVERRIDE)] eq "0"} {
    puts "pnr_io_drv.sdc: PNR_IO_DRV_OVERRIDE=0 - the IO ring keeps the"
    puts "  design-scope max_transition 0.300 limit. Expect ~96 failing"
    puts "  max_transition endpoints on ports and uPAD_*/PAD pins that no"
    puts "  optimisation pass can fix."
} else {
    pnr_io_drv_apply
}
