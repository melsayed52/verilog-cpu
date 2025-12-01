// skid_buffer_struct.sv
// One-entry elastic buffer for ready/valid channel.
// Uses your exact interface and an active-high async reset.
module skid_buffer_struct #(
  parameter type T = logic
) (
  input  logic clk,
  input  logic reset,

  // upstream (producer -> skid)
  input  logic valid_in,
  output logic ready_in,
  input  T     data_in,

  // downstream (skid -> consumer)
  output logic valid_out,
  input  logic ready_out,
  output T     data_out
);
  logic        full;       // holding a buffered item?
  T            data_buf;   // renamed from 'buf' to avoid keyword conflict

  // Prefer buffered data if present; otherwise pass-through
  assign valid_out = full ? 1'b1 : valid_in;
  assign data_out  = full ? data_buf : data_in;

  // Accept new input whenever not full (depth = 1)
  assign ready_in  = !full;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      full     <= 1'b0;
      data_buf <= '0;
    end else begin
      // Downstream consumed output this cycle
      if (valid_out && ready_out) begin
        if (full) full <= 1'b0; // released buffered item
      end

      // Capture new data on stall: upstream hands off, downstream not ready
      if (valid_in && ready_in && !ready_out) begin
        data_buf <= data_in;
        full     <= 1'b1;
      end
    end
  end
endmodule
