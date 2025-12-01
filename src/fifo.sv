////////////////////////////////////////////////////////////////////////////////
// Module: fifo
// Description: Circular‑buffer FIFO with registered read.  The FIFO depth
// is parameterised; a DEPTH of 1 effectively becomes a single register.
// The interface provides write_en and read_en signals, along with full
// and empty flags.  The read_data is registered, meaning that the data
// becomes valid on the cycle following a read_en.  This design follows
// common FIFO coding styles and uses a two‑port memory with write and
// read pointers.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module fifo #(
  parameter type T = logic [31:0],
  parameter int  DEPTH = 8,
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
)(
  input  logic clk,
  input  logic reset,          // active‑high synchronous reset

  input  logic write_en,
  input  T     write_data,

  input  logic read_en,
  output T     read_data,

  output logic full,
  output logic empty
);

  // storage and state
  T                mem [0:DEPTH-1];
  logic [PTR_W-1:0] wptr, rptr;
  logic [PTR_W:0]   count;
  T                 read_data_r;

  assign read_data = read_data_r;

  // qualified ops
  wire do_wr = write_en && !full;
  wire do_rd = read_en  && !empty;

  // flags from count
  always_comb begin
    full  = (count == DEPTH);
    empty = (count == 0);
  end

  // main seq logic (registered read)
  always_ff @(posedge clk) begin
    if (reset) begin
      wptr        <= '0;
      rptr        <= '0;
      count       <= '0;
      read_data_r <= '0;
    end else begin
      // write
      if (do_wr) begin
        mem[wptr] <= write_data;
        wptr      <= (wptr == DEPTH-1) ? '0 : wptr + 1'b1;
      end
      // read (data valid THIS clock edge; sample after posedge in TB)
      if (do_rd) begin
        read_data_r <= mem[rptr];
        rptr        <= (rptr == DEPTH-1) ? '0 : rptr + 1'b1;
      end
      // count update (prevents double inc/dec when both fire)
      unique case ({do_wr, do_rd})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: /* no change */ ;
      endcase
    end
  end
endmodule