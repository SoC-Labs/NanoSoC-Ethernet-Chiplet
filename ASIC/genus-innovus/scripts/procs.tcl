# Helper: expand ${VAR} and $(VAR) references to environment variable values.
# The hand-maintained project flists use ${VAR}; the nanosoc_gen-emitted flists
# (build_soc/flist/*.flist, which the ASIC flist -f-includes) use make-style
# $(VAR). Support both so the generator's native filelists can be -f'd directly
# (keeps the interconnect leaf list auto-in-sync instead of hand-inlined).
proc expand_env {str} {
    while {[regexp {\$\{(\w+)\}} $str -> varname]} {
        if {[info exists ::env($varname)]} {
            set pattern "\\$\\{${varname}\\}"
            regsub $pattern $str $::env($varname) str
        } else {
            error "Environment variable $varname is not set"
        }
    }
    while {[regexp {\$\((\w+)\)} $str -> varname]} {
        if {[info exists ::env($varname)]} {
            set pattern "\\$\\(${varname}\\)"
            regsub $pattern $str $::env($varname) str
        } else {
            error "Environment variable $varname is not set"
        }
    }
    return $str
}
