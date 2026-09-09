################################################################################
# fpga/board/kr260-eth-chiplet/board.tcl  --  THE BOARD PACK for kr260-eth-chiplet
#
# The AMD/Xilinx Kria KR260 Robotics Starter Kit: a K26 SOM (XCK26, SFVC784,
# -2LV, commercial) on the KR260 carrier, with the TideLink die-to-die ribbon
# wired to the carrier's Raspberry Pi header.
#
# PCB FACTS ONLY.  Which device is soldered down, what the clock the design is
# closed at runs at, how a .bin has to be formatted for this family's boot ROM,
# which names this bench addresses the board by.  Every one of them would still
# be true for a COMPLETELY DIFFERENT DESIGN on this board, which is the test.
#
# NOT IN HERE: a pin, a port name, a clock name, a module.  Those are facts
# about a design meeting a board and they live with the rest of the target
# collateral - which, for this project, is still
# tidelink/fpga/targets/kr260-eth-chiplet/.  See fpga/README.md.
#
# `make board-probe` loads and validates this file and prints every key it
# resolved.  It launches no tool and takes no licence.  Run it after every edit.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

#### 1. REQUIRED ###############################################################

# Must match the directory this file is in, which is what BOARD selects.
board_set board_name kr260-eth-chiplet

# THE DEVICE, full Vivado part string - device, package, speed grade and
# temperature grade.  -2LV is the LOW-VOLTAGE speed grade the K26 SOM ships
# (core supply 0.698-0.742 V) and it is NOT interchangeable with a -2: a part
# string missing or mis-stating any field resolves to a different device or to
# none, and "none" surfaces as an elaboration failure several minutes in.
#
# design.mk states PART as well and the two must agree.  See fpga/README.md for
# why both currently have to say it.
board_set part xck26-sfvc784-2LV-c

# A bitstream plus the firmware built into it.  The KR260 here runs Ubuntu with
# fpgautil, not a PYNQ overlay image.  Must agree with PLATFORM in design.mk;
# `make check` compares them.
board_set platform bare

# ── THE SYSTEM CLOCK ───────────────────────────────────────────────────────
#
# 25 MHz, and it is NOT pl_clk0.
#
# PS8 pl_clk0 is 100 MHz nominal - 99.999 MHz on the pin, which the block
# design reads back and re-states as clk_wiz PRIM_IN_FREQ to avoid BD 41-238.
# clk_wiz_0 clk_out1 is 25 MHz and that is sys_fclk: the clock the SoC, the AHB
# fabric and the PHC all run on, and the clock the forwarded PHY output is
# derived from `-divide_by 8`.
#
# This number is compiled into the firmware AND constrains the fabric.  A build
# where those two disagree BOOTS, and every baud rate and every timer is wrong
# by the ratio - here that would be a factor of four, and the symptom would
# read as a UART wiring fault.
board_set sys_clk_freq_hz 25000000

# ── HOW A .bin IS MADE FOR THIS FAMILY ─────────────────────────────────────
#
# zynqmp: the .bit HEADER IS STRIPPED and nothing else.
#
# zynq7 - header strip AND payload byte-swap - is the OTHER one, and the two
# are not interchangeable.  This project keeps two separate converters for
# exactly this reason and its Makefile says in as many words that the zynq7
# converter MUST NOT be used on ZynqMP: its byte-swap is the zynq-fpga driver's
# format, not fpgautil's.
#
# Get it wrong and the conversion succeeds, the file is the right size,
# fpgautil accepts it, and the PL does not come up.  Nothing in the chain says
# why.  There is no defensible default and guessing it from the part string is
# the kind of inference that is right until the day it is not.
board_set bin_style zynqmp


#### 2. CONDITIONAL ############################################################

# ── THE VENDOR BOARD FILE ──────────────────────────────────────────────────
#
# Zynq UltraScale+ targets drive the PS8 / DDR / MIO configuration from the
# board preset, and it must be set on the project BEFORE the block design is
# sourced - otherwise the BD silently mis-presets the PS.
board_set board_part xilinx.com:kr260_som:part0:1.1

