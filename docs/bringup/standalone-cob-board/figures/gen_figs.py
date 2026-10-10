#!/usr/bin/env python3
"""Generate the pad-ring map figure, the Appendix C pad table and the COB
fan-out feasibility numbers for STANDALONE_COB_BRINGUP_PLAN.tex.

Usage:  python3 gen_figs.py [path/to/pads_only.csv]
Input : the as-built pad CSV. Default: the repository copy,
        ASIC/submissions/padring_as_built_rzG_20260823/
        nanosoc_eth_chiplet_pads_as_built_pads_only.csv, found relative to this
        script (docs/bringup/standalone-cob-board/figures/ -> repo root).
Output (next to this script): padmap.pdf, appC_rows.tex, cob_feasibility.tex

Conventions (rc4 electrical research report 01):
  * design frame 1600 x 2000 um, origin lower-left; the imec seal ring adds
    20 um on every side (1640 x 2040 um): seal-ring frame = design frame + 20.
  * The CSV centre is the bond-pad CELL centre, not the opening centre.
    Opening-centre depth from the design-frame edge: 36.8 um (outer row,
    PAD70GU_SL) and 138.8 um (inner row, PAD70NU_SL); along the edge it is
    the CSV centre.
  * CSV row 9 (BuPAD_HOST_IO_6) says edge=top; the pad is on the RIGHT edge
    (its IO cell uPAD_HOST_IO_6 says right, and x = 1513 um). Corrected here.
"""
import csv
import math
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm
from matplotlib.patches import Rectangle, Patch

import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FIG = HERE if os.path.basename(HERE) == "figures" else os.path.join(HERE, "figures")
_REPO_CSV = os.path.join(FIG, "..", "..", "..", "..", "ASIC", "submissions",
                         "padring_as_built_rzG_20260823",
                         "nanosoc_eth_chiplet_pads_as_built_pads_only.csv")
if len(sys.argv) > 1:
    CSV = sys.argv[1]
elif os.path.exists(_REPO_CSV):
    CSV = _REPO_CSV
else:
    CSV = os.path.join(FIG, "pads_as_built.csv")

for f in ("Lato-Regular.ttf", "Lato-Bold.ttf", "Lato-Italic.ttf"):
    p = os.path.join("/usr/share/fonts/lato", f)
    if os.path.exists(p):
        fm.fontManager.addfont(p)
plt.rcParams["font.family"] = ["Lato", "DejaVu Sans"]
plt.rcParams["pdf.fonttype"] = 42

W, H = 1600.0, 2000.0          # design frame
SEAL = 20.0
DEPTH = {"o": 36.815, "i": 138.815}   # opening centre from design-frame edge
OPEN_ALONG, OPEN_DEEP = 58.0, 66.0

# ---------------------------------------------------------------- read CSV
rows = list(csv.DictReader(open(CSV)))
io = {r["inst_name"][len("uPAD_"):]: r for r in rows if r["kind"] == "io"}
bp = [r for r in rows if r["kind"] == "bondpad"]

HOSTIO_ROLE = {0: "IOREQ1/TDI", 1: "IOREQ2/TDO", 2: "IOACK",
               3: "IODATA0", 4: "IODATA1", 5: "IODATA2", 6: "IODATA3"}


def label_and_group(name):
    """name is the part after BuPAD_ (e.g. 'TL_RX_3')."""
    if name.startswith(("VDDIO", "VSSIO", "VDD_", "VSS_")):
        base = name.rsplit("_", 2)[0]
        lab = base
        if name == "VDDIO_T_0":
            lab = "VDDIO (POC)"
        return lab, "power"
    if name in ("CLK_I", "NRST_I", "TEST_I", "SE_I"):
        return name[:-2], "clkrst"
    if name in ("SWDCK_I", "SWDIO_IO"):
        return name.split("_")[0], "debug"
    if name.startswith("HOST_IO_"):
        n = int(name[-1])
        return "HOSTIO%d  %s" % (n, HOSTIO_ROLE[n]), "debug"
    if name.startswith("QSPI"):
        return name.replace("QSPI_IO_", "QSPI_IO"), "qspi"
    if name.startswith("RMII"):
        return name, "rmii"
    if name.startswith("TL_") or name.startswith("I2C"):
        return name.replace("TL_RX_", "TL_RX").replace("TL_TX_", "TL_TX"), "d2d"
    raise ValueError(name)


