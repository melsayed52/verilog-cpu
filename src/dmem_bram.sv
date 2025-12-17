//////////////////////////////////////////////////////////////////////////////////
// Module Name: dmem_bram
// Description: Simple BRAM-backed data memory model with fixed 2-cycle latency.
//              - request accepted on en_i
//              - response valid asserted 2 cycles later (for both loads/stores)
//              - stores update memory on accept
// Additional Comments:
//   - byte addressing; internal storage is word array.
//   - phase 3: extra cycle to mimic memory latency.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module dmem_bram #(
  parameter int DEPTH_WORDS = 1024
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // request (BRAM-style)
  input  logic                 en_i,
  input  logic                 we_i,
  input  logic [31:0]          addr_i,
  input  logic [31:0]          wdata_i,
  input  ooop_types::ls_size_t size_i,

  // response (2 cycles after en_i)
  output logic                 rvalid_o,
  output logic [31:0]          rdata_o
);

  import ooop_types::*;

  logic [31:0] mem [0:DEPTH_WORDS-1];

  // pipeline regs for returning data 2 cycles later
  logic        v1_q, v2_q;
  logic [31:0] rdata1_q, rdata2_q;

  // derived word index
  logic [$clog2(DEPTH_WORDS)-1:0] word_idx;
  assign word_idx = addr_i[2 +: $clog2(DEPTH_WORDS)];

  // store mask helper (writes into selected bytes/half/word)
  function automatic [31:0] write_merge(
    input [31:0] old_word,
    input [31:0] new_word,
    input ls_size_t sz,
    input [1:0]  off
  );
    logic [31:0] m;
    begin
      m = old_word;

      unique case (sz)
        LS_B: begin
          unique case (off)
            2'd0: m[7:0]   = new_word[7:0];
            2'd1: m[15:8]  = new_word[7:0];
            2'd2: m[23:16] = new_word[7:0];
            default: m[31:24] = new_word[7:0];
          endcase
        end

        LS_H: begin
          if (off[1]) m[31:16] = new_word[15:0];
          else        m[15:0]  = new_word[15:0];
        end

        default: begin
          m = new_word;
        end
      endcase

      write_merge = m;
    end
  endfunction

  integer i;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v1_q     <= 1'b0;
      v2_q     <= 1'b0;
      rdata1_q <= 32'd0;
      rdata2_q <= 32'd0;

      // optional init
      for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
        mem[i] <= 32'd0;
      end
    end else begin
      // stage 0 accept
      v1_q <= en_i;

      if (en_i) begin
        if (we_i) begin
          mem[word_idx] <= write_merge(mem[word_idx], wdata_i, size_i, addr_i[1:0]);
          rdata1_q      <= 32'd0;
        end else begin
          rdata1_q      <= mem[word_idx];
        end
      end

      // stage 1 -> stage 2
      v2_q     <= v1_q;
      rdata2_q <= rdata1_q;
    end
  end

  assign rvalid_o = v2_q;
  assign rdata_o  = rdata2_q;

endmodule
