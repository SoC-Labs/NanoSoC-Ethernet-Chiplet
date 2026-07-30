add_filler_gaps 0.2 -effort high

add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
    -prefix FILLER -fill_gap -merge true -check_drc true

add_filler_gaps 0.2 -effort high



check_filler > check_filler.log
add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
    -prefix FILLER -check_drc true -fix_drc

