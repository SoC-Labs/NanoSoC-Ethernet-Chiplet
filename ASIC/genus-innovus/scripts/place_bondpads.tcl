## Filler insertion — moved here from route_setup.tcl.
## place_bondpads.tcl is sourced by 4_pnr_route.tcl AFTER route_design and
## opt_design -post_route -hold, which is where filler belongs: the rows have
## stopped changing, so -check_drc/-fix_drc has real routing to check and the
## ANTENNA diodes see real antennas. Sourced before the bond pads themselves,
## which sit on M8/M9/AP and do not compete for core rows.
##
## 2026-08-06: filler.tcl now also runs `check_drc` and `route_eco -target`
## after inserting, because inserting was all it did. The premise of the
## paragraph above — that -check_drc/-fix_drc "has real routing to check" — was
## only half true: -check_drc did check routing, but -fix_drc needs a marker
## database, and the flow's only check_drc runs later in 4_pnr_route.tcl, after
## this file has returned. So the -fix_drc pass was inert on both the 2026-08-05
## and 2026-08-06 runs (IMPSP-9082, once per run) and nothing ever performed the
## post-route reroute the tool asks for (IMPSP-5217, once per add_fillers call).
## The ordering above is unchanged and still correct; the repair now happens
## inside it. Details, message text and the one violation this demonstrably
## leaves behind are in filler.tcl's header.
##
## THE `source` BELOW MUST STAY WHERE IT IS, i.e. before the bond pads are
## created. filler.tcl's new check_drc marks the violations that its -fix_drc
## and route_eco -target passes then act on, and running it here means those
## markers describe the CORE only. Move this source below the pad loops and the
## marker set also carries every M8/M9/AP pad-ring violation — the class that
## was 376 of 379 shorts in the 2026-08-05 baseline — and the filler repair
## would be handed a database dominated by geometry it cannot touch. The pads
## are still checked: 4_pnr_route.tcl's check_drc runs after everything and is
## the signoff report.
source ../scripts/filler.tcl

set top_pads_outer [list \
uPAD_VDDIO_T_0 \
uPAD_VSS_T_0 \
uPAD_SWDCK_I \
uPAD_TEST_I \
uPAD_VDD_T_1 \
uPAD_VSS_T_1 \
uPAD_VDDIO_T_2 \
uPAD_VSSIO_T_1 \
uPAD_VSSIO_T_2 \
]

set top_pads_inner [list \
uPAD_VDD_T_0 \
uPAD_NRST_I \
uPAD_CLK_I \
uPAD_SE_I \
uPAD_SWDIO_IO \
uPAD_VDDIO_T_1 \
uPAD_VSSIO_T_0 \
uPAD_VDD_T_2 \
]

set left_pads_outer [list \
uPAD_TL_RX_0 \
uPAD_TL_RX_2 \
uPAD_VDDIO_L_0 \
uPAD_TL_CLK_RX \
uPAD_TL_RX_5 \
uPAD_TL_RX_7 \
uPAD_I2C_SDA \
uPAD_VSSIO_L_1 \
uPAD_TL_TX_1 \
uPAD_TL_TX_3 \
uPAD_VSSIO_L_2 \
uPAD_TL_TX_4 \
uPAD_TL_TX_6 \
]
set left_pads_inner [list \
uPAD_TL_RX_1 \
uPAD_TL_RX_3 \
uPAD_VSSIO_L_0 \
uPAD_TL_RX_4 \
uPAD_TL_RX_6 \
uPAD_I2C_SCL \
uPAD_VDDIO_L_1 \
uPAD_TL_TX_0 \
uPAD_TL_TX_2 \
uPAD_VDDIO_L_2 \
uPAD_TL_CLK_TX \
uPAD_TL_TX_5 \
uPAD_TL_TX_7 \
]



