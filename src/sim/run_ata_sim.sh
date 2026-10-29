#!/bin/bash
# Simulate the virtual HDD (hdf_ata.v with SYNC_BUS + img_sdc.v) against a model of the mcu
# firmware with ISim: reads as the BIOS does them, before and after a CPU reset.
# Usage: src/sim/run_ata_sim.sh [path to ISE_DS/settings64.sh]
set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
set --
source "$SETTINGS" > /dev/null
cd "$(dirname "$0")"
mkdir -p build/ata
cd build/ata
cat > tb.prj <<PRJ
verilog work "../../../../modules/rtl/mcu/img_sdc.v"
verilog work "../../../../modules/rtl/mcu/hdf_ata.v"
verilog work "../../tb_ata.v"
PRJ
fuse -prj tb.prj -top work.tb_ata -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "ERROR|errors" sim.log | head -40
grep -q "tb_ata: 0 errors" sim.log
