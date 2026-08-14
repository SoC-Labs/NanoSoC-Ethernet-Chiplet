# user spec file, compiler rom_via_hdd_rvt_rvt, version r0p0

activity_factor = 5
back_biasing = off
bits = 32
bmux = on
bus_notation = on
check_instname = on
code_file = $(NANOSOC_MULTICORE_HOME)/build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom_chip_core/nanosoc_bootrom_chip_core.bintxt
corners = ff_1p32v_1p32v_125c,ff_1p32v_1p32v_m40c,ss_1p08v_1p08v_125c,ss_1p08v_1p08v_m40c,tt_1p20v_1p20v_25c
cust_comment = 
diodes = on
drive = 6
ema = on
frequency = 250.0
instname = rom_via
left_bus_delim = [
libertyviewstyle = nldm
libname = USERLIB
# See eth_rom.spec for the full derivation. `mode` is the compiler's synthetic
# testcode selector (Options[25], condition "testcode", tooltip "Type of code
# file to generate"); its nine legal values are
#   zeros ones addr iaddr raddr iraddr checkerboard random mixed
# and none of them means "read code_file". It only takes effect when no usable
# code_file is supplied, in which case the compiler fills the array rather than
# failing. `zeros` makes that failure self-evident.
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
# 512 words x 32 bits = 2 KB, matching the placed macro (A[8:0]) and the
# 512-line code file. See eth_rom.spec.
words = 512
