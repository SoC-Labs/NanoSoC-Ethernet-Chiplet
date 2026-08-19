#!/usr/bin/env python3
"""Parse the padring into an authoritative machine-readable pad table."""
import re, json, sys

PADS = "/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v"
IO   = "/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io"

def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)

src = strip_comments(open(PADS).read())

# --- top-level ports -------------------------------------------------------
hm = re.search(r"module\s+nanosoc_eth_chiplet_pads\s*\((.*?)\n\s*\)\s*;", src, re.S)
ports = {}
for d, rng, nm in re.findall(
        r"\b(input|output|inout)\b\s+(?:wire|reg|logic)?\s*(\[[^\]]*\])?\s*(\w+)", hm.group(1)):
    w = 1
    if rng:
        a, b = re.findall(r"(\d+)", rng)[:2]
        w = abs(int(a) - int(b)) + 1
    ports[nm] = {"dir": d, "width": w}

# --- pad instances ---------------------------------------------------------
SIG = ("PDDW04DGZ_G", "PDDW16DGZ_G", "PDUW08DGZ_G", "PDUW16DGZ_G")
pads = []
for cell, inst, body in re.findall(r"\b(P[A-Z0-9_]+)\s+(u\w+)\s*\((.*?)\)\s*;", src, re.S):
    if cell not in SIG:
        continue
    def get(p):
        m = re.search(r"\.%s\s*\(\s*(.*?)\s*\)" % p, body, re.S)
        return (m.group(1).strip() if m else "")
    C, I, OEN, REN, PAD = (get(x) for x in ("C", "I", "OEN", "REN", "PAD"))
    base = re.sub(r"\[.*", "", PAD)
    idx  = (lambda m: int(m.group(1)) if m else None)(re.search(r"\[(\d+)\]", PAD))

    oe_net, oe_inv = None, False
    if OEN not in ("tielo", "tiehi", ""):
        oe_inv = OEN.startswith("~")
        oe_net = OEN.lstrip("~").strip()

    # classify
    if I == "tielo" and oe_net and C:
        kind = "opendrain"          # I2C: data folded onto OEN, .I hard tie-low
    elif oe_net:
        kind = "bidir"
    elif OEN == "tiehi":
        kind = "input"
    elif OEN == "tielo":
        kind = "output"
    else:
        kind = "UNKNOWN"

    pads.append(dict(inst=inst, cell=cell, kind=kind, pad=PAD, port=base, idx=idx,
                     c_net=C or None, i_net=(I if I not in ("tielo","tiehi") else None),
                     oe_net=oe_net, oe_inv=oe_inv, ren=REN,
                     i_tied=(I if I in ("tielo","tiehi") else None)))

# --- physical ring order (from the .io) ------------------------------------
iof = open(IO).read()
ring = []
for side in ("top", "right", "bottom", "left"):
    m = re.search(r"\(%s\s*\n(.*?)\n\s*\)" % side, iof, re.S)
    names = re.findall(r'inst\s+name="([^"]+)"', m.group(1))
    # chain runs clockwise: top L->R, right T->B, bottom R->L, left B->T
    if side in ("right", "bottom"):
        names = list(reversed(names))
    ring += [(side, n) for n in names]
order = {n: i for i, (s, n) in enumerate(ring)}
for p in pads:
    p["ring_index"] = order.get(p["inst"], 10_000)
    p["side"] = next((s for s, n in ring if n == p["inst"]), "?")
pads.sort(key=lambda p: p["ring_index"])

out = dict(ports=ports, pads=pads)
json.dump(out, open("pad_table.json", "w"), indent=1)

# --- report ----------------------------------------------------------------
from collections import Counter
print("signal pads:", len(pads))
print("by kind :", dict(Counter(p["kind"] for p in pads)))
print("by cell :", dict(Counter(p["cell"] for p in pads)))
print("by side :", dict(Counter(p["side"] for p in pads)))
print("unplaced (not in .io):", [p["inst"] for p in pads if p["ring_index"] == 10_000] or "none")
print("UNKNOWN kind:", [p["inst"] for p in pads if p["kind"] == "UNKNOWN"] or "none")
# BSR cell budget
n_in  = sum(1 for p in pads if p["kind"] == "input")
n_out = sum(1 for p in pads if p["kind"] == "output")
n_bi  = sum(1 for p in pads if p["kind"] == "bidir")
n_od  = sum(1 for p in pads if p["kind"] == "opendrain")
print(f"\ninput={n_in} output={n_out} bidir={n_bi} opendrain={n_od}")
print(f"BSR cells (in + out + bidir*3 + od*2) = {n_in + n_out + n_bi*3 + n_od*2}")
