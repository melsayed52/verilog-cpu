//////////////////////////////////////////////////////////////////////////////////
// Module Name: dispatch_fifo
// Description: 1-entry fifo used by dispatch to buffer rename_pkt.
//   - Supports flush_i to drop buffered entry.
// Additional Comments:
//   - Provides standard valid/ready semantics:
//       in_ready  = !full || (out_ready && out_valid)
//       out_valid = full
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module dispatch_fifo (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   flush_i,

  input  logic                   in_valid,
  output logic                   in_ready,
  input  ooop_types::rename_pkt_t in_pkt,

  output logic                   out_valid,
  input  logic                   out_ready,
  output ooop_types::rename_pkt_t out_pkt
);

  import ooop_types::*;

  logic        full;
  rename_pkt_t storage;

  assign out_valid = full;
  assign out_pkt   = storage;

  // can accept when empty, or when simultaneously popping
  assign in_ready  = !full || (out_ready && out_valid);

  wire do_push = in_valid && in_ready;
  wire do_pop  = out_valid && out_ready;

  always @(posedge clk) begin
    if (!rst_n) begin
      full    <= 1'b0;
      storage <= '0;
    end else if (flush_i) begin
      full    <= 1'b0;
      storage <= '0;
    end else begin
      unique case ({do_push, do_pop})
        2'b10: begin // push only
          full    <= 1'b1;
          storage <= in_pkt;
        end
        2'b01: begin // pop only
          full    <= 1'b0;
          storage <= storage;
        end
        2'b11: begin // push+pop (replace)
          full    <= 1'b1;
          storage <= in_pkt;
        end
        default: begin end
      endcase
    end
  end

endmodule
