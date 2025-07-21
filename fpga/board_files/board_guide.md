# FPGA Bring-Up Guide

## JTAG Setup
1. Connect the JTAG programmer to the JTAG header.
2. Ensure `FTDI` drivers are installed and the cable is recognized.
3. Verify connectivity using `vivado -mode tcl -source jtag_detect.tcl`.

## Power-Rail Sequencing
1. Apply 3.3V auxiliary rail.
2. After 10ms, enable 1.2V core rail.
3. Finally enable the 0.9V transceiver rail and monitor current draw.

## PCIe Lane Mapping
- Lane 0: Bank 128, pins `PCIE_TX0/PCIE_RX0`
- Lane 1: Bank 128, pins `PCIE_TX1/PCIE_RX1`
- Lane 2: Bank 129, pins `PCIE_TX2/PCIE_RX2`
- Lane 3: Bank 129, pins `PCIE_TX3/PCIE_RX3`

## Clock Constraints
Reference clock at 100 MHz is driven on pin `REFCLK_P`. Constrain in XDC as:
```tcl
create_clock -name pcie_clk -period 10.0 [get_ports REFCLK_P]
```

## Vivado Flow Commands
```bash
vivado -source scripts/generate_bitstream.tcl -tclargs board
```
This runs synthesis, implementation, and bitstream generation using the provided constraints.

## Smoke Tests
1. Program the FPGA with the generated bitstream.
2. Use `lspci` to confirm the PCIe endpoint enumerates.
3. Run `dma_test` from the host SDK to verify data transfers.
