//-----------------------------------------------------------------------------
// Nanosoc CPU Instruction Memory Region (IMEM) — LOCAL OVERRIDE
//
// Local copy of
//   nanosoc-multicore-system/nanosoc_arch_tech/rtl/src/regions/imem/nanosoc_region_imem.v
// read IN PLACE of the upstream file by the eth-chiplet Vivado filelist
// (tidelink/fpga/vivado_ip/nanosoc_eth_chiplet_filelist.tcl). The upstream file is
// UNTOUCHED and must stay so. Module name, ports and parameters are byte-identical
// to upstream, so this is a drop-in.
//
// WHY THIS OVERRIDE EXISTS
// ------------------------
// Upstream selects ROM-vs-SRAM with a FILE-GLOBAL `ifdef RAM_PRELOAD, which flips
// EVERY nanosoc_region_imem instance at once. The eth-chiplet SoC has TWO:
//   * eth-ss / network_core (CPU0) IMEM @ 0x10000000  (ethernet_ss_ahb_rmii.sv)
//       -> needs a REAL preload image (ETH_IMEM_MEM_FPGA_IMG = the alive app hex)
//   * chip_core (CPU1) IMEM (nanosoc_ss_cpu_plus.sv)
//       -> keeps the DEFAULT placeholder MEM_FPGA_IMG = "image.hex"
// A global RAM_PRELOAD makes the CPU1 IMEM a ROM with no hex, so its $readmemh
// falls back to the nonexistent 'image.hex' -> Synth 8-4445 CRITICAL WARNING ->
// the TideLink message gate fails the build.
//
// This copy makes the ROM choice PER-INSTANCE, keyed on whether a real image was
// supplied: a region is a preload BRAM (ROM) only when MEM_FPGA_IMG differs from
// the "image.hex" default, otherwise it stays a writable SRAM exactly as upstream.
//   * CPU0 IMEM  (MEM_FPGA_IMG = ".../eth_imem_alive.hex") -> sl_ahb_rom (BRAM
//                 initialised via $readmemh through sl_fpga_rom_word)
//   * CPU1 IMEM  (MEM_FPGA_IMG = "image.hex")              -> sl_ahb_sram
//   * DMEM and other regions                               -> unaffected; they
//                 instantiate nanosoc_region_dmem, not this module
// No new parameter is threaded through the SoC hierarchy — MEM_FPGA_IMG already
// distinguishes the instances.
//
// sl_ahb_rom.v carries `define RAM_PRELOAD, baked in-body by the same filelist, so
// it selects the Vivado-synth-friendly sl_fpga_rom_word over the FPGA-zeroing
// cmsdk_fpga_rom. That define matters only where sl_ahb_rom is instantiated, i.e.
// the ROM branch below, i.e. CPU0 IMEM only.
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
// Copyright 2021-6, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------

module nanosoc_region_imem #(
    parameter    SYS_ADDR_W    = 32,          // System Address Width
    parameter    SYS_DATA_W    = 32,          // System Data Width
    parameter    RAM_ADDR_W    = 14,          // Width of RAM Address - Default 16KB
    parameter    RAM_DATA_W    = 32,          // Width of RAM Data Bus - Default 32 bits
    parameter    MEM_FPGA_IMG  = "image.hex"  // Image to Preload into ROM - FPGA only
)(
    input  wire                   HCLK,
    input  wire                   HRESETn,

    // AHB connection to Initiator
    input  wire                   HSEL,
    input  wire  [SYS_ADDR_W-1:0] HADDR,
    input  wire             [1:0] HTRANS,
    input  wire             [2:0] HSIZE,
    input  wire             [3:0] HPROT,
    input  wire                   HWRITE,
    input  wire                   HREADY,
    input  wire  [SYS_DATA_W-1:0] HWDATA,

    output wire                   HREADYOUT,
    output wire                   HRESP,
    output wire  [SYS_DATA_W-1:0] HRDATA
);

    generate
    if (MEM_FPGA_IMG != "image.hex") begin : g_preload_rom
        // A real preload image was supplied -> instantiate the preload BRAM
        // (initialised from MEM_FPGA_IMG at elaboration via $readmemh).
        sl_ahb_rom #(
            .SYS_DATA_W (SYS_DATA_W),
            .RAM_ADDR_W (RAM_ADDR_W),
            .RAM_DATA_W (RAM_DATA_W),
            .FILENAME   (MEM_FPGA_IMG)
        ) u_mem (
            // AHB Inputs
            .HCLK       (HCLK),
            .HRESETn    (HRESETn),
            .HSEL       (HSEL),
            .HADDR      (HADDR [RAM_ADDR_W-1:0]),
            .HTRANS     (HTRANS),
            .HSIZE      (HSIZE),
            .HWRITE     (HWRITE),
            .HWDATA     (HWDATA),
            .HREADY     (HREADY),

            // AHB Outputs
            .HREADYOUT  (HREADYOUT),
            .HRDATA     (HRDATA),
            .HRESP      (HRESP)
        );
    end else begin : g_sram
        // No image (placeholder default) -> writable SRAM, exactly as upstream's
        // `else` branch. Reset does not clear RAM contents.
        sl_ahb_sram #(
            .SYS_DATA_W (SYS_DATA_W),
            .RAM_ADDR_W (RAM_ADDR_W),
            .RAM_DATA_W (RAM_DATA_W)
        ) u_mem (
            // AHB Inputs
            .HCLK       (HCLK),
            .HRESETn    (HRESETn),
            .HSEL       (HSEL),
            .HADDR      (HADDR [RAM_ADDR_W-1:0]),
            .HTRANS     (HTRANS),
            .HSIZE      (HSIZE),
            .HWRITE     (HWRITE),
            .HWDATA     (HWDATA),
            .HREADY     (HREADY),

            // AHB Outputs
            .HREADYOUT  (HREADYOUT),
            .HRDATA     (HRDATA),
            .HRESP      (HRESP)
        );
    end
    endgenerate

endmodule
