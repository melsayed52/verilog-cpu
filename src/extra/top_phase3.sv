//////////////////////////////////////////////////////////////////////////////////
// Module: top_phase3
// Description: Phase 3 top-level for the Out-of-Order Core.
//   - Reuses Phase 2 front-end (fetch/decode/rename).
//   - Adds Phase 3 backend: dispatch + RS + ROB (inside dispatch),
//     ALU/LSU/BRU FUs, dmem, CDB arbiter, commit_unit.
//   - PRF lives inside dispatch; FUs talk to it via dispatch PRF read ports.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module top_phase3 #(
  parameter int     MEM_DEPTH = 512,
  parameter string  INIT_FILE = "../mem/program.hex",
  parameter logic [31:0] PC_RESET = 32'h0000_0000
)(
  input  logic clk,
  input  logic rst_n,

  // debug taps
  output logic       ren_valid_o,
  output logic       ren_ready_o,
  output logic       disp_fire_o,
  output rename_pkt_t disp_pkt_o,
  output logic       alu_issue_v_o,
  output issue_pkt_t alu_issue_pkt_o
);

  // ================================================================
  // ======================== INSTRUCTION MEM ========================
  // ================================================================
  logic        if_req_valid;
  logic [31:0] if_req_addr;
  logic [31:0] if_rd_data;
  logic        if_rd_valid;

  icache #(
    .MEM_DEPTH (MEM_DEPTH),
    .INIT_FILE (INIT_FILE)
  ) i_icache (
    .clk      (clk),
    .rst_n    (rst_n),
    .addr_i   (if_req_addr),
    .req_i    (if_req_valid),
    .rdata_o  (if_rd_data),
    .rvalid_o (if_rd_valid)
  );

  // ================================================================
  // ============================= FETCH =============================
  // ================================================================
  wire [31:0] if_pc;
  wire        if_valid;
  wire        if_ready;

  fetch i_fetch (
    .clk        (clk),
    .rst_n      (rst_n),
    .pc_reset_i (PC_RESET),

    .rd_valid_i (if_rd_valid),
    .rd_rdata_i (if_rd_data),

    .pc_o       (if_pc),
    .valid_o    (if_valid),
    .ready_i    (if_ready),

    .rd_req_o   (if_req_valid),
    .rd_addr_o  (if_req_addr)
  );

  // ================================================================
  // ====================== FETCH→DECODE SKID =======================
  // ================================================================
  wire [63:0] if_bus_in, if_bus_out;
  assign if_bus_in = {if_pc, if_rd_data};

  wire if_sk_valid, if_sk_ready;

  skidbuffer #(.DATA_WIDTH(64)) i_if_skid (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (1'b0),
    .valid_in  (if_valid),
    .ready_in  (if_ready),
    .data_in   (if_bus_in),
    .valid_out (if_sk_valid),
    .ready_out (if_sk_ready),
    .data_out  (if_bus_out)
  );

  wire [31:0] if_pc_out;
  wire [31:0] if_instr_out;
  assign {if_pc_out, if_instr_out} = if_bus_out;

  // ================================================================
  // ============================= DECODE ============================
  // ================================================================
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
    .valid_in   (if_sk_valid),
    .pc_in      (if_pc_out),
    .instr_in   (if_instr_out),
    .ready_out  (if_sk_ready),

    .valid_out  (d_valid_out),
    .pc_out     (d_pc_out),
    .rs1        (rs1_arch),
    .rs2        (rs2_arch),
    .rd         (rd_arch),
    .imm        (imm),
    .imm_used   (imm_used),
    .fu_type    (fu_type),
    .alu_op     (alu_op),
    .rd_used    (rd_used),
    .is_load    (is_load),
    .is_store   (is_store),
    .ls_size    (ls_size),
    .unsigned_l (unsigned_load),
    .is_branch  (is_branch),
    .is_jump    (is_jump)
  );

  // ================================================================
  // ====================== DECODE→RENAME SKID ======================
  // ================================================================
  // Bundle decode outputs into a single bus for skidbuffer
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
  } = {
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

  localparam int DEC2REN_W = 32 + 5 + 5 + 5 + 32 + 1 + 2 + 4 + 1 + 1 + 1 + 2 + 1 + 1 + 1;

  wire [DEC2REN_W-1:0] dec2ren_bus_in;
  wire [DEC2REN_W-1:0] dec2ren_bus_out;
  assign dec2ren_bus_in = {
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
  };

  wire dec2ren_valid;

  // handshake between skidbuffer and rename:
  //   - skidbuffer.valid_out  -> rename.valid_in
  //   - rename.ready_out      -> skidbuffer.ready_out
  wire ren_valid_in;
  wire ren_ready_from_rename;

  skidbuffer #(.DATA_WIDTH(DEC2REN_W)) i_dec_ren_skid (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (1'b0),
    .valid_in  (d_valid_out),
    .ready_in  (),                 // not backpressuring decode in this simple top
    .data_in   (dec2ren_bus_in),
    .valid_out (ren_valid_in),
    .ready_out (ren_ready_from_rename),
    .data_out  (dec2ren_bus_out)
  );

  assign dec2ren_valid = ren_valid_in;

  wire [31:0]  ren_pc_in;
  wire [4:0]   ren_rs1_arch;
  wire [4:0]   ren_rs2_arch;
  wire [4:0]   ren_rd_arch;
  wire [31:0]  ren_imm_in;
  wire         ren_imm_used_in;
  wire [1:0]   ren_fu_type_in;
  wire [3:0]   ren_alu_op_in;
  wire         ren_rd_used_in;
  wire         ren_is_load_in, ren_is_store_in, ren_unsigned_load_in, ren_is_branch_in, ren_is_jump_in;
  wire [1:0]   ren_ls_size_in;

  assign {
    ren_pc_in,
    ren_rs1_arch,
    ren_rs2_arch,
    ren_rd_arch,
    ren_imm_in,
    ren_imm_used_in,
    ren_fu_type_in,
    ren_alu_op_in,
    ren_rd_used_in,
    ren_is_load_in,
    ren_is_store_in,
    ren_ls_size_in,
    ren_unsigned_load_in,
    ren_is_branch_in,
    ren_is_jump_in
  } = dec2ren_bus_out;

  // ================================================================
  // =============================== RENAME ==========================
  // ================================================================
  wire        ren_valid_in_w  = dec2ren_valid;
  wire        ren_ready_to_disp;   // backpressure from dispatch

  rename_pkt_t ren_pkt;
  wire [N_PHYS_REGS-1:0] prf_valid_from_disp;

  rename i_rename (
    .clk        (clk),
    .rst_n      (rst_n),

    // upstream (from decode skid)
    .valid_in   (ren_valid_in_w),
    .ready_out  (ren_ready_from_rename),

    // decoded fields
    .pc_in      (ren_pc_in),
    .rs1_arch   (ren_rs1_arch),
    .rs2_arch   (ren_rs2_arch),
    .rd_arch    (ren_rd_arch),
    .imm_in     (ren_imm_in),
    .imm_used   (ren_imm_used_in),
    .fu_type    (ren_fu_type_in),
    .alu_op     (ren_alu_op_in),
    .rd_used    (ren_rd_used_in),
    .is_load    (ren_is_load_in),
    .is_store   (ren_is_store_in),
    .ls_size    (ren_ls_size_in),
    .unsigned_l (ren_unsigned_load_in),
    .is_branch  (ren_is_branch_in),
    .is_jump    (ren_is_jump_in),

    // downstream (to dispatch)
    .valid_out  (ren_valid_o),
    .ready_in   (ren_ready_to_disp),
    .pkt_out    (ren_pkt),

    .prf_valid_i(prf_valid_from_disp)
  );

  // debug export: rename's downstream ready (from dispatch)
  assign ren_ready_o = ren_ready_to_disp;

  // ================================================================
  // ====================== DISPATCH + BACKEND ======================
  // ================================================================

  // Issue packets to FUs
  issue_pkt_t alu_issue_pkt, lsu_issue_pkt, bru_issue_pkt;
  logic       alu_issue_valid, lsu_issue_valid, bru_issue_valid;

  // FU readiness
  logic alu_fu_ready, lsu_fu_ready, bru_fu_ready;

  // ROB commit → commit_unit
  logic                 rob_commit_valid;
  logic [ROB_TAG_W-1:0] rob_commit_tag;
  logic                 rob_commit_rd_used;
  logic [PREG_W-1:0]    rob_commit_dest_new;
  logic [PREG_W-1:0]    rob_commit_dest_old;

  // PRF valid bits
  logic [N_PHYS_REGS-1:0] prf_valid_bits;

  // CDB
  logic                 cdb_valid;
  logic [PREG_W-1:0]    cdb_tag;
  logic [XLEN-1:0]      cdb_data;

  // PRF read buses between FUs and dispatch
  logic [PREG_W-1:0] alu_rs1_tag, alu_rs2_tag;
  logic [XLEN-1:0]   alu_rs1_data, alu_rs2_data;

  logic [PREG_W-1:0] lsu_rs1_tag, lsu_rs2_tag;
  logic [XLEN-1:0]   lsu_rs1_data, lsu_rs2_data;

  logic [PREG_W-1:0] bru_rs1_tag, bru_rs2_tag;
  logic [XLEN-1:0]   bru_rs1_data, bru_rs2_data;

  dispatch i_dispatch (
    .clk   (clk),
    .rst_n (rst_n),
    .flush_i(1'b0),

    // From rename
    .valid_in (ren_valid_o),
    .ready_out(ren_ready_to_disp),
    .pkt_in   (ren_pkt),

    // FU ready
    .alu_exec_ready_i (alu_fu_ready),
    .lsu_exec_ready_i (lsu_fu_ready),
    .bru_exec_ready_i (bru_fu_ready),

    // CDB (writeback)
    .cdb_valid_i (cdb_valid),
    .cdb_tag_i   (cdb_tag),
    .cdb_data_i  (cdb_data),

    // debug
    .fire_o     (disp_fire_o),
    .fired_pkt_o(disp_pkt_o),

    // issue
    .alu_issue_valid_o (alu_issue_valid),
    .alu_issue_pkt_o   (alu_issue_pkt),
    .lsu_issue_valid_o (lsu_issue_valid),
    .lsu_issue_pkt_o   (lsu_issue_pkt),
    .bru_issue_valid_o (bru_issue_valid),
    .bru_issue_pkt_o   (bru_issue_pkt),

    // PRF valid bits
    .prf_valid_o (prf_valid_bits),

    // ROB commit
    .rob_commit_valid_o   (rob_commit_valid),
    .rob_commit_tag_o     (rob_commit_tag),
    .rob_commit_rd_used_o (rob_commit_rd_used),
    .rob_commit_dest_new_o(rob_commit_dest_new),
    .rob_commit_dest_old_o(rob_commit_dest_old),

    // NEW: PRF read ports to FUs
    .alu_prf_rs1_tag_i  (alu_rs1_tag),
    .alu_prf_rs2_tag_i  (alu_rs2_tag),
    .alu_prf_rs1_data_o (alu_rs1_data),
    .alu_prf_rs2_data_o (alu_rs2_data),

    .lsu_prf_rs1_tag_i  (lsu_rs1_tag),
    .lsu_prf_rs2_tag_i  (lsu_rs2_tag),
    .lsu_prf_rs1_data_o (lsu_rs1_data),
    .lsu_prf_rs2_data_o (lsu_rs2_data),

    .bru_prf_rs1_tag_i  (bru_rs1_tag),
    .bru_prf_rs2_tag_i  (bru_rs2_tag),
    .bru_prf_rs1_data_o (bru_rs1_data),
    .bru_prf_rs2_data_o (bru_rs2_data)
  );

  assign prf_valid_from_disp = prf_valid_bits;

  // expose ALU issue (debug)
  assign alu_issue_v_o   = alu_issue_valid;
  assign alu_issue_pkt_o = alu_issue_pkt;

  // ================================================================
  // =========================== EXECUTE FUs =========================
  // ================================================================

  // --------- ALU FU ----------
  logic                 alu_wb_valid;
  logic [PREG_W-1:0]    alu_wb_tag;
  logic [XLEN-1:0]      alu_wb_data;
  logic                 alu_cpl_valid;
  logic [ROB_TAG_W-1:0] alu_cpl_tag;

  alu_fu u_alu_fu (
    .clk (clk),
    .rst_n(rst_n),
    .flush_i(1'b0),

    .issue_valid_i (alu_issue_valid),
    .issue_ready_o (alu_fu_ready),
    .issue_pkt_i   (alu_issue_pkt),

    .prf_rs1_tag_o (alu_rs1_tag),
    .prf_rs2_tag_o (alu_rs2_tag),
    .prf_rs1_data_i(alu_rs1_data),
    .prf_rs2_data_i(alu_rs2_data),

    .wb_valid_o (alu_wb_valid),
    .wb_tag_o   (alu_wb_tag),
    .wb_data_o  (alu_wb_data),

    .cpl_valid_o(alu_cpl_valid),
    .cpl_tag_o  (alu_cpl_tag)
  );

  // --------- DMEM ----------
  logic        dmem_req_valid;
  logic [31:0] dmem_addr;
  logic [XLEN-1:0] dmem_rdata;
  logic        dmem_rvalid;

  dmem #(
    .MEM_DEPTH(MEM_DEPTH),
    .INIT_FILE("../mem/data.hex"),
    .XLEN_P(XLEN)
  ) i_dmem (
    .clk(clk),
    .rst_n(rst_n),
    .addr_i(dmem_addr),
    .req_valid_i(dmem_req_valid),
    .rdata_o(dmem_rdata),
    .rvalid_o(dmem_rvalid)
  );

  // --------- LSU FU ----------
  logic                 lsu_wb_valid;
  logic [PREG_W-1:0]    lsu_wb_tag;
  logic [XLEN-1:0]      lsu_wb_data;
  logic                 lsu_cpl_valid;
  logic [ROB_TAG_W-1:0] lsu_cpl_tag;

  lsu_fu u_lsu_fu (
    .clk(clk),
    .rst_n(rst_n),
    .flush_i(1'b0),

    .issue_valid_i(lsu_issue_valid),
    .issue_ready_o(lsu_fu_ready),
    .issue_pkt_i(lsu_issue_pkt),

    .prf_rs1_tag_o (lsu_rs1_tag),
    .prf_rs2_tag_o (lsu_rs2_tag),
    .prf_rs1_data_i(lsu_rs1_data),
    .prf_rs2_data_i(lsu_rs2_data),

    .dmem_req_valid_o(dmem_req_valid),
    .dmem_addr_o     (dmem_addr),
    .dmem_rdata_i    (dmem_rdata),
    .dmem_rvalid_i   (dmem_rvalid),

    .wb_valid_o (lsu_wb_valid),
    .wb_tag_o   (lsu_wb_tag),
    .wb_data_o  (lsu_wb_data),

    .cpl_valid_o(lsu_cpl_valid),
    .cpl_tag_o  (lsu_cpl_tag)
  );

  // --------- BRANCH FU ----------
  logic                 bru_wb_valid;
  logic [PREG_W-1:0]    bru_wb_tag;
  logic [XLEN-1:0]      bru_wb_data;
  logic                 bru_cpl_valid;
  logic [ROB_TAG_W-1:0] bru_cpl_tag;
  logic                 br_redir_valid;
  logic [XLEN-1:0]      br_redir_pc;
  logic                 br_taken;

  branch_fu u_branch_fu (
    .clk(clk),
    .rst_n(rst_n),
    .flush_i(1'b0),

    .issue_valid_i(bru_issue_valid),
    .issue_ready_o(bru_fu_ready),
    .issue_pkt_i  (bru_issue_pkt),

    .prf_rs1_tag_o (bru_rs1_tag),
    .prf_rs2_tag_o (bru_rs2_tag),
    .prf_rs1_data_i(bru_rs1_data),
    .prf_rs2_data_i(bru_rs2_data),

    .wb_valid_o (bru_wb_valid),
    .wb_tag_o   (bru_wb_tag),
    .wb_data_o  (bru_wb_data),

    .cpl_valid_o(bru_cpl_valid),
    .cpl_tag_o  (bru_cpl_tag),

    .br_redir_valid_o(br_redir_valid),
    .br_redir_pc_o   (br_redir_pc),
    .br_taken_o      (br_taken)
  );

  // ================================================================
  // =========================== WRITEBACK ===========================
  // ================================================================

  cdb_arbiter i_cdb_arbiter (
    .alu_wb_valid_i (alu_wb_valid),
    .alu_wb_tag_i   (alu_wb_tag),
    .alu_wb_data_i  (alu_wb_data),

    .lsu_wb_valid_i (lsu_wb_valid),
    .lsu_wb_tag_i   (lsu_wb_tag),
    .lsu_wb_data_i  (lsu_wb_data),

    .bru_wb_valid_i (bru_wb_valid),
    .bru_wb_tag_i   (bru_wb_tag),
    .bru_wb_data_i  (bru_wb_data),

    .cdb_valid_o (cdb_valid),
    .cdb_tag_o   (cdb_tag),
    .cdb_data_o  (cdb_data)
  );

  // ================================================================
  // ============================= COMMIT ============================
  // ================================================================

  commit_unit i_commit_unit (
    .clk  (clk),
    .rst_n(rst_n),
    .flush_i(1'b0),

    .rob_commit_valid_i   (rob_commit_valid),
    .rob_commit_tag_i     (rob_commit_tag),
    .rob_commit_rd_used_i (rob_commit_rd_used),
    .rob_commit_dest_new_i(rob_commit_dest_new),
    .rob_commit_dest_old_i(rob_commit_dest_old),

    .commit_ready_o(), // ROB already assumes ready=1 for Phase 3

    .free_old_tag_valid_o(),
    .free_old_tag_o       (),

    .commit_event_o(),
    .commit_rob_tag_o(),
    .commit_dest_new_o(),
    .commit_dest_old_o()
  );

endmodule
