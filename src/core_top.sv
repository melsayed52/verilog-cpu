//////////////////////////////////////////////////////////////////////////////////
// Module Name: core_top
// Description: Phase 4 integration (with skid buffers between stages).
// Additional Comments:
//   - Exposes rob_commit (internal signal) for testbench to count *all* commits
//   - Adds optional debug prints guarded by `CORE_DEBUG
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module core_top (
  input  logic clk,
  input  logic rst_n
);

  import ooop_types::*;

  // -------------------------
  // Recovery control
  // -------------------------
  logic        flush_i;
  logic [31:0] flush_pc_i;
  logic        recover_i;
  logic [ROB_W-1:0] recover_tag_i;

  // BRU signals
  logic        bru_mispredict;
  logic [31:0] bru_target_pc;
  logic [ROB_W-1:0] bru_recover_tag;

  // -------------------------
  // I-cache -> Fetch
  // -------------------------
  logic        ic_en;
  logic [31:0] ic_addr;
  logic [31:0] ic_rdata;
  logic        ic_rvalid;

  icache icache_u (
    .clk    (clk),
    .rst_n  (rst_n),
    .en     (ic_en),
    .addr   (ic_addr),
    .rdata  (ic_rdata),
    .rvalid (ic_rvalid)
  );

  // Fetch outputs (pre-skid)
  logic        f_valid_raw;
  logic        f_ready_raw;
  logic [31:0] f_pc_raw;
  logic [31:0] f_instr_raw;

  fetch fetch_u (
    .clk             (clk),
    .rst_n           (rst_n),
    .flush_i         (flush_i),
    .flush_pc_i      (flush_pc_i),

    .ready_in        (f_ready_raw),
    .valid_out       (f_valid_raw),
    .pc_out          (f_pc_raw),
    .instr_out       (f_instr_raw),

    .icache_en_o     (ic_en),
    .icache_addr_o   (ic_addr),
    .icache_rdata_i  (ic_rdata),
    .icache_rvalid_i (ic_rvalid)
  );

  // -------------------------
  // Skid: Fetch -> Decode
  // -------------------------
  localparam int F2D_W = 64;

  logic [F2D_W-1:0] f2d_in_data, f2d_out_data;
  logic             f2d_valid, f2d_ready;

  assign f2d_in_data = {f_pc_raw, f_instr_raw};

  skidbuffer #(.WIDTH(F2D_W)) skid_f2d_u (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (flush_i),

    .valid_in  (f_valid_raw),
    .ready_out (f_ready_raw),
    .data_in   (f2d_in_data),

    .valid_out (f2d_valid),
    .ready_in  (f2d_ready),
    .data_out  (f2d_out_data)
  );

  logic [31:0] f_pc;
  logic [31:0] f_instr;
  assign {f_pc, f_instr} = f2d_out_data;

  // -------------------------
  // Decode -> (skid) -> Rename
  // -------------------------
  logic        d_valid_raw;
  logic        d_ready_raw;
  decode_pkt_t d_pkt_raw;

  decode decode_u (
    .valid_in  (f2d_valid),
    .ready_out (f2d_ready),
    .ready_in  (d_ready_raw),

    .pc_in     (f_pc),
    .instr_in  (f_instr),

    .valid_out (d_valid_raw),
    .pkt_out   (d_pkt_raw)
  );

  localparam int D2R_W = $bits(decode_pkt_t);

  logic [D2R_W-1:0] d2r_in_data, d2r_out_data;
  logic             d_valid;
  logic             d_ready;
  decode_pkt_t       d_pkt;

  assign d2r_in_data = d_pkt_raw;

  skidbuffer #(.WIDTH(D2R_W)) skid_d2r_u (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (flush_i),

    .valid_in  (d_valid_raw),
    .ready_out (d_ready_raw),
    .data_in   (d2r_in_data),

    .valid_out (d_valid),
    .ready_in  (d_ready),
    .data_out  (d2r_out_data)
  );

  assign d_pkt = decode_pkt_t'(d2r_out_data);

  // -------------------------
  // ROB free interface into rename
  // -------------------------
  logic              free_req;
  logic [PREG_W-1:0] free_preg;

  // PRF valid vector + inval on alloc
  logic [N_PHYS_REGS-1:0] prf_valid;
  logic                   alloc_inval;
  logic [PREG_W-1:0]       alloc_preg;

  // checkpoint pulse (from rename)
  logic                   checkpoint_take;
  logic [ROB_W-1:0]        checkpoint_tag;

  // ROB live tag bitmap
  logic [ROB_DEPTH-1:0] rob_live_tag;

  // -------------------------
  // Robust ROB tag allocator (moved to top)
  // -------------------------
  logic [ROB_W-1:0] rob_tag;
  logic             tag_ok;

  // feedback when ROB actually allocates a packet (clears reserved tag)
  logic rob_alloc_v;
  rename_pkt_t rob_alloc_pkt;
  logic rob_ready;

  wire rename_fire;
  wire tag_alloc_req;

  assign rename_fire   = d_valid && d_ready; // rename handshake
  assign tag_alloc_req = rename_fire;

  rob_tag_alloc #(
    .ROB_DEPTH(ROB_DEPTH)
  ) rta0 (
    .clk             (clk),
    .rst_n           (rst_n),
    .flush_i         (flush_i),

    .recover_i       (recover_i),
    .recover_tag_i   (recover_tag_i),

    .live_tag_i      (rob_live_tag),

    .alloc_req       (tag_alloc_req),
    .alloc_ok_o      (tag_ok),
    .tag_o           (rob_tag),

    .rob_alloc_fire_i(rob_alloc_v && rob_ready),
    .rob_alloc_tag_i (rob_alloc_pkt.rob_tag),

    .checkpoint_take (checkpoint_take),
    .checkpoint_tag  (checkpoint_tag)
  );

  // Rename outputs (pre-skid)
  logic        r_valid_raw;
  logic        r_ready_raw;
  rename_pkt_t r_pkt_raw;

  rename rename_u (
    .clk              (clk),
    .rst_n            (rst_n),
    .flush_i          (flush_i),
    .recover_i        (recover_i),
    .recover_tag_i    (recover_tag_i),

    .valid_in         (d_valid),
    .ready_out        (d_ready),
    .pkt_in           (d_pkt),

    .valid_out        (r_valid_raw),
    .ready_in         (r_ready_raw),
    .pkt_out          (r_pkt_raw),

    .prf_valid_i      (prf_valid),

    .free_req_i       (free_req),
    .free_preg_i      (free_preg),

    .alloc_inval_o    (alloc_inval),
    .alloc_preg_o     (alloc_preg),

    .checkpoint_take_o(checkpoint_take),
    .checkpoint_tag_o (checkpoint_tag),

    .tag_ok_i         (tag_ok),
    .rob_tag_i        (rob_tag)
  );

  // -------------------------
  // Skid: Rename -> Dispatch
  // -------------------------
  localparam int R2D_W = $bits(rename_pkt_t);

  logic [R2D_W-1:0] r2d_in_data, r2d_out_data;
  logic             r_valid;
  logic             r_ready;
  rename_pkt_t       r_pkt;

  assign r2d_in_data = r_pkt_raw;

  skidbuffer #(.WIDTH(R2D_W)) skid_r2d_u (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (flush_i),

    .valid_in  (r_valid_raw),
    .ready_out (r_ready_raw),
    .data_in   (r2d_in_data),

    .valid_out (r_valid),
    .ready_in  (r_ready),
    .data_out  (r2d_out_data)
  );

  assign r_pkt = rename_pkt_t'(r2d_out_data);

  // -------------------------
  // Dispatch
  // -------------------------
  logic       rs_alu_ins_v, rs_bru_ins_v, rs_lsu_ins_v;
  rs_entry_t  rs_alu_ins_e, rs_bru_ins_e, rs_lsu_ins_e;
  logic       rs_alu_ready, rs_bru_ready, rs_lsu_ready;

  dispatch dispatch_u (
    .clk               (clk),
    .rst_n             (rst_n),
    .flush_i           (flush_i),

    .valid_in          (r_valid),
    .ready_out         (r_ready),
    .pkt_in            (r_pkt),

    .rs_alu_ready_i    (rs_alu_ready),
    .rs_bru_ready_i    (rs_bru_ready),
    .rs_lsu_ready_i    (rs_lsu_ready),

    .rs_alu_valid_o    (rs_alu_ins_v),
    .rs_alu_entry_o    (rs_alu_ins_e),

    .rs_bru_valid_o    (rs_bru_ins_v),
    .rs_bru_entry_o    (rs_bru_ins_e),

    .rs_lsu_valid_o    (rs_lsu_ins_v),
    .rs_lsu_entry_o    (rs_lsu_ins_e),

    .rob_ready_i       (rob_ready),
    .rob_alloc_valid_o (rob_alloc_v),
    .rob_alloc_pkt_o   (rob_alloc_pkt)
  );

  // -------------------------
  // Reservation Stations
  // -------------------------
  wb_pkt_t wb_alu, wb_bru, wb_lsu;

  logic      alu_issue_v, bru_issue_v, lsu_issue_v;
  rs_entry_t alu_issue_e, bru_issue_e, lsu_issue_e;

  logic issue_ready_alu, issue_ready_bru, issue_ready_lsu;

  rs #(.DEPTH(RS_DEPTH)) rs_alu_u (
    .clk             (clk),
    .rst_n           (rst_n),
    .flush_i         (flush_i),

    .recover_i       (recover_i),
    .live_tag_i      (rob_live_tag),

    .prf_valid_i     (prf_valid),        // << ADDED

    .insert_valid_i  (rs_alu_ins_v),
    .insert_entry_i  (rs_alu_ins_e),
    .ready_o         (rs_alu_ready),

    .wb_alu_i        (wb_alu),
    .wb_lsu_i        (wb_lsu),
    .wb_bru_i        (wb_bru),

    .issue_valid_o   (alu_issue_v),
    .issue_entry_o   (alu_issue_e),
    .issue_ready_i   (issue_ready_alu)
  );

  rs #(.DEPTH(RS_DEPTH)) rs_bru_u (
    .clk             (clk),
    .rst_n           (rst_n),
    .flush_i         (flush_i),

    .recover_i       (recover_i),
    .live_tag_i      (rob_live_tag),

    .prf_valid_i     (prf_valid),        // << ADDED

    .insert_valid_i  (rs_bru_ins_v),
    .insert_entry_i  (rs_bru_ins_e),
    .ready_o         (rs_bru_ready),

    .wb_alu_i        (wb_alu),
    .wb_lsu_i        (wb_lsu),
    .wb_bru_i        (wb_bru),

    .issue_valid_o   (bru_issue_v),
    .issue_entry_o   (bru_issue_e),
    .issue_ready_i   (issue_ready_bru)
  );

  rs #(.DEPTH(RS_DEPTH)) rs_lsu_u (
    .clk             (clk),
    .rst_n           (rst_n),
    .flush_i         (flush_i),

    .recover_i       (recover_i),
    .live_tag_i      (rob_live_tag),

    .prf_valid_i     (prf_valid),        // << ADDED

    .insert_valid_i  (rs_lsu_ins_v),
    .insert_entry_i  (rs_lsu_ins_e),
    .ready_o         (rs_lsu_ready),

    .wb_alu_i        (wb_alu),
    .wb_lsu_i        (wb_lsu),
    .wb_bru_i        (wb_bru),

    .issue_valid_o   (lsu_issue_v),
    .issue_entry_o   (lsu_issue_e),
    .issue_ready_i   (issue_ready_lsu)
  );

  // -------------------------
  // Single-issue select (priority ALU > BRU > LSU)
  // -------------------------
  logic      iss_alu, iss_bru, iss_lsu;
  rs_entry_t iss_e;

  always @* begin
    iss_alu = 1'b0;
    iss_bru = 1'b0;
    iss_lsu = 1'b0;
    iss_e   = '0;

    if (alu_issue_v) begin
      iss_alu = 1'b1;
      iss_e   = alu_issue_e;
    end else if (bru_issue_v) begin
      iss_bru = 1'b1;
      iss_e   = bru_issue_e;
    end else if (lsu_issue_v) begin
      iss_lsu = 1'b1;
      iss_e   = lsu_issue_e;
    end
  end

  assign issue_ready_alu = iss_alu;
  assign issue_ready_bru = iss_bru;
  assign issue_ready_lsu = iss_lsu;

  // -------------------------
  // PRF reads
  // -------------------------
  logic [PREG_W-1:0] prf_raddr1, prf_raddr2;
  xlen_t             prf_rdata1, prf_rdata2;

  assign prf_raddr1 = iss_e.prs1;
  assign prf_raddr2 = iss_e.prs2;

  prf prf_u (
    .clk              (clk),
    .rst_n            (rst_n),
    .flush_i          (flush_i),
    .recover_i        (recover_i),
    .recover_tag_i    (recover_tag_i),

    .checkpoint_take_i(checkpoint_take),
    .checkpoint_tag_i (checkpoint_tag),

    .raddr1_i         (prf_raddr1),
    .rdata1_o         (prf_rdata1),
    .raddr2_i         (prf_raddr2),
    .rdata2_o         (prf_rdata2),

    .wb_alu_i         (wb_alu),
    .wb_lsu_i         (wb_lsu),
    .wb_bru_i         (wb_bru),

    .alloc_inval_i    (alloc_inval),
    .alloc_preg_i     (alloc_preg),

    .valid_o          (prf_valid)
  );

  // -------------------------
  // FUs
  // -------------------------
  alu_fu alu_fu_u (
    .clk           (clk),
    .rst_n         (rst_n),
    .flush_i       (flush_i),
    .issue_valid_i (iss_alu),
    .entry_i       (iss_e),
    .src1_i        (prf_rdata1),
    .src2_i        (prf_rdata2),
    .wb_o          (wb_alu)
  );

  branch_fu branch_fu_u (
    .clk            (clk),
    .rst_n          (rst_n),
    .flush_i        (flush_i),

    .issue_valid_i  (iss_bru),
    .entry_i        (iss_e),
    .src1_i         (prf_rdata1),
    .src2_i         (prf_rdata2),

    .mispredict_o   (bru_mispredict),
    .target_pc_o    (bru_target_pc),

    .recover_tag_o  (bru_recover_tag),
    .wb_o           (wb_bru)
  );

  // DMEM + LSU
  logic        dmem_en, dmem_we, dmem_rvalid;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  ls_size_t    dmem_size;

  dmem_bram dmem_u (
    .clk      (clk),
    .rst_n    (rst_n),
    .en_i     (dmem_en),
    .we_i     (dmem_we),
    .addr_i   (dmem_addr),
    .wdata_i  (dmem_wdata),
    .size_i   (dmem_size),
    .rvalid_o (dmem_rvalid),
    .rdata_o  (dmem_rdata)
  );

  lsu_fu lsu_fu_u (
    .clk           (clk),
    .rst_n         (rst_n),
    .flush_i       (flush_i),
    .issue_valid_i (iss_lsu),
    .entry_i       (iss_e),
    .src1_i        (prf_rdata1),
    .src2_i        (prf_rdata2),

    .dmem_en_o     (dmem_en),
    .dmem_we_o     (dmem_we),
    .dmem_addr_o   (dmem_addr),
    .dmem_wdata_o  (dmem_wdata),
    .dmem_size_o   (dmem_size),

    .dmem_rvalid_i (dmem_rvalid),
    .dmem_rdata_i  (dmem_rdata),

    .wb_o          (wb_lsu)
  );

  // -------------------------
  // ROB
  // -------------------------
  logic rob_commit; // <-- TB should count this, not free_req
  rob #(.DEPTH(ROB_DEPTH)) rob_u (
    .clk              (clk),
    .rst_n            (rst_n),
    .flush_i          (flush_i),
    .recover_i        (recover_i),
    .recover_tag_i    (recover_tag_i),

    .checkpoint_take_i(checkpoint_take),
    .checkpoint_tag_i (checkpoint_tag),

    .alloc_valid_i    (rob_alloc_v),
    .alloc_pkt_i      (rob_alloc_pkt),
    .ready_o          (rob_ready),

    .wb_alu_i         (wb_alu),
    .wb_lsu_i         (wb_lsu),
    .wb_bru_i         (wb_bru),

    .free_req_o       (free_req),
    .free_preg_o      (free_preg),

    .commit_o         (rob_commit),

    .live_tag_o       (rob_live_tag)
  );

  // -------------------------
  // Recovery controller
  // -------------------------
  recovery_ctrl recovery_u (
    .clk           (clk),
    .rst_n         (rst_n),

    .mispredict_i  (bru_mispredict),
    .target_pc_i   (bru_target_pc),
    .recover_tag_i (bru_recover_tag),

    .flush_o       (flush_i),
    .flush_pc_o    (flush_pc_i),

    .recover_o     (recover_i),
    .recover_tag_o (recover_tag_i)
  );

`ifdef CORE_DEBUG
  // very lightweight tracing (prints on interesting events)
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (rob_commit) begin
        $display("[core] commit pc=0x%08x instr=0x%08x free_req=%0b free_preg=%0d flush=%0b recover=%0b",
                 f_pc, f_instr, free_req, free_preg, flush_i, recover_i);
      end
      if (flush_i) begin
        $display("[core] flush -> pc=0x%08x (recover=%0b tag=%0d)", flush_pc_i, recover_i, recover_tag_i);
      end
    end
  end
`endif

endmodule
