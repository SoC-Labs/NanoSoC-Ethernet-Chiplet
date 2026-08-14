# user spec file, compiler rom_via_hdd_rvt_rvt, version r0p0

activity_factor = 5
back_biasing = off
bits = 32
bmux = on
bus_notation = on
check_instname = on
code_file = $(NANOSOC_MULTICORE_HOME)/build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom/eth_ss_bootrom.bintxt
corners = ff_1p32v_1p32v_125c,ff_1p32v_1p32v_m40c,ss_1p08v_1p08v_125c,ss_1p08v_1p08v_m40c,tt_1p20v_1p20v_25c
cust_comment = 
diodes = on
drive = 6
ema = on
frequency = 250.0
instname = eth_rom_via
left_bus_delim = [
libertyviewstyle = nldm
libname = USERLIB
# `mode` is NOT a "use my code file" selector. Queried from the compiler's own
# option table (Options[25]): display "Mode", condition "testcode", tooltip
# "Type of code file to GENERATE". Its nine legal values are
#   zeros ones addr iaddr raddr iraddr checkerboard random mixed
# and NONE of them means "read code_file". mode only decides what synthetic
# testcode is substituted when no usable code_file is supplied -- the compiler
# does not fail in that case, it silently fills the array.
# `random` is the vendor default, and it is what made eth_rom ship 512 words of
# random data that matched no firmware in the tree. `zeros` is chosen so that
# the same failure is instantly obvious (word 0 = 0x00000000 is not a legal
# Cortex-M initial MSP) instead of masquerading as plausible code.
mode = zeros
mux = 8
mvt = 
name_case = upper
power_gating = on
power_type = otc
prefix = 
pwr_gnd_rename = vdde:VDDE,vsse:VSSE
right_bus_delim = ]
site_def = off
top_layer = m5-m10
# 512 words x 32 bits = 2 KB. NOT 2048. The placed macro, its LEF/GDS and the
# whole address path are 2 KB: A[8:0] (9-bit), HADDR[10:2] region decode,
# bootrom_gen.py -a 9, and the linker caps the RO region at 2 KB. The code
# files are 512 lines. A 2048-word rebuild yields an 11-bit-address macro that
# matches neither the wrapper nor the placed abstract.
words = 512
