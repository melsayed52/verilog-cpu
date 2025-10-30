// priority_decoder.sv
// Priority encoder: lowest-index '1' wins.
module priority_decoder #(
  parameter WIDTH = 4
) (
  input  wire [WIDTH-1:0]                 in,
  output logic [$clog2(WIDTH)-1:0]        out,
  output logic                            valid
);
  always_comb begin
    valid = |in;
    out   = '0;
    // Priority: index 0 is highest priority, then 1, 2, ...
    for (int i = 0; i < WIDTH; i++) begin
      if (in[i]) begin
        out = i[$clog2(WIDTH)-1:0];
        break;
      end
    end
  end
endmodule
