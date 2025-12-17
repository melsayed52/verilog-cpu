//////////////////////////////////////////////////////////////////////////////////
// Module Name: alu_fu
// Description: 1-cycle ALU FU for phase 3.
//              Latches issued entry + operands, writes back next cycle via wb_pkt_t.
// Additional Comments:
//   - tolerant to decode alu_op encodings by using instr bits as fallback
//   - added flush_i: clears in-flight wb packet when asserted
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module alu_fu (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 flush_i,

  input  logic                 issue_valid_i,
  input  ooop_types::rs_entry_t entry_i,
  input  ooop_types::xlen_t     src1_i,
  input  ooop_types::xlen_t     src2_i,

  output ooop_types::wb_pkt_t   wb_o
);

  import ooop_types::*;

  logic      v_q;
  rs_entry_t e_q;
  xlen_t     a_q, b_q;

  xlen_t op_b;
  xlen_t res;

  // decode fields from instruction (fallback correctness)
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  always @* begin
    opcode = e_q.instr[6:0];
    funct3 = e_q.instr[14:12];
    funct7 = e_q.instr[31:25];
  end

  always @* begin
    op_b = e_q.imm_used ? e_q.imm : b_q;
    res  = 32'd0;

    // Primary: use enum values when they match
    unique case (e_q.alu_op)
      ALU_ADD:   res = a_q + op_b;
      ALU_SUB:   res = a_q - op_b;
      ALU_AND:   res = a_q & op_b;
      ALU_OR:    res = a_q | op_b;
      ALU_XOR:   res = a_q ^ op_b;
      ALU_SLL:   res = a_q << op_b[4:0];
      ALU_SRL:   res = a_q >> op_b[4:0];
      ALU_SRA:   res = $signed(a_q) >>> op_b[4:0];
      ALU_SLT:   res = ($signed(a_q) < $signed(op_b)) ? 32'd1 : 32'd0;
      ALU_SLTU:  res = (a_q < op_b) ? 32'd1 : 32'd0;

      // keep your aliases
      ALU_SLTIU: res = (a_q < op_b) ? 32'd1 : 32'd0;
      ALU_LUI:   res = op_b;

      default: begin
        // Fallback: decode common subset using instr bits (fixes encoding mismatches)
        unique case (opcode)
          7'b0110111: begin
            // LUI
            res = e_q.imm;
          end
          7'b0010011: begin
            // I-type ALU
            unique case (funct3)
              3'b000: res = a_q + e_q.imm;                                    // addi
              3'b110: res = a_q | e_q.imm;                                    // ori
              3'b011: res = (a_q < e_q.imm) ? 32'd1 : 32'd0;                  // sltiu
              3'b101: res = $signed(a_q) >>> e_q.imm[4:0];                    // srai (approx)
              default: res = a_q + e_q.imm;
            endcase
          end
          7'b0110011: begin
            // R-type subset
            unique case ({funct7, funct3})
              {7'b0000000, 3'b000}: res = a_q + b_q;                          // add
              {7'b0100000, 3'b000}: res = a_q - b_q;                          // sub
              {7'b0000000, 3'b111}: res = a_q & b_q;                          // and
              {7'b0100000, 3'b101}: res = $signed(a_q) >>> b_q[4:0];          // sra
              default: res = a_q + b_q;
            endcase
          end
          default: res = 32'd0;
        endcase
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v_q <= 1'b0;
      e_q <= '0;
      a_q <= '0;
      b_q <= '0;
    end else if (flush_i) begin
      v_q <= 1'b0;
      e_q <= '0;
      a_q <= '0;
      b_q <= '0;
    end else begin
      v_q <= issue_valid_i;
      if (issue_valid_i) begin
        e_q <= entry_i;
        a_q <= src1_i;
        b_q <= src2_i;
      end
    end
  end

  always @* begin
    wb_o         = '0;
    wb_o.valid   = v_q;
    wb_o.rob_tag = e_q.rob_tag;
    wb_o.rd_used = e_q.rd_used;
    wb_o.prd     = e_q.rd_used ? e_q.prd : '0;
    wb_o.data    = res;
  end

endmodule
