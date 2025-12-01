////////////////////////////////////////////////////////////////////////////////
// Module: skidbuffer
// Description: One‑entry pipeline skid buffer.  When the downstream stage
// indicates ready_out=1, the buffer passes data straight through.  If
// ready_out drops while valid_in=1, the buffer captures one beat and
// holds it until downstream is ready again.  A flush input clears any
// buffered beat immediately.  Active‑low synchronous reset.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module skidbuffer #(
  parameter DATA_WIDTH = 32
)(
  input                   clk,
  input                   rst_n,        // synchronous, active‑low

  // flush: drop any buffered beat this cycle
  input                   flush_i,

  // upstream (producer → skid)
  input                   valid_in,
  output                  ready_in,
  input  [DATA_WIDTH-1:0] data_in,

  // downstream (skid → consumer)
  output                  valid_out,
  input                   ready_out,
  output [DATA_WIDTH-1:0] data_out
);

  reg                    skid_valid;
  reg [DATA_WIDTH-1:0]   skid_data;

  // Prefer skidded data when present
  assign valid_out = skid_valid | valid_in;
  assign data_out  = skid_valid ? skid_data : data_in;

  // Allow new input if downstream is ready or we are not holding a skidded beat
  assign ready_in  = ready_out || (skid_valid == 1'b0);

  always @(posedge clk) begin
    if (!rst_n) begin
      skid_valid <= 1'b0;
      skid_data  <= {DATA_WIDTH{1'b0}};
    end else begin
      // Explicit flush wins
      if (flush_i) begin
        skid_valid <= 1'b0;
      end else begin
        // Release skidded beat once downstream is ready
        if (ready_out)
          skid_valid <= 1'b0;
        // Late stall capture: capture new beat when downstream not ready and no beat buffered
        if (!ready_out && (skid_valid == 1'b0) && valid_in) begin
          skid_valid <= 1'b1;
          skid_data  <= data_in;
        end
      end
    end
  end
endmodule