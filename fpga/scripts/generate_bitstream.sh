#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="${SCRIPT_DIR}/.."
BIT_DIR="${BOARD_DIR}/../bitstreams"
REPO=$(mktemp -d)

cleanup() { rm -rf "$REPO"; }
trap cleanup EXIT

echo "Cloning hardware sources..."
if ! git clone https://example.com/hardware.git "$REPO"; then
    echo "Failed to clone hardware repository" >&2
    exit 1
fi

source /opt/Xilinx/Vivado/*/settings64.sh || { echo "Vivado settings not found" >&2; exit 1; }

vivado -mode batch -source "$REPO/scripts/build.tcl" -tclargs board || {
    echo "Vivado build failed" >&2
    exit 1
}

mkdir -p "$BIT_DIR"
cp "$REPO/output/board.bit" "$BIT_DIR"/ || {
    echo "Bitstream copy failed" >&2
    exit 1
}

echo "Bitstream generated at $BIT_DIR"
