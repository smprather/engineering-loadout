# Functional smoke for the packaged openroad: read a real LEF + DEF and query
# the database through the Tcl API. `openroad -version` prints 26Q3 from a
# binary that cannot load Tcl at all, so it proves nothing -- this does.
set here [file dirname [info script]]
read_lef [file join $here gscl45nm.lef]
read_def [file join $here design.def]
set block [[[ord::get_db] getChip] getBlock]
puts "SMOKE_DESIGN=[$block getName]"
puts "SMOKE_INSTANCES=[llength [$block getInsts]]"
puts "SMOKE_NETS=[llength [$block getNets]]"
exit 0
