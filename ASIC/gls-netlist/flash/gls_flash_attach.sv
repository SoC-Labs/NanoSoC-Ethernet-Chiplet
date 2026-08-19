//-----------------------------------------------------------------------------
// gls_flash_attach.sv - put a real QSPI flash device on the netlist GLS bench.
//
// A joint work commissioned on behalf of SoC Labs, under Arm Academic
// Access license.
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// WHAT PROBLEM THIS SOLVES
//
// Until 2026-08-19 ASIC/gls-netlist/bench/eth_chiplet_fp1505_cc.json said it in
// its own words - the text below is quoted from the force this file retired:
//
//     "This bench models no flash device, so CPU1 never reaches that write and
//      CPU0 never fetches at all (eth_rom_port.accessed=0). Forcing the
//      bootgate proves CPU0'S ROM FETCH PATH ONLY [...] It does NOT prove the
//      CPU1->CPU0 handshake, and a pass here must never be quoted as one."
//
// CPU1's stage-0 (firmware/bootloader/stage0_bootrom_chip_core/main.c) does
// flash I/O before it does anything else - a boot-attempt counter read+program
// in APB command mode, then XiP bring-up, then a boot table, then an image copy
// and a CRC - and only then writes chip_core_remap_ctrl[2]=0x4 to release CPU0.
// With no device on the QSPI pins none of that can complete. This file supplies
// the device, so the handshake can be observed instead of forced.
//
// HOW IT ATTACHES - AND WHY BY `bind`
//
// The bench is GENERATED, not shipped: run_gls_netlist.sh calls
// gen_netlist_tb.py, which writes $RUN/gls_netlist_tb.v from the JSON spec and
// compiles it with `-top gls_netlist_tb`. The spec schema can declare nets,
// tie them, pull them and connect them to the DUT - it cannot instantiate a
// module. Editing the generated file is not an option either; it is rewritten
// on every build.
//
// `bind` is the mechanism SystemVerilog provides for exactly this: it inserts
// an instance INSIDE a module you do not own, with its ports resolved in that
// module's scope. run_gls_netlist.sh already compiles with -sverilog
// (run_gls_netlist.sh:307), so it is available with no toolkit change.
//
// The three nets it binds to must exist in the generated bench. They do, if the
// spec declares them - QSPI_IO is in the shipped spec's `pullup` list, and
// QSPI_SCLK / QSPI_nCS are declared by putting them in `tiez`. That is the
// SHIPPED spec, ../bench/eth_chiplet_fp1505_cc.json; ../Makefile adds this
// file and the vendor model to that item's compile.
//
// Netlist port directions (nanosoc_eth_chiplet_pads_pnr.v, top module):
//     inout  [3:0] QSPI_IO;   output QSPI_SCLK;   output QSPI_nCS;
// so no external tri-state bridge is needed here - unlike the RTL cocotb bench
// (cocotb/soc_boot_flash/tb_top.sv), which sees the SoC's pre-pad
// qspi_io_o/_i/_e vectors and has to rebuild the IOBUF itself. At the pad ring
// the bidirectional net already exists.
//
// TIMING CHECKS ARE OFF, AND THAT IS LOAD-BEARING
//
// SST26VF064B.v corrupts its ENTIRE array to 'x' on any timing violation
// (SST26VF064B.v:225-243, `corrupt_all`). A gate-level QSPI clock that trips
// the model's Fclk/Tsckh specparams would therefore wipe the image mid-boot and
// present as a CRC failure. The GLS runner compiles with `+nospecify
// +notimingcheck` when GLSN_ZERO_DELAY=1, which is the default
// (run_gls_netlist.sh:311-313), so the specify block - and with it corrupt_all -
// is inert. Do NOT run this attachment with GLSN_ZERO_DELAY=0 without first
// confirming the QSPI clock divider keeps SCK slower than Fclk=9.59 ns.
// The same switch removes the model's output path delays, so this is a
// FUNCTIONAL attachment and says nothing about QSPI timing closure.
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module gls_flash_attach #(
    // WHEN the image is written, and this is NOT a tuning knob.
    //
    // The model's power-on-reset block fills its ENTIRE array with 0xFF at
    // time 0 (SST26VF064B.v:1918-1920, inside the "chip por setup" initial).
    // An image written from another time-0 initial block is therefore in a
    // race with it, and loses whenever the model's block is scheduled second -
    // which is what happens here. MEASURED 2026-08-19: with the load at time
    // 0 the array read back correct from the loading block's own $display and
    // then returned 0xFF to every Fast-Read over the wire.
    //
    // The vendor header says so, and the `#1` in its example is the point:
    //     "These bits are initalized at time 0 to the default values. To load
    //      these memorys with customer data load them AFTER time 0"
    //         -- ahb_qspi/verif/VIP/SST26VF064B.v:13-16
    //
    // 1 ns is far ahead of anything the design does: the bench holds reset for
    // 64 reference-clock cycles (spec "resets".cycles), which at the 20 ns
    // CLK period is 1280 ns before the CPU fetches at all.
    parameter integer LOAD_DELAY_NS = 1,
    // Pre-fill span. Belt-and-braces only: the model's POR block above has
    // already filled the whole array with 0xFF by the time this runs, so this
    // re-erases ground that is already erased. It is kept because it is cheap
    // and because it makes the erased-flash precondition explicit rather than
    // inherited from a vendor model's internals.
    parameter integer ERASE_BYTES = 32'h0010_0000,   // 1 MB
    // Default image filename. run_gls_netlist.sh runs simv with the run
    // directory as cwd (run_gls_netlist.sh:378 `cd "$RUN" && ./simv`), and
    // GLSN_STAGE copies each named file into that directory under its
    // BASENAME (run_gls_netlist.sh:235-247) - so a bare relative name resolves.
    parameter string IMAGE_FILE  = "flash_image.hex"
) (
    input  wire       SCK,
    input  wire       CEb,
    inout  wire [3:0] SIO
);

    sst26vf064b u_flash (.SCK(SCK), .SIO(SIO), .CEb(CEb));

    // Same shortened non-volatile op times the ahb_qspi reference bench and
    // cocotb/soc_boot_flash/tb_top.sv use. The CPU1 ROM PAGE-PROGRAMS one
    // counter byte on every boot (boot_counter_increment), and at the model's
    // real Tpp=1.5 ms that single byte would dominate the run.
    defparam u_flash.I0.Tbe  = 1_000;
    defparam u_flash.I0.Tse  = 1_000;
    defparam u_flash.I0.Tsce = 1_000;
    defparam u_flash.I0.Tpp  = 1_000;
    defparam u_flash.I0.Tws  = 1_000;

    string  image_file;
    integer fh;
    integer i;

    initial begin
        // ---- 0. LET THE MODEL POWER UP FIRST -------------------------------
        // Everything below MUST happen after time 0. See LOAD_DELAY_NS.
        #(LOAD_DELAY_NS);

        // ---- 1. ERASED-FLASH POWER-ON STATE --------------------------------
        // Every byte the ROM can reach has to be a DEFINED value: the CPU1 ROM
        // branches on bytes it reads from the counter sector
        // (boot_counter_read: `while (i < 16 && c[i] == 0x00)`) and on the
        // table magic, and an X in either derails an ARMv6-M on an X-dependent
        // branch - which then reads as a design failure rather than a bench
        // one. The model's POR has already done this; doing it again costs
        // nothing and does not depend on that remaining true.
        //
        // NOTE for anyone reading cocotb/soc_boot_flash/tb_top.sv: its comment
        // says this array is "an UNINITIALISED reg ... un-written cells read
        // back as X". That is true of the DECLARATION (SST26VF064B.v:48) and
        // false of the model, which fills the whole array with 0xFF in its POR
        // initial (SST26VF064B.v:1918-1920). Un-written cells read 0xFF.
        for (i = 0; i < ERASE_BYTES; i = i + 1)
            u_flash.I0.memory[i] = 8'hFF;

        // ---- 2. THE IMAGE --------------------------------------------------
        if (!$value$plusargs("flash_image=%s", image_file))
            image_file = IMAGE_FILE;

        // $readmemh on a missing file is a WARNING, not an error: the array
        // would stay uniformly 0xFF, the ROM would read blank flash, fail every
        // candidate, and STILL release CPU0 on its way to halt() (the
        // blank-flash release at the end of main). That produces a run in which
        // CPU0 comes out of reset and the eth ROM is fetched - which is exactly
        // what a successful handshake looks like from the outside. A silent
        // missing file would therefore manufacture a false pass. Refuse.
        fh = $fopen(image_file, "r");
        if (fh == 0) begin
            $display("GLSN-FLASH: FATAL: cannot open flash image '%0s'",
                     image_file);
            $display("GLSN-FLASH:   Without it the model reads as blank flash,");
            $display("GLSN-FLASH:   and a blank-flash boot ALSO releases CPU0 -");
            $display("GLSN-FLASH:   so this would look like a passing handshake.");
            $fatal(1, "GLSN-FLASH: no flash image");
        end
        $fclose(fh);

        $readmemh(image_file, u_flash.I0.memory);
        // DECLARED, not merely done. Everything this device hands the design
        // came from the TESTBENCH: a run that reached the application only
        // because a bench device supplied a valid image is not the design
        // booting unaided, and a month later nobody can tell the two apart from
        // a transcript that does not say so. sim.log is published evidence and
        // inputs.txt carries this file's sha256 beside it.
        $display("GLSN-FLASH: BENCH-SUPPLIED DEVICE sst26vf064b on QSPI_SCLK,QSPI_nCS,QSPI_IO");
        $display("GLSN-FLASH:   the boot image below came from the bench, not the design.");
        $display("GLSN-FLASH: loaded '%0s' into sst26vf064b.I0.memory (0x%0h bytes pre-erased to FF)",
                 image_file, ERASE_BYTES);
        // Announce the boot-table magic actually present at offset 0. If this
        // is not 424f4f54 the ROM will reject TABLE0 and the run is already
        // decided; better to see it in the first lines of the transcript than
        // to infer it from a halt 40 ms of simulated time later.
        $display("GLSN-FLASH: offset 0x0 = %02h %02h %02h %02h (magic, LE; expect 54 4f 4f 42)",
                 u_flash.I0.memory[0], u_flash.I0.memory[1],
                 u_flash.I0.memory[2], u_flash.I0.memory[3]);
    end

endmodule


// ---------------------------------------------------------------------------
// THE ATTACHMENT ITSELF.
//
// gls_netlist_tb is generated by gen_netlist_tb.py. QSPI_IO comes from the
// spec's `pullup` list (a wire plus per-bit pullup primitives, gen_netlist_tb
// .py:166-172); QSPI_SCLK and QSPI_nCS come from its `tiez` list (a bare wire,
// gen_netlist_tb.py:163-165). All three are also connected to the DUT by the
// same generator, so binding here puts the flash on the very same nets the
// chip's pads drive.
// ---------------------------------------------------------------------------
bind gls_netlist_tb gls_flash_attach u_gls_flash_attach (
    .SCK (QSPI_SCLK),
    .CEb (QSPI_nCS),
    .SIO (QSPI_IO)
);
