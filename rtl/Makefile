.PHONY:	all sim build clean
all:	build
sim:	build

#
#  Icarus Verilog settings
##
IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall -I../bench

SRC	:= $(wildcard *.v)
INC	:= $(wildcard *.vh)
PHY	:= $(wildcard arch/*.v) $(wildcard ../bench/arch/*.v)
LIB	:= $(wildcard misc/*.v) $(wildcard fifo/*.v) $(PHY) ../bench/ddr3.v
RTL	:= $(filter-out %_tb.v, $(SRC))
BENCH	:= $(filter %_tb.v, $(SRC))
OUT	:= $(BENCH:%.v=../build/%.out)

build:	$(OUT)
	make -C axis build
	make -C fifo build
	make -C misc build

../build/%.out: %.v $(RTL) $(LIB)
	$(IVC) $(OPT) -o $@ -s $(*F) $^
