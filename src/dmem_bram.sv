//////////////////////////////////////////////////////////////////////////////////
// Module Name: dmem_bram
// Description: Data memory, 2-cycle load latency (same interface/behavior as before).
// Synthesis notes (rewritten so Vivado infers a block RAM instead of flip-flops):
//   - No reset on the memory array (a BRAM cannot clear all words in one cycle).
//     Contents start at zero via the initial block (honored for BRAM init + sim).
//   - Sub-word stores use per-byte write enables instead of read-modify-write.
//   - Read data is registered straight out of the array (BRAM output register).
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module dmem_bram #(
  parameter int DEPTH_WORDS = 1024
)(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 en_i,
  input  logic                 we_i,
  input  logic [31:0]          addr_i,
  input  logic [31:0]          wdata_i,
  input  ooop_types::ls_size_t size_i,
  output logic                 rvalid_o,
  output logic [31:0]          rdata_o
);
  import ooop_types::*;

  localparam int AW = $clog2(DEPTH_WORDS);

  (* ram_style = "block" *) logic [31:0] mem [0:DEPTH_WORDS-1];

  initial begin
    for (int n = 0; n < DEPTH_WORDS; n++) mem[n] = 32'd0;
  end

  logic [AW-1:0] word_idx;
  assign word_idx = addr_i[2 +: AW];

  // byte enables + write data replicated into the right byte lanes
  logic [3:0]  be;
  logic [31:0] wdata_lane;
  always_comb begin
    unique case (size_i)
      LS_B: begin
        be         = 4'b0001 << addr_i[1:0];
        wdata_lane = {4{wdata_i[7:0]}};
      end
      LS_H: begin
        be         = addr_i[1] ? 4'b1100 : 4'b0011;
        wdata_lane = {2{wdata_i[15:0]}};
      end
      default: begin
        be         = 4'b1111;
        wdata_lane = wdata_i;
      end
    endcase
  end

  // ---- BRAM port: byte-write, read-first, no reset on the array ----
  logic [31:0] ram_q;
  always_ff @(posedge clk) begin
    if (en_i) begin
      if (we_i) begin
        for (int b = 0; b < 4; b++) begin
          if (be[b]) mem[word_idx][8*b +: 8] <= wdata_lane[8*b +: 8];
        end
      end
      ram_q <= mem[word_idx];
    end
  end

  // ---- control pipeline (matches the original 2-cycle behavior) ----
  // original: stage-1 data was 0 on a write, mem[addr] on a read, and held when en_i=0
  logic v1_q, v2_q, wr_q;
  logic [31:0] rdata2_q;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v1_q     <= 1'b0;
      v2_q     <= 1'b0;
      wr_q     <= 1'b1;   // stage-1 data reads as 0 right after reset (as before)
      rdata2_q <= 32'd0;
    end else begin
      v1_q <= en_i;
      if (en_i) wr_q <= we_i;
      v2_q     <= v1_q;
      rdata2_q <= wr_q ? 32'd0 : ram_q;
    end
  end

  assign rvalid_o = v2_q;
  assign rdata_o  = rdata2_q;

endmodule
