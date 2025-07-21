#!/bin/bash
set -e

./hardware/scripts/build_hw.sh
./software/scripts/build_sdk.sh
./verification/uvmtb/generate_coverage.sh
./fpga/scripts/generate_bitstream.sh

echo "Running performance benchmarks..."
python3 performance/benchmarks/run_benchmarks.py || true