# ┌──────────────────────────────────────────────────────────────────────────┐
# │ MEASURED 2026-09-08: THE KRIA BOARD FILES ARE NOT ON THIS HOST.          │
# │                                                                          │
# │   Neither /apps/Xilinx/Vivado/2021.1 nor 2024.1 carries a                │
# │   data/boards/board_files directory at all, and the user's xhub          │
# │   board_store holds TUL/pynq-z2 and nothing else.  The KR260 bitstreams  │
# │   in tidelink/imp/ were therefore built somewhere the files were         │
# │   present, and nothing in the tree records where.                        │
# │                                                                          │
# │   THAT IS THE ENTIRE ARGUMENT FOR THIS KEY.  Without a repository path   │
# │   Vivado resolves the VLNV against whatever board files happen to be     │
# │   installed on the machine running the build - an undeclared dependency  │
# │   that works on one host and fails, or worse silently differs, on the    │
# │   next.  The existing flow depends on it and calls update_board_part_    │
# │   repos to paper over it.                                                │
# │                                                                          │
# │   So it is DEFERRED, not guessed.  board_env records the resolution      │
# │   attempt whether or not it succeeds; if KRIA_BOARD_FILES is unset or    │
# │   does not name a directory, the key stays UNSET WITH A RECORDED REASON  │
# │   - board_has answers 0 and board_get errors naming what it could not    │
# │   read.  It never becomes "", which would concatenate into a plausible   │
# │   wrong path and flow onward.                                           │
# │                                                                          │
# │   TO RESOLVE IT: clone XilinxBoardStore (or install the Kria board       │
# │   files) and export KRIA_BOARD_FILES to the directory that CONTAINS the  │
# │   kr260_som board directory.                                            │
# └──────────────────────────────────────────────────────────────────────────┘
board_defer board_repo_paths {
    set root [board_env KRIA_BOARD_FILES \
        "Kria K26/KR260 Vivado board files - the directory containing kr260_som,\
         e.g. a XilinxBoardStore checkout's .../Vivado/<ver>/boards/Xilinx"]
    # TWO WAYS board_env CAN COME BACK WITHOUT A PATH, and both are handled.
    # An empty string is the ordinary "unset" case; the literal marker
    # <unset:NAME> is what it returns under FPGA_PACK_ALLOW_MISSING_ENV=1,
    # which is the mode `make board-probe` runs in so that it can REPORT a
    # missing site variable instead of dying on the first one.  Testing only
    # for "" would let the marker string flow onward as though it were a path.
    #
    # AND THE MESSAGE INTERPOLATES $root ON PURPOSE. `fpga-flow-part-probe`
    # decides whether to lead with "UNSET SITE VARIABLE(S)" by GREPPING ITS OWN
    # REPORT TEXT for the literal marker <unset:NAME>; it does not ask the
    # pack's env log, which records every attempt and knows the answer.  So a
    # pack that writes a good prose error and drops the marker gets told "NO
    # SITE VARIABLE IS UNSET, so this is not a mount problem" - the opposite of
    # the truth, and it sends the reader away from the one thing that would fix
    # it.  Keeping $root in the string satisfies the grep and loses nothing:
    # naming the variable in the exact form the report uses is informative
    # anyway.  Reported to the toolkit; see fpga/README.md.
    if {$root eq "" || [string match "<unset:*>" $root]} {
        error "KRIA_BOARD_FILES ('$root') is not set, and MEASURED 2026-09-08 no Vivado\
               install on this host carries data/boards/board_files at all\
               (2021.1, 2024.1, 2025.2, 2026.1 all checked; the user xhub\
               board_store holds TUL/pynq-z2 and nothing else). board_part\
               'xilinx.com:kr260_som:part0:1.1' cannot be resolved without it,\
               and resolving it against whatever the host happens to have\
               installed is precisely the undeclared dependency this key\
               exists to prevent. Point KRIA_BOARD_FILES at the directory that\
               CONTAINS kr260_som."
    }
    if {![file isdirectory $root]} {
        error "KRIA_BOARD_FILES='$root' is not a directory."
    }
    return $root
}

# ── THE BENCH ──────────────────────────────────────────────────────────────
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ TWO NAMESPACES. THEY DO NOT OVERLAP.                                     │
# │                                                                          │
# │   kr260_01     board GROUP  - the LEASE scope.  Leases, queues and       │
# │                reservations address this name.                           │
# │   kr260_01_pl  TARGET       - the PROGRAM scope.  Program, reset and     │
# │                actions address this one.                                 │
# │                                                                          │
# │   Using either where the other is expected returns 404, and the 404 does │
# │   not say which of the two you got wrong.                                │
# │                                                                          │
# │   ON THIS BENCH THE DISTINCTION IS PHYSICAL, not bookkeeping: the KR260  │
# │   carries more than one target-namespace member - the PL, and the PS     │
# │   reached over the bench switch - under one leasable board group.  A     │
# │   board group cannot stand in for a target here even by accident.        │
# └──────────────────────────────────────────────────────────────────────────┘
board_set fpgahub_board  kr260_01
board_set fpgahub_target kr260_01_pl


#### 3. OPTIONAL ###############################################################
#
# Set what is true.  Keys not set below are UNSET DELIBERATELY: reading one is
# an error that names the key, which is a better outcome than reading a guess.

# The PL is loaded over fpgahub, which runs fpgautil on the board against a
# header-stripped .bin.  JTAG exists on the board and is not how this bench
# programs it.
board_set deploy_style jtag

