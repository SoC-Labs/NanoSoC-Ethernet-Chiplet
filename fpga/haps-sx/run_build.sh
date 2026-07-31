#!/bin/bash
cd /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/fpga/haps-sx
source ../../set_env.sh > /dev/null
source ../../nanosoc-multicore-system/set_env.sh > /dev/null
source ../../tidelink/set_env.sh > /dev/null
cd build
vivado -mode batch -notrace -source ../scripts/build_vivado.tcl \
   -log chiplet_build.log -journal chiplet_build.jou
echo "EXIT=$?" >> chiplet_build.log
