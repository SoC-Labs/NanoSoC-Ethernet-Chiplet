#!/usr/bin/env python3
"""Does each core supply pad's PG pin actually reach the core ring?

This is the question two weeks of green reports could not answer, because
every check that could have answered it either gives up on PG nets or was
being asked of the same tool that was under suspicion. It is answered here
from GEOMETRY ALONE, dumped out of the routed database by padgeom.tcl:

    special wires  (rings, stripes, iowire, padring - every shape except the
                    ~350k M1 followpins, which hang OFF the mesh and cannot
                    form part of a pad-to-ring path)
    special vias   (bottom and top rectangles, in design coordinates)
    pad PG pins    (transformed out of cell coordinates by padgeom.tcl, which
                    self-checks the transform against the placed bounding box)

A union-find over those rectangles - same layer and overlapping/abutting are
one node, a via joins its own bottom and top rectangles - yields the connected
components of the actual drawn metal. Then: is each pad's PG pin in the same
component as the core ring?

WHAT THIS CANNOT SEE, stated up front. The path from the bond pad opening to
the pad cell's PG pin is INSIDE the vendor cell, and this site has only its
LEF abstract. So this proves "pad PG pin to core ring", which is the part the
project drew, and takes the cell-internal part on the vendor's abstract.

Usage: padconn.py <padgeom-dir> [--net VDD] [--eps 0.0]
"""

import sys
import os
from collections import defaultdict


class DSU:
    def __init__(self):
        self.p = {}

    def add(self, x):
        if x not in self.p:
            self.p[x] = x
        return x

    def find(self, x):
        p = self.p
        r = x
        while p[r] != r:
            r = p[r]
        while p[x] != r:
            p[x], x = r, p[x]
        return r

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.p[ra] = rb


def load_wires(path):
    """-> list of (layer, shape, x1, y1, x2, y2)"""
    out = []
    if not os.path.exists(path):
        return out
    with open(path) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            p = line.split()
            if len(p) != 6:
                continue
            try:
                out.append((p[0], p[1], float(p[2]), float(p[3]),
                            float(p[4]), float(p[5])))
            except ValueError:
                continue
    return out


def load_vias(path):
    """-> list of (botlayer, toplayer, cutlayer, botrect, toprect)"""
    out = []
    if not os.path.exists(path):
        return out
    with open(path) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            p = line.split()
            if len(p) != 11:
                continue
            try:
                b = tuple(float(v) for v in p[3:7])
                t = tuple(float(v) for v in p[7:11])
            except ValueError:
                continue
            out.append((p[0], p[1], p[2], b, t))
    return out


def load_padboxes(path):
    """-> list of (padname, basecell, orient, x1, y1, x2, y2)"""
    out = []
    if not os.path.exists(path):
        return out
    with open(path) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            p = line.split()
            if len(p) != 7:
                continue
            try:
                out.append((p[0], p[1], p[2], float(p[3]), float(p[4]),
                            float(p[5]), float(p[6])))
            except ValueError:
                continue
    return out


def load_pins(path):
    """-> dict padname -> list of (net, layer, x1, y1, x2, y2)"""
    out = defaultdict(list)
    if not os.path.exists(path):
        return out
    with open(path) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            p = line.split()
            if len(p) != 7:
                continue
            try:
                out[p[0]].append((p[1], p[2], float(p[3]), float(p[4]),
                                  float(p[5]), float(p[6])))
            except ValueError:
                continue
    return out


