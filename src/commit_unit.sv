//////////////////////////////////////////////////////////////////////////////////
// Module Name: commit_unit
// Description: Thin commit-stage wrapper around the ROB commit interface.
//              For Phase 3 this simply acknowledges commits and produces
//              optional signals for freeing old physical registers. In
//              later phases, this is where RAT / freelist / architectural
//              state update logic can be integrated.
// Additional Comments:
//   - Connect the ROB's commit_* outputs to the rob_commit_*_i ports here.
//   - Feed commit_ready_o back into ROB.commit_ready_i.
//   - free_old_tag_* outputs are useful for a future freelist.
//
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"

module commit_unit (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 flush_i,

  // From ROB
  input  logic                 rob_commit_valid_i,
  input  logic [ROB_TAG_W-1:0] rob_commit_tag_i,
  input  logic                 rob_commit_rd_used_i,
  input  logic [PREG_W-1:0]    rob_commit_dest_new_i,
  input  logic [PREG_W-1:0]    rob_commit_dest_old_i,

  // Back-pressure to ROB
  output logic                 commit_ready_o,

  // Outputs for future freelist / RAT recovery
  output logic                 free_old_tag_valid_o,
  output logic [PREG_W-1:0]    free_old_tag_o,

  // Optional debug taps
  output logic                 commit_event_o,
  output logic [ROB_TAG_W-1:0] commit_rob_tag_o,
  output logic [PREG_W-1:0]    commit_dest_new_o,
  output logic [PREG_W-1:0]    commit_dest_old_o
);

  // For Phase 3 we always accept commits (no extra back-pressure).
  assign commit_ready_o = 1'b1;

  // Free-list style output: when a committing instruction had an rd,
  // the old physical tag can be recycled.
  assign free_old_tag_valid_o = rob_commit_valid_i && rob_commit_rd_used_i;
  assign free_old_tag_o       = rob_commit_dest_old_i;

  // Optional debug taps
  assign commit_event_o     = rob_commit_valid_i;
  assign commit_rob_tag_o   = rob_commit_tag_i;
  assign commit_dest_new_o  = rob_commit_dest_new_i;
  assign commit_dest_old_o  = rob_commit_dest_old_i;

endmodule
