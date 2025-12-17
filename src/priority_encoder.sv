//////////////////////////////////////////////////////////////////////////////////
// Module Name: priority_encoder
// Description: finds lowest-index '1' in an input vector.
// Additional Comments:
//   - combinational
//   - used for free-list allocation and rs slot select
//////////////////////////////////////////////////////////////////////////////////

module priority_encoder #(
  parameter int WIDTH = 8
)(
  input  logic [WIDTH-1:0] in,
  output logic             found,
  output logic [$clog2(WIDTH)-1:0] index
);

  integer i;

  always @* begin
    found = 1'b0;
    index = '0;
    for (i = 0; i < WIDTH; i = i + 1) begin
      if (!found && in[i]) begin
        found = 1'b1;
        index = i[$clog2(WIDTH)-1:0];
      end
    end
  end

endmodule
