//////////////////////////////////////////////////////////////////////////////////
// Module Name: map_table
// Description: RAT (architectural->physical) with checkpoint/restore (Phase 4).
// Additional Comments:
//   - FIX: checkpoint stores "after rename" state by snapshotting rat_next, not rat.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"
`include "checkpoint_types.sv"

module map_table #(
  parameter int N_ARCH_REGS = ooop_types::N_ARCH_REGS,
  parameter int N_PHYS_REGS = ooop_types::N_PHYS_REGS,
  parameter int ROB_DEPTH   = ooop_types::ROB_DEPTH
)(
  input  logic clk,
  input  logic rst_n,
  input  logic flush_i,

  input  logic recover_i,
  input  logic [ooop_types::ROB_W-1:0] recover_tag_i,

  input  logic [$clog2(N_ARCH_REGS)-1:0] rs1_arch,
  input  logic [$clog2(N_ARCH_REGS)-1:0] rs2_arch,
  input  logic [$clog2(N_ARCH_REGS)-1:0] rd_arch,

  output logic [$clog2(N_PHYS_REGS)-1:0] rs1_phys,
  output logic [$clog2(N_PHYS_REGS)-1:0] rs2_phys,
  output logic [$clog2(N_PHYS_REGS)-1:0] rd_old_phys,

  input  logic we,
  input  logic [$clog2(N_ARCH_REGS)-1:0] we_arch,
  input  logic [$clog2(N_PHYS_REGS)-1:0] we_new_phys,

  input  logic checkpoint_take,
  input  logic [ooop_types::ROB_W-1:0] checkpoint_tag
);

  import ooop_types::*;
  import checkpoint_types::*;

  localparam int PHYS_W = $clog2(N_PHYS_REGS);

  logic [N_ARCH_REGS-1:0][PHYS_W-1:0] rat;
  rat_snapshot_t ckpt_rat[ROB_DEPTH];

  assign rs1_phys    = rat[rs1_arch];
  assign rs2_phys    = rat[rs2_arch];
  assign rd_old_phys = rat[rd_arch];

  // build "next" RAT for correct checkpointing
  logic [N_ARCH_REGS-1:0][PHYS_W-1:0] rat_next;
  integer i;

  always @* begin
    rat_next = rat;
    if (we && (we_arch != '0)) begin
      rat_next[we_arch] = we_new_phys;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (i = 0; i < N_ARCH_REGS; i = i + 1) begin
        rat[i] <= i[PHYS_W-1:0];
      end
      for (i = 0; i < ROB_DEPTH; i = i + 1) begin
        ckpt_rat[i] <= '0;
      end

    end else if (recover_i) begin
      rat <= ckpt_rat[recover_tag_i];

    end else if (flush_i) begin
      // no-op; recovery is authoritative

    end else begin
      // apply RAT update
      rat <= rat_next;

      // checkpoint AFTER applying update
      if (checkpoint_take) begin
        ckpt_rat[checkpoint_tag] <= rat_next;
      end
    end
  end

endmodule
