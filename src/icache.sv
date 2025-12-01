////////////////////////////////////////////////////////////////////////////////
// Module: icache
// Description: Simple synchronous instruction memory (Phase 1).
//
// The instruction cache acts as a ROM storing 32‑bit instructions, one per
// word.  It is inferred as block RAM with a one cycle read latency.
// The memory can be preloaded using $readmemh from INIT_FILE, or via a
// +HEX=path plusarg at runtime.  If no file is found the memory is
// initialised to NOPs.  After elaboration the module prints the first
// few words for debugging.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module icache #(
  parameter int     MEM_DEPTH = 512,                       // 2KB @ 4B/word
  parameter string  INIT_FILE = "../mem/program.hex"       // override from top/tb
)(
  input  logic        clk,
  input  logic        rst_n,

  // fetch request
  input  logic [31:2] index,    // word index = PC[31:2]
  input  logic        en,       // read enable

  // fetch response (valid is one cycle after en)
  output logic [31:0] rdata,
  output logic        rvalid
);

  // BRAM array
  (* rom_style="block", ram_style="block" *)
  logic [31:0] mem [0:MEM_DEPTH-1];

  // Robust init: prefill NOPs, try INIT_FILE, then optional +HEX=path
  int     i;
  int     fd;
  string  hex_from_plusarg;
  bit     loaded;

  initial begin
    for (i = 0; i < MEM_DEPTH; i++) mem[i] = 32'h0000_0013; // NOP
    loaded = 1'b0;
    if (INIT_FILE.len() != 0) begin
      $display("ICACHE: trying INIT_FILE: %0s", INIT_FILE);
      fd = $fopen(INIT_FILE, "r");
      if (fd != 0) begin
        $fclose(fd);
        $readmemh(INIT_FILE, mem);
        $display("ICACHE: loaded INIT_FILE OK");
        loaded = 1'b1;
      end else begin
        $display("ICACHE: INIT_FILE not found");
      end
    end
    if (!loaded && $value$plusargs("HEX=%s", hex_from_plusarg)) begin
      $display("ICACHE: trying +HEX: %0s", hex_from_plusarg);
      fd = $fopen(hex_from_plusarg, "r");
      if (fd != 0) begin
        $fclose(fd);
        $readmemh(hex_from_plusarg, mem);
        $display("ICACHE: loaded +HEX path OK");
        loaded = 1'b1;
      end else begin
        $display("ICACHE: +HEX path not found");
      end
    end
    if (!loaded) $display("ICACHE: WARNING - no hex loaded; running with NOPs.");
    // Show the first few words so we know exactly what's in BRAM.
    for (i = 0; i < 12; i++) begin
      $display("ICACHE: mem[%0d] @ 0x%08x = %08x", i, i*4, mem[i]);
    end
  end

  // Registered (1‑cycle) read timing
  logic [31:2] index_q;
  logic        en_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q <= '0;
      en_q    <= 1'b0;
      rdata   <= 32'h0000_0013;
      rvalid  <= 1'b0;
    end else begin
      index_q <= index;
      en_q    <= en;
      rdata   <= mem[index_q]; // prior‑cycle address phase
      rvalid  <= en_q;         // prior‑cycle enable
    end
  end
endmodule