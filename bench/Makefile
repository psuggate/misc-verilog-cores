.PHONY:	all build sim
all:	sim

#
#  Icarus Verilog settings
##
IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall -I../rtl/

RTLDIR	:= ../rtl
MISC_V	:= $(wildcard $(RTLDIR)/misc/*.v)
MISC	:= $(filter-out %_tb.v, $(MISC_V))
DDR3_V	:= $(wildcard $(RTLDIR)/*.v)
DDR3	:= $(filter-out %_tb.v, $(DDR3_V))
FIFO	:= $(wildcard $(RTLDIR)/fifo/*.v)
ARCH	:= $(wildcard $(RTLDIR)/arch/*.v) arch/gw2a_prim_sim.v
SIMSRC	:= $(wildcard *.v)
SRC	:= $(filter-out %_tb.v, $(SIMSRC))

LIB	:= $(MISC) $(FIFO) $(DDR3) $(ARCH) $(SRC)
TOP	?= $(wildcard *_tb.v)
OUT	?= $(TOP:%.v=../build/%.out)

sim:	build

build:	$(OUT)

../build/%.out: %.v $(LIB)
	$(IVC) $(OPT) -o $@ -s $(*F) $^
