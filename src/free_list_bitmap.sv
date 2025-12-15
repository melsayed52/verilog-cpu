//////////////////////////////////////////////////////////////////////////////////
// Module Name: free_list_bitmap
// Description: Physical register free list implemented as a bitmap (Phase 4).
//   - free_map[p] = 1 => phys reg p is free
//   - alloc: when alloc_req asserted, module grants if has_free_o=1
//       * alloc_gnt pulses when allocation actually happens
//       * alloc_preg is the chosen free preg (lowest available >= N_ARCH_REGS)
//   - free: free_req + free_preg sets bit back to 1
//   - checkpoint_take stores free_map snapshot indexed by checkpoint_tag
//   - recover_i restores free_map from checkpoint indexed by recover_tag_i
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module free_list_bitmap #(
  parameter int N_ARCH_REGS = ooop_types::N_ARCH_REGS,
  parameter int N_PHYS_REGS = ooop_types::N_PHYS_REGS,
  parameter int PREG_W      = ooop_types::PREG_W,
  parameter int ROB_DEPTH   = ooop_types::ROB_DEPTH,
  parameter int ROB_W       = ooop_types::ROB_W
)(
  input  logic                   clk,
  input  logic                   rst_n,

  // pipeline control
  input  logic                   flush_i,        // ok to ignore; recovery handles correctness
  input  logic                   recover_i,
  input  logic [ROB_W-1:0]       recover_tag_i,

  // allocate request (from rename)
  input  logic                   alloc_req,
  output logic                   alloc_gnt,
  output logic [PREG_W-1:0]      alloc_preg,
  output logic                   has_free_o,

  // free request (from ROB commit)
  input  logic                   free_req,
  input  logic [PREG_W-1:0]      free_preg,

  // checkpoint controls
  input  logic                   checkpoint_take,
  input  logic [ROB_W-1:0]       checkpoint_tag,

  // visibility/debug
  output logic [N_PHYS_REGS-1:0] free_bitmap_o
);

  // ----------------------------
  // state
  // ----------------------------
  logic [N_PHYS_REGS-1:0] free_map;
  logic [N_PHYS_REGS-1:0] ckpt_free_map [ROB_DEPTH];

  assign free_bitmap_o = free_map;

  // ----------------------------
  // combinational pick (lowest free >= N_ARCH_REGS)
  // ----------------------------
  logic                 found;
  logic [PREG_W-1:0]     found_preg;

  always @* begin
    found      = 1'b0;
    found_preg = '0;

    for (int j = N_ARCH_REGS; j < N_PHYS_REGS; j = j + 1) begin
      if (!found && free_map[j]) begin
        found      = 1'b1;
        found_preg = j[PREG_W-1:0];
      end
    end
  end

  assign has_free_o  = found;
  assign alloc_preg  = found_preg;

  // grant only when a request is present and we have a free preg
  assign alloc_gnt = alloc_req && has_free_o;

  // ----------------------------
  // sequential update
  // ----------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      free_map <= '0;

      // init: x0..x31 reserved, others free
      for (int j = N_ARCH_REGS; j < N_PHYS_REGS; j = j + 1) begin
        free_map[j] <= 1'b1;
      end

      for (int t = 0; t < ROB_DEPTH; t = t + 1) begin
        ckpt_free_map[t] <= '0;
      end

    end else if (recover_i) begin
      free_map <= ckpt_free_map[recover_tag_i];

    end else begin
      // flush_i: no-op here; correctness is via recover checkpoints.
      // (keeping it as a no-op avoids freeing wrong-path regs on flush.)

      // free on commit
      if (free_req && (free_preg != '0)) begin
        free_map[free_preg] <= 1'b1;
      end

      // allocate on rename-fire
      if (alloc_gnt) begin
        free_map[found_preg] <= 1'b0;
      end

      // checkpoint must reflect same-cycle free/alloc effects,
      // so compute next_map explicitly.
      if (checkpoint_take) begin
        logic [N_PHYS_REGS-1:0] next_map;
        next_map = free_map;

        if (free_req && (free_preg != '0))
          next_map[free_preg] = 1'b1;

        if (alloc_gnt)
          next_map[found_preg] = 1'b0;

        ckpt_free_map[checkpoint_tag] <= next_map;
      end
    end
  end

endmodule
