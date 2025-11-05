`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_phase1
// Description: Self-contained Phase 1 testbench for i-cache, fetch, skid buffer, and decode.
//   - Embeds a small instruction program directly in the testbench (no external HEX file)
//   - Simulates instruction flow through fetch -> skid -> decode
//   - Prints decoded instruction details each cycle
//////////////////////////////////////////////////////////////////////////////////

module tb_phase1;

  // clock + reset
  reg clk;
  reg rst_n;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk; // 100 MHz clock (10 ns period)
  end

  initial begin
    rst_n = 1'b0;          // active-low reset
    #50;
    rst_n = 1'b1;
  end

  // ------------------- Signals -------------------
  // i-cache <-> fetch
  wire [31:2] icache_index;
  wire        icache_en;
  wire [31:0] icache_rdata;
  wire        icache_rvalid;

  // fetch <-> skid buffer
  wire [31:0] f_pc, f_instr;
  wire        f_valid, f_ready;

  // skid buffer <-> decode
  wire [31:0] d_pc, d_instr;
  wire        d_valid, d_ready;

  // ------------------- Program ROM -------------------
  // Manually embed program instructions here
  reg [31:0] program_mem [0:15]; // 16 words for simplicity

  initial begin
    // Simple test program
    program_mem[0] = 32'h00000013; // NOP           (ADDI x0,x0,0)
    program_mem[1] = 32'h00200093; // ADDI x1,x0,2
    program_mem[2] = 32'h00300113; // ADDI x2,x0,3
    program_mem[3] = 32'h002081B3; // ADD  x3,x1,x2
    program_mem[4] = 32'h00000067; // JALR x0, 0(x0) decode sees FU=BRU, is_jump=1
  end

  // ------------------- i-cache model -------------------
  // behaves like a BRAM ROM (1-cycle latency)
  reg [31:0] icache_data_q;
  reg        icache_valid_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      icache_data_q  <= 32'd0;
      icache_valid_q <= 1'b0;
    end else begin
      if (icache_en) begin
        icache_data_q  <= program_mem[icache_index]; // word-addressed
        icache_valid_q <= 1'b1;
      end else begin
        icache_valid_q <= 1'b0;
      end
    end
  end

  assign icache_rdata  = icache_data_q;
  assign icache_rvalid = icache_valid_q;

  // ------------------- Fetch -------------------
  fetch fetch_inst (
    .clk(clk),
    .rst_n(rst_n),
    .icache_index(icache_index),
    .icache_en(icache_en),
    .icache_rdata(icache_rdata),
    .icache_rvalid(icache_rvalid),
    .pc(f_pc),
    .instr(f_instr),
    .valid(f_valid),
    .ready(f_ready)
  );

  // ------------------- Skid Buffer -------------------
  // NOTE: matches your module header (DATA_WIDTH, active-low rst_n)
  skidbuffer #(
    .DATA_WIDTH(64)                // 32-bit PC + 32-bit INSTR
  ) skid_fd (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(f_valid),
    .ready_in(f_ready),            // output to fetch (upstream ready)
    .data_in({f_pc, f_instr}),     // [63:32]=PC, [31:0]=INSTR

    .valid_out(d_valid),
    .ready_out(d_ready),           // input from decode (downstream ready)
    .data_out({d_pc, d_instr})
  );

  // ------------------- Decode -------------------
  wire [4:0]  rs1, rs2, rd;
  wire [31:0] imm;
  wire [1:0]  fu_type;
  wire [3:0]  alu_op;
  wire [1:0]  ls_size;
  wire        imm_used, rd_used, is_load, is_store, unsigned_load, is_branch, is_jump;

  decode decode_inst (
    .valid_in(d_valid),
    .pc_in(d_pc),
    .instr_in(d_instr),
    .ready_out(d_ready),
    .valid_out(), // not used in this TB
    .pc_out(),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .imm(imm),
    .imm_used(imm_used),
    .fu_type(fu_type),
    .alu_op(alu_op),
    .rd_used(rd_used),
    .is_load(is_load),
    .is_store(is_store),
    .ls_size(ls_size),
    .unsigned_load(unsigned_load),
    .is_branch(is_branch),
    .is_jump(is_jump)
  );

  // decode always ready
  assign d_ready = 1'b1;

  // ------------------- Monitor -------------------
  always @(posedge clk) begin
    if (rst_n && d_valid && d_ready) begin
      $display("T=%0t | PC=%08h INSTR=%08h | FU=%0d ALU=%0d | imm=%08h | L=%b S=%b B=%b J=%b",
               $time, d_pc, d_instr, fu_type, alu_op, imm, is_load, is_store, is_branch, is_jump);
    end
  end

  // ------------------- End Simulation -------------------
  initial begin
    $dumpfile("tb_phase1.vcd");
    $dumpvars(0, tb_phase1);
    #500;
    $finish;
  end

endmodule
