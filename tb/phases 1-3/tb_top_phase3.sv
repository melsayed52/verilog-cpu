`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module tb_top_phase3;

  // Clock / reset
  logic clk;
  logic rst_n;

  // Debug from top
  logic        ren_valid;
  logic        ren_ready;
  logic        disp_fire;
  rename_pkt_t disp_pkt;
  logic        alu_issue_v;
  issue_pkt_t  alu_issue_pkt;

  // Instantiate DUT
  top_phase3 #(
    .MEM_DEPTH(512),
    .INIT_FILE("../mem/program.hex),
    .PC_RESET(32'h0000_0000)
  ) dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .ren_valid_o  (ren_valid),
    .ren_ready_o  (ren_ready),
    .disp_fire_o  (disp_fire),
    .disp_pkt_o   (disp_pkt),
    .alu_issue_v_o(alu_issue_v),
    .alu_issue_pkt_o(alu_issue_pkt)
  );

  // Clock: 10ns period
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Reset sequence
  initial begin
    rst_n = 1'b0;
    #50;
    rst_n = 1'b1;
    $display("[%0t] Reset deasserted", $time);
  end

  // Simple progress monitor
  integer cycle;
  integer commits;

  initial begin
    cycle   = 0;
    commits = 0;
    @(posedge rst_n);
    // run for a while or until enough commits
    while (cycle < 2000) begin
      @(posedge clk);
      cycle++;

      // Dispatch events
      if (disp_fire) begin
        $display("[%0t] DISPATCH: pc=%08h fu=%0d rd_used=%0d rd_new=%0d rob_tag(ren)=%0d",
                 $time,
                 disp_pkt.pc,
                 disp_pkt.fu_type,
                 disp_pkt.rd_used,
                 disp_pkt.rd_new_tag,
                 disp_pkt.rob_tag);
      end

      // ALU issue events
      if (alu_issue_v) begin
        $display("[%0t] ALU ISSUE: pc=%08h rs1_tag=%0d rs2_tag=%0d rd_tag=%0d rob_tag=%0d",
                 $time,
                 alu_issue_pkt.pc,
                 alu_issue_pkt.rs1_tag,
                 alu_issue_pkt.rs2_tag,
                 alu_issue_pkt.rd_tag,
                 alu_issue_pkt.rob_tag);
      end

      // Commit events (hierarchical tap into commit_unit)
      if (dut.i_commit_unit.commit_event_o) begin
        commits++;
        $display("[%0t] COMMIT #%0d: rob_tag=%0d new=%0d old=%0d",
                 $time,
                 commits,
                 dut.i_commit_unit.commit_rob_tag_o,
                 dut.i_commit_unit.commit_dest_new_o,
                 dut.i_commit_unit.commit_dest_old_o);
        if (commits == 10) begin
          $display("[%0t] Reached 10 commits, finishing simulation.", $time);
          $finish;
        end
      end
    end

    $display("[%0t] Reached max cycles (%0d) without 10 commits, finishing.",
             $time, cycle);
    $finish;
  end

endmodule
