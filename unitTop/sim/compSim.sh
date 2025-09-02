#!/bin/bash

WORK_DIR=work
WAVE_FILE=result.ghw
GTKPROJ_FILE=result.gtkw
VCD_FILE=result.vcd
SAIF_FILE=result.saif

# create work dir if it does not exist
mkdir -p $WORK_DIR

# importing source files
ghdl -i --workdir=$WORK_DIR ../../unitAdder/src/fp_adder.vhd
ghdl -i --workdir=$WORK_DIR ../../unitMultiplier/src/fp_mul.vhd
ghdl -i --workdir=$WORK_DIR ../src/Top.vhd

ghdl -i --workdir=$WORK_DIR ./tb_top.vhd

# building simulation files
ghdl -m --workdir=$WORK_DIR tb

# running the simulation
ghdl -r --workdir="$WORK_DIR" tb --wave="$WORK_DIR/$WAVE_FILE" --vcd="$WORK_DIR/$VCD_FILE" --stop-time=1ms

python3 ./vcd_automation.py -i "$WORK_DIR/$VCD_FILE" --vdd 1.2 --ceff 2e-15

#python3 ./vcd2saif.py "$WORK_DIR/$VCD_FILE" "$WORK_DIR/${VCD_FILE%.vcd}.saif"

# running the simulation
#ghdl -r --workdir=$WORK_DIR tb_multi_bank_memory --wave=$WORK_DIR/result.vcd --stop-time=1ms

# open gtkwave with project with new waveform if project exists, if not then just open the waveform in new project
if [ -f $WORK_DIR/$GTKPROJ_FILE ]; then
   gtkwave $WORK_DIR/$GTKPROJ_FILE &
else
   gtkwave $WORK_DIR/$WAVE_FILE &
fi