#!/usr/bin/env python3
"""Build the two SoC variants for the cpu_ss_hsel regression, reading the multicore tree only.

build/shipped.flist    the multicore sim flist, expanded (rc4-lineage build_soc RTL)
build/gated.flist      the same, with the two one-line HSEL gates in build/gated/ copies
build/tb_top_okd2d.sv  cocotb/soc_smoke/tb_top.sv with the D2D error responder replaced by an
                       OKAY responder, so a DMA copy to the peer aperture runs every beat
build/inputs.md5       md5 + mtime of the files that decide the result
Every substitution must match exactly once, or this exits non-zero.
"""
import hashlib, os, re, subprocess, sys, time

NMH = os.environ["NANOSOC_MULTICORE_HOME"]
HERE = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(HERE, "build")
os.makedirs(os.path.join(B, "gated"), exist_ok=True)


def sub_once(text, pat, rep, what):
    new, n = re.subn(pat, rep, text)
    if n != 1:
        sys.exit(f"gen_variants: {what}: expected exactly 1 match, found {n}")
    return new


rtl = os.path.join(NMH, "build_soc", "rtl")
GATES = {
    "nanosoc_ss_cpu_plus.sv": (r"(\.cpu_ss_htrans\s*)\(cpu_ss_htrans\)",
                               r"\1(cpu_ss_hsel ? cpu_ss_htrans : 2'b00)"),
    "nanosoc_multicore_soc.sv": (r"(\.eth_ss_0_htrans\s*)\(eth_ss_slave_htrans\)",
                                 r"\1(eth_ss_slave_hsel ? eth_ss_slave_htrans : 2'b00)"),
}
for name, (pat, rep) in GATES.items():
    src = open(os.path.join(rtl, name)).read()
    open(os.path.join(B, "gated", name), "w").write(sub_once(src, pat, rep, f"gate in {name}"))

shipped = os.path.join(B, "shipped.flist")
subprocess.run([os.path.join(NMH, "scripts", "expand_flist.sh"),
                os.path.join(NMH, "flist", "nanosoc_multicore.flist"), shipped], check=True)
fl = open(shipped).read()
fl = sub_once(fl, r"(?m)^\$\{NANOSOC_MULTICORE_HOME\}/build_soc/rtl/nanosoc_ss_cpu_plus\.sv$",
              os.path.join(B, "gated", "nanosoc_ss_cpu_plus.sv"), "flist line nanosoc_ss_cpu_plus.sv")
fl = sub_once(fl, r"(?m)^\$\{SOCLABS_NANOSOC_SOC_DIR\}/build_soc/rtl/nanosoc_multicore_soc\.sv$",
              os.path.join(B, "gated", "nanosoc_multicore_soc.sv"), "flist line nanosoc_multicore_soc.sv")
open(os.path.join(B, "gated.flist"), "w").write(fl)

tb = open(os.path.join(NMH, "cocotb", "soc_smoke", "tb_top.sv")).read()
tb = sub_once(tb, r"nanosoc_d2d_idle_slave\s*#\(\.DATA_W\(32\)\)\s*u_d2d_idle_slave\s*\([^;]*\);",
              "// verif/cpu_ss_hsel: OKAY responder in place of the error responder.\n"
              "    assign d2d_ahb_m_hready = 1'b1;\n    assign d2d_ahb_m_hresp  = 1'b0;\n"
              "    assign d2d_ahb_m_hrdata = 32'h0;", "D2D idle slave in soc_smoke tb_top")
open(os.path.join(B, "tb_top_okd2d.sv"), "w").write(tb)

with open(os.path.join(B, "inputs.md5"), "w") as f:
    for rel in ["build_soc/rtl/nanosoc_ss_cpu_plus.sv", "build_soc/rtl/nanosoc_multicore_soc.sv",
                "build_soc/rtl/ethernet_ss_ahb_rmii.sv",
                "build_soc/rtl/multicore_ahb_interconnect/multicore_ahb_interconnect/multicore_target_output_CPU_SS_1_SLAVE.v",
                "build_soc/rtl/multicore_ahb_interconnect/multicore_ahb_interconnect/multicore_target_output_ETH_SS_SLAVE.v",
                "build_soc/rtl/eth_ss_ahb_interconnect/eth_ss_ahb_interconnect/eth_ss_ahb_interconnect_lite.v",
                "cocotb/soc_smoke/tb_top.sv"]:
        p = os.path.join(NMH, rel)
        md5 = hashlib.md5(open(p, "rb").read()).hexdigest()
        f.write(f"{md5}  {time.strftime('%Y-%m-%d %H:%M', time.localtime(os.path.getmtime(p)))}  {rel}\n")
print("gen_variants: build/{shipped,gated}.flist, build/gated/, build/tb_top_okd2d.sv, build/inputs.md5")
