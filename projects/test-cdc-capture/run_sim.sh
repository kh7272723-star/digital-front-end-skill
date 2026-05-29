#!/usr/bin/env bash
# Simulation script for ADC Capture Top (multi-clock CDC)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="$SCRIPT_DIR/rtl"
TB_DIR="$SCRIPT_DIR/tb"
WORK_DIR="$SCRIPT_DIR/sim"

mkdir -p "$WORK_DIR"

echo "=== Compiling with Icarus Verilog ==="
iverilog -g2012 -o "$WORK_DIR/sim.vvp" \
    "$RTL_DIR/reset_synchronizer.v" \
    "$RTL_DIR/async_fifo.v" \
    "$RTL_DIR/adc_sample_packer.v" \
    "$RTL_DIR/axis_serializer.v" \
    "$RTL_DIR/adc_capture_top.v" \
    "$TB_DIR/tb_top.v" \
    2>&1

echo ""
echo "=== Running Simulation ==="
timeout 30 vvp "$WORK_DIR/sim.vvp" 2>&1

echo ""
echo "=== Simulation Complete ==="
