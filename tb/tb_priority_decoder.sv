`timescale 1ns/1ps
module tb_priority_decoder;
  localparam int W = 8;

  logic [W-1:0] in;
  logic [$clog2(W)-1:0] out;
  logic valid;

  priority_decoder #(.WIDTH(W)) dut(.in(in), .out(out), .valid(valid));

  task show(string tag);
    $display("[%0t] %s in=%b  valid=%0d out=%0d", $time, tag, in, valid, out);
  endtask

  initial begin
    $display("[0] TB START (priority_decoder)");
    in = '0;              #1; show("none");          // valid=0
    in = 8'b1000_0000;    #1; show("bit7");          // out=7
    in = 8'b0000_0001;    #1; show("bit0");          // out=0
    in = 8'b0101_0000;    #1; show("bits6,4");       // out=4
    in = 8'b0010_0010;    #1; show("bits5,1");       // out=1
    in = 8'b0000_1000;    #1; show("bit3");          // out=3
    in = '0;              #1; show("none again");
    $display("✅ priority_decoder TB done."); $finish;
  end
endmodule
