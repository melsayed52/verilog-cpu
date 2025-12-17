//////////////////////////////////////////////////////////////////////////////////
// Module Name: dispatch
// Description: Dispatch stage.
//   - buffers rename packet in a 1-entry fifo (dispatch_fifo)
//   - inserts into one of 3 RS based on fu_type
//   - allocates one ROB entry in the same cycle as RS insert
// Additional Comments:
//   - phase 3: no flush/recover used (but keeps flush_i for interface)
//   - backpressure if target RS full or ROB full
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module dispatch (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   flush_i,

  // from rename
  input  logic                   valid_in,
  output logic                   ready_out,
  input  ooop_types::rename_pkt_t pkt_in,

  // RS space
  input  logic                   rs_alu_ready_i,
  input  logic                   rs_bru_ready_i,
  input  logic                   rs_lsu_ready_i,

  // to RS inserts
  output logic                   rs_alu_valid_o,
  output ooop_types::rs_entry_t   rs_alu_entry_o,

  output logic                   rs_bru_valid_o,
  output ooop_types::rs_entry_t   rs_bru_entry_o,

  output logic                   rs_lsu_valid_o,
  output ooop_types::rs_entry_t   rs_lsu_entry_o,

  // ROB allocate
  input  logic                   rob_ready_i,
  output logic                   rob_alloc_valid_o,
  output ooop_types::rename_pkt_t rob_alloc_pkt_o
);

  import ooop_types::*;

  // ---------------------------------------------------------------------------
  // 1-entry fifo between rename and dispatch routing
  // ---------------------------------------------------------------------------
  logic        f_in_ready;
  logic        f_out_valid;
  rename_pkt_t f_out_pkt;
  logic        f_out_ready;

  dispatch_fifo fifo_u (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (flush_i),

    .in_valid  (valid_in),
    .in_ready  (f_in_ready),
    .in_pkt    (pkt_in),

    .out_valid (f_out_valid),
    .out_ready (f_out_ready),
    .out_pkt   (f_out_pkt)
  );

  assign ready_out = f_in_ready;

  // ---------------------------------------------------------------------------
  // choose target RS space
  // ---------------------------------------------------------------------------
  logic rs_space_ok;

  always @* begin
    rs_space_ok = 1'b0;
    unique case (f_out_pkt.fu_type)
      FU_ALU: rs_space_ok = rs_alu_ready_i;
      FU_BRU: rs_space_ok = rs_bru_ready_i;
      FU_LSU: rs_space_ok = rs_lsu_ready_i;
      default: rs_space_ok = 1'b0;
    endcase
  end

  // dispatch fires only when fifo valid, ROB ready, and target RS has space
  // BUG 6 FIX: Do NOT dispatch during flush (which happens during recovery)
  wire fire = f_out_valid && rob_ready_i && rs_space_ok && !flush_i;
  assign f_out_ready = fire;

  // ---------------------------------------------------------------------------
  // build rs_entry_t from rename pkt
  // ---------------------------------------------------------------------------
  rs_entry_t entry;

  always @* begin
    entry = '0;

    entry.valid         = fire;
    entry.pc            = f_out_pkt.pc;
    entry.instr         = f_out_pkt.instr;

    entry.fu_type       = f_out_pkt.fu_type;
    entry.alu_op        = f_out_pkt.alu_op;

    entry.imm           = f_out_pkt.imm;
    entry.imm_used      = f_out_pkt.imm_used;

    entry.rd_used       = f_out_pkt.rd_used;

    entry.is_load       = f_out_pkt.is_load;
    entry.is_store      = f_out_pkt.is_store;
    entry.ls_size       = f_out_pkt.ls_size;
    entry.unsigned_load = f_out_pkt.unsigned_load;

    entry.is_branch     = f_out_pkt.is_branch;
    entry.is_jump       = f_out_pkt.is_jump;
    entry.is_jalr       = f_out_pkt.is_jalr;
    entry.funct3        = f_out_pkt.funct3;
    entry.predicted_taken  = f_out_pkt.predicted_taken;
    entry.predicted_target = f_out_pkt.predicted_target;

    entry.rs1_used      = f_out_pkt.rs1_used;
    entry.rs2_used      = f_out_pkt.rs2_used;

    entry.prs1          = f_out_pkt.prs1;
    entry.prs2          = f_out_pkt.prs2;
    entry.prd           = f_out_pkt.prd;

    entry.prs1_ready    = f_out_pkt.prs1_ready;
    entry.prs2_ready    = f_out_pkt.prs2_ready;

    entry.rob_tag       = f_out_pkt.rob_tag;
  end

  // ---------------------------------------------------------------------------
  // defaults
  // ---------------------------------------------------------------------------
  always @* begin
    rs_alu_valid_o   = 1'b0;
    rs_bru_valid_o   = 1'b0;
    rs_lsu_valid_o   = 1'b0;

    rs_alu_entry_o   = '0;
    rs_bru_entry_o   = '0;
    rs_lsu_entry_o   = '0;

    if (fire) begin
      unique case (f_out_pkt.fu_type)
        FU_ALU: begin
          rs_alu_valid_o = 1'b1;
          rs_alu_entry_o = entry;
        end
        FU_BRU: begin
          rs_bru_valid_o = 1'b1;
          rs_bru_entry_o = entry;
        end
        FU_LSU: begin
          rs_lsu_valid_o = 1'b1;
          rs_lsu_entry_o = entry;
        end
        default: begin end
      endcase
    end
  end

  // ROB allocate mirrors same-cycle fire
  assign rob_alloc_valid_o = fire;
  assign rob_alloc_pkt_o   = f_out_pkt;

endmodule
