### Delay Calculation 
write_sdf design.sdf -ideal_clock_network 
set_db add_tieoffs_max_fanout 10
add_tieoffs -lib_cell {TIEL TIEH} -prefix LTIE
