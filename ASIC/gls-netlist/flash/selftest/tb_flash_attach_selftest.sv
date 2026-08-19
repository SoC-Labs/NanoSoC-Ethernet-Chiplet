//-----------------------------------------------------------------------------
// tb_flash_attach_selftest.sv - prove the flash attachment before spending an
// hour compiling a 204k-instance gate netlist behind it.
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic
// Access license.
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// This module is deliberately named gls_netlist_tb: that is the module
// gls_flash_attach.sv binds into, and binding into a stand-in with the SAME
// net declarations is what makes this a test of the real attachment rather
// than of a second copy of it.
//
// The declarations below are COPIED FROM GENERATOR OUTPUT, not written by
// hand - `gen_netlist_tb.py --spec <the real spec> --out -` emits
//     wire [3:0] QSPI_IO;  pullup(QSPI_IO[0]); ... pullup(QSPI_IO[3]);
// for a `pullup` entry and a bare `wire QSPI_SCLK;` for a `tiez` entry
// (gen_netlist_tb.py:163-172). If the generator ever changes shape, this
// selftest stops matching it and should be re-derived.
//
// WHAT IT PROVES, in order:
//   1. `bind` inserts the flash into a module the bench does not own, with an
//      INOUT port resolved in that module's scope. (VCS accepts bind+inout.)
//   2. $readmemh reaches u_flash.I0.memory through the bound hierarchy.
//   3. The SST26 model answers a Fast-Read 0x0B + 24-bit address + 8 dummy
//      cycles - the exact command CPU1's ROM programs into AHB_SETUP
//      (0x0000_800B: AHB_CMD[7:0]=0x0B, AHB_DUMMY[15:12]=8; register map at
//      ahb_qspi/uvm/ahb_qspi/env/ahb_qspi_pkg.sv:40) - with the packed bytes.
//   4. The bytes it returns are the boot table flash_pack.py wrote, read back
//      over the wire rather than out of the array by hierarchical reference.
//
// What it does NOT prove: anything about the design. There is no DUT here.
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module gls_netlist_tb;

    // ---- nets in the shape gen_netlist_tb.py emits -------------------------
    wire [3:0] QSPI_IO;
    pullup(QSPI_IO[0]);
    pullup(QSPI_IO[1]);
    pullup(QSPI_IO[2]);
    pullup(QSPI_IO[3]);
    wire QSPI_SCLK;
    wire QSPI_nCS;

    // ---- the stand-in for the chip's QSPI pads -----------------------------
    // In the real bench the DUT drives these three. Here a minimal SPI master
    // does, so the flash is exercised over the actual serial protocol.
    reg sclk_r  = 1'b0;
    reg csn_r   = 1'b1;
    reg mosi_r  = 1'b0;
    reg mosi_oe = 1'b0;

    assign QSPI_SCLK = sclk_r;
    assign QSPI_nCS  = csn_r;
    assign QSPI_IO[0] = mosi_oe ? mosi_r : 1'bz;

    // 40 ns period. The model's specify block sets Fclk (min SCK period) to
    // 9.59 ns for Fast-Read, so this is comfortably legal even with timing
    // checks left ON - which they are here, unlike the GLS run.
    localparam integer HALF_NS = 20;

    integer n_fail = 0;
    integer n_pass = 0;

    task check32(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got === exp) begin
                n_pass = n_pass + 1;
                $display("SELFTEST: PASS %0s = 0x%08h", name, got);
            end else begin
                n_fail = n_fail + 1;
                $display("SELFTEST: FAIL %0s = 0x%08h, expected 0x%08h",
                         name, got, exp);
            end
        end
    endtask

    // ---- bit-level SPI (mode 0) -------------------------------------------
    // Master shifts MOSI out while SCK is low; both sides sample on the rising
    // edge; the flash drives its next MISO bit on the falling edge.
    task sck_bit(input mo, output mi);
        begin
            mosi_r = mo;
            #(HALF_NS);
            sclk_r = 1'b1;
            mi     = QSPI_IO[1];
            #(HALF_NS);
            sclk_r = 1'b0;
        end
    endtask

    task spi_out8(input [7:0] d);
        integer i;
        reg     dummy;
        begin
            for (i = 7; i >= 0; i = i - 1) sck_bit(d[i], dummy);
        end
    endtask

    task spi_in8(output [7:0] d);
        integer i;
        reg     b;
        begin
            d = 8'h00;
            for (i = 7; i >= 0; i = i - 1) begin
                sck_bit(1'b0, b);
                d[i] = b;
            end
        end
    endtask

    // Fast Read 0x0B: opcode, 24-bit address, 8 DUMMY CYCLES, then data.
    task fast_read(input [23:0] addr, input integer nbytes,
                   output [31:0] first_word_le);
        integer i;
        reg [7:0] b;
        reg [7:0] got [0:3];
        begin
            csn_r   = 1'b1; mosi_oe = 1'b1; #(HALF_NS * 2);
            csn_r   = 1'b0; #(HALF_NS);
            spi_out8(8'h0B);
            spi_out8(addr[23:16]);
            spi_out8(addr[15:8]);
            spi_out8(addr[7:0]);
            spi_out8(8'h00);            // 8 dummy cycles
            mosi_oe = 1'b0;             // release: the flash drives now
            for (i = 0; i < nbytes; i = i + 1) begin
                spi_in8(b);
                if (i < 4) got[i] = b;
            end
            #(HALF_NS);
            csn_r = 1'b1;
            #(HALF_NS * 4);
            // little-endian word, the way the CPU reads it
            first_word_le = {got[3], got[2], got[1], got[0]};
        end
    endtask

    // ---- the run -----------------------------------------------------------
    reg [31:0] w;

    initial begin
        // Let the bound instance's initial block pre-fill and $readmemh first.
        #100;

        $display("SELFTEST: reading the packed image back over SPI Fast-Read 0x0B");

        // Boot table header, TABLE0 @ 0. addrmap.h:393 magic 'BOOT'.
        fast_read(24'h000000, 4, w);
        check32("TABLE0 magic      @0x000000", w, 32'h424F4F54);
        fast_read(24'h000004, 4, w);
        check32("TABLE0 version    @0x000004", w, 32'h00000002);
        fast_read(24'h000008, 4, w);
        check32("TABLE0 num_entries@0x000008", w, 32'h00000002);

        // TABLE1, the second sequenced copy. addrmap.h:377.
        fast_read(24'h010000, 4, w);
        check32("TABLE1 magic      @0x010000", w, 32'h424F4F54);

        // Counter sector must read ERASED. addrmap.h:378 + the ROM's
        // boot_counter_read(): a non-0xFF byte here is a consumed attempt.
        fast_read(24'h020000, 4, w);
        check32("counter sector    @0x020000", w, 32'hFFFFFFFF);

        // CPU1's image in slot A - its vector table's initial SP.
        // addrmap.h:379.
        fast_read(24'h030000, 4, w);
        check32("CPU1 image MSP    @0x030000", w, 32'h18000C00);
        fast_read(24'h030004, 4, w);
        check32("CPU1 image rst PC @0x030004", w, 32'h10000189);

        // Golden mini-table. addrmap.h:381.
        fast_read(24'h050000, 4, w);
        check32("GOLDEN magic      @0x050000", w, 32'h424F4F54);

        // CPU0's image, and the link address that says it is a CPU0 build.
        fast_read(24'h060000, 4, w);
        check32("CPU0 image MSP    @0x060000", w, 32'h18003C00);
        fast_read(24'h060004, 4, w);
        check32("CPU0 image rst PC @0x060004", w, 32'h00000189);

        // A region the packer never wrote: must read as ERASED 0xFF, not X.
        // This is the check that catches a missing pre-fill - an X here is
        // what derails the M0+ on the ROM's X-dependent branches.
        fast_read(24'h07F000, 4, w);
        check32("unwritten gap     @0x07F000", w, 32'hFFFFFFFF);

        $display("SELFTEST: %0d passed, %0d failed", n_pass, n_fail);
        if (n_fail == 0) $display("SELFTEST: OVERALL PASS");
        else             $display("SELFTEST: OVERALL FAIL");
        $finish;
    end

endmodule
