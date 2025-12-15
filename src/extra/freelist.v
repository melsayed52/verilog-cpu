`include "ooop_defs.vh"
//////////////////////////////////////////////////////////////////////////////////
// Module Name: freelist
// Description: Simple circular free list for physical registers.
//////////////////////////////////////////////////////////////////////////////////

module freelist #(
  parameter NUM_ARCH = N_ARCH_REGS,
  parameter NUM_PHYS = N_PHYS_REGS,
  parameter TAG_W    = PREG_W
)(
  input                  clk,
  input                  rst_n,
  input                  alloc_req,
  output                 alloc_gnt,
  output [TAG_W-1:0]     alloc_tag,
  input                  free_req,
  input  [TAG_W-1:0]     free_tag,
  output                 empty,
  output                 full
);

  localparam NUM_FREE = NUM_PHYS - NUM_ARCH;
  localparam PTR_W    = clog2(NUM_FREE);

  reg [TAG_W-1:0] fifo [0:NUM_FREE-1];
  reg [PTR_W-1:0] rd_ptr;
  reg [PTR_W-1:0] wr_ptr;
  reg [PTR_W:0]   used;

  integer i;

  always @(posedge clk) begin
    if (!rst_n) begin
      for (i = 0; i < NUM_FREE; i = i + 1)
        fifo[i] <= NUM_ARCH + i;
      rd_ptr <= 0;
      wr_ptr <= 0;
      used   <= NUM_FREE;
    end else begin
      if (alloc_req && alloc_gnt && !(free_req && !full)) begin
        rd_ptr <= rd_ptr + 1'b1;
        used   <= used - 1'b1;
      end else if (free_req && !full && !(alloc_req && alloc_gnt)) begin
        fifo[wr_ptr] <= free_tag;
        wr_ptr       <= wr_ptr + 1'b1;
        used         <= used + 1'b1;
      end else if (alloc_req && alloc_gnt && free_req && !full) begin
        fifo[wr_ptr] <= free_tag;
        wr_ptr       <= wr_ptr + 1'b1;
        rd_ptr       <= rd_ptr + 1'b1;
      end
    end
  end

  assign empty     = (used == 0);
  assign full      = (used == NUM_FREE);
  assign alloc_gnt = alloc_req && !empty;
  assign alloc_tag = fifo[rd_ptr];

endmodule
