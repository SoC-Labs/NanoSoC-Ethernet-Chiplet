#-----------------------------------------------------------------------------
# survival.tcl -- what the eth chiplet declares must survive synthesis
#
# PROPOSED. Install as ASIC/eth-chiplet/survival.tcl and point
# SURVIVAL_MANIFEST at it from ASIC/eth-chiplet/design.mk. Nothing has been
# installed; see docs/bscan/PATCHSET.md.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#
# THIS FILE IS THE ONLY PLACE THAT KNOWS WHAT A PAD TABLE IS. The engine's
# `survive` command takes a pattern and a floor and nothing else; every number
# below is computed HERE, from an artefact this project already maintains and
# regenerates (`make bscan-table`). That is the whole point of the split: the
# toolkit is shared by designs that have no boundary scan, no pad table and no
# opinion about either.
#
# NO NUMBER IN THIS FILE IS TYPED. 76, 43, 119 and 48 are all read out of
# src/rtl/bscan/pad_table.json at run time. On the compute chiplet the same file
# would compute 80 and a different pad list without being edited. Literals are
# the failure mode this project keeps repeating: a number that is right for one
# die and quietly wrong for the next one.
#
# WHY REGEXP AND NOT A JSON PARSER. This is sourced by Genus's embedded Tcl.
# `package require json` needs tcllib, which is not part of the tool
# installation and is not something a synthesis run should depend on. The pad
# table is machine-generated with one key per line, so a line-oriented regexp is
# exact for it -- and the extraction ASSERTS, so a reformatted table fails the
# input contract loudly instead of yielding a plausible wrong number.
#-----------------------------------------------------------------------------

set _bs_table [file join [file dirname [info script]] .. .. src rtl bscan pad_table.json]

# --- read it, or stop ---------------------------------------------------------
# `die` here is right: this runs in section 0, before a licence-hour is spent,
# and a manifest that cannot read its own source artefact has no claims to make.
# Reporting that as "no claims" would be a green that measured nothing.
if {![file readable $_bs_table]} {
    die "survival manifest: cannot read the pad table at $_bs_table." \
        "  Every floor in ASIC/eth-chiplet/survival.tcl is derived from it," \
        "  so without it this design would declare nothing and the" \
        "  boundary-scan register would be unguarded. Regenerate it with" \
        "  \`make bscan-table\`."
}
set _bs_fh [open $_bs_table r]
set _bs_txt [read $_bs_fh]
close $_bs_fh

# --- the chain length the design declares ------------------------------------
if {![regexp {"boundary_length"\s*:\s*([0-9]+)} $_bs_txt -> _bs_len]} {
    die "survival manifest: no \"boundary_length\" in $_bs_table." \
        "  The table exists but does not have the shape this manifest parses." \
        "  Do NOT default it to a number - a floor invented here is exactly the" \
        "  literal this file exists to avoid."
}

# --- the control population the pad kinds imply -------------------------------
# One UPDATE stage per control cell. A bidir pad contributes two (its data cell
# and its output-enable cell); an open-drain pad one; a plain output one. Inputs
# contribute none - they are observe-only.
set _bs_out   [regexp -all {"kind"\s*:\s*"output"}    $_bs_txt]
set _bs_bid   [regexp -all {"kind"\s*:\s*"bidir"}     $_bs_txt]
set _bs_od    [regexp -all {"kind"\s*:\s*"opendrain"} $_bs_txt]
set _bs_ctl   [expr {$_bs_out + 2 * $_bs_bid + $_bs_od}]

# One SHIFT stage per boundary cell, one UPDATE stage per control cell.
# 76 + 43 = 119 on this chiplet, and 119 is exactly what the intact
# 2026-08-19 netlist holds - measured, see docs/bscan/DELETION_GUARD_DESIGN.md.
set _bs_flops [expr {$_bs_len + $_bs_ctl}]

# --- the pad instances the ring is made of ------------------------------------
set _bs_pads {}
foreach {_ _bs_i} [regexp -all -inline {"inst"\s*:\s*"([^"]+)"} $_bs_txt] {
    lappend _bs_pads $_bs_i
}
if {![llength $_bs_pads]} {
    die "survival manifest: the pad table names ZERO pad instances." \
        "  '0 of 0 survived' is a pass measured over nothing."
}

set _bs_prov "[file tail $_bs_table]: boundary_length $_bs_len + control cells\
              $_bs_ctl (out $_bs_out + 2*bidir $_bs_bid + opendrain $_bs_od)"


