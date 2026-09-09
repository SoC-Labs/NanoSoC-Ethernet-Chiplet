################################################################################
# fpga/hooks/post_bd.tcl - THE SAME ASSERTION, AT THE SEAM WHERE THE BLOCK
#                          DESIGN IS OPEN
#
# WHY THERE IS A SECOND SEAM AT ALL
# ===========================================================================
# DEVICE_CLASS is not a fileset generic and it is not a define.  It is a
# CONFIG.* property on the block design's own cell, set by the block design
# itself:
#
#     tidelink/fpga/targets/kr260-eth-chiplet/tidelink_design.tcl:155
#         set_property CONFIG.DEVICE_CLASS {1} $soc
#
# That is the strong form of the assertion - CONFIG.* is what survives
# ipx::package_project, where a fileset define does not - and it can only be
# read where the object exists.  MEASURED 2026-09-08: at pre_synth, in this
# toolkit's checkpoint synthesis, `get_ips` returns NOTHING.  The block design's
# IP objects belong to the project the bd stage built; the synthesis session
# read the design back out of it and has no IP objects of its own.  The row
# refused there, correctly, and refused again when it was "corrected" to the
# fully-qualified name tidelink_design_nanosoc_eth_chiplet_0_0 - the name was
# never the problem, the seam was.
#
# post_bd is the seam where it can be answered: the bd stage owns the project,
# the block design is current, and the hook fires AFTER the overlays and BEFORE
# save_bd_design (CONTRACT.md section 6.1.3), so the value asserted is the value
# that gets written.
#
# WHY THIS IS FOUR LINES AND NOT A SEVEN-HUNDRED-LINE COPY
# ===========================================================================
# The template's own instruction is `cp pre_synth.tcl post_bd.tcl` - the seam is
# the file's name.  That leaves two copies of one check in this project, and two
# copies of a check drift.  The toolkit's hook now takes ::RTL_ASSERT_SEAM as an
# override for exactly this case, so this file states the seam and sources the
# one implementation.  Every message and the record it writes name post_bd.
#
# The table it reads is RTL_ASSERT_TABLE_POST_BD (fpga/design.mk section 9);
# RTL_ASSERT_TABLE is what pre_synth reads.  One table per seam, because the two
# seams can answer different questions and a row nothing can evaluate refuses
# the stage.
#
# THE RECORD lands at $REPORT_DIR/rtl_assert_post_bd.txt and is collected with
# the run beside rtl_assert_pre_synth.txt.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

set ::RTL_ASSERT_SEAM post_bd
source [file join [file dirname [file normalize [info script]]] pre_synth.tcl]
unset -nocomplain ::RTL_ASSERT_SEAM

# Copyright (C) 2026, SoC Labs (www.soclabs.org)
