# klayout -b -r scripts/strip_logo_jack.py -rd inp=<logo.gds> -rd out=<text.gds> [-rd xcut=0.0]
#
# Drop the ethernet-jack artwork, keep the text. The full logo is 727.75um wide
# and LOGO.S.1 needs the footprint + a 10um halo clear of ALL OD/PO/M1-M9 -
# which nothing on a placed-and-routed die can offer. The text alone is ~360um
# wide, which is a keep-out a floorplan can plausibly host.
#
# The split is unambiguous, measured on the AP layer: 23 text shapes all lie at
# x < -3.6, the 5 jack/cable shapes all at x > 43.6. Cutting at x=0 separates
# them with 40um to spare. Applied to EVERY layer so 74/0, 158/0 and the 150/*
# markers stay consistent with each other - a LOGO marker that still covered the
# jack would keep asserting a keep-out over geometry that is no longer there.
inp = globals()["inp"]; out = globals()["out"]
xcut = float(globals().get("xcut", 0.0))
ly = pya.Layout(); ly.read(inp); dbu = ly.dbu
cut = int(round(xcut / dbu))
tot = kept = 0
for c in ly.each_cell():
    for li in ly.layer_indexes():
        rm = []
        for s in c.shapes(li).each():
            tot += 1
            if s.bbox().left >= cut: rm.append(s)
            else: kept += 1
        for s in rm: c.shapes(li).erase(s)
print("shapes: %d -> %d (dropped %d at x >= %g)" % (tot, kept, tot - kept, xcut))
for li in ly.layer_indexes():
    info = ly.get_info(li); n = sum(c.shapes(li).size() for c in ly.each_cell())
    if n: print("   %s : %d" % (info, n))
b = ly.cell("Logo").bbox()
print("new bbox: %.2f x %.2f um  (x %.2f .. %.2f)"
      % (b.width()*dbu, b.height()*dbu, b.left*dbu, b.right*dbu))
ly.write(out)
print("wrote: %s" % out)
