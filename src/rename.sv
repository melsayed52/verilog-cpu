//////////////////////////////////////////////////////////////////////////////////
// Module Name: rename
// Description: Rename stage (Phase 4).
// Additional Comments:
//   - FIX: tag allocation is collision-robust via external rob_tag_alloc.
//   - FIX: ready_out is gated by both free-reg availability and tag availability.
//   - Option A: rob_tag is provided as an input (rob_tag_i) from core_top.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module rename #(
  parameter int N_ARCH_REGS = ooop_types::N_ARCH_REGS,
  parameter int N_PHYS_REGS = ooop_types::N_PHYS_REGS,
  parameter int ROB_DEPTH   = ooop_types::ROB_DEPTH
)(
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   flush_i,

  input  logic                   recover_i,
  input  logic [ooop_types::ROB_W-1:0] recover_tag_i,

  // from decode
  input  logic                   valid_in,
  output logic                   ready_out,
  input  ooop_types::decode_pkt_t pkt_in,

  // to dispatch
  output logic                   valid_out,
  input  logic                   ready_in,
  output ooop_types::rename_pkt_t pkt_out,

  // PRF ready bits
  input  logic [N_PHYS_REGS-1:0] prf_valid_i,

  // free from ROB commit
  input  logic                   free_req_i,
  input  logic [ooop_types::PREG_W-1:0] free_preg_i,

  // invalidate newly allocated PRD in PRF
  output logic                   alloc_inval_o,
  output logic [ooop_types::PREG_W-1:0] alloc_preg_o,

  // checkpoint broadcast
  output logic                   checkpoint_take_o,
  output logic [ooop_types::ROB_W-1:0] checkpoint_tag_o,

  // NEW: tag allocator status and selected tag from core_top
  input  logic                   tag_ok_i,
  input  logic [ooop_types::ROB_W-1:0] rob_tag_i
);

  import ooop_types::*;

  localparam int PHYS_W = $clog2(N_PHYS_REGS);

  // RAT lookups
  logic [PHYS_W-1:0] rs1_phys, rs2_phys, rd_old_phys;

  // free list alloc
  logic              alloc_req;
  logic              alloc_gnt;
  logic [PHYS_W-1:0] alloc_preg;
  logic              has_free;

  // need a dest allocation?
  wire need_alloc = pkt_in.rd_used && (pkt_in.rd != '0);

  // gate on free preg and free tag
  wire alloc_ok = (!need_alloc) || has_free;
  wire tag_ok   = tag_ok_i;

  // handshake
  assign ready_out = ready_in && alloc_ok && tag_ok;
  assign valid_out = valid_in && alloc_ok && tag_ok;
  wire fire = valid_in && ready_out;

  // request allocation only when instruction advances
  assign alloc_req = fire && need_alloc;

  // checkpoint on branch/jump only when instruction advances
  wire checkpoint_take = fire && (pkt_in.is_branch || pkt_in.is_jump);
  assign checkpoint_take_o = checkpoint_take;
  assign checkpoint_tag_o  = rob_tag_i;

  map_table #(
    .N_ARCH_REGS(N_ARCH_REGS),
    .N_PHYS_REGS(N_PHYS_REGS),
    .ROB_DEPTH  (ROB_DEPTH)
  ) mt0 (
    .clk             (clk),
    .rst_n           (rst_n),
    .flush_i         (flush_i),

    .recover_i       (recover_i),
    .recover_tag_i   (recover_tag_i),

    .rs1_arch        (pkt_in.rs1),
    .rs2_arch        (pkt_in.rs2),
    .rd_arch         (pkt_in.rd),

    .rs1_phys        (rs1_phys),
    .rs2_phys        (rs2_phys),
    .rd_old_phys     (rd_old_phys),

    .we              (alloc_gnt),
    .we_arch         (pkt_in.rd),
    .we_new_phys     (alloc_preg),

    .checkpoint_take (checkpoint_take),
    .checkpoint_tag  (rob_tag_i)
  );

  free_list_bitmap #(
    .N_ARCH_REGS(N_ARCH_REGS),
    .N_PHYS_REGS(N_PHYS_REGS),
    .ROB_DEPTH  (ROB_DEPTH)
  ) fl0 (
    .clk             (clk),
    .rst_n           (rst_n),
    .flush_i         (flush_i),

    .recover_i       (recover_i),
    .recover_tag_i   (recover_tag_i),

    .alloc_req       (alloc_req),
    .alloc_gnt       (alloc_gnt),
    .alloc_preg      (alloc_preg),
    .has_free_o      (has_free),

    .free_req        (free_req_i),
    .free_preg       (free_preg_i),

    .checkpoint_take (checkpoint_take),
    .checkpoint_tag  (rob_tag_i),

    .free_bitmap_o   ()
  );

  function automatic logic preg_ready(input logic [PHYS_W-1:0] p);
    if (p == '0) preg_ready = 1'b1;
    else         preg_ready = prf_valid_i[p];
  endfunction

  // PRF invalidation on successful dest alloc (except x0)
  assign alloc_inval_o = alloc_gnt;
  assign alloc_preg_o  = alloc_gnt ? alloc_preg : '0;

  always @* begin
    pkt_out = '0;

    pkt_out.valid         = valid_out;

    pkt_out.pc            = pkt_in.pc;
    pkt_out.instr         = pkt_in.instr;

    pkt_out.rs1           = pkt_in.rs1;
    pkt_out.rs2           = pkt_in.rs2;
    pkt_out.rd            = pkt_in.rd;

    pkt_out.imm           = pkt_in.imm;
    pkt_out.imm_used      = pkt_in.imm_used;

    pkt_out.fu_type       = pkt_in.fu_type;
    pkt_out.alu_op        = pkt_in.alu_op;

    pkt_out.rd_used       = need_alloc;

    pkt_out.is_load       = pkt_in.is_load;
    pkt_out.is_store      = pkt_in.is_store;
    pkt_out.ls_size       = pkt_in.ls_size;
    pkt_out.unsigned_load = pkt_in.unsigned_load;

    pkt_out.is_branch     = pkt_in.is_branch;
    pkt_out.is_jump       = pkt_in.is_jump;
    pkt_out.is_jalr       = pkt_in.is_jalr;

    pkt_out.rs1_used      = pkt_in.rs1_used;
    pkt_out.rs2_used      = pkt_in.rs2_used;

    pkt_out.prs1          = rs1_phys;
    pkt_out.prs2          = rs2_phys;

    pkt_out.prs1_ready    = preg_ready(rs1_phys);
    pkt_out.prs2_ready    = preg_ready(rs2_phys);

    pkt_out.prd           = need_alloc ? alloc_preg  : '0;
    pkt_out.old_prd       = need_alloc ? rd_old_phys : '0;

    pkt_out.rob_tag       = rob_tag_i;
  end

endmodule
