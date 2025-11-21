////////////////////////////////////////////////////////////////////////////////
// File: ooop_defs.vh
// Description: Common parameters, widths, and enumerations for the OoO core.
//
// This header defines basic architectural sizes and enumerations used across
// the out‑of‑order CPU.  It is included by many modules to ensure that tag
// widths and structural sizes remain consistent.  You may adjust the
// parameters here to experiment with different physical register counts or
// reorder buffer depths, but keep in mind that other modules may assume
// specific relationships between the values (e.g. NUM_PHYS_REGS must be
// greater than or equal to N_ARCH_REGS).
////////////////////////////////////////////////////////////////////////////////

`ifndef OOOP_DEFS_VH
`define OOOP_DEFS_VH

// Basic machine word length.  All general purpose registers and immediates
// are XLEN bits wide.  For a RV32I design this is 32.  To experiment with
// RV64I set this parameter to 64 and adjust supporting logic accordingly.
parameter integer XLEN        = 32;

// Architectural and physical register counts.  N_ARCH_REGS should match the
// number of integer registers defined by the ISA (e.g. 32 for RV32I).  The
// physical register file must be larger to permit register renaming – the
// difference between N_PHYS_REGS and N_ARCH_REGS represents the free pool
// used during rename.  Make sure that N_PHYS_REGS ≥ N_ARCH_REGS or the
// freelist will initialize with no free tags.
parameter integer N_ARCH_REGS = 32;
parameter integer N_PHYS_REGS = 128;

// Reorder buffer depth.  ROB_ENTRIES controls how many in‑flight
// instructions may be tracked between dispatch and commit.  The tag width
// ROB_TAG_W is derived below using clog2.
parameter integer ROB_ENTRIES = 16;

// Ceiling of log2 for integers.  Many modules use this helper to derive
// pointer widths based on the size of a structure.  It iterates from
// value‑1 down to 1, counting the number of shifts required to reach 0.
function integer clog2;
  input integer value;
  integer i;
  begin
    clog2 = 0;
    for (i = value-1; i > 0; i = i >> 1)
      clog2 = clog2 + 1;
  end
endfunction

// Physical register tag width derived from N_PHYS_REGS.  A tag of this width
// can uniquely identify any entry in the physical register file.
parameter integer PREG_W    = clog2(N_PHYS_REGS);

// ROB tag width derived from ROB_ENTRIES.  A tag of this width can
// uniquely address any entry in the reorder buffer.
parameter integer ROB_TAG_W = clog2(ROB_ENTRIES);

// Functional unit type encoding.  These values categorise instructions so
// that the dispatch logic can route them to the appropriate reservation
// station.  FU_ALU is used for arithmetic/logic operations, FU_LSU for
// loads/stores, and FU_BRU for branches and jumps.
parameter [1:0] FU_ALU = 2'd0;
parameter [1:0] FU_LSU = 2'd1;
parameter [1:0] FU_BRU = 2'd2;

// LSU size encodings.  The load/store unit accepts a two‑bit size field
// indicating whether the access is a byte, halfword or word.  When
// extending this to 64‑bit loads/stores you should add a new encoding.
parameter [1:0] LS_BYTE = 2'd0;
parameter [1:0] LS_HALF = 2'd1;
parameter [1:0] LS_WORD = 2'd2;

`endif // OOOP_DEFS_VH