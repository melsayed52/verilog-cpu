////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_top_phase2
// Description: Basic testbench for Phase 2 top integration.  This testbench
// instantiates the top_phase2 module with an instruction memory and runs it
// for a fixed number of cycles.  It prints dispatch and issue events to
// the console.  The ICACHE should be initialised with a program hex file
// via the INIT_FILE parameter.  The testbench ties off all ready
// signals for execution units to 1 so that instructions can issue as
// soon as they are ready in the reservation stations.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_types.sv"

module tb_top_phase2;
  // 100 MHz clock
  reg clk = 0; always #5 clk = ~clk;
  reg rst_n = 0;

  // debug taps
  wire ren_v;
  wire ren_rdy;
  wire disp_fire;
  rename_pkt_t disp_pkt;
  wire alu_issue_v;
  issue_pkt_t alu_issue_pkt;

  localparam string HEX_ABS = "../mem/program.hex";

  top_phase2 #(.INIT_FILE(HEX_ABS)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .ren_valid_o(ren_v),
    .ren_ready_o(ren_rdy),
    .disp_fire_o(disp_fire),
    .disp_pkt_o(disp_pkt),
    .alu_issue_v_o(alu_issue_v),
    .alu_issue_pkt_o(alu_issue_pkt)
  );

  initial begin
    // reset sequence
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    // run long enough to see several fetches
    repeat (200) @(posedge clk);
    $finish;
  end

  // Print dispatch and issue events
  always @(posedge clk) begin
    if (disp_fire) begin
      $display("[DISPATCH] pc=%08x fu=%0d rs1=%0d(%0d) rs2=%0d(%0d) rd_new=%0d rd_used=%0d",
        disp_pkt.pc, disp_pkt.fu_type,
        disp_pkt.rs1_tag, disp_pkt.rs1_ready,
        disp_pkt.rs2_tag, disp_pkt.rs2_ready,
        disp_pkt.rd_new_tag, disp_pkt.rd_used);
    end
    if (alu_issue_v) begin
      $display("[ALU ISSUE] pc=%08x rob=%0d rs1=%0d rs2=%0d rd=%0d",
        alu_issue_pkt.pc, alu_issue_pkt.rob_tag,
        alu_issue_pkt.rs1_tag, alu_issue_pkt.rs2_tag,
        alu_issue_pkt.rd_tag);
    end
  end
endmodule