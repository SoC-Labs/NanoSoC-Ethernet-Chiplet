#!/bin/bash
cd /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/fpga/haps-sx-pc
source /usr/share/Modules/init/bash 2>/dev/null
module use /research/CAD/EDA-Modulefiles/tools 2>/dev/null
module load haps-sx-tools 2>&1 | tail -1
source ../../set_env.sh >/dev/null
source ../../nanosoc-multicore-system/set_env.sh >/dev/null
source ../../tidelink/set_env.sh >/dev/null
cd build
vivado -mode batch -notrace -source ../scripts/build_vivado_pc.tcl \
   -log build_vivado_pc.log -journal build_vivado_pc.jou
echo "VIV_EXIT=$?" >> build_vivado_pc.log
