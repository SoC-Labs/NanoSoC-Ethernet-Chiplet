## Snapshot the POST-PLACE database. See the note in route_setup.tcl: every
## stage writes the same DB name, so without this only the final post-route
## state survives and any CTS experiment costs a full re-run from placement.
## 3_pnr_clock.tcl sources this file right after its `read_db`, so the design
## here is exactly the post-place state.
##
##   resume from here:  cd work && innovus -stylus
##                      source ../scripts/config.tcl ; read_db ${block_name}_placed
write_db ${block_name}_placed

### Buffer Cells
## Left commented DELIBERATELY, for now. The attributes are real
## (innovus/etc/rdaDesign.tcl) and the patterns do match this library —
## tcbn65lp has CKBD0..CKBD24 and CKND0..CKND24. Enabling them constrains
## CCOpt's clock-cell choice, which changes the clock tree and therefore the
## hold profile; that is a physical change to evaluate on its own, not to
## bundle with a hold-repair experiment. For reference, this run's clock tree
## used 41,228 CKBD0, 5,648 CKND0 and 3,126 CKBD1 — plus 3,290 BUFFD1, a
## general-purpose buffer that a cts_buffer_cells list would have excluded.
#set_db cts_buffer_cells {CKB*}
### Inverter Cells
#set_db cts_inverter_cells {CKN*}

set_db cts_delay_cells {DEL*}