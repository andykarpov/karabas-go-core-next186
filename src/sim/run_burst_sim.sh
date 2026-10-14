#!/bin/bash
# Simulate tb_mcu_burst.vhd with ISim (Xilinx ISE 14.7).
# Usage: src/sim/run_burst_sim.sh [path to ISE_DS/settings64.sh]

set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
source "$SETTINGS" > /dev/null

cd "$(dirname "$0")"
RTL=../rtl
OUT=build
mkdir -p $OUT
cd $OUT

# the queue (rtl/fifo/fifo.v, module fifo1) cannot be elaborated from VHDL with an unconnected
# port in ISim: use a behavioural VHDL model of it (synthesis keeps the verilog file)
vhpcomp -work work ../fifo1_sim.vhd
vhpcomp -work work ../$RTL/spi/spi_slave.vhd ../$RTL/mcu/burst_rx.vhd ../$RTL/mcu/mcu.vhd ../tb_mcu_burst.vhd
echo "run 2 ms; quit" > run.tcl

# mcu CLK 50 MHz, classic frames at 8 MHz (spi_freq 8). Bursts: Go / Mini (BURST_MAX_MHZ 0) at the
# link clock, 8 MHz (and 16 MHz as margin); Mini G (BURST_MAX_MHZ 32) at 32 MHz
run_case() {
	name=$1; shift
	fuse -top work.tb_mcu_burst -o tb_$name.exe "$@" > fuse_$name.log
	./tb_$name.exe -tclbatch run.tcl > sim_$name.log
	grep -E "Note:" sim_$name.log | sed "s/^/[$name] /"
	if grep -q "Error:" sim_$name.log; then
		grep "Error:" sim_$name.log | head -5
		echo "SIMULATION FAILED ($name)"
		exit 1
	fi
	grep -q "tb_mcu_burst: finished" sim_$name.log || { echo "SIMULATION DID NOT FINISH ($name)"; exit 1; }
}
run_case burst8 -generic_top "BURST_SCK_HALF_PS=62500"
run_case burst16 -generic_top "BURST_SCK_HALF_PS=31250"
run_case burst32 -generic_top "BURST_SCK_HALF_PS=15625" -generic_top "MAX_MHZ=32"
echo "SIMULATION PASSED"
