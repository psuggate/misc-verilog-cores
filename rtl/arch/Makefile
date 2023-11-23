.PHONY:	all sim clean
all:	build
sim:	build

#
#  Icarus Verilog settings
##
IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall -I../../bench

SRC	:= $(wildcard *.v)
LIB	:= $(wildcard ../../bench/arch/*.v)
RTL	:= $(filter-out %_tb.v, $(SRC))
BENCH	:= $(filter %_tb.v, $(SRC))
OUT	:= $(BENCH:%.v=../../build/%.out)

build:	$(OUT)

../../build/%.out: %.v $(RTL) $(LIB)
	$(IVC) $(OPT) -o $@ -s $(*F) $^
