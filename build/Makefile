.PHONY:	sim all clean
all:	sim

#
#  Icarus Verilog settings
##
# DIR	:= ../rtl
# IVC	?= iverilog
# INC	:= $(wildcard $(DIR)/*.vh)
# OPT	:= -g2005-sv -D__icarus -Wall -I../bench -I$(DIR)
# OPT	:= -g2005-sv -D__icarus -Wall -I$(DIR)

# SRC	:= $(wildcard $(DIR)/*.v)
# PHY	:= $(wildcard $(DIR)/arch/*.v) $(wildcard ../bench/arch/*.v)
# LIB	:= $(wildcard $(DIR)/misc/*.v) $(wildcard $(DIR)/fifo/*.v) $(PHY) ../bench/ddr3.v
# RTL	:= $(filter-out %_tb.v, $(SRC))

# BENCH	:= $(filter %_tb.v, $(SRC)) $(wildcard ../bench/*_tb.v)
# OUT	:= $(BENCH:%.v=%.out)

OUT	:= $(wildcard *_tb.out)
VCD	:= $(OUT:%.out=%.vcd)

# build:	$(OUT)

sim:	$(VCD)

clean:
	rm *.vcd *.out

%.vcd:	%.out
	./$<

# %.out:	%.v $(RTL) $(LIB)
# 	$(IVC) $(OPT) -o $@ -s $(*F) $^
