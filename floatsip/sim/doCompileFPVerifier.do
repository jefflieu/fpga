set SIMLIBPATH {D:/intelFPGA_lite/18.0/quartus/eda/sim_lib/}
puts $SIMLIBPATH
vlog $SIMLIBPATH/220model.v
vlog $SIMLIBPATH/altera_mf.v
vlog $SIMLIBPATH/altera_primitives.v
vlog mFPVerifier.v
vlog mFPMultVerifier.v
vlog mFPAddSubVerifier.v
vlog mFloatLoader.sv
vlog mFloatCal.sv

vlog ../src/mFPMult.v
vlog ../src/mFPAddSub.v
