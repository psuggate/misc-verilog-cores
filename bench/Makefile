.PHONY:	all build clean sim
all:	sim

#
#  Icarus Verilog settings
##
IVC	?= iverilog
OPT	:= -g2005-sv -D__icarus -Wall -I../rtl/axis/ -I../rtl/usb/ -I../rtl/ddr3/

RTLDIR	:= ../rtl

USB_V	:= $(wildcard $(RTLDIR)/usb/*.v)
USB	:= $(filter-out %_tb.v, $(USB_V)) $(wildcard usb/*.v)

UART	:= $(wildcard $(RTLDIR)/uart/*.v)

DDR3_V	:= $(wildcard $(RTLDIR)/ddr3/*.v)
DDR3	:= $(filter-out %_tb.v, $(DDR3_V))

MISC_V	:= $(wildcard $(RTLDIR)/misc/*.v $(RTLDIR)/axis/*.v)
MISC	:= $(filter-out %_tb.v, $(MISC_V))
FIFO	:= $(wildcard $(RTLDIR)/fifo/*.v)
ARCH	:= $(wildcard $(RTLDIR)/arch/*.v) arch/gw2a_prim_sim.v

SYNTH	:= ../synth/gowin-ddr3-test
EXTRA_V	:= $(wildcard $(SYNTH)/*.v)
EXTRA	:= $(filter-out %_tb.v, $(EXTRA_V))

SIMSRC	:= $(wildcard *.v)
SRC	:= $(filter-out %_tb.v, $(SIMSRC))

LIB	:= $(MISC) $(FIFO) $(ARCH) $(USB) $(DDR3) $(UART) $(EXTRA) $(SRC)
TOP	?= $(wildcard *_tb.v)
OUT	?= $(TOP:%.v=../build/%.out)

USB_T	:= $(wildcard *usb*_tb.v)
USB_O	?= $(USB_T:%.v=../build/%.out)

sim:	build

usbsim:	$(USB_O)

build:	$(OUT)

clean:
	@make -C spi clean

../build/%.out: %.v $(LIB)
	$(IVC) $(OPT) -L../vpi -mulpisim -o $@ -s $(*F) $^
