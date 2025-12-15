//////////////////////////////////////////////////////////////////////////////////
// Module Name: rob
// Description: Reorder Buffer (Phase 4).
// Additional Comments:
//   - Added commit_o: pulses on ANY ROB retirement (including stores/branches/rd=x0)
//   - free_req_o remains "free old preg only when applicable"
//   - Added optional debug prints guarded by `ROB_DEBUG
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"
`include "checkpoint_types.sv"

module rob #(
  parameter int DEPTH = `ROB_DEPTH
)(
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   flush_i,

  input  logic                   recover_i,
  input  logic [ooop_types::ROB_W-1:0] recover_tag_i,

  input  logic                   checkpoint_take_i,
  input  logic [ooop_types::ROB_W-1:0] checkpoint_tag_i,

  // allocate from dispatch
  input  logic                   alloc_valid_i,
  input  ooop_types::rename_pkt_t alloc_pkt_i,
  output logic                   ready_o,

  // done-mark sources
  input  ooop_types::wb_pkt_t     wb_alu_i,
  input  ooop_types::wb_pkt_t     wb_lsu_i,
  input  ooop_types::wb_pkt_t     wb_bru_i,

  // commit -> free list / rename
  output logic                   free_req_o,
  output logic [ooop_types::PREG_W-1:0] free_preg_o,

  // NEW: commit pulse (counts ALL retired instructions)
  output logic                   commit_o,

  // live ROB tags bitmap
  output logic [ooop_types::ROB_DEPTH-1:0] live_tag_o
);

  import ooop_types::*;
  import checkpoint_types::*;

  typedef struct packed {
    logic              valid;
    logic              done;
    logic [ROB_W-1:0]  tag;
    logic              rd_used;
    logic [PREG_W-1:0] old_prd;
  } rob_ent_t;

  rob_ent_t entries[DEPTH];

  logic [ROB_W-1:0] head, tail;
  logic [ROB_W:0]   count;

  rob_ptrs_snapshot_t ckpt_ptrs[DEPTH];
  logic [DEPTH-1:0]   ckpt_pending;

  // action wires (current-cycle)
  logic commit_fire;
  logic alloc_fire;

  assign ready_o    = (count < DEPTH);
  assign alloc_fire = alloc_valid_i && ready_o;

  function automatic logic wb_hits(input wb_pkt_t wb, input logic [ROB_W-1:0] tag);
    wb_hits = wb.valid && (wb.rob_tag == tag);
  endfunction

  // commit is "head valid && done && count!=0" (but suppressed during flush only)
  // Allow commit during recover - the mispredicted instruction at head must retire first
  always @* begin
    commit_fire = 1'b0;
    if (!flush_i) begin
      if ((count != 0) && entries[head].valid && entries[head].done) begin
        commit_fire = 1'b1;
      end
    end
  end

  // expose commit pulse (combinational pulse aligned with retirement)
  assign commit_o = commit_fire;

  // commit/free logic (combinational)
  always @* begin
    free_req_o  = 1'b0;
    free_preg_o = '0;

    if (commit_fire) begin
      if (entries[head].rd_used && (entries[head].old_prd != '0)) begin
        free_req_o  = 1'b1;
        free_preg_o = entries[head].old_prd;
      end
    end
  end

  // live tag bitmap
  integer k;
  always @* begin
    live_tag_o = '0;
    for (k = 0; k < DEPTH; k = k + 1) begin
      if (entries[k].valid) begin
        live_tag_o[entries[k].tag] = 1'b1;
      end
    end
  end

  integer i, j;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      head <= '0;
      tail <= '0;
      count <= '0;
      ckpt_pending <= '0;

      for (i = 0; i < DEPTH; i++) begin
        entries[i]   <= '0;
        ckpt_ptrs[i] <= '0;
      end

`ifdef ROB_DEBUG
      $display("[rob] reset");
`endif

    end else if (flush_i && !recover_i) begin
      head <= '0;
      tail <= '0;
      count <= '0;
      ckpt_pending <= '0;

      for (i = 0; i < DEPTH; i++) begin
        entries[i] <= '0;
      end

`ifdef ROB_DEBUG
      $display("[rob] flush");
`endif

    end else begin
      // Handle recovery: invalidate younger entries, restore tail
      // But allow commit to happen normally (head updates from commit logic below)
      if (recover_i) begin
        logic [ROB_W-1:0] ckpt_tail;
        logic [ROB_W-1:0] idx;

        ckpt_tail = ckpt_ptrs[recover_tag_i].tail;
        idx       = ckpt_tail;

        // invalidate younger-than-checkpoint entries: [ckpt_tail .. tail)
        for (j = 0; j < DEPTH; j++) begin
          if (idx == tail) begin
            j = DEPTH;
          end else begin
            entries[idx] <= '0;
            idx = idx + 1'b1;
          end
        end

        tail         <= ckpt_tail;
        ckpt_pending <= '0;

`ifdef ROB_DEBUG
        $display("[rob] recover tag=%0d -> tail=%0d (flush younger, allow commit)", recover_tag_i, ckpt_tail);
`endif
      end

      // record checkpoint intent (tag is "next allocated instruction's rob_tag")
      if (checkpoint_take_i) begin
        ckpt_pending[checkpoint_tag_i] <= 1'b1;
`ifdef ROB_DEBUG
        $display("[rob] checkpoint pending set for tag=%0d", checkpoint_tag_i);
`endif
      end

      // mark done from WB
      for (i = 0; i < DEPTH; i++) begin
        if (entries[i].valid && !entries[i].done) begin
          if (wb_hits(wb_alu_i, entries[i].tag) ||
              wb_hits(wb_lsu_i, entries[i].tag) ||
              wb_hits(wb_bru_i, entries[i].tag)) begin
            entries[i].done <= 1'b1;
`ifdef ROB_DEBUG
            $display("[rob] done mark idx=%0d tag=%0d (alu=%0b lsu=%0b bru=%0b)",
                     i, entries[i].tag,
                     wb_hits(wb_alu_i, entries[i].tag),
                     wb_hits(wb_lsu_i, entries[i].tag),
                     wb_hits(wb_bru_i, entries[i].tag));
`endif
          end
        end
      end

      // commit: retire head entry
      if (commit_fire) begin
`ifdef ROB_DEBUG
        $display("[rob] commit head=%0d tag=%0d rd_used=%0b old_prd=%0d free_req=%0b",
                 head, entries[head].tag, entries[head].rd_used, entries[head].old_prd,
                 (entries[head].rd_used && (entries[head].old_prd != '0)));
`endif
        entries[head] <= '0;
        head <= head + 1'b1;
      end

      // allocate
      if (alloc_fire) begin
        entries[tail].valid   <= 1'b1;
        entries[tail].done    <= 1'b0;
        entries[tail].tag     <= alloc_pkt_i.rob_tag;
        entries[tail].rd_used <= alloc_pkt_i.rd_used;
        entries[tail].old_prd <= alloc_pkt_i.old_prd;

        if (ckpt_pending[alloc_pkt_i.rob_tag]) begin
          ckpt_ptrs[alloc_pkt_i.rob_tag].head  <= head;
          ckpt_ptrs[alloc_pkt_i.rob_tag].tail  <= tail + 1'b1;
          ckpt_ptrs[alloc_pkt_i.rob_tag].count <= count + 1'b1;
          ckpt_pending[alloc_pkt_i.rob_tag]    <= 1'b0;

`ifdef ROB_DEBUG
          $display("[rob] checkpoint snapshot tag=%0d: head=%0d tail_after=%0d count_after=%0d",
                   alloc_pkt_i.rob_tag, head, (tail + 1'b1), (count + 1'b1));
`endif
        end

`ifdef ROB_DEBUG
        $display("[rob] alloc tail=%0d tag=%0d rd_used=%0b old_prd=%0d",
                 tail, alloc_pkt_i.rob_tag, alloc_pkt_i.rd_used, alloc_pkt_i.old_prd);
`endif

        tail <= tail + 1'b1;
      end

      // count update: based on SAME-CYCLE commit_fire/alloc_fire and recover_i
      if (recover_i) begin
        // During recovery, count is determined by checkpoint count and commit
        if (commit_fire) begin
          count <= ckpt_ptrs[recover_tag_i].count - 1'b1;
        end else begin
          count <= ckpt_ptrs[recover_tag_i].count;
        end
      end else begin
        unique case ({alloc_fire, commit_fire})
          2'b10: count <= count + 1'b1; // alloc only
          2'b01: count <= count - 1'b1; // commit only
          default: count <= count;      // both or neither
        endcase
      end
    end
  end

endmodule
