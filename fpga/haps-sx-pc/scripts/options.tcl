# Options for the nanosoc_eth_chiplet ProtoCompiler leg. Sourced after
# 'database load'. Options are NOT stored in the database — re-source after
# reopening the GUI.
#
# Technology comes from 'database load -autocreate -technology HAPS-100' (the
# only VU19P technology our licences reach; it auto-sets part XCVU19P /
# package FSVA3824). Mapping happens in Vivado, so these mainly keep the PC
# front-end reports honest — we export at c0 and never call pre_map/map.
option set design_flow synthesis
option set speed_grade -2-e
