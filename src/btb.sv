//////////////////////////////////////////////////////////////////////////////////
// Module Name: btb
// Description: 8-entry fully associative Branch Target Buffer with 2-bit BHT
//   - Each entry: valid, tag (PC), target address, 2-bit saturating counter
//   - Lookup: combinational match on PC tag
//   - Update: on branch completion, insert/update entry with actual outcome
//   - 2-bit BHT states: 00=strongly not-taken, 01=weakly not-taken,
//                       10=weakly taken, 11=strongly taken
//   - Predict taken when counter[1] == 1
//   - FIFO replacement policy for new entries
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"

module btb #(
  parameter int ENTRIES = 8
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        flush_i,       // pipeline flush (don't clear BTB)

  // Lookup interface (from fetch) - combinational
  input  logic [31:0] lookup_pc_i,
  output logic        lookup_hit_o,
  output logic        lookup_taken_o,   // predicted taken (BHT[1])
  output logic [31:0] lookup_target_o,

  // Update interface (from branch completion)
  input  logic        update_valid_i,
  input  logic [31:0] update_pc_i,
  input  logic [31:0] update_target_i,
  input  logic        update_taken_i,   // actual outcome
  input  logic        update_is_branch_i // is conditional branch (vs jump)
);

  localparam int IDX_W = $clog2(ENTRIES);

  // BTB entry
  typedef struct packed {
    logic        valid;
    logic [31:0] tag;       // PC
    logic [31:0] target;
    logic [1:0]  bht;       // 2-bit saturating counter
  } btb_entry_t;

  btb_entry_t entries [ENTRIES];

  // FIFO replacement pointer
  logic [IDX_W-1:0] fifo_ptr;

  // ---------------------------------------------------------------------------
  // Lookup (combinational)
  // ---------------------------------------------------------------------------
  logic [ENTRIES-1:0] hit_vec;
  logic [IDX_W-1:0]   hit_idx;
  logic               any_hit;

  always_comb begin
    hit_vec = '0;
    for (int i = 0; i < ENTRIES; i++) begin
      hit_vec[i] = entries[i].valid && (entries[i].tag == lookup_pc_i);
    end
  end

  // Priority encoder to find hit index
  always_comb begin
    hit_idx = '0;
    any_hit = 1'b0;
    for (int i = 0; i < ENTRIES; i++) begin
      if (hit_vec[i] && !any_hit) begin
        hit_idx = i[IDX_W-1:0];
        any_hit = 1'b1;
      end
    end
  end

  assign lookup_hit_o    = any_hit;
  assign lookup_taken_o  = any_hit ? entries[hit_idx].bht[1] : 1'b0;
  assign lookup_target_o = any_hit ? entries[hit_idx].target : 32'd0;

  // ---------------------------------------------------------------------------
  // Update logic
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < ENTRIES; i++) begin
        entries[i] <= '0;
      end
      fifo_ptr <= '0;
    end else begin
      // Note: we don't clear BTB on flush_i - BTB state is still valid

      if (update_valid_i) begin
        // Check if PC already in BTB
        logic found;
        logic [IDX_W-1:0] found_idx;

        found = 1'b0;
        found_idx = '0;
        for (int i = 0; i < ENTRIES; i++) begin
          if (entries[i].valid && (entries[i].tag == update_pc_i) && !found) begin
            found = 1'b1;
            found_idx = i[IDX_W-1:0];
          end
        end

        if (found) begin
          // Update existing entry
          entries[found_idx].target <= update_target_i;

          // Update BHT (2-bit saturating counter)
          if (update_is_branch_i) begin
            if (update_taken_i) begin
              // Increment (saturate at 11)
              if (entries[found_idx].bht != 2'b11)
                entries[found_idx].bht <= entries[found_idx].bht + 1'b1;
            end else begin
              // Decrement (saturate at 00)
              if (entries[found_idx].bht != 2'b00)
                entries[found_idx].bht <= entries[found_idx].bht - 1'b1;
            end
          end
          // For jumps (JAL/JALR), don't update BHT - always taken

`ifdef BTB_DEBUG
          $display("[btb] update existing idx=%0d pc=0x%08x target=0x%08x taken=%0b bht=%0b->%0b",
                   found_idx, update_pc_i, update_target_i, update_taken_i,
                   entries[found_idx].bht,
                   update_taken_i ? 
                     (entries[found_idx].bht == 2'b11 ? 2'b11 : entries[found_idx].bht + 1'b1) :
                     (entries[found_idx].bht == 2'b00 ? 2'b00 : entries[found_idx].bht - 1'b1));
`endif
        end else begin
          // Insert new entry at FIFO position
          entries[fifo_ptr].valid  <= 1'b1;
          entries[fifo_ptr].tag    <= update_pc_i;
          entries[fifo_ptr].target <= update_target_i;
          // Initialize BHT: weakly taken (10) if taken, weakly not-taken (01) if not
          entries[fifo_ptr].bht    <= update_taken_i ? 2'b10 : 2'b01;

          fifo_ptr <= fifo_ptr + 1'b1; // wraps around

`ifdef BTB_DEBUG
          $display("[btb] insert new idx=%0d pc=0x%08x target=0x%08x taken=%0b bht=%0b",
                   fifo_ptr, update_pc_i, update_target_i, update_taken_i,
                   update_taken_i ? 2'b10 : 2'b01);
`endif
        end
      end
    end
  end

endmodule
