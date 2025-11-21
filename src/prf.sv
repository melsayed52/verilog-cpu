////////////////////////////////////////////////////////////////////////////////
// Module: prf
// Description: Simple physical register file with per‑register validity and
// writeback.  The PRF stores 128 XLEN‑bit registers by default.  On each
// cycle the dispatch stage may invalidate a newly allocated destination
// register via inv_valid_i/inv_tag_i; later a CDB writeback will mark a
// register as valid and write its value.  Multiple combinational read ports
// are provided to allow reservation stations to read operand values.  The
// valid_o vector is exported so that rename can determine source operand
// readiness without back‑to‑back stalls.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"

module prf #(
  parameter int XLEN_P  = XLEN,
  parameter int N_PHYS  = N_PHYS_REGS,
  parameter int N_ARCH  = N_ARCH_REGS,
  parameter int TAG_W   = PREG_W,
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

  // Combinational read ports
  input  logic [NUM_READ-1:0][TAG_W-1:0] rtag_i,
  output logic [NUM_READ-1:0][XLEN_P-1:0] rdata_o,

  // Per‑register valid bits
  output logic [N_PHYS-1:0]              valid_o
);

  // Register memory
  logic [XLEN_P-1:0] mem [0:N_PHYS-1];

  // Multi‑port combinational reads
  genvar r;
  generate
    for (r = 0; r < NUM_READ; r++) begin : GEN_READ
      always_comb begin
        rdata_o[r] = mem[rtag_i[r]];
      end
    end
  endgenerate

  integer i;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (i = 0; i < N_PHYS; i++) begin
        mem[i]     <= '0;
        valid_o[i] <= (i < N_ARCH); // physical regs backing architectural regs are valid
      end
      valid_o[0] <= 1'b1; // x0 always valid
    end else begin
      // Invalidate dest
      if (inv_valid_i && (inv_tag_i != '0)) begin
        valid_o[inv_tag_i] <= 1'b0;
      end
      // Writeback from CDB
      if (wb_valid_i && (wb_tag_i != '0)) begin
        mem[wb_tag_i]     <= wb_data_i;
        valid_o[wb_tag_i] <= 1'b1;
      end
    end
  end

endmodule