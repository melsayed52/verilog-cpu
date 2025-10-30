`timescale 1ns/1ps
module tb_skid_buffer_struct;
  typedef logic [7:0] T;
  logic clk, reset;

  // upstream
  logic valid_in, ready_in;
  T     data_in;

  // downstream
  logic valid_out, ready_out;
  T     data_out;

  skid_buffer_struct #(.T(T)) dut (
    .clk, .reset,
    .valid_in, .ready_in, .data_in,
    .valid_out, .ready_out, .data_out
  );

  // clock
  initial begin clk = 0; forever #5 clk = ~clk; end

  // tiny scoreboard
  T exp_q[$];

  task push(input T d);
    begin
      exp_q.push_back(d);
      @(posedge clk);
      data_in  <= d;
      valid_in <= 1'b1;
      // wait until accepted
      do @(posedge clk); while (!ready_in);
      valid_in <= 1'b0;
    end
  endtask

  // check outputs
  always @(posedge clk) if (valid_out && ready_out) begin
    T exp = exp_q.pop_front();
    assert (data_out === exp)
      else $fatal(1, "[%0t] MISMATCH got=0x%0h exp=0x%0h", $time, data_out, exp);
    $display("[%0t] OUT 0x%0h (ok)", $time, data_out);
  end

  // finish when queue drains
  always @(posedge clk) if (exp_q.size() == 0 && !reset && !valid_in) begin
    // give one extra cycle for any last handshake to print
    @(posedge clk);
    $display("✅ skid_buffer_struct TB done."); 
    $finish;
  end

  // watchdog (won't trigger unless something's wrong)
  initial begin
    #1_000_000; $fatal(1, "Watchdog timeout");
  end

  initial begin
    $display("[0] TB START (skid_buffer_struct)");
    valid_in = 0; data_in = '0; ready_out = 1;
    reset = 1; repeat (2) @(posedge clk); reset = 0;

    // Pass-through only
    push(8'hA0);
    push(8'hA1);
    push(8'hA2);
  end
endmodule
