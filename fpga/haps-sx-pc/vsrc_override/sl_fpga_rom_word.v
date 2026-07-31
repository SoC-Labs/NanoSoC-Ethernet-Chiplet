//-----------------------------------------------------------------------------
// SoCLabs Vivado-friendly FPGA preloaded BRAM (word-format $readmemh).
//
// Despite the "rom" in the filename this is actually a writable BRAM whose
// initial content is supplied by a word-format $readmemh hex file — i.e.
// a "preload" SRAM, not a true ROM. Keeping the file name avoids churn
// in the rest of the IP filelists; the module was previously strictly-
// read-only, which made SWD-driven firmware hot-flash impossible:
//   - The write port (WDATA / WREN) was tied off internally.
//   - `mww` from OpenOCD appeared to succeed on readback but left the
//     BRAM content unchanged (cmsdk_ahb_to_sram drove WEN correctly,
//     but the BRAM ignored it).
//   - Every SYSRESETREQ reverted IMEM to the baked image, and
//     firmware iteration required a full Vivado rebuild.
//
// Writable preload fixes all three: the $readmemh initial content
// provides a bootable firmware out of the bitstream, and debugger
// writes persist (BRAM cells on 7-series are NOT reset-clearable),
// so an SWD-loaded image survives a SYSRESETREQ and is picked up on
// the next Reset_Handler.
//
// Replaces the ARM cmsdk_fpga_rom — its byte-shuffle for-loop in an
// initial block triggered Vivado's "ignoring non-constant assignment
// in initial block" warning and left BRAM contents zero. This module
// reads a single 32-bit-word-format hex file directly into a 32-bit-
// wide BRAM array (one $readmemh, no loop, no temp).
//
// The companion Python script fpga/scripts/hex_byte_to_word.py converts
// the byte-format hex produced by `arm-none-eabi-objcopy -O verilog` into
// the word-format hex this module expects.
//
// Pin-compatible with the cmsdk_fpga_rom / cmsdk_fpga_sram interface
// used by sl_ahb_rom.v and sl_ahb_sram.v.
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic
// Access license.
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------

module sl_fpga_rom_word #(
    parameter AW       = 16,          // address bits (byte-addressed range)
    parameter filename = "image_word.hex"
)(
    input  wire          CLK,
    input  wire [AW-1:2] ADDR,
    input  wire [31:0]   WDATA,        // AHB write data (byte-strobed via WREN)
    input  wire [3:0]    WREN,         // per-byte write enables
    input  wire          CS,
    output wire [31:0]   RDATA
);

    localparam DEPTH = 1 << (AW - 2);

    // Single-port inferred BRAM with $readmemh preload + per-byte writes.
    // ram_style=block forces BRAM mapping (was previously pinned with
    // rom_style="block" too; rom_style is dropped because we now have
    // a live write port). 7-series BRAM cells retain state across
    // HRESETn, so SWD-written firmware survives a SYSRESETREQ.
    (* ram_style = "block" *)
    reg [31:0] mem [0:DEPTH-1];

    // -----------------------------------------------------------------------
    // LOCAL OVERRIDE for the ProtoCompiler UC (protocompiler100) flow.
    //
    // The upstream sl_fpga_rom_word.v zero-fills `mem` in a loop AND then calls
    // $readmemh in the SAME initial block. Ordinary VCS and Vivado accept that;
    // ProtoCompiler's UC elaboration (VCS with +XTOR_SVS_PROTOCOMPILER_FLOW)
    // rejects it as Error-[MULTI-MEM-INIT-SAME-HIERSIG] "Multiple memory
    // initializations for same hierarchical signal", which aborts UC compile.
    //
    // The zero-fill existed ONLY to keep unwritten cells out of X in
    // SIMULATION. This flow is FPGA synthesis: an inferred BRAM initialises to
    // 0 by construction, so a lone $readmemh is behaviourally identical here —
    // the populated range is loaded, the rest is 0, no X anywhere.
    //
    // This copy is prepended to the UC filelist and the dedup pass drops the
    // submodule's copy (first-wins), so the submodule is NOT modified and the
    // direct-Vivado flow (fpga/haps-sx) still uses the original.
    // -----------------------------------------------------------------------
    initial begin : mem_init
        $readmemh(filename, mem);
    end

    reg [31:0] rdata_r;

    always @(posedge CLK) begin
        if (CS) begin
            // Byte-enable-aware write. Vivado infers a byte-write-enabled
            // BRAM when the per-lane structure is this explicit, which
            // also preserves the $readmemh initial content.
            if (WREN[0]) mem[ADDR][ 7: 0] <= WDATA[ 7: 0];
            if (WREN[1]) mem[ADDR][15: 8] <= WDATA[15: 8];
            if (WREN[2]) mem[ADDR][23:16] <= WDATA[23:16];
            if (WREN[3]) mem[ADDR][31:24] <= WDATA[31:24];
            rdata_r <= mem[ADDR];
        end else begin
            rdata_r <= 32'h0;
        end
    end

    assign RDATA = rdata_r;

endmodule