set bottom_pads_outer [list \
uPAD_VDDIO_B_0 \
uPAD_VDD_B_1 \
uPAD_QSPI_IO_0 \
uPAD_QSPI_IO_2 \
uPAD_VSSIO_B_1 \
uPAD_QSPI_SCLK \
uPAD_VDD_B_0 \
uPAD_VDD_B_2 \
uPAD_VDDIO_B_2 \
]

set bottom_pads_inner [list \
uPAD_VSSIO_B_0 \
uPAD_VSS_B_0 \
uPAD_QSPI_IO_1 \
uPAD_VDDIO_B_1 \
uPAD_QSPI_IO_3 \
uPAD_QSPI_nCS \
uPAD_VSSIO_B_2 \
uPAD_VSS_B_1 \
]

set right_pads_outer [list \
uPAD_VDDIO_R_0 \
uPAD_RMII_MDC \
uPAD_RMII_RXD0 \
uPAD_VSSIO_R_1 \
uPAD_RMII_TXD0 \
uPAD_RMII_TX_EN \
uPAD_RMII_CRS_DV \
uPAD_VSSIO_R_2 \
uPAD_HOST_IO_1 \
uPAD_HOST_IO_3 \
uPAD_HOST_IO_5 \
]

set right_pads_inner [list \
uPAD_VSSIO_R_0 \
uPAD_RMII_REF_CLK \
uPAD_VDDIO_R_1 \
uPAD_RMII_RXD1 \
uPAD_RMII_TXD1 \
uPAD_RMII_MDIO \
uPAD_VDDIO_R_2 \
uPAD_HOST_IO_0 \
uPAD_HOST_IO_2 \
uPAD_HOST_IO_4 \
uPAD_HOST_IO_6 \
]


foreach pads $left_pads_outer {
    create_inst -cell PAD70GU -inst B$pads -ori R270
    create_relative_floorplan -place B$pads -orient R270  -ref_type object -ref $pads -horizontal_edge_separate {0  -2.5  0} -vertical_edge_separate {0  0  0}
} 

foreach pads $left_pads_inner {
    create_inst -cell PAD70NU -inst B$pads -ori R270
    create_relative_floorplan -place B$pads -orient R270  -ref_type object -ref $pads -horizontal_edge_separate {0  -2.5  0} -vertical_edge_separate {0  0  0}
} 

foreach pads $top_pads_outer {
    create_inst -cell PAD70GU -inst B$pads -ori R180
    create_relative_floorplan -place B$pads -orient R180  -ref_type object -ref $pads -horizontal_edge_separate {1  0  1} -vertical_edge_separate {2  2.5  2}
} 

foreach pads $top_pads_inner {
    create_inst -cell PAD70NU -inst B$pads -ori R180
    create_relative_floorplan -place B$pads -orient R180  -ref_type object -ref $pads -horizontal_edge_separate {1  0  1} -vertical_edge_separate {2  2.5  2}
} 

foreach pads $bottom_pads_outer {
    create_inst -cell PAD70GU -inst B$pads -ori R0
    create_relative_floorplan -place B$pads -orient R0  -ref_type object -ref $pads -horizontal_edge_separate {0  0  0} -vertical_edge_separate {0  -2.5  0}
} 

foreach pads $bottom_pads_inner {
    create_inst -cell PAD70NU -inst B$pads -ori R0
    create_relative_floorplan -place B$pads -orient R0  -ref_type object -ref $pads -horizontal_edge_separate {0  0  0} -vertical_edge_separate {0  -2.5  0}
} 

foreach pads $right_pads_outer {
    create_inst -cell PAD70GU -inst B$pads -ori R90
    create_relative_floorplan -place B$pads -orient R90  -ref_type object -ref $pads -horizontal_edge_separate {1 2.5 1} -vertical_edge_separate {2 0 2}
} 

foreach pads $right_pads_inner {
    create_inst -cell PAD70NU -inst B$pads -ori R90
    create_relative_floorplan -place B$pads -orient R90  -ref_type object -ref $pads -horizontal_edge_separate {1 2.5 1} -vertical_edge_separate {2 0 2}
} 
