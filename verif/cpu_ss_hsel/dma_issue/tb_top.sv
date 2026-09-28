`timescale 1ns/1ps
// Scratch bench: rc4-lineage dma_250_ahb (4 ch, 2 VCH, CFG_ADDR_W 14) on one AHB-Lite
// SRAM, with a per-cycle bus trace. Measures the DMA-250's idle cycles at each
// source<->destination switch, the quantity the cpu_ss_hsel phantom depends on.
module tb_top;
  localparam AW = 32, DW = 32, PAW = 14, NVCH = 2, NCH = 4;
  reg hclk = 1'b0; always #5 hclk = ~hclk;
  reg hresetn;
  reg psel = 0, penable = 0, pwrite = 0;
  reg  [PAW-1:0] paddr = 0;
  reg  [31:0]    pwdata = 0;
  wire [31:0]    prdata;
  wire           pready;
  wire [AW-1:0]  haddr;
  wire [2:0]     hburst, hsize;
  wire           hmastlock, hwrite;
  wire [3:0]     hprot;
  wire [1:0]     htrans;
  wire [DW-1:0]  hwdata, hrdata;
  wire           hready, hresp;
  wire [NCH-1:0] dma_done;
  wire           dma_err;
  dma_250_ahb #(.SYS_ADDR_W(AW), .SYS_DATA_W(DW), .CFG_ADDR_W(PAW),
                .CHANNEL_NUM(NCH), .NUM_VCH(NVCH)) u_dut (
      .HCLK(hclk), .HRESETn(hresetn),
      .HADDR(haddr), .HBURST(hburst), .HMASTLOCK(hmastlock), .HPROT(hprot),
      .HSIZE(hsize), .HTRANS(htrans), .HWDATA(hwdata), .HWRITE(hwrite),
      .HRDATA(hrdata), .HREADY(hready), .HRESP(hresp),
      .PCLKEN(1'b1), .PSEL(psel), .PEN(penable), .PWRITE(pwrite),
      .PADDR(paddr), .PWDATA(pwdata), .PRDATA(prdata), .PREADY(pready),
      .DMA_REQ({NCH{1'b0}}), .DMA_DONE(dma_done), .DMA_ERR(dma_err));
  tb_ahbl_sram_ws u_sram (
      .HCLK(hclk), .HRESETn(hresetn), .HSEL(1'b1), .HADDR(haddr), .HTRANS(htrans),
      .HWRITE(hwrite), .HSIZE(hsize), .HWDATA(hwdata), .HREADY(hready),
      .HRDATA(hrdata), .HREADYOUT(hready), .HRESP(hresp));
  integer scen = 0;   // set by the test while a copy runs
endmodule