pads = []
for r in bp:
    name = r["inst_name"][len("BuPAD_"):]
    edge = r["edge"]
    iocell = io[name]
    if iocell["edge"] != edge:            # CSV row-9 defect: trust the IO cell
        edge_fixed = iocell["edge"]
    else:
        edge_fixed = edge
    row = "o" if r["cell"] == "PAD70GU_SL" else "i"
    cx, cy = float(r["center_x"]), float(r["center_y"])
    d = DEPTH[row]
    if edge_fixed == "left":
        x, y, along = d, cy, cy
    elif edge_fixed == "right":
        x, y, along = W - d, cy, cy
    elif edge_fixed == "bottom":
        x, y, along = cx, d, cx
    else:
        x, y, along = cx, H - d, cx
    lab, grp = label_and_group(name)
    pads.append(dict(name=name, edge=edge_fixed, csv_edge=edge, row=row,
                     x=x, y=y, along=along, label=lab, group=grp,
                     cell=iocell["cell"], bondcell=r["cell"]))

assert len(pads) == 82, len(pads)
fixed = [p for p in pads if p["edge"] != p["csv_edge"]]
print("edge corrections:", [(p["name"], p["csv_edge"], p["edge"]) for p in fixed])

COL = {"power": "#8C8C8C", "clkrst": "#D55E00", "debug": "#0072B2",
       "qspi": "#009E73", "rmii": "#E69F00", "d2d": "#CC79A7"}
GNAME = {"power": "Power / ground", "clkrst": "Clock, reset, test",
         "debug": "Debug (SWD, HOSTIO4)", "qspi": "QSPI flash",
         "rmii": "RMII / MDIO", "d2d": "TideLink D2D + I²C (parked)"}

# ---------------------------------------------------------------- pad map
S_IN = 0.00223            # inches per micron (figure scale)
LAB_GAP = 230.0           # die edge -> label anchor (um)
XL = -LAB_GAP - 0.90 / S_IN
XR = W + LAB_GAP + 1.42 / S_IN
YB = -LAB_GAP - 0.88 / S_IN
YT = H + LAB_GAP + 1.00 / S_IN
fig = plt.figure(figsize=((XR - XL) * S_IN, (YT - YB) * S_IN))
ax = fig.add_axes([0.0, 0.0, 1.0, 1.0])
ax.set_xlim(XL, XR)
ax.set_ylim(YB, YT)
ax.set_aspect("equal")
ax.axis("off")
print("padmap figure size in: %.2f x %.2f" % ((XR - XL) * S_IN, (YT - YB) * S_IN))

# seal ring + die
ax.add_patch(Rectangle((-SEAL, -SEAL), W + 2 * SEAL, H + 2 * SEAL,
                       fc="#EDEDED", ec="#555555", lw=0.8))
ax.add_patch(Rectangle((0, 0), W, H, fc="#FAFAFA", ec="#555555", lw=0.6))
ax.add_patch(Rectangle((205, 205), 1190, 1590, fc="#F3F6FA", ec="#C9D3E0",
                       lw=0.5))
ax.text(W / 2, 1640, "nanoSoC Ethernet chiplet", ha="center",
        va="center", fontsize=10, weight="bold", color="#222222")
ax.text(W / 2, 1545, "rc4-20260829  ·  TSMC 65 nm LP", ha="center",
        va="center", fontsize=8, color="#222222")
ax.text(W / 2, 1330,
        "Die 1600 × 2000 µm (design frame)\n"
        "1640 × 2040 µm with imec seal ring\n"
        "Sawn size / thickness: not known",
        ha="center", va="center", fontsize=7.5, color="#222222",
        linespacing=1.35)
ax.text(W / 2, 1040,
        "82 bond pads in two staggered rows\n"
        "outer PAD70GU_SL (42), inner PAD70NU_SL (40)\n"
        "opening 58 × 66 µm, 80 µm alternating pitch\n"
        "(67 µm on the left / D2D edge)",
        ha="center", va="center", fontsize=7.5, color="#222222",
        linespacing=1.35)
ax.text(W / 2, 770,
        "Origin: lower-left of the design frame.\n"
        "Opening centres 36.8 µm (outer) and\n"
        "138.8 µm (inner) from the design-frame edge.\n"
        "Seal-ring frame = design frame + 20 µm.",
        ha="center", va="center", fontsize=7, color="#444444",
        linespacing=1.35, style="italic")

