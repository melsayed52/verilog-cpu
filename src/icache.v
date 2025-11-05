//////////////////////////////////////////////////////////////////////////////////
// Module Name: icache
// Description: Simple synchronous instruction memory (Phase 1)
//   - Acts as ROM storing 32-bit instructions, one per row
//   - Inferred as FPGA BRAM (1-cycle read latency)
//   - Read-only: no write path
// Additional Comments:
//   - Parameterized depth (default 2 KB = 512 words)
//   - Preload program using $readmemh("program.hex")
//////////////////////////////////////////////////////////////////////////////////
module icache #(
  parameter MEM_DEPTH = 512,                   // 512 x 4 bytes = 2 KB
  parameter INIT_FILE = "program.hex"           // initialization file
)(
  input  wire        clk,
  input  wire        rst_n,

  // fetch request
  input  wire [31:2] index,                    // word index = PC[31:2]
  input  wire        en,                       // read enable

  // fetch response
  output reg  [31:0] rdata,                    // instruction word
  output reg         rvalid                    // valid 1 cycle after en
);

  // BRAM memory array (32-bit words)
  reg [31:0] mem [0:MEM_DEPTH-1];

  // preload program code
  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  // registered read for 1-cycle latency
  reg [31:2] index_reg;
  reg        en_reg;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_reg <= 'd0;
      en_reg    <= 1'b0;
      rdata     <= 32'd0;
      rvalid    <= 1'b0;
    end else begin
      index_reg <= index;
      en_reg    <= en;
      if (en)
        rdata <= mem[index];    // synchronous BRAM read
      else
        rdata <= 32'd0;
      rvalid <= en_reg;         // delayed valid (1-cycle)
    end
  end

endmodule
