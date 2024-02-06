.PHONY:	all sim build clean
all:	build
sim:	build

#
#  Icarus Verilog settings
##
IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall

DEP	:= $(wildcard ../misc/*.v) $(wildcard ../axis/*.v)
SRC	:= $(wildcard *.v) $(filter-out %_tb.v, $(DEP))
RTL	:= $(filter-out %_tb.v, $(SRC))
BENCH	:= $(filter %_tb.v, $(SRC))
OUT	:= $(BENCH:%.v=../../build/%.out)

build:	$(OUT)

../../build/%.out: %.v $(RTL)
	$(IVC) $(OPT) -o $@ -s $(*F) $^
