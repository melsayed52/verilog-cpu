`include "ooop_defs.vh"
//////////////////////////////////////////////////////////////////////////////////
// Module Name: rat
//////////////////////////////////////////////////////////////////////////////////

module rat #(
  parameter ARCH_REGS = N_ARCH_REGS,
  parameter PHYS_REGS = N_PHYS_REGS,
  parameter TAG_W     = PREG_W
)(
  input                  clk,
  input                  rst_n,
  input  [4:0]           rs1_arch,
  input  [4:0]           rs2_arch,
  output [TAG_W-1:0]     rs1_tag,
  output [TAG_W-1:0]     rs2_tag,
  input  [4:0]           rd_arch,
  output [TAG_W-1:0]     rd_old_tag,
  input                  rd_we,
  input  [TAG_W-1:0]     rd_new_tag
);

  reg [TAG_W-1:0] table [0:ARCH_REGS-1];
  integer i;

  always @(posedge clk) begin
    if (!rst_n) begin
      for (i = 0; i < ARCH_REGS; i = i + 1)
        table[i] <= i[TAG_W-1:0];
    end else begin
      if (rd_we && (rd_arch != 5'd0))
        table[rd_arch] <= rd_new_tag;
    end
  end

  assign rs1_tag    = table[rs1_arch];
  assign rs2_tag    = table[rs2_arch];
  assign rd_old_tag = table[rd_arch];

endmodule
