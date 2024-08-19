.PHONY:	all sim build clean

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

sim:	build
	make -C axis sim
	make -C fifo sim
	make -C misc sim

all:	build
	make -C axis all
	make -C fifo all
	make -C misc all

build:	$(OUT)
	make -C axis build
	make -C fifo build
	make -C misc build

../build/%.out: %.v $(RTL) $(LIB)
	$(IVC) $(OPT) -o $@ -s $(*F) $^
