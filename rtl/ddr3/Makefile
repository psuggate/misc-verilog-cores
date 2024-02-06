.PHONY:	all sim build clean
all:	build
sim:	build

#
#  Icarus Verilog settings
##
BUILD	:= ../../build
BENCH	:= ../../bench
ARCH	:= ../arch

IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall -I$(BENCH)

INC	:= $(wildcard *.vh)

AXIS	:= $(wildcard ../axis/*.v)
FIFO	:= $(wildcard ../fifo/*.v)
MISC	:= $(wildcard ../misc/*.v)
PHY	:= $(wildcard $(ARCH)/*.v) $(wildcard $(BENCH)/arch/*.v)
LIB	:= $(AXIS) $(FIFO) $(MISC) $(PHY) $(BENCH)/ddr3.v

SRC	:= $(wildcard *.v)
RTL	:= $(filter-out %_tb.v, $(SRC))
TOP	:= $(filter %_tb.v, $(SRC))
OUT	:= $(TOP:%.v=$(BUILD)/%.out)

build:	$(OUT)

../../build/%.out: %.v $(RTL) $(LIB)
	$(IVC) $(OPT) -o $@ -s $(*F) $^
