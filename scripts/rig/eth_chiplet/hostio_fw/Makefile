# ----------------------------------------------------------------------------
# hostio_fw -- three small raw-binary images for the eth chiplet.
#
#   make TARGET=fpga            25.010 MHz  (KR260 fabric, measured)
#   make TARGET=asic            100 MHz     (ASIC signoff clock)
#   make TARGET=asic FAULT=1    heartbeat image also makes HIO-507's one
#                               deliberate access to 0x70000000
#   make check                  re-validate the built binaries
#   make clean
#
# THERE IS NO DEFAULT CLOCK ON PURPOSE.  FW_CORE_HZ is a -D on every compile
# and fw_rt.h #errors without it: the header's SystemCoreClock default of
# 100 MHz is wrong by 4x on the KR260, and that is exactly the sort of silent
# error that reads as a hardware fault later.
#
# Output: build/$(TARGET)/*.bin  (raw binary, NOT ELF, NOT hex), plus .elf,
# .map and .lst beside each one for review.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
# ----------------------------------------------------------------------------

CROSS   ?= arm-none-eabi-
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
SIZE    := $(CROSS)size
PYTHON  ?= python3

TARGET  ?= fpga
FAULT   ?= 0

ifeq ($(TARGET),fpga)
  FW_CORE_HZ := 25010000
else ifeq ($(TARGET),asic)
  FW_CORE_HZ := 100000000
else
  $(error TARGET must be 'fpga' (25.010 MHz, measured on the KR260 fabric) or \
'asic' (100 MHz, the ASIC signoff clock).  There is no third answer and no default)
endif

# The output directory carries FAULT as well as TARGET.  Building FAULT=1 over
# a FAULT=0 tree would relink an up-to-date fw_start.o against a new
# fw_heartbeat.o and produce a binary nobody can attribute -- this repo has
# been bitten by stale build directories before, so the variants never share
# one.
B := build/$(TARGET)$(if $(filter-out 0,$(FAULT)),-fault,)

# Cortex-M0 (armv6-m baseline) so one binary runs on the M0 and the M0+ alike.
# The SoC's generated memory map declares NANOSOC_DEFAULT_CPU := cortex-m0 and
# the shipping ROMs are built m0plus; baseline code is correct on both.
CPUFLAGS := -mcpu=cortex-m0 -mthumb
CFLAGS   := $(CPUFLAGS) -Os -g3 -std=c11 \
            -ffreestanding -fno-builtin -fno-common \
            -ffunction-sections -fdata-sections \
            -Wall -Wextra -Werror \
            -DFW_CORE_HZ=$(FW_CORE_HZ) -DFW_DO_FAULT=$(FAULT) -I.
ASFLAGS  := $(CPUFLAGS) -g3 -I.
LDFLAGS  := $(CPUFLAGS) -nostdlib -nostartfiles \
            -Wl,--gc-sections -Wl,--build-id=none -Wl,--fatal-warnings

# eth CPU0 IMEM: 32 KB, remap-independent alias.  CPU1 IMEM: 16 KB, at
# 0x10000000 in CPU1's OWN view (0x90000000 is the debug port's alias).
CPU0_BASE  := 0x10000000
CPU0_SIZE  := 0x8000
CPU1_BASE  := 0x10000000
CPU1_SIZE  := 0x4000
CPU0_STACK := 1024
CPU1_STACK := 256

IMAGES := fw_cpu1_park fw_heartbeat fw_mdio_probe
BINS   := $(addprefix $(B)/,$(addsuffix .bin,$(IMAGES)))

.PHONY: all check selftest clean env
all: $(BINS) check

$(B):
	@mkdir -p $(B)

# -- linker scripts (one template, two geometries) ---------------------------
$(B)/fw_cpu0.ld: fw_link.ld.in | $(B)
	$(CC) -E -P -x c -o $@ \
	  -DFW_LOAD_BASE=$(CPU0_BASE) -DFW_LOAD_SIZE=$(CPU0_SIZE) \
	  -DFW_STACK_BYTES=$(CPU0_STACK) -DFW_ENTRY=fw_reset $<

$(B)/fw_cpu1.ld: fw_link.ld.in | $(B)
	$(CC) -E -P -x c -o $@ \
	  -DFW_LOAD_BASE=$(CPU1_BASE) -DFW_LOAD_SIZE=$(CPU1_SIZE) \
	  -DFW_STACK_BYTES=$(CPU1_STACK) -DFW_ENTRY=fw_park $<

# -- objects -----------------------------------------------------------------
$(B)/fw_start.o: fw_start.c fw_rt.h fw_abi.h | $(B)
	$(CC) $(CFLAGS) -c -o $@ $<

$(B)/fw_heartbeat.o: fw_heartbeat.c fw_rt.h fw_abi.h | $(B)
	$(CC) $(CFLAGS) -c -o $@ $<

$(B)/fw_mdio_probe.o: fw_mdio_probe.c fw_rt.h fw_abi.h | $(B)
	$(CC) $(CFLAGS) -c -o $@ $<

$(B)/fw_cpu1_park.o: fw_cpu1_park.S | $(B)
	$(CC) $(ASFLAGS) -c -o $@ $<

# -- links -------------------------------------------------------------------
$(B)/fw_heartbeat.elf: $(B)/fw_start.o $(B)/fw_heartbeat.o $(B)/fw_cpu0.ld
	$(CC) $(LDFLAGS) -T $(B)/fw_cpu0.ld -Wl,-Map=$(B)/fw_heartbeat.map \
	  -o $@ $(B)/fw_start.o $(B)/fw_heartbeat.o

$(B)/fw_mdio_probe.elf: $(B)/fw_start.o $(B)/fw_mdio_probe.o $(B)/fw_cpu0.ld
	$(CC) $(LDFLAGS) -T $(B)/fw_cpu0.ld -Wl,-Map=$(B)/fw_mdio_probe.map \
	  -o $@ $(B)/fw_start.o $(B)/fw_mdio_probe.o

$(B)/fw_cpu1_park.elf: $(B)/fw_cpu1_park.o $(B)/fw_cpu1.ld
	$(CC) $(LDFLAGS) -T $(B)/fw_cpu1.ld -Wl,-Map=$(B)/fw_cpu1_park.map \
	  -o $@ $(B)/fw_cpu1_park.o

# -- raw binaries ------------------------------------------------------------
$(B)/%.bin: $(B)/%.elf
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d -S $< > $(B)/$*.lst
	@$(SIZE) $<

# -- validation --------------------------------------------------------------
# EVERY built image goes through this.  It re-reads the vector table OUT OF THE
# BINARY -- initial SP inside the target memory, reset vector inside the image
# with the Thumb bit SET -- so "the toolchain got the Thumb bit right" is a
# measurement of the artefact and not an assumption about the assembler.
check: $(BINS)
	$(PYTHON) fw_check.py --target $(TARGET) $(BINS)

# No hardware, no serial port.  Every case is a MUTATION: it breaks exactly one
# property of something that passes and asserts the matching check goes red.
selftest:
	$(PYTHON) fw_selftest.py

env:
	@echo "TARGET=$(TARGET)  FW_CORE_HZ=$(FW_CORE_HZ)  FAULT=$(FAULT)"
	@echo "CC=$(CC)"; $(CC) --version | head -1

clean:
	rm -rf build
