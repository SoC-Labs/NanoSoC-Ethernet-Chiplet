# ---------------------------------------------------------------------------
# clip_gds.rb --- cut a carryable window out of the full stream.
#
#   klayout -b -r clip_gds.rb \
#           -rd in=<big.gds> -rd out=<small.gds> -rd box=x1,y1,x2,y2 [-rd flat=1]
#
# The full chip stream is ~300 MB. A 150 um window is a fraction of that, which
# is what makes "look at this on the train" work at all.
#
# THE CLIP STAYS HIERARCHICAL, FOR SIZE
# -------------------------------------
# Flattening costs file size and buys nothing. Measured on this design:
#
#                          50 um window     150 um window
#   hierarchical              0.6 MB            5.6 MB
#   flattened (-rd flat=1)    2.3 MB           59.0 MB
#
# DRC runtime on the two 50 um files was IDENTICAL -- 58 s each, 4 threads, all
# layers, same 1039 markers. So this is a size decision, not a speed one: a
# clipped window has little repetition left for the hierarchical engine to
# exploit either way. `-rd flat=1` is kept for handing a single cell to
# something that cannot read hierarchy.
#
# WHAT YOU LOSE, and it matters when you read the DRC result:
# a clip CUTS wires. A cut wire has a raw end, so it is narrow, small in area,
# and any via under a metal that used to continue past the window now has no
# enclosure. The deck's clip guard drops markers within 2 um of the boundary
# for exactly this reason -- but that guard only applies when the DECK does the
# clipping (-rd clip=...). If you clip here and then run the deck on the result,
# the deck sees a whole layout and guards nothing.
#
# So: use `-rd clip=` on the deck when you have the full stream. Use this
# script only to MOVE a window to a machine that does not have it.
# ---------------------------------------------------------------------------

gds = $in  || raise("clip_gds: -rd in=<gds> required")
out = $out || raise("clip_gds: -rd out=<gds> required")
box = $box || raise("clip_gds: -rd box=x1,y1,x2,y2 (um) required")

c = box.split(",").collect { |v| v.to_f }
c.size == 4 || raise("clip_gds: -rd box needs four comma-separated um values")

t0 = Time.now
ly = RBA::Layout::new
ly.read(gds)
ly.top_cells.size == 1 ||
  raise("clip_gds: expected one top cell, found #{ly.top_cells.size}: " +
        ly.top_cells.collect { |x| x.name }.inspect)
top = ly.top_cell
puts "read   : #{gds} (#{ly.cells} cells, %.1f s)" % (Time.now - t0)

dbox = RBA::DBox::new(c[0], c[1], c[2], c[3])
dbox.overlaps?(top.dbbox) ||
  raise("clip_gds: box #{dbox} does not overlap the design #{top.dbbox}")

clipped = ly.clip(top.cell_index, RBA::Box::from_dbox(dbox * (1.0 / ly.dbu)))
if $flat == "1"
  ly.flatten(clipped, -1, true)
  puts "flatten: ON -- do not run DRC on this, see the header"
end

# Write ONLY the clipped cell's tree. Without add_cell, `write` streams the
# whole original hierarchy out alongside it and the output is as big as the
# input.
opt = RBA::SaveLayoutOptions::new
opt.add_cell(clipped)
ly.write(out, opt)

puts "clip   : #{dbox.to_s} um"
puts "write  : #{out} (%.1f MB, %.1f s total)" %
     [File.size(out) / 1048576.0, Time.now - t0]
puts
puts "NOTE: markers within a couple of um of the window edge are artefacts of"
puts "      the cut, not defects. See the header of this script."
