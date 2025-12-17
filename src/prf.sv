//////////////////////////////////////////////////////////////////////////////////
// Module Name: prf
// Description: Physical Register File + valid bits (Phase 4).
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"
`include "checkpoint_types.sv"

module prf (
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 flush_i,

  input  logic                 recover_i,
  input  logic [ooop_types::ROB_W-1:0] recover_tag_i,

  input  logic                 checkpoint_take_i,
  input  logic [ooop_types::ROB_W-1:0] checkpoint_tag_i,

  input  logic [ooop_types::PREG_W-1:0] raddr1_i,
  output ooop_types::xlen_t             rdata1_o,
  input  logic [ooop_types::PREG_W-1:0] raddr2_i,
  output ooop_types::xlen_t             rdata2_o,

  input  ooop_types::wb_pkt_t           wb_alu_i,
  input  ooop_types::wb_pkt_t           wb_lsu_i,
  input  ooop_types::wb_pkt_t           wb_bru_i,

  input  logic                          alloc_inval_i,
  input  logic [ooop_types::PREG_W-1:0]  alloc_preg_i,

  output logic [ooop_types::N_PHYS_REGS-1:0] valid_o
);

  import ooop_types::*;
  import checkpoint_types::*;

  xlen_t regs [0:N_PHYS_REGS-1];
  logic [N_PHYS_REGS-1:0] valid_bits;

  prf_valid_snapshot_t ckpt_valid [0:ROB_DEPTH-1];
  xlen_t               ckpt_regs  [0:ROB_DEPTH-1][0:N_PHYS_REGS-1];

  // comb reads
  assign rdata1_o = regs[raddr1_i];
  assign rdata2_o = regs[raddr2_i];

  function automatic logic [N_PHYS_REGS-1:0] apply_wb_valid(
    input logic [N_PHYS_REGS-1:0] vb,
    input wb_pkt_t wb
  );
    logic [N_PHYS_REGS-1:0] tmp;
    begin
      tmp = vb;
      if (wb.valid && wb.rd_used && (wb.prd != '0)) begin
        tmp[wb.prd] = 1'b1;
      end
      apply_wb_valid = tmp;
    end
  endfunction

  logic [N_PHYS_REGS-1:0] valid_next;

  always @* begin
    valid_next = valid_bits;

    if (alloc_inval_i && (alloc_preg_i != '0)) begin
      valid_next[alloc_preg_i] = 1'b0;
    end

    valid_next = apply_wb_valid(valid_next, wb_alu_i);
    valid_next = apply_wb_valid(valid_next, wb_lsu_i);
    valid_next = apply_wb_valid(valid_next, wb_bru_i);

    valid_next[0] = 1'b1;
  end

  task automatic do_wb_data(input wb_pkt_t wb);
    if (wb.valid && wb.rd_used && (wb.prd != '0)) begin
      regs[wb.prd] <= wb.data;
    end
  endtask

  task automatic ckpt_apply_wb_data(
    input int unsigned tag,
    input wb_pkt_t wb
  );
    if (wb.valid && wb.rd_used && (wb.prd != '0)) begin
      ckpt_regs[tag][wb.prd] <= wb.data;
    end
  endtask

  integer i, j;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (i = 0; i < N_PHYS_REGS; i = i + 1) begin
        regs[i]       <= '0;
        valid_bits[i] <= 1'b1;
      end
      regs[0]       <= '0;
      valid_bits[0] <= 1'b1;

      for (i = 0; i < ROB_DEPTH; i = i + 1) begin
        ckpt_valid[i] <= '0;
      end
      for (i = 0; i < ROB_DEPTH; i = i + 1) begin
        for (j = 0; j < N_PHYS_REGS; j = j + 1) begin
          ckpt_regs[i][j] <= '0;
        end
      end

    end else if (recover_i) begin
      // NOTE: Do NOT restore PRF data or valid bits!
      // Instructions older than the mispredicting branch (including the branch itself)
      // have already executed and written valid results to the PRF.
      // Only the RAT and Free List need restoration to squash younger instructions.
      // The PRF state should remain as-is with all valid writes intact.
      regs[0]       <= '0;
      valid_bits[0] <= 1'b1;

    end else if (flush_i) begin
      regs[0]       <= '0;
      valid_bits[0] <= 1'b1;

    end else begin
      do_wb_data(wb_alu_i);
      do_wb_data(wb_lsu_i);
      do_wb_data(wb_bru_i);

      valid_bits <= valid_next;

      if (checkpoint_take_i) begin
        ckpt_valid[checkpoint_tag_i] <= valid_next;

        for (i = 0; i < N_PHYS_REGS; i = i + 1) begin
          ckpt_regs[checkpoint_tag_i][i] <= regs[i];
        end

        // apply overrides so checkpoint matches "after this cycle"
        ckpt_apply_wb_data(checkpoint_tag_i, wb_bru_i);
        ckpt_apply_wb_data(checkpoint_tag_i, wb_lsu_i);
        ckpt_apply_wb_data(checkpoint_tag_i, wb_alu_i);

        ckpt_regs[checkpoint_tag_i][0] <= '0;
      end

      regs[0]       <= '0;
      valid_bits[0] <= 1'b1;
    end
  end

  assign valid_o = valid_bits;

endmodule
