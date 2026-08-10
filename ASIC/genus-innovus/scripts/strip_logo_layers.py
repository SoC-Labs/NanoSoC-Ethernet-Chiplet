# klayout -b -r scripts/strip_logo_layers.py -rd inp=<logo.gds> -rd out=<ap_only.gds>
#
# Keep AP (74/0) ONLY. Measured 2026-08-10 with the foundry deck: shipping the
# logo's 158/0 (LOGO) layer costs >= 2020 extra DRC results, two rulechecks
# saturated at the 1000 cap, because 158 is NOT a passive marker here --
#   LOGO.S.1  (deck :20450) min clearance LOGO -> OD/PO/M1..M9 = 10.0 um
#   LOGO.R.4  (deck :20498) OD/PO/M1x..M9x CUT LOGO is not allowed
# and at die centre the logo sits over live routing and an rf_01k register file.
# No placement on this die satisfies it: 158 needs 747.75 x 340.25 um clear of
# ALL OD/PO/M1-M9, the core is placed and routed, and the 205 um periphery is a
# 135 um IO ring plus a 70 um annulus - narrower than 340.25 um either way.
# 150/9 maps to DM9EXCL and is inert (zero DUM9 in this design); 150/10 is not
# mapped at all by the 9-metal deck. Neither prevented anything.
# AP-only measures +20 results, all cosmetic artwork rules, none capped.
inp = globals()["inp"]; out = globals()["out"]
KEEP = [(74, 0)]
ly = pya.Layout(); ly.read(inp)
kept, dropped = [], []
for li in list(ly.layer_indexes()):
    info = ly.get_info(li)
    if (info.layer, info.datatype) in KEEP:
        kept.append(str(info))
    else:
        dropped.append("%s (%d shapes)" % (info, sum(c.shapes(li).size() for c in ly.each_cell())))
        ly.delete_layer(li)
if not kept:
    raise RuntimeError("nothing kept - AP 74/0 absent from %s" % inp)
print("kept   : %s" % ", ".join(kept))
print("dropped: %s" % ", ".join(dropped))
ly.write(out)
print("wrote  : %s" % out)