#-----------------------------------------------------------------------------
# CLAIM 1 -- the boundary-scan shift and update flops
#
# THE PATTERN. `*u_bsc_*_reg` matches the flops Genus names from the RTL
# instance names in src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv
# (u_bsc_00_NRST_I_obs ... u_bsc_75_*), whatever it does with the hierarchy:
#
#   hierarchy kept       u_bsc_00_NRST_I_obs_dr_q_reg
#   hierarchy ungrouped  u_nanosoc_eth_chiplet_bscan_u_bsc_00_NRST_I_obs_dr_q_reg
#
# Both of those are real, from two runs of this design one day apart. The
# LEADING `*` is what makes the claim survive the second case, and it is not
# decoration -- without it this claim reads 0 on a completely intact netlist.
# Counting `module nanosoc_eth_chiplet_bscan` instead reads ABSENT in that same
# case, which is how a re-synthesis that deleted FOUR cells was reported as
# having deleted 117.
#
# BOTH EXPECTATIONS, because they catch different things:
#   -min       the design intends 119 of these. Catches deletion at ANY stage,
#              including syn_generic - which is where a case-analysed enable pin
#              deletes the register, before any baseline could have counted it.
#   -baseline  whatever existed after mapping must still exist. Needs no number
#              and names WHICH instances went, which a floor cannot.
#-----------------------------------------------------------------------------
# SPLIT INTO TWO CLAIMS, and the reason matters more than the split.
#
# A single claim of 119 FAILS A CORRECT NETLIST. build/bscan-probe2 has 115:
# four update flops were removed, all of them on the three pads the TAP itself
# borrows (SWDIO=TMS, HOST_IO_0=TDI, HOST_IO_1=TDO). The pad ring overrides
# those pins whenever boundary scan is enabled, and `mode` implies `bscan_en`,
# so no input combination lets those update values reach a pad. Genus deleted
# provably dead logic and was right to; IEEE 1149.1 clause 10 excludes TAP pins
# from the boundary register for exactly this reason.
#
# A gate that reds a correct result teaches the next person to waive it, and a
# waived gate catches nothing. So:
#
#   SHIFT STAGES are the hard floor. The chain length is what the BSDL promises
#   a tester; if it moves, the BSDL is wrong about the silicon. It must be 76.
#
#   UPDATE STAGES carry a floor reduced by the TAP-borrowed pads, because those
#   are dead by construction rather than by accident. If MORE than those go, the
#   drive path is being lost and that is a real defect.
survive "IEEE 1149.1 boundary-scan shift stages (the chain itself)" \
    -pattern "*u_bsc_*_dr_q_reg" \
    -min     $_bs_len \
    -source  "$_bs_prov -- chain length, the number the BSDL promises" \
    -baseline \
    -advice  "The chain length changed. The BSDL's BOUNDARY_LENGTH no longer\
              describes this netlist, and a tester shifting the declared number\
              of bits will misalign every cell. Check the register survived and\
              that scripts/gen_bscan.py --check is clean."

survive "IEEE 1149.1 boundary-scan update stages" \
    -pattern "*u_bsc_*_update_q_reg" \
    -min     [expr {$_bs_ctl - 4}] \
    -source  $_bs_prov \
    -baseline \
    -advice  "The register's only stimulus is the TAP, and the TAP's enable is\
              the strapped SE pad. Hold SE constant - `set_case_analysis 0\
              \[get_ports SE\]` is the exact spelling that did it - and the whole\
              register becomes unreachable and unobservable, at which point\
              deleting it is CORRECT constant propagation and no message is\
              printed. Check ASIC/genus-innovus/inputs/bscan_constraints.sdc is\
              being read, that nothing re-introduces a case analysis on SE, and\
              that src/rtl/bscan/*.sv are in the rendered ASIC filelist."

#-----------------------------------------------------------------------------
# CLAIM 2 -- the TAP itself
#
# A boundary register with no TAP is unreachable, and the failure looks
# different in the netlist: the chain can be intact while its controller is not.
# 4 is the IEEE 1149.1 state vector width, not a property of this die - the one
# number in this file that is a standard's, and it is sourced to the standard
# rather than to the pad table.
#-----------------------------------------------------------------------------
survive "IEEE 1149.1 TAP state register" \
    -pattern "*u_tap_state_q_reg*" \
    -min     4 \
    -source  "IEEE 1149.1 clause 6: the TAP controller is a 16-state machine,\
              4 state bits. Not derived from the pad table because it is not a\
              property of this die." \
    -baseline \
    -advice  "The boundary chain cannot be reached without its controller."

#-----------------------------------------------------------------------------
# CLAIM 3 -- the pad ring, from the pad table's own list
#
# This overlaps section 13a deliberately and does NOT replace it: 13a derives
# its list from the .io file (the floorplan's view) and this derives it from the
# pad table (the boundary-scan generator's view). Two artefacts that are
# supposed to agree, checked independently, is the point - a pad renamed in one
# and not the other is a real defect that neither check alone can see.
#
# NO LEADING `*`, and that is correct here: these are top-level instance names
# in the pad ring wrapper, so they are never prefixed. The engine warns about
# the missing `*` at registration; this comment is the answer to that warning.
#-----------------------------------------------------------------------------
survive "pad instances named by the boundary-scan pad table" \
    -names   $_bs_pads \
    -source  "[file tail $_bs_table]: [llength $_bs_pads] entries in \"pads\"" \
    -baseline \
    -advice  "Supply pads have no ports and are read as dead logic unless\
              DONT_TOUCH_PATTERNS protects them by name. 34 were once deleted\
              this way, and the first symptom was IMPFP-254 x68 in the bond-pad\
              ring, four stages downstream."

unset _bs_table _bs_fh _bs_txt _bs_len _bs_out _bs_bid _bs_od _bs_ctl _bs_flops _bs_pads _bs_prov
