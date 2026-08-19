module eth_ss_bootrom (input logic clk, input logic en,
    input logic [9-1:0] word_addr, output logic [32-1:0] out_data);
logic [32-1:0] rdata;
always_comb begin
    case (word_addr)
        9'h000 : rdata = 32'h18003c00; // 0x0000
        9'h001 : rdata = 32'h08000189; // 0x0004
        9'h002 : rdata = 32'h080001cd; // 0x0008
        9'h003 : rdata = 32'h080001cf; // 0x000c
        9'h004 : rdata = 32'h080001d1; // 0x0010
        9'h005 : rdata = 32'h00000000; // 0x0014
        9'h006 : rdata = 32'h00000000; // 0x0018
        9'h007 : rdata = 32'h00000000; // 0x001c
        default : rdata = 32'h00000000;
    endcase
end
endmodule
