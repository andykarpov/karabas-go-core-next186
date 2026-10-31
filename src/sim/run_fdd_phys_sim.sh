#!/bin/bash
# Simulate the physical floppy drive of the Karabas Go (tb_fdd_phys.v: fdd_port PHYS 1 +
# pcxt_fdd_phys + the drive model fdd_model.v) with iverilog, a few minutes.
# Usage: src/sim/run_fdd_phys_sim.sh [+vcd]
set -e
cd "$(dirname "$0")"
mkdir -p build
F=../rtl/fdd
iverilog -g2005 -o build/tb_fdd_phys.vvp -s tb_fdd_phys tb_fdd_phys.v fdd_model.v \
	$F/fdd_port.v $F/pcxt_fdd_phys.v $F/mfm_rx.v $F/mfm_tx.v
vvp -n build/tb_fdd_phys.vvp "$@" | tee build/tb_fdd_phys.log | grep -E "ERROR|errors|probed|command"
grep -q "tb_fdd_phys: 0 errors" build/tb_fdd_phys.log
