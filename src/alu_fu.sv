//////////////////////////////////////////////////////////////////////////////////
// Module Name: alu_fu
// Description: Single-cycle integer ALU functional unit for the out-of-order
//              core. Takes an issued instruction from the ALU reservation
//              station, reads source operands from the physical register file,
//              performs the ALU operation, and produces writeback and ROB
//              completion signals.
// Additional Comments:
//   - Uses issue_pkt_t fields: rs1_tag, rs2_tag, rd_tag, rd_used,
//     alu_op, imm, imm_used, rob_tag.
//   - ALU operation encoding (alu_op) should match the existing decode logic.
//     The case statement below assumes a simple convention and can be
//     extended/adjusted to match your course-provided enum.
//
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module alu_fu #(
  parameter int XLEN_P = XLEN
)(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 flush_i,

  // From ALU reservation station
  input  logic                 issue_valid_i,
  output logic                 issue_ready_o,
  input  issue_pkt_t           issue_pkt_i,

  // PRF combinational read ports (two operands)
  output logic [PREG_W-1:0]    prf_rs1_tag_o,
  output logic [PREG_W-1:0]    prf_rs2_tag_o,
  input  logic [XLEN_P-1:0]    prf_rs1_data_i,
  input  logic [XLEN_P-1:0]    prf_rs2_data_i,

  // Writeback to CDB / PRF
  output logic                 wb_valid_o,
  output logic [PREG_W-1:0]    wb_tag_o,
  output logic [XLEN_P-1:0]    wb_data_o,

  // Completion to ROB
  output logic                 cpl_valid_o,
  output logic [ROB_TAG_W-1:0] cpl_tag_o
);

  // ---------------------------------------------------------------------------
  // PRF read tags: directly expose source tags from the issue packet
  // ---------------------------------------------------------------------------
  assign prf_rs1_tag_o = issue_pkt_i.rs1_tag;
  assign prf_rs2_tag_o = issue_pkt_i.rs2_tag;

  // ---------------------------------------------------------------------------
  // Simple 1-op-in-flight pipeline: capture packet + operands for 1 cycle
  // ---------------------------------------------------------------------------
  logic        busy_q;
  issue_pkt_t  pkt_q;
  logic [XLEN_P-1:0] op_a_q;
  logic [XLEN_P-1:0] op_b_q;
  logic [XLEN_P-1:0] result_d;

  // The FU can accept a new instruction when not busy.
  assign issue_ready_o = !busy_q;

  // Operand capture and busy flag
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q <= 1'b0;
      pkt_q  <= '0;
      op_a_q <= '0;
      op_b_q <= '0;
    end else if (flush_i) begin
      busy_q <= 1'b0;
      pkt_q  <= '0;
    end else begin
      if (issue_valid_i && issue_ready_o) begin
        busy_q <= 1'b1;
        pkt_q  <= issue_pkt_i;
        op_a_q <= prf_rs1_data_i;
        // Use immediate when imm_used is set, otherwise rs2 value
        op_b_q <= issue_pkt_i.imm_used ? issue_pkt_i.imm : prf_rs2_data_i;
      end else if (busy_q) begin
        // Single-cycle execute: result is ready one cycle later
        busy_q <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // ALU operation
  // ---------------------------------------------------------------------------
  always_comb begin
    result_d = '0;

    // NOTE: This assumes a simple alu_op encoding. Adjust to match your
    //       existing decode (e.g. ALU_ADD, ALU_SUB, etc.).
    unique case (pkt_q.alu_op)
      4'd0: result_d = op_a_q + op_b_q;                    // ADD / ADDI
      4'd1: result_d = op_a_q - op_b_q;                    // SUB
      4'd2: result_d = op_a_q & op_b_q;                    // AND / ANDI
      4'd3: result_d = op_a_q | op_b_q;                    // OR / ORI
      4'd4: result_d = op_a_q ^ op_b_q;                    // XOR / XORI
      4'd5: result_d = op_a_q << op_b_q[4:0];              // SLL / SLLI
      4'd6: result_d = op_a_q >> op_b_q[4:0];              // SRL / SRLI
      4'd7: result_d = $signed(op_a_q) >>> op_b_q[4:0];    // SRA / SRAI
      default: result_d = op_a_q + op_b_q;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Writeback + completion
  // ---------------------------------------------------------------------------
  // In this simple 1-cycle model, writeback and completion happen together
  // when the FU was busy in the previous cycle.
  assign wb_valid_o  = busy_q && pkt_q.rd_used;
  assign wb_tag_o    = pkt_q.rd_tag;
  assign wb_data_o   = result_d;

  assign cpl_valid_o = busy_q;          // mark ROB entry done
  assign cpl_tag_o   = pkt_q.rob_tag;

endmodule
