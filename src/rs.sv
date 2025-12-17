//////////////////////////////////////////////////////////////////////////////////
// Module Name: rs
// Description: Reservation station (phase 2/3/4).
//   - enqueues rs_entry_t when space exists
//   - wakes operands on 3 WB buses
//   - selects one ready entry and HOLDS it stable until issue_ready_i=1
// Additional Comments:
//   - critical: do NOT pop unless granted (prevents dropping entries from
//     non-selected RS in top-level arbitration)
//   - FIX (phase 4): on recover_i, squash ONLY entries whose rob_tag is NOT live
//     according to ROB's live_tag bitmap. This avoids wiping older ops and
//     prevents ROB deadlock after branch recovery.
//   - FIX (wakeup-miss): on enqueue, recompute src readiness using *current*
//     PRF valid + current-cycle WB match to avoid "missed wakeup in fifo".
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module rs #(
  parameter int DEPTH = `RS_DEPTH
)(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  flush_i,

  // NEW: recovery squash (phase 4)
  input  logic                  recover_i,
  input  logic [ooop_types::ROB_DEPTH-1:0] live_tag_i,

  // NEW: current PRF valid bits (fix missed wakeup while sitting in fifo)
  input  logic [ooop_types::N_PHYS_REGS-1:0] prf_valid_i,

  // enqueue
  input  logic                   insert_valid_i,
  input  ooop_types::rs_entry_t   insert_entry_i,
  output logic                   ready_o,

  // wakeup sources (3 writeback busses)
  input  ooop_types::wb_pkt_t     wb_alu_i,
  input  ooop_types::wb_pkt_t     wb_lsu_i,
  input  ooop_types::wb_pkt_t     wb_bru_i,

  // issue handshake
  output logic                   issue_valid_o,
  output ooop_types::rs_entry_t   issue_entry_o,
  input  logic                   issue_ready_i
);

  import ooop_types::*;

  localparam int IDX_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);

  rs_entry_t entries  [DEPTH];
  logic      occupied [DEPTH];

  // free + ready masks
  logic [DEPTH-1:0] free_mask;
  logic [DEPTH-1:0] ready_mask;

  logic             free_found;
  logic [IDX_W-1:0] free_idx;

  logic             pick_found;
  logic [IDX_W-1:0] pick_idx;

  // hold selected entry stable when not granted
  logic             hold_valid_q;
  logic [IDX_W-1:0] hold_idx_q;

  function automatic logic match_wb(input wb_pkt_t wb, input logic [PREG_W-1:0] preg);
    match_wb = wb.valid && wb.rd_used && (wb.prd == preg) && (preg != '0);
  endfunction

  function automatic logic preg_is_valid(input logic [PREG_W-1:0] preg);
    if (preg == '0) begin
      preg_is_valid = 1'b1; // x0 always ready
    end else begin
      preg_is_valid = prf_valid_i[preg];
    end
  endfunction

  function automatic logic ready_on_wb(input logic [PREG_W-1:0] preg);
    ready_on_wb =
      match_wb(wb_alu_i, preg) ||
      match_wb(wb_lsu_i, preg) ||
      match_wb(wb_bru_i, preg);
  endfunction

  // build masks + choose lowest index
  always @* begin
    for (int idx = 0; idx < DEPTH; idx = idx + 1) begin
      free_mask[idx]  = !occupied[idx];
      ready_mask[idx] = occupied[idx] && entries[idx].valid &&
                        (!entries[idx].rs1_used || entries[idx].prs1_ready) &&
                        (!entries[idx].rs2_used || entries[idx].prs2_ready);
    end

    free_found = |free_mask;
    free_idx   = '0;
    for (int idx = 0; idx < DEPTH; idx = idx + 1) begin
      if (free_mask[idx]) begin
        free_idx = idx[IDX_W-1:0];
        break;
      end
    end

    pick_found = |ready_mask;
    pick_idx   = '0;
    for (int idx = 0; idx < DEPTH; idx = idx + 1) begin
      if (ready_mask[idx]) begin
        pick_idx = idx[IDX_W-1:0];
        break;
      end
    end

    ready_o = free_found;
  end

  // current selection: held if present, else freshly picked
  logic             sel_valid;
  logic [IDX_W-1:0] sel_idx;

  always @* begin
    if (hold_valid_q) begin
      sel_valid = 1'b1;
      sel_idx   = hold_idx_q;
    end else begin
      sel_valid = pick_found;
      sel_idx   = pick_idx;
    end
  end

  // issue outputs always reflect sel_*
  always @* begin
    issue_valid_o = sel_valid;
    issue_entry_o = sel_valid ? entries[sel_idx] : '0;
  end

  wire issue_fire = sel_valid && issue_ready_i;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hold_valid_q <= 1'b0;
      hold_idx_q   <= '0;
      for (int idx = 0; idx < DEPTH; idx = idx + 1) begin
        occupied[idx] <= 1'b0;
        entries[idx]  <= '0;
      end

    end else if (flush_i) begin
      hold_valid_q <= 1'b0;
      hold_idx_q   <= '0;
      for (int idx = 0; idx < DEPTH; idx = idx + 1) begin
        occupied[idx] <= 1'b0;
        entries[idx]  <= '0;
      end

    end else if (recover_i) begin
      // squash only entries that are not in the ROB anymore
      // and drop any held selection if it got squashed.
      for (int idx = 0; idx < DEPTH; idx = idx + 1) begin
        if (occupied[idx]) begin
          if (!live_tag_i[entries[idx].rob_tag]) begin
            occupied[idx] <= 1'b0;
            entries[idx]  <= '0;
          end
        end
      end

      if (hold_valid_q) begin
        if (!occupied[hold_idx_q] || !live_tag_i[entries[hold_idx_q].rob_tag]) begin
          hold_valid_q <= 1'b0;
          hold_idx_q   <= '0;
        end
      end

    end else begin
      // wakeup existing entries
      for (int idx = 0; idx < DEPTH; idx = idx + 1) begin
        if (occupied[idx]) begin
          if (!entries[idx].prs1_ready) begin
            if (ready_on_wb(entries[idx].prs1)) begin
              entries[idx].prs1_ready <= 1'b1;
            end
          end
          if (!entries[idx].prs2_ready) begin
            if (ready_on_wb(entries[idx].prs2)) begin
              entries[idx].prs2_ready <= 1'b1;
            end
          end
        end
      end

      // hold behavior
      if (!hold_valid_q && pick_found && !issue_ready_i) begin
        hold_valid_q <= 1'b1;
        hold_idx_q   <= pick_idx;
      end

      // dequeue ONLY on grant
      if (issue_fire) begin
        occupied[sel_idx] <= 1'b0;
        entries[sel_idx]  <= '0;
        hold_valid_q      <= 1'b0;
      end

      // enqueue (FIX: recompute readiness using *current* PRF valid + same-cycle WB)
      if (insert_valid_i && ready_o) begin
        rs_entry_t ins;
        ins = insert_entry_i;

        ins.prs1_ready = insert_entry_i.prs1_ready ||
                         preg_is_valid(insert_entry_i.prs1) ||
                         ready_on_wb(insert_entry_i.prs1);

        ins.prs2_ready = insert_entry_i.prs2_ready ||
                         preg_is_valid(insert_entry_i.prs2) ||
                         ready_on_wb(insert_entry_i.prs2);

        occupied[free_idx] <= 1'b1;
        entries[free_idx]  <= ins;
      end
    end
  end

endmodule
