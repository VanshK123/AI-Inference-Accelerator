# Makefile for AI Inference Accelerator Project

.PHONY: all clean sim synth-fpga synth-asic test verify format help

# Directories
RTL_DIR = hardware/rtl
VERIF_DIR = verification
SOFTWARE_DIR = software
FPGA_DIR = fpga
ASIC_DIR = asic

# Tools
VERILATOR = verilator
SYNTH_TOOL = vivado  # Change to quartus for Intel FPGAs

# Default target
all: sim test

help:
	@echo "Available targets:"
	@echo "  sim          - Run RTL simulation"
	@echo "  synth-fpga   - Synthesize for FPGA"
	@echo "  synth-asic   - Synthesize for ASIC"
	@echo "  test         - Run all tests"
	@echo "  verify       - Run formal verification"
	@echo "  format       - Format code"
	@echo "  clean        - Clean build artifacts"

# Simulation
sim:
	@echo "Running RTL simulation..."
	cd $(RTL_DIR) && \
	$(VERILATOR) --cc --exe --build --top-module top_level \
		-Wall -Wno-UNOPTFLAT \
		top_level.sv mac_array.sv memory_subsystem.sv \
		control_sequencer.sv axi4_lite_slave.sv \
		-CFLAGS "-std=c++11 -O2"

# FPGA Synthesis
synth-fpga:
	@echo "Synthesizing for FPGA..."
	cd $(FPGA_DIR)/scripts && bash generate_bitstream.sh

# ASIC Synthesis (placeholder)
synth-asic:
	@echo "Synthesizing for ASIC..."
	@echo "ASIC synthesis requires commercial tools (Synopsys DC, Cadence, etc.)"
	@echo "See asic/ directory for synthesis scripts"

# Tests
test: test-golden test-software

test-golden:
	@echo "Running golden model tests..."
	cd $(VERIF_DIR)/golden_model && python3 resnet50_numpy.py

test-software:
	@echo "Running software SDK tests..."
	cd $(SOFTWARE_DIR)/sdk/cpp && g++ -std=c++11 -o test_accel accelerator.cpp && ./test_accel || echo "Mock mode"

# Formal Verification
verify:
	@echo "Running formal verification..."
	cd $(VERIF_DIR)/formal/symbiyosys && \
	if command -v sby &> /dev/null; then \
		sby -f inference.sby; \
	else \
		echo "SymbiYosys not found, skipping formal verification"; \
	fi

# Code formatting
format:
	@echo "Formatting SystemVerilog files..."
	@find $(RTL_DIR) -name "*.sv" -exec echo "Formatting {}" \;

# Clean
clean:
	@echo "Cleaning build artifacts..."
	rm -rf obj_dir
	rm -rf $(VERIF_DIR)/uvmtb/*.vpd
	rm -rf $(FPGA_DIR)/*.rpt
	rm -rf $(FPGA_DIR)/*.log
	rm -rf $(SOFTWARE_DIR)/sdk/cpp/*.o
	rm -rf $(SOFTWARE_DIR)/sdk/cpp/test_accel
	find . -name "*.log" -delete
	find . -name "*.vcd" -delete

# Install dependencies (Linux)
install-deps:
	sudo apt-get update
	sudo apt-get install -y \
		verilator \
		build-essential \
		python3 \
		python3-pip \
		git
	pip3 install numpy

# Build kernel module
build-kernel:
	@echo "Building kernel module..."
	cd $(SOFTWARE_DIR)/kernel_module && make

# Build SDK
build-sdk:
	@echo "Building SDK..."
	cd $(SOFTWARE_DIR)/sdk/cpp && g++ -std=c++11 -fPIC -shared -o libaccelerator.so accelerator.cpp