# ── oscillator_hz IS NOT SET, AND THE ABSENCE IS THE HONEST ANSWER ─────────
#
# The K26 SOM's PS reference crystal has not been read off a schematic by
# anyone here, and this design does not use a PL-side free-running oscillator
# at all: every clock in it descends from PS8 pl_clk0, which is a PS PLL output
# and not a crystal.  Writing the PS reference frequency here from memory would
# put a number in a manifest that nothing measured and that a reader would
# reasonably compare against sys_clk_freq_hz to check the MMCM ratio - a ratio
# that would then be wrong, because the MMCM's input is pl_clk0 and not the
# crystal.
#
# What IS known is recorded as a note below, where it cannot be mistaken for a
# measured key.

# io_voltage_by_bank IS NOT SET.  The bank the TideLink ribbon lands in (44) is
# known and recorded in the note below; the SUPPLY VOLTAGE the carrier provides
# to each bank has not been read off the KR260 schematic.  A guessed voltage
# here would defeat the whole purpose of the key, which is to catch an XDC
# IOSTANDARD the board cannot actually supply.

# connectors: what is wired where, for humans.  This is the note that stops the
# next person tracing a ribbon with a multimeter.
#
# ONE LINE, DELIBERATELY.  `fpga-flow-part-get` documents its output as
# manifest-shaped `<key> <value>` LINES so a caller can parse it with `read`,
# and a value carrying an embedded newline breaks that for every key after it.
# A list key is allowed to be long; it is not allowed to be multi-line.  Detail
# that needs paragraphs goes in a board_note, which the summary reflows.
board_set connectors {rpi_header "TideLink d2d ribbon: 8 data lanes + forwarded clock, HDIO bank 44" som_eth "K26 SOM gigabit ethernet, PS-side, over the bench switch - NOT the eth chiplet MAC" usb_uart "console"}


#### 4. NOTES ##################################################################
#
# Recorded in the run manifest, so a bitstream built for this board carries
# these with it.

board_note {BANK 44 IS HIGH-DENSITY AND HAS NO IDELAY. The TideLink ribbon
            lands in HDIO bank 44, and on xck26 banks 43/44/45 are
            BT_HIGH_DENSITY - HD banks carry no IDELAY/ISERDES IO logic at all,
            which lives in the HP banks (64/65/66) inside RXTX_BITSLICE. A
            design that assigns this interface to bank 44 and then asks for an
            IDELAY does not get one. This is why FPGA_USE_IDELAY is 0 for every
            build on this board, and it is a BOARD fact (where the ribbon
            lands) reached through a PART fact (what that bank is), which is
            why it is written down on this side of the split.}

board_note {THIS DESIGN HAS NO PL-SIDE OSCILLATOR. Every clock descends from
            PS8 pl_clk0, configured at 100 MHz and measured at 99.999 MHz on
            the pin - the block design reads the pin's FREQ_HZ back and
            re-states clk_wiz PRIM_IN_FREQ from it, because leaving it at a
            round 100.000 raises BD 41-238. sys_clk_freq_hz (25 MHz) is
            clk_wiz clk_out1. oscillator_hz is deliberately unset: see
            section 3.}

board_note {THE KRIA BOARD FILES ARE ON THIS HOST, BUNDLED IN THE VIVADO INSTALL. Measured 2026-09-08 at /apps/Xilinx/Vivado/2024.1/data/xhub/boards/XilinxBoardStore/boards/Xilinx/kr260_som (revisions 1.0 and 1.1). An earlier note here said they were absent; that was measured against the USER xhub board_store, which holds only TUL/pynq-z2, and missed the store Vivado ships inside its own data directory. Not in 2021.1. board_repo_paths is still DEFERRED rather than defaulted, because a path inside one Vivado version's install is a site fact and CONTRACT section 8 forbids defaulting one - but the value to export is now known: KRIA_BOARD_FILES=/apps/Xilinx/Vivado/2024.1/data/xhub/boards/XilinxBoardStore/boards/Xilinx. With it set, board-probe exits 0. Note also that the legacy flow does not need it at all: build_design.tcl:213 calls xhub::refresh_catalog and fetches the board files from the Xilinx board store on demand.}

board_note {cfgbvs / config_voltage ARE NOT STATED HERE, BUT NOW COULD BE. An earlier note said the schema made it impossible: CONTRACT section 8 called them board keys while part/pack_api.tcl still carried them in the PART schema and in neither board table, so - unknown keys being fatal - nothing could state them at all. That was fixed on 2026-09-08 and both are now board keys. They are still unset here because nobody has read how config bank 0 is wired on this carrier; stating a guess would be worse than the CFGBVS-1 warning it would silence. Set them once the carrier is checked.}

board_note {BOARD REVISION IS NOT RECORDED. The schema has a board_rev key and
            this pack does not set it, because nobody has read the revision off
            the two KR260s on this bench. If the two carriers differ, this pack
            currently describes both and cannot tell them apart.}

# Copyright (C) 2026, SoC Labs (www.soclabs.org)
