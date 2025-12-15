//////////////////////////////////////////////////////////////////////////////////
// Module Name: cdb_arbiter
// Description: Common Data Bus (CDB) arbiter. Merges writeback results from
//              multiple functional units (ALU, LSU, BRU) into a single
//              cdb_valid/tag/data interface that feeds the physical register
//              file and reservation station wakeup logic.
// Additional Comments:
//   - Fixed-priority arbitration: ALU > LSU > BRU.
//   - Assumes at most one FU will normally attempt to write back in a given
//     cycle. If multiple are valid, only the highest-priority one is sent.
//   - Connect the outputs (cdb_*) to whatever module currently consumes the
//     CDB in your Phase 2 design (likely dispatch / PRF wrapper).
//
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"

module cdb_arbiter #(
  parameter int XLEN_P = XLEN
)(
  // ALU writeback
  input  logic                 alu_wb_valid_i,
  input  logic [PREG_W-1:0]    alu_wb_tag_i,
  input  logic [XLEN_P-1:0]    alu_wb_data_i,

  // LSU writeback
  input  logic                 lsu_wb_valid_i,
  input  logic [PREG_W-1:0]    lsu_wb_tag_i,
  input  logic [XLEN_P-1:0]    lsu_wb_data_i,

  // Branch unit writeback (e.g., link register for jumps)
  input  logic                 bru_wb_valid_i,
  input  logic [PREG_W-1:0]    bru_wb_tag_i,
  input  logic [XLEN_P-1:0]    bru_wb_data_i,

  // Merged CDB output
  output logic                 cdb_valid_o,
  output logic [PREG_W-1:0]    cdb_tag_o,
  output logic [XLEN_P-1:0]    cdb_data_o
);

  // ---------------------------------------------------------------------------
  // Fixed-priority selection: ALU > LSU > BRU
  // ---------------------------------------------------------------------------
  always_comb begin
    cdb_valid_o = 1'b0;
    cdb_tag_o   = '0;
    cdb_data_o  = '0;

    if (alu_wb_valid_i) begin
      cdb_valid_o = 1'b1;
      cdb_tag_o   = alu_wb_tag_i;
      cdb_data_o  = alu_wb_data_i;
    end else if (lsu_wb_valid_i) begin
      cdb_valid_o = 1'b1;
      cdb_tag_o   = lsu_wb_tag_i;
      cdb_data_o  = lsu_wb_data_i;
    end else if (bru_wb_valid_i) begin
      cdb_valid_o = 1'b1;
      cdb_tag_o   = bru_wb_tag_i;
      cdb_data_o  = bru_wb_data_i;
    end
  end

endmodule
