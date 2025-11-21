////////////////////////////////////////////////////////////////////////////////
// Module: dispatch
// Description: Dispatch stage for the out‑of‑order CPU.  The dispatch
// receives renamed instructions and assigns them to the appropriate
// reservation station.  It also allocates an entry in the reorder buffer
// and updates the physical register file validity when a destination is
// assigned.  A one‑entry skid buffer is used to hold the incoming rename
// packet when reservation stations or the ROB are full.  Completion of
// instructions via the CDB marks entries done in the ROB; commit
// automatically drains completed entries.  This module does not perform
// execution – it merely routes instructions to the RS and manages book
// keeping.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module dispatch (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 flush_i,

  // From rename
  input  logic                 valid_in,
  output logic                 ready_out,
  input  rename_pkt_t          pkt_in,

  // Execution unit readiness (one per FU type)
  input  logic                 alu_exec_ready_i,
  input  logic                 lsu_exec_ready_i,
  input  logic                 bru_exec_ready_i,

  // Common data bus (CDB) feedback
  input  logic                 cdb_valid_i,
  input  logic [PREG_W-1:0]    cdb_tag_i,
  input  logic [XLEN-1:0]      cdb_data_i,

  // Optional debug taps
  output logic                 fire_o,
  output rename_pkt_t          fired_pkt_o,

  // Issue outputs to execution units
  output logic                 alu_issue_valid_o,
  output issue_pkt_t           alu_issue_pkt_o,
  output logic                 lsu_issue_valid_o,
  output issue_pkt_t           lsu_issue_pkt_o,
  output logic                 bru_issue_valid_o,
  output issue_pkt_t           bru_issue_pkt_o,

  // PRF valid bits to feed rename
  output logic [N_PHYS_REGS-1:0] prf_valid_o,

  // ROB commit outputs
  output logic                 rob_commit_valid_o,
  output logic [ROB_TAG_W-1:0] rob_commit_tag_o,
  output logic                 rob_commit_rd_used_o,
  output logic [PREG_W-1:0]    rob_commit_dest_new_o,
  output logic [PREG_W-1:0]    rob_commit_dest_old_o
);

  // Width of rename packet for skidbuffer
  localparam int PKT_W = $bits(rename_pkt_t);

  // -----------------------
  // Skid buffer to hold rename packet when resources are busy
  // -----------------------
  logic [PKT_W-1:0] buf_bus_in, buf_bus_out;
  logic buf_valid;
  logic buf_ready_in, buf_ready_out;

  assign buf_bus_in = pkt_in;

  skidbuffer #(.DATA_WIDTH(PKT_W)) i_disp_skid (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (flush_i),
    .valid_in  (valid_in),
    .ready_in  (ready_out),    // handshake to rename
    .data_in   (buf_bus_in),
    .valid_out (buf_valid),
    .ready_out (buf_ready_out),// handshake to dispatch logic
    .data_out  (buf_bus_out)
  );

  // Cast skid buffer output back to rename packet
  rename_pkt_t buf_pkt;
  assign buf_pkt = rename_pkt_t'(buf_bus_out);

  // -----------------------
  // Physical register file
  // -----------------------
  logic prf_inv_valid;
  logic [PREG_W-1:0] prf_inv_tag;

  prf #(.NUM_READ(4)) i_prf (
    .clk         (clk),
    .rst_n       (rst_n),
    .inv_valid_i (prf_inv_valid),
    .inv_tag_i   (prf_inv_tag),
    .wb_valid_i  (cdb_valid_i),
    .wb_tag_i    (cdb_tag_i),
    .wb_data_i   (cdb_data_i),
    .rtag_i      ('0),
    .rdata_o     (),
    .valid_o     (prf_valid_o)
  );

  // -----------------------
  // Reservation stations
  // -----------------------
  logic alu_push_ready, lsu_push_ready, bru_push_ready;
  logic alu_push_valid, lsu_push_valid, bru_push_valid;

  rs_alu i_rs_alu (
    .clk           (clk),
    .rst_n         (rst_n),
    .flush_i       (flush_i),
    .push_valid_i  (alu_push_valid),
    .push_ready_o  (alu_push_ready),
    .push_pkt_i    (buf_pkt),
    .push_rob_tag_i(rob_alloc_tag),
    .wakeup_valid_i(cdb_valid_i),
    .wakeup_tag_i  (cdb_tag_i),
    .exec_ready_i  (alu_exec_ready_i),
    .issue_valid_o (alu_issue_valid_o),
    .issue_pkt_o   (alu_issue_pkt_o)
  );

  rs_lsu i_rs_lsu (
    .clk           (clk),
    .rst_n         (rst_n),
    .flush_i       (flush_i),
    .push_valid_i  (lsu_push_valid),
    .push_ready_o  (lsu_push_ready),
    .push_pkt_i    (buf_pkt),
    .push_rob_tag_i(rob_alloc_tag),
    .wakeup_valid_i(cdb_valid_i),
    .wakeup_tag_i  (cdb_tag_i),
    .exec_ready_i  (lsu_exec_ready_i),
    .issue_valid_o (lsu_issue_valid_o),
    .issue_pkt_o   (lsu_issue_pkt_o)
  );

  rs_bru i_rs_bru (
    .clk           (clk),
    .rst_n         (rst_n),
    .flush_i       (flush_i),
    .push_valid_i  (bru_push_valid),
    .push_ready_o  (bru_push_ready),
    .push_pkt_i    (buf_pkt),
    .push_rob_tag_i(rob_alloc_tag),
    .wakeup_valid_i(cdb_valid_i),
    .wakeup_tag_i  (cdb_tag_i),
    .exec_ready_i  (bru_exec_ready_i),
    .issue_valid_o (bru_issue_valid_o),
    .issue_pkt_o   (bru_issue_pkt_o)
  );

  // Determine if target reservation station has space
  logic target_rs_ready;
  always_comb begin
    unique case (buf_pkt.fu_type)
      FU_ALU: target_rs_ready = alu_push_ready;
      FU_LSU: target_rs_ready = lsu_push_ready;
      FU_BRU: target_rs_ready = bru_push_ready;
      default: target_rs_ready = 1'b0;
    endcase
  end

  // -----------------------
  // Reorder buffer
  // -----------------------
  logic rob_alloc_req;
  logic rob_alloc_gnt;
  logic [ROB_TAG_W-1:0] rob_alloc_tag;
  logic rob_full;
  logic rob_cpl_valid;
  logic [ROB_TAG_W-1:0] rob_cpl_tag;
  logic rob_checkpoint_req;
  logic [ROB_TAG_W-1:0] rob_checkpoint_tail;

  rob i_rob (
    .clk              (clk),
    .rst_n            (rst_n),
    .flush_i          (flush_i),
    .alloc_req_i      (rob_alloc_req),
    .alloc_gnt_o      (rob_alloc_gnt),
    .alloc_tag_o      (rob_alloc_tag),
    .alloc_rd_used_i  (buf_pkt.rd_used),
    .alloc_dest_new_i (buf_pkt.rd_new_tag),
    .alloc_dest_old_i (buf_pkt.rd_old_tag),
    .full_o           (rob_full),
    .cpl_valid_i      (rob_cpl_valid),
    .cpl_tag_i        (rob_cpl_tag),
    .commit_ready_i   (1'b1), // auto‑commit in this phase
    .commit_valid_o   (rob_commit_valid_o),
    .commit_tag_o     (rob_commit_tag_o),
    .commit_rd_used_o (rob_commit_rd_used_o),
    .commit_dest_new_o(rob_commit_dest_new_o),
    .commit_dest_old_o(rob_commit_dest_old_o),
    .checkpoint_req_i (rob_checkpoint_req),
    .checkpoint_tail_o(rob_checkpoint_tail)
  );

  // -----------------------
  // Dispatch decision logic
  // -----------------------
  logic can_dispatch;
  assign can_dispatch = buf_valid && !rob_full && target_rs_ready;

  // Skidbuffer downstream ready
  assign buf_ready_out = can_dispatch;

  // Fire indicates the cycle we actually dispatch an instruction
  assign fire_o      = can_dispatch;
  assign fired_pkt_o = buf_pkt;

  // ROB allocation request when we dispatch
  assign rob_alloc_req = fire_o;

  // Drive push valids based on FU type and dispatch
  always_comb begin
    alu_push_valid = fire_o && (buf_pkt.fu_type == FU_ALU);
    lsu_push_valid = fire_o && (buf_pkt.fu_type == FU_LSU);
    bru_push_valid = fire_o && (buf_pkt.fu_type == FU_BRU);
  end

  // Invalidate PRF destination on dispatch
  assign prf_inv_valid = fire_o && buf_pkt.rd_used;
  assign prf_inv_tag   = buf_pkt.rd_new_tag;

  // Checkpoint on branches – record ROB tail pointer for potential recovery
  assign rob_checkpoint_req = fire_o && buf_pkt.is_branch;

  // -----------------------
  // Completion tracking – mark ROB entry done when issued
  // This simple logic completes at most one instruction per cycle.
  // -----------------------
  always_comb begin
    rob_cpl_valid = 1'b0;
    rob_cpl_tag   = '0;
    if (alu_issue_valid_o && alu_exec_ready_i) begin
      rob_cpl_valid = 1'b1;
      rob_cpl_tag   = alu_issue_pkt_o.rob_tag;
    end else if (bru_issue_valid_o && bru_exec_ready_i) begin
      rob_cpl_valid = 1'b1;
      rob_cpl_tag   = bru_issue_pkt_o.rob_tag;
    end else if (lsu_issue_valid_o && lsu_exec_ready_i) begin
      rob_cpl_valid = 1'b1;
      rob_cpl_tag   = lsu_issue_pkt_o.rob_tag;
    end
  end

endmodule