FS = 7.4
for p in pads:
    c = COL[p["group"]]
    x, y = p["x"], p["y"]
    e = p["edge"]
    if e in ("left", "right"):
        w_, h_ = OPEN_DEEP, OPEN_ALONG
    else:
        w_, h_ = OPEN_ALONG, OPEN_DEEP
    ax.add_patch(Rectangle((x - w_ / 2, y - h_ / 2), w_, h_, fc=c, ec="#222222",
                           lw=0.3, zorder=3))
    weight = "bold" if p["name"] == "VDDIO_T_0" else "normal"
    if e == "left":
        lx = -LAB_GAP
        ax.plot([x - w_ / 2, -SEAL - 20, lx + 20], [y, y, y], color=c, lw=0.6,
                zorder=2)
        ax.text(lx, y, p["label"], ha="right", va="center", fontsize=FS,
                weight=weight)
    elif e == "right":
        lx = W + LAB_GAP
        ax.plot([x + w_ / 2, W + SEAL + 20, lx - 20], [y, y, y], color=c,
                lw=0.6, zorder=2)
        ax.text(lx, y, p["label"], ha="left", va="center", fontsize=FS,
                weight=weight)
    elif e == "top":
        ly = H + LAB_GAP
        ax.plot([x, x, x], [y + h_ / 2, H + SEAL + 20, ly - 20], color=c,
                lw=0.6, zorder=2)
        ax.text(x, ly, p["label"], ha="center", va="bottom", fontsize=FS,
                rotation=90, weight=weight)
    else:
        ly = -LAB_GAP
        ax.plot([x, x, x], [y - h_ / 2, -SEAL - 20, ly + 20], color=c,
                lw=0.6, zorder=2)
        ax.text(x, ly, p["label"], ha="center", va="top", fontsize=FS,
                rotation=90)

edge_title = {
    "left": "LEFT — TideLink D2D (parked) and I²C",
    "right": "RIGHT — RMII / MDIO and HOSTIO4",
    "top": "TOP — supplies, CLK, NRST, TEST, SE, SWD",
    "bottom": "BOTTOM — supplies, QSPI flash",
}
ax.text(W / 2, YT - 0.08 / S_IN, edge_title["top"], ha="center", va="top",
        fontsize=8.5, weight="bold", color="#222222")
ax.text(W / 2, YB + 0.08 / S_IN, edge_title["bottom"], ha="center",
        va="bottom", fontsize=8.5, weight="bold", color="#222222")
ax.text(XL + 0.10 / S_IN, H / 2, edge_title["left"], ha="center",
        va="center", fontsize=8.5, weight="bold", color="#222222", rotation=90)
ax.text(XR - 0.10 / S_IN, H / 2, edge_title["right"], ha="center",
        va="center", fontsize=8.5, weight="bold", color="#222222", rotation=270)

ax.plot([0], [0], marker="+", color="#000000", ms=6, mew=0.8, zorder=5)
ax.text(-SEAL - 15, -SEAL - 15, "(0,0)", ha="right", va="top", fontsize=7,
        color="#222222", zorder=6,
        bbox=dict(fc="white", ec="none", pad=0.5))

handles = [Patch(fc=COL[k], ec="#222222", lw=0.3, label=GNAME[k])
           for k in ("power", "clkrst", "debug", "qspi", "rmii", "d2d")]
leg = ax.legend(handles=handles, loc="center",
                bbox_to_anchor=((W / 2 - XL) / (XR - XL),
                                (420 - YB) / (YT - YB)),
                ncol=1, fontsize=7.4, frameon=True, framealpha=1.0,
                edgecolor="#BBBBBB", handlelength=1.3, borderpad=0.6,
                labelspacing=0.45)
fig.savefig(os.path.join(FIG, "padmap.pdf"))
plt.close(fig)

# ---------------------------------------------------------------- Appendix C
DIR = {
    "CLK": "in", "NRST": "in", "TEST": "in", "SE": "in", "SWDCK": "in",
    "SWDIO": "bidir", "QSPI_SCLK": "out", "QSPI_nCS": "out",
}


def pad_dir(p):
    n = p["name"]
    if p["group"] == "power":
        return "supply"
    for k, v in DIR.items():
        if n.startswith(k):
            return v
    if n.startswith("HOST_IO"):
        return "bidir"
    if n.startswith("QSPI_IO"):
        return "bidir"
    if n in ("RMII_TXD0", "RMII_TXD1", "RMII_TX_EN", "RMII_MDC"):
        return "out"
    if n == "RMII_MDIO":
        return "bidir"
    if n.startswith("RMII"):
        return "in"
    if n.startswith("TL_TX") or n == "TL_CLK_TX":
        return "out"
    if n.startswith("TL_RX") or n == "TL_CLK_RX":
        return "in"
    if n.startswith("I2C"):
        return "od"
    raise ValueError(n)


