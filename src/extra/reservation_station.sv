////////////////////////////////////////////////////////////////////////////////
// Module: reservation_station
// Description: Generic reservation station with free and ready slot selection.
//
// A reservation station buffers renamed instructions until both of their
// operands become ready and the corresponding execution unit is free.  Each
// reservation station instance is parameterised by its depth (number of
// entries).  Incoming instructions are pushed into the first free slot as
// indicated by a priority decoder; ready instructions are issued out of
// the first entry whose operands are ready.  Wakeup events from the
// common data bus update operand readiness for all entries.  On a flush
// all entries are cleared.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module reservation_station #(
  parameter int DEPTH = 8
)(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          flush_i,

  // Push interface from dispatch
  input  logic          push_valid_i,
  output logic          push_ready_o,
  input  rename_pkt_t   push_pkt_i,
  input  logic [ROB_TAG_W-1:0] push_rob_tag_i,

  // Wakeup input from common data bus (CDB)
  input  logic          wakeup_valid_i,
  input  logic [PREG_W-1:0] wakeup_tag_i,

  // Issue interface to execution unit
  input  logic          exec_ready_i,
  output logic          issue_valid_o,
  output issue_pkt_t    issue_pkt_o
);

  // Define per‑entry structure
  typedef struct packed {
    logic               valid;
    logic [31:0]        pc;
    logic [1:0]         fu_type;
    logic [3:0]         alu_op;
    logic [XLEN-1:0]    imm;
    logic               imm_used;
    logic               is_load;
    logic               is_store;
    logic [1:0]         ls_size;
    logic               unsigned_load;
    logic               is_branch;
    logic               is_jump;
    logic [ROB_TAG_W-1:0] rob_tag;
    logic [PREG_W-1:0]  rs1_tag;
    logic               rs1_ready;
    logic [PREG_W-1:0]  rs2_tag;
    logic               rs2_ready;
    logic               rd_used;
    logic [PREG_W-1:0]  rd_tag;
  } rs_entry_t;

  // Storage array
  rs_entry_t entries [0:DEPTH-1];

  // Determine free slots (true when entry.valid == 0)
  logic [DEPTH-1:0] free_vec;
  logic [$clog2(DEPTH)-1:0] free_idx;
  logic free_valid;

  genvar fi;
  generate
    for (fi = 0; fi < DEPTH; fi++) begin : GEN_FREE
      always_comb free_vec[fi] = ~entries[fi].valid;
    end
  endgenerate

  priority_decoder #(.WIDTH(DEPTH)) i_free_pd (
    .in    (free_vec),
    .out   (free_idx),
    .valid (free_valid)
  );

  assign push_ready_o = free_valid;

  // Determine ready entries (valid and both operands ready)
  logic [DEPTH-1:0] ready_vec;
  logic [$clog2(DEPTH)-1:0] issue_idx;
  logic ready_valid;

  genvar ri;
  generate
    for (ri = 0; ri < DEPTH; ri++) begin : GEN_READY
      always_comb ready_vec[ri] = entries[ri].valid && entries[ri].rs1_ready && entries[ri].rs2_ready;
    end
  endgenerate

  priority_decoder #(.WIDTH(DEPTH)) i_issue_pd (
    .in    (ready_vec),
    .out   (issue_idx),
    .valid (ready_valid)
  );

  assign issue_valid_o = ready_valid;

  // Pack issue packet
  always_comb begin
    issue_pkt_o = '0;
    if (ready_valid) begin
      issue_pkt_o.pc            = entries[issue_idx].pc;
      issue_pkt_o.fu_type       = entries[issue_idx].fu_type;
      issue_pkt_o.alu_op        = entries[issue_idx].alu_op;
      issue_pkt_o.imm           = entries[issue_idx].imm;
      issue_pkt_o.imm_used      = entries[issue_idx].imm_used;
      issue_pkt_o.is_load       = entries[issue_idx].is_load;
      issue_pkt_o.is_store      = entries[issue_idx].is_store;
      issue_pkt_o.ls_size       = entries[issue_idx].ls_size;
      issue_pkt_o.unsigned_load = entries[issue_idx].unsigned_load;
      issue_pkt_o.is_branch     = entries[issue_idx].is_branch;
      issue_pkt_o.is_jump       = entries[issue_idx].is_jump;
      issue_pkt_o.rob_tag       = entries[issue_idx].rob_tag;
      issue_pkt_o.rs1_tag       = entries[issue_idx].rs1_tag;
      issue_pkt_o.rs2_tag       = entries[issue_idx].rs2_tag;
      issue_pkt_o.rd_used       = entries[issue_idx].rd_used;
      issue_pkt_o.rd_tag        = entries[issue_idx].rd_tag;
    end
  end

  // Issue fire – both ready_valid and exec_ready_i must be true
  wire issue_fire = issue_valid_o && exec_ready_i;

  // Sequential logic
  integer k;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (k = 0; k < DEPTH; k++) entries[k] <= '0;
    end else begin
      if (flush_i) begin
        for (k = 0; k < DEPTH; k++) entries[k] <= '0;
      end else begin
        // Pop on issue
        if (issue_fire) begin
          entries[issue_idx].valid <= 1'b0;
        end
        // Update operand readiness on wakeup
        if (wakeup_valid_i) begin
          for (k = 0; k < DEPTH; k++) begin
            if (entries[k].valid) begin
              if (!entries[k].rs1_ready && entries[k].rs1_tag == wakeup_tag_i)
                entries[k].rs1_ready <= 1'b1;
              if (!entries[k].rs2_ready && entries[k].rs2_tag == wakeup_tag_i)
                entries[k].rs2_ready <= 1'b1;
            end
          end
        end
        // Push new entry
        if (push_valid_i && push_ready_o) begin
          entries[free_idx].valid         <= 1'b1;
          entries[free_idx].pc            <= push_pkt_i.pc;
          entries[free_idx].fu_type       <= push_pkt_i.fu_type;
          entries[free_idx].alu_op        <= push_pkt_i.alu_op;
          entries[free_idx].imm           <= push_pkt_i.imm;
          entries[free_idx].imm_used      <= push_pkt_i.imm_used;
          entries[free_idx].is_load       <= push_pkt_i.is_load;
          entries[free_idx].is_store      <= push_pkt_i.is_store;
          entries[free_idx].ls_size       <= push_pkt_i.ls_size;
          entries[free_idx].unsigned_load <= push_pkt_i.unsigned_load;
          entries[free_idx].is_branch     <= push_pkt_i.is_branch;
          entries[free_idx].is_jump       <= push_pkt_i.is_jump;
          entries[free_idx].rob_tag       <= push_rob_tag_i;
          entries[free_idx].rs1_tag       <= push_pkt_i.rs1_tag;
          entries[free_idx].rs1_ready     <= push_pkt_i.rs1_ready;
          entries[free_idx].rs2_tag       <= push_pkt_i.rs2_tag;
          entries[free_idx].rs2_ready     <= push_pkt_i.rs2_ready;
          entries[free_idx].rd_used       <= push_pkt_i.rd_used;
          entries[free_idx].rd_tag        <= push_pkt_i.rd_new_tag;
        end
      end
    end
  end

endmodule