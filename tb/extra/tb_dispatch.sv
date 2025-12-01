`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module tb_dispatch;

  // ----------------------
  // Clock / reset
  // ----------------------
  logic clk = 0;
  always #5 clk = ~clk;   // 100 MHz

  logic rst_n = 0;

  // ----------------------
  // DUT interface signals
  // ----------------------
  // From rename
  logic        valid_in;
  logic        ready_out;
  rename_pkt_t pkt_in;

  // Exec unit readiness
  logic alu_exec_ready_i;
  logic lsu_exec_ready_i;
  logic bru_exec_ready_i;

  // CDB (unused in this simple TB)
  logic        cdb_valid_i;
  logic [PREG_W-1:0] cdb_tag_i;
  logic [XLEN-1:0]   cdb_data_i;

  // Debug taps
  logic        fire_o;
  rename_pkt_t fired_pkt_o;

  // RS issue outputs
  logic        alu_issue_valid_o;
  issue_pkt_t  alu_issue_pkt_o;
  logic        lsu_issue_valid_o;
  issue_pkt_t  lsu_issue_pkt_o;
  logic        bru_issue_valid_o;
  issue_pkt_t  bru_issue_pkt_o;

  // PRF valid bits
  logic [N_PHYS_REGS-1:0] prf_valid_o;

  // ROB commit outputs
  logic        rob_commit_valid_o;
  logic [ROB_TAG_W-1:0] rob_commit_tag_o;
  logic        rob_commit_rd_used_o;
  logic [PREG_W-1:0]    rob_commit_dest_new_o;
  logic [PREG_W-1:0]    rob_commit_dest_old_o;

  // Flush (mispredict) – not used yet
  logic flush_i;

  // ----------------------
  // DUT instance
  // ----------------------
  dispatch DUT (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .flush_i               (flush_i),

    .valid_in              (valid_in),
    .ready_out             (ready_out),
    .pkt_in                (pkt_in),

    .alu_exec_ready_i      (alu_exec_ready_i),
    .lsu_exec_ready_i      (lsu_exec_ready_i),
    .bru_exec_ready_i      (bru_exec_ready_i),

    .cdb_valid_i           (cdb_valid_i),
    .cdb_tag_i             (cdb_tag_i),
    .cdb_data_i            (cdb_data_i),

    .fire_o                (fire_o),
    .fired_pkt_o           (fired_pkt_o),

    .alu_issue_valid_o     (alu_issue_valid_o),
    .alu_issue_pkt_o       (alu_issue_pkt_o),
    .lsu_issue_valid_o     (lsu_issue_valid_o),
    .lsu_issue_pkt_o       (lsu_issue_pkt_o),
    .bru_issue_valid_o     (bru_issue_valid_o),
    .bru_issue_pkt_o       (bru_issue_pkt_o),

    .prf_valid_o           (prf_valid_o),

    .rob_commit_valid_o    (rob_commit_valid_o),
    .rob_commit_tag_o      (rob_commit_tag_o),
    .rob_commit_rd_used_o  (rob_commit_rd_used_o),
    .rob_commit_dest_new_o (rob_commit_dest_new_o),
    .rob_commit_dest_old_o (rob_commit_dest_old_o)
  );

  // ----------------------
  // Simple stimulus
  // ----------------------
  // Drive a handful of fake rename packets into dispatch and watch
  // them get assigned to RS + ROB and later "complete" / commit.
  // This doesn’t depend on fetch/decode/rename, so it’s good for
  // checking wiring & handshake.

  // helper: make a packet
  task automatic make_pkt(
    input  int              idx,
    input  logic [1:0]      fu,
    output rename_pkt_t     p
  );
    begin
      p = '0;

      p.pc            = 32'h0000_1000 + idx*4;

      p.fu_type       = fu;
      p.alu_op        = 4'd0;

      p.imm           = 32'(idx);
      p.imm_used      = 1'b0;

      p.is_load       = (fu == FU_LSU);
      p.is_store      = 1'b0;
      p.ls_size       = 2'd2;
      p.unsigned_load = 1'b0;

      p.is_branch     = (fu == FU_BRU);
      p.is_jump       = 1'b0;

      p.rob_tag       = '0;   // actual tag is assigned inside ROB

      p.rs1_tag       = PREG_W'(idx % N_PHYS_REGS);
      p.rs1_ready     = 1'b1;
      p.rs2_tag       = PREG_W'((idx+1) % N_PHYS_REGS);
      p.rs2_ready     = 1'b1;

      p.rd_used       = 1'b1;
      p.rd_new_tag    = PREG_W'((idx+32) % N_PHYS_REGS);
      p.rd_old_tag    = PREG_W'((idx+1) % N_PHYS_REGS);
    end
  endtask

  int instr_idx;
  logic [1:0] fu_sel;

  initial begin
    // init defaults
    valid_in          = 1'b0;
    flush_i           = 1'b0;

    alu_exec_ready_i  = 1'b1;
    lsu_exec_ready_i  = 1'b1;
    bru_exec_ready_i  = 1'b1;

    cdb_valid_i       = 1'b0;
    cdb_tag_i         = '0;
    cdb_data_i        = '0;

    // reset
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    // send ~20 instructions
    instr_idx = 0;
    while (instr_idx < 20) begin
      @(posedge clk);

      // only launch when dispatch buffer can accept a new packet
      if (ready_out) begin
        fu_sel = (instr_idx % 3); // 0=ALU,1=LSU,2=BRU
        make_pkt(instr_idx, fu_sel, pkt_in);
        valid_in = 1'b1;
        instr_idx++;
      end else begin
        valid_in = 1'b0;
      end
    end

    // stop sending
    @(posedge clk);
    valid_in = 1'b0;
    pkt_in   = '0;

    // let ROB/RS drain
    repeat (100) @(posedge clk);
    $finish;
  end

  // ----------------------
  // Logging
  // ----------------------
  always @(posedge clk) begin
    if (fire_o) begin
      $display("[%0t] DISPATCH: pc=%08x fu=%0d rd_new=%0d",
               $time, fired_pkt_o.pc, fired_pkt_o.fu_type,
               fired_pkt_o.rd_new_tag);
    end

    if (alu_issue_valid_o) begin
      $display("[%0t] ALU ISSUE: pc=%08x rob=%0d rd=%0d",
               $time, alu_issue_pkt_o.pc,
               alu_issue_pkt_o.rob_tag,
               alu_issue_pkt_o.rd_tag);
    end

    if (lsu_issue_valid_o) begin
      $display("[%0t] LSU ISSUE: pc=%08x rob=%0d rd=%0d",
               $time, lsu_issue_pkt_o.pc,
               lsu_issue_pkt_o.rob_tag,
               lsu_issue_pkt_o.rd_tag);
    end

    if (bru_issue_valid_o) begin
      $display("[%0t] BRU ISSUE: pc=%08x rob=%0d rd=%0d",
               $time, bru_issue_pkt_o.pc,
               bru_issue_pkt_o.rob_tag,
               bru_issue_pkt_o.rd_tag);
    end

    if (rob_commit_valid_o) begin
      $display("[%0t] COMMIT: rob=%0d rd_used=%0d new=%0d old=%0d",
               $time, rob_commit_tag_o,
               rob_commit_rd_used_o,
               rob_commit_dest_new_o,
               rob_commit_dest_old_o);
    end
  end

endmodule
