//////////////////////////////////////////////////////////////////////////////////
// Module Name: branch_fu
// Description: Branch functional unit (Phase 4).
//   - Always predict not-taken.
//   - If actual outcome is taken => mispredict_o=1 and target_pc_o is provided.
//   - Still produces a wb_pkt for ROB done and optional PRF writeback (JAL/JALR link).
// Additional Comments:
//   - Added flush_i: clears any in-flight output when asserted.
//   - FIX: also latches the *recover_tag_o* aligned with mispredict_o, so recovery_ctrl
//          does not depend on wb_bru.rob_tag timing/arb alignment.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module branch_fu (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 flush_i,

  input  logic                 issue_valid_i,
  input  ooop_types::rs_entry_t entry_i,
  input  ooop_types::xlen_t     src1_i,
  input  ooop_types::xlen_t     src2_i,

  output logic                 mispredict_o,
  output logic [31:0]          target_pc_o,

  // FIX: explicit tag aligned with mispredict_o
  output logic [ooop_types::ROB_W-1:0] recover_tag_o,

  output ooop_types::wb_pkt_t   wb_o
);

  import ooop_types::*;

  // decode bits
  logic [6:0] opcode;
  logic [2:0] funct3;

  always @* begin
    opcode = entry_i.instr[6:0];
    funct3 = entry_i.instr[14:12];
  end

  // actual taken?
  logic actual_taken;
  logic [31:0] target_pc;

  always @* begin
    actual_taken = 1'b0;
    target_pc    = entry_i.pc + entry_i.imm;

    if (issue_valid_i && entry_i.valid) begin
      // jumps always taken
      if (entry_i.is_jump || (opcode == 7'b1101111) || (opcode == 7'b1100111)) begin
        actual_taken = 1'b1;
        if (entry_i.is_jalr) begin // handle JALR specifc
          // JALR target = (rs1 + imm) & ~1
          target_pc = (src1_i + entry_i.imm) & 32'hFFFF_FFFE;
        end else begin
          // JAL uses pc+imm
          target_pc = entry_i.pc + entry_i.imm;
        end
      end else if (entry_i.is_branch || (opcode == 7'b1100011)) begin
        // branch: decide by funct3
        unique case (funct3)
          3'b000: actual_taken = (src1_i == src2_i);                  // beq
          3'b001: actual_taken = (src1_i != src2_i);                  // bne
          3'b100: actual_taken = ($signed(src1_i) < $signed(src2_i)); // blt
          3'b101: actual_taken = ($signed(src1_i) >= $signed(src2_i));// bge
          3'b110: actual_taken = (src1_i < src2_i);                   // bltu
          3'b111: actual_taken = (src1_i >= src2_i);                  // bgeu
          default: actual_taken = 1'b0;
        endcase
        target_pc = entry_i.pc + entry_i.imm;
      end
    end
  end

  // always predict not taken => mispredict if actually taken
  logic mp_n, mp_q;
  logic [31:0] tgt_n, tgt_q;

  // FIX: latch the tag that caused the mispredict, aligned with mp/tgt
  logic [ROB_W-1:0] rtag_n, rtag_q;

  wb_pkt_t wb_n, wb_q;

  always @* begin
    wb_n   = '0;
    mp_n   = 1'b0;
    tgt_n  = 32'd0;
    rtag_n = '0;

    if (issue_valid_i && entry_i.valid) begin
      // mark done in ROB
      wb_n.valid    = 1'b1;
      wb_n.rob_tag  = entry_i.rob_tag;
      wb_n.rd_used  = entry_i.rd_used;
      wb_n.prd      = entry_i.rd_used ? entry_i.prd : '0;

      // link for jal/jalr
      if ((entry_i.is_jump || (opcode == 7'b1101111) || (opcode == 7'b1100111)) && entry_i.rd_used) begin
        wb_n.data = entry_i.pc + 32'd4;
      end else begin
        wb_n.data = 32'd0;
      end

      if (actual_taken) begin
        mp_n   = 1'b1;
        tgt_n  = target_pc;
        rtag_n = entry_i.rob_tag; // tag of the branch/jump being resolved
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wb_q   <= '0;
      mp_q   <= 1'b0;
      tgt_q  <= 32'd0;
      rtag_q <= '0;
    end else if (flush_i) begin
      wb_q   <= '0;
      mp_q   <= 1'b0;
      tgt_q  <= 32'd0;
      rtag_q <= '0;
    end else begin
      wb_q   <= wb_n;
      mp_q   <= mp_n;
      tgt_q  <= tgt_n;
      rtag_q <= rtag_n;
    end
  end

  assign wb_o          = wb_q;
  assign mispredict_o  = mp_q;
  assign target_pc_o   = tgt_q;
  assign recover_tag_o = rtag_q;

endmodule
