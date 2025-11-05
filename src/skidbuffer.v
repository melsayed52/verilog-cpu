//////////////////////////////////////////////////////////////////////////////////
// Module Name: skidbuffer
// Description: one-entry pipeline skid buffer. pass-through when ready_out=1,
//              capture one beat when ready_out drops while valid_in=1.
// Additional Comments: synchronous, active-low reset (rst_n).
//////////////////////////////////////////////////////////////////////////////////
module skidbuffer #(
  parameter DATA_WIDTH = 32
)(
  input                   clk,
  input                   rst_n,        // synchronous, active-low

  // upstream (producer -> skid)
  input                   valid_in,
  output                  ready_in,
  input  [DATA_WIDTH-1:0] data_in,

  // downstream (skid -> consumer)
  output                  valid_out,
  input                   ready_out,
  output [DATA_WIDTH-1:0] data_out
);

  reg                    skid_valid;
  reg [DATA_WIDTH-1:0]   skid_data;

  // prefer skidded data when present
  assign valid_out = skid_valid | valid_in;
  assign data_out  = skid_valid ? skid_data : data_in;

  // allow new input if downstream is ready or we are not holding a skidded beat
  assign ready_in  = ready_out || (skid_valid == 1'b0);

  always @(posedge clk) begin
    if (!rst_n) begin
      skid_valid <= 1'b0;
      skid_data  <= {DATA_WIDTH{1'b0}};
    end else begin
      // release skidded beat once downstream is ready
      if (ready_out)
        skid_valid <= 1'b0;

      // late stall capture
      if (!ready_out && (skid_valid == 1'b0) && valid_in) begin
        skid_valid <= 1'b1;
        skid_data  <= data_in;
      end
    end
  end
endmodule
