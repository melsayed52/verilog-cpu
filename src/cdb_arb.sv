//////////////////////////////////////////////////////////////////////////////////
// Module Name: cdb_arb
// Description: Simple fixed-priority CDB arbiter for phase 3.
// Selects at most one completed FU result per cycle to broadcast on the CDB.
// Priority: ALU > LSU > BRU (deterministic, "random is fine" per spec).
// Additional Comments:
// - For phase 3, branch is always not taken and no mispredict/flush is used.
// - Still forwards BRU completions to ROB (and PRF if rd_used).
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module cdb_arb (
  input  logic                 clk,
  input  logic                 rst_n,

  // ALU FU input
  input  logic                 alu_valid_i,
  input  logic [6:0]           alu_rob_tag_i,
  input  logic [6:0]           alu_prd_i,
  input  logic [31:0]          alu_data_i,
  input  logic                 alu_rd_used_i,

  // LSU FU input
  input  logic                 lsu_valid_i,
  input  logic [6:0]           lsu_rob_tag_i,
  input  logic [6:0]           lsu_prd_i,
  input  logic [31:0]          lsu_data_i,
  input  logic                 lsu_rd_used_i,

  // BRU FU input
  input  logic                 bru_valid_i,
  input  logic [6:0]           bru_rob_tag_i,
  input  logic [6:0]           bru_prd_i,
  input  logic [31:0]          bru_data_i,
  input  logic                 bru_rd_used_i,

  // CDB output (single broadcast)
  output logic                 cdb_valid_o,
  output logic [6:0]           cdb_rob_tag_o,
  output logic [6:0]           cdb_prd_o,
  output logic [31:0]          cdb_data_o
);

  always @* begin
    cdb_valid_o   = 1'b0;
    cdb_rob_tag_o = '0;
    cdb_prd_o     = '0;
    cdb_data_o    = '0;

    // fixed priority: ALU > LSU > BRU
    if (alu_valid_i) begin
      cdb_valid_o   = 1'b1;
      cdb_rob_tag_o = alu_rob_tag_i;
      cdb_prd_o     = (alu_rd_used_i) ? alu_prd_i : 7'd0;
      cdb_data_o    = alu_data_i;
    end else if (lsu_valid_i) begin
      cdb_valid_o   = 1'b1;
      cdb_rob_tag_o = lsu_rob_tag_i;
      cdb_prd_o     = (lsu_rd_used_i) ? lsu_prd_i : 7'd0;
      cdb_data_o    = lsu_data_i;
    end else if (bru_valid_i) begin
      cdb_valid_o   = 1'b1;
      cdb_rob_tag_o = bru_rob_tag_i;
      cdb_prd_o     = (bru_rd_used_i) ? bru_prd_i : 7'd0;
      cdb_data_o    = bru_data_i;
    end
  end

endmodule
