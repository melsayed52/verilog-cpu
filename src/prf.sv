//////////////////////////////////////////////////////////////////////////////////
// Module: prf
// Description: Physical Register File with:
//   - One CDB write port
//   - One invalidate port (for newly allocated dest regs)
//   - NUM_READ combinational read ports (flattened as vectors)
//   - Valid bits per physical register to feed rename
// Notes:
//   - Tag 0 is treated as x0: always reads as 0 and is always valid.
//   - valid_o[0] is forced to 1 on reset and every cycle.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"

module prf #(
  parameter int XLEN_P   = XLEN,
  parameter int N_PHYS   = N_PHYS_REGS,
  parameter int N_ARCH   = N_ARCH_REGS,  // unused but kept for compatibility
  parameter int TAG_W    = PREG_W,
  parameter int NUM_READ = 4
)(
  input  logic                           clk,
  input  logic                           rst_n,

  // Invalidate newly allocated dest registers
  input  logic                           inv_valid_i,
  input  logic [TAG_W-1:0]               inv_tag_i,

  // Writeback on common data bus
  input  logic                           wb_valid_i,
  input  logic [TAG_W-1:0]               wb_tag_i,
  input  logic [XLEN_P-1:0]              wb_data_i,

  // Flattened read ports: NUM_READ tags in, NUM_READ data out
  input  logic [NUM_READ*TAG_W-1:0]      rtag_i,
  output logic [NUM_READ*XLEN_P-1:0]     rdata_o,

  // Valid bits (one per physical register)
  output logic [N_PHYS-1:0]              valid_o
);

  // Register file storage
  logic [XLEN_P-1:0] mem [0:N_PHYS-1];

  // ---------------------------------------------------------------------------
  // Combinational reads
  // ---------------------------------------------------------------------------
  genvar r;
  generate
    for (r = 0; r < NUM_READ; r++) begin : GEN_READ_PORTS
      wire [TAG_W-1:0] rtag  = rtag_i[r*TAG_W   +: TAG_W];
      wire [XLEN_P-1:0] rval = (rtag == '0) ? '0 : mem[rtag];
      assign rdata_o[r*XLEN_P +: XLEN_P] = rval;
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Sequential writes + valid bits
  // ---------------------------------------------------------------------------
  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Clear everything; x0 is valid and zero
      for (i = 0; i < N_PHYS; i++) begin
        mem[i]    <= '0;
        valid_o[i] <= 1'b0;
      end
      mem[0]     <= '0;
      valid_o[0] <= 1'b1;
    end else begin
      // Keep x0 always valid and zero
      mem[0]     <= '0;
      valid_o[0] <= 1'b1;

      // Invalidate dest (except tag 0)
      if (inv_valid_i && (inv_tag_i != '0)) begin
        valid_o[inv_tag_i] <= 1'b0;
      end

      // Writeback from CDB (except tag 0)
      if (wb_valid_i && (wb_tag_i != '0)) begin
        mem[wb_tag_i]     <= wb_data_i;
        valid_o[wb_tag_i] <= 1'b1;
      end
    end
  end

endmodule
