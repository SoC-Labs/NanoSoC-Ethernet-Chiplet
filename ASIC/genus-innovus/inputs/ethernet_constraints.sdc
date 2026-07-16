#-----------------------------------------------------------------------------
#### ETHERNET (RMII) CLOCK DOMAINS + CDC CONSTRAINTS
#-----------------------------------------------------------------------------
# Before this block the entire ethernet clock tree was UNDEFINED in Genus, so
# every eth clock-domain-crossing (CDC) synchroniser was either unclocked or
# timed against the wrong launch clock. This section (a) creates the RMII ref
# clock + its two internally-generated MII clocks and (b) constrains the
# RMII/MII <-> system-clock (CLK) crossings.
#
# Topology  (nanosoc_chip_pads -> u_nanosoc_multicore_soc -> u_network_core):
#   RMII_REF_CLK pad -> soc_rmii_ref_clk -> u_network_core/u_rmii_to_mii, which
#   toggles the mrx_clk / mtx_clk registers every REFCLK edge => two 25 MHz MII
#   clocks (REFCLK/2). The MAC (u_ethmac_0/u_inner/u_eth_top), the RX checksum
#   snoop (u_ethmac_0/u_inner/u_eth_rx_cksum) and the PTP event detectors
#   (u_ethmac_0/u_inner/u_rx_ptp_det, u_tx_ptp_det) all run in the MII domain;
#   their register/CLK sides run in the CLK (system HCLK) domain.

set RMII_REF_PERIOD 20.0 ; # 50 MHz RMII reference (100BASE-TX); MII = REFCLK/2 = 25 MHz
set ETH_SS   "u_nanosoc_eth_chiplet_chip/u_soc/u_soc/u_network_core"
set RMII2MII "${ETH_SS}/u_rmii_to_mii"
set CKSUM    "${ETH_SS}/u_ethmac_0/u_inner/u_eth_rx_cksum"

create_clock -name "rmii_ref_clk" -period "$RMII_REF_PERIOD" -waveform "0 [expr $RMII_REF_PERIOD/2]" [get_ports RMII_REF_CLK]
set_clock_uncertainty $CLK_ERROR [get_clocks rmii_ref_clk]

# 25 MHz MII TX/RX clocks are generated (divide-by-2) INSIDE u_rmii_to_mii by
# toggling the mrx_clk / mtx_clk output registers -> declare them as generated
# clocks so CTS / timing see the real internal domain.
create_generated_clock -name "mii_rx_clk" -source [get_ports RMII_REF_CLK] -divide_by 2 [get_pins ${RMII2MII}/mrx_clk]
create_generated_clock -name "mii_tx_clk" -source [get_ports RMII_REF_CLK] -divide_by 2 [get_pins ${RMII2MII}/mtx_clk]

# RMII is source-synchronous to REFCLK at the pads. Conservative bring-up budget
# (tune for signoff); constrains the otherwise-floating RMII data pins.
set_input_delay  -min 2 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_RXD[*] RMII_CRS_DV}]
set_input_delay  -max 8 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_RXD[*] RMII_CRS_DV}]
set_output_delay -min 2 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_TXD[*] RMII_TX_EN}]
set_output_delay -max 8 -clock [get_clocks rmii_ref_clk] [get_ports {RMII_TXD[*] RMII_TX_EN}]

### CDC 1 — wholly-asynchronous directions (RMII/MII family <-> CLK)
# The RMII ref clock and its two /2 children are MUTUALLY SYNCHRONOUS (one
# source) and stay timed relative to each other (rmii_ref->mii_rx carries the
# real mrxd/mrxdv datapath; mii_rx<->mii_tx are synchronous siblings). They are
# asynchronous to CLK. Two of the three cross-domain directions carry NO path we
# need to keep timed, so cut them wholesale by clock (robust, name-free):
#   * CLK -> family  : every system-side control synchroniser first stage
#     (eth_rx_cksum ctrl_en/ctrl_mode/rptr_gray syncs; OpenCores MAC WB->MRx/MTx
#     syncs e.g. RxAbortSyncb / WriteRxDataToFifoSync / TxStartFrm_sync).
#   * {ref,mii_tx} -> CLK : every TX/ref-side crossing (OpenCores MAC TX status
#     + TX-FIFO syncs TxRetrySync/TxAbortSync/TxDoneSync/ReadTxDataFromFifo_sync,
#     and the u_tx_ptp_det TX event strobe -> PHC).
# The mii_rx -> CLK direction is deliberately LEFT TIMED here because it carries
# the eth_rx_cksum last_push_flags data-with-toggle path we want to keep as a
# (relaxed) multicycle — see CDC 3. Its correctly-synchronised crossings are cut
# individually in CDC 2. (CLK<->SWDCLK is intentionally NOT grouped so the
# existing SWD multicycle/false-path block above is preserved.)
set_false_path -from [get_clocks clk] -to [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}]
set_false_path -from [get_clocks {rmii_ref_clk mii_tx_clk}] -to [get_clocks clk]

