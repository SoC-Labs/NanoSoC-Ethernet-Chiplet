# The variables of nanosoc-multicore-system/set_env.sh, and nothing else.
# Do NOT source set_env.sh itself: it can run `make -C sys_desc`, which regenerates build_soc/,
# the only copy of the generated RTL rc4 was synthesised from. It can also move submodules.
# Site paths and IP release directories are read from set_env.sh's own export lines (as text;
# the script is never executed), so this file names none of them. Any can be overridden.
NANOSOC_MULTICORE_HOME ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../nanosoc-multicore-system)
SETENV := $(NANOSOC_MULTICORE_HOME)/set_env.sh
# default of an `export VAR="${VAR:-default}"` line
_setenv_default = $(shell sed -n -E 's|^export $(1)="\$$\{$(1):-(.*)\}"$$|\1|p' $(SETENV) | head -1)
ARM_IP_LIBRARY_PATH ?= $(call _setenv_default,ARM_IP_LIBRARY_PATH)
ifeq ($(ARM_IP_LIBRARY_PATH),)
  $(error ARM_IP_LIBRARY_PATH unset and not found in $(SETENV))
endif
_expand = $(subst $${ARM_IP_LIBRARY_PATH},$(ARM_IP_LIBRARY_PATH),$(1))
# CMSDK: set_env.sh's Corstone-101 candidate. set_env.sh itself prefers its first candidate when
# present, but the two copies differ in cmsdk_fpga_sram.v, the model this bench seeds; the
# Corstone-101 copy is the one cocotb/soc_dma250 uses and 12 of rc4's 14 CMSDK flist lines name.
CMSDK_DIR ?= $(call _expand,$(shell sed -n -E 's|^[[:space:]]*export CMSDK_DIR="(.*Corstone-101.*)"$$|\1|p' $(SETENV) | head -1))
ARM_CORTEXM0PLUS_IP_PATH ?= $(call _expand,$(call _setenv_default,ARM_CORTEXM0PLUS_IP_PATH))
$(foreach v,CMSDK_DIR ARM_CORTEXM0PLUS_IP_PATH,$(if $(wildcard $($(v))),,$(error $(v)='$($(v))' does not exist)))
export NANOSOC_MULTICORE_HOME ARM_IP_LIBRARY_PATH CMSDK_DIR ARM_CORTEXM0PLUS_IP_PATH
export SOCLABS_PROJECT_DIR          := $(NANOSOC_MULTICORE_HOME)
export SOCLABS_NANOSOC_SOC_DIR      := $(NANOSOC_MULTICORE_HOME)
export SOCLABS_NANOSOC_ARCH_TECH_DIR := $(NANOSOC_MULTICORE_HOME)/nanosoc_arch_tech
export SOCLABS_NANOSOC_GEN_DIR      := $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/nanosoc_gen
export SOCLABS_SLCOREM0_TECH_DIR    := $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/rtl/slcorem0_tech
export SOCLABS_SLCOREM0P_TECH_DIR   := $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/rtl/slcorem0p_tech
export SOCLABS_SLDMA230_TECH_DIR    := $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/rtl/sldma230_tech
export SOCLABS_HOSTIO4_TECH_DIR     := $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/rtl/hostio4
export SOCLABS_SOCDEBUG_TECH_DIR    := $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/rtl/socdebug_tech
export ETH_SS_HOME                  := $(NANOSOC_MULTICORE_HOME)/ethernet-subsystem-ahb
export ETHMAC_AHB_HOME              := $(ETH_SS_HOME)/ethernet-mac-ahb
export ETHMAC_IP_DIR                ?= $(ARM_IP_LIBRARY_PATH)/OpenCores-EthMAC
export HA1588_IP_DIR                ?= $(ARM_IP_LIBRARY_PATH)/OpenCores-HA1588
export AHB_BRIDGES_HOME             := $(ETHMAC_AHB_HOME)/amba_wb_bridges
export PHC_AHB_HOME                 := $(NANOSOC_MULTICORE_HOME)/ptp-hardware-clock-ahb
export PHC_HOME                     := $(PHC_AHB_HOME)
export AHB_QSPI_HOME                := $(NANOSOC_MULTICORE_HOME)/ahb_qspi
export SOCLABS_AHB_QSPI_DIR         := $(AHB_QSPI_HOME)
export IPC_MAILBOX_HOME             := $(NANOSOC_MULTICORE_HOME)/inter-processor-communications-ahb
