// tb_fifo.sv - deterministic, verbose TB that must terminate
`timescale 1ns/1ps
module tb_fifo;
  localparam int DEPTH = 16;
  typedef logic [7:0] T;

  // DUT I/O
  logic clk = 0, reset = 1;
  logic write_en = 0, read_en = 0;
  T     write_data = '0, read_data;
  logic full, empty;

  // Instantiate FIFO (matches your doc interface)
  fifo #(.T(T), .DEPTH(DEPTH)) dut (
    .clk(clk), .reset(reset),
    .write_en(write_en), .write_data(write_data),
    .read_en(read_en),   .read_data(read_data),
    .full(full), .empty(empty)
  );

  // 100 MHz clock
  always #5 clk = ~clk;

  // ---------- MAIN ----------
  initial begin : main
    int i;
    int guard;

    $display("[%0t] TB START", $time);

    // Hold reset 3 negedges
    repeat (3) @(negedge clk);
    reset = 0;
    $display("[%0t] Deassert reset", $time);

    // ---- PHASE 1: Write exactly DEPTH items (0..DEPTH-1) ----
    for (i = 0; i < DEPTH; i++) begin
      @(negedge clk);
      if (full) $fatal(1, "[%0t] FULL during fill at i=%0d", $time, i);
      write_en   <= 1;
      write_data <= T'(i);
      $display("[%0t] WRITE  i=%0d  data=0x%0h  full=%0b empty=%0b",
               $time, i, T'(i), full, empty);
      @(negedge clk);
      write_en <= 0;
    end
    $display("[%0t] Filled FIFO", $time);

    // ---- PHASE 2: Read exactly DEPTH items and check ----
    for (i = 0; i < DEPTH; i++) begin
      @(negedge clk);
      if (empty) $fatal(1, "[%0t] EMPTY before read at i=%0d", $time, i);
      read_en <= 1;
      @(posedge clk); #1;  // registered read: sample after posedge
      $display("[%0t] READ   i=%0d  got=0x%0h  (full=%0b empty=%0b)",
               $time, i, read_data, full, empty);
      if (read_data !== T'(i))
        $fatal(1, "[%0t] MISMATCH: got=0x%0h exp=0x%0h",
               $time, read_data, T'(i));
      @(negedge clk);
      read_en <= 0;
    end
    $display("[%0t] Drained FIFO", $time);

    // ---- PHASE 3: Wrap stress (interleaved ops) ----
    for (i = 0; i < 2*DEPTH; i++) begin
      // write one (tag with 0xA0+i)
      @(negedge clk);
      if (!full) begin
        write_en   <= 1;
        write_data <= T'(8'hA0 + i);
        $display("[%0t] WRITE  wrap i=%0d data=0x%0h", $time, i, T'(8'hA0 + i));
      end
      @(negedge clk) write_en <= 0;

      // read one (if not empty)
      if (!empty) begin
        @(negedge clk) read_en <= 1;
        @(posedge clk); #1;
        $display("[%0t] READ   wrap i=%0d got=0x%0h", $time, i, read_data);
        @(negedge clk) read_en <= 0;
      end
    end

    // ---- PHASE 4: Final drain until empty (bounded by time) ----
    guard = 0;
    while (!empty && guard < 1000) begin
      guard++;
      @(negedge clk) read_en <= 1;
      @(posedge clk); #1;
      $display("[%0t] READ   final got=0x%0h", $time, read_data);
      @(negedge clk) read_en <= 0;
    end
    if (guard == 1000) $fatal(1, "Guard hit while draining - investigate flags.");

    $display("✅ TB finished without errors.");
    $finish;
  end

  // Optional: protocol assertions (remove if they trip prematurely)
  always @(posedge clk) begin
    assert(!(write_en && full))  else $fatal(1,"Write attempted when FULL");
    assert(!(read_en  && empty)) else $fatal(1,"Read attempted when EMPTY");
  end
endmodule
