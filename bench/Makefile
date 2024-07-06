.PHONY:	all build sim vpi
all:	sim

#
#  Icarus Verilog settings
##
IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall -I../rtl/ -I../rtl/usb/ -I../rtl/ddr3/

RTLDIR	:= ../rtl

USB_V	:= $(wildcard $(RTLDIR)/usb/*.v)
USB	:= $(filter-out %_tb.v, $(USB_V)) $(wildcard usb/*.v)

DDR3_V	:= $(wildcard $(RTLDIR)/ddr3/*.v)
DDR3	:= $(filter-out %_tb.v, $(DDR3_V))

MISC_V	:= $(wildcard $(RTLDIR)/misc/*.v $(RTLDIR)/axis/*.v)
MISC	:= $(filter-out %_tb.v, $(MISC_V))
FIFO	:= $(wildcard $(RTLDIR)/fifo/*.v)
ARCH	:= $(wildcard $(RTLDIR)/arch/*.v) arch/gw2a_prim_sim.v

SIMSRC	:= $(wildcard *.v)
SRC	:= $(filter-out %_tb.v, $(SIMSRC))

LIB	:= $(MISC) $(FIFO) $(ARCH) $(USB) $(DDR3) $(SRC)
TOP	?= $(wildcard *_tb.v)
OUT	?= $(TOP:%.v=../build/%.out)

sim:	build vpi

vpi:
	@make -C src all

build:	$(OUT)

../build/%.out: %.v $(LIB)
	$(IVC) $(OPT) -L. -mmonitor -o $@ -s $(*F) $^
