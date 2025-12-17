//////////////////////////////////////////////////////////////////////////////////
// Module Name: rob_tag_alloc
// Description: ROB tag allocator with checkpoint/restore (Phase 4), made robust.
//   - Avoids tag collisions by tracking:
//       (a) live tags currently in ROB (live_tag_i)
//       (b) reserved tags allocated by rename but not yet inserted into ROB
//   - Checkpoint stores "next_tag after allocation" (true post-rename behavior).
//   - On recovery/flush, reserved tags are cleared (pipeline younger ops are dropped).
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module rob_tag_alloc #(
  parameter int ROB_DEPTH = ooop_types::ROB_DEPTH
)(
  input  logic clk,
  input  logic rst_n,
  input  logic flush_i,

  input  logic recover_i,
  input  logic [ooop_types::ROB_W-1:0] recover_tag_i,

  // NEW: live tags in ROB (1 = tag present in ROB)
  input  logic [ooop_types::ROB_DEPTH-1:0] live_tag_i,

  // allocate request from rename (fire)
  input  logic alloc_req,
  output logic alloc_ok_o, // NEW: can allocate a tag this cycle?
  output logic [ooop_types::ROB_W-1:0] tag_o,

  // NEW: feedback when ROB actually allocates the packet with tag (clears reserved)
  input  logic rob_alloc_fire_i,
  input  logic [ooop_types::ROB_W-1:0] rob_alloc_tag_i,

  // checkpoint controls
  input  logic checkpoint_take,
  input  logic [ooop_types::ROB_W-1:0] checkpoint_tag
);

  import ooop_types::*;

  logic [ROB_W-1:0] next_tag;
  logic [ROB_W-1:0] ckpt_next_tag[ROB_DEPTH];

  // reserved tags: allocated by rename, not yet inserted in ROB
  logic [ROB_DEPTH-1:0] reserved;

  // used = live OR reserved
  logic [ROB_DEPTH-1:0] used;
  assign used = live_tag_i | reserved;

  // find first free tag starting from next_tag (circular scan)
  logic             found_free;
  logic [ROB_W-1:0] free_tag;

  always @* begin
    found_free = 1'b0;
    free_tag   = next_tag;

    for (int k = 0; k < ROB_DEPTH; k = k + 1) begin
      logic [ROB_W-1:0] cand;
      cand = next_tag + k[ROB_W-1:0];

      if (!found_free && !used[cand]) begin
        found_free = 1'b1;
        free_tag   = cand;
      end
    end
  end

  assign alloc_ok_o = found_free;
  assign tag_o      = free_tag;

  // compute next_tag if we allocate this cycle
  logic [ROB_W-1:0] next_tag_after_alloc;
  assign next_tag_after_alloc = free_tag + 1'b1;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      next_tag <= '0;
      reserved <= '0;

      for (int k = 0; k < ROB_DEPTH; k = k + 1) begin
        ckpt_next_tag[k] <= '0;
      end

    end else if (recover_i) begin
      // restore allocator pointer, drop any reserved younger tags
      next_tag <= ckpt_next_tag[recover_tag_i];
      reserved <= '0;

    end else if (flush_i) begin
      // flush drops in-flight packets; clear reserved
      reserved <= '0;

    end else begin
      // clear reserved tag when ROB actually allocates it
      if (rob_alloc_fire_i) begin
        reserved[rob_alloc_tag_i] <= 1'b0;
      end

      // allocate a tag at rename-fire time
      if (alloc_req && alloc_ok_o) begin
        reserved[free_tag] <= 1'b1;
        next_tag           <= next_tag_after_alloc;
      end

      // checkpoint must capture true "post-allocation next_tag"
      if (checkpoint_take) begin
        // if the branch/jump is firing this cycle, store next_tag_after_alloc;
        // otherwise store current next_tag.
        if (alloc_req && alloc_ok_o) begin
          ckpt_next_tag[checkpoint_tag] <= next_tag_after_alloc;
        end else begin
          ckpt_next_tag[checkpoint_tag] <= next_tag;
        end
      end
    end
  end

endmodule