def build(rects, eps, bucket=20.0):
    """rects: list of (id, layer, x1,y1,x2,y2). Union same-layer overlaps."""
    dsu = DSU()
    for r in rects:
        dsu.add(r[0])
    buckets = defaultdict(list)
    for r in rects:
        _, lay, x1, y1, x2, y2 = r
        bx1, bx2 = int((x1 - eps) // bucket), int((x2 + eps) // bucket)
        by1, by2 = int((y1 - eps) // bucket), int((y2 + eps) // bucket)
        # A ring is 1200 um long; capping the spread keeps one huge shape from
        # exploding the index, at the cost of nothing: its ends still land in
        # their own buckets and the middle is covered by whatever crosses it.
        for bx in range(bx1, bx2 + 1):
            for by in range(by1, by2 + 1):
                buckets[(lay, bx, by)].append(r)
    for key, lst in buckets.items():
        n = len(lst)
        if n < 2:
            continue
        for i in range(n):
            _, _, ax1, ay1, ax2, ay2 = lst[i]
            ia = lst[i][0]
            for j in range(i + 1, n):
                _, _, bx1_, by1_, bx2_, by2_ = lst[j]
                if ax1 - eps <= bx2_ and bx1_ - eps <= ax2 and \
                   ay1 - eps <= by2_ and by1_ - eps <= ay2:
                    dsu.union(ia, lst[j][0])
    return dsu


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    d = sys.argv[1]
    nets = ["VDD", "VSS"]
    if "--net" in sys.argv:
        nets = [sys.argv[sys.argv.index("--net") + 1]]
    eps = 0.0
    if "--eps" in sys.argv:
        eps = float(sys.argv[sys.argv.index("--eps") + 1])

    pins = load_pins(os.path.join(d, "padpins.txt"))
    boxes = load_padboxes(os.path.join(d, "pads.txt"))
    if not pins:
        print("NOTE: padpins.txt carries no pin shapes. Falling back to the pad")
        print("      FOOTPRINT test: which drawn PG metal lies inside each pad's")
        print("      placed bounding box, and is that metal in the ring's")
        print("      component. That is a weaker claim than 'the pin rectangle")
        print("      is connected' and is labelled as such wherever it is used.")

    rc = 0
    for net in nets:
        wires = load_wires(os.path.join(d, "swires_%s.txt" % net))
        vias = load_vias(os.path.join(d, "svias_%s.txt" % net))
        print("=" * 76)
        print("NET %s : %d non-followpin special wires, %d special vias"
              % (net, len(wires), len(vias)))
        if not wires:
            print("  no wire geometry - skipping")
            continue

        rects = []
        meta = {}
        for i, (lay, shp, x1, y1, x2, y2) in enumerate(wires):
            rid = ("w", i)
            rects.append((rid, lay, x1, y1, x2, y2))
            meta[rid] = ("wire", shp, lay)
        via_pairs = []
        for i, (bl, tl, cl, b, t) in enumerate(vias):
            rb, rt = ("vb", i), ("vt", i)
            rects.append((rb, bl, b[0], b[1], b[2], b[3]))
            rects.append((rt, tl, t[0], t[1], t[2], t[3]))
            meta[rb] = ("via", cl, bl)
            meta[rt] = ("via", cl, tl)
            via_pairs.append((rb, rt))
        padrect = defaultdict(list)
        for pad, shapes in pins.items():
            for k, (pnet, lay, x1, y1, x2, y2) in enumerate(shapes):
                if pnet != net:
                    continue
                rid = ("p", pad, k)
                rects.append((rid, lay, x1, y1, x2, y2))
                meta[rid] = ("pin", pad, lay)
                padrect[pad].append(rid)

        dsu = build(rects, eps)
        for a, b in via_pairs:
            dsu.union(a, b)

        # Components, and which one is the core ring.
        comp = defaultdict(list)
        for r in rects:
            comp[dsu.find(r[0])].append(r[0])
        sizes = sorted(((len(v), k) for k, v in comp.items()), reverse=True)
        print("  components: %d ; largest 5 sizes: %s"
              % (len(comp), [s for s, _ in sizes[:5]]))

        ring_ids = [r[0] for r in rects
                    if meta[r[0]][0] == "wire" and meta[r[0]][1] == "ring"]
        if not ring_ids:
            print("  NO shape=ring wires on this net - falling back to the "
                  "largest component as 'the mesh'")
            mesh_roots = {sizes[0][1]}
        else:
            mesh_roots = {dsu.find(r) for r in ring_ids}
            print("  ring shapes: %d, in %d component(s)"
                  % (len(ring_ids), len(mesh_roots)))

        stripe_ids = [r[0] for r in rects
                      if meta[r[0]][0] == "wire" and meta[r[0]][1] == "stripe"]
        if stripe_ids:
            in_mesh = sum(1 for r in stripe_ids if dsu.find(r) in mesh_roots)
            print("  stripes in the ring component: %d of %d (%.1f%%)"
                  % (in_mesh, len(stripe_ids),
                     100.0 * in_mesh / len(stripe_ids)))

        # Per shape type: how much of it reaches the ring. A type that is
        # entirely absent from the ring's component is not automatically a
        # defect - 'padring' segments are joined through the IO cells' internal
        # buses by ABUTMENT, which is not drawn metal and cannot appear here -
        # but it must be seen and named rather than averaged away.
        bytype = defaultdict(lambda: [0, 0])
        for r in rects:
            kind, sub, lay = meta[r[0]]
            key = sub if kind == "wire" else ("via:%s" % sub)
            bytype[key][0] += 1
            if dsu.find(r[0]) in mesh_roots:
                bytype[key][1] += 1
        print("  shape type reach:")
        for k in sorted(bytype):
            tot, hit = bytype[k]
            print("    %-14s %8d shapes, %8d in the ring component (%.1f%%)"
                  % (k, tot, hit, 100.0 * hit / tot))

        # ---- PAD FOOTPRINT TEST -------------------------------------------
        # route_special -connect {pad_pin pad_ring} draws its wires FROM the
        # pad's PG pin, so those wires necessarily lie inside the pad's placed
        # bounding box. Asking which drawn PG metal is inside each pad, and
        # which component it belongs to, tests the pad-to-ring path without
        # needing the pin rectangle itself.
        cellnet = {"PVDD1DGZ_G": "VDD", "PVSS1DGZ_G": "VSS"}
        mine = [b for b in boxes if cellnet.get(b[1]) == net]
        if mine:
            print("  PAD FOOTPRINT TEST (drawn PG metal inside each pad's bbox)")
            print("    %-16s %-7s %8s %8s  %s"
                  % ("pad", "bbox", "shapes", "in mesh", "layers/shapes seen"))
            fbad = []
            for (pad, bc, orient, px1, py1, px2, py2) in sorted(mine):
                inside = []
                for r in rects:
                    rid, lay, x1, y1, x2, y2 = r
                    if meta[rid][0] == "pin":
                        continue
                    if x1 <= px2 and px1 <= x2 and y1 <= py2 and py1 <= y2:
                        inside.append(r)
                hit = [r for r in inside if dsu.find(r[0]) in mesh_roots]
                kinds = sorted({"%s/%s" % (r[1], meta[r[0]][1]) for r in hit})
                if not hit:
                    fbad.append(pad)
                print("    %-16s %-7s %8d %8d  %s"
                      % (pad, "%gx%g" % (px2 - px1, py2 - py1), len(inside),
                         len(hit), ",".join(kinds[:6]) if kinds else "-"))
            if fbad:
                print("    FOOTPRINT VERDICT %s: %d pad(s) contain NO metal that "
                      "reaches the ring: %s" % (net, len(fbad), ", ".join(fbad)))
            else:
                print("    FOOTPRINT VERDICT %s: every pad contains drawn PG metal "
                      "that is in the ring's component." % net)

        print("  %-34s %6s %8s  %s" % ("pad", "shapes", "in mesh", "verdict"))
        bad = []
        for pad in sorted(padrect):
            ids = padrect[pad]
            hit = [r for r in ids if dsu.find(r) in mesh_roots]
            ok = len(hit) > 0
            if not ok:
                bad.append(pad)
            print("  %-34s %6d %8d  %s"
                  % (pad, len(ids), len(hit), "CONNECTED" if ok else "*** NOT CONNECTED ***"))
        if not padrect:
            print("  (no pad pin shapes on this net)")
        elif bad:
            print("  VERDICT %s: %d of %d pads DO NOT reach the ring: %s"
                  % (net, len(bad), len(padrect), ", ".join(bad)))
            rc = 3
        else:
            print("  VERDICT %s: all %d pads reach the core ring."
                  % (net, len(padrect)))
    return rc


if __name__ == "__main__":
    sys.exit(main())
