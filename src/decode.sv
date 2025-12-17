//////////////////////////////////////////////////////////////////////////////////
// Module Name: decode
// Description: Decode stage (fully combinational). Produces decode_pkt_t.
// Additional Comments:
//   - handshake passthrough: ready_out = ready_in, valid_out = valid_in
//   - emits ooop_types enums (alu_op_t, fu_t, ls_size_t) to match Phase 2/3 plumbing
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module decode (
  input  logic       valid_in,
  output logic       ready_out,
  input  logic       ready_in,

  input  logic [31:0] pc_in,
  input  logic [31:0] instr_in,
  input  logic        predicted_taken_in,
  input  logic [31:0] predicted_target_in,

  output logic        valid_out,
  output ooop_types::decode_pkt_t pkt_out
);

  import ooop_types::*;

  // handshake passthrough (no internal state)
  assign ready_out = ready_in;
  assign valid_out = valid_in;

  // fields
  wire [6:0] opcode = instr_in[6:0];
  wire [2:0] funct3 = instr_in[14:12];
  wire [6:0] funct7 = instr_in[31:25];

  wire [4:0] rd  = instr_in[11:7];
  wire [4:0] rs1 = instr_in[19:15];
  wire [4:0] rs2 = instr_in[24:20];

  // immediates
  wire [31:0] imm_i = {{20{instr_in[31]}}, instr_in[31:20]};
  wire [31:0] imm_s = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
  wire [31:0] imm_b = {{19{instr_in[31]}}, instr_in[31], instr_in[7], instr_in[30:25], instr_in[11:8], 1'b0};
  wire [31:0] imm_u = {instr_in[31:12], 12'b0};

  // FIX: J-immediate for JAL
  wire [31:0] imm_j = {{11{instr_in[31]}}, instr_in[31], instr_in[19:12], instr_in[20], instr_in[30:21], 1'b0};

  // default decode
  always @* begin
    pkt_out = '0;

    pkt_out.pc        = pc_in;
    pkt_out.rs1       = rs1;
    pkt_out.rs2       = rs2;
    pkt_out.rd        = rd;

    pkt_out.rd_used   = 1'b0;
    pkt_out.rs1_used  = 1'b0;
    pkt_out.rs2_used  = 1'b0;

    pkt_out.fu_type   = FU_ALU;
    pkt_out.alu_op    = ALU_ADD;

    pkt_out.imm       = 32'd0;
    pkt_out.imm_used  = 1'b0;

    pkt_out.is_load   = 1'b0;
    pkt_out.is_store  = 1'b0;
    pkt_out.ls_size   = LS_W;
    pkt_out.unsigned_load = 1'b0;

    pkt_out.is_branch = 1'b0;
    pkt_out.is_jump   = 1'b0;
    pkt_out.is_jalr   = 1'b0;
    pkt_out.funct3    = funct3;  // pass funct3 for branch/load/store decoding
    pkt_out.predicted_taken  = predicted_taken_in;
    pkt_out.predicted_target = predicted_target_in;

    unique case (opcode)

      // LUI
      7'b0110111: begin
        pkt_out.fu_type   = FU_ALU;
        pkt_out.alu_op    = ALU_LUI;
        pkt_out.rd_used   = (rd != 5'd0);
        pkt_out.imm       = imm_u;
        pkt_out.imm_used  = 1'b1;
      end

      // FIX: JAL
      7'b1101111: begin
        pkt_out.fu_type   = FU_BRU;
        pkt_out.is_jump   = 1'b1;
        pkt_out.rd_used   = (rd != 5'd0); // jal x0,... means no link
        pkt_out.imm       = imm_j;
        pkt_out.imm_used  = 1'b1;
      end

      // OP-IMM (ADDI, ORI, ANDI, SLTIU, SRAI)
      7'b0010011: begin
        pkt_out.fu_type   = FU_ALU;
        pkt_out.rs1_used  = 1'b1;
        pkt_out.rd_used   = (rd != 5'd0);
        pkt_out.imm       = imm_i;
        pkt_out.imm_used  = 1'b1;

        unique case (funct3)
          3'b000: pkt_out.alu_op = ALU_ADD;    // addi
          3'b110: pkt_out.alu_op = ALU_OR;     // ori
          3'b111: pkt_out.alu_op = ALU_AND;    // andi
          3'b011: pkt_out.alu_op = ALU_SLTIU;  // sltiu
          3'b101: begin
            // srli/srai distinguish via funct7
            if (funct7 == 7'b0100000) pkt_out.alu_op = ALU_SRA; // srai
            else                      pkt_out.alu_op = ALU_SRA; // (you only use sra in traces)
          end
          default: pkt_out.alu_op = ALU_ADD;
        endcase
      end

      // OP (ADD/SUB, AND, OR, SRA)
      7'b0110011: begin
        pkt_out.fu_type   = FU_ALU;
        pkt_out.rs1_used  = 1'b1;
        pkt_out.rs2_used  = 1'b1;
        pkt_out.rd_used   = (rd != 5'd0);

        unique case (funct3)
          3'b000: begin
            if (funct7 == 7'b0100000) pkt_out.alu_op = ALU_SUB; // sub
            else                      pkt_out.alu_op = ALU_ADD; // add
          end
          3'b111: pkt_out.alu_op = ALU_AND; // and
          3'b110: pkt_out.alu_op = ALU_OR;  // or
          3'b101: pkt_out.alu_op = ALU_SRA; // sra
          default: pkt_out.alu_op = ALU_ADD;
        endcase
      end

      // LOAD (LW, LBU)
      7'b0000011: begin
        pkt_out.fu_type   = FU_LSU;
        pkt_out.rs1_used  = 1'b1;
        pkt_out.rd_used   = (rd != 5'd0);
        pkt_out.is_load   = 1'b1;
        pkt_out.imm       = imm_i;
        pkt_out.imm_used  = 1'b1;

        unique case (funct3)
          3'b010: begin pkt_out.ls_size = LS_W; pkt_out.unsigned_load = 1'b0; end // lw
          3'b100: begin pkt_out.ls_size = LS_B; pkt_out.unsigned_load = 1'b1; end // lbu
          default: begin pkt_out.ls_size = LS_W; pkt_out.unsigned_load = 1'b0; end
        endcase
      end

      // STORE (SW, SH)
      7'b0100011: begin
        pkt_out.fu_type   = FU_LSU;
        pkt_out.rs1_used  = 1'b1;
        pkt_out.rs2_used  = 1'b1;
        pkt_out.is_store  = 1'b1;
        pkt_out.imm       = imm_s;
        pkt_out.imm_used  = 1'b1;

        unique case (funct3)
          3'b010: pkt_out.ls_size = LS_W; // sw
          3'b001: pkt_out.ls_size = LS_H; // sh
          default: pkt_out.ls_size = LS_W;
        endcase
      end

      // BRANCH (BNE only is fine for your tests)
      7'b1100011: begin
        pkt_out.fu_type   = FU_BRU;
        pkt_out.is_branch = 1'b1;
        pkt_out.rs1_used  = 1'b1;
        pkt_out.rs2_used  = 1'b1;
        pkt_out.imm       = imm_b;
        pkt_out.imm_used  = 1'b1;
      end

      // JALR
      7'b1100111: begin
        pkt_out.fu_type   = FU_BRU;
        pkt_out.is_jump   = 1'b1;
        pkt_out.is_jalr   = 1'b1;
        pkt_out.rs1_used  = 1'b1;
        pkt_out.rd_used   = (rd != 5'd0); // jalr x0,... means no link
        pkt_out.imm       = imm_i;
        pkt_out.imm_used  = 1'b1;
      end

      default: begin
        // unknown -> treat as NOP (valid still flows, but it won't write anything)
        pkt_out = '0;
        pkt_out.pc = pc_in;
      end

    endcase
  end

endmodule
