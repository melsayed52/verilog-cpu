////////////////////////////////////////////////////////////////////////////////
// Module: top_phase2
// Description: Integration of fetch, decode, rename and dispatch for Phase 2.
//
// This top module instantiates the instruction cache, fetch stage,
// decode stage, a skidbuffer between decode and rename, the rename
// module and the dispatch module.  It exposes a few taps to the test bench
// so that rename and dispatch events can be monitored.  Execution units
// are assumed always ready in this phase and no common data bus feedback
// occurs (cdb_valid_i is tied to 0).  For proper operation the ICACHE
// should be initialised with a program hex file.  Branch redirects are
// disabled; the PC increments linearly.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module top_phase2 #(
  parameter int     MEM_DEPTH = 512,
  parameter string  INIT_FILE = "../mem/program.hex",
  parameter logic [31:0] PC_RESET = 32'h0000_0000
)(
  input  logic clk,
  input  logic rst_n,

  // debug taps
  output logic ren_valid_o,
  output logic ren_ready_o,
  output logic disp_fire_o,
  output rename_pkt_t disp_pkt_o,
  output logic alu_issue_v_o,
  output issue_pkt_t alu_issue_pkt_o
);

  // ---------------- i‑cache, fetch ----------------
  wire [31:2] ic_index;
  wire        ic_en;
  wire [31:0] ic_rdata;
  wire        ic_rvalid;

  icache #(.MEM_DEPTH(MEM_DEPTH), .INIT_FILE(INIT_FILE)) i_icache (
    .clk    (clk),
    .rst_n  (rst_n),
    .index  (ic_index),
    .en     (ic_en),
    .rdata  (ic_rdata),
    .rvalid (ic_rvalid)
  );

  wire [31:0] f_pc, f_instr;
  wire        f_valid, f_ready;

  fetch #(.PC_RESET(PC_RESET)) i_fetch (
    .clk            (clk),
    .rst_n          (rst_n),
    .pc_redir_valid (1'b0),
    .pc_redir_target('0),
    .icache_index   (ic_index),
    .icache_en      (ic_en),
    .icache_rdata   (ic_rdata),
    .icache_rvalid  (ic_rvalid),
    .pc             (f_pc),
    .instr          (f_instr),
    .valid          (f_valid),
    .ready          (f_ready)
  );

  // ---------------- skid IF → decode ----------------
  localparam int IF_BUS_W = 64;
  wire [IF_BUS_W-1:0] if_bus_in  = {f_pc, f_instr};
  wire [IF_BUS_W-1:0] if_bus_out;
  wire                if_valid;
  wire                if_ready;

  skidbuffer #(.DATA_WIDTH(IF_BUS_W)) i_skid_if (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (1'b0),
    .valid_in  (f_valid),
    .ready_in  (f_ready),
    .data_in   (if_bus_in),
    .valid_out (if_valid),
    .ready_out (if_ready),
    .data_out  (if_bus_out)
  );

  wire [31:0] if_pc;
  wire [31:0] if_instr_o;
  assign {if_pc, if_instr_o} = if_bus_out;

  // ---------------- decode comb ----------------
  wire        d_valid_out;
  wire [31:0] d_pc_out;
  wire [4:0]  rs1_arch, rs2_arch, rd_arch;
  wire [31:0] imm;
  wire        imm_used;
  wire [1:0]  fu_type;
  wire [3:0]  alu_op;
  wire        rd_used;
  wire        is_load, is_store, unsigned_load, is_branch, is_jump;
  wire [1:0]  ls_size;

  decode i_decode (
    .valid_in  (if_valid),
    .pc_in     (if_pc),
    .instr_in  (if_instr_o),
    .ready_out (),
    .valid_out (d_valid_out),
    .pc_out    (d_pc_out),
    .rs1       (rs1_arch),
    .rs2       (rs2_arch),
    .rd        (rd_arch),
    .imm       (imm),
    .imm_used  (imm_used),
    .fu_type   (fu_type),
    .alu_op    (alu_op),
    .rd_used   (rd_used),
    .is_load   (is_load),
    .is_store  (is_store),
    .ls_size   (ls_size),
    .unsigned_load(unsigned_load),
    .is_branch (is_branch),
    .is_jump   (is_jump)
  );

  // ---------------- skid decode → rename (with back‑pressure) ----------------
  localparam int DEC_BUS_W = 94;
  wire [DEC_BUS_W-1:0] dec_bus_in  = {
    d_pc_out,
    rs1_arch,
    rs2_arch,
    rd_arch,
    imm,
    imm_used,
    fu_type,
    alu_op,
    rd_used,
    is_load,
    is_store,
    ls_size,
    unsigned_load,
    is_branch,
    is_jump
  };
  wire [DEC_BUS_W-1:0] dec_bus_out;
  wire dec2ren_valid;
  wire dec2ren_ready;

  skidbuffer #(.DATA_WIDTH(DEC_BUS_W)) i_skid_dec2ren (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (1'b0),
    .valid_in  (d_valid_out),
    .ready_in  (dec2ren_ready),
    .data_in   (dec_bus_in),
    .valid_out (dec2ren_valid),
    .ready_out (ren_ready_o),
    .data_out  (dec_bus_out)
  );

  // Backpressure from rename stops fetch
  assign if_ready = dec2ren_ready;

  // ---------------- unpack decode bundle ----------------
  wire [31:0]  r_pc_in;
  wire [4:0]   r_rs1_arch;
  wire [4:0]   r_rs2_arch;
  wire [4:0]   r_rd_arch;
  wire [31:0]  r_imm_in;
  wire         r_imm_used_in;
  wire [1:0]   r_fu_type_in;
  wire [3:0]   r_alu_op_in;
  wire         r_rd_used_in;
  wire         r_is_load_in, r_is_store_in, r_unsigned_load_in, r_is_branch_in, r_is_jump_in;
  wire [1:0]   r_ls_size_in;

  assign {
    r_pc_in,
    r_rs1_arch,
    r_rs2_arch,
    r_rd_arch,
    r_imm_in,
    r_imm_used_in,
    r_fu_type_in,
    r_alu_op_in,
    r_rd_used_in,
    r_is_load_in,
    r_is_store_in,
    r_ls_size_in,
    r_unsigned_load_in,
    r_is_branch_in,
    r_is_jump_in
  } = dec_bus_out;

  // ---------------- rename stage ----------------
  wire ren_valid_out;
  wire [31:0] ren_pc_out;
  wire [1:0]  ren_fu_type_out;
  wire [3:0]  ren_alu_op_out;
  wire [31:0] ren_imm_out;
  wire        ren_imm_used_out;
  wire        ren_is_load_out;
  wire        ren_is_store_out;
  wire [1:0]  ren_ls_size_out;
  wire        ren_unsigned_load_out;
  wire        ren_is_branch_out;
  wire        ren_is_jump_out;
  wire [ROB_TAG_W-1:0] ren_rob_tag_out;
  wire [PREG_W-1:0] ren_rs1_tag_out, ren_rs2_tag_out, ren_rd_new_tag_out, ren_rd_old_tag_out;
  wire ren_rs1_ready_out, ren_rs2_ready_out;
  wire ren_rd_used_out;
  wire [N_PHYS_REGS-1:0] prf_valid_from_disp;

  rename i_rename (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(dec2ren_valid),
    .ready_out(ren_ready_o),
    .pc_in(r_pc_in),
    .rs1_arch(r_rs1_arch),
    .rs2_arch(r_rs2_arch),
    .rd_arch(r_rd_arch),
    .imm_in(r_imm_in),
    .imm_used_in(r_imm_used_in),
    .fu_type_in(r_fu_type_in),
    .alu_op_in(r_alu_op_in),
    .rd_used_in(r_rd_used_in),
    .is_load_in(r_is_load_in),
    .is_store_in(r_is_store_in),
    .ls_size_in(r_ls_size_in),
    .unsigned_load_in(r_unsigned_load_in),
    .is_branch_in(r_is_branch_in),
    .is_jump_in(r_is_jump_in),
    .prf_valid(prf_valid_from_disp),
    .valid_out(ren_valid_out),
    .ready_in(ren_ready_o),
    .pc_out(ren_pc_out),
    .fu_type_out(ren_fu_type_out),
    .alu_op_out(ren_alu_op_out),
    .imm_out(ren_imm_out),
    .imm_used_out(ren_imm_used_out),
    .is_load_out(ren_is_load_out),
    .is_store_out(ren_is_store_out),
    .ls_size_out(ren_ls_size_out),
    .unsigned_load_out(ren_unsigned_load_out),
    .is_branch_out(ren_is_branch_out),
    .is_jump_out(ren_is_jump_out),
    .rob_tag_out(ren_rob_tag_out),
    .rs1_tag_out(ren_rs1_tag_out),
    .rs1_ready_out(ren_rs1_ready_out),
    .rs2_tag_out(ren_rs2_tag_out),
    .rs2_ready_out(ren_rs2_ready_out),
    .rd_used_out(ren_rd_used_out),
    .rd_new_tag_out(ren_rd_new_tag_out),
    .rd_old_tag_out(ren_rd_old_tag_out)
  );

  assign ren_valid_o = ren_valid_out;

  // Build rename packet
  rename_pkt_t ren_pkt;
  always_comb begin
    ren_pkt            = '0;
    ren_pkt.pc         = ren_pc_out;
    ren_pkt.fu_type    = ren_fu_type_out;
    ren_pkt.alu_op     = ren_alu_op_out;
    ren_pkt.imm        = ren_imm_out;
    ren_pkt.imm_used   = ren_imm_used_out;
    ren_pkt.is_load    = ren_is_load_out;
    ren_pkt.is_store   = ren_is_store_out;
    ren_pkt.ls_size    = ren_ls_size_out;
    ren_pkt.unsigned_load = ren_unsigned_load_out;
    ren_pkt.is_branch  = ren_is_branch_out;
    ren_pkt.is_jump    = ren_is_jump_out;
    ren_pkt.rob_tag    = ren_rob_tag_out;
    ren_pkt.rs1_tag    = ren_rs1_tag_out;
    ren_pkt.rs1_ready  = ren_rs1_ready_out;
    ren_pkt.rs2_tag    = ren_rs2_tag_out;
    ren_pkt.rs2_ready  = ren_rs2_ready_out;
    ren_pkt.rd_used    = ren_rd_used_out;
    ren_pkt.rd_new_tag = ren_rd_new_tag_out;
    ren_pkt.rd_old_tag = ren_rd_old_tag_out;
  end

  // ---------------- dispatch stage ----------------
  issue_pkt_t lsu_issue_pkt_o;
  issue_pkt_t bru_issue_pkt_o;

  dispatch i_dispatch (
    .clk(clk),
    .rst_n(rst_n),
    .flush_i(1'b0),
    .valid_in(ren_valid_out),
    .ready_out(ren_ready_o),
    .pkt_in(ren_pkt),
    .alu_exec_ready_i(1'b1),
    .lsu_exec_ready_i(1'b1),
    .bru_exec_ready_i(1'b1),
    .cdb_valid_i(1'b0),
    .cdb_tag_i('0),
    .cdb_data_i('0),
    .fire_o(disp_fire_o),
    .fired_pkt_o(disp_pkt_o),
    .alu_issue_valid_o(alu_issue_v_o),
    .alu_issue_pkt_o(alu_issue_pkt_o),
    .lsu_issue_valid_o(),
    .lsu_issue_pkt_o(lsu_issue_pkt_o),
    .bru_issue_valid_o(),
    .bru_issue_pkt_o(bru_issue_pkt_o),
    .prf_valid_o(prf_valid_from_disp),
    .rob_commit_valid_o(),
    .rob_commit_tag_o(),
    .rob_commit_rd_used_o(),
    .rob_commit_dest_new_o(),
    .rob_commit_dest_old_o()
  );
endmodule