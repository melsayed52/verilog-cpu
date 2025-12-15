//////////////////////////////////////////////////////////////////////////////////
// Module Name: checkpoint_types
// Description: Common checkpoint storage types for Phase 4 recovery.
// Additional Comments:
//   - checkpoints are indexed by ROB tag (ROB_W bits)
//   - snapshots are taken "after renaming" the branch/jump instruction
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

package checkpoint_types;

  import ooop_types::*;

  // RAT snapshot: for each architectural register, store its physical mapping
  typedef logic [N_ARCH_REGS-1:0][PREG_W-1:0] rat_snapshot_t;

  // Free list snapshot: 1 means free, 0 means allocated
  typedef logic [N_PHYS_REGS-1:0] freelist_snapshot_t;

  // PRF valid snapshot: 1 means ready
  typedef logic [N_PHYS_REGS-1:0] prf_valid_snapshot_t;

  // ROB pointers snapshot (enough to truncate younger ops on recovery)
  typedef struct packed {
    logic [ROB_W-1:0] head;
    logic [ROB_W-1:0] tail;
    logic [ROB_W:0]   count;
  } rob_ptrs_snapshot_t;

  // ROB tag allocator snapshot: next tag counter
  typedef logic [ROB_W-1:0] rob_tag_snapshot_t;

endpackage