order = {"left": 0, "top": 1, "right": 2, "bottom": 3}
pads_sorted = sorted(pads, key=lambda p: (order[p["edge"]], p["along"]))


def tex(s):
    return s.replace("_", r"\_").replace("·", "").replace("  ", " ")


lines = []
for i, p in enumerate(pads_sorted, 1):
    lab = p["label"].split("  ")[0]
    if p["name"] == "VDDIO_T_0":
        lab = "VDDIO (POC)"
    note = ""
    if p["name"] == "HOST_IO_6":
        note = r"\textsuperscript{a}"
    lines.append(
        r"%d & %s%s & \texttt{%s} & %s & %s & \texttt{%s} & %.1f & %.1f & %.1f & %.1f \\"
        % (i, tex(lab), note, tex(p["name"]), p["edge"], p["row"],
           tex(p["cell"]), p["x"], p["y"], p["x"] + SEAL, p["y"] + SEAL))
    lines[-1] = lines[-1].replace(r"\texttt{%s}" % tex(p["cell"]),
                                  r"\texttt{%s}" % tex(p["cell"]))
    # keep pad direction for a separate check
    p["dir"] = pad_dir(p)
open(os.path.join(FIG, "appC_rows.tex"), "w").write("\n".join(lines) + "\n")

# counts check
from collections import Counter
print("per edge:", Counter(p["edge"] for p in pads))
print("per group:", Counter(p["group"] for p in pads))
print("rows:", Counter(p["row"] for p in pads))

# ---------------------------------------------------------------- COB fan-out
# Single-row finger ring, fingers >= 150 um wide with >= 100 um gaps (250 um
# pitch), centred on each die edge; distances measured from the seal-ring
# outer edge (the sawn edge is not known, so real distances are larger by the
# scribe width). Wire from opening centre to finger centre.
PITCH = 250.0
res = []
for e in ("left", "top", "right", "bottom"):
    ps = sorted([p for p in pads if p["edge"] == e], key=lambda p: p["along"])
    n = len(ps)
    edge_len = (H if e in ("left", "right") else W) + 2 * SEAL
    centre = (H if e in ("left", "right") else W) / 2.0
    fingers = [centre + (k - (n - 1) / 2.0) * PITCH for k in range(n)]
    dmax = max(abs(f - p["along"]) for f, p in zip(fingers, ps))
    row_len = (n - 1) * PITCH + 150.0
    # perpendicular distance from the opening to the finger row, for 45 deg:
    # need D >= dmax. Opening depth from the seal-ring edge: 56.8 / 158.8 um.
    # minimum ring offset from the seal-ring edge so that every wire <= 45 deg
    worst = 0.0
    for f, p in zip(fingers, ps):
        depth_sr = DEPTH[p["row"]] + SEAL
        need = abs(f - p["along"]) - depth_sr
        worst = max(worst, need)
    res.append((e, n, edge_len, row_len, dmax, worst))
    print(e, n, "edge", edge_len, "row", row_len, "max along-offset %.0f" % dmax,
          "min ring offset for 45deg %.0f" % worst)

# common ring offset = max over edges; the corner constraint: the left/right
# finger rows extend beyond the die by (row_len - edge_len)/2 and must clear
# the top/bottom rows, which sit at the ring offset.
g = max(r[5] for r in res)
lens = []
for e, n, edge_len, row_len, dmax, worst in res:
    ps = sorted([p for p in pads if p["edge"] == e], key=lambda p: p["along"])
    centre = (H if e in ("left", "right") else W) / 2.0
    fingers = [centre + (k - (n - 1) / 2.0) * PITCH for k in range(n)]
    L = [math.hypot(abs(f - p["along"]), g + DEPTH[p["row"]] + SEAL)
         for f, p in zip(fingers, ps)]
    lens.append((e, min(L), max(L)))
print("ring offset %.0f um" % g, lens)
overhang = {e: (row_len - edge_len) / 2 for e, n, edge_len, row_len, dmax, w in res}
print("row overhang beyond the die edge:", overhang)

with open(os.path.join(FIG, "cob_feasibility.tex"), "w") as fh:
    for (e, n, edge_len, row_len, dmax, worst), (_, lmin, lmax) in zip(res, lens):
        fh.write(r"%s & %d & %.2f & %.2f & %.2f & %.2f & %.1f--%.1f \\" % (
            e.capitalize(), n, edge_len / 1000, row_len / 1000,
            max(0.0, (row_len - edge_len) / 2000), worst / 1000,
            lmin / 1000, lmax / 1000) + "\n")
    fh.write("%% common ring offset for 45 deg on every edge: %.2f mm\n" % (g / 1000))
print("done")
