#!/bin/bash
cd /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/fpga/haps-sx-pc
source /usr/share/Modules/init/bash 2>/dev/null
module use /research/CAD/EDA-Modulefiles/tools 2>/dev/null
module load protocompiler 2>&1
export UC_VCS_HOME=/apps/synopsys/vcs/W-2024.09-SP2-3-PC
source ../../set_env.sh >/dev/null
source ../../nanosoc-multicore-system/set_env.sh >/dev/null
source ../../tidelink/set_env.sh >/dev/null
export CHIPLET_SOC_VCS_FLIST=$PWD/../../build/elab/soc_vcs.f
export CHIPLET_TL_VCS_FLIST=$PWD/../../build/elab/tidelink_vcs.f
cd build
echo "VCS_HOME=$VCS_HOME  UC_VCS_HOME=$UC_VCS_HOME  which protocompiler=$(which protocompiler)"
protocompiler -batch -tcl ../scripts/build_pc.tcl -log build_pc.log
echo "PC_EXIT=$?" >> build_pc.log
