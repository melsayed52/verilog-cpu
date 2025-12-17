//////////////////////////////////////////////////////////////////////////////////
// Module Name: skidbuffer
// Description: 1-entry skid buffer for ready/valid decoupling.
// Additional Comments:
//   - flush_i drops buffered entry (Phase 4 recovery)
//////////////////////////////////////////////////////////////////////////////////

module skidbuffer #(
  parameter int WIDTH = 32
)(
  input  logic             clk,
  input  logic             rst_n,
  input  logic             flush_i,

  input  logic             valid_in,
  output logic             ready_out,
  input  logic [WIDTH-1:0] data_in,

  output logic             valid_out,
  input  logic             ready_in,
  output logic [WIDTH-1:0] data_out
);

  logic             skid_valid;
  logic [WIDTH-1:0] skid_data;

  assign valid_out = skid_valid ? 1'b1 : valid_in;
  assign data_out  = skid_valid ? skid_data : data_in;

  assign ready_out = ready_in || !skid_valid;

  always @(posedge clk) begin
    if (!rst_n) begin
      skid_valid <= 1'b0;
      skid_data  <= '0;
    end else if (flush_i) begin
      skid_valid <= 1'b0;
      skid_data  <= '0;
    end else begin
      if (valid_in && !ready_in && !skid_valid) begin
        skid_valid <= 1'b1;
        skid_data  <= data_in;
      end

      if (skid_valid && ready_in) begin
        skid_valid <= 1'b0;
      end
    end
  end

endmodule
