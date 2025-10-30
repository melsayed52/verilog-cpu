# Verilog CPU — Phase 0

This repo contains my implementation for **Phase 0** of the Verilog CPU project.

### Implemented modules
- `fifo.sv`
- `priority_decoder.sv`
- `skid_buffer_struct.sv`

Each module has its own self-checking testbench located in the `tb/` directory.

### How to simulate
Open Vivado → Add `src/` as design sources and `tb/` as simulation sources →  
Right-click any testbench (e.g. `tb_fifo.sv`) → **Set as Top** → **Run Simulation**.

---

### Team notes
For Phase 0, my teammate and I decided to work **individually** so we could both get familiar with Vivado, simulation setup, and the project workflow.  
Starting from **Phase 1**, we’ll begin collaborating directly and sharing responsibilities on design and verification.

To run a testbench in Vivado:  
Add `src/` as Design Sources and `tb/` as Simulation Sources → Set any `tb_*.sv` as top → Run Behavioral Simulation.