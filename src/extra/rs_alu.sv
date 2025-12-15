////////////////////////////////////////////////////////////////////////////////
// Module: rs_alu
// Description: Wrapper for the ALU reservation station.  This simply
// instantiates a reservation_station of depth eight and passes through all
// signals.  Using a wrapper helps document the intended width and makes
// top‑level wiring more readable.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"
`include "reservation_station.sv"

module rs_alu (
  input  logic clk,
  input  logic rst_n,
  input  logic flush_i,
  // push interface
  input  logic        push_valid_i,
  output logic        push_ready_o,
  input  rename_pkt_t push_pkt_i,
  input  logic [ROB_TAG_W-1:0] push_rob_tag_i,
  // wakeup
  input  logic        wakeup_valid_i,
  input  logic [PREG_W-1:0] wakeup_tag_i,
  // exec
  input  logic        exec_ready_i,
  output logic        issue_valid_o,
  output issue_pkt_t  issue_pkt_o
);
  reservation_station #(.DEPTH(8)) u_rs (
    .clk(clk), .rst_n(rst_n), .flush_i(flush_i),
    .push_valid_i(push_valid_i), .push_ready_o(push_ready_o),
    .push_pkt_i(push_pkt_i), .push_rob_tag_i(push_rob_tag_i),
    .wakeup_valid_i(wakeup_valid_i), .wakeup_tag_i(wakeup_tag_i),
    .exec_ready_i(exec_ready_i), .issue_valid_o(issue_valid_o), .issue_pkt_o(issue_pkt_o)
  );
endmodule