////////////////////////////////////////////////////////////////////////////////
// Module: rob
// Description: Reorder buffer with in‑order commit and completion tracking.
//
// The ROB is a circular buffer of ENTRIES entries.  Each entry stores
// whether the instruction is valid, whether it has completed execution,
// whether it writes a destination register, and the new/old physical
// register tags.  Dispatch allocates a new entry for each instruction and
// obtains its tag; the execution units notify completion via cpl_valid_i
///cpl_tag_i; and the commit logic pops entries in order when they are done
// and the downstream core (e.g. retirement stage) is ready.  A flush input
// resets the ROB to its initial state.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"

module rob #(
  parameter int ENTRIES = ROB_ENTRIES,
  parameter int TAG_W   = ROB_TAG_W,
  parameter int PREG_WP = PREG_W
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // Global flush (e.g. mispredict recovery)
  input  logic                 flush_i,

  // Allocate new entry from dispatch
  input  logic                 alloc_req_i,
  output logic                 alloc_gnt_o,
  output logic [TAG_W-1:0]     alloc_tag_o,
  input  logic                 alloc_rd_used_i,
  input  logic [PREG_WP-1:0]   alloc_dest_new_i,
  input  logic [PREG_WP-1:0]   alloc_dest_old_i,
  output logic                 full_o,

  // Completion from execution/CDB
  input  logic                 cpl_valid_i,
  input  logic [TAG_W-1:0]     cpl_tag_i,

  // Commit interface (in‑order)
  input  logic                 commit_ready_i,
  output logic                 commit_valid_o,
  output logic [TAG_W-1:0]     commit_tag_o,
  output logic                 commit_rd_used_o,
  output logic [PREG_WP-1:0]   commit_dest_new_o,
  output logic [PREG_WP-1:0]   commit_dest_old_o,

  // Checkpoint interface (snapshot of tail)
  input  logic                 checkpoint_req_i,
  output logic [TAG_W-1:0]     checkpoint_tail_o
);

  typedef struct packed {
    logic               valid;
    logic               done;
    logic               rd_used;
    logic [PREG_WP-1:0] dest_new;
    logic [PREG_WP-1:0] dest_old;
  } rob_entry_t;

  rob_entry_t entries [0:ENTRIES-1];
  logic [TAG_W-1:0] head;
  logic [TAG_W-1:0] tail;
  logic [TAG_W:0]   count;

  // Increment function for ring pointers
  function automatic [TAG_W-1:0] inc_ptr(input [TAG_W-1:0] p);
    inc_ptr = (p == ENTRIES-1) ? '0 : (p + 1'b1);
  endfunction

  // Allocation handshake
  assign alloc_tag_o = tail;
  assign full_o      = (count == ENTRIES);
  assign alloc_gnt_o = alloc_req_i && !full_o;

  // Commit handshake – valid if head entry is valid and done
  assign commit_valid_o    = (count != 0) && entries[head].valid && entries[head].done;
  assign commit_tag_o      = head;
  assign commit_rd_used_o  = entries[head].rd_used;
  assign commit_dest_new_o = entries[head].dest_new;
  assign commit_dest_old_o = entries[head].dest_old;

  integer i;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      head  <= '0;
      tail  <= '0;
      count <= '0;
      for (i = 0; i < ENTRIES; i++) entries[i] <= '0;
    end else if (flush_i) begin
      // Flush resets the entire ROB
      head  <= '0;
      tail  <= '0;
      count <= '0;
      for (i = 0; i < ENTRIES; i++) entries[i] <= '0;
    end else begin
      // Allocation
      if (alloc_gnt_o) begin
        entries[tail].valid    <= 1'b1;
        entries[tail].done     <= 1'b0;
        entries[tail].rd_used  <= alloc_rd_used_i;
        entries[tail].dest_new <= alloc_dest_new_i;
        entries[tail].dest_old <= alloc_dest_old_i;
        tail                  <= inc_ptr(tail);
        count                 <= count + 1'b1;
      end
      // Completion
      if (cpl_valid_i && entries[cpl_tag_i].valid) begin
        entries[cpl_tag_i].done <= 1'b1;
      end
      // Commit in order
      if (commit_valid_o && commit_ready_i) begin
        entries[head].valid <= 1'b0;
        head               <= inc_ptr(head);
        count              <= count - 1'b1;
      end
    end
  end

  // Checkpoint simply returns the current tail pointer
  always_comb begin
    checkpoint_tail_o = tail;
  end

endmodule