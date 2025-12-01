// tb_top.sv - prints the ALIGNED (decode-side) PC/INSTR pair
`timescale 1ns/1ps
module tb_top;
  // 100 MHz clock
  reg clk = 0; always #5 clk = ~clk;
  reg rst_n = 0;

  // IF observation
  wire        if_v;
  wire [31:0] if_pc, if_instr;

  // DEC observation (aligned after skid #2)
  wire        dec_v;
  wire [31:0] dec_pc, dec_instr;
  wire [4:0]  rs1, rs2, rd;
  wire [31:0] imm;
  wire [1:0]  fu;
  wire [3:0]  alu;
  wire        ld, st, br, j;

  // Absolute path (adjust if you moved the file)
  localparam string HEX_ABS = "../mem/program.hex";
  // Optional alternative at runtime: add xsim testplusarg -testplusarg HEX=... (icache supports +HEX)

  top #(
    .INIT_FILE(HEX_ABS)
  ) DUT (
    .clk(clk),
    .rst_n(rst_n),
    .sink_ready_i(1'b1),         // no backpressure in Phase 1

    // IF taps
    .if_valid_o(if_v),
    .if_pc_o(if_pc),
    .if_instr_o(if_instr),

    // DEC taps (aligned)
    .dec_valid_o(dec_v),
    .dec_pc_o(dec_pc),
    .dec_instr_o(dec_instr),
    .dec_rs1_o(rs1),
    .dec_rs2_o(rs2),
    .dec_rd_o(rd),
    .dec_imm_o(imm),
    .dec_fu_type_o(fu),
    .dec_alu_op_o(alu),
    .dec_is_load_o(ld),
    .dec_is_store_o(st),
    .dec_is_branch_o(br),
    .dec_is_jump_o(j)
  );

  initial begin
    // reset sequence
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    // run long enough to see several fetches
    repeat (120) @(posedge clk);
    $finish;
  end

  // Print the ALIGNED pair from the decode-side bundle
  always @(posedge clk) if (dec_v)
    $display("PC=%08x INSTR=%08x fu=%0d alu=%0d ld=%0d st=%0d br=%0d j=%0d",
             dec_pc, dec_instr, fu, alu, ld, st, br, j);

  // --- Optional: also show IF vs DEC to compare timing (uncomment to use) ---
  // always @(posedge clk) if (dec_v) begin
  //   $display("IF : pc=%08x instr=%08x", if_pc, if_instr);
  //   $display("DEC: pc=%08x instr=%08x", dec_pc, dec_instr);
  // end

endmodule
