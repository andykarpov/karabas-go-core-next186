#!/bin/bash
# Simulate the floppy drives (fdd_port.v + img_sdc.v) against a model of the mcu
# firmware with ISim: reads, writes and a format as the BIOS does them.
# Usage: src/sim/run_fdd_sim.sh [path to ISE_DS/settings64.sh]
set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
set --
source "$SETTINGS" > /dev/null
cd "$(dirname "$0")"
mkdir -p build/fdd
cd build/fdd
cat > tb.prj <<PRJ
verilog work "../../../../modules/rtl/mcu/img_sdc.v"
verilog work "../../../rtl/fdd/fdd_port.v"
verilog work "../../tb_fdd.v"
PRJ
fuse -prj tb.prj -top work.tb_fdd -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "ERROR|errors" sim.log | head -40
grep -q "tb_fdd: 0 errors" sim.log
