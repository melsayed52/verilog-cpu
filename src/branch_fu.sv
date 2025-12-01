//////////////////////////////////////////////////////////////////////////////////
// Module Name: branch_fu
// Description: Branch and jump functional unit. Evaluates branch conditions,
//              computes targets, optionally writes link registers (for JAL/
//              JALR-style ops), and produces ROB completion plus redirect
//              signals for later use (Phase 4).
// Additional Comments:
//   - Uses issue_pkt_t fields: pc, alu_op, imm, imm_used, is_branch,
//     is_jump, rs1_tag, rs2_tag, rd_used, rd_tag, rob_tag.
//   - Branch condition encoding via alu_op is assumed; adjust mapping to
//     match your decode (e.g. BEQ/BNE/BLT/BGE).
//
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module branch_fu #(
  parameter int XLEN_P = XLEN
)(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 flush_i,

  // From BRU reservation station
  input  logic                 issue_valid_i,
  output logic                 issue_ready_o,
  input  issue_pkt_t           issue_pkt_i,

  // PRF read ports
  output logic [PREG_W-1:0]    prf_rs1_tag_o,
  output logic [PREG_W-1:0]    prf_rs2_tag_o,
  input  logic [XLEN_P-1:0]    prf_rs1_data_i,
  input  logic [XLEN_P-1:0]    prf_rs2_data_i,

  // Writeback to CDB / PRF (e.g. link register for jumps)
  output logic                 wb_valid_o,
  output logic [PREG_W-1:0]    wb_tag_o,
  output logic [XLEN_P-1:0]    wb_data_o,

  // Completion to ROB
  output logic                 cpl_valid_o,
  output logic [ROB_TAG_W-1:0] cpl_tag_o,

  // Redirect info for Phase 4 (can be ignored for now)
  output logic                 br_redir_valid_o,
  output logic [XLEN_P-1:0]    br_redir_pc_o,
  output logic                 br_taken_o
);

  // ---------------------------------------------------------------------------
  // PRF tags
  // ---------------------------------------------------------------------------
  assign prf_rs1_tag_o = issue_pkt_i.rs1_tag;
  assign prf_rs2_tag_o = issue_pkt_i.rs2_tag;

  // ---------------------------------------------------------------------------
  // Simple 1-op pipeline (similar to ALU)
  // ---------------------------------------------------------------------------
  logic        busy_q;
  issue_pkt_t  pkt_q;
  logic [XLEN_P-1:0] rs1_q;
  logic [XLEN_P-1:0] rs2_q;

  assign issue_ready_o = !busy_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q <= 1'b0;
      pkt_q  <= '0;
      rs1_q  <= '0;
      rs2_q  <= '0;
    end else if (flush_i) begin
      busy_q <= 1'b0;
      pkt_q  <= '0;
    end else begin
      if (issue_valid_i && issue_ready_o) begin
        busy_q <= 1'b1;
        pkt_q  <= issue_pkt_i;
        rs1_q  <= prf_rs1_data_i;
        rs2_q  <= prf_rs2_data_i;
      end else if (busy_q) begin
        busy_q <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Branch decision + target computation
  // ---------------------------------------------------------------------------
  logic                 take_branch_d;
  logic [XLEN_P-1:0]    target_d;
  logic [XLEN_P-1:0]    link_val_d;

  always_comb begin
    take_branch_d = 1'b0;
    target_d      = pkt_q.pc + pkt_q.imm;
    link_val_d    = pkt_q.pc + XLEN_P'(32'd4); // default link = pc+4

    if (pkt_q.is_jump) begin
      // JAL / JALR style: always taken
      take_branch_d = 1'b1;
      if (pkt_q.imm_used) begin
        // Approximate JALR: rs1 + imm
        target_d = rs1_q + pkt_q.imm;
      end else begin
        // JAL: pc + imm
        target_d = pkt_q.pc + pkt_q.imm;
      end
    end else if (pkt_q.is_branch) begin
      // Conditional branches: use alu_op encoding for condition
      unique case (pkt_q.alu_op)
        4'd0: take_branch_d = (rs1_q == rs2_q);                         // BEQ
        4'd1: take_branch_d = (rs1_q != rs2_q);                         // BNE
        4'd2: take_branch_d = ($signed(rs1_q) <  $signed(rs2_q));       // BLT
        4'd3: take_branch_d = ($signed(rs1_q) >= $signed(rs2_q));       // BGE
        4'd4: take_branch_d = (rs1_q <  rs2_q);                         // BLTU
        4'd5: take_branch_d = (rs1_q >= rs2_q);                         // BGEU
        default: take_branch_d = 1'b0;
      endcase
      target_d = pkt_q.pc + pkt_q.imm;
    end
  end

  // ---------------------------------------------------------------------------
  // Writeback, completion, redirect
  // ---------------------------------------------------------------------------
  // Link register write (for jumps) iff rd_used is set.
  assign wb_valid_o  = busy_q && pkt_q.rd_used && pkt_q.is_jump;
  assign wb_tag_o    = pkt_q.rd_tag;
  assign wb_data_o   = link_val_d;

  assign cpl_valid_o = busy_q;
  assign cpl_tag_o   = pkt_q.rob_tag;

  assign br_taken_o        = busy_q && take_branch_d;
  assign br_redir_valid_o  = busy_q && take_branch_d;
  assign br_redir_pc_o     = target_d;

endmodule
