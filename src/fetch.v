//////////////////////////////////////////////////////////////////////////////////
// Module Name: fetch
// Description: Single-instruction fetch stage (Phase 1)
//   - Fetches one 32-bit instruction from i-cache per cycle
//   - Increments PC by +4 on each accepted instruction
//   - Holds output if downstream not ready
// Additional Comments:
//   - Word-aligned (PC[1:0] == 2'b00)
//   - No branch prediction or BTB yet
//////////////////////////////////////////////////////////////////////////////////
module fetch #(
  parameter PC_RESET = 32'h0000_0000
)(
  input  wire        clk,
  input  wire        rst_n,

  // i-cache interface
  output reg  [31:2] icache_index,  // word index = PC[31:2]
  output reg         icache_en,     // read enable
  input  wire [31:0] icache_rdata,  // fetched instruction
  input  wire        icache_rvalid, // asserted when rdata is valid

  // handshake to decode
  output reg  [31:0] pc,
  output reg  [31:0] instr,
  output reg         valid,
  input  wire        ready
);

  // internal state
  reg [31:0] pc_reg;
  reg [31:0] instr_reg;
  reg        valid_reg;

  wire can_issue_read = ~(valid_reg && !ready);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_reg       <= PC_RESET;
      instr_reg    <= 32'h00000013; // NOP
      valid_reg    <= 1'b0;
      icache_index <= PC_RESET[31:2];
      icache_en    <= 1'b0;
    end else begin
      icache_en <= 1'b0;

      // issue read if not stalled
      if (can_issue_read) begin
        icache_index <= pc_reg[31:2];
        icache_en    <= 1'b1;
      end

      // capture instruction when valid
      if (icache_rvalid) begin
        instr_reg <= icache_rdata;
        valid_reg <= 1'b1;
      end

      // advance PC when downstream ready
      if (valid_reg && ready) begin
        pc_reg    <= pc_reg + 32'd4;
        valid_reg <= 1'b0;
      end
    end
  end

  // drive outputs
  always @* begin
    pc    = pc_reg;
    instr = instr_reg;
    valid = valid_reg;
  end

endmodule
