//////////////////////////////////////////////////////////////////////////////////
// Module Name: dmem
// Description: Simple synchronous data memory (BRAM) for loads. Acts as a
//              word-addressable memory with one registered read port. The LSU
//              supplies a byte address; the memory uses word index (addr[31:2])
//              and returns a full XLEN-sized word with 1-cycle latency.
// Additional Comments:
//   - For Phase 3 we only need loads. Stores can be added later.
//   - Memory can optionally be initialised from INIT_FILE using $readmemh.
//
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"

module dmem #(
  parameter int     MEM_DEPTH = 1024,                       // 4KB @ 4B/word
  parameter string  INIT_FILE = "../mem/data.hex",          // override from top/tb
  parameter int     XLEN_P    = XLEN
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // Load request
  input  logic [31:0]          addr_i,       // byte address
  input  logic                 req_valid_i,  // read enable

  // Load response (valid is one cycle after req_valid_i)
  output logic [XLEN_P-1:0]    rdata_o,
  output logic                 rvalid_o
);

  // BRAM array (word-addressable)
  (* ram_style="block" *)
  logic [XLEN_P-1:0] mem [0:MEM_DEPTH-1];

  // Optional memory init
  initial begin : init_block
    integer i;
    for (i = 0; i < MEM_DEPTH; i++) begin
      mem[i] = '0;
    end
    if (INIT_FILE != "") begin
      $display("DMEM: attempting to load INIT_FILE=%0s", INIT_FILE);
      $readmemh(INIT_FILE, mem);
    end
  end

  // Registered (1-cycle) read timing
  logic [31:2] index_q;
  logic        en_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q <= '0;
      en_q    <= 1'b0;
    end else begin
      index_q <= addr_i[31:2];   // word index
      en_q    <= req_valid_i;
    end
  end

  always_ff @(posedge clk) begin
    if (en_q) begin
      rdata_o <= mem[index_q];
    end
  end

  assign rvalid_o = en_q;

endmodule