### CDC 2 — mii_rx -> CLK correctly-synchronised crossings (targeted false paths)
# Cut ONLY the metastability-capture flops so the last_push_flags MCP (CDC 3)
# survives on the same clock pair. eth_rx_cksum (exact paths, RTL-verified):
set_false_path -to [get_pins ${CKSUM}/wptr_gray_pclk_s0_reg[*]/D] ; # gray write-pointer sync (async FIFO)
set_false_path -to [get_pins ${CKSUM}/ovf_tog_pclk_s0_reg/D]      ; # overflow toggle synchroniser
set_false_path -to [get_pins ${CKSUM}/push_tog_pclk_s0_reg/D]     ; # push  toggle synchroniser
set_false_path -from [get_cells ${CKSUM}/fifo_mem_reg*] -to [get_clocks clk] ; # async FIFO memory read (mrx write -> pclk peek/prdata)
# OpenCores MAC (u_eth_top) MRxClk->WB(CLK) crossings + PTP RX event. Leaf names
# are RTL-verified; deep hierarchy is matched with -hierarchical (confirm the
# set is complete post-elaboration — see review note):
set_false_path -to [get_cells -hierarchical -filter {name =~ *RxAbortSync1_reg}]               ; # RX abort MRx->WB sync
set_false_path -to [get_cells -hierarchical -filter {name =~ *RxStatusWriteLatched_sync1_reg}] ; # RX status/frame-done MRx->WB sync
set_false_path -from [get_cells -hierarchical -filter {name =~ *RxDataLatched2_reg*}] -to [get_clocks clk] ; # RX data (MRx) -> bd_ram (WB), gated by the synced write enable
set_false_path -from [get_cells ${ETH_SS}/u_ethmac_0/u_inner/u_rx_ptp_det/ptp_event_reg] -to [get_clocks clk] ; # eth_rx_ptp_event (mii_rx) -> PHC eth_rx_capture (CLK)

### CDC 3 — eth_rx_cksum last_push_flags data-with-toggle (MULTICYCLE, not cut)
# last_push_flags_mrx[7:0] is latched in mii_rx_clk on the SAME edge that flips
# push_tog_mrx; the CLK-side counters read it only AFTER push_tog resynchronises
# through push_tog_pclk_s0/s1/s2 (edge = s1^s2), i.e. >= 2 CLK cycles later. It
# is a REAL data path (the flags are consumed) whose setup may be relaxed to 2
# destination cycles — a set_multicycle_path, NOT a false path. last_push_flags
# fans out ONLY to the five CLK-domain counters (frame_count_q / ip_good_q /
# ip_bad_q / l4_good_q / l4_bad_q), so "-to CLK" targets exactly this crossing.
# Multiplier 2/1 mirrors the toggle's >=2-cycle handshake and the SWDCK->CLK
# idiom above (-end = relax on the capturing CLK).
set_multicycle_path 2 -setup -end -from [get_cells ${CKSUM}/last_push_flags_mrx_reg[*]] -to [get_clocks clk]
set_multicycle_path 1 -hold  -end -from [get_cells ${CKSUM}/last_push_flags_mrx_reg[*]] -to [get_clocks clk]

# NOTE (max-robustness alternative): if a name-free, guaranteed-complete cut of
# the mii_rx->CLK boundary is preferred over the verified last_push_flags MCP,
# replace CDC 2+3 with a single async clock group and drop the -to clk direction
# from CDC 1:
#   set_clock_groups -asynchronous \
#     -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] -group [get_clocks clk]
# That is safe (last_push_flags is held stable for a whole frame vs a ~2-cycle
# toggle resync) but converts last_push_flags from a timed MCP into a false path.

