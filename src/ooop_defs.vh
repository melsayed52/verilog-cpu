`ifndef OOOP_DEFS_VH
`define OOOP_DEFS_VH

// -----------------------------------------------------------------------------
// Global project constants (phase 1-3)
// -----------------------------------------------------------------------------

`define XLEN 32

// architectural and physical register counts
`define N_ARCH_REGS 32
`define N_PHYS_REGS 128

// structure sizes (per spec defaults)
`define ROB_DEPTH 16
`define RS_DEPTH  8

// derived widths
`define REG_W  $clog2(`N_ARCH_REGS)
`define PREG_W $clog2(`N_PHYS_REGS)
`define ROB_W  $clog2(`ROB_DEPTH)
`define RS_W   $clog2(`RS_DEPTH)

`endif // OOOP_DEFS_VH
