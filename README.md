
# Domain-Specific AI Inference Accelerator

> A modular, high-efficiency hardware accelerator for deep neural network inference  
> leveraging parameterizable datapaths, hierarchical memory, and standard interfaces.

---

## Table of Contents

1. [Introduction](#introduction)  
2. [Design Goals](#design-goals)  
3. [High-Level Architecture](#high-level-architecture)  
4. [Datapath Design](#datapath-design)  
   - [MAC Array](#mac-array)  
   - [Precision & Quantization](#precision--quantization)  
5. [Memory Hierarchy](#memory-hierarchy)  
   - [On-Chip Scratchpad](#on-chip-scratchpad)  
   - [DMA Engine](#dma-engine)  
   - [External Memory Interfaces](#external-memory-interfaces)  
6. [Control & Sequencing](#control--sequencing)  
   - [Microcoded Sequencer](#microcoded-sequencer)  
   - [Layer Scheduling](#layer-scheduling)  
7. [Host Interface](#host-interface)  
   - [AXI4-Lite Control Plane](#axi4-lite-control-plane)  
   - [AXI4-Stream Data Plane](#axi4-stream-data-plane)  
   - [PCIe Integration](#pcie-integration)  
8. [Integration & Deployment](#integration--deployment)  
9. [Verification Strategy](#verification-strategy)  
10. [Repository Structure](#repository-structure)  
11. [Getting Started](#getting-started)  
12. [Maintainers](#maintainers)

---

## Introduction

The Domain-Specific AI Inference Accelerator is a hardware IP designed to execute deep neural network inference workloads efficiently. By tailoring datapaths, memory subsystems, and control logic to the characteristics of convolutional and fully connected layers, this design achieves superior utilization and flexibility across edge and cloud platforms.

## Design Goals

- **Modularity**: Parameterizable components allow scaling of compute array dimensions and precision modes.  
- **Efficiency**: Hierarchical buffering and microcoded control reduce idle cycles and external memory traffic.  
- **Interoperability**: Standardized interfaces (AXI4, PCIe) facilitate seamless integration into FPGA or ASIC systems.  
- **Extensibility**: Clear IP boundaries support addition of new layer types or mixed-precision modes without major RTL rewrite.

## High-Level Architecture

```
+--------------------------------------------------------+
|                Top-Level Accelerator                  |
|                                                        |
|  +-----------+    +--------------+    +-------------+  |
|  | Control   |    | Datapath     |    | Memory      |  |
|  | & Sequencer|<->| (MAC Array)  |<->| Subsystem   |  |
|  +-----------+    +--------------+    +-------------+  |
|         ^                   ^                   ^       |
|         |                   |                   |       |
|      AXI4-Lite         AXI4-Stream        External    |
|                                        Memory / PCIe   |
+--------------------------------------------------------+
```

## Datapath Design

### MAC Array

- **Structure**: A two-dimensional grid of Multiply–Accumulate units; dimensions are configurable at synthesis time.  
- **Function**: Executes inner-product operations for convolutional and dense layers.  
- **Scalability**: Supports tiling and partitioning for various layer sizes.

### Precision & Quantization

- **Modes**: INT8, INT16, and optional FLOAT16 support via separate datapath lanes.  
- **Trade-offs**: Lower bit-widths increase parallelism; mixed-precision scheduling managed by the sequencer.

## Memory Hierarchy

### On-Chip Scratchpad

- **Dual-Port BRAM**: Low-latency storage for input tile buffers and partial sums.  
- **Banked Layout**: Allows concurrent read/write by multiple MAC subregions.

### DMA Engine

- **Scatter–Gather**: Moves blocks between external memory and on-chip scratchpad without host CPU intervention.  
- **AXI-DMA**: Complies with AMBA AXI4 specifications for burst transfers.

### External Memory Interfaces

- **HBM/DDR Abstraction**: Parameterized interface layer to adapt to different memory technologies.  
- **Flow Control**: Backpressure mechanisms prevent overrun of on-chip buffers.

## Control & Sequencing

### Microcoded Sequencer

- **Instruction Set**: Custom micro-ops for layer start/end, tile loops, and data transfers.  
- **Programmability**: Firmware-like updates enable new layer patterns without RTL changes.

### Layer Scheduling

- **Dynamic Partitioning**: Breaks layers into tiles based on resource availability.  
- **QoS Policies**: Prioritizes inference streams in multi-tenant scenarios.

## Host Interface

### AXI4-Lite Control Plane

- Exposes configuration registers for mode selection, status monitoring, and sequencing parameters.

### AXI4-Stream Data Plane

- Streamlines bulk tensor transfers with minimal handshake latency.

### PCIe Integration

- **Endpoint Logic**: Implements PCIe Gen3/Gen4 x4 interface.  
- **DMA Control**: Host-driven scatter–gather descriptors for end-to-end data movement.

## Integration & Deployment

- **FPGA**: Synthesizable with Vivado or Quartus; includes board-level constraint files.  
- **ASIC**: Compatible with standard cell synthesis flows (e.g., Synopsys DC); adheres to DRC/LVS requirements.  
- **SDK**: Host-side libraries in C/Python for driver interaction and job dispatch.

## Verification Strategy

- **Unit Tests**: Self-checking Verilog testbenches covering corner-case arithmetic and control paths.  
- **UVM Environment**: Complete functional coverage plan with directed and random tests.  
- **Formal Verification**: Property assertions for deadlock freedom, data integrity, and interface compliance.  
- **Golden Model**: Cycle-accurate reference written in Python with NumPy.

## Repository Structure

```
project-root/
├── README.md
├── hardware/
│   ├── rtl/
│   │   ├── top_level.sv
│   │   ├── mac_array.sv
│   │   └── memory_subsystem.sv
│   ├── constraints/
│   │   └── timing.xdc
│   └── scripts/
│       └── build_hw.sh
├── software/
│   ├── kernel_module/
│   │   ├── src/
│   │   └── Makefile
│   ├── sdk/
│   │   ├── cpp/
│   │   ├── python/
│   │   └── samples/
│   └── scripts/
│       └── build_sdk.sh
├── verification/
│   ├── uvmtb/
│   │   ├── testbench_top.sv
│   │   └── coverage.ucdb
│   ├── formal/
│   │   └── symbiyosys/
│   └── golden_model/
│       └── resnet50_numpy.py
├── fpga/
│   ├── bitstreams/
│   ├── board_files/
│   │   ├── pinout.csv
│   │   └── board_guide.md
│   └── scripts/
│       └── generate_bitstream.sh
├── performance/
│   └── benchmarks/
│       ├── latency_report.csv
│       └── power_report.csv
└── asic/
    ├── pdk/
    └── library/
        └── cell_libs.lef
```

## Getting Started

1. **Prerequisites**  
   - SystemVerilog simulator (Verilator, VCS, etc.)  
   - FPGA toolchain or ASIC synthesis suite  
   - Python 3.x with NumPy  

2. **Clone Repository**  
   ```bash
   git clone https://github.com/VanshK123/AI-Inference-Accelerator.git
   cd AI-Inference-Accelerator
   ```

3. **Simulation**  
   ```bash
   make sim
   ```

4. **Synthesis & Export**  
   ```bash
   make synth-fpga
   make synth-asic
   ```
