//////////////////////////////////////////////////////////////////////////////////
// Module Name: recovery_ctrl
// Description: Centralized recovery/flush controller for Phase 4.
//   - Always predict not-taken.
//   - If branch/jump resolves taken => mispredict => assert flush + recover
//     for 1 cycle, and provide redirect PC.
// Additional Comments:
//   - Outputs are 1-cycle pulses when a mispredict event is seen.
//   - Assumes mispredict_i is asserted with stable recover_tag_i/target_pc_i.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module recovery_ctrl (
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 mispredict_i,
  input  logic [31:0]          target_pc_i,
  input  logic [ooop_types::ROB_W-1:0] recover_tag_i,

  output logic                 flush_o,
  output logic [31:0]          flush_pc_o,

  output logic                 recover_o,
  output logic [ooop_types::ROB_W-1:0] recover_tag_o
);

  import ooop_types::*;

  // one-cycle pulse generation
  logic mp_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mp_q <= 1'b0;
    end else begin
      mp_q <= mispredict_i;
    end
  end

  wire fire = mispredict_i && !mp_q; // rising edge

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      flush_o       <= 1'b0;
      flush_pc_o    <= 32'd0;
      recover_o     <= 1'b0;
      recover_tag_o <= '0;
    end else begin
      flush_o   <= fire;
      recover_o <= fire;

      if (fire) begin
        flush_pc_o    <= target_pc_i;
        recover_tag_o <= recover_tag_i;
      end
    end
  end

endmodule
