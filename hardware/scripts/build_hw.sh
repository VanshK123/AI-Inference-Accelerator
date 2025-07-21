#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PDK_ROOT="$ROOT_DIR/../asic/pdk"

# Lint and simulate using Verilator
verilator -Wall --lint-only $ROOT_DIR/rtl/top_level.sv $ROOT_DIR/rtl/*.sv

# Basic simulation
verilator -cc $ROOT_DIR/rtl/top_level.sv --exe $ROOT_DIR/../verification/golden_model/resnet50_numpy.py
make -C obj_dir -f Vtop_level.mk

# Synthesis using Synopsys DC
dc_shell -f <(cat <<EOT
set_app_var search_path "$PDK_ROOT $ROOT_DIR/rtl"
set_app_var target_library [list $PDK_ROOT/lib/tsmc5nm.lib]
set_app_var link_library "* $PDK_ROOT/lib/tsmc5nm.lib"
read_file -rtl $ROOT_DIR/rtl/top_level.sv
elaborate top_level
compile_ultra
write -format verilog -hierarchy -output $ROOT_DIR/out/top_level_g.v
report_area -hierarchy > $ROOT_DIR/out/area.rpt
report_timing > $ROOT_DIR/out/timing.rpt
quit
EOT
)
