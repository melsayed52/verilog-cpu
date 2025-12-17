//////////////////////////////////////////////////////////////////////////////////
// Module Name: branch_fu
// Description: Branch functional unit with dynamic branch prediction support.
//   - Compares prediction (from BTB via pipeline) with actual outcome
//   - Misprediction cases:
//     1. Predicted taken, actually not-taken -> redirect to PC+4
//     2. Predicted not-taken, actually taken -> redirect to target
//     3. Target mismatch (JALR) -> redirect to correct target
//   - Outputs BTB update information for learning
// Additional Comments:
//   - Added flush_i: clears any in-flight output when asserted.
//   - FIX: also latches the *recover_tag_o* aligned with mispredict_o
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

  // BTB update interface (active for all branches/jumps, not just mispredicts)
  output logic                 btb_update_valid_o,
  output logic [31:0]          btb_update_pc_o,
  output logic [31:0]          btb_update_target_o,
  output logic                 btb_update_taken_o,
  output logic                 btb_update_is_branch_o,  // conditional branch vs jump

  output ooop_types::wb_pkt_t   wb_o
);

  import ooop_types::*;

  // decode bits
  logic [6:0] opcode;
  logic [2:0] funct3;

  always @* begin
    opcode = entry_i.instr[6:0];
    funct3 = entry_i.funct3;  // use reliable funct3 from pipeline instead of decoding from instr
  end

  // Is this a conditional branch (vs unconditional jump)?
  wire is_cond_branch = entry_i.is_branch || (opcode == 7'b1100011);
  wire is_jump        = entry_i.is_jump || (opcode == 7'b1101111) || (opcode == 7'b1100111);

  // actual taken?
  logic actual_taken;
  logic [31:0] target_pc;

  always @* begin
    actual_taken = 1'b0;
    target_pc    = entry_i.pc + entry_i.imm;

    if (issue_valid_i && entry_i.valid) begin
      // jumps always taken
      if (is_jump) begin
        actual_taken = 1'b1;
        if (entry_i.is_jalr) begin
          // JALR target = (rs1 + imm) & ~1
          target_pc = (src1_i + entry_i.imm) & 32'hFFFF_FFFE;
        end else begin
          // JAL uses pc+imm
          target_pc = entry_i.pc + entry_i.imm;
        end
      end else if (is_cond_branch) begin
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

  // Dynamic branch prediction: compare prediction vs actual
  // Misprediction cases:
  // 1. Predicted taken, actually not-taken -> redirect to PC+4
  // 2. Predicted not-taken, actually taken -> redirect to target
  // 3. Predicted taken but wrong target (JALR) -> redirect to correct target
  logic mp_n, mp_q;
  logic [31:0] tgt_n, tgt_q;

  // FIX: latch the tag that caused the mispredict, aligned with mp/tgt
  logic [ROB_W-1:0] rtag_n, rtag_q;

  // BTB update signals (registered)
  logic        btb_upd_v_n, btb_upd_v_q;
  logic [31:0] btb_upd_pc_n, btb_upd_pc_q;
  logic [31:0] btb_upd_tgt_n, btb_upd_tgt_q;
  logic        btb_upd_taken_n, btb_upd_taken_q;
  logic        btb_upd_is_br_n, btb_upd_is_br_q;

  wb_pkt_t wb_n, wb_q;

  always @* begin
    wb_n   = '0;
    mp_n   = 1'b0;
    tgt_n  = 32'd0;
    rtag_n = '0;

    btb_upd_v_n     = 1'b0;
    btb_upd_pc_n    = 32'd0;
    btb_upd_tgt_n   = 32'd0;
    btb_upd_taken_n = 1'b0;
    btb_upd_is_br_n = 1'b0;

    if (issue_valid_i && entry_i.valid) begin
      // mark done in ROB
      wb_n.valid    = 1'b1;
      wb_n.rob_tag  = entry_i.rob_tag;
      wb_n.rd_used  = entry_i.rd_used;
      wb_n.prd      = entry_i.rd_used ? entry_i.prd : '0;

      // link for jal/jalr
      if (is_jump && entry_i.rd_used) begin
        wb_n.data = entry_i.pc + 32'd4;
      end else begin
        wb_n.data = 32'd0;
      end

      // BTB update: always update for branches and jumps
      if (is_cond_branch || is_jump) begin
        btb_upd_v_n     = 1'b1;
        btb_upd_pc_n    = entry_i.pc;
        btb_upd_tgt_n   = target_pc;
        btb_upd_taken_n = actual_taken;
        btb_upd_is_br_n = is_cond_branch;  // true for branches, false for jumps
      end

      // Misprediction detection with dynamic prediction
      // predicted_taken and predicted_target come from BTB via pipeline
      if (is_cond_branch || is_jump) begin
        if (entry_i.predicted_taken != actual_taken) begin
          // Direction misprediction
          mp_n   = 1'b1;
          rtag_n = entry_i.rob_tag;
          if (actual_taken) begin
            // Predicted not-taken, actually taken -> go to target
            tgt_n = target_pc;
          end else begin
            // Predicted taken, actually not-taken -> go to PC+4
            tgt_n = entry_i.pc + 32'd4;
          end
        end else if (actual_taken && (entry_i.predicted_target != target_pc)) begin
          // Target misprediction (e.g., JALR with wrong target)
          mp_n   = 1'b1;
          tgt_n  = target_pc;
          rtag_n = entry_i.rob_tag;
        end
        // else: prediction was correct, no misprediction
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wb_q           <= '0;
      mp_q           <= 1'b0;
      tgt_q          <= 32'd0;
      rtag_q         <= '0;
      btb_upd_v_q    <= 1'b0;
      btb_upd_pc_q   <= 32'd0;
      btb_upd_tgt_q  <= 32'd0;
      btb_upd_taken_q<= 1'b0;
      btb_upd_is_br_q<= 1'b0;
    end else if (flush_i) begin
      wb_q           <= '0;
      mp_q           <= 1'b0;
      tgt_q          <= 32'd0;
      rtag_q         <= '0;
      btb_upd_v_q    <= 1'b0;
      btb_upd_pc_q   <= 32'd0;
      btb_upd_tgt_q  <= 32'd0;
      btb_upd_taken_q<= 1'b0;
      btb_upd_is_br_q<= 1'b0;
    end else begin
      wb_q           <= wb_n;
      mp_q           <= mp_n;
      tgt_q          <= tgt_n;
      rtag_q         <= rtag_n;
      btb_upd_v_q    <= btb_upd_v_n;
      btb_upd_pc_q   <= btb_upd_pc_n;
      btb_upd_tgt_q  <= btb_upd_tgt_n;
      btb_upd_taken_q<= btb_upd_taken_n;
      btb_upd_is_br_q<= btb_upd_is_br_n;
    end
  end

  assign wb_o          = wb_q;
  assign mispredict_o  = mp_q;
  assign target_pc_o   = tgt_q;
  assign recover_tag_o = rtag_q;

  // BTB update outputs
  assign btb_update_valid_o     = btb_upd_v_q;
  assign btb_update_pc_o        = btb_upd_pc_q;
  assign btb_update_target_o    = btb_upd_tgt_q;
  assign btb_update_taken_o     = btb_upd_taken_q;
  assign btb_update_is_branch_o = btb_upd_is_br_q;

endmodule
